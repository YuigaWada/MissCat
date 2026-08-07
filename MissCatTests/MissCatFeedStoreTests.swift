@testable import MissCat
import XCTest

final class MockMissCatFeedRepository: MissCatFeedRepository {
    struct PageRequest: Equatable {
        let source: MissCatFeedSource
        let cursor: String?
        let limit: Int
    }

    struct RepliesRequest: Equatable {
        let noteID: String
        let cursor: String?
        let limit: Int
    }

    var pages: [MissCatFeedPage] = []
    var repliesPages: [MissCatNoteRepliesPage] = []
    var threadResult: MissCatNoteThread?
    var requestedPages: [PageRequest] = []
    var requestedReplies: [RepliesRequest] = []
    var performedActions: [MissCatFeedAction] = []
    var fetchError: Error?
    var actionError: Error?
    var actionErrorsByIndex: [Int: Error] = [:]
    var failingActions: [MissCatFeedAction] = []
    var actionDelayNanoseconds: UInt64 = 0
    var realtimeContinuation: AsyncStream<MissCatRealtimeEvent>.Continuation?
    var realtimeRequestCount = 0

    func fetchPage(
        source: MissCatFeedSource,
        cursor: String?,
        limit: Int
    ) async throws -> MissCatFeedPage {
        requestedPages.append(.init(source: source, cursor: cursor, limit: limit))
        if let fetchError { throw fetchError }
        return pages.isEmpty ? .init(notes: [], hasMore: false) : pages.removeFirst()
    }

    func fetchThread(noteID: String, replyLimit: Int) async throws -> MissCatNoteThread {
        if let fetchError { throw fetchError }
        guard let threadResult else { throw TestFeedError.failed }
        return threadResult
    }

    func fetchReplies(noteID: String, cursor: String?, limit: Int) async throws -> MissCatNoteRepliesPage {
        requestedReplies.append(.init(noteID: noteID, cursor: cursor, limit: limit))
        if let fetchError { throw fetchError }
        return repliesPages.isEmpty
            ? .init(replies: [], nextCursor: nil, hasMore: false)
            : repliesPages.removeFirst()
    }

    func realtimeEvents(
        source: MissCatFeedSource,
        capturing noteIDs: [String]
    ) -> AsyncStream<MissCatRealtimeEvent> {
        realtimeRequestCount += 1
        return AsyncStream { realtimeContinuation = $0 }
    }

    func perform(_ action: MissCatFeedAction) async throws {
        performedActions.append(action)
        let actionIndex = performedActions.count - 1
        if actionDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: actionDelayNanoseconds)
        }
        if let actionError = actionErrorsByIndex[actionIndex] { throw actionError }
        if failingActions.contains(action) { throw TestFeedError.failed }
        if let actionError { throw actionError }
    }
}

private enum TestFeedError: LocalizedError {
    case failed

    var errorDescription: String? { "test failure" }
}

@MainActor
final class MissCatFeedStoreTests: XCTestCase {
    func testInitialFetchPublishesNotesAndRequestScope() async {
        let repository = MockMissCatFeedRepository()
        repository.pages = [.init(notes: [note("one"), note("two")], hasMore: true)]
        let store = MissCatFeedStore(source: .search(query: "cats"), repository: repository, pageSize: 2)

        await store.loadInitial()

        XCTAssertEqual(store.phase, .loaded)
        XCTAssertEqual(store.notes.map(\.id), ["one", "two"])
        XCTAssertTrue(store.canLoadMore)
        XCTAssertEqual(
            repository.requestedPages,
            [.init(source: .search(query: "cats"), cursor: nil, limit: 2)]
        )
    }

    func testRefreshPrependsNewNotesWithoutDuplicates() async {
        let repository = MockMissCatFeedRepository()
        repository.pages = [
            .init(notes: [note("two"), note("one")], hasMore: true),
            .init(notes: [note("three"), note("two")], hasMore: true)
        ]
        let store = MissCatFeedStore(source: .home, repository: repository, pageSize: 2)

        await store.loadInitial()
        XCTAssertEqual(store.refreshCompletionGeneration, 0)
        await store.refresh()

        XCTAssertEqual(store.notes.map(\.id), ["three", "two", "one"])
        XCTAssertEqual(store.refreshCompletionGeneration, 1)
        XCTAssertEqual(repository.requestedPages.map(\.cursor), [nil, nil])
    }

    func testPaginationUsesLastItemAndAppendsUniqueNotes() async {
        let repository = MockMissCatFeedRepository()
        repository.pages = [
            .init(notes: [note("three"), note("two")], hasMore: true),
            .init(notes: [note("two"), note("one")], hasMore: false)
        ]
        let store = MissCatFeedStore(source: .global, repository: repository, pageSize: 2)

        await store.loadInitial()
        await store.loadNextPageIfNeeded(currentNoteID: "two")

        XCTAssertEqual(store.notes.map(\.id), ["three", "two", "one"])
        XCTAssertFalse(store.canLoadMore)
        XCTAssertEqual(repository.requestedPages.last?.cursor, "two")
    }

