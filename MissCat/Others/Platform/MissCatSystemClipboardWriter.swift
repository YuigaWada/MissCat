import UIKit

/// The single production boundary for the OS pasteboard API.
public final class MissCatSystemClipboardWriter: MissCatClipboardWriting {
    public static let didWriteNotification = Notification.Name("MissCatSystemClipboardWriter.didWrite")

    public init() {}

    @MainActor
    public func write(_ value: String) {
        UIPasteboard.general.string = value
        NotificationCenter.default.post(name: Self.didWriteNotification, object: nil)
    }

    @MainActor
    public func read() -> String? {
        UIPasteboard.general.string
    }
}
