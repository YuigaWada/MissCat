import AVKit
import SwiftUI

extension MissCatVisualPalette {
    static let noteLegacyLight = MissCatVisualPalette(
        accent: Color(hex: "7AB800"),
        base: Color(hex: "FFFFFF"),
        strong: Color(hex: "6B6B6B"),
        border: Color(hex: "D1D1D1"),
        muted: Color(hex: "E0E0E0"),
        surface: Color(hex: "F5F5F5"),
        text: Color(hex: "2E2E2E")
    )
}

struct MissCatTrackedRemoteImage: View {
    let url: URL?
    let key: String
    let palette: MissCatVisualPalette
    let fallbackSymbol: String
    let contentMode: ContentMode
    let readiness: MissCatNoteVisualReadiness?

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        configured(image)
                            .overlay { terminalReporter }
                    case .failure:
                        fallback.overlay { terminalReporter }
                    case .empty:
                        palette.surface.overlay { ProgressView().tint(palette.strong) }
                    @unknown default:
                        fallback.overlay { terminalReporter }
                    }
                }
                .onAppear { readiness?.register(key) }
            } else {
                fallback
            }
        }
    }

    @ViewBuilder
    private func configured(_ image: Image) -> some View {
        if contentMode == .fill {
            image.resizable().scaledToFill()
        } else {
            image.resizable().scaledToFit()
        }
    }

    private var fallback: some View {
        palette.surface.overlay {
            Image(systemName: fallbackSymbol)
                .foregroundStyle(palette.strong)
        }
    }

    private var terminalReporter: some View {
        Color.clear
            .onAppear { readiness?.complete(key) }
            .accessibilityHidden(true)
    }
}

/// A native SwiftUI presentation surface matching the legacy bottom-panel
/// geometry without depending on UIKit presentation controllers.
struct MissCatLegacyBottomOverlay<Content: View>: View {
    let height: CGFloat
    let palette: MissCatVisualPalette
    let content: Content

    init(
        height: CGFloat,
        palette: MissCatVisualPalette,
        @ViewBuilder content: () -> Content
    ) {
        self.height = height
        self.palette = palette
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.24).ignoresSafeArea()

            content
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .safeAreaPadding(.bottom, 12)
                .frame(maxWidth: .infinity)
                .frame(height: height, alignment: .top)
                .background(palette.base)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 14,
                        topTrailingRadius: 14
                    )
                )
        }
        .presentationBackground(.clear)
    }
}

public struct MissCatURLPreviewCard: View {
    @Environment(\.openURL) private var openURL
    @StateObject private var store: MissCatURLPreviewStore

    private let sourceURL: URL
    private let palette: MissCatVisualPalette
    private let readiness: MissCatNoteVisualReadiness?
    @State private var presentedFailure: PresentedFailure?
    private var requestKey: String { "url-preview:\(sourceURL.absoluteString)" }

    public init(
        sourceURL: URL,
        repository: any MissCatNoteContextRepository,
        palette: MissCatVisualPalette = .legacyLight,
        readiness: MissCatNoteVisualReadiness? = nil
    ) {
        self.sourceURL = sourceURL
        self.palette = palette
        self.readiness = readiness
        _store = StateObject(
            wrappedValue: MissCatURLPreviewStore(sourceURL: sourceURL, repository: repository)
        )
    }

