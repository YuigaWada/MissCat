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
    private let palette: MissCatVisualPalette
    private let navigationActions: MissCatFeedNavigationActions

    public init(
        noteID: String,
        repository: MissCatFeedRepository,
        palette: MissCatVisualPalette = .legacyLight,
        navigationActions: MissCatFeedNavigationActions = .init()
    ) {
        self.noteID = noteID
        self.repository = repository
        self.palette = palette
        self.navigationActions = navigationActions
    }

    public var body: some View {
        MissCatFeedView(
            source: .noteDetail(noteID: noteID),
            repository: repository,
            palette: palette,
            navigationActions: navigationActions
        )
        .navigationTitle("Thread")
        .navigationBarTitleDisplayMode(.inline)
    }
}
