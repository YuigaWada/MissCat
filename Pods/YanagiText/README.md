<img src="Resources/Logo.png">

[![License][license-image]][license-url]
[![Swift Version][swift-image]][swift-url]
[![CocoaPods Compatible](https://img.shields.io/cocoapods/v/EZSwiftExtensions.svg)](https://img.shields.io/cocoapods/v/LFAlertController.svg)
[![Carthage compatible](https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat)](https://github.com/Carthage/Carthage)

<br>

## YanagiText 📓

<img align="right" src="Resources/Demo.gif" width=30%>

YanagiText allows us to add any UIView to UITextView!

## Installation 📒

#### CocoaPods
You can use [CocoaPods](http://cocoapods.org/) to install `YanagiText` by adding it to your `Podfile`:

```ruby
pod 'YanagiText'
```

#### Carthage
Create a `Cartfile` that lists the framework and run `carthage update`. Follow the [instructions](https://github.com/Carthage/Carthage#if-youre-building-for-ios) to add `$(SRCROOT)/Carthage/Build/iOS/YanagiText.framework` to an iOS project.

```
github "YuigaWada/YanagiText"
```

#### Manually
1. Download and drop ```YanagiText``` in your project.  
2. Congratulations!  

<br><br>

## Usage 🔥

```YanagiText.getViewString``` registers a view internally, so you must call this methods via your TextView where you wanna add the view.

```swift
@IBOutlet weak var textView: YanagiText!

override func viewDidLoad() {
    super.viewDidLoad()

    // You can add a view to your UITextView
    self.textView = self.textView.getViewString(with: anyView, size: anyView.frame.size)
}
```


If you wanna set ```YanagiText.isEditable = true```, write the following code.

```swift
class YourViewController: UIViewController, UITextViewDelegate {

  override func viewDidLoad() {
      super.viewDidLoad()
      self.textView.delegate = self
  }

      ...

  func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
      return self.textView.shouldChangeText(textView, shouldChangeTextIn: range, replacementText: text)
  }

```

<br><br>

## Contribute 👨

We would love you for the contribution to **YanagiText**, check the ``LICENSE`` file for more info.



## Others

Yuiga Wada -  [WebSite](https://yuiga.dev)
Twitter         - [@YuigaWada](https://twitter.com/YuigaWada)





Distributed under the MIT license. See ``LICENSE`` for more information.

[https://github.com/YuigaWada/YanagiText](https://github.com/YuigaWada/YanagiText)




[swift-image]:https://img.shields.io/badge/swift-5.0-orange.svg
[swift-url]: https://swift.org/
[license-image]: https://img.shields.io/badge/License-MIT-blue.svg
[license-url]: LICENSE
[codebeat-image]: https://codebeat.co/badges/c19b47ea-2f9d-45df-8458-b2d952fe9dad
[codebeat-url]: https://codebeat.co/projects/github-com-vsouza-awesomeios-com
