import SwiftUI

public struct MissCatFeedReactionRequest {
    public let noteID: String
    public let existingReactions: [MissCatReaction]
    public let selectReaction: (String) -> Void

    public init(
        noteID: String,
        existingReactions: [MissCatReaction],
        selectReaction: @escaping (String) -> Void
    ) {
        self.noteID = noteID
        self.existingReactions = existingReactions
        self.selectReaction = selectReaction
    }
}

public struct MissCatFeedNavigationActions {
    public var openUser: (String) -> Void
    public var openNote: (String) -> Void
    public var openAttachment: (MissCatNoteAttachment) -> Void
    public var openHashtag: (String) -> Void
    public var openMention: (String) -> Void
    public var reply: (String) -> Void
    public var chooseReaction: (MissCatFeedReactionRequest) -> Void
    public var share: (String) -> Void

    public init(
        openUser: @escaping (String) -> Void = { _ in },
        openNote: @escaping (String) -> Void = { _ in },
        openAttachment: @escaping (MissCatNoteAttachment) -> Void = { _ in },
        openHashtag: @escaping (String) -> Void = { _ in },
        openMention: @escaping (String) -> Void = { _ in },
        reply: @escaping (String) -> Void = { _ in },
        chooseReaction: @escaping (MissCatFeedReactionRequest) -> Void = { _ in },
        share: @escaping (String) -> Void = { _ in }
    ) {
        self.openUser = openUser
        self.openNote = openNote
        self.openAttachment = openAttachment
        self.openHashtag = openHashtag
        self.openMention = openMention
        self.reply = reply
        self.chooseReaction = chooseReaction
        self.share = share
    }
}

/// Shared native SwiftUI feed renderer. Timeline, saved/search/tag results and the
/// thread screen use the same store and row behavior instead of seven independent stacks.
public struct MissCatFeedView: View {
    @StateObject private var store: MissCatFeedStore
    @Binding private var scrollPositionID: String?
    @State private var presentedSheet: PresentedSheet?
    @State private var pendingRenote: MissCatNote?
    @State private var pendingDestructiveAction: DestructiveAction?
    @State private var pendingReport: MissCatNote?
    @State private var reportComment = ""

    private let palette: MissCatVisualPalette
    private let emptyTitle: String
    private let navigationActions: MissCatFeedNavigationActions
    private let scrollToTopTrigger: Int
    private let relativeDateReference: Date
    private let visualReadyIdentifier: String?
    private let allowsLoadingVisualReady: Bool
    private let contextRepository: (any MissCatNoteContextRepository)?

    public init(
        source: MissCatFeedSource,
        repository: MissCatFeedRepository,
        accountScope: MissCatShellAccountScope? = nil,
        palette: MissCatVisualPalette = .legacyLight,
        emptyTitle: String = "ノートがありません",
        scrollPositionID: Binding<String?> = .constant(nil),
        scrollToTopTrigger: Int = 0,
        relativeDateReference: Date = Date(),
        visualReadyIdentifier: String? = nil,
        allowsLoadingVisualReady: Bool = false,
        navigationActions: MissCatFeedNavigationActions = .init()
    ) {
        _store = StateObject(
            wrappedValue: MissCatFeedStore(
                source: source,
                repository: repository,
                accountScope: accountScope
            )
        )
        _scrollPositionID = scrollPositionID
        contextRepository = repository as? any MissCatNoteContextRepository
        self.palette = palette
        self.emptyTitle = emptyTitle
        self.scrollToTopTrigger = scrollToTopTrigger
        self.relativeDateReference = relativeDateReference
        self.visualReadyIdentifier = visualReadyIdentifier
        self.allowsLoadingVisualReady = allowsLoadingVisualReady
        self.navigationActions = navigationActions
    }

