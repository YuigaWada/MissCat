import SwiftUI

public struct MissCatInstanceEditorView: View {
    @Binding private var instance: String
    public let onCancel: () -> Void
    public let onApply: (String) -> Void

    @State private var draft: String
    @FocusState private var isFocused: Bool

    public init(
        instance: Binding<String>,
        onCancel: @escaping () -> Void,
        onApply: @escaping (String) -> Void
    ) {
        _instance = instance
        _draft = State(initialValue: instance.wrappedValue)
        self.onCancel = onCancel
        self.onApply = onApply
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("接続先インスタンス") {
                    TextField("misskey.io", text: $draft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .submitLabel(.done)
                        .focused($isFocused)
                        .onSubmit(apply)
                        .accessibilityIdentifier("instance.field")
                }
            }
            .navigationTitle("インスタンスを変更")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル", action: onCancel)
                        .accessibilityIdentifier("instance.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("変更", action: apply)
                        .disabled(Self.normalize(draft).isEmpty)
                        .accessibilityIdentifier("instance.apply")
                }
            }
        }
        .onAppear { isFocused = true }
        .accessibilityIdentifier("instance.screen")
    }

    public static func normalize(_ value: String) -> String {
        var normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "　", with: "")

        for prefix in ["https://", "http://"] where normalized.hasPrefix(prefix) {
            normalized.removeFirst(prefix.count)
        }
        return normalized.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func apply() {
        let normalized = Self.normalize(draft)
        guard !normalized.isEmpty else { return }
        instance = normalized
        onApply(normalized)
    }
}