    public var body: some View {
        Group {
            switch store.phase {
            case .idle, .loading:
                loadingCard
            case let .loaded(preview):
                loadedCard(preview)
            case let .failed(message):
                failureCard(message)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .stroke(palette.border, lineWidth: MissCatLegacyMetrics.hairlineWidth)
        }
        .accessibilityElement(children: .contain)
        .onAppear {
            readiness?.register(requestKey)
            store.load()
        }
        .onDisappear { store.cancel() }
        .onChange(of: store.phase) { _, phase in
            switch phase {
            case let .loaded(preview):
                if let imageURL = preview.imageURL {
                    readiness?.register(imageKey(imageURL))
                }
                readiness?.complete(requestKey)
            case let .failed(message):
                presentedFailure = PresentedFailure(message: message)
                readiness?.complete(requestKey)
            case .idle, .loading:
                break
            }
        }
        .fullScreenCover(item: $presentedFailure) { failure in
            MissCatLegacyBottomOverlay(
                height: MissCatLegacyMetrics.notePreviewFailurePanelHeight,
                palette: palette
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("リンクを表示できません")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(palette.text)
                        .accessibilityIdentifier("note.url-preview.failure")

                    Button {
                        openURL(store.fallbackPreview.resolvedURL)
                    } label: {
                        Text(failure.message)
                            .font(.system(size: 13))
                            .foregroundStyle(palette.strong)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("note.url-preview.fallback")

                    Button("再試行") {
                        presentedFailure = nil
                        store.retry()
                    }
                    .font(.system(size: 17))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(palette.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("note.url-preview.retry")
                }
            }
        }
    }

    private var loadingCard: some View {
        HStack(spacing: 12) {
            palette.muted.frame(width: 92, height: 86)
            VStack(alignment: .leading, spacing: 8) {
                palette.muted.frame(height: 13)
                palette.muted.frame(width: 150, height: 11)
                palette.muted.frame(height: 11)
            }
            .padding(.trailing, 12)
        }
        .background(palette.surface)
        .accessibilityLabel("リンク情報を読み込み中")
        .accessibilityIdentifier("note.url-preview.loading")
    }

    private func loadedCard(_ preview: MissCatURLPreview) -> some View {
        Button { openURL(preview.resolvedURL) } label: {
            HStack(spacing: 0) {
                if let imageURL = preview.imageURL {
                    MissCatTrackedRemoteImage(
                        url: imageURL,
                        key: imageKey(imageURL),
                        palette: palette,
                        fallbackSymbol: "link",
                        contentMode: .fill,
                        readiness: readiness
                    )
                    .frame(width: 104, height: 96)
                    .clipped()
                    .blur(radius: preview.isSensitive ? 14 : 0)
                } else {
                    palette.muted
                        .frame(width: 104, height: 96)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(preview.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.text)
                        .lineLimit(1)
                    if !preview.description.isEmpty {
                        Text(preview.description)
                            .font(.system(size: 11))
                            .foregroundStyle(palette.strong)
                            .lineLimit(3)
                    }
                    Text(preview.siteName ?? preview.resolvedURL.host ?? preview.resolvedURL.absoluteString)
                        .font(.system(size: 10))
                        .foregroundStyle(palette.strong)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .frame(height: 96)
            .background(palette.base)
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(palette.border, lineWidth: 0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(preview.title)。リンクを開く")
        .accessibilityIdentifier("note.url-preview.content")
    }

    private func failureCard(_ message: String) -> some View {
        loadedCard(store.fallbackPreview)
            .accessibilityValue(message)
    }

    private func imageKey(_ url: URL) -> String { "url-preview-image:\(url.absoluteString)" }

    private struct PresentedFailure: Identifiable {
        let id = UUID()
        let message: String
    }
}

public struct MissCatReactionPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store: MissCatReactionPickerStore

    private let noteID: String
    private let existingReactions: [MissCatReaction]
    private let palette: MissCatVisualPalette
    private let onSelect: (String, String) -> Void

    public init(
        noteID: String,
        existingReactions: [MissCatReaction],
        repository: any MissCatNoteContextRepository,
        palette: MissCatVisualPalette = .legacyLight,
        onSelect: @escaping (String, String) -> Void
    ) {
        self.noteID = noteID
        self.existingReactions = existingReactions
        self.palette = palette
        self.onSelect = onSelect
        _store = StateObject(wrappedValue: MissCatReactionPickerStore(repository: repository))
    }

    public var body: some View {
        MissCatLegacyBottomOverlay(
            height: MissCatLegacyMetrics.noteReactionPanelHeight,
            palette: palette
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text("リアクション")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.text)
                    .accessibilityIdentifier("reaction.picker")

                Divider()

                pickerContent
            }
        }
        .task { store.load() }
        .accessibilityElement(children: .contain)
    }

    private var pickerContent: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                TextField("絵文字を検索", text: $store.query)
            }
            .font(.system(size: 16))
            .foregroundStyle(palette.strong)
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityIdentifier("reaction.picker.search")

            if case let .failed(message) = store.phase {
                HStack {
                    Text(message).lineLimit(1)
                    Spacer()
                    Button("再試行") { store.retry() }
                        .accessibilityIdentifier("reaction.picker.retry")
                }
                .font(.system(size: 11))
                .foregroundStyle(palette.strong)
            }

            Divider()

            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 8) {
                    ForEach(allChoices) { choice in
                        Button {
                            onSelect(noteID, choice.value)
                            dismiss()
                        } label: {
                            Text(choice.label)
                                .font(.system(size: 24))
                                .lineLimit(1)
                                .minimumScaleFactor(0.55)
                                .frame(maxWidth: .infinity, minHeight: 42)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(choice.value)
                        .accessibilityIdentifier("reaction.picker.choice.\(choice.value)")
                    }
                }
            }
        }
    }

    private var allChoices: [MissCatReactionChoice] {
        var values = Set<String>()
        let existing = existingReactions.map { MissCatReactionChoice(value: $0.name) }
        return (store.filteredChoices + existing).filter { values.insert($0.value).inserted }
    }
}

