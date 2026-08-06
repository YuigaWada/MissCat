@testable import MissCat
import XCTest

final class MissCatNoteDetailTests: XCTestCase {
    func testProductionSwiftUINoteMediaTapUsesOneNativeOwnerAndNeverInvokesLegacyViewer() {
        let attachment = MissCatNoteAttachment(
            id: "media",
            name: "fixture image",
            kind: .image,
            url: URL(string: "https://example.invalid/image.png")
        )
        var nativePresentations = 0
        var legacyPresentations = 0

        let owner = MissCatNoteMediaTapRouter.route(
            attachment,
            presentNatively: { selected in
                XCTAssertEqual(selected.id, attachment.id)
                nativePresentations += 1
            },
            legacyPresentation: { _ in legacyPresentations += 1 }
        )

        XCTAssertEqual(owner, .nativeSwiftUIPager)
        XCTAssertEqual(nativePresentations, 1)
        XCTAssertEqual(legacyPresentations, 0)
    }

    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NoteDetailURLProtocolStub.self]
        session = URLSession(configuration: configuration)
    }

    override func tearDown() {
        NoteDetailURLProtocolStub.handler = nil
        session.invalidateAndCancel()
        session = nil
        super.tearDown()
    }

    func testNativeMFMRendererDropsUnsafeMotionTagsAndPreservesText() {
        let rendered = MissCatNativeMFMRenderer.render(
            "<spin>回転しない</spin> **太字** (((安全)))"
        )

        XCTAssertEqual(String(rendered.characters), "回転しない 太字 安全")
    }

    func testNativeMFMRendererMakesDetectedURLTappable() {
        let rendered = MissCatNativeMFMRenderer.render("see https://example.test/path")
        let links = rendered.runs.compactMap(\.link)

        XCTAssertEqual(links, [URL(string: "https://example.test/path")!])
    }

    func testPreviewURLDetectionIsStableDeduplicatedAndBounded() {
        let urls = MissCatNativeMFMRenderer.previewURLs(
            in: "https://one.test/a https://one.test/a https://two.test/b",
            limit: 2
        )

        XCTAssertEqual(urls.map(\.absoluteString), ["https://one.test/a", "https://two.test/b"])
    }

    func testCompositeFeedIdentitySeparatesSameServerUserIDAcrossInstances() {
        let one = MissCatFeedSession(
            accountID: "same-user",
            username: "wada",
            instance: "one.example",
            apiKey: "test-token"
        )
        let two = MissCatFeedSession(
            accountID: "same-user",
            username: "wada",
            instance: "two.example",
            apiKey: "test-token"
        )

        XCTAssertNotEqual(one.compositeAccountID, two.compositeAccountID)
        XCTAssertEqual(
            one.compositeAccountID,
            MissCatAccountIdentity.storageKey(instance: "one.example", userId: "same-user")
        )
    }

    func testURLPreviewUsesAccountInstanceProxyAndPercentEncodedQuery() async throws {
        var captured: URLRequest?
        NoteDetailURLProtocolStub.handler = { request in
            captured = request
            return Self.response(
                request,
                status: 200,
                json: [
                    "title": "Preview title",
                    "description": "Preview body",
                    "thumbnail": "https://cdn.example/preview.png",
                    "sitename": "Example",
                    "sensitive": false,
                    "url": "https://target.example/a?b=c",
                ]
            )
        }
        let repository = makeRepository(instance: "tenant.example:8443")

        let preview = try await repository.fetchURLPreview(
            for: URL(string: "https://target.example/a?b=c")!
        )

        XCTAssertEqual(captured?.httpMethod, "GET")
        XCTAssertEqual(captured?.url?.host, "tenant.example")
        XCTAssertEqual(captured?.url?.port, 8443)
        XCTAssertEqual(captured?.url?.path, "/url")
        XCTAssertEqual(
            URLComponents(url: captured!.url!, resolvingAgainstBaseURL: false)?.queryItems,
            [URLQueryItem(name: "url", value: "https://target.example/a?b=c")]
        )
        XCTAssertNil(captured?.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(preview.title, "Preview title")
        XCTAssertEqual(preview.imageURL?.absoluteString, "https://cdn.example/preview.png")
    }

    func testURLPreviewRejectsUnsupportedSchemeBeforeTransport() async {
        var requestCount = 0
        NoteDetailURLProtocolStub.handler = { request in
            requestCount += 1
            return Self.response(request, status: 500, json: [:])
        }

        do {
            _ = try await makeRepository().fetchURLPreview(for: URL(string: "file:///tmp/private")!)
            XCTFail("Expected unsupported URL")
        } catch let error as MissCatURLPreviewError {
            XCTAssertEqual(error, .unsupportedURL)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(requestCount, 0)
    }

    func testDeleteAndMuteUseCurrentMisskeyWriteContracts() async throws {
        var requests: [URLRequest] = []
        NoteDetailURLProtocolStub.handler = { request in
            requests.append(request)
            return Self.response(request, status: 204, data: Data())
        }
        let repository = makeRepository()

        try await repository.perform(.delete(noteID: "note-1"))
        try await repository.perform(.mute(userID: "user-2"))

        XCTAssertEqual(requests.map { $0.url?.path }, ["/api/notes/delete", "/api/mute/create"])
        let bodies = try requests.map { request in
            try XCTUnwrap(
                JSONSerialization.jsonObject(with: XCTUnwrap(Self.bodyData(from: request)))
                    as? [String: String]
            )
        }
        XCTAssertEqual(bodies[0], ["i": "test-token", "noteId": "note-1"])
        XCTAssertEqual(bodies[1], ["i": "test-token", "userId": "user-2"])
    }

    @MainActor
    func testVisualReadinessWaitsForEveryRegisteredAssetAndStabilizes() async throws {
        let readiness = MissCatNoteVisualReadiness()
        readiness.register("thread")
        readiness.register("image")
        readiness.setModelTerminal(true)
        readiness.complete("thread")
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertFalse(readiness.isReady)

        readiness.complete("image")
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(readiness.isReady)
    }

    @MainActor
    func testURLPreviewStorePublishesFailureAndCanRetry() async throws {
        let repository = NoteDetailContextRepositoryStub()
        repository.previewResults = [
            .failure(URLError(.notConnectedToInternet)),
            .success(.init(sourceURL: URL(string: "https://example.test")!, title: "Recovered")),
        ]
        let store = MissCatURLPreviewStore(
            sourceURL: URL(string: "https://example.test")!,
            repository: repository
        )

        store.load()
        let didFail = await waitUntil {
            if case .failed = store.phase { return true }
            return false
        }
        XCTAssertTrue(didFail)
        store.retry()
        let didRecover = await waitUntil {
            if case .loaded = store.phase { return true }
            return false
        }
        XCTAssertTrue(didRecover)
    }

    @MainActor
    func testDetailStoreDeleteAndMuteRemoveOnlyAffectedNotes() async {
        let repository = NoteDetailContextRepositoryStub()
        repository.thread = Self.threadFixture
        let store = MissCatFeedStore(source: .noteDetail(noteID: "root"), repository: repository)
        await store.loadInitial()

        await store.delete(noteID: "root")
        XCTAssertEqual(store.notes.map(\.noteID), ["ancestor", "reply"])
        await store.muteUser(userID: "reply-user")
        XCTAssertEqual(store.notes.map(\.noteID), ["ancestor"])
        XCTAssertEqual(repository.actions, [.delete(noteID: "root"), .mute(userID: "reply-user")])
    }

    @MainActor
    func testDetailStorePreservesOfflineSemanticsAcrossSystemLocales() async {
        let repository = NoteDetailContextRepositoryStub()
        repository.threadError = URLError(.notConnectedToInternet)
        let store = MissCatFeedStore(source: .noteDetail(noteID: "root"), repository: repository)

        await store.loadInitial()

        XCTAssertEqual(store.phase, .failed(message: "インターネットに接続できません。"))
    }

    private func makeRepository(instance: String = "tenant.example") -> MissCatMisskeyFeedRepository {
        MissCatMisskeyFeedRepository(
            session: .init(
                accountID: "me",
                username: "wada",
                instance: instance,
                apiKey: "test-token"
            ),
            urlSession: session
        )
    }

    @MainActor
    private func waitUntil(
        timeout: TimeInterval = 2,
        condition: () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }

    private static var threadFixture: MissCatNoteThread {
        let mine = MissCatNoteAuthor(id: "me", name: "Wada", username: "wada")
        let reply = MissCatNoteAuthor(id: "reply-user", name: "Reply", username: "reply")
        return MissCatNoteThread(
            ancestors: [.init(id: "ancestor", author: mine, text: "before")],
            note: .init(id: "root", author: mine, text: "root"),
            replies: [.init(id: "reply", author: reply, text: "reply")]
        )
    }

    private static func response(
        _ request: URLRequest,
        status: Int,
        json: Any
    ) -> (HTTPURLResponse, Data) {
        response(request, status: status, data: try! JSONSerialization.data(withJSONObject: json))
    }

    private static func response(
        _ request: URLRequest,
        status: Int,
        data: Data
    ) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, data)
    }

    private static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var body = Data()
        let capacity = 4096
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

