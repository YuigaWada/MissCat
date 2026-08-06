@testable import MissCat
import Foundation
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
        draft.contentWarning = String(repeating: "a", count: 1_501)
        XCTAssertThrowsError(
            try MissCatComposeSubmissionBuilder.build(mode: .note, draft: draft, accountID: accountID)
        ) { error in
            XCTAssertEqual(error as? MissCatComposeValidationError, .contentWarningTooLong(limit: 1_500))
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

        draft.media = [makeMedia(index: 0, altText: String(repeating: "a", count: 1_501))]
        assertBuildError(draft, equals: .altTextTooLong(limit: 1_500))
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

    func testSubmitWaitsForUploadsAndPostCompletion() async {
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
        XCTAssertEqual(
            viewModel.phase,
            .uploading(MissCatComposeUploadProgress(completed: 0, total: 2))
        )

        posting.report(completed: 1, total: 2)
        XCTAssertEqual(
            viewModel.phase,
            .uploading(MissCatComposeUploadProgress(completed: 1, total: 2))
        )
        posting.report(completed: 2, total: 2)
        XCTAssertEqual(viewModel.phase, .submitting)

        posting.succeed()
        let succeeded = await task.value
        XCTAssertTrue(succeeded)
        XCTAssertEqual(viewModel.phase, .completed)
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