    func testRealtimeInsertReactionAndDeleteUpdateLoadedFeed() async {
        let repository = MockMissCatFeedRepository()
        repository.pages = [.init(notes: [note("one")], hasMore: false)]
        let store = MissCatFeedStore(source: .local, repository: repository)

        await store.loadInitial()
        await waitForRealtimeContinuation(repository)
        repository.realtimeContinuation?.yield(.inserted(note("two")))
        repository.realtimeContinuation?.yield(
            .reaction(noteID: "one", reaction: "👍", delta: 1, isMine: true)
        )
        await waitUntil {
            store.notes.last?.myReaction == "👍"
                && store.notes.last?.reactions.first?.count == 1
        }

        XCTAssertEqual(store.notes.map(\.id), ["two", "one"])
        XCTAssertEqual(store.notes.last?.myReaction, "👍")
        XCTAssertEqual(store.notes.last?.reactions.first?.count, 1)

        repository.realtimeContinuation?.yield(.removed(noteID: "two"))
        await waitUntil { store.notes.map(\.id) == ["one"] }
        XCTAssertEqual(store.notes.map(\.id), ["one"])
    }

    func testFavoriteActionIsOptimisticAndRollsBackOnFailure() async {
        let repository = MockMissCatFeedRepository()
        repository.pages = [.init(notes: [note("one")], hasMore: false)]
        let store = MissCatFeedStore(source: .home, repository: repository)
        await store.loadInitial()

        repository.actionError = TestFeedError.failed
        await store.toggleFavorite(noteID: "one")

        XCTAssertEqual(repository.performedActions, [.favorite(noteID: "one")])
        XCTAssertFalse(try! XCTUnwrap(store.notes.first).isFavorite)
        XCTAssertEqual(store.actionErrorMessage, "test failure")
    }

    func testUnfavoritingFromFavoritesRemovesTheRow() async {
        let repository = MockMissCatFeedRepository()
        var favorite = note("one")
        favorite.isFavorite = true
        repository.pages = [.init(notes: [favorite], hasMore: false)]
        let store = MissCatFeedStore(source: .favorites, repository: repository)
        await store.loadInitial()

        await store.toggleFavorite(noteID: "one")

        XCTAssertEqual(repository.performedActions, [.unfavorite(noteID: "one")])
        XCTAssertTrue(store.notes.isEmpty)
        XCTAssertEqual(store.phase, .empty)
    }

    func testSwitchingReactionRemovesOldReactionBeforeAddingNewOne() async {
        let repository = MockMissCatFeedRepository()
        var reacted = note("one")
        reacted.myReaction = "👍"
        reacted.reactions = [.init(name: "👍", count: 2, isMine: true)]
        repository.pages = [.init(notes: [reacted], hasMore: false)]
        let store = MissCatFeedStore(source: .home, repository: repository)
        await store.loadInitial()

        await store.toggleReaction(noteID: "one", reaction: "❤️")

        XCTAssertEqual(
            repository.performedActions,
            [.removeReaction(noteID: "one"), .addReaction(noteID: "one", reaction: "❤️")]
        )
        XCTAssertEqual(store.notes.first?.myReaction, "❤️")
        XCTAssertEqual(store.notes.first?.reactions.map(\.name), ["👍", "❤️"])
        XCTAssertEqual(store.notes.first?.reactions.first?.count, 1)
    }

    func testSwitchingReactionKeepsServerReconciledStateWhenAddFailsAfterRemove() async {
        let repository = MockMissCatFeedRepository()
        var reacted = note("one")
        reacted.myReaction = "👍"
        reacted.reactions = [.init(name: "👍", count: 2, isMine: true)]
        repository.pages = [.init(notes: [reacted], hasMore: false)]
        repository.actionErrorsByIndex = [1: TestFeedError.failed]
        let store = MissCatFeedStore(source: .home, repository: repository)
        await store.loadInitial()

        await store.toggleReaction(noteID: "one", reaction: "❤️")

        XCTAssertEqual(
            repository.performedActions,
            [.removeReaction(noteID: "one"), .addReaction(noteID: "one", reaction: "❤️")]
        )
        XCTAssertNil(store.notes.first?.myReaction)
        XCTAssertEqual(store.notes.first?.reactions.map(\.name), ["👍"])
        XCTAssertEqual(store.notes.first?.reactions.first?.count, 1)
        XCTAssertEqual(store.actionErrorMessage, "test failure")
    }

