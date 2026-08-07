@testable import MissCat
import XCTest

final class MissCatDiscoveryTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DiscoveryURLProtocolStub.self]
        session = URLSession(configuration: configuration)
    }

    override func tearDown() {
        DiscoveryURLProtocolStub.handler = nil
        session.invalidateAndCancel()
        session = nil
        super.tearDown()
    }

    func testTrendAndUserSearchUseCurrentMisskeyContracts() async throws {
        var requests: [URLRequest] = []
        DiscoveryURLProtocolStub.handler = { request in
            requests.append(request)
            if request.url?.path == "/api/hashtags/trend" {
                return Self.response(request, json: [[
                    "tag": "SwiftUI",
                    "chart": [1, 2, 3],
                    "usersCount": 7,
                ]])
            }
            return Self.response(request, json: [[
                "id": "user-1",
                "username": "wada",
            ]])
        }
        let repository = MissCatMisskeyDiscoveryRepository(
            session: Self.feedSession,
            urlSession: session
        )

        let trends = try await repository.fetchTrends()
        let users = try await repository.searchUsers(query: "cat", offset: 20, limit: 150)

        XCTAssertEqual(trends.first?.tag, "SwiftUI")
        XCTAssertEqual(users.items.first?.id, "user-1")
        XCTAssertEqual(requests.map { $0.url?.path }, ["/api/hashtags/trend", "/api/users/search"])
        XCTAssertEqual(try Self.body(requests[0]).count, 0)
        XCTAssertEqual(
            try Self.body(requests[1]),
            [
                "i": "test-token",
                "query": "cat",
                "offset": 20,
                "limit": 100,
                "origin": "combined",
                "detail": true,
            ]
        )
    }

    func testSharedFeedSupportsUserAndUserListTimelineRequestShapes() async throws {
        var requests: [URLRequest] = []
        DiscoveryURLProtocolStub.handler = { request in
            requests.append(request)
            return Self.response(request, json: [])
        }
        let repository = MissCatMisskeyFeedRepository(session: Self.feedSession, urlSession: session)

        _ = try await repository.fetchPage(
            source: .user(userID: "user-2", includeReplies: true, withFiles: false),
            cursor: "cursor-1",
            limit: 120
        )
        _ = try await repository.fetchPage(
            source: .userList(listID: "list-3"),
            cursor: "cursor-2",
            limit: 40
        )

        XCTAssertEqual(requests.map { $0.url?.path }, ["/api/users/notes", "/api/notes/user-list-timeline"])
        XCTAssertEqual(
            try Self.body(requests[0]),
            [
                "i": "test-token",
                "userId": "user-2",
                "withReplies": true,
                "withRenotes": true,
                "withFiles": false,
                "limit": 100,
                "untilId": "cursor-1",
            ]
        )
        XCTAssertEqual(
            try Self.body(requests[1]),
            [
                "i": "test-token",
                "listId": "list-3",
                "limit": 40,
                "untilId": "cursor-2",
                "allowPartial": true,
            ]
        )
    }

    func testNativeHashtagDestinationUsesTagFeedContract() async throws {
        var request: URLRequest?
        DiscoveryURLProtocolStub.handler = { value in
            request = value
            return Self.response(value, json: [])
        }
        let repository = MissCatMisskeyFeedRepository(session: Self.feedSession, urlSession: session)

        _ = try await repository.fetchPage(
            source: .hashtag(tag: "ExternalRoute"),
            cursor: "cursor-tag",
            limit: 40
        )

        let captured = try XCTUnwrap(request)
        XCTAssertEqual(captured.url?.path, "/api/notes/search-by-tag")
        XCTAssertEqual(
            try Self.body(captured),
            [
                "i": "test-token",
                "tag": "ExternalRoute",
                "limit": 40,
                "untilId": "cursor-tag",
            ]
        )
    }

    func testUserTimelineRejectsInvalidRepliesAndMediaCombinationBeforeNetwork() async {
        var count = 0
        DiscoveryURLProtocolStub.handler = { request in
            count += 1
            return Self.response(request, json: [])
        }
        let repository = MissCatMisskeyFeedRepository(session: Self.feedSession, urlSession: session)

        do {
            _ = try await repository.fetchPage(
                source: .user(userID: "user", includeReplies: true, withFiles: true),
                cursor: nil,
                limit: 20
            )
            XCTFail("Expected the current users/notes contract guard")
        } catch let error as MissCatFeedRepositoryError {
            XCTAssertEqual(error, .unsupportedSource)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(count, 0)
    }

    @MainActor
    func testSearchStoreFetchesBothKindsDeduplicatesAndPaginates() async {
        let repository = DiscoveryRepositoryStub()
        repository.notePages = [
            .init(items: [Self.note("n1"), Self.note("n1")], nextCursor: "next"),
            .init(items: [Self.note("n1"), Self.note("n2")], nextCursor: nil),
        ]
        repository.userPages = [
            .init(items: [Self.user("u1"), Self.user("u1")], nextCursor: nil),
        ]
        let store = MissCatDiscoveryStore(repository: repository, pageSize: 2)
        store.query = "SwiftUI"
        store.submitSearch()
        await store.waitForPendingTasksForTesting()

        XCTAssertEqual(store.noteResults.items.map(\.id), ["n1"])
        XCTAssertEqual(store.userResults.items.map(\.id), ["u1"])
        XCTAssertEqual(repository.noteQueries, ["SwiftUI"])
        XCTAssertEqual(repository.userQueries, ["SwiftUI"])

        store.loadMoreNotesIfNeeded(currentNoteID: "n1")
        await store.waitForPendingTasksForTesting()
        XCTAssertEqual(store.noteResults.items.map(\.id), ["n1", "n2"])
        XCTAssertNil(store.noteResults.nextCursor)
    }

    @MainActor
    func testNewSearchGenerationCannotBeOverwrittenBySlowPreviousQuery() async throws {
        let repository = DiscoveryRepositoryStub()
        repository.delayedByQuery = ["old": 200_000_000, "new": 5_000_000]
        let store = MissCatDiscoveryStore(repository: repository)

        store.query = "old"
        store.submitSearch()
        try await Task.sleep(nanoseconds: 20_000_000)
        store.query = "new"
        store.submitSearch()
        try await Task.sleep(nanoseconds: 260_000_000)

        XCTAssertEqual(store.committedQuery, "new")
        XCTAssertEqual(store.noteResults.items.map(\.id), ["note-new"])
        XCTAssertEqual(store.userResults.items.map(\.id), ["user-new"])
    }

    @MainActor
    func testExternalHashtagEntryMutatesNativeStoreAndStartsAccountScopedSearch() async {
        let repository = DiscoveryRepositoryStub()
        let store = MissCatDiscoveryStore(repository: repository)

        store.search(hashtag: "  #NativeRoute  ")
        await store.waitForPendingTasksForTesting()

        XCTAssertEqual(store.query, "#NativeRoute")
        XCTAssertEqual(store.committedQuery, "#NativeRoute")
        XCTAssertEqual(store.selectedTab, .notes)
        XCTAssertEqual(repository.noteQueries, ["#NativeRoute"])
        XCTAssertEqual(repository.userQueries, ["#NativeRoute"])
    }

    @MainActor
    func testAccountSwitchCancelsOldGenerationAndRejectsLateResults() async throws {
        let oldRepository = CancellationDiscoveryRepository(accountIdentifier: "one.example::same")
        let oldGeneration = MissCatDiscoveryAccountGeneration(
            session: .init(accountID: "same", username: "one", instance: "one.example", apiKey: "one-token"),
            discoveryRepository: oldRepository,
            feedRepository: MissCatMisskeyFeedRepository(
                session: .init(accountID: "same", username: "one", instance: "one.example", apiKey: "one-token")
            )
        )
        let coordinator = MissCatDiscoveryAccountCoordinator(generation: oldGeneration)
        oldGeneration.store.query = "old-account"
        oldGeneration.store.submitSearch()
        try await Task.sleep(nanoseconds: 20_000_000)

        let nextRepository = DiscoveryRepositoryStub(accountIdentifier: "two.example::same")
        let nextGeneration = MissCatDiscoveryAccountGeneration(
            session: .init(accountID: "same", username: "two", instance: "two.example", apiKey: "two-token"),
            discoveryRepository: nextRepository,
            feedRepository: MissCatMisskeyFeedRepository(
                session: .init(accountID: "same", username: "two", instance: "two.example", apiKey: "two-token")
            )
        )
        XCTAssertTrue(coordinator.replace(with: nextGeneration))
        try await Task.sleep(nanoseconds: 40_000_000)

        XCTAssertEqual(coordinator.generation.id, nextGeneration.id)
        XCTAssertEqual(coordinator.generation.accountIdentifier, nextGeneration.session.compositeAccountID)
        XCTAssertGreaterThanOrEqual(oldRepository.cancellationCount, 2)
        XCTAssertTrue(oldGeneration.store.noteResults.items.isEmpty)
        XCTAssertTrue(oldGeneration.store.userResults.items.isEmpty)
    }

    func testTypedDiscoveryRoutesCoverEveryNativeDestinationFamily() {
        let routes: Set<MissCatDiscoveryRoute> = [
            .note("note"),
            .profile("user"),
            .userTimeline(userID: "user", includesReplies: true, onlyFiles: false),
            .userList("list"),
            .search(query: "query", tab: .users),
            .media("media"),
            .hashtag("tag"),
        ]

        XCTAssertEqual(routes.count, 7)
    }

    func testShippingTargetHasNoLegacyHomeOrSearchControllerMembership() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let project = try String(
            contentsOf: repositoryRoot.appendingPathComponent("MissCat.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )

        XCTAssertFalse(project.contains("HomeViewController.swift in Sources"))
        XCTAssertFalse(project.contains("SearchViewController.swift in Sources"))
        XCTAssertFalse(project.contains("TrendViewController.swift in Sources"))
    }

    @MainActor
    func testTerminalOfflineAndEmptyStatesBecomeVisualReady() async {
        let offline = DiscoveryRepositoryStub()
        offline.error = URLError(.notConnectedToInternet)
        let offlineStore = MissCatDiscoveryStore(repository: offline)
        offlineStore.loadTrends()
        await offlineStore.waitForPendingTasksForTesting()
        XCTAssertEqual(offlineStore.trendPhase, .offline)
        XCTAssertTrue(offlineStore.visualReady)

        let empty = DiscoveryRepositoryStub()
        empty.trends = []
        let emptyStore = MissCatDiscoveryStore(repository: empty)
        emptyStore.loadTrends()
        await emptyStore.waitForPendingTasksForTesting()
        XCTAssertEqual(emptyStore.trendPhase, .empty)
        XCTAssertTrue(emptyStore.visualReady)
    }

    func testDiscoveryIdentitySeparatesSameUserAcrossInstances() {
        let first = MissCatMisskeyDiscoveryRepository(
            session: .init(accountID: "same", username: "wada", instance: "one.example", apiKey: "token")
        )
        let second = MissCatMisskeyDiscoveryRepository(
            session: .init(accountID: "same", username: "wada", instance: "two.example", apiKey: "token")
        )
        XCTAssertNotEqual(first.accountIdentifier, second.accountIdentifier)
    }

    private static let feedSession = MissCatFeedSession(
        accountID: "user-1",
        username: "wada",
        instance: "example.test",
        apiKey: "test-token"
    )

    private static func note(_ id: String) -> MissCatNote {
        .init(id: id, author: .init(id: "author", name: "Author", username: "author"), text: id)
    }

    private static func user(_ id: String) -> MissCatProfileUser {
        .init(id: id, username: id)
    }

    private static func response(_ request: URLRequest, json: Any) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, try! JSONSerialization.data(withJSONObject: json))
    }

    private static func body(_ request: URLRequest) throws -> [String: AnyHashable] {
        let data = try XCTUnwrap(bodyData(from: request))
        let value = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: AnyHashable])
        return value
    }

    private static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var body = Data()
        let capacity = 4_096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: capacity)
            guard count >= 0 else { return nil }
            if count == 0 { break }
            body.append(buffer, count: count)
        }
        return body
    }
}

