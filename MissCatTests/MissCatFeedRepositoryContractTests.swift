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
            MissCatReaction(
                name: ":party:",
                count: 2,
                isMine: true,
                emojiURL: URL(string: "https://example.invalid/party.webp")
            ),
            MissCatReaction(name: "like", count: 4, isMine: false),
        ])
        XCTAssertEqual(note.emojis["party"], URL(string: "https://example.invalid/party.webp"))
        XCTAssertEqual(note.author.emojis["party"], URL(string: "https://example.invalid/party.webp"))
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

    func testMentionResolutionUsesUsersShowAndReturnsServerUserID() async throws {
        var requests: [URLRequest] = []
        FeedURLProtocolStub.handler = { request in
            requests.append(request)
            return Self.response(for: request, json: [
                "id": "resolved-user",
                "name": "Alice",
                "username": "alice",
                "host": NSNull(),
                "avatarUrl": NSNull(),
                "isCat": false,
                "emojis": [:],
            ])
        }
        let subject = makeSubject()

        let localID = try await subject.resolveMention("alice@example.invalid")
        let remoteID = try await subject.resolveMention("@alice@remote.invalid")

        XCTAssertEqual(localID, "resolved-user")
        XCTAssertEqual(remoteID, "resolved-user")
        XCTAssertEqual(requests.compactMap { $0.url?.path }, ["/api/users/show", "/api/users/show"])
        let localBody = try XCTUnwrap(requests[0].feedBodyData).feedJSONObject
        XCTAssertEqual(localBody["i"] as? String, "account-token")
        XCTAssertEqual(localBody["username"] as? String, "alice")
        XCTAssertNil(localBody["host"])
        let remoteBody = try XCTUnwrap(requests[1].feedBodyData).feedJSONObject
        XCTAssertEqual(remoteBody["host"] as? String, "remote.invalid")
    }

    func testUserAndListFeedsUseScopedNativeRequestShapes() async throws {
        var requests: [URLRequest] = []
        FeedURLProtocolStub.handler = { request in
            requests.append(request)
            return Self.response(for: request, json: [])
        }
        let subject = makeSubject()

        _ = try await subject.fetchPage(
            source: .user(userID: "remote-user", includeReplies: false, withFiles: false),
            cursor: "older-user",
            limit: 12
        )
        _ = try await subject.fetchPage(
            source: .userList(listID: "cats-list"),
            cursor: "older-list",
            limit: 13
        )

        XCTAssertEqual(
            requests.compactMap { $0.url?.path },
            ["/api/users/notes", "/api/notes/user-list-timeline"]
        )
        let user = try XCTUnwrap(requests[0].feedBodyData).feedJSONObject
        XCTAssertEqual(user["i"] as? String, "account-token")
        XCTAssertEqual(user["userId"] as? String, "remote-user")
        XCTAssertEqual(user["untilId"] as? String, "older-user")
        XCTAssertEqual(user["limit"] as? Int, 12)
        let list = try XCTUnwrap(requests[1].feedBodyData).feedJSONObject
        XCTAssertEqual(list["i"] as? String, "account-token")
        XCTAssertEqual(list["listId"] as? String, "cats-list")
        XCTAssertEqual(list["untilId"] as? String, "older-list")
        XCTAssertEqual(list["limit"] as? Int, 13)
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
        try await subject.perform(.delete(noteID: "n7"))
        try await subject.perform(.mute(userID: "u8"))
        try await subject.perform(.block(userID: "u9"))
        try await subject.perform(.report(userID: "u10", comment: "abuse evidence"))

        XCTAssertEqual(
            requests.compactMap { $0.url?.path },
            [
                "/api/notes/favorites/create",
                "/api/notes/favorites/delete",
                "/api/notes/reactions/create",
                "/api/notes/reactions/delete",
                "/api/notes/create",
                "/api/notes/polls/vote",
                "/api/notes/delete",
                "/api/mute/create",
                "/api/blocking/create",
                "/api/users/report-abuse",
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
        XCTAssertEqual(bodies[6] as NSDictionary, ["i": "account-token", "noteId": "n7"] as NSDictionary)
        XCTAssertEqual(bodies[7] as NSDictionary, ["i": "account-token", "userId": "u8"] as NSDictionary)
        XCTAssertEqual(bodies[8] as NSDictionary, ["i": "account-token", "userId": "u9"] as NSDictionary)
        XCTAssertEqual(
            bodies[9] as NSDictionary,
            ["i": "account-token", "userId": "u10", "comment": "abuse evidence"] as NSDictionary
        )
    }

    func testReportEndpointValidatesOne2048And2049CharacterBoundaries() async throws {
        var requests: [URLRequest] = []
        FeedURLProtocolStub.handler = { request in
            requests.append(request)
            return Self.response(for: request, status: 204, data: Data())
        }
        let subject = makeSubject()
        let maximum = String(repeating: "猫", count: 2_048)

        try await subject.perform(.report(userID: "one", comment: "x"))
        try await subject.perform(.report(userID: "maximum", comment: maximum))
        do {
            try await subject.perform(
                .report(userID: "too-long", comment: String(repeating: "猫", count: 2_049))
            )
            XCTFail("2049-character reports must be rejected before networking")
        } catch {
            XCTAssertEqual(error as? MissCatFeedRepositoryError, .invalidReportComment)
        }

        XCTAssertEqual(requests.count, 2)
        let bodies = try requests.map { try XCTUnwrap($0.feedBodyData).feedJSONObject }
        XCTAssertEqual(bodies[0]["comment"] as? String, "x")
        XCTAssertEqual(bodies[1]["comment"] as? String, maximum)
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

    func testStreamingUsesSecretSafeRequestAndExactConnectAcknowledgement() async throws {
        let socket = FeedFakeWebSocket()
        let factory = FeedFakeWebSocketFactory(sockets: [socket])
        let subject = makeStreamingSubject(factory: factory, streamID: "stream-home")
        let recorder = FeedRealtimeEventRecorder()
        let task = record(
            subject.realtimeEvents(source: .home, capturing: ["captured-a"]),
            in: recorder
        )

        await assertEventually(awaitValue { socket.resumeCount == 1 && socket.sentObjects.count == 1 })
        let request = try XCTUnwrap(factory.requests.first)
        XCTAssertEqual(request.url?.scheme, "wss")
        XCTAssertEqual(request.url?.host, "example.invalid")
        XCTAssertEqual(request.url?.path, "/streaming")
        XCTAssertNil(request.url?.query)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer account-token")
        XCTAssertFalse(try XCTUnwrap(request.url?.absoluteString).contains("account-token"))

        let connect = try XCTUnwrap(socket.sentObjects.first)
        XCTAssertEqual(connect["type"] as? String, "connect")
        let body = try XCTUnwrap(connect["body"] as? [String: Any])
        XCTAssertEqual(body["channel"] as? String, "homeTimeline")
        XCTAssertEqual(body["id"] as? String, "stream-home")
        XCTAssertEqual(body["params"] as? NSDictionary, [:] as NSDictionary)
        XCTAssertEqual(body["pong"] as? Bool, true)
        XCTAssertFalse(socket.sentText.contains("account-token"))

        socket.push(json: ["type": "connected", "body": ["id": "another-stream"]])
        try await Task.sleep(nanoseconds: 20_000_000)
        let beforeAck = await recorder.snapshot()
        XCTAssertTrue(beforeAck.isEmpty)

        socket.push(json: ["type": "connected", "body": ["id": "stream-home"]])
        await assertEventually(awaitValue {
            let values = await recorder.snapshot()
            return values.contains(.connected(true))
                && socket.sentObjects.contains {
                    $0["type"] as? String == "subNote"
                        && (($0["body"] as? [String: Any])?["id"] as? String) == "captured-a"
                }
        })

        task.cancel()
    }

    func testStreamingMapsAllCurrentTimelineChannelNames() async throws {
        let mappings: [(MissCatFeedSource, String)] = [
            (.home, "homeTimeline"),
            (.local, "localTimeline"),
            (.social, "hybridTimeline"),
            (.global, "globalTimeline"),
        ]

        for (source, expectedChannel) in mappings {
            let socket = FeedFakeWebSocket()
            let factory = FeedFakeWebSocketFactory(sockets: [socket])
            let subject = makeStreamingSubject(factory: factory, streamID: "stream-map")
            let task = Task {
                for await _ in subject.realtimeEvents(source: source, capturing: []) {}
            }

            await assertEventually(awaitValue { !socket.sentObjects.isEmpty })
            let connect = try XCTUnwrap(socket.sentObjects.first)
            let body = try XCTUnwrap(connect["body"] as? [String: Any])
            XCTAssertEqual(body["channel"] as? String, expectedChannel)
            task.cancel()
            await assertEventually(awaitValue { socket.cancelCount == 1 })
        }
    }

    func testStreamingDecodesCurrentDictionaryNoteEnvelopeAndSubscribesToIt() async throws {
        let socket = FeedFakeWebSocket()
        let factory = FeedFakeWebSocketFactory(sockets: [socket])
        let subject = makeStreamingSubject(factory: factory, streamID: "stream-note")
        let recorder = FeedRealtimeEventRecorder()
        let task = record(subject.realtimeEvents(source: .local, capturing: []), in: recorder)

        await assertEventually(awaitValue { !socket.sentObjects.isEmpty })
        socket.push(json: ["type": "connected", "body": ["id": "stream-note"]])
        await assertEventually(awaitValue {
            let values = await recorder.snapshot()
            return values.contains(.connected(true))
        })

        socket.push(json: [
            "type": "channel",
            "body": [
                "id": "stream-note",
                "type": "note",
                "body": Self.noteJSON(id: "live-note"),
            ],
        ])

        await assertEventually(awaitValue {
            let values = await recorder.snapshot()
            return values.contains { event in
                guard case let .inserted(note) = event else { return false }
                return note.noteID == "live-note"
                    && note.attachments.first?.width == 640
                    && note.poll?.choices.first?.votes == 3
            }
        })
        XCTAssertTrue(socket.sentObjects.contains {
            $0["type"] as? String == "subNote"
                && (($0["body"] as? [String: Any])?["id"] as? String) == "live-note"
        })

        task.cancel()
    }

    func testStreamingDecodesEveryCurrentNoteUpdatedVariantAndIsMine() async throws {
        let socket = FeedFakeWebSocket()
        let factory = FeedFakeWebSocketFactory(sockets: [socket])
        let subject = makeStreamingSubject(factory: factory, streamID: "stream-updates")
        let recorder = FeedRealtimeEventRecorder()
        let task = record(
            subject.realtimeEvents(source: .social, capturing: ["note-a"]),
            in: recorder
        )

        await assertEventually(awaitValue { !socket.sentObjects.isEmpty })
        socket.push(json: ["type": "connected", "body": ["id": "stream-updates"]])
        await assertEventually(awaitValue {
            let values = await recorder.snapshot()
            return values.contains(.connected(true))
        })

        socket.push(json: Self.noteUpdated(
            id: "note-a",
            type: "reacted",
            body: ["reaction": ":party:", "userId": "me"]
        ))
        socket.push(json: Self.noteUpdated(
            id: "note-a",
            type: "unreacted",
            body: ["reaction": "like", "userId": "someone-else"]
        ))
        socket.push(json: Self.noteUpdated(
            id: "note-a",
            type: "pollVoted",
            body: ["choice": 2, "userId": "me"]
        ))
        socket.push(json: Self.noteUpdated(
            id: "note-a",
            type: "deleted",
            body: ["deletedAt": "2026-08-07T00:00:00.000Z"]
        ))

        await assertEventually(awaitValue {
            let values = await recorder.snapshot()
            return values.contains(.reaction(
                noteID: "note-a",
                reaction: ":party:",
                delta: 1,
                isMine: true
            ))
                && values.contains(.reaction(
                    noteID: "note-a",
                    reaction: "like",
                    delta: -1,
                    isMine: false
                ))
                && values.contains(.pollVote(noteID: "note-a", choice: 2, isMine: true))
                && values.contains(.removed(noteID: "note-a"))
        })

        task.cancel()
    }

    func testSiblingStreamsIgnoreOtherChannelAndCapturedNoteEvents() async throws {
        let socketA = FeedFakeWebSocket()
        let socketB = FeedFakeWebSocket()
        let factory = FeedFakeWebSocketFactory(sockets: [socketA, socketB])
        let IDs = FeedStreamIDSequence(["stream-a", "stream-b"])
        let subject = MissCatMisskeyFeedRepository(
            session: account,
            urlSession: urlSession,
            webSocketFactory: factory,
            makeStreamID: { IDs.next() }
        )
        let recorderA = FeedRealtimeEventRecorder()
        let recorderB = FeedRealtimeEventRecorder()
        let taskA = record(
            subject.realtimeEvents(source: .home, capturing: ["note-a"]),
            in: recorderA
        )
        await assertEventually(awaitValue { !socketA.sentObjects.isEmpty })
        let taskB = record(
            subject.realtimeEvents(source: .global, capturing: ["note-b"]),
            in: recorderB
        )
        await assertEventually(awaitValue { !socketB.sentObjects.isEmpty })

        socketA.push(json: ["type": "connected", "body": ["id": "stream-a"]])
        socketB.push(json: ["type": "connected", "body": ["id": "stream-b"]])
        await assertEventually(awaitValue {
            let a = await recorderA.snapshot()
            let b = await recorderB.snapshot()
            return a.contains(.connected(true)) && b.contains(.connected(true))
        })

        socketA.push(json: [
            "type": "channel",
            "body": [
                "id": "stream-b",
                "type": "note",
                "body": Self.noteJSON(id: "wrong-channel"),
            ],
        ])
        socketA.push(json: Self.noteUpdated(
            id: "note-b",
            type: "reacted",
            body: ["reaction": "wrong", "userId": "me"]
        ))
        socketA.push(json: Self.noteUpdated(
            id: "note-a",
            type: "reacted",
            body: ["reaction": "right-a", "userId": "me"]
        ))
        socketB.push(json: Self.noteUpdated(
            id: "note-b",
            type: "reacted",
            body: ["reaction": "right-b", "userId": "me"]
        ))

        await assertEventually(awaitValue {
            let a = await recorderA.snapshot()
            let b = await recorderB.snapshot()
            return a.contains(.reaction(noteID: "note-a", reaction: "right-a", delta: 1, isMine: true))
                && b.contains(.reaction(noteID: "note-b", reaction: "right-b", delta: 1, isMine: true))
        })
        let valuesA = await recorderA.snapshot()
        let valuesB = await recorderB.snapshot()
        XCTAssertFalse(valuesA.contains { event in
            if case let .inserted(note) = event { return note.noteID == "wrong-channel" }
            if case let .reaction(_, reaction, _, _) = event { return reaction == "wrong" }
            return false
        })
        XCTAssertFalse(valuesB.contains { event in
            if case let .reaction(noteID, _, _, _) = event { return noteID == "note-a" }
            return false
        })

        taskA.cancel()
        taskB.cancel()
    }

    func testStreamingTerminationUnsubscribesDisconnectsAndClosesSocket() async throws {
        let socket = FeedFakeWebSocket()
        let factory = FeedFakeWebSocketFactory(sockets: [socket])
        let subject = makeStreamingSubject(factory: factory, streamID: "stream-stop")
        let task = Task {
            for await _ in subject.realtimeEvents(
                source: .home,
                capturing: ["note-b", "note-a"]
            ) {}
        }

        await assertEventually(awaitValue { !socket.sentObjects.isEmpty })
        socket.push(json: ["type": "connected", "body": ["id": "stream-stop"]])
        await assertEventually(awaitValue {
            socket.sentObjects.filter { $0["type"] as? String == "subNote" }.count == 2
        })
        task.cancel()

        await assertEventually(awaitValue {
            let objects = socket.sentObjects
            let unsubscribed = Set(objects.compactMap { object -> String? in
                guard object["type"] as? String == "unsubNote" else { return nil }
                return (object["body"] as? [String: Any])?["id"] as? String
            })
            let disconnected = objects.contains { object in
                object["type"] as? String == "disconnect"
                    && ((object["body"] as? [String: Any])?["id"] as? String) == "stream-stop"
            }
            return unsubscribed == Set(["note-a", "note-b"])
                && disconnected
                && socket.cancelCount == 1
        })
    }

    func testReconnectResubscribesThenPerformsRESTResyncAndIgnoresStaleSocket() async throws {
        let first = FeedFakeWebSocket()
        let second = FeedFakeWebSocket()
        let factory = FeedFakeWebSocketFactory(sockets: [first, second])
        var resyncRequests: [URLRequest] = []
        FeedURLProtocolStub.handler = { request in
            resyncRequests.append(request)
            return Self.response(
                for: request,
                json: [Self.noteJSON(id: "note-old"), Self.noteJSON(id: "note-new")]
            )
        }
        let subject = makeStreamingSubject(
            factory: factory,
            streamID: "stream-reconnect",
            configuration: MissCatFeedRealtimeConfiguration(
                maximumReconnectAttempts: 3,
                baseReconnectDelayNanoseconds: 0,
                maximumReconnectDelayNanoseconds: 0,
                resynchronizationLimit: 100
            ),
            reconnectSleep: { _ in }
        )
        let recorder = FeedRealtimeEventRecorder()
        let task = record(
            subject.realtimeEvents(source: .home, capturing: ["note-old"]),
            in: recorder
        )

        await assertEventually(awaitValue { !first.sentObjects.isEmpty })
        first.push(json: ["type": "connected", "body": ["id": "stream-reconnect"]])
        await assertEventually(awaitValue {
            let values = await recorder.snapshot()
            return values.contains(.connected(true))
        })
        first.push(json: [
            "type": "channel",
            "body": [
                "id": "stream-reconnect",
                "type": "note",
                "body": Self.noteJSON(id: "note-live"),
            ],
        ])
        await assertEventually(awaitValue {
            let values = await recorder.snapshot()
            return values.contains { event in
                guard case let .inserted(note) = event else { return false }
                return note.noteID == "note-live"
            }
        })

        first.fail(FeedFakeWebSocketError.connectionLost)
        await assertEventually(awaitValue { !second.sentObjects.isEmpty })
        second.push(json: ["type": "connected", "body": ["id": "stream-reconnect"]])

        await assertEventually(awaitValue {
            let values = await recorder.snapshot()
            let connectedCount = values.filter { $0 == .connected(true) }.count
            let replaced = values.contains { event in
                guard case let .replaced(note) = event else { return false }
                return note.noteID == "note-old"
            }
            let inserted = values.contains { event in
                guard case let .inserted(note) = event else { return false }
                return note.noteID == "note-new"
            }
            return connectedCount == 2 && replaced && inserted && resyncRequests.count == 1
        })

        let secondTypes = second.sentObjects.compactMap { $0["type"] as? String }
        XCTAssertEqual(secondTypes.first, "connect")
        XCTAssertEqual(Array(secondTypes.dropFirst().prefix(2)), ["subNote", "subNote"])
        let resubscribedBeforeResync = Set(second.sentObjects.dropFirst().prefix(2).compactMap {
            ($0["body"] as? [String: Any])?["id"] as? String
        })
        XCTAssertEqual(resubscribedBeforeResync, Set(["note-live", "note-old"]))
        XCTAssertTrue(second.sentObjects.contains {
            $0["type"] as? String == "subNote"
                && (($0["body"] as? [String: Any])?["id"] as? String) == "note-new"
        })
        let resyncBody = try XCTUnwrap(resyncRequests.first?.feedBodyData).feedJSONObject
        XCTAssertEqual(resyncBody["i"] as? String, "account-token")
        XCTAssertEqual(resyncBody["limit"] as? Int, 100)

        let beforeStale = await recorder.snapshot()
        first.push(json: Self.noteUpdated(
            id: "note-old",
            type: "reacted",
            body: ["reaction": "stale", "userId": "me"]
        ))
        try await Task.sleep(nanoseconds: 20_000_000)
        let afterStale = await recorder.snapshot()
        XCTAssertEqual(afterStale, beforeStale)

        task.cancel()
    }

    func testMalformedUnknownAndWrongIdentifiersAreIgnored() async throws {
        let socket = FeedFakeWebSocket()
        let factory = FeedFakeWebSocketFactory(sockets: [socket])
        let subject = makeStreamingSubject(factory: factory, streamID: "stream-filter")
        let recorder = FeedRealtimeEventRecorder()
        let task = record(
            subject.realtimeEvents(source: .global, capturing: ["note-a"]),
            in: recorder
        )

        await assertEventually(awaitValue { !socket.sentObjects.isEmpty })
        socket.push(json: ["type": "connected", "body": ["id": "stream-filter"]])
        await assertEventually(awaitValue {
            let values = await recorder.snapshot()
            return values.contains(.connected(true))
        })

        socket.push(text: "{not-json")
        socket.push(json: ["type": "futureEvent", "body": ["anything": true]])
        socket.push(json: [
            "type": "channel",
            "body": [
                "id": "wrong-stream",
                "type": "note",
                "body": Self.noteJSON(id: "wrong-note"),
            ],
        ])
        socket.push(json: Self.noteUpdated(
            id: "uncaptured",
            type: "reacted",
            body: ["reaction": "ignored", "userId": "me"]
        ))
        socket.push(json: Self.noteUpdated(
            id: "note-a",
            type: "deleted",
            body: [:]
        ))
        socket.push(json: Self.noteUpdated(
            id: "note-a",
            type: "reacted",
            body: ["reaction": "accepted", "userId": "me"]
        ))

        await assertEventually(awaitValue {
            let values = await recorder.snapshot()
            return values.contains(
                .reaction(noteID: "note-a", reaction: "accepted", delta: 1, isMine: true)
            )
        })
        let values = await recorder.snapshot()
        let mutations = values.filter {
            if case .connected = $0 { return false }
            return true
        }
        XCTAssertEqual(
            mutations,
            [.reaction(noteID: "note-a", reaction: "accepted", delta: 1, isMine: true)]
        )

        task.cancel()
    }

    func testReconnectDelayIsBoundedExponential() {
        let configuration = MissCatFeedRealtimeConfiguration(
            maximumReconnectAttempts: 6,
            baseReconnectDelayNanoseconds: 500_000_000,
            maximumReconnectDelayNanoseconds: 30_000_000_000,
            resynchronizationLimit: 100
        )

        XCTAssertEqual(configuration.reconnectDelayNanoseconds(forAttempt: 0), 500_000_000)
        XCTAssertEqual(configuration.reconnectDelayNanoseconds(forAttempt: 1), 500_000_000)
        XCTAssertEqual(configuration.reconnectDelayNanoseconds(forAttempt: 2), 1_000_000_000)
        XCTAssertEqual(configuration.reconnectDelayNanoseconds(forAttempt: 3), 2_000_000_000)
        XCTAssertEqual(configuration.reconnectDelayNanoseconds(forAttempt: 7), 30_000_000_000)
        XCTAssertEqual(configuration.reconnectDelayNanoseconds(forAttempt: 100), 30_000_000_000)
    }

    private func makeStreamingSubject(
        factory: FeedFakeWebSocketFactory,
        streamID: String,
        configuration: MissCatFeedRealtimeConfiguration = .live,
        reconnectSleep: @escaping @Sendable (UInt64) async throws -> Void = { nanoseconds in
            try await Task.sleep(nanoseconds: nanoseconds)
        }
    ) -> MissCatMisskeyFeedRepository {
        MissCatMisskeyFeedRepository(
            session: account,
            urlSession: urlSession,
            webSocketFactory: factory,
            realtimeConfiguration: configuration,
            makeStreamID: { streamID },
            reconnectSleep: reconnectSleep
        )
    }

    private func record(
        _ stream: AsyncStream<MissCatRealtimeEvent>,
        in recorder: FeedRealtimeEventRecorder
    ) -> Task<Void, Never> {
        Task {
            for await event in stream {
                await recorder.append(event)
            }
        }
    }

    private func awaitValue(
        timeout: TimeInterval = 2,
        condition: @escaping () async -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return true }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return await condition()
    }

    private func assertEventually(
        _ value: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(value, file: file, line: line)
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

    private static func noteUpdated(
        id: String,
        type: String,
        body: [String: Any]
    ) -> [String: Any] {
        [
            "type": "noteUpdated",
            "body": ["id": id, "type": type, "body": body] as [String: Any],
        ]
    }
}

private actor FeedRealtimeEventRecorder {
    private var values: [MissCatRealtimeEvent] = []

    func append(_ event: MissCatRealtimeEvent) {
        values.append(event)
    }

    func snapshot() -> [MissCatRealtimeEvent] {
        values
    }
}

private enum FeedFakeWebSocketError: Error {
    case connectionLost
}

private final class FeedFakeWebSocket: MissCatFeedWebSocket {
    private typealias MessageResult = Result<URLSessionWebSocketTask.Message, Error>

    private let lock = NSLock()
    private var queuedResults: [MessageResult] = []
    private var pendingReceive: CheckedContinuation<URLSessionWebSocketTask.Message, Error>?
    private var storedSentMessages: [URLSessionWebSocketTask.Message] = []
    private var storedResumeCount = 0
    private var storedCancelCount = 0

    var resumeCount: Int { lock.feedWithLock { storedResumeCount } }
    var cancelCount: Int { lock.feedWithLock { storedCancelCount } }

    var sentObjects: [[String: Any]] {
        lock.feedWithLock { storedSentMessages }.compactMap { message in
            let data: Data
            switch message {
            case let .string(text): data = Data(text.utf8)
            case let .data(messageData): data = messageData
            @unknown default: return nil
            }
            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }
    }

    var sentText: String {
        lock.feedWithLock { storedSentMessages }.compactMap { message in
            switch message {
            case let .string(text): text
            case let .data(data): String(data: data, encoding: .utf8)
            @unknown default: nil
            }
        }.joined(separator: "\n")
    }

    func resume() {
        lock.feedWithLock { storedResumeCount += 1 }
    }

    func send(_ message: URLSessionWebSocketTask.Message) async throws {
        lock.feedWithLock { storedSentMessages.append(message) }
    }

    func receive() async throws -> URLSessionWebSocketTask.Message {
        try await withCheckedThrowingContinuation { continuation in
            let queued: MessageResult? = lock.feedWithLock {
                if !queuedResults.isEmpty { return queuedResults.removeFirst() }
                pendingReceive = continuation
                return nil
            }
            if let queued { continuation.resume(with: queued) }
        }
    }

    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let continuation: CheckedContinuation<URLSessionWebSocketTask.Message, Error>? = lock.feedWithLock {
            storedCancelCount += 1
            let continuation = pendingReceive
            pendingReceive = nil
            return continuation
        }
        continuation?.resume(throwing: CancellationError())
    }

    func push(json: Any) {
        let data = try! JSONSerialization.data(withJSONObject: json)
        push(.success(.data(data)))
    }

    func push(text: String) {
        push(.success(.string(text)))
    }

    func fail(_ error: Error) {
        push(.failure(error))
    }

    private func push(_ result: MessageResult) {
        let continuation: CheckedContinuation<URLSessionWebSocketTask.Message, Error>? = lock.feedWithLock {
            if let continuation = pendingReceive {
                pendingReceive = nil
                return continuation
            }
            queuedResults.append(result)
            return nil
        }
        continuation?.resume(with: result)
    }
}

private final class FeedFakeWebSocketFactory: MissCatFeedWebSocketFactory {
    private let lock = NSLock()
    private var sockets: [FeedFakeWebSocket]
    private var storedRequests: [URLRequest] = []

    init(sockets: [FeedFakeWebSocket]) {
        self.sockets = sockets
    }

    var requests: [URLRequest] { lock.feedWithLock { storedRequests } }

    func makeWebSocket(request: URLRequest) -> any MissCatFeedWebSocket {
        lock.feedWithLock {
            precondition(!sockets.isEmpty, "A fake socket must be provided for every connection")
            storedRequests.append(request)
            return sockets.removeFirst()
        }
    }
}

private final class FeedStreamIDSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String]

    init(_ values: [String]) {
        self.values = values
    }

    func next() -> String {
        lock.feedWithLock {
            precondition(!values.isEmpty, "A stream ID must be provided for every stream")
            return values.removeFirst()
        }
    }
}

private extension NSLock {
    func feedWithLock<Value>(_ body: () throws -> Value) rethrows -> Value {
        lock()
        defer { unlock() }
        return try body()
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
