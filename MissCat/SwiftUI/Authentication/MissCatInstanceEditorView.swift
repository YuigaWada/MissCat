import SwiftUI

/// Presents the instance editor with the same native alert chrome and copy used by
/// the legacy start screen. Keeping it as a SwiftUI alert also preserves the
/// automatic keyboard presentation and platform button layout.
public struct MissCatInstanceEditorView: View {
    @Binding private var isPresented: Bool
    @Binding private var instance: String
    public let onCancel: () -> Void
    public let onApply: (String) -> Void

    @State private var draft = ""

    public init(
        isPresented: Binding<Bool>,
        instance: Binding<String>,
        onCancel: @escaping () -> Void,
        onApply: @escaping (String) -> Void
    ) {
        _isPresented = isPresented
        _instance = instance
        self.onCancel = onCancel
        self.onApply = onApply
    }

    public var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .alert("インスタンスの変更", isPresented: $isPresented) {
                TextField("misskey.io", text: $draft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.done)
                    .onSubmit(apply)
                    .accessibilityIdentifier("instance.field")

                Button("閉じる", role: .cancel) {
                    onCancel()
                }
                .accessibilityIdentifier("instance.cancel")

                Button("変更", action: apply)
                    .accessibilityIdentifier("instance.apply")
            }
            .onChange(of: isPresented) { _, presented in
                if presented {
                    // UIKit's text field was intentionally empty and displayed
                    // misskey.io as a placeholder every time the alert opened.
                    draft = ""
                }
            }
            .overlay {
                MissCatAuthenticationMarker(identifier: "instance.screen")
            }
    }

    /// Mirrors `StartViewController.shapeInstance(_:)` so existing instance
    /// strings keep the same behavior during the SwiftUI migration.
    nonisolated public static func normalize(_ value: String) -> String {
        var normalized = value
        var removals = [" ", "　"]
        if value.contains("http") {
            removals.append("http://")
            removals.append("https://")
        }

        for removal in removals {
            normalized = normalized.replacingOccurrences(of: removal, with: "")
        }
        return normalized
    }

    nonisolated public static func resolve(_ value: String) -> String {
        normalize(value.isEmpty ? "misskey.io" : value)
    }

    private func apply() {
        let resolved = Self.resolve(draft)
        instance = resolved
        isPresented = false
        onApply(resolved)
    }
}