public struct MissCatMediaViewer: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: String
    @StateObject private var readiness = MissCatNoteVisualReadiness()

    public let attachments: [MissCatNoteAttachment]

    public init(attachments: [MissCatNoteAttachment], selectedID: String) {
        self.attachments = attachments
        _selectedID = State(initialValue: selectedID)
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $selectedID) {
                ForEach(attachments) { attachment in
                    mediaPage(attachment)
                        .tag(attachment.id)
                        .accessibilityIdentifier("media.page.\(attachment.id)")
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .accessibilityIdentifier("media.pager")

            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("閉じる")
                    .accessibilityIdentifier("media.close")
                    Spacer()
                    Text(pageLabel)
                        .font(.system(size: 13, weight: .semibold))
                        .accessibilityIdentifier("media.page-indicator")
                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal, 8)
                .foregroundStyle(.white)
                .background(.black.opacity(0.55))
                Spacer()
            }

        }
        .onAppear {
            for attachment in attachments {
                if let url = attachment.url {
                    readiness.register("media:\(url.absoluteString)")
                }
            }
            readiness.setModelTerminal(true)
        }
        .accessibilityIdentifier("media.viewer")
    }

    @ViewBuilder
    private func mediaPage(_ attachment: MissCatNoteAttachment) -> some View {
        switch attachment.kind {
        case .image, .animatedImage:
            MissCatTrackedRemoteImage(
                url: attachment.url,
                key: attachment.url.map { "media:\($0.absoluteString)" } ?? "",
                palette: .legacyDark,
                fallbackSymbol: "photo",
                contentMode: .fit,
                readiness: readiness
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .video, .audio:
            if let url = attachment.url {
                MissCatMediaPlayer(url: url, kind: attachment.kind, readiness: readiness)
            } else {
                mediaFallback(attachment)
            }
        case .other:
            mediaFallback(attachment)
        }
    }

    private func mediaFallback(_ attachment: MissCatNoteAttachment) -> some View {
        VStack(spacing: 14) {
            Image(systemName: attachment.kind == .audio ? "waveform" : "doc")
                .font(.system(size: 48))
            Text(attachment.name).font(.system(size: 14))
        }
        .foregroundStyle(.white)
    }

    private var pageLabel: String {
        let index = attachments.firstIndex(where: { $0.id == selectedID }) ?? 0
        return "\(index + 1) / \(max(attachments.count, 1))"
    }
}

private struct MissCatMediaPlayer: View {
    @State private var player: AVPlayer
    let url: URL
    let kind: MissCatAttachmentKind
    let readiness: MissCatNoteVisualReadiness

    init(url: URL, kind: MissCatAttachmentKind, readiness: MissCatNoteVisualReadiness) {
        self.url = url
        self.kind = kind
        self.readiness = readiness
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        Group {
            if kind == .audio {
                VStack(spacing: 18) {
                    Image(systemName: "waveform.circle.fill").font(.system(size: 76))
                    VideoPlayer(player: player).frame(height: 70)
                }
                .foregroundStyle(.white)
            } else {
                VideoPlayer(player: player)
            }
        }
        .onAppear {
            readiness.register("media:\(url.absoluteString)")
            readiness.complete("media:\(url.absoluteString)")
        }
        .onDisappear { player.pause() }
    }
}