    func testRapidDuplicateMutationsSubmitEachActionAtMostOnce() async {
        let repository = MockMissCatFeedRepository()
        var pollNote = note("one")
        pollNote.poll = MissCatPoll(
            choices: [.init(id: 0, text: "yes", votes: 0)],
            allowsMultipleChoices: false
        )
        repository.pages = [.init(notes: [pollNote], hasMore: false)]
        repository.actionDelayNanoseconds = 50_000_000
        let store = MissCatFeedStore(source: .home, repository: repository)
        await store.loadInitial()

        async let favoriteA: Void = store.toggleFavorite(noteID: "one")
        async let favoriteB: Void = store.toggleFavorite(noteID: "one")
        _ = await (favoriteA, favoriteB)

        async let reactionA: Void = store.toggleReaction(noteID: "one", reaction: "👍")
        async let reactionB: Void = store.toggleReaction(noteID: "one", reaction: "👍")
        _ = await (reactionA, reactionB)

        async let renoteA: Void = store.renote(noteID: "one")
        async let renoteB: Void = store.renote(noteID: "one")
        _ = await (renoteA, renoteB)

        async let voteA: Void = store.vote(noteID: "one", choice: 0)
        async let voteB: Void = store.vote(noteID: "one", choice: 0)
        _ = await (voteA, voteB)

        XCTAssertEqual(
            repository.performedActions,
            [
                .favorite(noteID: "one"),
                .addReaction(noteID: "one", reaction: "👍"),
                .renote(noteID: "one"),
                .vote(noteID: "one", choice: 0)
            ]
        )
    }

    func testFailedMutationDoesNotRollBackSuccessfulMutationOnAnotherNote() async {
        let repository = MockMissCatFeedRepository()
        repository.pages = [.init(notes: [note("one"), note("two")], hasMore: false)]
        repository.actionDelayNanoseconds = 50_000_000
        repository.failingActions = [.favorite(noteID: "one")]
        let store = MissCatFeedStore(source: .home, repository: repository)
        await store.loadInitial()

        async let failedFavorite: Void = store.toggleFavorite(noteID: "one")
        async let successfulFavorite: Void = store.toggleFavorite(noteID: "two")
        _ = await (failedFavorite, successfulFavorite)

        XCTAssertFalse(try! XCTUnwrap(store.notes.first(where: { $0.noteID == "one" })).isFavorite)
        XCTAssertTrue(try! XCTUnwrap(store.notes.first(where: { $0.noteID == "two" })).isFavorite)
        XCTAssertEqual(repository.performedActions.count, 2)
    }

    func testMutationLockIsReleasedAfterFailure() async {
        let repository = MockMissCatFeedRepository()
        repository.pages = [.init(notes: [note("one")], hasMore: false)]
        repository.actionErrorsByIndex = [0: TestFeedError.failed]
        let store = MissCatFeedStore(source: .home, repository: repository)
        await store.loadInitial()

        await store.toggleFavorite(noteID: "one")
        await store.toggleFavorite(noteID: "one")

        XCTAssertEqual(
            repository.performedActions,
            [.favorite(noteID: "one"), .favorite(noteID: "one")]
        )
        XCTAssertTrue(try! XCTUnwrap(store.notes.first).isFavorite)
    }

    func testVoteRejectsExpiredOrAlreadyCompletedSingleChoicePoll() async {
        let repository = MockMissCatFeedRepository()
        var expired = note("expired")
        expired.poll = MissCatPoll(
            choices: [.init(id: 0, text: "yes", votes: 0)],
            expiresAt: Date(timeIntervalSince1970: 1)
        )
        var completed = note("completed")
        completed.poll = MissCatPoll(
            choices: [
                .init(id: 0, text: "yes", votes: 1, isVoted: true),
                .init(id: 1, text: "no", votes: 0)
            ]
        )
        repository.pages = [.init(notes: [expired, completed], hasMore: false)]
        let store = MissCatFeedStore(source: .home, repository: repository)
        await store.loadInitial()

        await store.vote(noteID: "expired", choice: 0)
        await store.vote(noteID: "completed", choice: 1)

        XCTAssertTrue(repository.performedActions.isEmpty)
    }

    func testVoteRejectsDuplicateMultipleChoiceAndUnknownChoice() async {
        let repository = MockMissCatFeedRepository()
        var pollNote = note("one")
        pollNote.poll = MissCatPoll(
            choices: [
                .init(id: 0, text: "yes", votes: 1, isVoted: true),
                .init(id: 1, text: "no", votes: 0)
            ],
            allowsMultipleChoices: true
        )
        repository.pages = [.init(notes: [pollNote], hasMore: false)]
        let store = MissCatFeedStore(source: .home, repository: repository)
        await store.loadInitial()

        await store.vote(noteID: "one", choice: 0)
        await store.vote(noteID: "one", choice: 99)

        XCTAssertTrue(repository.performedActions.isEmpty)
        XCTAssertEqual(store.notes.first?.poll, pollNote.poll)
    }

    func testTimelineModerationActionsUseRepositoryAndPreserveExpectedRows() async {
        let blockRepository = MockMissCatFeedRepository()
        blockRepository.pages = [.init(notes: [note("one"), note("two")], hasMore: false)]
        let blockStore = MissCatFeedStore(source: .home, repository: blockRepository)
        await blockStore.loadInitial()

        await blockStore.blockUser(userID: "author")

        XCTAssertEqual(blockRepository.performedActions, [.block(userID: "author")])
        XCTAssertEqual(blockStore.phase, .empty)
        XCTAssertTrue(blockStore.notes.isEmpty)

        let reportRepository = MockMissCatFeedRepository()
        reportRepository.pages = [.init(notes: [note("three")], hasMore: false)]
        let reportStore = MissCatFeedStore(source: .home, repository: reportRepository)
        await reportStore.loadInitial()

        await reportStore.reportUser(userID: "author", comment: "  abusive post  ")

        XCTAssertEqual(
            reportRepository.performedActions,
            [.report(userID: "author", comment: "abusive post")]
        )
        XCTAssertEqual(reportStore.notes.map(\.id), ["three"])
        XCTAssertEqual(reportStore.phase, .loaded)
    }