    public var body: some View {
        ZStack {
            palette.base.ignoresSafeArea()

            switch store.phase {
            case .idle, .loading:
                loadingView
            case let .failed(message):
                failureView(message)
            case .empty:
                refreshableEmptyView
            case .loaded:
                feedScrollView
            }
        }
        .task { await store.loadInitial() }
        .onDisappear { store.cancelAllFeedTasks() }
        .onChange(of: scrollToTopTrigger) { _, generation in
            guard generation > 0, let firstID = store.notes.first?.id else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                scrollPositionID = firstID
            }
        }
        .overlay(alignment: .top) {
            VStack(spacing: 6) {
                if store.isRefreshing {
                    HStack(spacing: 8) {
                        ProgressView().tint(palette.accent)
                        Text("更新中…")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(palette.text)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(palette.surface.opacity(0.98), in: Capsule())
                    .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("feed.refreshing")
                }

                if let message = store.actionErrorMessage {
                    MissCatFeedStatusBanner(
                        message: message,
                        palette: palette,
                        onDismiss: store.dismissActionError
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
        }
        .overlay(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                Text("refresh-completed")
                    .font(.system(size: 1))
                    .opacity(0.01)
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier("feed.refresh.completed")
                    .accessibilityValue("\(store.refreshCompletionGeneration)")

                if isVisuallyStable, let visualReadyIdentifier {
                    Text("visual-ready")
                        .font(.system(size: 1))
                        .opacity(0.01)
                        .frame(width: 1, height: 1)
                        .accessibilityIdentifier(visualReadyIdentifier)
                        .accessibilityValue(scrollPositionID ?? "top")
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.actionErrorMessage)
        .fullScreenCover(item: $presentedSheet) { sheet in
            switch sheet.kind {
            case .reaction:
                if let contextRepository {
                    MissCatReactionPickerView(
                        noteID: sheet.note.noteID,
                        existingReactions: sheet.note.reactions,
                        repository: contextRepository,
                        palette: palette
                    ) { noteID, reaction in
                        Task { await store.toggleReaction(noteID: noteID, reaction: reaction) }
                    }
                }
            case .reply:
                MissCatNoteComposeSheet(note: sheet.note, kind: .reply) {
                    presentedSheet = nil
                    Task { await store.refresh() }
                }
            case .quote:
                MissCatNoteComposeSheet(note: sheet.note, kind: .quote) {
                    presentedSheet = nil
                    Task { await store.refresh() }
                }
            }
        }
        .confirmationDialog(
            "Renote",
            isPresented: Binding(
                get: { pendingRenote != nil },
                set: { if !$0 { pendingRenote = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let note = pendingRenote {
                Button("Renote") {
                    pendingRenote = nil
                    Task { await store.renote(noteID: note.noteID) }
                }
                .accessibilityIdentifier("timeline.renote.confirm")
                Button("引用Renote") {
                    pendingRenote = nil
                    presentedSheet = PresentedSheet(kind: .quote, note: note)
                }
                .accessibilityIdentifier("timeline.renote.quote")
            }
            Button("キャンセル", role: .cancel) { pendingRenote = nil }
        }
        .alert(
            pendingDestructiveAction?.title ?? "確認",
            isPresented: Binding(
                get: { pendingDestructiveAction != nil },
                set: { if !$0 { pendingDestructiveAction = nil } }
            ),
            presenting: pendingDestructiveAction
        ) { action in
            Button(action.actionTitle, role: .destructive) {
                pendingDestructiveAction = nil
                Task {
                    switch action {
                    case let .delete(note): await store.delete(noteID: note.noteID)
                    case let .mute(note): await store.muteUser(userID: note.author.id)
                    case let .block(note): await store.blockUser(userID: note.author.id)
                    }
                }
            }
            .accessibilityIdentifier("timeline.destructive.confirm")
            Button("キャンセル", role: .cancel) { pendingDestructiveAction = nil }
        } message: { action in
            Text(action.message)
        }
        .alert(
            "このユーザーを通報",
            isPresented: Binding(
                get: { pendingReport != nil },
                set: {
                    if !$0 {
                        pendingReport = nil
                        reportComment = ""
                    }
                }
            ),
            presenting: pendingReport
        ) { note in
            TextField("通報理由（必須）", text: $reportComment)
                .accessibilityIdentifier("timeline.report.comment")
                .onChange(of: reportComment) { _, value in
                    if value.count > MissCatReportComment.maximumLength {
                        reportComment = MissCatReportComment.clamped(value)
                    }
                }
            Button("通報", role: .destructive) {
                let comment = reportComment
                pendingReport = nil
                reportComment = ""
                Task { await store.reportUser(userID: note.author.id, comment: comment) }
            }
            .disabled(MissCatReportComment.normalized(reportComment) == nil)
            .accessibilityIdentifier("timeline.report.confirm")
            Button("キャンセル", role: .cancel) {
                pendingReport = nil
                reportComment = ""
            }
        } message: { note in
            Text("@\(note.author.username) を運営に通報します。")
        }
        .accessibilityElement(children: .contain)
        .overlay(alignment: .topLeading) {
            MissCatFeedAccessibilityMarker(identifier: "feed.\(store.source.accessibilityName)")
        }
    }

    private var feedScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(store.notes.enumerated()), id: \.element.id) { index, note in
                    MissCatNoteRow(
                        note: note,
                        palette: palette,
                        expandsContentWarning: store.isThreadRoot(note),
                        showsThreadConnector: isThreadNote(at: index),
                        relativeDateReference: relativeDateReference,
                        onOpenUser: navigationActions.openUser,
                        onOpenNote: navigationActions.openNote,
                        onOpenAttachment: navigationActions.openAttachment,
                        onOpenHashtag: navigationActions.openHashtag,
                        onOpenMention: openMention,
                        onReply: { _ in
                            if contextRepository != nil {
                                presentedSheet = PresentedSheet(kind: .reply, note: note)
                            } else {
                                navigationActions.reply(note.noteID)
                            }
                        },
                        onRenote: { _ in pendingRenote = note },
                        onChooseReaction: { noteID in
                            if contextRepository != nil {
                                presentedSheet = PresentedSheet(kind: .reaction, note: note)
                            } else {
                                navigationActions.chooseReaction(
                                    MissCatFeedReactionRequest(
                                        noteID: noteID,
                                        existingReactions: note.reactions,
                                        selectReaction: { reaction in
                                            Task {
                                                await store.toggleReaction(
                                                    noteID: noteID,
                                                    reaction: reaction
                                                )
                                            }
                                        }
                                    )
                                )
                            }
                        },
                        onToggleReaction: { noteID, reaction in
                            Task { await store.toggleReaction(noteID: noteID, reaction: reaction) }
                        },
                        onToggleFavorite: { noteID in
                            Task { await store.toggleFavorite(noteID: noteID) }
                        },
                        onVote: { noteID, choice in
                            Task { await store.vote(noteID: noteID, choice: choice) }
                        },
                        onDelete: { _ in pendingDestructiveAction = .delete(note) },
                        onMuteUser: { _ in pendingDestructiveAction = .mute(note) },
                        onBlockUser: { _ in pendingDestructiveAction = .block(note) },
                        onReportUser: { _ in
                            reportComment = ""
                            pendingReport = note
                        },
                        onShare: navigationActions.share,
                        contextRepository: contextRepository
                    )
                    .id(note.id)
                    .task {
                        await store.loadNextPageIfNeeded(currentNoteID: note.id)
                    }
                }

                if store.isLoadingNextPage {
                    ProgressView()
                        .tint(palette.accent)
                        .frame(height: 52)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("さらに読み込み中")
                        .accessibilityIdentifier("feed.pagination.loading")
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollPosition(id: $scrollPositionID, anchor: .top)
        .refreshable { await store.refresh() }
        .background(palette.base)
        .accessibilityIdentifier("feed.scroll")
        .accessibilityValue(store.isRealtimeConnected ? "realtime-connected" : "realtime-disconnected")
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView().tint(palette.accent)
            Text("読み込み中…")
                .font(.system(size: 14))
                .foregroundStyle(palette.strong)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("feed.loading")
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label(emptyTitle, systemImage: "text.bubble")
        } description: {
            Text("下に引っ張ると更新できます")
        }
        .foregroundStyle(palette.strong)
        .accessibilityIdentifier("feed.empty")
    }

    private var refreshableEmptyView: some View {
        ScrollView {
            emptyView
                .frame(maxWidth: .infinity)
                .frame(minHeight: 360)
        }
        .scrollIndicators(.hidden)
        .refreshable { await store.refresh() }
        .accessibilityIdentifier("feed.empty.refreshable")
    }

    private func failureView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("読み込めませんでした", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("再試行") {
                Task { await store.retry() }
            }
            .buttonStyle(.borderedProminent)
            .tint(palette.accent)
            .accessibilityIdentifier("feed.retry")
        }
        .foregroundStyle(palette.strong)
        .accessibilityIdentifier("feed.failure")
    }

    private func isThreadNote(at index: Int) -> Bool {
        guard case .noteDetail = store.source else { return false }
        return index < store.notes.count - 1
    }

    private var isVisuallyStable: Bool {
        switch store.phase {
        case .loaded, .empty, .failed:
            true
        case .idle, .loading:
            allowsLoadingVisualReady
        }
    }

    private struct PresentedSheet: Identifiable {
        enum Kind: String { case reaction, reply, quote }
        let kind: Kind
        let note: MissCatNote
        var id: String { "\(kind.rawValue):\(note.noteID)" }
    }

    private func openMention(_ acct: String) {
        guard let contextRepository else {
            navigationActions.openMention(acct)
            return
        }
        Task {
            do {
                navigationActions.openUser(try await contextRepository.resolveMention(acct))
            } catch {
                navigationActions.openMention(acct)
            }
        }
    }

    private enum DestructiveAction {
        case delete(MissCatNote)
        case mute(MissCatNote)
        case block(MissCatNote)

        var title: String {
            switch self {
            case .delete: "ノートを削除しますか？"
            case .mute: "このユーザーをミュートしますか？"
            case .block: "このユーザーをブロックしますか？"
            }
        }

        var message: String {
            switch self {
            case .delete: "この操作は取り消せません。"
            case .mute: "このユーザーのノートは表示されなくなります。"
            case .block: "相互フォローが解除され、このユーザーとのやり取りが制限されます。"
            }
        }

        var actionTitle: String {
            switch self {
            case .delete: "削除"
            case .mute: "ミュート"
            case .block: "ブロック"
            }
        }
    }
}

public struct MissCatFeedStatusBanner: View {
    public let message: String
    public let palette: MissCatVisualPalette
    public let onDismiss: () -> Void

    public init(
        message: String,
        palette: MissCatVisualPalette = .legacyLight,
        onDismiss: @escaping () -> Void
    ) {
        self.message = message
        self.palette = palette
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.white)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("閉じる")
            .accessibilityIdentifier("feed.banner.dismiss")
        }
        .padding(.leading, 12)
        .padding(.trailing, 5)
        .padding(.vertical, 6)
        .background(palette.strong.opacity(0.96), in: RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("feed.banner.error")
    }
}

public struct MissCatSocialTimelineView: View {
    private let repository: MissCatFeedRepository
    private let palette: MissCatVisualPalette
    private let navigationActions: MissCatFeedNavigationActions

    public init(
        repository: MissCatFeedRepository,
        palette: MissCatVisualPalette = .legacyLight,
        navigationActions: MissCatFeedNavigationActions = .init()
    ) {
        self.repository = repository
        self.palette = palette
        self.navigationActions = navigationActions
    }

    public var body: some View {
        MissCatFeedView(
            source: .social,
            repository: repository,
            palette: palette,
            navigationActions: navigationActions
        )
    }
}

public struct MissCatHomeTimelineView: View {
    private let repository: MissCatFeedRepository
    private let palette: MissCatVisualPalette
    private let navigationActions: MissCatFeedNavigationActions

    public init(
        repository: MissCatFeedRepository,
        palette: MissCatVisualPalette = .legacyLight,
        navigationActions: MissCatFeedNavigationActions = .init()
    ) {
        self.repository = repository
        self.palette = palette
        self.navigationActions = navigationActions
    }

    public var body: some View {
        MissCatFeedView(
            source: .home,
            repository: repository,
            palette: palette,
            navigationActions: navigationActions
        )
    }
}

public struct MissCatLocalTimelineView: View {
    private let repository: MissCatFeedRepository
    private let palette: MissCatVisualPalette
    private let navigationActions: MissCatFeedNavigationActions

    public init(
        repository: MissCatFeedRepository,
        palette: MissCatVisualPalette = .legacyLight,
        navigationActions: MissCatFeedNavigationActions = .init()
    ) {
        self.repository = repository
        self.palette = palette
        self.navigationActions = navigationActions
    }

    public var body: some View {
        MissCatFeedView(
            source: .local,
            repository: repository,
            palette: palette,
            navigationActions: navigationActions
        )
    }
}

public struct MissCatGlobalTimelineView: View {
    private let repository: MissCatFeedRepository
    private let palette: MissCatVisualPalette
    private let navigationActions: MissCatFeedNavigationActions

    public init(
        repository: MissCatFeedRepository,
        palette: MissCatVisualPalette = .legacyLight,
        navigationActions: MissCatFeedNavigationActions = .init()
    ) {
        self.repository = repository
        self.palette = palette
        self.navigationActions = navigationActions
    }

    public var body: some View {
        MissCatFeedView(
            source: .global,
            repository: repository,
            palette: palette,
            navigationActions: navigationActions
        )
    }
}

public struct MissCatFavoritesView: View {
    private let repository: MissCatFeedRepository
    private let palette: MissCatVisualPalette
    private let navigationActions: MissCatFeedNavigationActions

    public init(
        repository: MissCatFeedRepository,
        palette: MissCatVisualPalette = .legacyLight,
        navigationActions: MissCatFeedNavigationActions = .init()
    ) {
        self.repository = repository
        self.palette = palette
        self.navigationActions = navigationActions
    }

    public var body: some View {
        MissCatFeedView(
            source: .favorites,
            repository: repository,
            palette: palette,
            emptyTitle: "お気に入りはありません",
            navigationActions: navigationActions
        )
        .navigationTitle("Favorites")
        .navigationBarTitleDisplayMode(.inline)
    }
}

public struct MissCatSearchResultsView: View {
    public let query: String
    private let repository: MissCatFeedRepository
    private let palette: MissCatVisualPalette
    private let navigationActions: MissCatFeedNavigationActions

    public init(
        query: String,
        repository: MissCatFeedRepository,
        palette: MissCatVisualPalette = .legacyLight,
        navigationActions: MissCatFeedNavigationActions = .init()
    ) {
        self.query = query
        self.repository = repository
        self.palette = palette
        self.navigationActions = navigationActions
    }

    public var body: some View {
        MissCatFeedView(
            source: .search(query: query),
            repository: repository,
            palette: palette,
            emptyTitle: "検索結果はありません",
            navigationActions: navigationActions
        )
        .navigationTitle(query)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The three legacy profile timeline modes now share the same native feed
/// renderer and current `users/notes` transport.
public struct MissCatUserTimelineView: View {
    public let userID: String
    public let includesReplies: Bool
    public let onlyFiles: Bool
    private let repository: MissCatFeedRepository
    private let palette: MissCatVisualPalette
    private let navigationActions: MissCatFeedNavigationActions

    public init(
        userID: String,
        includesReplies: Bool = false,
        onlyFiles: Bool = false,
        repository: MissCatFeedRepository,
        palette: MissCatVisualPalette = .legacyLight,
        navigationActions: MissCatFeedNavigationActions = .init()
    ) {
        self.userID = userID
        self.includesReplies = includesReplies
        self.onlyFiles = onlyFiles
        self.repository = repository
        self.palette = palette
        self.navigationActions = navigationActions
    }

    public var body: some View {
        MissCatFeedView(
            source: .user(
                userID: userID,
                includeReplies: includesReplies,
                withFiles: onlyFiles
            ),
            repository: repository,
            palette: palette,
            navigationActions: navigationActions
        )
    }
}

/// User-list timelines use the same pagination, note actions, and row renderer
/// as every other SwiftUI feed.
public struct MissCatUserListTimelineView: View {
    public let listID: String
    private let repository: MissCatFeedRepository
    private let palette: MissCatVisualPalette
    private let navigationActions: MissCatFeedNavigationActions

    public init(
        listID: String,
        repository: MissCatFeedRepository,
        palette: MissCatVisualPalette = .legacyLight,
        navigationActions: MissCatFeedNavigationActions = .init()
    ) {
        self.listID = listID
        self.repository = repository
        self.palette = palette
        self.navigationActions = navigationActions
    }

    public var body: some View {
        MissCatFeedView(
            source: .userList(listID: listID),
            repository: repository,
            palette: palette,
            navigationActions: navigationActions
        )
    }
}

public struct MissCatHashtagResultsView: View {
    public let tag: String
    private let repository: MissCatFeedRepository
    private let palette: MissCatVisualPalette
    private let navigationActions: MissCatFeedNavigationActions

    public init(
        tag: String,
        repository: MissCatFeedRepository,
        palette: MissCatVisualPalette = .legacyLight,
        navigationActions: MissCatFeedNavigationActions = .init()
    ) {
        self.tag = tag.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        self.repository = repository
        self.palette = palette
        self.navigationActions = navigationActions
    }

    public var body: some View {
        MissCatFeedView(
            source: .hashtag(tag: tag),
            repository: repository,
            palette: palette,
            emptyTitle: "このハッシュタグのノートはありません",
            navigationActions: navigationActions
        )
        .navigationTitle("#\(tag)")
        .navigationBarTitleDisplayMode(.inline)
    }
}

public struct MissCatNoteDetailView: View {
    public let noteID: String
    private let repository: MissCatFeedRepository
    private let contextRepository: (any MissCatNoteContextRepository)?
    private let palette: MissCatVisualPalette
    private let navigationActions: MissCatFeedNavigationActions
    @StateObject private var store: MissCatFeedStore
    @StateObject private var readiness = MissCatNoteVisualReadiness()
    @State private var presentedSheet: PresentedSheet?
    @State private var pendingRenote: MissCatNote?
    @State private var pendingDestructiveAction: DestructiveAction?
    @State private var pendingReport: MissCatNote?
    @State private var reportComment = ""

    public init(
        noteID: String,
        repository: MissCatFeedRepository,
        palette: MissCatVisualPalette = .legacyLight,
        navigationActions: MissCatFeedNavigationActions = .init()
    ) {
        self.noteID = noteID
        self.repository = repository
        contextRepository = repository as? any MissCatNoteContextRepository
        self.palette = palette
        self.navigationActions = navigationActions
        _store = StateObject(
            wrappedValue: MissCatFeedStore(source: .noteDetail(noteID: noteID), repository: repository)
        )
    }

    public var body: some View {
        ZStack {
            palette.base.ignoresSafeArea()
            phaseContent
        }
        .task { await store.loadInitial() }
        .onDisappear { store.stopRealtime() }
        .onChange(of: store.phase, initial: true) { _, phase in
            switch phase {
            case .loaded, .empty, .failed:
                readiness.setModelTerminal(true)
            case .idle, .loading:
                readiness.setModelTerminal(false)
            }
        }
        .alert(
            "エラー",
            isPresented: Binding(
                get: { store.actionErrorMessage != nil },
                set: { if !$0 { store.dismissActionError() } }
            )
        ) {
            if store.canRetryAction {
                Button("再試行") { Task { await store.retryLastAction() } }
            }
            Button("閉じる") { store.dismissActionError() }
        } message: {
            Text(store.actionErrorMessage ?? "")
        }
        .fullScreenCover(item: $presentedSheet) { sheet in
            switch sheet.kind {
            case .reaction:
                if let contextRepository {
                    MissCatReactionPickerView(
                        noteID: sheet.note.noteID,
                        existingReactions: sheet.note.reactions,
                        repository: contextRepository,
                        palette: palette
                    ) { noteID, reaction in
                        Task { await store.toggleReaction(noteID: noteID, reaction: reaction) }
                    }
                }
            case .reply:
                MissCatNoteComposeSheet(note: sheet.note, kind: .reply) {
                    presentedSheet = nil
                    Task { await store.refresh() }
                }
            case .quote:
                MissCatNoteComposeSheet(note: sheet.note, kind: .quote) {
                    presentedSheet = nil
                    Task { await store.refresh() }
                }
            }
        }
        .confirmationDialog(
            "Renote",
            isPresented: Binding(
                get: { pendingRenote != nil },
                set: { if !$0 { pendingRenote = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let note = pendingRenote {
                Button("Renote") {
                    pendingRenote = nil
                    Task { await store.renote(noteID: note.noteID) }
                }
                .accessibilityIdentifier("note.renote.confirm")
                Button("引用Renote") {
                    pendingRenote = nil
                    presentedSheet = PresentedSheet(kind: .quote, note: note)
                }
                .accessibilityIdentifier("note.renote.quote")
            }
            Button("キャンセル", role: .cancel) { pendingRenote = nil }
        }
        .alert(
            pendingDestructiveAction?.title ?? "確認",
            isPresented: Binding(
                get: { pendingDestructiveAction != nil },
                set: { if !$0 { pendingDestructiveAction = nil } }
            ),
            presenting: pendingDestructiveAction
        ) { action in
            Button(action.actionTitle, role: .destructive) {
                pendingDestructiveAction = nil
                Task {
                    switch action {
                    case let .delete(note): await store.delete(noteID: note.noteID)
                    case let .mute(note): await store.muteUser(userID: note.author.id)
                    case let .block(note): await store.blockUser(userID: note.author.id)
                    }
                }
            }
            .accessibilityIdentifier("note.destructive.confirm")
            Button("キャンセル", role: .cancel) { pendingDestructiveAction = nil }
        } message: { action in
            Text(action.message)
        }
        .alert(
            "このユーザーを通報",
            isPresented: Binding(
                get: { pendingReport != nil },
                set: {
                    if !$0 {
                        pendingReport = nil
                        reportComment = ""
                    }
                }
            ),
            presenting: pendingReport
        ) { note in
            TextField("通報理由（必須）", text: $reportComment)
                .accessibilityIdentifier("note.report.comment")
                .onChange(of: reportComment) { _, value in
                    if value.count > MissCatReportComment.maximumLength {
                        reportComment = MissCatReportComment.clamped(value)
                    }
                }
            Button("通報", role: .destructive) {
                let comment = reportComment
                pendingReport = nil
                reportComment = ""
                Task { await store.reportUser(userID: note.author.id, comment: comment) }
            }
            .disabled(MissCatReportComment.normalized(reportComment) == nil)
            .accessibilityIdentifier("note.report.confirm")
            Button("キャンセル", role: .cancel) {
                pendingReport = nil
                reportComment = ""
            }
        } message: { note in
            Text("@\(note.author.username) を運営に通報します。")
        }
        .navigationTitle("Thread")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await store.refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("再読込")
                .accessibilityIdentifier("note.detail.refresh")
            }
        }
        .id(contextRepository?.accountIdentifier ?? "unscoped:\(noteID)")
        .overlay(alignment: .topLeading) {
            MissCatFeedAccessibilityMarker(identifier: "note.detail.screen")
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch store.phase {
        case .idle, .loading:
            VStack(spacing: 12) {
                ProgressView().tint(palette.accent)
                Text("スレッドを読み込み中…")
                    .font(.system(size: 14))
                    .foregroundStyle(palette.strong)
            }
            .accessibilityIdentifier("note.detail.loading")
        case let .failed(message):
            ContentUnavailableView {
                Label(
                    isOffline(message) ? "オフラインです" : "スレッドを読み込めません",
                    systemImage: isOffline(message) ? "wifi.slash" : "exclamationmark.triangle"
                )
            } description: {
                Text(message)
            } actions: {
                Button("再試行") { Task { await store.retry() } }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.accent)
                    .accessibilityIdentifier("note.detail.retry")
            }
            .accessibilityIdentifier(isOffline(message) ? "note.detail.offline" : "note.detail.failure")
        case .empty:
            ContentUnavailableView {
                Label("ノートがありません", systemImage: "text.bubble")
            } description: {
                Text("削除されたか、表示する権限がありません")
            }
            .foregroundStyle(palette.strong)
            .accessibilityIdentifier("note.detail.empty")
        case .loaded:
            detailScrollView
        }
    }

    private var detailScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(store.notes.enumerated()), id: \.element.id) { index, note in
                    if let role = threadRole(note) {
                        Text(role.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.strong)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.top, 9)
                            .padding(.bottom, 4)
                            .accessibilityIdentifier("note.detail.section.\(role.rawValue)")
                    }

                    MissCatNoteRow(
                        note: note,
                        palette: palette,
                        expandsContentWarning: store.isThreadRoot(note),
                        showsThreadConnector: false,
                        onOpenUser: navigationActions.openUser,
                        onOpenNote: navigationActions.openNote,
                        onOpenAttachment: navigationActions.openAttachment,
                        onOpenHashtag: navigationActions.openHashtag,
                        onOpenMention: openMention,
                        onReply: { _ in presentedSheet = PresentedSheet(kind: .reply, note: note) },
                        onRenote: { _ in pendingRenote = note },
                        onChooseReaction: { _ in
                            if contextRepository != nil {
                                presentedSheet = PresentedSheet(kind: .reaction, note: note)
                            } else {
                                navigationActions.chooseReaction(
                                    MissCatFeedReactionRequest(
                                        noteID: note.noteID,
                                        existingReactions: note.reactions,
                                        selectReaction: { reaction in
                                            Task {
                                                await store.toggleReaction(
                                                    noteID: note.noteID,
                                                    reaction: reaction
                                                )
                                            }
                                        }
                                    )
                                )
                            }
                        },
                        onToggleReaction: { noteID, reaction in
                            Task { await store.toggleReaction(noteID: noteID, reaction: reaction) }
                        },
                        onToggleFavorite: { noteID in Task { await store.toggleFavorite(noteID: noteID) } },
                        onVote: { noteID, choice in Task { await store.vote(noteID: noteID, choice: choice) } },
                        onDelete: { _ in pendingDestructiveAction = .delete(note) },
                        onMuteUser: { _ in pendingDestructiveAction = .mute(note) },
                        onBlockUser: { _ in pendingDestructiveAction = .block(note) },
                        onReportUser: { _ in
                            reportComment = ""
                            pendingReport = note
                        },
                        onShare: navigationActions.share,
                        contextRepository: contextRepository,
                        readiness: readiness
                    )
                    .task {
                        await store.loadNextPageIfNeeded(currentNoteID: note.id)
                    }
                }

                if store.isLoadingNextPage {
                    ProgressView()
                        .tint(palette.accent)
                        .padding(.vertical, 18)
                        .accessibilityIdentifier("note.detail.pagination.loading")
                } else if !store.canLoadMore {
                    Text("返信をすべて表示しました")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.strong)
                        .padding(.vertical, 14)
                        .accessibilityIdentifier("note.detail.pagination.terminal")
                        .accessibilityValue("\(store.thread?.replies.count ?? 0)")
                }
            }
        }
        .scrollIndicators(.hidden)
        .refreshable { await store.refresh() }
        .background(palette.base)
        .accessibilityIdentifier("note.detail.thread")
        .overlay(alignment: .topLeading) {
            VStack {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityElement()
                    .accessibilityIdentifier("note.detail.pagination.cursor")
                    .accessibilityValue(store.thread?.repliesCursor ?? "none")
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityElement()
                    .accessibilityIdentifier("note.detail.refresh.completed")
                    .accessibilityValue("\(store.refreshCompletionGeneration)")
            }
        }
    }

