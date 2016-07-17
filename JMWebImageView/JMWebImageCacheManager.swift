//
//  WebImageCacheManager.swift
//  JMWebImageView
//
//  Copyright (c) 2016 J.M. Schaeffer
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.

import UIKit
import ImageIO


private final class WebImageMemoryCache: NSObject {
    static let sharedManager = WebImageMemoryCache()
    
    let images: NSCache = NSCache() // [String: UIImage]
    var expirationDates: [String: NSDate] = [:]
    
    
    func cacheImage(image: UIImage, url: NSURL, size: CGFloat, cacheDuration: NSTimeInterval) {
        let key = keyFromUrl(url, size: size)
        
        images[key] = image
        if cacheDuration < .infinity {
            expirationDates[key] = NSDate().dateByAddingTimeInterval(cacheDuration)
        }
    }
    
    func imageForURL(url: NSURL, size: CGFloat = .max) -> UIImage? {
        let key = keyFromUrl(url, size: size)
        
        if let expirationDate = expirationDates[key] where expirationDate.earlierDate(NSDate()) == expirationDate {
            expirationDates[key] = nil
            images[key] = nil
            
            return nil
        }
        
        return images[keyFromUrl(url, size: size)] as? UIImage
    }
    
    func keyFromUrl(url: NSURL, size: CGFloat) -> String {
        return "\(url.absoluteString):\(size)"
    }
    
    func clear() {
        images.removeAllObjects()
        expirationDates.removeAll()
    }
}


private final class WebImageDiskCache: NSObject {
    static let sharedManager = WebImageDiskCache()
    
    var expirationDates: [String: NSDate] = [:]
    let fileManager = NSFileManager()
    
    
    override init() {
        super.init()
        
        if let url = expirationDatesFileURL {
            expirationDates = NSDictionary(contentsOfURL: url) as? [String: NSDate] ?? [:]
        }
    }
    
    var rootURL: NSURL? {
        do {
            let cacheURL = try fileManager.URLForDirectory(.CachesDirectory, inDomain: .UserDomainMask, appropriateForURL: nil, create: false)
            let rootURL = cacheURL.URLByAppendingPathComponent("YJWebImages", isDirectory: true)
            
            var error: NSError?
            if rootURL.checkResourceIsReachableAndReturnError(&error) {
                return rootURL
            } else {
                if let error = error where error.code != NSFileReadNoSuchFileError {
                    print("WARNING: 🖼 Unable to check if file is reachable: \(error)")
                }
                
                do {
                    try fileManager.createDirectoryAtURL(rootURL, withIntermediateDirectories: true, attributes: nil)
                    
                    return rootURL
                } catch let error as NSError {
                    print("ERROR: 🖼 Unable to create images cache directory URL: \(error)")
                }
            }
        } catch let error as NSError {
            print("ERROR: 🖼 Unable to retrieve caches directory URL: \(error)")
        }
        
        return nil
    }
    
    var expirationDatesFileURL: NSURL? {
        return rootURL?.URLByAppendingPathComponent("METADATA")
    }
    
    func cacheURLForImageURL(url: NSURL) -> NSURL? {
        return rootURL?.URLByAppendingPathComponent(url.absoluteString.stringByReplacingOccurrencesOfString("/", withString: "$"))
    }
    
    // Executed on the main thread to be able to be called from the NSURLSession data task delegate
    func cacheImageFromLocation(location: NSURL, url: NSURL, cacheDuration: NSTimeInterval) -> NSURL? {
        guard let destinationURL = cacheURLForImageURL(url) else {
            return nil
        }
        
        do {
            var error: NSError?
            if destinationURL.checkResourceIsReachableAndReturnError(&error) {
                do {
                    try fileManager.replaceItemAtURL(destinationURL, withItemAtURL: location, backupItemName: nil, options: .UsingNewMetadataOnly, resultingItemURL: nil)
                    
                    saveCacheDuration(cacheDuration, for: destinationURL)
                } catch let error as NSError {
                    print("ERROR: 🖼 Unable to replace image: \(error)")
                }
            } else {
                if let error = error where error.code != NSFileReadNoSuchFileError {
                    print("WARNING: 🖼 Unable to check if file is reachable: \(error)")
                }
                
                do {
                    try fileManager.moveItemAtURL(location, toURL: destinationURL)
                    
                    saveCacheDuration(cacheDuration, for: destinationURL)
                } catch let error as NSError {
                    print("ERROR: 🖼 Unable to move image file: \(error)")
                }
            }
        }
        
        return destinationURL
    }
    