    func testReportCommentAcceptsOneAnd2048CharactersButRejects2049() async {
        let repository = MockMissCatFeedRepository()
        repository.pages = [.init(notes: [note("report")], hasMore: false)]
        let store = MissCatFeedStore(source: .home, repository: repository)
        await store.loadInitial()
        let maximum = String(repeating: "猫", count: 2_048)

        await store.reportUser(userID: "one", comment: "x")
        await store.reportUser(userID: "maximum", comment: maximum)
        await store.reportUser(
            userID: "too-long",
            comment: String(repeating: "猫", count: 2_049)
        )

        XCTAssertEqual(
            repository.performedActions,
            [
                .report(userID: "one", comment: "x"),
                .report(userID: "maximum", comment: maximum)
            ]
        )
    }

    func testThreadFetchPreservesAncestorRootReplyOrderAndExpandsRoot() async {
        let repository = MockMissCatFeedRepository()
        repository.threadResult = MissCatNoteThread(
            ancestors: [note("ancestor")],
            note: note("root"),
            replies: [note("reply")]
        )
        let store = MissCatFeedStore(source: .noteDetail(noteID: "root"), repository: repository)

        await store.loadInitial()

        XCTAssertEqual(store.notes.map(\.id), ["ancestor", "root", "reply"])
        XCTAssertTrue(store.isThreadRoot(try! XCTUnwrap(store.notes.dropFirst().first)))
        XCTAssertFalse(store.canLoadMore)
    }

    func testDetailReplyPaginationAdvancesCursorDeduplicatesTerminatesAndRefreshes() async {
        let repository = MockMissCatFeedRepository()
        repository.threadResult = MissCatNoteThread(
            ancestors: [note("ancestor")],
            note: note("root"),
            replies: [note("reply-1"), note("root")],
            repliesCursor: "cursor-1",
            hasMoreReplies: true
        )
        repository.repliesPages = [
            .init(
                replies: [note("reply-1"), note("reply-2")],
                nextCursor: "cursor-2",
                hasMore: true
            ),
            .init(
                replies: [note("reply-2"), note("reply-3")],
                nextCursor: "cursor-3",
                hasMore: false
            ),
        ]
        let store = MissCatFeedStore(
            source: .noteDetail(noteID: "root"),
            repository: repository,
            pageSize: 2
        )

        await store.loadInitial()
        XCTAssertEqual(store.notes.map(\.id), ["ancestor", "root", "reply-1"])
        XCTAssertTrue(store.canLoadMore)

        await store.loadNextPageIfNeeded(currentNoteID: "reply-1")
        await store.loadNextPageIfNeeded(currentNoteID: "reply-2")
        await store.loadNextPageIfNeeded(currentNoteID: "reply-3")

        XCTAssertEqual(store.notes.map(\.id), ["ancestor", "root", "reply-1", "reply-2", "reply-3"])
        XCTAssertEqual(store.thread?.replies.map(\.id), ["reply-1", "reply-2", "reply-3"])
        XCTAssertEqual(
            repository.requestedReplies,
            [
                .init(noteID: "root", cursor: "cursor-1", limit: 2),
                .init(noteID: "root", cursor: "cursor-2", limit: 2),
            ]
        )
        XCTAssertFalse(store.canLoadMore)
        XCTAssertEqual(store.thread?.repliesCursor, "cursor-3")

        repository.threadResult = MissCatNoteThread(
            ancestors: [],
            note: note("root"),
            replies: [note("reply-refreshed")],
            repliesCursor: "refresh-cursor",
            hasMoreReplies: true
        )
        await store.refresh()

        XCTAssertEqual(store.notes.map(\.id), ["root", "reply-refreshed"])
        XCTAssertEqual(store.thread?.repliesCursor, "refresh-cursor")
        XCTAssertTrue(store.canLoadMore)
        XCTAssertEqual(store.refreshCompletionGeneration, 1)
    }

    func testTimelineSelectionUsesOneStateForTapSwipeAndReverseSwipe() {
        var state = MissCatTimelineSelectionState(
            pageIDs: ["home", "local", "social", "global"],
            selectedID: "home"
        )

        XCTAssertTrue(state.select("social", origin: .tap))
        XCTAssertEqual(state.selectedID, "social")
        XCTAssertEqual(state.lastOrigin, .tap)

        XCTAssertTrue(state.move(by: 1))
        XCTAssertEqual(state.selectedID, "global")
        XCTAssertTrue(state.move(by: -1))
        XCTAssertEqual(state.selectedID, "social")
        XCTAssertEqual(state.lastOrigin, .swipe)
    }