    private enum ThreadRole: String {
        case ancestors
        case note
        case replies

        var title: String {
            switch self {
            case .ancestors: "会話"
            case .note: "ノート"
            case .replies: "返信"
            }
        }
    }

    private struct PresentedSheet: Identifiable {
        enum Kind: String { case reaction, reply, quote }
        let kind: Kind
        let note: MissCatNote
        var id: String { "\(kind.rawValue):\(note.noteID)" }
    }

    private func openMention(_ acct: String) {
        guard let contextRepository else {
            navigationActions.openMention(acct)
            return
        }
        Task {
            do {
                navigationActions.openUser(try await contextRepository.resolveMention(acct))
            } catch {
                navigationActions.openMention(acct)
            }
        }
    }

    private enum DestructiveAction {
        case delete(MissCatNote)
        case mute(MissCatNote)
        case block(MissCatNote)

        var title: String {
            switch self {
            case .delete: "ノートを削除しますか？"
            case .mute: "このユーザーをミュートしますか？"
            case .block: "このユーザーをブロックしますか？"
            }
        }

        var message: String {
            switch self {
            case .delete: "この操作は取り消せません。"
            case .mute: "このユーザーのノートは表示されなくなります。"
            case .block: "相互フォローが解除され、このユーザーとのやり取りが制限されます。"
            }
        }

