//
//  WebImageDownloaderManager.swift
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


private final class WebImageDownloader {
    let url: NSURL
    let useCache: Bool
    let cacheDuration: NSTimeInterval
    let monitorProgress: Bool
    
    // Key: desired max pixel size (the max of the desired width and desired height)
    var completionsBySize: [CGFloat: [String: (error: NSError?, image: UIImage?, progress: Float?) -> Void]] = [:]
    var maxSize: CGFloat = 0.0
    var images: [CGFloat: UIImage] = [:]
    
    weak var task: NSURLSessionDownloadTask?
    
    
    init(url: NSURL, useCache: Bool, cacheDuration: NSTimeInterval, monitorProgress: Bool) {
        self.url = url
        self.useCache = useCache
        self.cacheDuration = cacheDuration
        self.monitorProgress = monitorProgress
    }
    
    deinit {
        task?.cancel()
    }
    
    func register(completion: (error: NSError?, image: UIImage?, progress: Float?) -> Void, key: String, size: CGFloat? = nil) {
        let size = size ?? .max
        
        if completionsBySize[size] != nil {
            // completions is passed by copy so we need to use its reference
            completionsBySize[size]?[key] = completion
        } else {
            completionsBySize[size] = [key: completion]
        }
    }
    
    func unregister(key: String) {
        for (size, completions) in completionsBySize.reverse() {
            for currentKey in completions.keys.reverse() {
                if key == currentKey {
                    // completions is passed by copy so we need to directly use its reference
                    completionsBySize[size]?[key] = nil
                    
                    if completionsBySize[size]?.isEmpty == true {
                        completionsBySize[size] = nil
                    }
                }
            }
        }
        
        if completionsBySize.isEmpty {
            task?.cancel()
        }
    }
    
    func download(session: NSURLSession) {
        // We should think of a way to display the status bar network activity indicator
        // UIApplication.sharedApplication().networkActivityIndicatorVisible = true
        
        let request = NSURLRequest(URL: url)
        
        let task = session.downloadTaskWithRequest(request)
        self.task = task
        task.resume()
    }
    
    func didCompleteWithError(error: NSError?) {
        dispatch_async(dispatch_get_main_queue()) {
            for (size, completions) in self.completionsBySize {
                let image = self.images[min(self.maxSize, size)]
                
                completions.forEach({ $0.1(error: error, image: image, progress: nil) })
            }
            
            // UIApplication.sharedApplication().networkActivityIndicatorVisible = false
        }
    }
    
    func didFinishDownloadingToURL(location: NSURL) {
        // CGImageSourceCreateWithURL cannot be used directly on 'location' because the file is ephemeral
        var source: CGImageSourceRef?
        if useCache {
            if let url = WebImageCacheManager.cacheImageOnDiskFromLocation(location, url: url, cacheDuration: cacheDuration) {
                source = CGImageSourceCreateWithURL(url, nil) // However after moving the file we can use its new URL
            }
        } else if let data = NSData(contentsOfURL: location) {
            source = CGImageSourceCreateWithData(data, nil)
        }
        
        if let source = source,
            dictionary = CGImageSourceCopyPropertiesAtIndex(source, 0, nil),
            properties = dictionary as NSDictionary as? [NSString: NSObject],
            width = properties[kCGImagePropertyPixelWidth as String] as? CGFloat,
            height = properties[kCGImagePropertyPixelHeight as String] as? CGFloat {
            maxSize = max(width, height)
            
            for size in completionsBySize.keys {
                let actualSize = min(maxSize, size)
                guard images[actualSize] == nil else {
                    break
                }
                
                var image: UIImage?
                
                if size < maxSize {
                    let options: [NSString: NSObject] = [
                        kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
                        kCGImageSourceThumbnailMaxPixelSize: size
                    ]
                    if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) {
                        image = UIImage(CGImage: cgImage)
                    }
                } else {
                    if let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                        image = UIImage(CGImage: cgImage)
                    }
                }
                
                images[actualSize] = image
                
                if let image = image where useCache {
                    WebImageCacheManager.cacheImageInMemory(image, url: url, size: actualSize, cacheDuration: cacheDuration)
                }
            }
        } else {
            print("INFO: 🖼 Couldn't load the image from the file from: \(url)")
        }
    }
    
    func didWriteData(bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if monitorProgress {
            if totalBytesExpectedToWrite != NSURLSessionTransferSizeUnknown {
                let progress = Float(totalBytesWritten) / Float(totalBytesExpectedToWrite)
                
                dispatch_async(dispatch_get_main_queue()) {
                    for completions in self.completionsBySize.values {
                        completions.forEach({ $0.1(error: nil, image: nil, progress: progress) })
                    }
                }
            }
        }
    }
}


