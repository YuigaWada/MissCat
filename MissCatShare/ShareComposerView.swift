import Foundation
import SwiftUI

struct ShareExtensionRootView: View {
    @StateObject private var viewModel: ShareComposerViewModel

    private let inputItems: [Any]
    private let inputLoader: ShareInputLoading
    private let onComplete: () -> Void
    private let onCancel: () -> Void
    private let credentialReadProof: ShareCredentialReadProof?

    init(
        userModel: UserModel,
        inputItems: [Any],
        inputLoader: ShareInputLoading = ShareInputLoader(),
        onComplete: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        let users = userModel.getUsers()
        let accounts = users.map {
            ShareAccount(userID: $0.userId, username: $0.username, instance: $0.instance)
        }
        let currentAccountID = userModel.getCurrentUser()?.accountIdentifier
        let selectedAccountID = accounts.contains(where: { $0.id == currentAccountID })
            ? currentAccountID
            : accounts.first?.id
        let visibility = userModel.getCurrentVisibility() ?? .public

        _viewModel = StateObject(
            wrappedValue: ShareComposerViewModel(
                accounts: accounts,
                selectedAccountID: selectedAccountID,
                visibility: visibility,
                posting: SharePostService(
                    userProvider: userModel.getUser(accountIdentifier:)
                )
            )
        )
        self.inputItems = inputItems
        self.inputLoader = inputLoader
        self.onComplete = onComplete
        self.onCancel = onCancel
#if DEBUG
        credentialReadProof = ShareCredentialReadProofLoader.loadIfRequested(userModel: userModel)
#else
        credentialReadProof = nil
#endif
    }

    @ViewBuilder
    var body: some View {
        if let credentialReadProof {
            ShareCredentialReadProofView(proof: credentialReadProof)
        } else {
            ShareComposerView(
                viewModel: viewModel,
                onComplete: onComplete,
                onCancel: cancel,
                onReloadInput: reloadInput
            )
            .task {
                await loadSharedContent()
            }
        }
    }

    private func reloadInput() {
        Task { @MainActor in
            await loadSharedContent()
        }
    }

    @MainActor
    private func loadSharedContent() async {
        guard viewModel.phase != .posting,
              viewModel.phase != .completed,
              viewModel.phase != .cancelled,
              viewModel.phase != .outcomeUnknown
        else { return }
        viewModel.beginLoading()

        do {
            let draft = try await inputLoader.load(inputItems: inputItems)
            viewModel.load(draft)
        } catch is CancellationError {
            return
        } catch {
            viewModel.failLoading(error)
        }
    }

    private func cancel() {
        viewModel.cancel()
        onCancel()
    }
}

#if DEBUG
private enum ShareCredentialReadProofLoader {
    static func loadIfRequested(userModel: UserModel) -> ShareCredentialReadProof? {
        guard let defaults = UserDefaults(suiteName: ShareCredentialReadProbe.appGroup),
              defaults.bool(forKey: ShareCredentialReadProbe.requestKey)
        else { return nil }

        var proof: ShareCredentialReadProof?
        let invoked = ShareCredentialReadProbe.invokeIfRequested(
            arguments: ProcessInfo.processInfo.arguments + [ShareCredentialReadProbe.launchArgument],
            accountIdentifier: userModel.getCurrentUserId(),
            read: userModel.credentialReadProof(accountIdentifier:),
            store: { proof = $0 }
        )
        guard invoked, let proof else { return nil }

        defaults.set(proof.credentialAvailable, forKey: ShareCredentialReadProbe.resultKey)
        defaults.set(proof.accountIdentifierHash, forKey: ShareCredentialReadProbe.accountHashKey)
        defaults.synchronize()
        return proof
    }
}
#endif

struct ShareComposerView: View {
    @ObservedObject var viewModel: ShareComposerViewModel

    let onComplete: () -> Void
    let onCancel: () -> Void
    let onReloadInput: () -> Void

