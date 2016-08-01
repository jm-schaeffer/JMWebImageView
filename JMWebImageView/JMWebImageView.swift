//
//  JMWebImageView.swift
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


class JMWebImageView: UIImageView {
    private weak var loadingView: UIView?
    
    weak var delegate: JMWebImageViewDelegate?
    
    var url: NSURL? {
        didSet {
            if let oldValue = oldValue where oldValue != url {
                WebImageDownloaderManager.sharedManager.cancel(oldValue, key: hashString)
            }
            
            if url == nil {
                setState(.Initial)
            } else if superview != nil {
                load()
            }
        }
    }
    
    var useCache: Bool = true
    var cacheDuration: NSTimeInterval = 86400 // 1 day
    var placeholderImage: UIImage? // Displayed when the image cannot be loaded or if the url is set to nil
    
    
    var hashString: String {
        return String(ObjectIdentifier(self).uintValue)
    }
    
    
    private func load() {
        guard let url = url else {
            return
        }
        
        let size = max(bounds.width, bounds.height) * UIScreen.mainScreen().scale
        
        let download = {
            self.setState(.Loading)
            
            WebImageDownloaderManager.sharedManager.request(url, key: self.hashString, size: size, useCache: self.useCache, cacheDuration: self.cacheDuration, completion: { error, image, progress in
                self.setImage(image, animated: true)
            })
        }
        
        if useCache {
            WebImageCacheManager.imageForURL(url, size: size, cacheDuration: self.cacheDuration) { error, image in
                if let image = image where error == nil {
                    self.setImage(image, animated: false)
                } else {
                    download()
                }
            }
        } else {
            download()
        }
    }
    
    private let dissolveAnimationDuration = 0.5
    private func setImage(image: UIImage?, animated: Bool) {
        delegate?.webImageView(self, willUpdateImage: animated, duration: dissolveAnimationDuration)
        
        UIView.transitionWithView(
            self,
            duration: animated ? dissolveAnimationDuration : 0.0,
            options: [.TransitionCrossDissolve],
            animations: {
                self.setState(.Complete, image: image)
            },
            completion: { finished in
                self.delegate?.webImageView(self, didUpdateImage: animated)
        })
    }
    
    // MARK: - State
    private enum State {
        case Initial
        case Loading
        case Complete
    }
    private func setState(state: State, image: UIImage? = nil) {
        switch state {
        case .Initial:
            self.image = placeholderImage
            layer.removeAllAnimations()
            removeLoadingView()
        case .Loading:
            self.image = nil
            layer.removeAllAnimations()
            showLoadingView()
        case .Complete:
            removeLoadingView()
            self.image = image ?? placeholderImage
            if image == nil { // When the image couldn't be loaded we need to reset the url
                url = nil
            }
        }
    }
    
    // MARK: - Loading View
    private func showLoadingView() {
        if loadingView == nil {
            if let loadingView = loadLoadingView() {
                loadingView.autoresizingMask = [.FlexibleWidth, .FlexibleHeight]
                loadingView.frame = CGRect(x: 0.0, y: 0.0, width: bounds.width, height: bounds.height)
                addSubview(loadingView)
                self.loadingView = loadingView
            }
        }
    }
    
    private func removeLoadingView() {
        loadingView?.removeFromSuperview()
    }
    
    // MARK: - Methods that can be overriden
    // Don't call the super implementation
    func loadLoadingView() -> UIView? {
        if bounds.width >= 30.0 && bounds.height >= 30.0 {
            let activityIndicatorView = UIActivityIndicatorView(activityIndicatorStyle: .Gray)
            activityIndicatorView.startAnimating()
            return activityIndicatorView
        } else {
            return nil
        }
    }
    
    func setProgress(progress: Float) {
        
    }
}


protocol JMWebImageViewDelegate: NSObjectProtocol {
    func webImageView(webImageView: JMWebImageView, willUpdateImage animated: Bool, duration: NSTimeInterval)
    func webImageView(webImageView: JMWebImageView, didUpdateImage animated: Bool)
}
