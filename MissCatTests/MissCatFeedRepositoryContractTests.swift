@testable import MissCat
import Foundation
import XCTest

final class MissCatFeedRepositoryContractTests: XCTestCase {
    private var urlSession: URLSession!
    private let account = MissCatFeedSession(
        accountID: "me",
        username: "alice",
        instance: "example.invalid",
        apiKey: "account-token"
    )

    override func setUp() {
        super.setUp()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FeedURLProtocolStub.self]
        urlSession = URLSession(configuration: configuration)
    }

    override func tearDown() {
        FeedURLProtocolStub.handler = nil
        urlSession.invalidateAndCancel()
        urlSession = nil
        super.tearDown()
    }

    func testModernTimelinesUseAccountTokenAndDecodeDictionaryFields() async throws {
        var requests: [URLRequest] = []
        FeedURLProtocolStub.handler = { request in
            requests.append(request)
            return Self.response(for: request, json: [Self.noteJSON(id: "note-a")])
        }
        let subject = makeSubject()

        let pages = try await [
            MissCatFeedSource.home,
            .local,
            .social,
            .global,
        ].asyncMap { source in
            try await subject.fetchPage(source: source, cursor: "older", limit: 1)
        }

        XCTAssertEqual(
            requests.compactMap { $0.url?.path },
            [
                "/api/notes/timeline",
                "/api/notes/local-timeline",
                "/api/notes/hybrid-timeline",
                "/api/notes/global-timeline",
            ]
        )
        for request in requests {
            let body = try XCTUnwrap(request.feedBodyData).feedJSONObject
            XCTAssertEqual(body["i"] as? String, "account-token")
            XCTAssertEqual(body["untilId"] as? String, "older")
            XCTAssertEqual(body["limit"] as? Int, 1)
        }
        XCTAssertTrue(pages.allSatisfy(\.hasMore))
        let note = try XCTUnwrap(pages.first?.notes.first)
        XCTAssertEqual(note.id, "note-a")
        XCTAssertEqual(note.noteID, "note-a")
        XCTAssertEqual(note.reactions, [
            MissCatReaction(name: ":party:", count: 2, isMine: true),
            MissCatReaction(name: "like", count: 4, isMine: false),
        ])
        XCTAssertEqual(note.attachments.first?.kind, .image)
        XCTAssertEqual(note.attachments.first?.width, 640)
        XCTAssertEqual(note.poll?.choices.first?.votes, 3)
    }

    func testSearchAndHashtagUseCurrentRequestShapes() async throws {
        var requests: [URLRequest] = []
        FeedURLProtocolStub.handler = { request in
            requests.append(request)
            return Self.response(for: request, json: [])
        }
        let subject = makeSubject()

        _ = try await subject.fetchPage(source: .search(query: "swift ui"), cursor: "older", limit: 20)
        _ = try await subject.fetchPage(source: .hashtag(tag: "SwiftUI"), cursor: nil, limit: 20)

        XCTAssertEqual(requests.compactMap { $0.url?.path }, ["/api/notes/search", "/api/notes/search-by-tag"])
        let search = try XCTUnwrap(requests[0].feedBodyData).feedJSONObject
        XCTAssertEqual(search["query"] as? String, "swift ui")
        XCTAssertEqual(search["untilId"] as? String, "older")
        let hashtag = try XCTUnwrap(requests[1].feedBodyData).feedJSONObject
        XCTAssertEqual(hashtag["tag"] as? String, "SwiftUI")
        XCTAssertNil(hashtag["query"])
        XCTAssertNil(hashtag["untilId"])
    }

    func testFavoritesDecodeWrapperAndPageByFavoriteID() async throws {
        var capturedRequest: URLRequest?
        FeedURLProtocolStub.handler = { request in
            capturedRequest = request
            return Self.response(
                for: request,
                json: [[
                    "id": "favorite-wrapper-id",
                    "createdAt": "2026-08-07T00:00:00.000Z",
                    "noteId": "note-a",
                    "note": Self.noteJSON(id: "note-a"),
                ]]
            )
        }
        let subject = makeSubject()

        let page = try await subject.fetchPage(source: .favorites, cursor: "older-favorite-id", limit: 1)

        XCTAssertEqual(capturedRequest?.url?.path, "/api/i/favorites")
        let body = try XCTUnwrap(capturedRequest?.feedBodyData).feedJSONObject
        XCTAssertEqual(body["untilId"] as? String, "older-favorite-id")
        XCTAssertEqual(page.notes.first?.id, "favorite-wrapper-id")
        XCTAssertEqual(page.notes.first?.noteID, "note-a")
        XCTAssertEqual(page.notes.first?.isFavorite, true)
        XCTAssertTrue(page.hasMore)
    }

    func testThreadUsesShowForAncestorsAndChildrenForReplies() async throws {
        var requestedPaths: [String] = []
        FeedURLProtocolStub.handler = { request in
            let path = try XCTUnwrap(request.url?.path)
            requestedPaths.append(path)
            let body = try XCTUnwrap(request.feedBodyData).feedJSONObject
            if path.hasSuffix("notes/children") {
                XCTAssertEqual(body["noteId"] as? String, "root")
                XCTAssertEqual(body["limit"] as? Int, 30)
                return Self.response(for: request, json: [Self.noteJSON(id: "child")])
            }
            let noteID = try XCTUnwrap(body["noteId"] as? String)
            switch noteID {
            case "root": return Self.response(for: request, json: Self.noteJSON(id: "root", replyId: "parent"))
            case "parent": return Self.response(for: request, json: Self.noteJSON(id: "parent"))
            default:
                XCTFail("Unexpected note ID \(noteID)")
                return Self.response(for: request, status: 404, json: [:])
            }
        }
        let subject = makeSubject()

        let thread = try await subject.fetchThread(noteID: "root", replyLimit: 30)

        XCTAssertEqual(requestedPaths, ["/api/notes/show", "/api/notes/show", "/api/notes/children"])
        XCTAssertEqual(thread.ancestors.map(\.id), ["parent"])
        XCTAssertEqual(thread.note.id, "root")
        XCTAssertEqual(thread.replies.map(\.id), ["child"])
    }

    func testActionsUseCurrentEndpointsAndExactBodies() async throws {
        var requests: [URLRequest] = []
        FeedURLProtocolStub.handler = { request in
            requests.append(request)
            if request.url?.path == "/api/notes/create" {
                return Self.response(for: request, json: ["createdNote": Self.noteJSON(id: "renote-result")])
            }
            return Self.response(for: request, status: 204, data: Data())
        }
        let subject = makeSubject()

        try await subject.perform(.favorite(noteID: "n1"))
        try await subject.perform(.unfavorite(noteID: "n2"))
        try await subject.perform(.addReaction(noteID: "n3", reaction: ":party:"))
        try await subject.perform(.removeReaction(noteID: "n4"))
        try await subject.perform(.renote(noteID: "n5"))
        try await subject.perform(.vote(noteID: "n6", choice: 2))

        XCTAssertEqual(
            requests.compactMap { $0.url?.path },
            [
                "/api/notes/favorites/create",
                "/api/notes/favorites/delete",
                "/api/notes/reactions/create",
                "/api/notes/reactions/delete",
                "/api/notes/create",
                "/api/notes/polls/vote",
            ]
        )
        let bodies = try requests.map { try XCTUnwrap($0.feedBodyData).feedJSONObject }
        XCTAssertEqual(bodies[0] as NSDictionary, ["i": "account-token", "noteId": "n1"] as NSDictionary)
        XCTAssertEqual(bodies[1] as NSDictionary, ["i": "account-token", "noteId": "n2"] as NSDictionary)
        XCTAssertEqual(bodies[2] as NSDictionary, ["i": "account-token", "noteId": "n3", "reaction": ":party:"] as NSDictionary)
        XCTAssertEqual(bodies[3] as NSDictionary, ["i": "account-token", "noteId": "n4"] as NSDictionary)
        XCTAssertEqual(bodies[4] as NSDictionary, ["i": "account-token", "renoteId": "n5"] as NSDictionary)
        XCTAssertEqual(bodies[5]["i"] as? String, "account-token")
        XCTAssertEqual(bodies[5]["noteId"] as? String, "n6")
        XCTAssertEqual(bodies[5]["choice"] as? Int, 2)
    }

    func testSuccessfulWriteNeverBecomesDecodeFailure() async throws {
        FeedURLProtocolStub.handler = { request in
            Self.response(for: request, status: 200, data: Data("not-json".utf8))
        }
        let subject = makeSubject()

        try await subject.perform(.renote(noteID: "n1"))
        try await subject.perform(.favorite(noteID: "n1"))
    }

    func testHTTPFailureSurfacesMisskeyMessageAndStatus() async {
        FeedURLProtocolStub.handler = { request in
            Self.response(for: request, status: 403, json: ["error": ["message": "Permission denied"]])
        }
        let subject = makeSubject()

        do {
            _ = try await subject.fetchPage(source: .home, cursor: nil, limit: 20)
            XCTFail("Expected request to fail")
        } catch {
            XCTAssertEqual(error as? MissCatFeedRepositoryError, .http(403, "Permission denied"))
        }
    }

    func testInvalidInstanceDoesNotStartNetworkRequest() async {
        var requestCount = 0
        FeedURLProtocolStub.handler = { request in
            requestCount += 1
            return Self.response(for: request, json: [])
        }
        let invalid = MissCatFeedSession(accountID: "me", username: "alice", instance: "", apiKey: "token")
        let subject = MissCatMisskeyFeedRepository(session: invalid, urlSession: urlSession)

        do {
            _ = try await subject.fetchPage(source: .home, cursor: nil, limit: 20)
            XCTFail("Expected request to fail")
        } catch {
            XCTAssertEqual(error as? MissCatFeedRepositoryError, .invalidInstance)
            XCTAssertEqual(requestCount, 0)
        }
    }

    private func makeSubject() -> MissCatMisskeyFeedRepository {
        MissCatMisskeyFeedRepository(session: account, urlSession: urlSession)
    }

    private static func response(for request: URLRequest, status: Int = 200, json: Any) -> (HTTPURLResponse, Data) {
        response(for: request, status: status, data: try! JSONSerialization.data(withJSONObject: json))
    }

    private static func response(for request: URLRequest, status: Int, data: Data) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (response, data)
    }

    fileprivate static func noteJSON(id: String, replyId: String? = nil) -> [String: Any] {
        var note: [String: Any] = [
            "id": id,
            "createdAt": "2026-08-07T00:00:00.000Z",
            "text": "Hello :party:",
            "cw": NSNull(),
            "userId": "user-a",
            "user": [
                "id": "user-a", "name": "Alice", "username": "alice", "host": NSNull(),
                "avatarUrl": "https://example.invalid/avatar.png", "isCat": true,
                "emojis": ["party": "https://example.invalid/party.webp"],
            ],
            "visibility": "public",
            "files": [[
                "id": "file-a", "name": "photo.png", "type": "image/png",
                "url": "https://example.invalid/photo.png",
                "thumbnailUrl": "https://example.invalid/thumb.png", "isSensitive": false,
                "properties": ["width": 640, "height": 480],
            ]],
            "tags": ["SwiftUI"],
            "poll": [
                "expiresAt": "2026-08-08T00:00:00.000Z", "multiple": false,
                "choices": [["isVoted": true, "text": "Yes", "votes": 3]],
            ],
            "emojis": ["party": "https://example.invalid/party.webp"],
            "reactionEmojis": ["party": "https://example.invalid/party.webp"],
            "reactions": [":party:": 2, "like": 4],
            "reactionCount": 6, "renoteCount": 2, "repliesCount": 1, "myReaction": ":party:",
        ]
        if let replyId { note["replyId"] = replyId }
        return note
    }
}

private final class FeedURLProtocolStub: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let (response, data) = try XCTUnwrap(Self.handler)(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if !data.isEmpty { client?.urlProtocol(self, didLoad: data) }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private extension URLRequest {
    var feedBodyData: Data? {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var result = Data()
        let bufferSize = 4_096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: bufferSize)
            guard count > 0 else { break }
            result.append(buffer, count: count)
        }
        return result
    }
}

private extension Data {
    var feedJSONObject: [String: Any] {
        get throws { try XCTUnwrap(JSONSerialization.jsonObject(with: self) as? [String: Any]) }
    }
}

private extension Array {
    func asyncMap<Transformed>(_ transform: (Element) async throws -> Transformed) async rethrows -> [Transformed] {
        var values: [Transformed] = []
        for element in self { values.append(try await transform(element)) }
        return values
    }
}
