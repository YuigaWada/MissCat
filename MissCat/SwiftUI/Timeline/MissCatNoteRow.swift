import SwiftUI

public struct MissCatNoteRow: View {
    @Environment(\.openURL) private var openURL
    public let note: MissCatNote
    public let palette: MissCatVisualPalette
    public let expandsContentWarning: Bool
    public let showsThreadConnector: Bool
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

    @State private var isContentWarningExpanded: Bool
    @State private var revealedSensitiveAttachmentIDs = Set<String>()
    @State private var selectedAttachment: MissCatNoteAttachment?

    public init(
        note: MissCatNote,
        palette: MissCatVisualPalette = .legacyLight,
        expandsContentWarning: Bool = false,
        showsThreadConnector: Bool = false,
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
        readiness: MissCatNoteVisualReadiness? = nil
    ) {
        self.note = note
        self.palette = palette
        self.expandsContentWarning = expandsContentWarning
        self.showsThreadConnector = showsThreadConnector
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
                .fill(palette.border)
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
                    Text(Self.relativeDateFormatter.localizedString(for: createdAt, relativeTo: Date()))
                        .font(.system(size: 13))
                        .foregroundStyle(palette.strong)
                        .lineLimit(1)
                }
            }
            .frame(height: 27)
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
                        .tint(palette.accent)
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

    private func attachmentGrid(_ attachments: [MissCatNoteAttachment]) -> some View {
        let columns = attachments.count == 1
            ? [GridItem(.flexible(), spacing: 4)]
            : [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)]

        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Array(attachments.prefix(4))) { attachment in
                attachmentView(attachment, single: attachments.count == 1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .accessibilityIdentifier("note.\(note.id).attachments")
    }

    private func attachmentView(_ attachment: MissCatNoteAttachment, single: Bool) -> some View {
        let sensitiveIsHidden = attachment.isSensitive && !revealedSensitiveAttachmentIDs.contains(attachment.id)

        return Button {
            if sensitiveIsHidden {
                revealedSensitiveAttachmentIDs.insert(attachment.id)
            } else {
                selectedAttachment = attachment
                onOpenAttachment(attachment)
            }
        } label: {
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
                .frame(height: single ? 210 : 130)
                .clipped()
                .blur(radius: sensitiveIsHidden ? 18 : 0)

                if attachment.kind == .video || attachment.kind == .audio || attachment.kind == .animatedImage {
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
                    .frame(minHeight: 28)
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
                symbol: note.myReaction == nil ? "face.smiling" : "face.smiling.inverse",
                count: nil,
                label: "リアクション",
                identifier: "reaction"
            ) { onChooseReaction(note.noteID) }

            overflowMenu
        }
        .frame(height: 40)
        .foregroundStyle(palette.strong)
        .accessibilityIdentifier("note.\(note.id).actions")
    }

    private var overflowMenu: some View {
        Menu {
            Button {
                onToggleFavorite(note.noteID)
                onOverflowAction(note.isFavorite ? .unfavorite : .favorite)
            } label: {
                Label(note.isFavorite ? "お気に入り解除" : "お気に入り", systemImage: "star")
            }
            .accessibilityIdentifier("note.\(note.id).overflow.favorite")

            if let permalink = contextRepository?.notePermalink(noteID: note.noteID) {
                Button {
                    UIPasteboard.general.string = permalink.absoluteString
                    onOverflowAction(.copyLink)
                } label: { Label("リンクをコピー", systemImage: "doc.on.doc") }
                    .accessibilityIdentifier("note.\(note.id).overflow.copy-link")

                Button {
                    openURL(permalink)
                    onOverflowAction(.openInBrowser)
                } label: { Label("ブラウザで開く", systemImage: "safari") }
                    .accessibilityIdentifier("note.\(note.id).overflow.browser")
            }

            if contextRepository?.currentServerUserID == note.author.id {
                Button(role: .destructive) {
                    onDelete(note.noteID)
                    onOverflowAction(.delete)
                } label: { Label("削除", systemImage: "trash") }
                    .accessibilityIdentifier("note.\(note.id).overflow.delete")
            } else {
                Button(role: .destructive) {
                    onMuteUser(note.author.id)
                    onOverflowAction(.muteUser)
                } label: { Label("このユーザーをミュート", systemImage: "speaker.slash") }
                    .accessibilityIdentifier("note.\(note.id).overflow.mute")
            }
        } label: {
            Image(systemName: note.isFavorite ? "star.fill" : "ellipsis")
                .font(.system(size: 15, weight: .bold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityLabel("その他")
        .accessibilityIdentifier("note.\(note.id).action.overflow")
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
                    .font(.system(size: 15, weight: .bold))
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
        case .video: "video"
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
