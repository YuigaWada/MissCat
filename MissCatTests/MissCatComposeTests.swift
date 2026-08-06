@testable import MissCat
import Foundation
import UIKit
import XCTest

final class MissCatComposeSubmissionBuilderTests: XCTestCase {
    private let accountID = "account-1"

    func testNewNoteMapsEveryAudienceAndExtractionField() throws {
        var draft = MissCatComposeDraft()
        draft.text = "Hello @cat #misskey"
        draft.hasContentWarning = true
        draft.contentWarning = " spoiler "
        draft.visibility = .specified
        draft.visibleUserIDs = [" user-a ", "user-a", "user-b"]
        draft.localOnly = true

        let submission = try MissCatComposeSubmissionBuilder.build(
            mode: .note,
            draft: draft,
            accountID: accountID
        )

        XCTAssertEqual(submission.text, "Hello @cat #misskey")
        XCTAssertEqual(submission.contentWarning, "spoiler")
        XCTAssertEqual(submission.visibility, .specified)
        XCTAssertEqual(submission.visibleUserIDs, ["user-a", "user-b"])
        XCTAssertTrue(submission.localOnly)
        XCTAssertFalse(submission.noExtractMentions)
        XCTAssertFalse(submission.noExtractHashtags)
        XCTAssertNil(submission.replyID)
        XCTAssertNil(submission.renoteID)
    }

    func testReplyMapsReplyIDWithoutRenoteID() throws {
        let target = makeTarget(id: "reply-note")
        var draft = MissCatComposeDraft()
        draft.text = "返信"

        let submission = try MissCatComposeSubmissionBuilder.build(
            mode: .reply(target),
            draft: draft,
            accountID: accountID
        )

        XCTAssertEqual(submission.replyID, "reply-note")
        XCTAssertNil(submission.renoteID)
    }

    func testQuoteMapsRenoteIDAndComment() throws {
        let target = makeTarget(id: "quoted-note")
        var draft = MissCatComposeDraft()
        draft.text = "引用コメント"

        let submission = try MissCatComposeSubmissionBuilder.build(
            mode: .quote(target),
            draft: draft,
            accountID: accountID
        )

        XCTAssertEqual(submission.renoteID, "quoted-note")
        XCTAssertEqual(submission.text, "引用コメント")
        XCTAssertNil(submission.replyID)
    }

    func testPlainRenoteAllowsEmptyPayloadAndRejectsCustomization() throws {
        let target = makeTarget(id: "renote-target")
        let submission = try MissCatComposeSubmissionBuilder.build(
            mode: .renote(target),
            draft: MissCatComposeDraft(),
            accountID: accountID
        )
        XCTAssertEqual(submission.renoteID, "renote-target")
        XCTAssertEqual(submission.text, "")

        var customized = MissCatComposeDraft()
        customized.text = "comment"
        XCTAssertThrowsError(
            try MissCatComposeSubmissionBuilder.build(
                mode: .renote(target),
                draft: customized,
                accountID: accountID
            )
        ) { error in
            XCTAssertEqual(error as? MissCatComposeValidationError, .renoteCannotContainComment)
        }
    }

    func testEmptyNormalPostAndMissingAccountAreRejected() {
        XCTAssertThrowsError(
            try MissCatComposeSubmissionBuilder.build(
                mode: .note,
                draft: MissCatComposeDraft(),
                accountID: accountID
            )
        ) { error in
            XCTAssertEqual(error as? MissCatComposeValidationError, .emptyPost)
        }

        var draft = MissCatComposeDraft()
        draft.text = "投稿"
        XCTAssertThrowsError(
            try MissCatComposeSubmissionBuilder.build(mode: .note, draft: draft, accountID: nil)
        ) { error in
            XCTAssertEqual(error as? MissCatComposeValidationError, .accountRequired)
        }
    }

    func testTextAndContentWarningLimitsAreIndependent() {
        var draft = MissCatComposeDraft()
        draft.text = String(repeating: "a", count: 1_501)
        XCTAssertThrowsError(
            try MissCatComposeSubmissionBuilder.build(mode: .note, draft: draft, accountID: accountID)
        ) { error in
            XCTAssertEqual(error as? MissCatComposeValidationError, .textTooLong(limit: 1_500))
        }

        draft.text = "投稿"
        draft.hasContentWarning = true
        draft.contentWarning = String(repeating: "a", count: 101)
        XCTAssertThrowsError(
            try MissCatComposeSubmissionBuilder.build(mode: .note, draft: draft, accountID: accountID)
        ) { error in
            XCTAssertEqual(error as? MissCatComposeValidationError, .contentWarningTooLong(limit: 100))
        }
    }

    func testDirectVisibilityRequiresRecipient() {
        var draft = MissCatComposeDraft()
        draft.text = "direct"
        draft.visibility = .specified
        XCTAssertThrowsError(
            try MissCatComposeSubmissionBuilder.build(mode: .note, draft: draft, accountID: accountID)
        ) { error in
            XCTAssertEqual(error as? MissCatComposeValidationError, .directRecipientRequired)
        }
    }

    func testPollMapsChoiceMultipleAndDuration() throws {
        var draft = MissCatComposeDraft()
        draft.poll = MissCatPollDraft(
            choices: [MissCatPollChoice(text: " Cat "), MissCatPollChoice(text: "Dog")],
            allowsMultiple: true,
            expiry: .duration(3_600)
        )

        let submission = try MissCatComposeSubmissionBuilder.build(
            mode: .note,
            draft: draft,
            accountID: accountID
        )

        XCTAssertEqual(submission.poll?.choices, ["Cat", "Dog"])
        XCTAssertEqual(submission.poll?.allowsMultiple, true)
        XCTAssertEqual(submission.poll?.expiresAfterMilliseconds, 3_600_000)
        XCTAssertNil(submission.poll?.expiresAtMilliseconds)
    }

    func testPollMapsAbsoluteExpiryToMilliseconds() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        var draft = MissCatComposeDraft()
        draft.poll = MissCatPollDraft(
            choices: [MissCatPollChoice(text: "A"), MissCatPollChoice(text: "B")],
            allowsMultiple: false,
            expiry: .at(Date(timeIntervalSince1970: 1_100))
        )

        let submission = try MissCatComposeSubmissionBuilder.build(
            mode: .note,
            draft: draft,
            accountID: accountID,
            now: now
        )

