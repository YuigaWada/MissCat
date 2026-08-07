@testable import MissCat
import ImageIO
import UIKit
import XCTest

@MainActor
final class MissCatNoteDetailTests: XCTestCase {
    @MainActor
    func testClipboardActionsWriteExactTextAndPermalinkThroughBoundary() {
        let writer = NoteDetailClipboardWriterSpy()
        let actions = MissCatNoteClipboardActions(writer: writer)

        actions.copyText("本文 🐈\nsecond line")
        actions.copyLink(URL(string: "https://example.test/notes/note-1?view=full")!)

        XCTAssertEqual(
            writer.values,
            ["本文 🐈\nsecond line", "https://example.test/notes/note-1?view=full"]
        )
    }

    @MainActor
    func testSystemClipboardAdapterWritesExactValueAndPublishesFixtureProbe() {
        let writer = MissCatSystemClipboardWriter()
        let observedValue = MissCatTestLockedState<String?>(nil)
        let observer = NotificationCenter.default.addObserver(
            forName: MissCatSystemClipboardWriter.didWriteNotification,
            object: nil,
            queue: nil
        ) { notification in
            observedValue.value = notification.object as? String
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        writer.write("system pasteboard 🐈\nexact")

        XCTAssertEqual(UIPasteboard.general.string, "system pasteboard 🐈\nexact")
        XCTAssertEqual(observedValue.value, "system pasteboard 🐈\nexact")
    }

    func testCustomCopyActionKeepsPasteboardInOneAuditableAdapterAndDomainStaysUIKitFree() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let productionRoot = repositoryRoot.appendingPathComponent("MissCat")
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(
                at: productionRoot,
                includingPropertiesForKeys: nil
            )
        )
        var pasteboardOwners: [String] = []
        while let file = enumerator.nextObject() as? URL {
            guard file.pathExtension == "swift" else { continue }
            let source = try String(contentsOf: file, encoding: .utf8)
            if source.contains("UIPasteboard") {
                pasteboardOwners.append(file.lastPathComponent)
            }
        }

