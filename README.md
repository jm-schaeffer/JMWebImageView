# JMWebImageView

`UIImageView` subclass set up from a `NSURL`, asynchronously downloading the image and displaying it

## Optimizations

 - Image automatic resizing: if the image is too big a smaller version will be generated, cached and used / the original size image will also be cached and will be used to generate other sizes if necessary
 - Great image decoding performances thanks to ImageIO
 - Memory and file cache implemented using respectively NSCache and NSFileManager (in an asynchronous thread)

## Setup

```swift
@IBOutlet private weak var imageView: JMWebImageView!

func setUp() {
  imageView.url = NSURL(string: "http://thecatapi.com/api/images/get?format=src&type=png")
}
```

## Customization

### Basics

Simply create a `JMWebImageView` subclass and change the `UIImageView` properties

```swift
class CustomWebImageView: JMWebImageView {
  override func awakeFromNib() {
    super.awakeFromNib()

    backgroundColor = .whiteColor()
  }
}
```

### Loading

You can override the `loadLoadingView` method to add a simple `UIActivityIndicatorView` or the view of your choice.

```Swift
class CustomWebImageView: JMWebImageView {
  override func loadLoadingView() -> UIView? {
    if bounds.width >= 30.0 && bounds.height >= 30.0 {
      return CustomLoadingView.view()
    } else {
      return nil
    }
  }
}
```
