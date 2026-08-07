import UIKit

/// The single production boundary for the OS pasteboard API.
public final class MissCatSystemClipboardWriter: MissCatClipboardWriting {
    public init() {}

    @MainActor
    public func write(_ value: String) {
        UIPasteboard.general.string = value
    }
}