        XCTAssertEqual(pasteboardOwners, ["MissCatSystemClipboardWriter.swift"])
        let adapter = try String(
            contentsOf: productionRoot
                .appendingPathComponent("Others/Platform/MissCatSystemClipboardWriter.swift"),
            encoding: .utf8
        )
        XCTAssertEqual(adapter.components(separatedBy: "public func ").count - 1, 1)
        XCTAssertFalse(adapter.contains("func read("))
        let timelineRoot = productionRoot.appendingPathComponent("SwiftUI/Timeline")
        let timelineEnumerator = try XCTUnwrap(
            FileManager.default.enumerator(at: timelineRoot, includingPropertiesForKeys: nil)
        )
        while let file = timelineEnumerator.nextObject() as? URL {
            guard file.pathExtension == "swift" else { continue }
            let source = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(source.contains("import UIKit"), "\(file.lastPathComponent) must remain UIKit-free")
            XCTAssertFalse(source.contains("UIPasteboard"), "\(file.lastPathComponent) must remain pasteboard-free")
        }
    }

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

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NoteDetailURLProtocolStub.self]
        return URLSession(configuration: configuration)
    }()

    override func setUp() {
        super.setUp()
        NoteDetailURLProtocolStub.handler = nil
    }

    override func tearDown() {
        NoteDetailURLProtocolStub.handler = nil
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

    func testNativeMFMRendererPreservesExplicitLineBreaks() {
        let rendered = MissCatNativeMFMRenderer.render("first\nsecond")

        XCTAssertEqual(String(rendered.characters), "first\nsecond")
    }

    func testNativeMFMRendererStripsAttributedMotionTagsAndRoutesMentionAndHashtag() {
        let rendered = MissCatNativeMFMRenderer.render(
            #"<spin duration="1s">safe</spin> @alice@example.test #SwiftUI"#
        )
        let links = rendered.runs.compactMap(\.link)

        XCTAssertEqual(String(rendered.characters), "safe @alice@example.test #SwiftUI")
        XCTAssertTrue(links.contains(URL(string: "misscat-mfm://mention/alice@example.test")!))
        XCTAssertTrue(links.contains(URL(string: "misscat-mfm://hashtag/SwiftUI")!))
        XCTAssertEqual(
            MissCatNativeMFMRenderer.interactiveValue(
                from: URL(string: "misscat-mfm://hashtag/SwiftUI")!,
                kind: "hashtag"
            ),
            "SwiftUI"
        )
    }

    func testNativeMFMAccessibilityKeepsCustomEmojiNamesAvailableToVoiceOver() {
        XCTAssertEqual(
            MissCatNativeMFMRenderer.accessibilityText("hello :blobcat: :wave@remote.example:"),
            "hello blobcat 絵文字 wave@remote.example 絵文字"
        )
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
    func testCustomEmojiStoreCachesSuccessfulLoadsAcrossViews() async {
        let url = URL(string: "https://example.test/emoji.webp")!
        let cache = MissCatCustomEmojiCache(countLimit: 2)
        let probe = CustomEmojiLoaderProbe(data: Self.customEmojiPNGData)
        let first = MissCatCustomEmojiStore(
            emojis: ["cat": url],
            readiness: nil,
            cache: cache,
            loader: { url in try await probe.load(url) }
        )
        await first.load()
        let second = MissCatCustomEmojiStore(
            emojis: ["cat": url],
            readiness: nil,
            cache: cache,
            loader: { url in try await probe.load(url) }
        )
        await second.load()

        XCTAssertEqual(probe.callCount, 1)
        XCTAssertEqual(first.imageByName["cat"]?.width, 1)
        XCTAssertEqual(second.imageByName["cat"]?.height, 1)
    }

    @MainActor
    func testCustomEmojiStoreCoalescesConcurrentDownloadAndDecodeByURL() async {
        let url = URL(string: "https://example.test/shared.webp")!
        let cache = MissCatCustomEmojiCache(countLimit: 2)
        let probe = CustomEmojiLoaderProbe(
            data: Self.customEmojiPNGData,
            delayNanoseconds: 100_000_000
        )
        let first = MissCatCustomEmojiStore(
            emojis: ["first-name": url],
            readiness: nil,
            cache: cache,
            loader: { url in try await probe.load(url) }
        )
        let second = MissCatCustomEmojiStore(
            emojis: ["second-name": url],
            readiness: nil,
            cache: cache,
            loader: { url in try await probe.load(url) }
        )

        let firstTask = Task { await first.load() }
        let secondTask = Task { await second.load() }
        await firstTask.value
        await secondTask.value

        XCTAssertEqual(probe.callCount, 1)
        XCTAssertEqual(first.animationByName["first-name"]?.firstFrame.width, 1)
        XCTAssertEqual(second.animationByName["second-name"]?.firstFrame.height, 1)
    }

    @MainActor
    func testCancellingOneCoalescedEmojiWaiterKeepsTheOtherLoadAlive() async {
        let url = URL(string: "https://example.test/shared-cancellation.webp")!
        let cache = MissCatCustomEmojiCache(countLimit: 2)
        let probe = CustomEmojiLoaderProbe(
            data: Self.customEmojiPNGData,
            delayNanoseconds: 100_000_000
        )
        let cancelledStore = MissCatCustomEmojiStore(
            emojis: ["cancelled": url],
            readiness: nil,
            cache: cache,
            loader: { url in try await probe.load(url) }
        )
        let survivingStore = MissCatCustomEmojiStore(
            emojis: ["surviving": url],
            readiness: nil,
            cache: cache,
            loader: { url in try await probe.load(url) }
        )

        let cancelledTask = Task { await cancelledStore.load() }
        let didStartLoading = await waitUntil { probe.callCount == 1 }
        XCTAssertTrue(didStartLoading)
        let survivingTask = Task { await survivingStore.load() }
        try? await Task.sleep(nanoseconds: 20_000_000)
        cancelledTask.cancel()
        await cancelledTask.value
        await survivingTask.value

        XCTAssertEqual(probe.callCount, 1)
        XCTAssertTrue(cancelledStore.animationByName.isEmpty)
        XCTAssertEqual(survivingStore.animationByName["surviving"]?.firstFrame.width, 1)
    }

    func testCustomEmojiLoopMetadataRejectsNonFiniteAndClampsOutOfRangeValues() {
        let formats: [(CFString, CFString)] = [
            (kCGImagePropertyGIFDictionary, kCGImagePropertyGIFLoopCount),
            (kCGImagePropertyPNGDictionary, kCGImagePropertyAPNGLoopCount),
            (kCGImagePropertyWebPDictionary, kCGImagePropertyWebPLoopCount),
        ]

        for (dictionaryKey, loopKey) in formats {
            XCTAssertEqual(
                MissCatCustomEmojiImageDecoder.loopCount(
                    properties: [dictionaryKey: [loopKey: Double.nan]]
                ),
                0
            )
            XCTAssertEqual(
                MissCatCustomEmojiImageDecoder.loopCount(
                    properties: [dictionaryKey: [loopKey: Double.infinity]]
                ),
                0
            )
            XCTAssertEqual(
                MissCatCustomEmojiImageDecoder.loopCount(
                    properties: [dictionaryKey: [loopKey: -1]]
                ),
                0
            )
            XCTAssertEqual(
                MissCatCustomEmojiImageDecoder.loopCount(
                    properties: [dictionaryKey: [loopKey: 4.9]]
                ),
                4
            )
            XCTAssertEqual(
                MissCatCustomEmojiImageDecoder.loopCount(
                    properties: [dictionaryKey: [loopKey: Double.greatestFiniteMagnitude]]
                ),
                Int.max
            )
        }
    }

    func testCustomEmojiFramesNormalizeToOneStableCanvas() throws {
        let source = try MissCatCustomEmojiImageDecoder.decode(Self.customEmojiPNGData)
        let first = try MissCatCustomEmojiImageDecoder.normalizedFrame(
            source,
            canvasWidth: 3,
            canvasHeight: 2
        )
        let second = try MissCatCustomEmojiImageDecoder.normalizedFrame(
            source,
            canvasWidth: 3,
            canvasHeight: 2
        )

        XCTAssertEqual(first.width, 3)
        XCTAssertEqual(first.height, 2)
        XCTAssertEqual(second.width, first.width)
        XCTAssertEqual(second.height, first.height)
    }

    @MainActor
    func testCustomEmojiCancellationCompletesEveryReadinessRegistration() async throws {
        let readiness = MissCatNoteVisualReadiness()
        readiness.setModelTerminal(true)
        let probe = CustomEmojiLoaderProbe(
            data: Self.customEmojiPNGData,
            delayNanoseconds: 5_000_000_000
        )
        let store = MissCatCustomEmojiStore(
            emojis: [
                "cat": URL(string: "https://example.test/cat.webp")!,
                "dog": URL(string: "https://example.test/dog.webp")!,
            ],
            readiness: readiness,
            cache: MissCatCustomEmojiCache(countLimit: 2),
            loader: { url in try await probe.load(url) }
        )
        let task = Task { await store.load() }
        let didStartLoading = await waitUntil { probe.callCount == 1 }
        XCTAssertTrue(didStartLoading)

        task.cancel()
        await task.value
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertTrue(store.imageByName.isEmpty)
        XCTAssertTrue(readiness.isReady)
        XCTAssertEqual(probe.callCount, 1)
    }

    @MainActor
    func testCustomEmojiFailureBecomesTerminalWithoutPassingVisualAcceptance() async throws {
        let readiness = MissCatNoteVisualReadiness()
        readiness.setModelTerminal(true)
        let store = MissCatCustomEmojiStore(
            emojis: ["cat": URL(string: "https://example.test/cat.webp")!],
            readiness: readiness,
            cache: MissCatCustomEmojiCache(countLimit: 1),
            loader: { _ in throw URLError(.cannotDecodeContentData) }
        )

        await store.load()
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertTrue(readiness.hasFailures)
        XCTAssertFalse(readiness.isReady)
        XCTAssertTrue(store.imageByName.isEmpty)
    }

    func testCustomEmojiTransportRejectsOversizedHeaderAndNonImageMIMEBeforeBody() throws {
        let url = try XCTUnwrap(URL(string: "https://cdn.example/emoji.webp"))
        let oversized = try XCTUnwrap(HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: [
                "Content-Type": "image/webp",
                "Content-Length": "4000001",
            ]
        ))
        let wrongMIME = try XCTUnwrap(HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/html"]
        ))

        XCTAssertThrowsError(try MissCatCustomEmojiTransportPolicy.validate(response: oversized)) {
            XCTAssertEqual($0 as? MissCatCustomEmojiLoadError, .payloadTooLarge)
        }
        XCTAssertThrowsError(try MissCatCustomEmojiTransportPolicy.validate(response: wrongMIME)) {
            XCTAssertEqual($0 as? MissCatCustomEmojiLoadError, .unsupportedMIME)
        }
        XCTAssertThrowsError(
            try MissCatCustomEmojiTransportPolicy.validate(
                url: URL(string: "file:///tmp/emoji.png")!
            )
        ) {
            XCTAssertEqual($0 as? MissCatCustomEmojiLoadError, .unsupportedURL)
        }
    }

    func testCustomEmojiDecoderBoundsCompressedAndDecodedMemory() async throws {
        let image = try await MissCatCustomEmojiImageDecoder.decodeOffMain(Self.customEmojiPNGData)
        XCTAssertEqual(image.width, 1)
        XCTAssertEqual(image.height, 1)

        XCTAssertThrowsError(
            try MissCatCustomEmojiImageDecoder.validateDimensions(width: 4_097, height: 1)
        ) {
            XCTAssertEqual($0 as? MissCatCustomEmojiLoadError, .dimensionsTooLarge)
        }
        XCTAssertThrowsError(
            try MissCatCustomEmojiImageDecoder.validateDimensions(width: 4_096, height: 4_097)
        ) {
            XCTAssertEqual($0 as? MissCatCustomEmojiLoadError, .dimensionsTooLarge)
        }
        XCTAssertThrowsError(try MissCatCustomEmojiImageDecoder.decode(Data(repeating: 0, count: 32))) {
            XCTAssertEqual($0 as? MissCatCustomEmojiLoadError, .invalidImage)
        }
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
    func testURLPreviewCacheIsAccountScopedAndAvoidsDuplicateTransport() async throws {
        let repository = NoteDetailContextRepositoryStub()
        let url = URL(string: "https://example.test/cached")!
        repository.previewResults = [
            .success(.init(sourceURL: url, title: "Cached")),
            .success(.init(sourceURL: url, title: "Second account")),
        ]
        let cache = MissCatURLPreviewCache(timeToLive: 60)
        let first = MissCatURLPreviewStore(sourceURL: url, repository: repository, cache: cache)
        let second = MissCatURLPreviewStore(sourceURL: url, repository: repository, cache: cache)

        first.load()
        let firstLoaded = await waitUntil { if case .loaded = first.phase { true } else { false } }
        XCTAssertTrue(firstLoaded)
        second.load()
        let secondLoaded = await waitUntil { if case .loaded = second.phase { true } else { false } }
        XCTAssertTrue(secondLoaded)
        XCTAssertEqual(repository.previewRequestCount, 1)

        repository.accountIdentifier = "misscat-account-v2:other:test"
        let otherAccount = MissCatURLPreviewStore(sourceURL: url, repository: repository, cache: cache)
        otherAccount.load()
        let otherLoaded = await waitUntil { if case .loaded = otherAccount.phase { true } else { false } }
        XCTAssertTrue(otherLoaded)
        XCTAssertEqual(repository.previewRequestCount, 2)
    }

    @MainActor
    func testURLPreviewCancellationRejectsLateCompletionAndKeepsFallback() async throws {
        let repository = NoteDetailContextRepositoryStub()
        repository.previewDelayNanoseconds = 180_000_000
        let url = URL(string: "https://fallback.example/path")!
        repository.previewResults = [.success(.init(sourceURL: url, title: "Too late"))]
        let store = MissCatURLPreviewStore(
            sourceURL: url,
            repository: repository,
            cache: MissCatURLPreviewCache()
        )

        store.load()
        store.cancel()
        try await Task.sleep(nanoseconds: 260_000_000)

        XCTAssertEqual(store.phase, .loading)
        XCTAssertEqual(store.fallbackPreview.title, "fallback.example")
        XCTAssertEqual(store.fallbackPreview.resolvedURL, url)
    }

    @MainActor
    func testReactionPickerFallsBackThenRetriesRemoteChoices() async throws {
        let repository = NoteDetailContextRepositoryStub()
        repository.reactionResults = [
            .failure(MissCatFeedRepositoryError.invalidResponse),
            .success([MissCatReactionChoice(value: ":misscat:", label: "🐈")]),
        ]
        let store = MissCatReactionPickerStore(repository: repository)

        store.load()
        let didFail = await waitUntil { if case .failed = store.phase { true } else { false } }
        XCTAssertTrue(didFail)
        XCTAssertTrue(store.choices.contains { $0.value == "👍" })
        store.retry()
        let didRecover = await waitUntil { store.phase == .loaded }
        XCTAssertTrue(didRecover)
        XCTAssertTrue(store.choices.contains { $0.value == ":misscat:" })
    }

    func testReactionSelectionPolicyCoversEveryCurrentAcceptanceVariant() {
        let catalog = [
            MissCatReactionChoice(value: ":open:", emojiURL: URL(string: "https://cdn.example/open.webp")),
            MissCatReactionChoice(
                value: ":local:",
                emojiURL: URL(string: "https://cdn.example/local.webp"),
                isLocalOnly: true
            ),
            MissCatReactionChoice(
                value: ":sensitive:",
                emojiURL: URL(string: "https://cdn.example/sensitive.webp"),
                isSensitive: true
            ),
        ]
        let existing = [
            MissCatReaction(name: ":role_denied:", count: 1, emojiURL: URL(string: "https://cdn.example/denied.webp")),
            MissCatReaction(name: "😺", count: 2),
            MissCatReaction(name: "like", count: 3),
        ]

        let unrestricted = MissCatReactionSelectionPolicy.selectableChoices(
            catalog: catalog,
            existingReactions: existing,
            noteAuthorHost: nil,
            reactionAcceptance: nil
        )
        XCTAssertEqual(Set(unrestricted.map(\.value)), [":open:", ":local:", ":sensitive:", "😺"])
        XCTAssertFalse(unrestricted.contains { $0.value == ":role_denied:" || $0.value == "like" })

        let likeOnly = MissCatReactionSelectionPolicy.selectableChoices(
            catalog: catalog,
            existingReactions: existing,
            noteAuthorHost: nil,
            reactionAcceptance: "likeOnly"
        )
        XCTAssertEqual(likeOnly.map(\.value), ["\u{2764}"])

        let likeOnlyForRemote = MissCatReactionSelectionPolicy.selectableChoices(
            catalog: catalog,
            existingReactions: existing,
            noteAuthorHost: nil,
            reactionAcceptance: "likeOnlyForRemote"
        )
        XCTAssertEqual(Set(likeOnlyForRemote.map(\.value)), Set(unrestricted.map(\.value)))

        for acceptance in [
            "nonSensitiveOnly",
            "nonSensitiveOnlyForLocalLikeOnlyForRemote",
        ] {
            let choices = MissCatReactionSelectionPolicy.selectableChoices(
                catalog: catalog,
                existingReactions: existing,
                noteAuthorHost: nil,
                reactionAcceptance: acceptance
            )
            XCTAssertFalse(choices.contains { $0.value == ":sensitive:" })
            XCTAssertTrue(choices.contains { $0.value == ":local:" })
        }

        let remoteNote = MissCatReactionSelectionPolicy.selectableChoices(
            catalog: catalog,
            existingReactions: existing,
            noteAuthorHost: "remote.example",
            reactionAcceptance: nil
        )
        XCTAssertFalse(remoteNote.contains { $0.value == ":local:" })
        XCTAssertTrue(remoteNote.contains { $0.value == ":open:" })
    }

    @MainActor
    func testRenoteFailureRollsBackAndRetryCommitsExactlyOnce() async throws {
        let repository = NoteDetailContextRepositoryStub()
        repository.thread = Self.threadFixture
        repository.actionDelayNanoseconds = 80_000_000
        repository.actionResults = [
            .failure(MissCatFeedRepositoryError.rejectedAction),
            .success(()),
        ]
        let store = MissCatFeedStore(source: .noteDetail(noteID: "root"), repository: repository)
        await store.loadInitial()

        async let first: Void = store.renote(noteID: "root")
        async let duplicate: Void = store.renote(noteID: "root")
        _ = await (first, duplicate)

        XCTAssertEqual(store.notes.first { $0.noteID == "root" }?.renoteCount, 0)
        XCTAssertEqual(repository.actions, [.renote(noteID: "root")])
        XCTAssertTrue(store.canRetryAction)

        await store.retryLastAction()

        XCTAssertEqual(store.notes.first { $0.noteID == "root" }?.renoteCount, 1)
        XCTAssertEqual(repository.actions, [.renote(noteID: "root"), .renote(noteID: "root")])
        XCTAssertNil(store.actionErrorMessage)
    }

    @MainActor
    func testDeleteFailureKeepsThreadUntilSuccessfulRetry() async {
        let repository = NoteDetailContextRepositoryStub()
        repository.thread = Self.threadFixture
        repository.actionResults = [
            .failure(MissCatFeedRepositoryError.rejectedAction),
            .success(()),
        ]
        let store = MissCatFeedStore(source: .noteDetail(noteID: "root"), repository: repository)
        await store.loadInitial()

        await store.delete(noteID: "root")
        XCTAssertTrue(store.notes.contains { $0.noteID == "root" })
        await store.retryLastAction()
        XCTAssertFalse(store.notes.contains { $0.noteID == "root" })
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

    @MainActor
    func testDetailStoreMapsMissingThreadToDeterministicEmptyState() async {
        let repository = NoteDetailContextRepositoryStub()
        repository.threadError = MissCatFeedRepositoryError.emptyResponse
        let store = MissCatFeedStore(source: .noteDetail(noteID: "root"), repository: repository)

        await store.loadInitial()

        XCTAssertEqual(store.phase, .empty)
        XCTAssertTrue(store.notes.isEmpty)
        XCTAssertNil(store.thread)
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

    private static let customEmojiPNGData = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    )!

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

@MainActor
private final class NoteDetailClipboardWriterSpy: MissCatClipboardWriting {
    private(set) var values: [String] = []

    func write(_ value: String) {
        values.append(value)
    }
}

private final class CustomEmojiLoaderProbe: @unchecked Sendable {
    private let queue = DispatchQueue(label: "misscat.custom-emoji-loader-probe")
    private let data: Data
    private let delayNanoseconds: UInt64
    private var storedCallCount = 0

    init(data: Data, delayNanoseconds: UInt64 = 0) {
        self.data = data
        self.delayNanoseconds = delayNanoseconds
    }

    var callCount: Int {
        queue.sync { storedCallCount }
    }

    func load(_ url: URL) async throws -> Data {
        queue.sync { storedCallCount += 1 }
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return data
    }
}

/// The `@MainActor` note-detail tests serialize all access to this mutable fake.
private final class NoteDetailContextRepositoryStub:
    MissCatNoteContextRepository,
    @unchecked Sendable
{
    var accountIdentifier = "misscat-account-v2:test:test"
    var currentServerUserID = "me"
    var thread = MissCatNoteThread(
        ancestors: [],
        note: .init(id: "root", author: .init(id: "me", name: "Wada", username: "wada")),
        replies: []
    )
    var previewResults: [Result<MissCatURLPreview, Error>] = []
    var previewRequestCount = 0
    var previewDelayNanoseconds: UInt64 = 0
    var reactionResults: [Result<[MissCatReactionChoice], Error>] = []
    var actions: [MissCatFeedAction] = []
    var actionResults: [Result<Void, Error>] = []
    var actionDelayNanoseconds: UInt64 = 0
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

    func perform(_ action: MissCatFeedAction) async throws {
        actions.append(action)
        if actionDelayNanoseconds > 0 { try await Task.sleep(nanoseconds: actionDelayNanoseconds) }
        guard !actionResults.isEmpty else { return }
        try actionResults.removeFirst().get()
    }

    func notePermalink(noteID: String) -> URL? { URL(string: "https://example.test/notes/\(noteID)") }

    func fetchURLPreview(for url: URL) async throws -> MissCatURLPreview {
        previewRequestCount += 1
        if previewDelayNanoseconds > 0 { try await Task.sleep(nanoseconds: previewDelayNanoseconds) }
        guard !previewResults.isEmpty else { return .init(sourceURL: url, title: "Preview") }
        return try previewResults.removeFirst().get()
    }

    func fetchReactionChoices() async throws -> [MissCatReactionChoice] {
        guard !reactionResults.isEmpty else { return MissCatReactionChoice.legacyDefaults }
        return try reactionResults.removeFirst().get()
    }
}

private final class NoteDetailURLProtocolStub: URLProtocol {
    typealias Handler = (URLRequest) throws -> (HTTPURLResponse, Data)
    private static let handlerState = MissCatTestLockedState<Handler?>(nil)
    static var handler: Handler? {
        get { handlerState.value }
        set { handlerState.value = newValue }
    }

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