    func testTimelineSelectionClampsEdgeSwipesAndRejectsUnknownTabs() {
        var state = MissCatTimelineSelectionState(
            pageIDs: ["home", "local", "global"],
            selectedID: "missing"
        )

        XCTAssertEqual(state.selectedID, "home")
        XCTAssertFalse(state.move(by: -1))
        XCTAssertEqual(state.selectedID, "home")
        XCTAssertFalse(state.select("unknown", origin: .tap))
        XCTAssertEqual(state.selectedID, "home")

        XCTAssertTrue(state.select("global", origin: .tap))
        XCTAssertFalse(state.move(by: 1))
        XCTAssertEqual(state.selectedID, "global")
    }

    func testTimelineSelectionHandlesRapidChangesAndPageReplacement() {
        var state = MissCatTimelineSelectionState(
            pageIDs: ["home", "local", "social", "global", "home"],
            selectedID: "home"
        )

        ["global", "local", "social", "home", "global"].forEach {
            XCTAssertTrue(state.select($0, origin: .tap))
        }
        XCTAssertEqual(state.selectedID, "global")
        XCTAssertEqual(state.pageIDs, ["home", "local", "social", "global"])

        state.updatePages(["home", "local"])
        XCTAssertEqual(state.selectedID, "home")
        XCTAssertEqual(state.lastOrigin, .pagesChanged)
    }

    func testAccountScopeNormalizesInstanceAndNeverCollidesAcrossInstances() {
        let first = MissCatShellAccountScope(
            instance: " HTTPS://Social.Example/ ",
            userID: "same-user",
            username: "cat"
        )
        let same = MissCatShellAccountScope(
            instance: "https://social.example",
            userID: "same-user",
            username: "cat"
        )
        let other = MissCatShellAccountScope(
            instance: "https://other.example",
            userID: "same-user",
            username: "cat"
        )

        XCTAssertEqual(first, same)
        XCTAssertNotEqual(first, other)
        XCTAssertEqual(Set([first, same, other]).count, 2)
    }

    func testFiveFooterDestinationsShareSelectionAndReselectContract() {
        var state = MissCatFooterSelectionState()

        XCTAssertEqual(state.activate(.home), .reselected(.home))
        XCTAssertEqual(state.activate(.notifications), .selected(.notifications))
        XCTAssertEqual(state.activate(.notifications), .reselected(.notifications))
        XCTAssertEqual(state.activate(.compose), .composeRequested)
        XCTAssertEqual(state.selectedSection, .notifications)
        XCTAssertEqual(state.activate(.messages), .selected(.messages))
        XCTAssertEqual(state.activate(.profile), .selected(.profile))
        XCTAssertEqual(state.selectedSection, .profile)
    }

    func testShellStorePersistsTapAndSwipeAgainstInstanceUserScope() async {
        let provider = MockShellConfigurationProvider()
        let store = MissCatShellStore(provider: provider)
        await store.load()

        store.selectTimeline("local", origin: .tap)
        await store.waitForPendingPersistence()
        store.selectTimeline("home", origin: .swipe)
        await store.waitForPendingPersistence()

        XCTAssertEqual(store.selectedTimelineID, "home")
        XCTAssertEqual(store.timelineSelectionOrigin, .swipe)
        XCTAssertEqual(provider.savedSelections.map(\.selectedID), ["local", "home"])
        XCTAssertEqual(provider.savedSelections.map(\.scope), [provider.primaryScope, provider.primaryScope])
    }

    func testShellStoreSwitchesExactScopeAndResetsConfiguredSelection() async {
        let provider = MockShellConfigurationProvider()
        let store = MissCatShellStore(provider: provider)
        await store.load()
        store.selectTimeline("local", origin: .tap)
        await store.waitForPendingPersistence()

        store.switchAccount(to: provider.secondaryScope)
        await store.waitForPendingAccountSwitch()

        XCTAssertEqual(store.configuration?.currentScope, provider.secondaryScope)
        XCTAssertEqual(store.selectedTimelineID, "secondary-home")
        XCTAssertEqual(provider.switchedScopes, [provider.secondaryScope])
    }

    func testShellStoreRejectsLateNonCooperativeAccountSwitch() async {
        let provider = NonCooperativeShellConfigurationProvider()
        let store = MissCatShellStore(provider: provider)
        await store.load()

        store.switchAccount(to: provider.secondaryScope)
        await waitUntil { provider.pendingScopes.contains(provider.secondaryScope) }
        XCTAssertTrue(provider.pendingScopes.contains(provider.secondaryScope))
        store.switchAccount(to: provider.tertiaryScope)
        await waitUntil { provider.pendingScopes.contains(provider.tertiaryScope) }
        XCTAssertTrue(provider.pendingScopes.contains(provider.tertiaryScope))

        provider.resumeSwitch(to: provider.tertiaryScope)
        await store.waitForPendingAccountSwitch()
        provider.resumeSwitch(to: provider.secondaryScope)
        await waitUntil { provider.returnedScopes.contains(provider.secondaryScope) }
        await Task.yield()

        XCTAssertTrue(provider.returnedScopes.contains(provider.secondaryScope))
        XCTAssertEqual(store.configuration?.currentScope, provider.tertiaryScope)
        XCTAssertEqual(store.selectedTimelineID, "tertiary-home")
        XCTAssertEqual(store.phase, .loaded)
    }