        XCTAssertEqual(submission.poll?.expiresAtMilliseconds, 1_100_000)
        XCTAssertNil(submission.poll?.expiresAfterMilliseconds)
    }

    func testPollRejectsEmptyDuplicateAndPastChoices() {
        assertPollError(
            MissCatPollDraft(
                choices: [MissCatPollChoice(text: "A"), MissCatPollChoice(text: " ")],
                allowsMultiple: false,
                expiry: .never
            ),
            equals: .emptyPollChoice
        )
        assertPollError(
            MissCatPollDraft(
                choices: [MissCatPollChoice(text: "Cat"), MissCatPollChoice(text: "cat")],
                allowsMultiple: false,
                expiry: .never
            ),
            equals: .duplicatePollChoice
        )
        assertPollError(
            MissCatPollDraft(
                choices: [
                    MissCatPollChoice(text: String(repeating: "a", count: 51)),
                    MissCatPollChoice(text: "B")
                ],
                allowsMultiple: false,
                expiry: .never
            ),
            equals: .pollChoiceTooLong(limit: 50)
        )
        assertPollError(
            MissCatPollDraft(
                choices: [MissCatPollChoice(text: "A"), MissCatPollChoice(text: "B")],
                allowsMultiple: false,
                expiry: .at(.distantPast)
            ),
            equals: .pollExpiryInvalid
        )
    }

    func testMediaAllowsFourImagesAndPreservesOrderAndMetadata() throws {
        var draft = MissCatComposeDraft()
        draft.media = (0 ..< 4).map { index in
            makeMedia(index: index, altText: "alt-\(index)", sensitive: index == 2)
        }

        let submission = try MissCatComposeSubmissionBuilder.build(
            mode: .note,
            draft: draft,
            accountID: accountID
        )

        XCTAssertEqual(submission.media.map(\.filename), ["0.jpeg", "1.jpeg", "2.jpeg", "3.jpeg"])
        XCTAssertEqual(submission.media[2].altText, "alt-2")
        XCTAssertTrue(submission.media[2].isSensitive)
    }

    func testMediaRejectsFifthImageMixedVideoAndLongAltText() {
        var draft = MissCatComposeDraft()
        draft.media = (0 ..< 5).map { makeMedia(index: $0) }
        assertBuildError(draft, equals: .tooManyMedia(limit: 4))

        draft.media = [
            makeMedia(index: 0),
            MissCatComposeMedia(
                kind: .video,
                data: Data([0x02]),
                filename: "video.mp4",
                mimeType: "video/mp4"
            )
        ]
        assertBuildError(draft, equals: .videoMustBeAlone)

        draft.media = [makeMedia(index: 0, altText: String(repeating: "a", count: 513))]
        assertBuildError(draft, equals: .altTextTooLong(limit: 512))
    }

    private func assertPollError(_ poll: MissCatPollDraft, equals expected: MissCatComposeValidationError) {
        var draft = MissCatComposeDraft()
        draft.poll = poll
        assertBuildError(draft, equals: expected)
    }

    private func assertBuildError(_ draft: MissCatComposeDraft, equals expected: MissCatComposeValidationError) {
        XCTAssertThrowsError(
            try MissCatComposeSubmissionBuilder.build(
                mode: .note,
                draft: draft,
                accountID: accountID,
                now: Date(timeIntervalSince1970: 10)
            )
        ) { error in
            XCTAssertEqual(error as? MissCatComposeValidationError, expected)
        }
    }
}

final class MissCatComposeTextInsertionTests: XCTestCase {
    func testMentionAndHashtagAreNormalizedAndSeparated() {
        let mention = MissCatComposeTextInsertion.appendingMention(
            username: "@cat",
            instance: "@misskey.io",
            to: "hello"
        )
        XCTAssertEqual(mention, "hello @cat@misskey.io ")
        XCTAssertEqual(
            MissCatComposeTextInsertion.appendingHashtag("#MissCat", to: mention),
            "hello @cat@misskey.io #MissCat "
        )
    }

    func testEmptyTokensDoNotChangeText() {
        XCTAssertEqual(
            MissCatComposeTextInsertion.appendingMention(username: " ", instance: nil, to: "draft"),
            "draft"
        )
        XCTAssertEqual(MissCatComposeTextInsertion.appendingHashtag("#", to: "draft"), "draft")
    }
}

@MainActor
final class MissCatNativeComposeAPIContractTests: XCTestCase {
    private var urlSession: URLSession!

