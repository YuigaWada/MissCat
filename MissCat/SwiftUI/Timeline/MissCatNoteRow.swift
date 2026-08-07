import SwiftUI

public struct MissCatNoteRow: View {
    @Environment(\.openURL) private var openURL
    public let note: MissCatNote
    public let palette: MissCatVisualPalette
    public let expandsContentWarning: Bool
    public let showsThreadConnector: Bool
    public let relativeDateReference: Date
    public let onOpenUser: (String) -> Void
    public let onOpenNote: (String) -> Void
    public let onOpenAttachment: (MissCatNoteAttachment) -> Void
    public let onOpenHashtag: (String) -> Void
    public let onReply: (String) -> Void
    public let onRenote: (String) -> Void
    public let onChooseReaction: (String) -> Void
    public let onToggleReaction: (String, String) -> Void
    public let onToggleFavorite: (String) -> Void
    public let onVote: (String, Int) -> Void
    public let onDelete: (String) -> Void
    public let onMuteUser: (String) -> Void
    public let onOverflowAction: (MissCatNoteOverflowAction) -> Void
    public let contextRepository: (any MissCatNoteContextRepository)?
    public let readiness: MissCatNoteVisualReadiness?
    public let presentsMediaInternally: Bool

    @State private var isContentWarningExpanded: Bool
    @State private var revealedSensitiveAttachmentIDs = Set<String>()
    @State private var selectedAttachment: MissCatNoteAttachment?
    @State private var showsOverflowActions = false

    public init(
        note: MissCatNote,
        palette: MissCatVisualPalette = .legacyLight,
        expandsContentWarning: Bool = false,
        showsThreadConnector: Bool = false,
        relativeDateReference: Date = Date(),
        onOpenUser: @escaping (String) -> Void = { _ in },
        onOpenNote: @escaping (String) -> Void = { _ in },
        onOpenAttachment: @escaping (MissCatNoteAttachment) -> Void = { _ in },
        onOpenHashtag: @escaping (String) -> Void = { _ in },
        onReply: @escaping (String) -> Void = { _ in },
        onRenote: @escaping (String) -> Void = { _ in },
        onChooseReaction: @escaping (String) -> Void = { _ in },
        onToggleReaction: @escaping (String, String) -> Void = { _, _ in },
        onToggleFavorite: @escaping (String) -> Void = { _ in },
        onVote: @escaping (String, Int) -> Void = { _, _ in },
        onDelete: @escaping (String) -> Void = { _ in },
        onMuteUser: @escaping (String) -> Void = { _ in },
        onOverflowAction: @escaping (MissCatNoteOverflowAction) -> Void = { _ in },
        contextRepository: (any MissCatNoteContextRepository)? = nil,
        readiness: MissCatNoteVisualReadiness? = nil,
        presentsMediaInternally: Bool = true
    ) {
        self.note = note
        self.palette = palette
        self.expandsContentWarning = expandsContentWarning
        self.showsThreadConnector = showsThreadConnector
        self.relativeDateReference = relativeDateReference
        self.onOpenUser = onOpenUser
        self.onOpenNote = onOpenNote
        self.onOpenAttachment = onOpenAttachment
        self.onOpenHashtag = onOpenHashtag
        self.onReply = onReply
        self.onRenote = onRenote
        self.onChooseReaction = onChooseReaction
        self.onToggleReaction = onToggleReaction
        self.onToggleFavorite = onToggleFavorite
        self.onVote = onVote
        self.onDelete = onDelete
        self.onMuteUser = onMuteUser
        self.onOverflowAction = onOverflowAction
        self.contextRepository = contextRepository
        self.readiness = readiness
        self.presentsMediaInternally = presentsMediaInternally
        _isContentWarningExpanded = State(initialValue: expandsContentWarning || note.cw == nil)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let renotedBy = note.renotedBy {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.2.squarepath")
                    Text("\(renotedBy.name)さんがRenoteしました")
                        .lineLimit(1)
                }
                .font(.system(size: 12))
                .foregroundStyle(palette.strong)
                .padding(.leading, 80)
                .padding(.top, 7)
                .accessibilityIdentifier("note.\(note.id).renote-attribution")
            }