private final class NoteDetailContextRepositoryStub: MissCatNoteContextRepository {
    var accountIdentifier = "misscat-account-v2:test:test"
    var currentServerUserID = "me"
    var thread = MissCatNoteThread(
        ancestors: [],
        note: .init(id: "root", author: .init(id: "me", name: "Wada", username: "wada")),
        replies: []
    )
    var previewResults: [Result<MissCatURLPreview, Error>] = []
    var actions: [MissCatFeedAction] = []
    var threadError: Error?

    func fetchPage(source: MissCatFeedSource, cursor: String?, limit: Int) async throws -> MissCatFeedPage {
        .init(notes: [], hasMore: false)
    }

    func fetchThread(noteID: String, replyLimit: Int) async throws -> MissCatNoteThread {
        if let threadError { throw threadError }
        return thread
    }

    func realtimeEvents(source: MissCatFeedSource, capturing noteIDs: [String]) -> AsyncStream<MissCatRealtimeEvent> {
        AsyncStream { $0.finish() }
    }

    func perform(_ action: MissCatFeedAction) async throws { actions.append(action) }

    func notePermalink(noteID: String) -> URL? { URL(string: "https://example.test/notes/\(noteID)") }

    func fetchURLPreview(for url: URL) async throws -> MissCatURLPreview {
        guard !previewResults.isEmpty else { return .init(sourceURL: url, title: "Preview") }
        return try previewResults.removeFirst().get()
    }
}

private final class NoteDetailURLProtocolStub: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
}
