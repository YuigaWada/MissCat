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
    let accountIdentifier = "fixture.example::fixture-me"
    let currentServerUserID = "fixture-me"
    var trends: [MissCatTrend] = [.init(tag: "SwiftUI")]
    var notePages: [MissCatDiscoveryPage<MissCatNote>] = []
    var userPages: [MissCatDiscoveryPage<MissCatProfileUser>] = []
    var noteQueries: [String] = []
    var userQueries: [String] = []
    var delayedByQuery: [String: UInt64] = [:]
    var error: Error?

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

private final class DiscoveryURLProtocolStub: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

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
