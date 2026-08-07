# Share and Clipboard boundaries

The app uses SwiftUI `ShareLink` with a `String` or `URL` `Transferable` for
system share presentations. This keeps activity-sheet ownership in SwiftUI and
does not require an app-owned `UIActivityViewController` representable.

Timeline overflow actions intentionally keep one isolated
`MissCatSystemClipboardWriter` adapter. The actions are immediate custom
buttons, not the focused standard Copy command. Apple's `copyable(_:)`
documentation says custom actions such as context-menu items must update
`UIPasteboard` directly. Replacing the adapter with `copyable(_:)` would remove
the existing tap-to-copy behavior on iPhone. The domain and every SwiftUI
timeline source remain UIKit- and pasteboard-free; tests enforce that this
adapter is the only owner.

References:

- <https://developer.apple.com/documentation/swiftui/sharelink>
- <https://developer.apple.com/documentation/swiftui/view/copyable%28_%3A%29>
- <https://developer.apple.com/documentation/coretransferable>