            HStack(alignment: .top, spacing: 10) {
                avatarColumn

                VStack(alignment: .leading, spacing: 8) {
                    authorHeader
                    noteContent

                    if !note.reactions.isEmpty {
                        reactionChips
                    }

                    actionBar
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 20)
            .padding(.trailing, 20)
            .padding(.top, note.renotedBy == nil ? 13 : 6)
            .padding(.bottom, 1)
        }
        .background(palette.base)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(hex: "DBDBDB"))
                .frame(height: MissCatLegacyMetrics.hairlineWidth)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("note.row.\(note.id)")
        .onAppear { registerRemoteAssets() }
        .fullScreenCover(item: $selectedAttachment) { attachment in
            MissCatMediaViewer(attachments: note.attachments, selectedID: attachment.id)
        }
    }

    private var avatarColumn: some View {
        VStack(spacing: 7) {
            Button {
                onOpenUser(note.author.id)
            } label: {
                MissCatTrackedRemoteImage(
                    url: note.author.avatarURL,
                    key: assetKey(note.author.avatarURL),
                    palette: palette,
                    fallbackSymbol: "person.fill",
                    contentMode: .fill,
                    readiness: readiness
                )
                .frame(width: 50, height: 50)
                .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(note.author.name)のプロフィール")
            .accessibilityIdentifier("note.\(note.id).author-avatar")

            if showsThreadConnector {
                Rectangle()
                    .fill(palette.muted)
                    .frame(width: 3)
                    .frame(maxHeight: .infinity)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: 50)
    }

    private var authorHeader: some View {
        Button {
            onOpenUser(note.author.id)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(note.author.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.text)
                    .lineLimit(1)

                if note.author.isCat {
                    Image(systemName: "cat.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.accent)
                        .accessibilityLabel("猫")
                }

                Text(note.author.acct)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.strong)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if let createdAt = note.createdAt {
                    Text(Self.relativeDateFormatter.localizedString(for: createdAt, relativeTo: relativeDateReference))
                        .font(.system(size: 13))
                        .foregroundStyle(palette.strong)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("note.\(note.id).author")
    }

    @ViewBuilder
    private var noteContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let cw = note.cw {
                VStack(alignment: .leading, spacing: 6) {
                    Text(cw)
                        .font(.system(size: 14))
                        .foregroundStyle(palette.text)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(isContentWarningExpanded ? "隠す" : "もっと見る") {
                        isContentWarningExpanded.toggle()
                    }
                    .font(.system(size: 13, weight: .medium))
                    .buttonStyle(.bordered)
                    .tint(palette.strong)
                    .accessibilityIdentifier("note.\(note.id).cw-toggle")
                }
            }

            if isContentWarningExpanded {
                if !note.text.isEmpty {
                    Text(MissCatNativeMFMRenderer.render(note.text))
                        .font(.system(size: 14))
                        .foregroundStyle(palette.text)
                        .tint(palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("note.\(note.id).body")
                        .onTapGesture { onOpenNote(note.noteID) }
                }

                if let contextRepository {
                    ForEach(MissCatNativeMFMRenderer.previewURLs(in: note.text), id: \.absoluteString) { url in
                        MissCatURLPreviewCard(
                            sourceURL: url,
                            repository: contextRepository,
                            palette: palette,
                            readiness: readiness
                        )
                    }
                }

                if !note.attachments.isEmpty {
                    attachmentGrid(note.attachments)
                }

                if let poll = note.poll {
                    pollView(poll)
                }

                if let quotedNote = note.quotedNote {
                    quotedNoteView(quotedNote)
                }
            }

            if !note.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(note.tags, id: \.self) { tag in
                            Button("#\(tag)") { onOpenHashtag(tag) }
                                .font(.system(size: 13))
                                .buttonStyle(.plain)
                                .foregroundStyle(palette.accent)
                                .accessibilityIdentifier("note.\(note.id).hashtag.\(tag)")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func attachmentGrid(_ attachments: [MissCatNoteAttachment]) -> some View {
        if attachments.allSatisfy({ $0.url == nil && $0.thumbnailURL == nil }) {
            unavailableAttachmentGrid(attachments)
        } else {
            let columns: [GridItem] = if attachments.count == 1 {
                [GridItem(.flexible(), spacing: 4)]
            } else if attachments.count == 3 {
                Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)
            } else {
                [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)]
            }

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(attachments.prefix(4))) { attachment in
                    attachmentView(attachment, single: attachments.count == 1)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .accessibilityIdentifier("note.\(note.id).attachments")
        }
    }

    private func unavailableAttachmentGrid(_ attachments: [MissCatNoteAttachment]) -> some View {
        ZStack {
            palette.surface

            Image(systemName: "photo")
                .font(.system(size: 20))
                .foregroundStyle(palette.strong)

            HStack(spacing: -8) {
                Image(systemName: "photo")
                Image(systemName: "play.circle.fill")
            }
            .font(.system(size: 20))
            .foregroundStyle(palette.strong)
            .offset(x: 18)
            .frame(maxWidth: .infinity, alignment: .trailing)

            HStack(spacing: 0) {
                ForEach(Array(attachments.prefix(4))) { attachment in
                    Button { handleAttachmentTap(attachment) } label: {
                        Color.clear.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(attachment.name)
                    .accessibilityIdentifier("note.\(note.id).attachment.\(attachment.id)")
                }
            }
        }
        .frame(height: 104)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .accessibilityIdentifier("note.\(note.id).attachments")
    }

    private func attachmentView(_ attachment: MissCatNoteAttachment, single: Bool) -> some View {
        let sensitiveIsHidden = attachment.isSensitive && !revealedSensitiveAttachmentIDs.contains(attachment.id)

        return Button { handleAttachmentTap(attachment) } label: {
            ZStack {
                MissCatTrackedRemoteImage(
                    url: attachment.thumbnailURL ?? attachment.url,
                    key: assetKey(attachment.thumbnailURL ?? attachment.url),
                    palette: palette,
                    fallbackSymbol: Self.symbol(for: attachment.kind),
                    contentMode: .fill,
                    readiness: readiness
                )
                .frame(maxWidth: .infinity)
                .frame(height: single ? 210 : note.attachments.count == 3 ? 104 : 130)
                .clipped()
                .blur(radius: sensitiveIsHidden ? 18 : 0)

                if attachment.url != nil,
                   attachment.kind == .video || attachment.kind == .audio || attachment.kind == .animatedImage {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 38))
                        .foregroundStyle(.white.opacity(0.8))
                        .shadow(radius: 2)
                }

                if sensitiveIsHidden {
                    Rectangle().fill(.black.opacity(0.42))
                    Text("閲覧注意\nタップで表示")
                        .multilineTextAlignment(.center)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color(hex: "FFFF8F"))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(sensitiveIsHidden ? "閲覧注意。タップで表示" : attachment.name)
        .accessibilityIdentifier("note.\(note.id).attachment.\(attachment.id)")
    }

    private func handleAttachmentTap(_ attachment: MissCatNoteAttachment) {
        if attachment.isSensitive && !revealedSensitiveAttachmentIDs.contains(attachment.id) {
            revealedSensitiveAttachmentIDs.insert(attachment.id)
        } else {
            MissCatNoteMediaTapRouter.route(
                attachment,
                presentNatively: { selectedAttachment = $0 },
                legacyPresentation: onOpenAttachment
            )
        }
    }

    private func quotedNoteView(_ quoted: MissCatQuotedNote) -> some View {
        Button {
            onOpenNote(quoted.noteID)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                MissCatTrackedRemoteImage(
                    url: quoted.author.avatarURL,
                    key: assetKey(quoted.author.avatarURL),
                    palette: palette,
                    fallbackSymbol: "person.fill",
                    contentMode: .fill,
                    readiness: readiness
                )
                .frame(width: 32, height: 32)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(quoted.author.name).fontWeight(.semibold)
                        Text(quoted.author.acct).foregroundStyle(palette.strong)
                    }
                    .font(.system(size: 12))
                    .lineLimit(1)

                    if let cw = quoted.cw {
                        Text(cw).fontWeight(.medium)
                    } else {
                        Text(quoted.text)
                    }
                }
                .font(.system(size: 13))
                .foregroundStyle(palette.text)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(palette.surface)
            .overlay {
                RoundedRectangle(cornerRadius: 5).stroke(palette.border, lineWidth: 0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("引用ノート")
        .accessibilityIdentifier("note.\(note.id).quote")
    }

    private func pollView(_ poll: MissCatPoll) -> some View {
        VStack(spacing: 6) {
            ForEach(poll.choices) { choice in
                Button {
                    onVote(note.noteID, choice.id)
                } label: {
                    HStack {
                        Image(systemName: choice.isVoted ? "checkmark.circle.fill" : "circle")
                        Text(choice.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(choice.votes)")
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(choice.isVoted ? palette.accent : palette.text)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 36)
                    .background(palette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("note.\(note.id).poll.\(choice.id)")
            }
        }
        .accessibilityIdentifier("note.\(note.id).poll")
    }

    private var reactionChips: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 5)], alignment: .leading, spacing: 5) {
            ForEach(note.reactions) { reaction in
                Button {
                    onToggleReaction(note.noteID, reaction.name)
                } label: {
                    HStack(spacing: 4) {
                        Text(reaction.name)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                        Text("\(reaction.count)")
                    }
                    .font(.system(size: 13))
                    .padding(.horizontal, 7)
                    .frame(width: 72, height: 28)
                    .foregroundStyle(reaction.isMine ? .white : palette.text)
                    .background(reaction.isMine ? palette.accent : palette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("note.\(note.id).reaction.\(reaction.name)")
            }
        }
        .accessibilityIdentifier("note.\(note.id).reactions")
    }

    private var actionBar: some View {
        HStack(spacing: 0) {
            actionButton(
                symbol: "arrowshape.turn.up.left",
                count: note.repliesCount,
                label: "返信",
                identifier: "reply"
            ) { onReply(note.noteID) }

            actionButton(
                symbol: "arrow.2.squarepath",
                count: note.renoteCount,
                label: "Renote",
                identifier: "renote"
            ) { onRenote(note.noteID) }

            actionButton(
                symbol: "face.smiling",
                count: nil,
                label: "リアクション",
                identifier: "reaction"
            ) { onChooseReaction(note.noteID) }

            overflowMenu
        }
        .frame(height: 40)
        .foregroundStyle(palette.strong)
        .accessibilityElement(children: .contain)
    }

    private var overflowMenu: some View {
        Button { showsOverflowActions = true } label: {
            Image(systemName: note.isFavorite ? "star.fill" : "ellipsis")
                .font(.system(size: 20))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("その他")
        .accessibilityIdentifier("note.\(note.id).action.overflow")
        .fullScreenCover(isPresented: $showsOverflowActions) {
            MissCatNoteOverflowPanel(
                note: note,
                palette: palette,
                permalink: contextRepository?.notePermalink(noteID: note.noteID),
                isOwnNote: contextRepository?.currentServerUserID == note.author.id,
                onFavorite: {
                    onToggleFavorite(note.noteID)
                    onOverflowAction(note.isFavorite ? .unfavorite : .favorite)
                },
                onCopyLink: { permalink in
                    UIPasteboard.general.string = permalink.absoluteString
                    onOverflowAction(.copyLink)
                },
                onOpenBrowser: { permalink in
                    openURL(permalink)
                    onOverflowAction(.openInBrowser)
                },
                onDelete: {
                    onDelete(note.noteID)
                    onOverflowAction(.delete)
                },
                onMute: {
                    onMuteUser(note.author.id)
                    onOverflowAction(.muteUser)
                }
            )
        }
    }

    private func actionButton(
        symbol: String,
        count: Int?,
        label: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 20))
                if let count, count > 0 {
                    Text("\(count)").font(.system(size: 12))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier("note.\(note.id).action.\(identifier)")
    }

    private static func symbol(for kind: MissCatAttachmentKind) -> String {
        switch kind {
        case .image, .animatedImage: "photo"
        case .video: "play.circle.fill"
        case .audio: "waveform"
        case .other: "doc"
        }
    }

    private func registerRemoteAssets() {
        [note.author.avatarURL, note.quotedNote?.author.avatarURL]
            .compactMap { $0 }
            .forEach { readiness?.register(assetKey($0)) }
        note.attachments.compactMap { $0.thumbnailURL ?? $0.url }.forEach {
            readiness?.register(assetKey($0))
        }
    }

    private func assetKey(_ url: URL?) -> String {
        url.map { "note-asset:\($0.absoluteString)" } ?? ""
    }

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}

private struct MissCatNoteOverflowPanel: View {
    @Environment(\.dismiss) private var dismiss

    let note: MissCatNote
    let palette: MissCatVisualPalette
    let permalink: URL?
    let isOwnNote: Bool
    let onFavorite: () -> Void
    let onCopyLink: (URL) -> Void
    let onOpenBrowser: (URL) -> Void
    let onDelete: () -> Void
    let onMute: () -> Void

    var body: some View {
        MissCatLegacyBottomOverlay(
            height: MissCatLegacyMetrics.noteOverflowPanelHeight,
            palette: palette
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text("その他")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.text)

                actionButton(
                    note.isFavorite ? "お気に入り解除" : "お気に入り",
                    symbol: "star",
                    identifier: "note.\(note.id).overflow.favorite"
                ) { onFavorite() }

                if let permalink {
                    actionButton(
                        "リンクをコピー",
                        symbol: "doc.on.doc",
                        identifier: "note.\(note.id).overflow.copy-link"
                    ) { onCopyLink(permalink) }
                    actionButton(
                        "ブラウザで開く",
                        symbol: "safari",
                        identifier: "note.\(note.id).overflow.browser"
                    ) { onOpenBrowser(permalink) }
                }

                if isOwnNote {
                    actionButton(
                        "削除",
                        symbol: "trash",
                        role: .destructive,
                        identifier: "note.\(note.id).overflow.delete",
                        action: onDelete
                    )
                } else {
                    actionButton(
                        "このユーザーをミュート",
                        symbol: "speaker.slash",
                        role: .destructive,
                        identifier: "note.\(note.id).overflow.mute",
                        action: onMute
                    )
                }

                Spacer(minLength: 0)
            }
        }
    }

    private func actionButton(
        _ title: String,
        symbol: String,
        role: ButtonRole? = nil,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role) {
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { action() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol).frame(width: 25)
                Text(title)
                Spacer()
            }
            .font(.system(size: 16))
            .frame(height: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(role == .destructive ? Color.red : palette.text)
        .accessibilityIdentifier(identifier)
    }
}

enum MissCatNoteMediaPresentationOwner: Equatable {
    case nativeSwiftUIPager
}

/// Migrated note rows own media presentation. The legacy callback remains in
/// the navigation action value for source compatibility while routes move in
/// batches, but it must never start Agrume for a SwiftUI row.
enum MissCatNoteMediaTapRouter {
    @discardableResult
    static func route(
        _ attachment: MissCatNoteAttachment,
        presentNatively: (MissCatNoteAttachment) -> Void,
        legacyPresentation: (MissCatNoteAttachment) -> Void
    ) -> MissCatNoteMediaPresentationOwner {
        presentNatively(attachment)
        _ = legacyPresentation
        return .nativeSwiftUIPager
    }
}