        var actionTitle: String {
            switch self {
            case .delete: "削除"
            case .mute: "ミュート"
            case .block: "ブロック"
            }
        }
    }

    private func threadRole(_ note: MissCatNote) -> ThreadRole? {
        guard let thread = store.thread else { return nil }
        if thread.note.id == note.id { return .note }
        if thread.ancestors.first?.id == note.id { return .ancestors }
        if thread.replies.first?.id == note.id { return .replies }
        return nil
    }

    private func isOffline(_ message: String) -> Bool {
        let lowercased = message.lowercased()
        return lowercased.contains("offline")
            || lowercased.contains("internet")
            || message.contains("オフライン")
            || message.contains("インターネット")
    }
}

private struct MissCatFeedAccessibilityMarker: View {
    let identifier: String

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(identifier)
            .accessibilityIdentifier(identifier)
            .allowsHitTesting(false)
    }
}

private struct MissCatNoteComposeSheet: View {
    enum Kind { case reply, quote }

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: MissCatComposeViewModel
    private let kind: Kind
    private let onComplete: () -> Void

    @MainActor
    init(note: MissCatNote, kind: Kind, onComplete: @escaping () -> Void) {
        self.kind = kind
        self.onComplete = onComplete
        let target = MissCatComposeTarget(
            id: note.noteID,
            username: note.author.username,
            instance: note.author.host ?? "",
            text: note.text,
            avatarURL: note.author.avatarURL
        )
        let mode: MissCatComposeMode = kind == .reply ? .reply(target) : .quote(target)
#if DEBUG
        let model = MissCatNoteOrdinaryRouteConfiguration.isEnabled || MissCatShellFixtureLaunch.isRequested
            ? MissCatNoteOrdinaryRouteComposeFactory.makeViewModel(mode: mode)
            : MissCatComposeFactory.makeViewModel(mode: mode)
#else
        let model = MissCatComposeFactory.makeViewModel(mode: mode)
#endif
        _viewModel = StateObject(wrappedValue: model)
    }

