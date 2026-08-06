@testable import MissCat
import XCTest

final class MockMissCatFeedRepository: MissCatFeedRepository {
    struct PageRequest: Equatable {
        let source: MissCatFeedSource
        let cursor: String?
        let limit: Int
    }

    var pages: [MissCatFeedPage] = []
    var threadResult: MissCatNoteThread?
    var requestedPages: [PageRequest] = []
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
        await store.refresh()

        XCTAssertEqual(store.notes.map(\.id), ["three", "two", "one"])
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

        await store.switchAccount(to: provider.secondaryScope)

        XCTAssertEqual(store.configuration?.currentScope, provider.secondaryScope)
        XCTAssertEqual(store.selectedTimelineID, "secondary-home")
        XCTAssertEqual(provider.switchedScopes, [provider.secondaryScope])
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
