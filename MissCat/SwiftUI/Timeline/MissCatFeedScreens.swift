import SwiftUI

public struct MissCatFeedNavigationActions {
    public var openUser: (String) -> Void
    public var openNote: (String) -> Void
    public var openAttachment: (MissCatNoteAttachment) -> Void
    public var openHashtag: (String) -> Void
    public var reply: (String) -> Void
    public var chooseReaction: (String) -> Void

    public init(
        openUser: @escaping (String) -> Void = { _ in },
        openNote: @escaping (String) -> Void = { _ in },
        openAttachment: @escaping (MissCatNoteAttachment) -> Void = { _ in },
        openHashtag: @escaping (String) -> Void = { _ in },
        reply: @escaping (String) -> Void = { _ in },
        chooseReaction: @escaping (String) -> Void = { _ in }
    ) {
        self.openUser = openUser
        self.openNote = openNote
        self.openAttachment = openAttachment
        self.openHashtag = openHashtag
        self.reply = reply
        self.chooseReaction = chooseReaction
    }
}

/// Shared native SwiftUI feed renderer. Timeline, saved/search/tag results and the
/// thread screen use the same store and row behavior instead of seven independent stacks.
public struct MissCatFeedView: View {
    @StateObject private var store: MissCatFeedStore
    @Binding private var scrollPositionID: String?

    private let palette: MissCatVisualPalette
    private let emptyTitle: String
    private let navigationActions: MissCatFeedNavigationActions

    public init(
        source: MissCatFeedSource,
        repository: MissCatFeedRepository,
        palette: MissCatVisualPalette = .legacyLight,
        emptyTitle: String = "ノートがありません",
        scrollPositionID: Binding<String?> = .constant(nil),
        navigationActions: MissCatFeedNavigationActions = .init()
    ) {
        _store = StateObject(
            wrappedValue: MissCatFeedStore(source: source, repository: repository)
        )
        _scrollPositionID = scrollPositionID
        self.palette = palette
        self.emptyTitle = emptyTitle
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
                emptyView
            case .loaded:
                feedScrollView
            }
        }
        .task { await store.loadInitial() }
        .onDisappear { store.stopRealtime() }
        .alert(
            "エラー",
            isPresented: Binding(
                get: { store.actionErrorMessage != nil },
                set: { if !$0 { store.dismissActionError() } }
            )
        ) {
            Button("閉じる") { store.dismissActionError() }
        } message: {
            Text(store.actionErrorMessage ?? "")
        }
        .accessibilityIdentifier("feed.\(store.source.accessibilityName)")
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
                        onOpenUser: navigationActions.openUser,
                        onOpenNote: navigationActions.openNote,
                        onOpenAttachment: navigationActions.openAttachment,
                        onOpenHashtag: navigationActions.openHashtag,
                        onReply: navigationActions.reply,
                        onRenote: { noteID in
                            Task { await store.renote(noteID: noteID) }
                        },
                        onChooseReaction: navigationActions.chooseReaction,
                        onToggleReaction: { noteID, reaction in
                            Task { await store.toggleReaction(noteID: noteID, reaction: reaction) }
                        },
                        onToggleFavorite: { noteID in
                            Task { await store.toggleFavorite(noteID: noteID) }
                        },
                        onVote: { noteID, choice in
                            Task { await store.vote(noteID: noteID, choice: choice) }
                        }
                    )
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
            Button("閉じる") { store.dismissActionError() }
        } message: {
            Text(store.actionErrorMessage ?? "")
        }
        .navigationTitle("Thread")
        .navigationBarTitleDisplayMode(.inline)
        .id(contextRepository?.accountIdentifier ?? "unscoped:\(noteID)")
        .accessibilityIdentifier("note.detail.screen")
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
                            .padding(.top, index == 0 ? 8 : 12)
                            .padding(.bottom, 4)
                            .accessibilityIdentifier("note.detail.section.\(role.rawValue)")
                    }

                    MissCatNoteRow(
                        note: note,
                        palette: palette,
                        expandsContentWarning: store.isThreadRoot(note),
                        showsThreadConnector: index < store.notes.count - 1,
                        onOpenUser: navigationActions.openUser,
                        onOpenNote: navigationActions.openNote,
                        onOpenAttachment: navigationActions.openAttachment,
                        onOpenHashtag: navigationActions.openHashtag,
                        onReply: navigationActions.reply,
                        onRenote: { noteID in Task { await store.renote(noteID: noteID) } },
                        onChooseReaction: navigationActions.chooseReaction,
                        onToggleReaction: { noteID, reaction in
                            Task { await store.toggleReaction(noteID: noteID, reaction: reaction) }
                        },
                        onToggleFavorite: { noteID in Task { await store.toggleFavorite(noteID: noteID) } },
                        onVote: { noteID, choice in Task { await store.vote(noteID: noteID, choice: choice) } },
                        onDelete: { noteID in Task { await store.delete(noteID: noteID) } },
                        onMuteUser: { userID in Task { await store.muteUser(userID: userID) } },
                        contextRepository: contextRepository,
                        readiness: readiness
                    )
                }
            }
        }
        .scrollIndicators(.hidden)
        .refreshable { await store.refresh() }
        .background(palette.base)
        .accessibilityIdentifier("note.detail.thread")
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