    var body: some View {
        MissCatLegacyBottomOverlay(
            height: MissCatLegacyMetrics.noteComposePanelHeight,
            palette: .noteLegacyLight
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text(kind == .reply ? "返信" : "引用Renote")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(MissCatVisualPalette.noteLegacyLight.text)
                    .accessibilityIdentifier("compose.mode")

                if let target = viewModel.mode.target {
                    Text(targetSummary(target))
                        .font(.system(size: 13))
                        .foregroundStyle(MissCatVisualPalette.noteLegacyLight.text)
                        .lineLimit(2)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                        .background(MissCatVisualPalette.noteLegacyLight.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .accessibilityIdentifier("compose.target")
                }

                ZStack(alignment: .topLeading) {
                    if viewModel.draft.text.isEmpty {
                        Text(kind == .reply ? "返信を入力" : "コメントを入力")
                            .font(.system(size: 17))
                            .foregroundStyle(MissCatVisualPalette.noteLegacyLight.strong.opacity(0.55))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                    }
                    TextEditor(text: $viewModel.draft.text)
                        .font(.system(size: 17))
                        .scrollContentBackground(.hidden)
                        .accessibilityIdentifier("compose.text")
                }
                .frame(height: 140)
                .overlay {
                    Rectangle()
                        .stroke(MissCatVisualPalette.noteLegacyLight.border, lineWidth: 0.5)
                }

                Button(kind == .reply ? "返信" : "投稿") {
                    Task {
                        if await viewModel.submit() { complete() }
                    }
                }
                .font(.system(size: 17))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(MissCatVisualPalette.noteLegacyLight.accent)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .buttonStyle(.plain)
                .allowsHitTesting(viewModel.canSubmit)
                .accessibilityIdentifier("compose.submit")

                Spacer(minLength: 0)
            }
        }
        .task { await viewModel.load() }
        .alert("エラー", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.dismissError() } }
        )) {
            Button("閉じる") { viewModel.dismissError() }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private func complete() {
        dismiss()
        onComplete()
    }

    private func targetSummary(_ target: MissCatComposeTarget) -> String {
        let rendered = String(MissCatNativeMFMRenderer.render(target.text).characters)
        let firstURLIndex = ["https://", "http://"]
            .compactMap { rendered.range(of: $0)?.lowerBound }
            .min() ?? rendered.endIndex
        let withoutURL = rendered[..<firstURLIndex]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return target.mention + "  " + withoutURL
    }
}
