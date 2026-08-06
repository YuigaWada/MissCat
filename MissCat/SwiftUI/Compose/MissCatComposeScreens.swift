import SwiftUI
import UIKit

@MainActor
enum MissCatComposeFactory {
    static func makeViewModel(
        mode: MissCatComposeMode,
        draft: MissCatComposeDraft = MissCatComposeDraft()
    ) -> MissCatComposeViewModel {
        MissCatComposeViewModel(
            mode: mode,
            draft: draft,
            environment: MissCatComposeEnvironmentStore(),
            posting: MissCatComposePostService(),
            nowPlayingProvider: MissCatNowPlayingProvider()
        )
    }
}

struct MissCatNewNoteComposerView: View {
    @ObservedObject var viewModel: MissCatComposeViewModel
    let onComplete: () -> Void
    let onCancel: () -> Void

    var body: some View {
        MissCatComposeScreen(viewModel: viewModel, onComplete: onComplete, onCancel: onCancel)
    }
}

struct MissCatReplyComposerView: View {
    @ObservedObject var viewModel: MissCatComposeViewModel
    let onComplete: () -> Void
    let onCancel: () -> Void

    var body: some View {
        MissCatComposeScreen(viewModel: viewModel, onComplete: onComplete, onCancel: onCancel)
    }
}

struct MissCatQuoteComposerView: View {
    @ObservedObject var viewModel: MissCatComposeViewModel
    let onComplete: () -> Void
    let onCancel: () -> Void

    var body: some View {
        MissCatComposeScreen(viewModel: viewModel, onComplete: onComplete, onCancel: onCancel)
    }
}

struct MissCatRenoteComposerView: View {
    @ObservedObject var viewModel: MissCatComposeViewModel
    let onComplete: () -> Void
    let onCancel: () -> Void

    var body: some View {
        MissCatComposeScreen(viewModel: viewModel, onComplete: onComplete, onCancel: onCancel)
    }
}

struct MissCatComposeScreen: View {
    @ObservedObject var viewModel: MissCatComposeViewModel
    let onComplete: () -> Void
    let onCancel: () -> Void

