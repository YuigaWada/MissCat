import AVKit
import SwiftUI
import UIKit

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

public struct MissCatURLPreviewCard: View {
    @Environment(\.openURL) private var openURL
    @StateObject private var store: MissCatURLPreviewStore

    private let sourceURL: URL
    private let palette: MissCatVisualPalette
    private let readiness: MissCatNoteVisualReadiness?
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
        .accessibilityIdentifier("note.url-preview")
        .onAppear {
            readiness?.register(requestKey)
            store.load()
        }
        .onChange(of: store.phase) { _, phase in
            switch phase {
            case let .loaded(preview):
                if let imageURL = preview.imageURL {
                    readiness?.register(imageKey(imageURL))
                }
                readiness?.complete(requestKey)
            case .failed:
                readiness?.complete(requestKey)
            case .idle, .loading:
                break
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
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(preview.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.text)
                        .lineLimit(2)
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
                .padding(10)
            }
            .frame(minHeight: 86)
            .background(palette.surface)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(preview.title)。リンクを開く")
        .accessibilityIdentifier("note.url-preview.content")
    }

    private func failureCard(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
            VStack(alignment: .leading, spacing: 3) {
                Text("リンクを表示できません")
                    .font(.system(size: 12, weight: .semibold))
                Text(message).font(.system(size: 10)).lineLimit(2)
            }
            Spacer(minLength: 4)
            Button("再試行") { store.retry() }
                .font(.system(size: 11, weight: .semibold))
                .accessibilityIdentifier("note.url-preview.retry")
        }
        .foregroundStyle(palette.strong)
        .padding(12)
        .background(palette.surface)
        .accessibilityIdentifier("note.url-preview.failure")
    }

    private func imageKey(_ url: URL) -> String { "url-preview-image:\(url.absoluteString)" }
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