final class WebImageDownloaderManager: NSObject {
    static let sharedManager = WebImageDownloaderManager()
    
    private lazy var cacheSession: NSURLSession = {
        return NSURLSession(
            configuration: NSURLSessionConfiguration.defaultSessionConfiguration(),
            delegate: self,
            delegateQueue: nil)
    }()
    private lazy var noCacheSession: NSURLSession = {
        let noCacheConfiguration = NSURLSessionConfiguration.defaultSessionConfiguration()
        noCacheConfiguration.requestCachePolicy = NSURLRequestCachePolicy.ReloadIgnoringLocalCacheData
        
        return NSURLSession(
            configuration: noCacheConfiguration,
            delegate: self,
            delegateQueue: nil)
    }()
    
    private var imageDownloaders: [String: WebImageDownloader] = [:] // Key: URL absolute string
    
    
    func request(url: NSURL, key: String, size: CGFloat? = nil, useCache: Bool = true, cacheDuration: NSTimeInterval = 86400 /* 1 day */, useProtocolCachePolicy: Bool = true, monitorProgress: Bool = false, completion: (error: NSError?, image: UIImage?, progress: Float?) -> Void) {
        if let imageDownloader = imageDownloaders[url.absoluteString] {
            imageDownloader.register(completion, key: key, size: size)
        } else {
            let imageDownloader = WebImageDownloader(url: url, useCache: useCache, cacheDuration: cacheDuration, monitorProgress: monitorProgress)
            imageDownloader.register(completion, key: key, size: size)
            
            imageDownloaders[url.absoluteString] = imageDownloader
            
            imageDownloader.download(useProtocolCachePolicy ? cacheSession : noCacheSession)
        }
    }
    
    func cancel(url: NSURL, key: String) {
        if let imageDownloader = imageDownloaders[url.absoluteString] {
            imageDownloader.unregister(key)
            
            if imageDownloader.completionsBySize.isEmpty {
                imageDownloaders[url.absoluteString] = nil
            }
        }
    }
    
    func isDownloading(url: NSURL) -> Bool {
        return imageDownloaders[url.absoluteString] != nil
    }
}

extension WebImageDownloaderManager: NSURLSessionTaskDelegate {
    func URLSession(session: NSURLSession, task: NSURLSessionTask, didCompleteWithError error: NSError?) {
        if let request = task.originalRequest,
            url = request.URL,
            downloader = imageDownloaders[url.absoluteString] {
            downloader.didCompleteWithError(error)
            
            imageDownloaders[url.absoluteString] = nil
        }
    }
}

extension WebImageDownloaderManager: NSURLSessionDataDelegate {
    func URLSession(session: NSURLSession, dataTask: NSURLSessionDataTask, willCacheResponse proposedResponse: NSCachedURLResponse, completionHandler: (NSCachedURLResponse?) -> Void) {
        completionHandler(session === cacheSession ? proposedResponse : nil)
    }
}

extension WebImageDownloaderManager: NSURLSessionDownloadDelegate {
    func URLSession(session: NSURLSession, downloadTask: NSURLSessionDownloadTask, didFinishDownloadingToURL location: NSURL) {
        if let request = downloadTask.originalRequest,
            url = request.URL,
            downloader = imageDownloaders[url.absoluteString] {
            downloader.didFinishDownloadingToURL(location)
        }
    }
    
    func URLSession(session: NSURLSession, downloadTask: NSURLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if let request = downloadTask.originalRequest,
            url = request.URL,
            downloader = imageDownloaders[url.absoluteString] {
            downloader.didWriteData(bytesWritten, totalBytesWritten: totalBytesWritten, totalBytesExpectedToWrite: totalBytesExpectedToWrite)
        }
    }
}