    @FocusState private var focusedField: FocusedField?
    @State private var showsAccounts = false
    @State private var showsVisibility = false
    @State private var showsContentWarning = false
    @State private var showsPoll = false
    @State private var showsMediaPicker = false
    @State private var showsTokens = false
    @State private var showsDiscardConfirmation = false
    @State private var editingMedia: MissCatComposeMedia?
    @State private var mediaValidationMessage: String?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            navigationHeader
            if case .renote = viewModel.mode {
                renoteConfirmation
            } else {
                composerBody
            }
        }
        .background(palette.base.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !viewModel.mode.isRenote { composerToolbar }
        }
        .overlay { progressOverlay }
        .task {
            await viewModel.load()
            if viewModel.phase == .ready, !viewModel.mode.isRenote {
                focusedField = viewModel.draft.hasContentWarning ? .contentWarning : .text
            }
        }
        .sheet(isPresented: $showsAccounts) {
            MissCatComposeAccountPicker(
                accounts: viewModel.accounts,
                selectedAccountID: viewModel.selectedAccountID,
                onSelect: viewModel.selectAccount
            )
        }
        .sheet(isPresented: $showsVisibility) {
            MissCatVisibilitySelectorView(
                visibility: visibilityBinding,
                visibleUserIDs: $viewModel.draft.visibleUserIDs
            )
        }
        .sheet(isPresented: $showsContentWarning, onDismiss: refocusEditor) {
            MissCatContentWarningEditorView(
                isEnabled: $viewModel.draft.hasContentWarning,
                text: $viewModel.draft.contentWarning
            )
        }
        .sheet(isPresented: $showsPoll, onDismiss: refocusEditor) {
            if viewModel.draft.poll != nil {
                MissCatPollEditorView(poll: pollBinding)
            }
        }
        .sheet(isPresented: $showsMediaPicker, onDismiss: refocusEditor) {
            MissCatMediaPickerView(existingMedia: viewModel.draft.media) { media in
                do {
                    try viewModel.addMedia(media)
                } catch {
                    mediaValidationMessage = error.localizedDescription
                }
            }
        }
        .sheet(isPresented: $showsTokens, onDismiss: refocusEditor) {
            MissCatTokenInsertionView(
                onMention: viewModel.insertMention,
                onHashtag: viewModel.insertHashtag
            )
        }
        .sheet(item: $editingMedia, onDismiss: refocusEditor) { media in
            if media.kind == .image {
                MissCatMediaEditorView(media: media) { data in
                    viewModel.replaceMedia(id: media.id, data: data)
                }
            }
        }
        .alert("エラー", isPresented: errorIsPresented) {
            if viewModel.canSubmit {
                Button("再試行") { submit() }
            } else if viewModel.accounts.isEmpty {
                Button("再読込") { Task { await viewModel.load() } }
            }
            Button("閉じる", role: .cancel) { viewModel.dismissError() }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .alert("メディアを追加できません", isPresented: mediaErrorIsPresented) {
            Button("閉じる", role: .cancel) { mediaValidationMessage = nil }
        } message: {
            Text(mediaValidationMessage ?? "")
        }
        .confirmationDialog(
            "この投稿を破棄しますか？",
            isPresented: $showsDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("破棄", role: .destructive) { cancelNow() }
            Button("編集を続ける", role: .cancel) {}
        }
        .interactiveDismissDisabled(viewModel.hasUnsavedChanges || isBusy)
        .accessibilityIdentifier("compose.screen")
    }

    private var navigationHeader: some View {
        HStack(spacing: 22) {
            Button(action: requestCancel) {
                Image(systemName: "xmark").frame(width: 38, height: 38)
            }
            .accessibilityLabel("キャンセル")
            .accessibilityIdentifier("compose.cancel")

            Text(viewModel.mode.title)
                .font(MissCatTypography.navigationTitle)
                .lineLimit(1)

            Spacer()

            Button { showsVisibility = true } label: {
                Image(systemName: viewModel.draft.visibility.systemImage)
                    .frame(width: 38, height: 38)
            }
            .disabled(isBusy || viewModel.mode.isRenote)
            .accessibilityLabel(viewModel.draft.visibility.label)
            .accessibilityIdentifier("compose.visibility")

            Button(action: submit) {
                Image(systemName: viewModel.mode.isRenote ? "repeat" : "square.and.pencil")
                    .frame(width: 38, height: 38)
            }
            .disabled(!viewModel.canSubmit)
            .accessibilityLabel(viewModel.mode.isRenote ? "Renote" : "投稿")
            .accessibilityIdentifier("compose.submit")
        }
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(palette.accent)
        .padding(.horizontal, 12)
        .frame(height: MissCatLegacyMetrics.navigationHeaderHeight)
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.border).frame(height: MissCatLegacyMetrics.hairlineWidth)
        }
    }

    private var composerBody: some View {
        HStack(alignment: .top, spacing: 8) {
            Button { showsAccounts = true } label: {
                AsyncImage(url: viewModel.selectedAccount?.avatarURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Circle().fill(palette.surface)
                        .overlay(Image(systemName: "person.fill").foregroundStyle(palette.strong))
                }
                .frame(width: 33, height: 33)
                .clipShape(Circle())
            }
            .disabled(isBusy)
            .accessibilityLabel(viewModel.selectedAccount?.displayName ?? "アカウントを選択")
            .accessibilityIdentifier("compose.account")

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if viewModel.draft.hasContentWarning {
                        ZStack(alignment: .topLeading) {
                            if viewModel.draft.contentWarning.isEmpty {
                                Text("-注釈をここに書く-")
                                    .foregroundStyle(palette.muted)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 8)
                            }
                            TextEditor(text: $viewModel.draft.contentWarning)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 48)
                                .focused($focusedField, equals: .contentWarning)
                                .accessibilityIdentifier("compose.cw.inline-text")
                        }
                        Divider()
                    }

                    ZStack(alignment: .topLeading) {
                        if viewModel.draft.text.isEmpty {
                            Text("What's happening?")
                                .foregroundStyle(palette.muted)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 8)
                        }
                        TextEditor(text: $viewModel.draft.text)
                            .font(.system(size: 17))
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 220)
                            .focused($focusedField, equals: .text)
                            .accessibilityLabel("投稿内容")
                            .accessibilityIdentifier("compose.text")
                    }

                    MissCatComposeTargetPreview(mode: viewModel.mode)

                    if let poll = viewModel.draft.poll {
                        Button { showsPoll = true } label: {
                            HStack {
                                Image(systemName: "chart.bar")
                                Text("アンケート（\(poll.choices.count)件）")
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                            .padding(10)
                            .background(palette.surface, in: RoundedRectangle(cornerRadius: 5))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("compose.poll.summary")
                    }

                    if !viewModel.draft.media.isEmpty {
                        MissCatMediaPreviewStrip(
                            media: $viewModel.draft.media,
                            onEdit: { item in
                                if item.kind == .image { editingMedia = item }
                            }
                        )
                    }

                    if viewModel.draft.localOnly {
                        Label("ローカルのみ", systemImage: "house.fill")
                            .font(.caption)
                            .foregroundStyle(palette.strong)
                            .accessibilityIdentifier("compose.local-only-indicator")
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .padding(.top, 15)
        .padding(.horizontal, 20)
    }

    private var renoteConfirmation: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "repeat.circle.fill")
                .font(.system(size: 54))
                .foregroundStyle(palette.accent)
            Text("このノートをRenoteしますか？")
                .font(.headline)
            MissCatComposeTargetPreview(mode: viewModel.mode)
                .padding()
                .background(palette.surface, in: RoundedRectangle(cornerRadius: 8))
            Button("Renote", action: submit)
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canSubmit)
                .accessibilityIdentifier("compose.renote.confirm")
            Spacer()
        }
        .padding(20)
    }

    private var composerToolbar: some View {
        HStack(spacing: 4) {
            toolbarButton("camera", label: "メディアを追加") { showsMediaPicker = true }
            toolbarButton("chart.bar", label: "アンケート") {
                if viewModel.draft.poll == nil { viewModel.draft.poll = MissCatPollDraft() }
                showsPoll = true
            }
            toolbarButton("eye", label: "注釈と閲覧注意") { showsContentWarning = true }
            toolbarButton("music.note", label: "再生中の曲") { viewModel.addNowPlaying() }
                .disabled(viewModel.nowPlaying == nil)
            toolbarButton("at", label: "メンションとハッシュタグ") { showsTokens = true }

            Spacer(minLength: 4)

            Menu {
                Toggle("ローカルのみ", isOn: $viewModel.draft.localOnly)
                Button("公開範囲を変更") { showsVisibility = true }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(width: 38, height: 38)
            }
            .accessibilityIdentifier("compose.more")

            Text("\(viewModel.remainingCharacterCount)")
                .font(.system(size: 14).monospacedDigit())
                .foregroundStyle(viewModel.remainingCharacterCount < 0 ? Color.red : palette.strong)
                .frame(minWidth: 38)
                .accessibilityIdentifier("compose.counter")
        }
        .foregroundStyle(palette.accent)
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(palette.base)
        .overlay(alignment: .top) {
            Rectangle().fill(palette.border).frame(height: MissCatLegacyMetrics.hairlineWidth)
        }
    }

    @ViewBuilder
    private var progressOverlay: some View {
        switch viewModel.phase {
        case .loading:
            busyOverlay(label: "読み込み中", progress: nil, identifier: "compose.loading")
        case let .uploading(progress):
            busyOverlay(
                label: "アップロード中 \(progress.completed)/\(progress.total)",
                progress: progress.fraction,
                identifier: "compose.uploading"
            )
        case .submitting:
            busyOverlay(label: "送信中", progress: nil, identifier: "compose.submitting")
        case .ready, .failed, .completed, .cancelled:
            EmptyView()
        }
    }

    private func busyOverlay(label: String, progress: Double?, identifier: String) -> some View {
        ZStack {
            Color.black.opacity(0.18).ignoresSafeArea()
            VStack(spacing: 10) {
                if let progress {
                    ProgressView(value: progress).frame(width: 150)
                } else {
                    ProgressView()
                }
                Text(label).font(.subheadline)
            }
            .padding(20)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .accessibilityIdentifier(identifier)
    }

    private func toolbarButton(
        _ image: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: image).frame(width: 38, height: 38)
        }
        .disabled(isBusy)
        .accessibilityLabel(label)
        .accessibilityIdentifier("compose.toolbar.\(image)")
    }

    private var palette: MissCatVisualPalette {
        colorScheme == .dark ? .legacyDark : .legacyLight
    }

    private var isBusy: Bool {
        switch viewModel.phase {
        case .loading, .uploading, .submitting: true
        case .ready, .failed, .completed, .cancelled: false
        }
    }

    private var visibilityBinding: Binding<MissCatComposeVisibility> {
        Binding(
            get: { viewModel.draft.visibility },
            set: { viewModel.selectVisibility($0) }
        )
    }

    private var pollBinding: Binding<MissCatPollDraft> {
        Binding(
            get: { viewModel.draft.poll ?? MissCatPollDraft() },
            set: { viewModel.draft.poll = $0 }
        )
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.dismissError() } }
        )
    }

    private var mediaErrorIsPresented: Binding<Bool> {
        Binding(
            get: { mediaValidationMessage != nil },
            set: { if !$0 { mediaValidationMessage = nil } }
        )
    }

    private func submit() {
        focusedField = nil
        Task { @MainActor in
            if await viewModel.submit() { onComplete() }
        }
    }

    private func requestCancel() {
        focusedField = nil
        if viewModel.hasUnsavedChanges {
            showsDiscardConfirmation = true
        } else {
            cancelNow()
        }
    }

    private func cancelNow() {
        viewModel.cancel()
        onCancel()
    }

    private func refocusEditor() {
        guard viewModel.phase == .ready else { return }
        focusedField = .text
    }

    private enum FocusedField: Hashable {
        case contentWarning
        case text
    }
}