    @State private var showsAccountPicker = false
    @State private var showsVisibilityPicker = false

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .trailing, spacing: 4) {
                        TextEditor(text: $viewModel.text)
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .padding(10)
                            .frame(minHeight: 170)
                            .background(.white, in: RoundedRectangle(cornerRadius: 10))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.black.opacity(0.12), lineWidth: 0.5)
                            }
                            .accessibilityLabel("投稿内容")
                            .accessibilityIdentifier("share.compose.text")

                        Text("\(viewModel.text.count) / \(ShareComposerViewModel.maximumTextLength)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(
                                viewModel.text.count > ShareComposerViewModel.maximumTextLength
                                    ? Color.red
                                    : Color.secondary
                            )
                            .accessibilityIdentifier("share.compose.character-count")
                    }

                    if !viewModel.imageData.isEmpty {
                        imagePreviews
                    }

                    VStack(spacing: 0) {
                        selectionRow(
                            title: "アカウント",
                            value: viewModel.selectedAccount?.displayName ?? "未選択",
                            identifier: "share.compose.account"
                        ) {
                            showsAccountPicker = true
                        }

                        Divider().padding(.leading, 16)

                        selectionRow(
                            title: "公開範囲",
                            value: viewModel.visibility.rawValue,
                            identifier: "share.compose.visibility"
                        ) {
                            showsVisibilityPicker = true
                        }
                    }
                    .background(.white, in: RoundedRectangle(cornerRadius: 10))
                }
                .padding(16)
            }
            .disabled(viewModel.phase == .posting)
            .background(Color(hex: "F2F2F7"))
        }
        .overlay {
            if viewModel.phase == .loading || viewModel.phase == .posting {
                ZStack {
                    Color.black.opacity(0.16).ignoresSafeArea()
                    ProgressView(viewModel.phase == .posting ? "送信中" : "読み込み中")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                .accessibilityIdentifier(
                    viewModel.phase == .posting ? "share.compose.posting" : "share.compose.loading"
                )
                .allowsHitTesting(false)
            }
        }
        .sheet(isPresented: $showsAccountPicker) {
            ShareAccountPickerView(
                accounts: viewModel.accounts,
                selectedAccountID: $viewModel.selectedAccountID
            )
        }
        .sheet(isPresented: $showsVisibilityPicker) {
            ShareVisibilityPickerView(visibility: $viewModel.visibility)
        }
        .alert(
            "エラー",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.clearError() } }
            )
        ) {
            if viewModel.canPost {
                Button("再試行") { submit() }
            } else if viewModel.canReloadInput {
                Button("再読込") { onReloadInput() }
            }
            Button("閉じる", role: .cancel) { viewModel.clearError() }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .accessibilityIdentifier("share.compose.screen")
    }

    private var header: some View {
        ZStack {
            Image("back")
                .resizable()
                .scaledToFill()

            Image("MissCat")
                .resizable()
                .scaledToFit()
                .frame(height: 32)
                .accessibilityHidden(true)

            HStack {
                Button("キャンセル", action: onCancel)
                    .accessibilityIdentifier("share.compose.cancel")

                Spacer()

                Button("投稿", action: submit)
                    .fontWeight(.semibold)
                    .disabled(!viewModel.canPost)
                    .accessibilityIdentifier("share.compose.post")
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
        }
        .frame(height: 52)
        .clipped()
    }

    private var imagePreviews: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(viewModel.imageData.enumerated()), id: \.offset) { index, data in
                    if let image = ShareImageCodec.decode(data) {
                        Image(decorative: image, scale: 1, orientation: .up)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 92, height: 92)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .accessibilityLabel("添付画像\(index + 1)")
                            .accessibilityIdentifier("share.compose.image.\(index)")
                    }
                }
            }
        }
        .accessibilityIdentifier("share.compose.images")
    }

    private func selectionRow(
        title: String,
        value: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                Text(value)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 50)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private func submit() {
        Task { @MainActor in
            if await viewModel.submit() {
                onComplete()
            }
        }
    }
}

struct ShareCredentialReadProofView: View {
    let proof: ShareCredentialReadProof

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Shared Keychain proof")
                .font(.headline)
            Text(proof.credentialAvailable ? "true" : "false")
                .font(.system(.body, design: .monospaced))
                .accessibilityIdentifier("share-keychain-proof.available")
            Text(proof.accountIdentifierHash)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .accessibilityIdentifier("share-keychain-proof.account-hash")
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(Color(hex: "F2F2F7"))
        .accessibilityElement(children: .contain)
    }
}

private struct ShareAccountPickerView: View {
    let accounts: [ShareAccount]
    @Binding var selectedAccountID: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(accounts) { account in
                Button {
                    selectedAccountID = account.id
                    dismiss()
                } label: {
                    HStack {
                        Text(account.displayName)
                        Spacer()
                        if selectedAccountID == account.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color(hex: "2BA3BC"))
                        }
                    }
                }
                .foregroundStyle(.primary)
                .accessibilityIdentifier("share.account.\(account.id)")
            }
            .navigationTitle("アカウント")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                        .accessibilityIdentifier("share.account.close")
                }
            }
        }
        .accessibilityIdentifier("share.account.screen")
    }
}

private struct ShareVisibilityPickerView: View {
    @Binding var visibility: ShareVisibility
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(ShareVisibility.allCases) { option in
                Button {
                    visibility = option
                    dismiss()
                } label: {
                    HStack {
                        Text(option.rawValue)
                        Spacer()
                        if visibility == option {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color(hex: "2BA3BC"))
                        }
                    }
                }
                .foregroundStyle(.primary)
                .accessibilityIdentifier("share.visibility.\(option.rawValue)")
            }
            .navigationTitle("公開範囲")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                        .accessibilityIdentifier("share.visibility.close")
                }
            }
        }
        .accessibilityIdentifier("share.visibility.screen")
    }
}

private extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}