    override func setUp() {
        super.setUp()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ComposeURLProtocolStub.self]
        urlSession = URLSession(configuration: configuration)
    }

    override func tearDown() {
        ComposeURLProtocolStub.handler = nil
        ComposeURLProtocolStub.suspendsRequests = false
        ComposeURLProtocolStub.onStart = nil
        ComposeURLProtocolStub.onStop = nil
        urlSession.invalidateAndCancel()
        urlSession = nil
        super.tearDown()
    }

    func testNoteCreateUsesBearerAccountScopeAndCurrentBodyShapes() async throws {
        let recorder = ComposeRequestRecorder()
        ComposeURLProtocolStub.handler = { request in
            recorder.record(request)
            return (202, Data(#"{"createdNote":{"id":"created-note"}}"#.utf8))
        }
        let client = try makeClient(token: "account-token")

        let firstID = try await client.createNote(
            MissCatComposeAPINote(
                visibility: .specified,
                visibleUserIDs: ["recipient-a", "recipient-b"],
                text: "reply text",
                contentWarning: "spoiler",
                localOnly: true,
                noExtractMentions: true,
                noExtractHashtags: true,
                noExtractEmojis: false,
                fileIDs: ["file-a", "file-b"],
                replyID: "reply-note",
                poll: MissCatComposeAPIPoll(
                    choices: ["Cat", "Dog"],
                    multiple: true,
                    expiresAt: 1_900_000_000_000,
                    expiredAfter: nil
                )
            )
        )
        let renoteID = try await client.createNote(
            MissCatComposeAPINote(
                visibility: .public,
                text: "",
                renoteID: "renote-target"
            )
        )

        XCTAssertEqual(firstID, "created-note")
        XCTAssertEqual(renoteID, "created-note")
        let requests = recorder.snapshot()
        XCTAssertEqual(requests.count, 2)
        for request in requests {
            XCTAssertEqual(request.request.url?.absoluteString, "https://example.invalid/api/notes/create")
            XCTAssertEqual(request.request.httpMethod, "POST")
            XCTAssertEqual(request.request.value(forHTTPHeaderField: "Authorization"), "Bearer account-token")
            XCTAssertEqual(request.request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertNil(request.request.value(forHTTPHeaderField: "Idempotency-Key"))
            XCTAssertEqual(request.request.timeoutInterval, 9)
            XCTAssertNil(request.body.range(of: Data("account-token".utf8)))
        }

        let reply = try requests[0].jsonBody
        XCTAssertNil(reply["i"])
        XCTAssertEqual(reply["visibility"] as? String, "specified")
        XCTAssertEqual(reply["visibleUserIds"] as? [String], ["recipient-a", "recipient-b"])
        XCTAssertEqual(reply["text"] as? String, "reply text")
        XCTAssertEqual(reply["cw"] as? String, "spoiler")
        XCTAssertEqual(reply["localOnly"] as? Bool, true)
        XCTAssertEqual(reply["noExtractMentions"] as? Bool, true)
        XCTAssertEqual(reply["noExtractHashtags"] as? Bool, true)
        XCTAssertEqual(reply["noExtractEmojis"] as? Bool, false)
        XCTAssertEqual(reply["fileIds"] as? [String], ["file-a", "file-b"])
        XCTAssertEqual(reply["replyId"] as? String, "reply-note")
        XCTAssertNil(reply["renoteId"])
        let poll = try XCTUnwrap(reply["poll"] as? [String: Any])
        XCTAssertEqual(poll["choices"] as? [String], ["Cat", "Dog"])
        XCTAssertEqual(poll["multiple"] as? Bool, true)
        XCTAssertEqual((poll["expiresAt"] as? NSNumber)?.int64Value, 1_900_000_000_000)
        XCTAssertNil(poll["expiredAfter"])

        let renote = try requests[1].jsonBody
        XCTAssertEqual(renote["renoteId"] as? String, "renote-target")
        XCTAssertNil(renote["text"])
        XCTAssertNil(renote["fileIds"])
        XCTAssertNil(renote["replyId"])
        XCTAssertNil(renote["poll"])
    }

    func testMultipartUploadPreservesMetadataWithoutPuttingTokenInBody() async throws {
        let recorder = ComposeRequestRecorder()
        ComposeURLProtocolStub.handler = { request in
            recorder.record(request)
            return (201, Data(#"{"id":"drive-file"}"#.utf8))
        }
        let client = try makeClient(token: "upload-token")
        let fileData = Data([0x00, 0xCA, 0xFE, 0xFF])

        let fileID = try await client.upload(
            MissCatComposeAPIUpload(
                data: fileData,
                mimeType: "image/jpeg",
                filename: "cat photo.jpeg",
                comment: "sleeping cat",
                isSensitive: true
            )
        )

        XCTAssertEqual(fileID, "drive-file")
        let request = try XCTUnwrap(recorder.snapshot().first)
        XCTAssertEqual(request.request.url?.path, "/api/drive/files/create")
        XCTAssertEqual(request.request.value(forHTTPHeaderField: "Authorization"), "Bearer upload-token")
        XCTAssertEqual(request.request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertTrue(request.request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=MissCat-") == true)
        XCTAssertEqual(Int(request.request.value(forHTTPHeaderField: "Content-Length") ?? ""), request.body.count)
        XCTAssertNil(request.body.range(of: Data("upload-token".utf8)))
        XCTAssertNotNil(request.body.range(of: fileData))

        let body = String(decoding: request.body, as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"name\"\r\n\r\ncat photo.jpeg\r\n"))
        XCTAssertTrue(body.contains("name=\"comment\"\r\n\r\nsleeping cat\r\n"))
        XCTAssertTrue(body.contains("name=\"isSensitive\"\r\n\r\ntrue\r\n"))
        XCTAssertTrue(body.contains("name=\"force\"\r\n\r\nfalse\r\n"))
        XCTAssertTrue(body.contains("name=\"file\"; filename=\"cat photo.jpeg\""))
        XCTAssertTrue(body.contains("Content-Type: image/jpeg"))
        let orderedFields = [
            "name=\"name\"", "name=\"comment\"", "name=\"isSensitive\"",
            "name=\"force\"", "name=\"file\""
        ]
        let offsets = try orderedFields.map { field in
            try XCTUnwrap(body.range(of: field)?.lowerBound).utf16Offset(in: body)
        }
        XCTAssertEqual(offsets, offsets.sorted())
        XCTAssertNil(request.request.value(forHTTPHeaderField: "Idempotency-Key"))
    }

    func testComposeServiceKeepsMultipleUploadOrderAndMetadata() async throws {
        let recorder = ComposeRequestRecorder()
        ComposeURLProtocolStub.handler = { request in
            let pathIndex = recorder.record(request)
            if request.url?.path == "/api/drive/files/create" {
                return (200, Data("{\"id\":\"file-\(pathIndex)\"}".utf8))
            }
            return (200, Data(#"{"createdNote":{"id":"note"}}"#.utf8))
        }
        let user = SecureUser(
            userId: "same-user",
            username: "cat",
            instance: "example.invalid",
            apiKey: "service-token"
        )
        let service = MissCatComposePostService(
            userProvider: { identifier in
                identifier == user.accountIdentifier ? user : nil
            },
            transport: MissCatComposeURLSessionTransport(session: urlSession),
            requestTimeout: 12,
            journal: MemoryComposeJournal()
        )
        let first = makeValidJPEG(red: 1, green: 0)
        let second = makeValidJPEG(red: 0, green: 1)
        let submission = MissCatComposeSubmission(
            accountID: user.accountIdentifier,
            mode: .note,
            text: "two images",
            contentWarning: nil,
            visibility: .home,
            visibleUserIDs: [],
            localOnly: false,
            noExtractMentions: false,
            noExtractHashtags: false,
            media: [
                MissCatComposeMedia(
                    kind: .image,
                    data: first,
                    filename: "first.png",
                    mimeType: "image/png",
                    altText: "first alt",
                    isSensitive: false
                ),
                MissCatComposeMedia(
                    kind: .image,
                    data: second,
                    filename: "second.png",
                    mimeType: "image/png",
                    altText: "second alt",
                    isSensitive: true
                )
            ],
            poll: nil
        )
        var progress: [MissCatComposeUploadProgress] = []

        try await service.submit(submission) { progress.append($0) }

        let requests = recorder.snapshot()
        XCTAssertEqual(requests.map { $0.request.url?.path }, [
            "/api/drive/files/create",
            "/api/drive/files/create",
            "/api/notes/create"
        ])
        XCTAssertEqual(progress, [
            MissCatComposeUploadProgress(completed: 1, total: 2),
            MissCatComposeUploadProgress(completed: 2, total: 2)
        ])
        let firstBody = String(decoding: requests[0].body, as: UTF8.self)
        let secondBody = String(decoding: requests[1].body, as: UTF8.self)
        XCTAssertTrue(firstBody.contains("first.jpeg"))
        XCTAssertTrue(firstBody.contains("first alt"))
        XCTAssertTrue(firstBody.contains("name=\"isSensitive\"\r\n\r\nfalse"))
        XCTAssertTrue(secondBody.contains("second.jpeg"))
        XCTAssertTrue(secondBody.contains("second alt"))
        XCTAssertTrue(secondBody.contains("name=\"isSensitive\"\r\n\r\ntrue"))
        let noteBody = try requests[2].jsonBody
        XCTAssertEqual(noteBody["fileIds"] as? [String], ["file-1", "file-2"])
    }

    func testNon2xxPropagatesRedactedMisskeyErrorAndMalformed2xxHasUnknownOutcome() async throws {
        ComposeURLProtocolStub.handler = { _ in
            (
                422,
                Data(#"{"error":{"message":"bad secret-token value","code":"INVALID_PARAM","id":"error-id"}}"#.utf8)
            )
        }
        let client = try makeClient(token: "secret-token")

        do {
            _ = try await client.createNote(MissCatComposeAPINote(visibility: .public, text: "hello"))
            XCTFail("Expected server error")
        } catch let error as MissCatNativeComposeAPIError {
            XCTAssertEqual(
                error,
                .server(
                    status: 422,
                    code: "INVALID_PARAM",
                    message: "bad <redacted> value",
                    id: "error-id"
                )
            )
            XCTAssertFalse(error.localizedDescription.contains("secret-token"))
        }

        ComposeURLProtocolStub.handler = { _ in (204, Data()) }
        do {
            _ = try await client.upload(
                MissCatComposeAPIUpload(
                    data: Data([1]),
                    mimeType: "image/jpeg",
                    filename: "cat.jpeg",
                    comment: nil,
                    isSensitive: false
                )
            )
            XCTFail("Expected unknown mutation outcome")
        } catch let error as MissCatNativeComposeAPIError {
            XCTAssertEqual(error, .outcomeUnknown(endpoint: "drive/files/create"))
        }
    }

    func testTimeoutAndCancellationAfterDispatchHaveUnknownOutcomeWithoutRetry() async throws {
        let recorder = ComposeRequestRecorder()
        ComposeURLProtocolStub.handler = { request in
            recorder.record(request)
            throw URLError(.timedOut)
        }
        let client = try makeClient(token: "timeout-token")
        do {
            _ = try await client.createNote(MissCatComposeAPINote(visibility: .public, text: "hello"))
            XCTFail("Expected timeout")
        } catch let error as MissCatNativeComposeAPIError {
            XCTAssertEqual(error, .outcomeUnknown(endpoint: "notes/create"))
        }
        XCTAssertEqual(recorder.snapshot().count, 1)
        XCTAssertEqual(recorder.snapshot().first?.request.timeoutInterval, 9)

        let suspended = SuspendedComposeHTTPTransport()
        let cancellableClient = MissCatNativeComposeAPIClient(
            scope: try makeScope(token: "cancel-token"),
            transport: suspended,
            timeout: 20
        )
        let task = Task {
            try await cancellableClient.createNote(
                MissCatComposeAPINote(visibility: .public, text: "cancel me")
            )
        }
        await suspended.waitUntilRequested()
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected unknown mutation outcome")
        } catch let error as MissCatNativeComposeAPIError {
            XCTAssertEqual(error, .outcomeUnknown(endpoint: "notes/create"))
        }
        let cancellationRequestCount = await suspended.requestCount
        XCTAssertEqual(cancellationRequestCount, 1)
    }

    func testCancellingNativeURLSessionTransportStopsTheActiveURLSessionTask() async throws {
        let started = expectation(description: "URL loading started")
        let stopped = expectation(description: "URL loading stopped")
        ComposeURLProtocolStub.suspendsRequests = true
        ComposeURLProtocolStub.onStart = { started.fulfill() }
        ComposeURLProtocolStub.onStop = { stopped.fulfill() }
        let client = try makeClient(token: "urlsession-cancel-token")
        let task = Task {
            try await client.createNote(
                MissCatComposeAPINote(visibility: .public, text: "cancel active URLSession task")
            )
        }
        await fulfillment(of: [started], timeout: 2)

        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected outcomeUnknown after an in-flight mutation cancellation")
        } catch let error as MissCatNativeComposeAPIError {
            XCTAssertEqual(error, .outcomeUnknown(endpoint: "notes/create"))
        }
        await fulfillment(of: [stopped], timeout: 2)
    }

    func testServiceRejectsConcurrentDuplicateAndAllowsNextAttemptAfterCompletion() async throws {
        let suspended = SuspendedComposeHTTPTransport()
        let user = SecureUser(
            userId: "user",
            username: "cat",
            instance: "example.invalid",
            apiKey: "concurrent-guard-token"
        )
        let service = MissCatComposePostService(
            userProvider: { _ in user },
            transport: suspended,
            journal: MemoryComposeJournal()
        )
        let submission = MissCatComposeSubmission(
            accountID: user.accountIdentifier,
            mode: .note,
            text: "one post",
            contentWarning: nil,
            visibility: .public,
            visibleUserIDs: [],
            localOnly: false,
            noExtractMentions: false,
            noExtractHashtags: false,
            media: [],
            poll: nil
        )
        let first = Task { @MainActor in
            try await service.submit(submission) { _ in }
        }
        await suspended.waitUntilRequested()

        do {
            try await service.submit(submission) { _ in }
            XCTFail("Expected exact-once guard")
        } catch let error as MissCatNativeComposeAPIError {
            XCTAssertEqual(error, .alreadySubmitting)
        }
        let duplicateRequestCount = await suspended.requestCount
        XCTAssertEqual(duplicateRequestCount, 1)

        await suspended.succeed(with: Data(#"{"createdNote":{"id":"note-1"}}"#.utf8))
        try await first.value
        let second = Task { @MainActor in
            try await service.submit(submission) { _ in }
        }
        await suspended.waitUntilRequestCount(2)
        await suspended.succeed(with: Data(#"{"createdNote":{"id":"note-2"}}"#.utf8))
        try await second.value
        let finalRequestCount = await suspended.requestCount
        XCTAssertEqual(finalRequestCount, 2)
    }

    func testOutcomeUnknownJournalBlocksSameOperationWithoutSecondNetworkMutation() async throws {
        let recorder = ComposeRequestRecorder()
        ComposeURLProtocolStub.handler = { request in
            recorder.record(request)
            throw URLError(.timedOut)
        }
        let user = SecureUser(
            userId: "unknown-user",
            username: "cat",
            instance: "unknown.example",
            apiKey: "unknown-token"
        )
        let journal = MemoryComposeJournal()
        let service = MissCatComposePostService(
            userProvider: { _ in user },
            transport: MissCatComposeURLSessionTransport(session: urlSession),
            journal: journal
        )
        let submission = makeSubmission(user: user, text: "ambiguous note")

        for _ in 0 ..< 2 {
            do {
                try await service.submit(submission) { _ in }
                XCTFail("Expected outcomeUnknown")
            } catch let error as MissCatNativeComposeAPIError {
                XCTAssertEqual(error, .outcomeUnknown(endpoint: "notes/create"))
            }
        }
        XCTAssertEqual(recorder.snapshot().map { $0.request.url?.path }, ["/api/notes/create"])
    }

    func testReplyQuoteAndRenoteMetadataDriftKeepsCanonicalFingerprintAndBlocksRelaunch() async throws {
        let recorder = ComposeRequestRecorder()
        ComposeURLProtocolStub.handler = { request in
            recorder.record(request)
            throw URLError(.timedOut)
        }
        let user = SecureUser(
            userId: "metadata-user",
            username: "cat",
            instance: "metadata.example",
            apiKey: "metadata-token"
        )
        let original = MissCatComposeTarget(
            id: "target-id",
            username: "before",
            instance: "before.example",
            text: "old display text",
            avatarURL: URL(string: "https://before.example/avatar.png")
        )
        let drifted = MissCatComposeTarget(
            id: "target-id",
            username: "after",
            instance: "after.example",
            text: "new display text",
            avatarURL: URL(string: "https://after.example/avatar.png")
        )
        let modePairs: [(MissCatComposeMode, MissCatComposeMode)] = [
            (.reply(original), .reply(drifted)),
            (.quote(original), .quote(drifted)),
            (.renote(original), .renote(drifted))
        ]

        for (index, pair) in modePairs.enumerated() {
            let journal = MemoryComposeJournal()
            let service = MissCatComposePostService(
                userProvider: { _ in user },
                transport: MissCatComposeURLSessionTransport(session: urlSession),
                journal: journal
            )
            let originalSubmission = makeSubmission(
                user: user,
                text: pair.0.isRenote ? "" : "body-\(index)",
                mode: pair.0
            )
            let driftedSubmission = makeSubmission(
                user: user,
                text: pair.1.isRenote ? "" : "body-\(index)",
                mode: pair.1
            )
            XCTAssertEqual(
                service.operationFingerprint(for: originalSubmission),
                service.operationFingerprint(for: driftedSubmission)
            )

            for submission in [originalSubmission, driftedSubmission] {
                do {
                    try await service.submit(submission) { _ in }
                    XCTFail("Expected durable outcomeUnknown")
                } catch let error as MissCatNativeComposeAPIError {
                    XCTAssertEqual(error, .outcomeUnknown(endpoint: "notes/create"))
                }
            }
        }

        XCTAssertEqual(recorder.snapshot().count, modePairs.count)
    }

    func testMismatchedJournalIdentityAndIllegalPhaseRejectBeforeNetworkMutation() async throws {
        let recorder = ComposeRequestRecorder()
        ComposeURLProtocolStub.handler = { request in
            recorder.record(request)
            return (200, Data(#"{"createdNote":{"id":"must-not-exist"}}"#.utf8))
        }
        let user = SecureUser(
            userId: "bound-user",
            username: "cat",
            instance: "bound.example",
            apiKey: "bound-token"
        )
        let submission = makeSubmission(user: user, text: "bound request")
        let scope = try MissCatComposeAccountScope(
            accountID: user.accountIdentifier,
            instance: user.instance,
            accessToken: "bound-token"
        )
        let journal = MemoryComposeJournal()
        let service = MissCatComposePostService(
            userProvider: { _ in user },
            transport: MissCatComposeURLSessionTransport(session: urlSession),
            journal: journal
        )
        let expected = service.operationIdentity(for: submission, scope: scope)
        let mismatches = [
            MissCatComposeOperationRecord.Identity(
                fingerprint: String(repeating: "0", count: 64),
                operation: expected.operation,
                accountIdentifierHash: expected.accountIdentifierHash,
                instanceOriginHash: expected.instanceOriginHash,
                mediaCount: expected.mediaCount
            ),
            MissCatComposeOperationRecord.Identity(
                fingerprint: expected.fingerprint,
                operation: .reply,
                accountIdentifierHash: expected.accountIdentifierHash,
                instanceOriginHash: expected.instanceOriginHash,
                mediaCount: expected.mediaCount
            ),
            MissCatComposeOperationRecord.Identity(
                fingerprint: expected.fingerprint,
                operation: expected.operation,
                accountIdentifierHash: String(repeating: "1", count: 64),
                instanceOriginHash: expected.instanceOriginHash,
                mediaCount: expected.mediaCount
            ),
            MissCatComposeOperationRecord.Identity(
                fingerprint: expected.fingerprint,
                operation: expected.operation,
                accountIdentifierHash: expected.accountIdentifierHash,
                instanceOriginHash: String(repeating: "2", count: 64),
                mediaCount: expected.mediaCount
            ),
            MissCatComposeOperationRecord.Identity(
                fingerprint: expected.fingerprint,
                operation: expected.operation,
                accountIdentifierHash: expected.accountIdentifierHash,
                instanceOriginHash: expected.instanceOriginHash,
                mediaCount: 1
            )
        ]

        for mismatch in mismatches {
            journal.set(
                MissCatComposeOperationRecord(identity: mismatch),
                for: expected.fingerprint
            )
            do {
                try await service.submit(submission) { _ in }
                XCTFail("Expected mismatched identity to fail closed")
            } catch let error as MissCatNativeComposeAPIError {
                XCTAssertEqual(error, .outcomeUnknown(endpoint: "journal"))
            }
        }

        journal.set(
            MissCatComposeOperationRecord(identity: expected, phase: .noteCreated),
            for: expected.fingerprint
        )
        do {
            try await service.submit(submission) { _ in }
            XCTFail("Expected illegal phase to fail closed")
        } catch let error as MissCatNativeComposeAPIError {
            XCTAssertEqual(error, .outcomeUnknown(endpoint: "journal"))
        }
        XCTAssertTrue(recorder.snapshot().isEmpty)
    }

    func testSafeRelaunchReusesKnownUploadIDWithoutUploadingAgain() async throws {
        let recorder = ComposeRequestRecorder()
        ComposeURLProtocolStub.handler = { request in
            recorder.record(request)
            return (200, Data(#"{"createdNote":{"id":"resumed-note"}}"#.utf8))
        }
        let user = SecureUser(
            userId: "resume-user",
            username: "cat",
            instance: "resume.example",
            apiKey: "resume-token"
        )
        let journal = MemoryComposeJournal()
        let service = MissCatComposePostService(
            userProvider: { _ in user },
            transport: MissCatComposeURLSessionTransport(session: urlSession),
            journal: journal
        )
        let submission = makeSubmission(
            user: user,
            text: "resume upload",
            media: [
                MissCatComposeMedia(
                    kind: .image,
                    data: makeValidJPEG(red: 1, green: 0),
                    filename: "known.jpeg",
                    mimeType: "image/jpeg"
                )
            ]
        )
        let scope = try MissCatComposeAccountScope(
            accountID: user.accountIdentifier,
            instance: user.instance,
            accessToken: "resume-token"
        )
        let identity = service.operationIdentity(for: submission, scope: scope)
        XCTAssertTrue(journal.save(MissCatComposeOperationRecord(
            identity: identity,
            phase: .uploading,
            knownFileIDs: ["known-file"]
        )))

        try await service.submit(submission) { _ in }

        let requests = recorder.snapshot()
        XCTAssertEqual(requests.map { $0.request.url?.path }, ["/api/notes/create"])
        XCTAssertEqual(try requests[0].jsonBody["fileIds"] as? [String], ["known-file"])
    }

    func testDefiniteNoteFailureDeletesKnownOrphanUpload() async throws {
        let recorder = ComposeRequestRecorder()
        ComposeURLProtocolStub.handler = { request in
            recorder.record(request)
            switch request.url?.path {
            case "/api/drive/files/create":
                return (200, Data(#"{"id":"orphan-file"}"#.utf8))
            case "/api/notes/create":
                return (422, Data(#"{"error":{"code":"INVALID_PARAM"}}"#.utf8))
            case "/api/drive/files/delete":
                return (204, Data())
            default:
                return (404, Data())
            }
        }
        let user = SecureUser(
            userId: "cleanup-user",
            username: "cat",
            instance: "cleanup.example",
            apiKey: "cleanup-token"
        )
        let service = MissCatComposePostService(
            userProvider: { _ in user },
            transport: MissCatComposeURLSessionTransport(session: urlSession),
            journal: MemoryComposeJournal()
        )
        let submission = makeSubmission(
            user: user,
            text: "definite failure",
            media: [
                MissCatComposeMedia(
                    kind: .image,
                    data: makeValidJPEG(red: 0, green: 1),
                    filename: "orphan.jpeg",
                    mimeType: "image/jpeg"
                )
            ]
        )

        do {
            try await service.submit(submission) { _ in }
            XCTFail("Expected server rejection")
        } catch let error as MissCatNativeComposeAPIError {
            guard case .server(status: 422, code: "INVALID_PARAM", message: nil, id: nil) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        let requests = recorder.snapshot()
        XCTAssertEqual(requests.map { $0.request.url?.path }, [
            "/api/drive/files/create", "/api/notes/create", "/api/drive/files/delete"
        ])
        XCTAssertEqual(try requests[2].jsonBody["fileId"] as? String, "orphan-file")
    }

    func testOrphanDeleteFailureStaysPendingAndBlocksCleanupAndRepostAfterRelaunch() async throws {
        let recorder = ComposeRequestRecorder()
        ComposeURLProtocolStub.handler = { request in
            recorder.record(request)
            switch request.url?.path {
            case "/api/drive/files/create":
                return (200, Data(#"{"id":"retained-orphan"}"#.utf8))
            case "/api/notes/create":
                return (422, Data(#"{"error":{"code":"INVALID_PARAM"}}"#.utf8))
            case "/api/drive/files/delete":
                throw URLError(.timedOut)
            default:
                return (404, Data())
            }
        }
        let user = SecureUser(
            userId: "orphan-delete-user",
            username: "cat",
            instance: "orphan-delete.example",
            apiKey: "orphan-delete-token"
        )
        let journal = MemoryComposeJournal()
        let submission = makeSubmission(
            user: user,
            text: "cleanup must persist",
            media: [
                MissCatComposeMedia(
                    kind: .image,
                    data: makeValidJPEG(red: 1, green: 0),
                    filename: "orphan.jpeg",
                    mimeType: "image/jpeg"
                )
            ]
        )
        let firstService = MissCatComposePostService(
            userProvider: { _ in user },
            transport: MissCatComposeURLSessionTransport(session: urlSession),
            journal: journal
        )

        do {
            try await firstService.submit(submission) { _ in }
            XCTFail("Expected server rejection")
        } catch let error as MissCatNativeComposeAPIError {
            guard case .server(status: 422, code: "INVALID_PARAM", message: nil, id: nil) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        let fingerprint = firstService.operationFingerprint(for: submission)
        let retained = try XCTUnwrap(journal.record(fingerprint: fingerprint))
        XCTAssertEqual(retained.phase, .outcomeUnknown)
        XCTAssertEqual(retained.uncertainEndpoint, "drive/files/delete")
        XCTAssertEqual(retained.cleanupAttemptedFileIDs, ["retained-orphan"])

        let relaunched = MissCatComposePostService(
            userProvider: { _ in user },
            transport: MissCatComposeURLSessionTransport(session: urlSession),
            journal: journal
        )
        do {
            try await relaunched.submit(submission) { _ in }
            XCTFail("Expected pending cleanup to block relaunch")
        } catch let error as MissCatNativeComposeAPIError {
            XCTAssertEqual(error, .outcomeUnknown(endpoint: "drive/files/delete"))
        }
        XCTAssertEqual(recorder.snapshot().map { $0.request.url?.path }, [
            "/api/drive/files/create", "/api/notes/create", "/api/drive/files/delete"
        ])
    }

    func testCancellationAfterKnownNoteIDDeletesNoteExactlyOnce() async throws {
        let recorder = ComposeRequestRecorder()
        ComposeURLProtocolStub.handler = { request in
            recorder.record(request)
            if request.url?.path == "/api/notes/create" {
                return (200, Data(#"{"createdNote":{"id":"known-note"}}"#.utf8))
            }
            return (204, Data())
        }
        let user = SecureUser(
            userId: "compensate-user",
            username: "cat",
            instance: "compensate.example",
            apiKey: "compensate-token"
        )
        let journal = MemoryComposeJournal()
        var service: MissCatComposePostService!
        service = MissCatComposePostService(
            userProvider: { _ in user },
            transport: MissCatComposeURLSessionTransport(session: urlSession),
            journal: journal
        )
        journal.onSave = { record in
            if record.phase == .noteCreated { service.cancelActiveSubmission() }
        }

        do {
            try await service.submit(makeSubmission(user: user, text: "cancel after response")) { _ in }
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // The known note is compensated before the cancellation returns.
        }

        let requests = recorder.snapshot()
        XCTAssertEqual(requests.map { $0.request.url?.path }, ["/api/notes/create", "/api/notes/delete"])
        XCTAssertEqual(try requests[1].jsonBody["noteId"] as? String, "known-note")
    }

    func testNoteDeleteFailureStaysPendingAndBlocksDeleteAndRepostAfterRelaunch() async throws {
        let recorder = ComposeRequestRecorder()
        ComposeURLProtocolStub.handler = { request in
            recorder.record(request)
            if request.url?.path == "/api/notes/create" {
                return (200, Data(#"{"createdNote":{"id":"retained-note"}}"#.utf8))
            }
            throw URLError(.timedOut)
        }
        let user = SecureUser(
            userId: "note-delete-user",
            username: "cat",
            instance: "note-delete.example",
            apiKey: "note-delete-token"
        )
        let journal = MemoryComposeJournal()
        var firstService: MissCatComposePostService!
        firstService = MissCatComposePostService(
            userProvider: { _ in user },
            transport: MissCatComposeURLSessionTransport(session: urlSession),
            journal: journal
        )
        let submission = makeSubmission(user: user, text: "note cleanup must persist")
        journal.onSave = { record in
            if record.phase == .noteCreated { firstService.cancelActiveSubmission() }
        }

        do {
            try await firstService.submit(submission) { _ in }
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // The cancellation is returned only after compensation is attempted.
        }
        journal.onSave = nil

        let fingerprint = firstService.operationFingerprint(for: submission)
        let retained = try XCTUnwrap(journal.record(fingerprint: fingerprint))
        XCTAssertEqual(retained.phase, .outcomeUnknown)
        XCTAssertEqual(retained.uncertainEndpoint, "notes/delete")
        XCTAssertEqual(retained.createdNoteID, "retained-note")
        XCTAssertTrue(retained.noteDeleteAttempted)

        let relaunched = MissCatComposePostService(
            userProvider: { _ in user },
            transport: MissCatComposeURLSessionTransport(session: urlSession),
            journal: journal
        )
        do {
            try await relaunched.submit(submission) { _ in }
            XCTFail("Expected pending note cleanup to block relaunch")
        } catch let error as MissCatNativeComposeAPIError {
            XCTAssertEqual(error, .outcomeUnknown(endpoint: "notes/delete"))
        }
        XCTAssertEqual(recorder.snapshot().map { $0.request.url?.path }, [
            "/api/notes/create", "/api/notes/delete"
        ])
    }

    func testSameBareUserIDDifferentInstanceBindsExactOriginAndToken() async throws {
        let recorder = ComposeRequestRecorder()
        ComposeURLProtocolStub.handler = { request in
            recorder.record(request)
            return (200, Data(#"{"createdNote":{"id":"exact-note"}}"#.utf8))
        }
        let first = SecureUser(
            userId: "same-user",
            username: "cat",
            instance: "one.example",
            apiKey: "one-token"
        )
        let second = SecureUser(
            userId: "same-user",
            username: "cat",
            instance: "two.example",
            apiKey: "two-token"
        )
        let users = [first.accountIdentifier: first, second.accountIdentifier: second]
        let service = MissCatComposePostService(
            userProvider: { users[$0] },
            transport: MissCatComposeURLSessionTransport(session: urlSession),
            journal: MemoryComposeJournal()
        )

        try await service.submit(makeSubmission(user: second, text: "exact instance")) { _ in }

        let request = try XCTUnwrap(recorder.snapshot().first?.request)
        XCTAssertEqual(request.url?.host, "two.example")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer two-token")
        XCTAssertNotEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer one-token")
    }

    func testJournalWriteFailurePreventsAnyMutationRequest() async throws {
        let recorder = ComposeRequestRecorder()
        ComposeURLProtocolStub.handler = { request in
            recorder.record(request)
            return (200, Data(#"{"createdNote":{"id":"must-not-exist"}}"#.utf8))
        }
        let user = SecureUser(
            userId: "journal-user",
            username: "cat",
            instance: "journal.example",
            apiKey: "journal-token"
        )
        let service = MissCatComposePostService(
            userProvider: { _ in user },
            transport: MissCatComposeURLSessionTransport(session: urlSession),
            journal: FailingComposeJournal()
        )

        do {
            try await service.submit(makeSubmission(user: user, text: "must not dispatch")) { _ in }
            XCTFail("Expected journalUnavailable")
        } catch let error as MissCatNativeComposeAPIError {
            XCTAssertEqual(error, .journalUnavailable)
        }
        XCTAssertTrue(recorder.snapshot().isEmpty)
    }

    func testUserDefaultsJournalPersistsWithoutDraftOrCredentialAndCorruptionFailsClosed() throws {
        let suiteName = "MissCatComposeJournalTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let journal = MissCatComposeOperationJournal(defaults: defaults)
        let fingerprint = String(repeating: "a", count: 64)
        let key = "native-compose-operation-v1.\(fingerprint)"
        let identity = MissCatComposeOperationRecord.Identity(
            fingerprint: fingerprint,
            operation: .note,
            accountIdentifierHash: String(repeating: "b", count: 64),
            instanceOriginHash: String(repeating: "c", count: 64),
            mediaCount: 1
        )
        let record = MissCatComposeOperationRecord(
            identity: identity,
            phase: .uploading,
            knownFileIDs: ["known-file-id"]
        )

        XCTAssertTrue(journal.save(record))
        XCTAssertEqual(journal.record(fingerprint: fingerprint), record)
        let stored = try XCTUnwrap(defaults.data(forKey: key))
        XCTAssertNil(stored.range(of: Data("private-draft-body".utf8)))
        XCTAssertNil(stored.range(of: Data("private-access-token".utf8)))

        let otherFingerprint = String(repeating: "d", count: 64)
        let mismatched = MissCatComposeOperationRecord(
            identity: MissCatComposeOperationRecord.Identity(
                fingerprint: otherFingerprint,
                operation: .note,
                accountIdentifierHash: identity.accountIdentifierHash,
                instanceOriginHash: identity.instanceOriginHash,
                mediaCount: 1
            ),
            phase: .uploading,
            knownFileIDs: ["known-file-id"]
        )
        defaults.set(try JSONEncoder().encode(mismatched), forKey: key)
        XCTAssertTrue(defaults.synchronize())
        XCTAssertEqual(
            journal.record(fingerprint: fingerprint),
            MissCatComposeOperationRecord.invalid(fingerprint: fingerprint)
        )

        defaults.set(Data("not-json".utf8), forKey: key)
        XCTAssertTrue(defaults.synchronize())
        XCTAssertEqual(
            journal.record(fingerprint: fingerprint),
            MissCatComposeOperationRecord.invalid(fingerprint: fingerprint)
        )
        XCTAssertTrue(journal.remove(fingerprint: fingerprint))
        XCTAssertNil(defaults.data(forKey: key))
    }

    private func makeClient(token: String) throws -> MissCatNativeComposeAPIClient {
        MissCatNativeComposeAPIClient(
            scope: try makeScope(token: token),
            transport: MissCatComposeURLSessionTransport(session: urlSession),
            timeout: 9
        )
    }

    private func makeSubmission(
        user: SecureUser,
        text: String,
        media: [MissCatComposeMedia] = [],
        mode: MissCatComposeMode = .note
    ) -> MissCatComposeSubmission {
        MissCatComposeSubmission(
            accountID: user.accountIdentifier,
            mode: mode,
            text: text,
            contentWarning: nil,
            visibility: .public,
            visibleUserIDs: [],
            localOnly: false,
            noExtractMentions: false,
            noExtractHashtags: false,
            media: media,
            poll: nil
        )
    }

    private func makeScope(token: String) throws -> MissCatComposeAccountScope {
        try MissCatComposeAccountScope(
            accountID: "account-id",
            instance: "HTTPS://EXAMPLE.INVALID:443/",
            accessToken: token
        )
    }

    private func makeValidJPEG(red: CGFloat, green: CGFloat) -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2))
        return renderer.image { context in
            UIColor(red: red, green: green, blue: 0, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }.jpegData(compressionQuality: 1)!
    }
}

@MainActor
final class MissCatComposeViewModelTests: XCTestCase {
    func testLoadUsesCurrentAccountAndSavedVisibility() async {
        let environment = FakeComposeEnvironment(
            bootstrap: MissCatComposeBootstrap(
                accounts: [makeAccount(id: "a"), makeAccount(id: "b")],
                selectedAccountID: "b",
                visibility: .followers
            )
        )
        let viewModel = makeViewModel(environment: environment, posting: SequencedComposePosting(results: []))

        await viewModel.load()

        XCTAssertEqual(viewModel.phase, .ready)
        XCTAssertEqual(viewModel.selectedAccountID, "b")
        XCTAssertEqual(viewModel.draft.visibility, .followers)
    }

    func testSelectionPersistsAccountAndVisibilityAndClearsDirectTargets() async {
        let environment = FakeComposeEnvironment(bootstrap: standardBootstrap)
        let viewModel = makeViewModel(environment: environment, posting: SequencedComposePosting(results: []))
        await viewModel.load()
        viewModel.draft.visibleUserIDs = ["user"]

        viewModel.selectAccount("b")
        viewModel.selectVisibility(.home)

        XCTAssertEqual(environment.persistedAccountIDs, ["b"])
        XCTAssertEqual(environment.persistedVisibilities, [.home])
        XCTAssertTrue(viewModel.draft.visibleUserIDs.isEmpty)
    }

    func testPlainRenoteIgnoresSavedVisibility() async {
        let target = makeTarget(id: "target")
        let environment = FakeComposeEnvironment(
            bootstrap: MissCatComposeBootstrap(
                accounts: [makeAccount(id: "a")],
                selectedAccountID: "a",
                visibility: .followers
            )
        )
        let viewModel = MissCatComposeViewModel(
            mode: .renote(target),
            environment: environment,
            posting: SequencedComposePosting(results: [.success(())])
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.draft.visibility, .public)
        XCTAssertTrue(viewModel.canSubmit)
    }

    func testCancelWinsWhileSubmitIsInFlight() async {
        let posting = SuspendedComposePosting()
        var draft = MissCatComposeDraft()
        draft.text = "投稿"
        draft.media = [makeMedia(index: 0), makeMedia(index: 1)]
        let viewModel = makeViewModel(draft: draft, posting: posting)
        await viewModel.load()

        let task = Task { @MainActor in await viewModel.submit() }
        await posting.waitUntilCalled()
        XCTAssertEqual(
            viewModel.phase,
            .uploading(MissCatComposeUploadProgress(completed: 0, total: 2))
        )
        viewModel.cancel()
        XCTAssertEqual(viewModel.phase, .cancelled)

        posting.report(completed: 1, total: 2)
        XCTAssertEqual(viewModel.phase, .cancelled)
        posting.report(completed: 2, total: 2)
        XCTAssertEqual(viewModel.phase, .cancelled)

        posting.succeed()
        let succeeded = await task.value
        XCTAssertFalse(succeeded)
        XCTAssertEqual(viewModel.phase, .cancelled)
        XCTAssertEqual(posting.submissions.count, 1)
    }

    func testFailureKeepsCompleteDraftAndRetries() async {
        let posting = SequencedComposePosting(results: [.failure(TestComposeError.expected), .success(())])
        var draft = MissCatComposeDraft()
        draft.text = "retry @cat #tag"
        draft.hasContentWarning = true
        draft.contentWarning = "cw"
        draft.visibility = .specified
        draft.visibleUserIDs = ["recipient"]
        draft.localOnly = true
        draft.poll = MissCatPollDraft(
            choices: [MissCatPollChoice(text: "A"), MissCatPollChoice(text: "B")],
            allowsMultiple: true,
            expiry: .duration(300)
        )
        draft.media = [makeMedia(index: 0, altText: "description", sensitive: true)]
        let viewModel = makeViewModel(draft: draft, posting: posting)
        await viewModel.load()

        let firstSucceeded = await viewModel.submit()
        XCTAssertFalse(firstSucceeded)
        XCTAssertEqual(viewModel.phase, .failed)
        XCTAssertEqual(viewModel.draft, draft)
        XCTAssertNotNil(viewModel.errorMessage)

        let retrySucceeded = await viewModel.submit()
        XCTAssertTrue(retrySucceeded)
        XCTAssertEqual(posting.submissions.count, 2)
        XCTAssertEqual(posting.submissions[0], posting.submissions[1])
    }

    func testCancelIsDeterministicAndDoesNotSubmit() async {
        let posting = SequencedComposePosting(results: [.success(())])
        let viewModel = makeViewModel(posting: posting)
        await viewModel.load()
        viewModel.draft.text = "discard"

        viewModel.cancel()

        XCTAssertEqual(viewModel.phase, .cancelled)
        XCTAssertTrue(posting.submissions.isEmpty)
    }

    func testCancelDuringUploadCancelsRetainedSubmissionAndWinsTerminalRace() async {
        let posting = SuspendedComposePosting()
        var draft = MissCatComposeDraft()
        draft.text = "cancel active upload"
        draft.media = [makeMedia(index: 0)]
        let viewModel = makeViewModel(draft: draft, posting: posting)
        await viewModel.load()
        let submission = Task { @MainActor in await viewModel.submit() }
        await posting.waitUntilCalled()

        viewModel.cancel()

        let didSubmit = await submission.value
        XCTAssertFalse(didSubmit)
        XCTAssertEqual(viewModel.phase, .cancelled)
        XCTAssertEqual(posting.cancelCount, 1)
        posting.succeed()
        XCTAssertEqual(viewModel.phase, .cancelled)
    }

    func testNowPlayingAddsTextAndArtwork() async {
        let nowPlaying = MissCatNowPlaying(
            artist: "Artist",
            title: "Track",
            artworkData: Data([0x01])
        )
        let viewModel = MissCatComposeViewModel(
            mode: .note,
            environment: FakeComposeEnvironment(bootstrap: standardBootstrap),
            posting: SequencedComposePosting(results: []),
            nowPlayingProvider: FakeNowPlayingProvider(value: nowPlaying)
        )
        await viewModel.load()

        viewModel.addNowPlaying()

        XCTAssertEqual(viewModel.draft.text, "Artist - Track #nowplaying")
        XCTAssertEqual(viewModel.draft.media.count, 1)
        XCTAssertEqual(viewModel.draft.media.first?.altText, "Track")
    }

    private func makeViewModel(
        draft: MissCatComposeDraft = MissCatComposeDraft(),
        environment: FakeComposeEnvironment? = nil,
        posting: MissCatComposeSubmitting
    ) -> MissCatComposeViewModel {
        MissCatComposeViewModel(
            mode: .note,
            draft: draft,
            environment: environment ?? FakeComposeEnvironment(bootstrap: standardBootstrap),
            posting: posting
        )
    }

    private var standardBootstrap: MissCatComposeBootstrap {
        MissCatComposeBootstrap(
            accounts: [makeAccount(id: "a"), makeAccount(id: "b")],
            selectedAccountID: "a",
            visibility: .public
        )
    }
}

@MainActor
private final class FakeComposeEnvironment: MissCatComposeEnvironmentProviding {
    let bootstrap: MissCatComposeBootstrap
    var persistedAccountIDs: [String] = []
    var persistedVisibilities: [MissCatComposeVisibility] = []

    init(bootstrap: MissCatComposeBootstrap) {
        self.bootstrap = bootstrap
    }

    func load() async throws -> MissCatComposeBootstrap { bootstrap }
    func persistSelectedAccount(id: String) { persistedAccountIDs.append(id) }
    func persistVisibility(_ visibility: MissCatComposeVisibility) {
        persistedVisibilities.append(visibility)
    }
}

@MainActor
private final class SequencedComposePosting: MissCatComposeSubmitting {
    var results: [Result<Void, Error>]
    var submissions: [MissCatComposeSubmission] = []

    init(results: [Result<Void, Error>]) {
        self.results = results
    }

    func submit(
        _ submission: MissCatComposeSubmission,
        progress: @escaping (MissCatComposeUploadProgress) -> Void
    ) async throws {
        submissions.append(submission)
        if !submission.media.isEmpty {
            progress(MissCatComposeUploadProgress(completed: submission.media.count, total: submission.media.count))
        }
        guard !results.isEmpty else { return }
        try results.removeFirst().get()
    }
}

@MainActor
private final class SuspendedComposePosting: MissCatComposeSubmitting {
    var submissions: [MissCatComposeSubmission] = []
    private var progressHandler: ((MissCatComposeUploadProgress) -> Void)?
    private var continuation: CheckedContinuation<Void, Error>?
    private var callWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var cancelCount = 0

    func submit(
        _ submission: MissCatComposeSubmission,
        progress: @escaping (MissCatComposeUploadProgress) -> Void
    ) async throws {
        submissions.append(submission)
        progressHandler = progress
        callWaiters.forEach { $0.resume() }
        callWaiters.removeAll()
        try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func waitUntilCalled() async {
        if !submissions.isEmpty { return }
        await withCheckedContinuation { callWaiters.append($0) }
    }

    func report(completed: Int, total: Int) {
        progressHandler?(MissCatComposeUploadProgress(completed: completed, total: total))
    }

    func succeed() {
        continuation?.resume(returning: ())
        continuation = nil
    }

    func cancelActiveSubmission() {
        cancelCount += 1
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }
}

@MainActor
private final class FakeNowPlayingProvider: MissCatNowPlayingProviding {
    let value: MissCatNowPlaying?
    init(value: MissCatNowPlaying?) { self.value = value }
    func current() -> MissCatNowPlaying? { value }
}

private enum TestComposeError: LocalizedError {
    case expected
    var errorDescription: String? { "expected failure" }
}

private func makeTarget(id: String) -> MissCatComposeTarget {
    MissCatComposeTarget(
        id: id,
        username: "cat",
        instance: "misskey.io",
        text: "target text",
        avatarURL: nil
    )
}

private func makeAccount(id: String) -> MissCatComposeAccount {
    MissCatComposeAccount(id: id, username: "cat-\(id)", instance: "misskey.io", avatarURL: nil)
}

private func makeMedia(
    index: Int,
    altText: String = "",
    sensitive: Bool = false
) -> MissCatComposeMedia {
    MissCatComposeMedia(
        kind: .image,
        data: Data([UInt8(index + 1)]),
        filename: "\(index).jpeg",
        mimeType: "image/jpeg",
        altText: altText,
        isSensitive: sensitive
    )
}

private struct RecordedComposeRequest {
    let request: URLRequest
    let body: Data

    var jsonBody: [String: Any] {
        get throws {
            try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        }
    }
}

private final class ComposeRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [RecordedComposeRequest] = []

    @discardableResult
    func record(_ request: URLRequest) -> Int {
        lock.lock()
        defer { lock.unlock() }
        requests.append(
            RecordedComposeRequest(
                request: request,
                body: request.composeBodyData ?? Data()
            )
        )
        return requests.count
    }

    func snapshot() -> [RecordedComposeRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }
}

private final class ComposeURLProtocolStub: URLProtocol {
    static var handler: ((URLRequest) throws -> (status: Int, data: Data))?
    static var suspendsRequests = false
    static var onStart: (() -> Void)?
    static var onStop: (() -> Void)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.onStart?()
        if Self.suspendsRequests { return }
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let result = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: result.status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: result.data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
        Self.onStop?()
    }
}

private actor SuspendedComposeHTTPTransport: MissCatComposeHTTPTransport {
    private(set) var requestCount = 0
    private var request: URLRequest?
    private var continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>?
    private var countWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requestCount += 1
        self.request = request
        let readyWaiters = countWaiters.filter { requestCount >= $0.count }
        countWaiters.removeAll { requestCount >= $0.count }
        readyWaiters.forEach { $0.continuation.resume() }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation = $0 }
        } onCancel: {
            Task { await self.cancelPendingRequest() }
        }
    }

    func waitUntilRequested() async {
        await waitUntilRequestCount(1)
    }

    func waitUntilRequestCount(_ count: Int) async {
        if requestCount >= count { return }
        await withCheckedContinuation { continuation in
            countWaiters.append((count, continuation))
        }
    }

    func succeed(with data: Data, status: Int = 200) {
        guard let request,
              let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
              )
        else { return }
        let continuation = self.continuation
        self.continuation = nil
        self.request = nil
        continuation?.resume(returning: (data, response))
    }

    private func cancelPendingRequest() {
        let continuation = self.continuation
        self.continuation = nil
        request = nil
        continuation?.resume(throwing: CancellationError())
    }
}

private final class MemoryComposeJournal: MissCatComposeOperationJournalStoring {
    private var records: [String: MissCatComposeOperationRecord] = [:]
    var onSave: ((MissCatComposeOperationRecord) -> Void)?

    func record(fingerprint: String) -> MissCatComposeOperationRecord? {
        records[fingerprint]
    }

    func save(_ record: MissCatComposeOperationRecord) -> Bool {
        records[record.fingerprint] = record
        onSave?(record)
        return true
    }

    func set(_ record: MissCatComposeOperationRecord, for fingerprint: String) {
        records[fingerprint] = record
    }

    func remove(fingerprint: String) -> Bool {
        records.removeValue(forKey: fingerprint)
        return true
    }
}

private final class FailingComposeJournal: MissCatComposeOperationJournalStoring {
    func record(fingerprint: String) -> MissCatComposeOperationRecord? { nil }
    func save(_ record: MissCatComposeOperationRecord) -> Bool { false }
    func remove(fingerprint: String) -> Bool { false }
}

private extension URLRequest {
    var composeBodyData: Data? {
        if let httpBody { return httpBody }
        guard let httpBodyStream else { return nil }

        httpBodyStream.open()
        defer { httpBodyStream.close() }
        var body = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4_096)
        defer { buffer.deallocate() }
        while httpBodyStream.hasBytesAvailable {
            let read = httpBodyStream.read(buffer, maxLength: 4_096)
            guard read > 0 else { break }
            body.append(buffer, count: read)
        }
        return body
    }
}