    func saveCacheDuration(cacheDuration: NSTimeInterval, for cacheURL: NSURL) {
        guard cacheDuration < .infinity else {
            return
        }
        
        expirationDates[cacheURL.absoluteString] = NSDate().dateByAddingTimeInterval(cacheDuration)
        
        guard let expirationDatesFileURL = expirationDatesFileURL else {
            return
        }
        
        if !(expirationDates as NSDictionary).writeToURL(expirationDatesFileURL, atomically: true) {
            print("ERROR: 🖼 Unable to save expiration dates file!")
        }
    }
    
    func imageForURL(url: NSURL, size: CGFloat = .max, completion: (error: NSError?, image: UIImage?) -> Void) {
        // ImageIO likely decodes the images on another thread, so the following operations can be performed on the main thread
        var error: NSError?
        var image: UIImage?
        
        defer {
            completion(error: error, image: image)
        }
        
        guard let cacheURL = self.cacheURLForImageURL(url) else {
            return
        }
        
        if let expirationDatesFileURL = expirationDatesFileURL,
            expirationDate = expirationDates[cacheURL.absoluteString] where expirationDate.earlierDate(NSDate()) == expirationDate {
            expirationDates[cacheURL.absoluteString] = nil
            
            do {
                try fileManager.removeItemAtURL(expirationDatesFileURL)
            } catch let error as NSError {
                print("ERROR: 🖼 Unable to remove expired image file: \(error)")
            }
            
            return
        }
        
        if let source = CGImageSourceCreateWithURL(cacheURL, nil),
            dictionary = CGImageSourceCopyPropertiesAtIndex(source, 0, nil),
            properties = dictionary as NSDictionary as? [NSString: NSObject],
            width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
            height = properties[kCGImagePropertyPixelHeight] as? CGFloat {
            // Since the file may be deleted by the system, should we force the decoding to be immmediate?
            if size < width || size < height {
                let options: [NSString: NSObject] = [
                    kCGImageSourceThumbnailMaxPixelSize: size,
                    kCGImageSourceCreateThumbnailFromImageIfAbsent: true
                ]
                if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) {
                    image = UIImage(CGImage: cgImage)
                }
            } else {
                if let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                    image = UIImage(CGImage: cgImage)
                }
            }
        }
    }
    
    func clear() {
        if let rootURL = rootURL {
            do {
                try fileManager.removeItemAtURL(rootURL)
            } catch let error as NSError {
                print("ERROR: 🖼 rootURL remove failed: \(error)")
            }
        }
    }
}


final class WebImageCacheManager: NSObject {
    class func cacheImageInMemory(image: UIImage, url: NSURL, size: CGFloat, cacheDuration: NSTimeInterval) {
        WebImageMemoryCache.sharedManager.cacheImage(image, url: url, size: size, cacheDuration: cacheDuration)
    }
    
    class func cacheImageOnDiskFromLocation(imageLocation: NSURL, url: NSURL, cacheDuration: NSTimeInterval) -> NSURL? {
        return WebImageDiskCache.sharedManager.cacheImageFromLocation(imageLocation, url: url, cacheDuration: cacheDuration)
    }
    
    class func imageForURL(url: NSURL, size: CGFloat = .max, cacheDuration: NSTimeInterval, completion: (error: NSError?, image: UIImage?) -> Void) {
        if let image = WebImageMemoryCache.sharedManager.imageForURL(url, size: size) {
            completion(error: nil, image: image)
        } else {
            WebImageDiskCache.sharedManager.imageForURL(url, size: size) { error, image in
                if let image = image {
                    WebImageMemoryCache.sharedManager.cacheImage(image, url: url, size: size, cacheDuration: cacheDuration)
                }
                
                completion(error: error, image: image)
            }
        }
    }
    
    class func clear() {
        WebImageMemoryCache.sharedManager.clear()
        WebImageDiskCache.sharedManager.clear()
    }
}

extension NSCache {
    subscript(key: AnyObject) -> AnyObject? {
        get {
            return objectForKey(key)
        }
        set {
            if let newValue = newValue {
                setObject(newValue, forKey: key)
            } else {
                removeObjectForKey(key)
            }
        }
    }
}
