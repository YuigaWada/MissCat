# Share extension SwiftUI boundary

The `MissCatShare` target contains eight PBX source members. Its ratcheted
framework counts are:

- UIKit-only: 0
- SwiftUI-only: 1
- UIKit + SwiftUI hybrid: 1
- Neutral: 6
- Pure SwiftUI ratio: 1 / 2 (50%)

Run `scripts/verify-swiftui-share-framework-ratio.sh` to check the ratchet.
The stricter `scripts/verify-swiftui-share-framework-complete.sh` intentionally
fails while the system-required principal controller remains.

## Why one UIKit boundary remains

`com.apple.share-services` launches the class named by
`NSExtensionPrincipalClass`. Apple's Share extension contract obtains incoming
items and finishes or cancels the request through the principal view
controller's `extensionContext`. `ShareViewController` therefore remains the
single UIKit/SwiftUI hybrid boundary: it reads `extensionContext.inputItems`,
hosts one SwiftUI root in `UIHostingController`, and resolves completion or
cancellation exactly once.

ExtensionKit scenes do not replace that system contract. They serve custom
extension points whose host declares a user-interface attribute and requests a
scene through `EXHostViewController`. The system Share sheet does not expose
that host-side scene negotiation. In the iOS 18.5 SDK, the standard Share
composer entry also remains `SLComposeServiceViewController : UIViewController`.

References:

- [Apple Share extension programming guide](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Share.html)
- [NSExtensionPrincipalClass](https://developer.apple.com/documentation/bundleresources/information-property-list/nsextension/nsextensionprincipalclass)
- [ExtensionKit UI hosting contract](https://developer.apple.com/documentation/ExtensionKit/including-extension-based-ui-in-your-interface)

All visual content, including the signed Keychain proof fixture, is SwiftUI.
Input normalization is Foundation/Uniform Type Identifiers, while image preview
and JPEG preparation use Core Graphics and Image I/O without UIKit. Account
selection, shared-Keychain credential resolution, text/URL/image receipt,
posting, retry, and cancellation behavior remain unchanged.
