# Share and Clipboard boundaries

The app uses SwiftUI `ShareLink` with a `String` or `URL` `Transferable` for
system share presentations. This keeps activity-sheet ownership in SwiftUI and
does not require an app-owned `UIActivityViewController` representable.

Timeline overflow actions intentionally keep one isolated
`MissCatSystemClipboardWriter` adapter. The actions are immediate custom
buttons, not a selection- or focus-driven standard Copy command. SwiftUI's
`copyable(_:)` exposes transferable content to the system copy interaction but
does not provide an imperative custom-button operation that preserves the
existing one-tap overflow action. Replacing the adapter with `copyable(_:)`
would therefore change the interaction on iPhone.

The adapter exposes exactly one public operation, `write(_:)`, and its only OS
call is assigning `UIPasteboard.general.string`. The fixture probe receives the
just-written value through an internal notification; it never reads the
pasteboard back. The domain actions accept `MissCatClipboardWriting`, and every
SwiftUI timeline source remains UIKit- and pasteboard-free. Source tests audit
all production files and fail if another pasteboard owner or a read API appears.

References:

- <https://developer.apple.com/documentation/swiftui/sharelink>
- <https://developer.apple.com/documentation/swiftui/view/copyable%28_%3A%29>
- <https://developer.apple.com/documentation/coretransferable>