private final class DiscoveryRepositoryStub: MissCatDiscoveryRepository {
    let accountIdentifier: String
    let currentServerUserID = "fixture-me"
    var trends: [MissCatTrend] = [.init(tag: "SwiftUI")]
    var notePages: [MissCatDiscoveryPage<MissCatNote>] = []
    var userPages: [MissCatDiscoveryPage<MissCatProfileUser>] = []
    var noteQueries: [String] = []
    var userQueries: [String] = []
    var delayedByQuery: [String: UInt64] = [:]
    var error: Error?

    init(accountIdentifier: String = "fixture.example::fixture-me") {
        self.accountIdentifier = accountIdentifier
    }

    func fetchTrends() async throws -> [MissCatTrend] {
        if let error { throw error }
        return trends
    }

    func searchNotes(query: String, cursor: String?, limit: Int) async throws -> MissCatDiscoveryPage<MissCatNote> {
        noteQueries.append(query)
        if let delay = delayedByQuery[query] { try? await Task.sleep(nanoseconds: delay) }
        if let error { throw error }
        if !notePages.isEmpty { return notePages.removeFirst() }
        return .init(
            items: [.init(
                id: "note-\(query)",
                author: .init(id: "author", name: "Author", username: "author"),
                text: query
            )],
            nextCursor: nil
        )
    }