    func testShellStoreRejectsLateNonCooperativeConfigurationLoad() async {
        let provider = NonCooperativeShellLoadProvider()
        let store = MissCatShellStore(provider: provider)

        let load = Task { await store.load() }
        await waitUntil { provider.hasPendingLoad }
        XCTAssertTrue(provider.hasPendingLoad)
        store.cancelConfigurationTasks()
        provider.resumeLoad()
        await load.value

        XCTAssertNil(store.configuration)
        XCTAssertEqual(store.phase, .idle)
    }

    func testPageOwnerResolutionUsesCompositeAccountIdentity() {
        let otherInstance = MissCatShellAccountScope(
            instance: "one.example",
            userID: "shared-user",
            username: "cat"
        )
        let current = MissCatShellAccountScope(
            instance: "two.example",
            userID: "shared-user",
            username: "cat"
        )
        let unique = MissCatShellAccountScope(
            instance: "three.example",
            userID: "unique-user",
            username: "dog"
        )
        let ambiguousOne = MissCatShellAccountScope(
            instance: "four.example",
            userID: "ambiguous-user",
            username: "fox"
        )
        let ambiguousTwo = MissCatShellAccountScope(
            instance: "five.example",
            userID: "ambiguous-user",
            username: "fox"
        )

        XCTAssertEqual(
            MissCatLegacyShellConfigurationProvider.resolvePageOwnerScope(
                userID: "shared-user",
                among: [otherInstance, current, unique, ambiguousOne, ambiguousTwo],
                currentScope: current
            ),
            current
        )
        XCTAssertEqual(
            MissCatLegacyShellConfigurationProvider.resolvePageOwnerScope(
                userID: "unique-user",
                among: [otherInstance, current, unique, ambiguousOne, ambiguousTwo],
                currentScope: current
            ),
            unique
        )
        XCTAssertNil(
            MissCatLegacyShellConfigurationProvider.resolvePageOwnerScope(
                userID: "missing-user",
                among: [otherInstance, current, unique, ambiguousOne, ambiguousTwo],
                currentScope: current
            )
        )
        XCTAssertNil(
            MissCatLegacyShellConfigurationProvider.resolvePageOwnerScope(
                userID: "ambiguous-user",
                among: [otherInstance, current, unique, ambiguousOne, ambiguousTwo],
                currentScope: current
            )
        )
    }

    func testShellStoreEmitsOnlyHomeAndNotificationScrollToTopSignals() async {
        let store = MissCatShellStore(provider: MockShellConfigurationProvider())
        await store.load()

        XCTAssertEqual(store.activateFooter(.home), .reselected(.home))
        XCTAssertEqual(store.homeScrollToTopGeneration, 1)
        XCTAssertEqual(store.activateFooter(.notifications), .selected(.notifications))
        XCTAssertEqual(store.activateFooter(.notifications), .reselected(.notifications))
        XCTAssertEqual(store.notificationsScrollToTopGeneration, 1)
        XCTAssertEqual(store.activateFooter(.messages), .selected(.messages))
        XCTAssertEqual(store.activateFooter(.messages), .reselected(.messages))
        XCTAssertEqual(store.homeScrollToTopGeneration, 1)
        XCTAssertEqual(store.notificationsScrollToTopGeneration, 1)
    }

    func testCancelledInitialLoadReturnsToIdleWithoutError() async {
        let repository = MockMissCatFeedRepository()
        repository.fetchError = CancellationError()
        let store = MissCatFeedStore(source: .home, repository: repository)

        await store.loadInitial()

        XCTAssertEqual(store.phase, .idle)
        XCTAssertNil(store.actionErrorMessage)
    }

    func testLoadedFeedRestartsRealtimeAfterViewLifetimeCancellation() async {
        let repository = MockMissCatFeedRepository()
        repository.pages = [.init(notes: [note("one")], hasMore: false)]
        let store = MissCatFeedStore(source: .home, repository: repository)
        await store.loadInitial()
        await waitUntil { repository.realtimeRequestCount == 1 }

        store.stopRealtime()
        await store.loadInitial()
        await waitUntil { repository.realtimeRequestCount == 2 }

        XCTAssertEqual(repository.realtimeRequestCount, 2)
    }

    func testCancelledStoreRejectsLateNonCooperativeInitialResult() async {
        let repository = NonCooperativeFeedRepository()
        let scope = MissCatShellAccountScope(
            instance: "one.example",
            userID: "shared-user",
            username: "cat"
        )
        let store = MissCatFeedStore(source: .home, repository: repository, accountScope: scope)

        let load = Task { await store.loadInitial() }
        await waitUntil { repository.hasPendingPage }
        store.cancelAllFeedTasks()
        repository.resumePage(.init(notes: [note("stale")], hasMore: false))
        await load.value

        XCTAssertEqual(store.phase, .idle)
        XCTAssertTrue(store.notes.isEmpty)
        XCTAssertFalse(store.isRealtimeConnected)
    }

