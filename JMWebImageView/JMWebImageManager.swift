//
//  WebImageManager.swift
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


class WebImageManager: NSObject {
    static var sharedManager = WebImageManager()
    
    
    func request(url: NSURL,
                 key: String,
                 size: CGFloat = .max,
                 useCache: Bool = true,
                 cacheDuration: NSTimeInterval = 86400, /* 1 day */
                 useProtocolCachePolicy: Bool = true,
                 monitorProgress: Bool = false,
                 completion: (error: NSError?, image: UIImage?, progress: Float?) -> Void) {
        let download = {
            WebImageDownloaderManager.sharedManager.request(url,
                                                            key: key,
                                                            size: size,
                                                            useCache: useCache,
                                                            useProtocolCachePolicy: useProtocolCachePolicy,
                                                            monitorProgress: monitorProgress,
                                                            completion: completion)
        }
        
        if useCache {
            WebImageCacheManager.imageForURL(url, size: size, cacheDuration: cacheDuration) { error, image in
                if let image = image where error == nil {
                    completion(error: error, image: image, progress: nil)
                } else {
                    download()
                }
            }
        } else {
            download()
        }
    }
}
