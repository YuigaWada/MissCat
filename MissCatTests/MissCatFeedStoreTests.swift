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
    var realtimeContinuation: AsyncStream<MissCatRealtimeEvent>.Continuation?

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
        AsyncStream { realtimeContinuation = $0 }
    }

    func perform(_ action: MissCatFeedAction) async throws {
        performedActions.append(action)
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