    func searchUsers(query: String, offset: Int, limit: Int) async throws -> MissCatDiscoveryPage<MissCatProfileUser> {
        userQueries.append(query)
        if let delay = delayedByQuery[query] { try? await Task.sleep(nanoseconds: delay) }
        if let error { throw error }
        if !userPages.isEmpty { return userPages.removeFirst() }
        return .init(items: [.init(id: "user-\(query)", username: query)], nextCursor: nil)
    }
}

private final class CancellationDiscoveryRepository: MissCatDiscoveryRepository {
    let accountIdentifier: String
    let currentServerUserID = "same"
    private let queue = DispatchQueue(label: "discovery-cancellation-test")
    private var cancellations = 0

    init(accountIdentifier: String) {
        self.accountIdentifier = accountIdentifier
    }

    var cancellationCount: Int {
        queue.sync { cancellations }
    }

    func fetchTrends() async throws -> [MissCatTrend] { [] }

    func searchNotes(
        query: String,
        cursor: String?,
        limit: Int
    ) async throws -> MissCatDiscoveryPage<MissCatNote> {
        try await delayedResult(.init(items: [], nextCursor: nil))
    }

    func searchUsers(
        query: String,
        offset: Int,
        limit: Int
    ) async throws -> MissCatDiscoveryPage<MissCatProfileUser> {
        try await delayedResult(.init(items: [], nextCursor: nil))
    }

    private func delayedResult<Value>(_ value: Value) async throws -> Value {
        do {
            try await Task.sleep(nanoseconds: 3_600_000_000_000)
            return value
        } catch {
            queue.sync { cancellations += 1 }
            throw error
        }
    }
}

private final class DiscoveryURLProtocolStub: URLProtocol {
    typealias Handler = (URLRequest) throws -> (HTTPURLResponse, Data)
    private static let handlerState = MissCatTestLockedState<Handler?>(nil)
    static var handler: Handler? {
        get { handlerState.value }
        set { handlerState.value = newValue }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let handler = try XCTUnwrap(Self.handler)
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