    func testCancelledStoreRejectsLateNonCooperativePaginationAndRefresh() async {
        let repository = NonCooperativeFeedRepository()
        let scope = MissCatShellAccountScope(
            instance: "one.example",
            userID: "shared-user",
            username: "cat"
        )
        let store = MissCatFeedStore(source: .home, repository: repository, accountScope: scope)

        let initial = Task { await store.loadInitial() }
        await waitUntil { repository.hasPendingPage }
        repository.resumePage(.init(notes: [note("current")], hasMore: true))
        await initial.value

        let pagination = Task {
            await store.loadNextPageIfNeeded(currentNoteID: "current")
        }
        await waitUntil { repository.hasPendingPage }
        store.cancelAllFeedTasks()
        repository.resumePage(.init(notes: [note("stale-page")], hasMore: false))
        await pagination.value
        XCTAssertEqual(store.notes.map(\.id), ["current"])

        let refresh = Task { await store.refresh() }
        await waitUntil { repository.hasPendingPage }
        store.cancelAllFeedTasks()
        repository.resumePage(.init(notes: [note("stale-refresh")], hasMore: false))
        await refresh.value
        XCTAssertEqual(store.notes.map(\.id), ["current"])
        XCTAssertFalse(store.isRefreshing)
        XCTAssertFalse(store.isLoadingNextPage)
    }

    func testScrollPositionsRestoreByCompositeAccountIdentity() {
        let firstScope = MissCatShellAccountScope(
            instance: "one.example",
            userID: "shared-user",
            username: "cat"
        )
        let secondScope = MissCatShellAccountScope(
            instance: "two.example",
            userID: "shared-user",
            username: "cat"
        )
        let firstKey = MissCatTimelineScrollKey(accountScope: firstScope, pageID: "home")
        let secondKey = MissCatTimelineScrollKey(accountScope: secondScope, pageID: "home")
        var positions = MissCatTimelineScrollPositionState()

        positions.setPosition("first-note", for: firstKey)
        positions.setPosition("second-note", for: secondKey)

        XCTAssertEqual(positions.position(for: firstKey), "first-note")
        XCTAssertEqual(positions.position(for: secondKey), "second-note")
        XCTAssertNotEqual(firstKey, secondKey)
    }

    func testShellPersistenceFailurePublishesDismissibleBanner() async {
        let provider = MockShellConfigurationProvider()
        provider.saveError = TestFeedError.failed
        let store = MissCatShellStore(provider: provider)
        await store.load()

        store.selectTimeline("local", origin: .tap)
        await store.waitForPendingPersistence()

        XCTAssertEqual(store.bannerMessage, "test failure")
        store.dismissBanner()
        XCTAssertNil(store.bannerMessage)
    }

    private func waitForRealtimeContinuation(_ repository: MockMissCatFeedRepository) async {
        for _ in 0 ..< 20 where repository.realtimeContinuation == nil {
            await Task.yield()
        }
        XCTAssertNotNil(repository.realtimeContinuation)
    }

    private func waitUntil(_ condition: @escaping () -> Bool) async {
        for _ in 0 ..< 100 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    private func note(_ id: String) -> MissCatNote {
        MissCatNote(
            id: id,
            author: MissCatNoteAuthor(id: "author", name: "Miss Cat", username: "misscat"),
            text: "note \(id)"
        )
    }
}

private final class NonCooperativeFeedRepository: MissCatFeedRepository {
    private var pageContinuation: CheckedContinuation<MissCatFeedPage, Never>?

    var hasPendingPage: Bool { pageContinuation != nil }

    func resumePage(_ page: MissCatFeedPage) {
        let continuation = pageContinuation
        pageContinuation = nil
        continuation?.resume(returning: page)
    }

    func fetchPage(
        source: MissCatFeedSource,
        cursor: String?,
        limit: Int
    ) async throws -> MissCatFeedPage {
        await withCheckedContinuation { continuation in
            pageContinuation = continuation
        }
    }

    func fetchThread(noteID: String, replyLimit: Int) async throws -> MissCatNoteThread {
        throw TestFeedError.failed
    }

    func realtimeEvents(
        source: MissCatFeedSource,
        capturing noteIDs: [String]
    ) -> AsyncStream<MissCatRealtimeEvent> {
        AsyncStream { $0.finish() }
    }

    func perform(_ action: MissCatFeedAction) async throws {}
}

@MainActor
private final class MockShellConfigurationProvider: MissCatShellConfigurationProviding {
    struct SavedSelection: Equatable {
        let selectedID: String
        let scope: MissCatShellAccountScope
    }

    let primaryScope = MissCatShellAccountScope(instance: "one.example", userID: "shared", username: "cat")
    let secondaryScope = MissCatShellAccountScope(instance: "two.example", userID: "shared", username: "cat")
    var savedSelections: [SavedSelection] = []
    var switchedScopes: [MissCatShellAccountScope] = []
    var saveError: Error?
    private let feedRepository = MockMissCatFeedRepository()

    func loadConfiguration() async throws -> MissCatShellConfiguration {
        configuration(scope: primaryScope, pageIDs: ["home", "local"])
    }

    func switchAccount(to scope: MissCatShellAccountScope) async throws -> MissCatShellConfiguration {
        switchedScopes.append(scope)
        guard scope == secondaryScope else { throw MissCatShellConfigurationError.accountNotFound }
        return configuration(scope: secondaryScope, pageIDs: ["secondary-home", "secondary-global"])
    }

    func saveSelectedTimelineID(_ selectedID: String, for scope: MissCatShellAccountScope) async throws {
        if let saveError { throw saveError }
        savedSelections.append(.init(selectedID: selectedID, scope: scope))
    }

    func repository(for scope: MissCatShellAccountScope) throws -> any MissCatFeedRepository {
        feedRepository
    }

    private func configuration(
        scope: MissCatShellAccountScope,
        pageIDs: [String]
    ) -> MissCatShellConfiguration {
        MissCatShellConfiguration(
            currentScope: scope,
            accounts: [
                MissCatShellAccount(scope: primaryScope),
                MissCatShellAccount(scope: secondaryScope)
            ],
            timelinePages: pageIDs.map {
                MissCatTimelinePage(id: $0, title: $0, source: .home, accountScope: scope)
            },
            selectedTimelineID: pageIDs[0],
            appearance: .init(isDark: false, accentHex: "2F7CF6")
        )
    }
}

@MainActor
private final class NonCooperativeShellConfigurationProvider: MissCatShellConfigurationProviding {
    let primaryScope = MissCatShellAccountScope(instance: "one.example", userID: "shared", username: "cat")
    let secondaryScope = MissCatShellAccountScope(instance: "two.example", userID: "shared", username: "cat")
    let tertiaryScope = MissCatShellAccountScope(instance: "three.example", userID: "shared", username: "cat")

    private var continuations: [
        MissCatShellAccountScope: CheckedContinuation<MissCatShellConfiguration, Never>
    ] = [:]
    private let feedRepository = MockMissCatFeedRepository()
    private(set) var returnedScopes: Set<MissCatShellAccountScope> = []

    var pendingScopes: Set<MissCatShellAccountScope> {
        Set(continuations.keys)
    }

    func loadConfiguration() async throws -> MissCatShellConfiguration {
        configuration(scope: primaryScope, pageID: "primary-home")
    }

    func switchAccount(to scope: MissCatShellAccountScope) async throws -> MissCatShellConfiguration {
        let configuration = await withCheckedContinuation { continuation in
            continuations[scope] = continuation
        }
        returnedScopes.insert(scope)
        return configuration
    }

    func resumeSwitch(to scope: MissCatShellAccountScope) {
        continuations.removeValue(forKey: scope)?.resume(
            returning: configuration(scope: scope, pageID: scope == tertiaryScope ? "tertiary-home" : "secondary-home")
        )
    }

    func saveSelectedTimelineID(
        _ selectedID: String,
        for scope: MissCatShellAccountScope
    ) async throws {}

    func repository(for scope: MissCatShellAccountScope) throws -> any MissCatFeedRepository {
        feedRepository
    }

    private func configuration(
        scope: MissCatShellAccountScope,
        pageID: String
    ) -> MissCatShellConfiguration {
        MissCatShellConfiguration(
            currentScope: scope,
            accounts: [primaryScope, secondaryScope, tertiaryScope].map { MissCatShellAccount(scope: $0) },
            timelinePages: [MissCatTimelinePage(id: pageID, title: pageID, source: .home, accountScope: scope)],
            selectedTimelineID: pageID,
            appearance: .init(isDark: false, accentHex: "2F7CF6")
        )
    }
}

@MainActor
private final class NonCooperativeShellLoadProvider: MissCatShellConfigurationProviding {
    private let scope = MissCatShellAccountScope(instance: "one.example", userID: "shared", username: "cat")
    private var loadContinuation: CheckedContinuation<MissCatShellConfiguration, Never>?
    private let feedRepository = MockMissCatFeedRepository()

    var hasPendingLoad: Bool { loadContinuation != nil }

    func loadConfiguration() async throws -> MissCatShellConfiguration {
        await withCheckedContinuation { continuation in
            loadContinuation = continuation
        }
    }

    func resumeLoad() {
        loadContinuation?.resume(returning: configuration)
        loadContinuation = nil
    }

    func switchAccount(to scope: MissCatShellAccountScope) async throws -> MissCatShellConfiguration {
        throw MissCatShellConfigurationError.accountNotFound
    }

    func saveSelectedTimelineID(
        _ selectedID: String,
        for scope: MissCatShellAccountScope
    ) async throws {}

    func repository(for scope: MissCatShellAccountScope) throws -> any MissCatFeedRepository {
        feedRepository
    }

    private var configuration: MissCatShellConfiguration {
        let page = MissCatTimelinePage(id: "home", title: "Home", source: .home, accountScope: scope)
        return MissCatShellConfiguration(
            currentScope: scope,
            accounts: [MissCatShellAccount(scope: scope)],
            timelinePages: [page],
            selectedTimelineID: page.id,
            appearance: .init(isDark: false, accentHex: "2F7CF6")
        )
    }
}
