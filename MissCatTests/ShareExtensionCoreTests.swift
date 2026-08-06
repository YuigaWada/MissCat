import Foundation
import XCTest

final class ShareContentNormalizerTests: XCTestCase {
    func testNormalizesTextURLAndImagesWithoutDuplicates() throws {
        let image = Data([0x01, 0x02, 0x03])
        let url = try XCTUnwrap(URL(string: "https://misskey.io/notes/example"))

        let draft = ShareContentNormalizer.normalize(
            initialTexts: ["  本文  ", "本文"],
            fragments: [
                .text("追加テキスト"),
                .url(url),
                .url(url),
                .imageData(image),
                .imageData(image),
                .text("   ")
            ]
        )

        XCTAssertEqual(draft.text, "本文\n追加テキスト\nhttps://misskey.io/notes/example")
        XCTAssertEqual(draft.imageData, [image])
        XCTAssertTrue(draft.hasContent)
    }

    func testDoesNotAppendURLAlreadyPresentInInitialText() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/article"))
        let draft = ShareContentNormalizer.normalize(
            initialTexts: ["記事 https://example.com/article"],
            fragments: [.url(url)]
        )

        XCTAssertEqual(draft.text, "記事 https://example.com/article")
    }

    func testEmptyFragmentsNeverProducePostableContent() {
        let draft = ShareContentNormalizer.normalize(
            initialTexts: [" \n "],
            fragments: [.text(""), .imageData(Data())]
        )

        XCTAssertEqual(draft, .empty)
        XCTAssertFalse(draft.hasContent)
    }
}

final class ShareVisibilityTests: XCTestCase {
    func testVisibilityAPIValuesRemainCompatibleWithMisskey() {
        XCTAssertEqual(ShareVisibility.public.apiValue, "public")
        XCTAssertEqual(ShareVisibility.home.apiValue, "home")
        XCTAssertEqual(ShareVisibility.followers.apiValue, "followers")
        XCTAssertEqual(ShareVisibility.allCases.map(\.apiValue), ["public", "home", "followers"])
    }
}

@MainActor
final class ShareComposerViewModelTests: XCTestCase {
    func testSubmitCompletesOnlyAfterPostingServiceSucceeds() async {
        let posting = SuspendedSharePosting()
        let viewModel = makeViewModel(posting: posting)
        viewModel.load(ShareDraft(text: "投稿", imageData: []))

        let submission = Task { @MainActor in await viewModel.submit() }
        await posting.waitUntilCalled()

        XCTAssertEqual(viewModel.phase, .posting)
        XCTAssertFalse(submission.isCancelled)
        let duplicateSucceeded = await viewModel.submit()
        XCTAssertFalse(duplicateSucceeded)
        XCTAssertEqual(posting.submissions.count, 1)

        posting.succeed()
        let didSubmit = await submission.value
        XCTAssertTrue(didSubmit)
        XCTAssertEqual(viewModel.phase, .completed)
        XCTAssertEqual(posting.submissions.count, 1)
    }

    func testFailedSubmitKeepsDraftSelectionAndVisibilityForRetry() async {
        let posting = SequencedSharePosting(results: [
            .failure(TestError.expected),
            .success(())
        ])
        let viewModel = makeViewModel(posting: posting, visibility: .followers)
        let image = Data([0xCA, 0xFE])
        viewModel.load(ShareDraft(text: "再試行する投稿", imageData: [image]))

        let firstAttemptSucceeded = await viewModel.submit()
        XCTAssertFalse(firstAttemptSucceeded)
        XCTAssertEqual(viewModel.phase, .failed)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.text, "再試行する投稿")
        XCTAssertEqual(viewModel.imageData, [image])
        XCTAssertEqual(viewModel.selectedAccountID, "user-1")
        XCTAssertEqual(viewModel.visibility, .followers)

        let retrySucceeded = await viewModel.submit()
        XCTAssertTrue(retrySucceeded)
        XCTAssertEqual(viewModel.phase, .completed)
        XCTAssertEqual(posting.submissions.count, 2)
    }

    func testEmptyOrOverlongDraftNeverCallsPostingService() async {
        let posting = SequencedSharePosting(results: [.success(())])
        let viewModel = makeViewModel(posting: posting)
        viewModel.load(.empty)

        let emptyDraftSucceeded = await viewModel.submit()
        XCTAssertFalse(emptyDraftSucceeded)
        XCTAssertTrue(posting.submissions.isEmpty)

        viewModel.text = String(repeating: "a", count: ShareComposerViewModel.maximumTextLength + 1)
        let overlongDraftSucceeded = await viewModel.submit()
        XCTAssertFalse(overlongDraftSucceeded)
        XCTAssertTrue(posting.submissions.isEmpty)
    }

    func testCompositeAccountSelectionSeparatesSameUserIDAcrossInstances() async throws {
        let first = ShareAccount(userID: "same-user", username: "cat", instance: "one.example")
        let second = ShareAccount(
            userID: "same-user",
            username: "cat",
            instance: "HTTPS://TWO.EXAMPLE:443/"
        )
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(second.instance, "two.example")
        XCTAssertEqual(
            second.id,
            MissCatAccountIdentity.storageKey(instance: "two.example", userId: "same-user")
        )
        let posting = SequencedSharePosting(results: [.success(())])
        let viewModel = ShareComposerViewModel(
            accounts: [first, second],
            selectedAccountID: first.id,
            visibility: .home,
            posting: posting
        )
        viewModel.load(ShareDraft(text: "second instance", imageData: []))

        viewModel.selectedAccountID = second.id
        let didSubmit = await viewModel.submit()

        XCTAssertTrue(didSubmit)
        XCTAssertEqual(posting.submissions.count, 1)
        XCTAssertEqual(posting.submissions.first?.1, second.id)
        XCTAssertEqual(viewModel.selectedAccount?.instance, "two.example")
    }

    func testCredentialReadProofContainsNoCredentialPayload() {
        let accountID = MissCatAccountIdentity.storageKey(
            instance: "proof.example",
            userId: "same-user"
        )
        let accountIdentifierHash = String(repeating: "a", count: 64)
        let proof = ShareCredentialReadProof(
            accountIdentifierHash: accountIdentifierHash,
            credentialAvailable: true
        )

        XCTAssertEqual(proof.accountIdentifierHash, accountIdentifierHash)
        XCTAssertTrue(proof.credentialAvailable)
        XCTAssertFalse(proof.description.localizedCaseInsensitiveContains("token"))
        XCTAssertFalse(proof.description.localizedCaseInsensitiveContains("secret"))
        XCTAssertFalse(proof.description.contains(accountID))
    }

    func testSharedOutcomeUnknownContractProducesTerminalNonRetryableState() async {
        let posting = SequencedSharePosting(results: [.failure(ShareUnknownOutcomeError())])
        let viewModel = makeViewModel(posting: posting)
        viewModel.load(ShareDraft(text: "ambiguous result", imageData: []))

        let didSubmit = await viewModel.submit()

        XCTAssertFalse(didSubmit)
        XCTAssertEqual(viewModel.phase, .outcomeUnknown)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.canPost)
    }

    private func makeViewModel(
        posting: SharePosting,
        visibility: ShareVisibility = .public
    ) -> ShareComposerViewModel {
        ShareComposerViewModel(
            accounts: [ShareAccount(id: "user-1", username: "cat", instance: "misskey.io")],
            selectedAccountID: "user-1",
            visibility: visibility,
            posting: posting
        )
    }
}

@MainActor
private final class SuspendedSharePosting: SharePosting {
    private var continuation: CheckedContinuation<Void, Error>?
    private var calledWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var submissions: [(ShareDraft, String, ShareVisibility)] = []

    func submit(
        draft: ShareDraft,
        accountID: String,
        visibility: ShareVisibility
    ) async throws {
        submissions.append((draft, accountID, visibility))
        calledWaiters.forEach { $0.resume() }
        calledWaiters.removeAll()
        try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func waitUntilCalled() async {
        if !submissions.isEmpty { return }
        await withCheckedContinuation { calledWaiters.append($0) }
    }

    func succeed() {
        continuation?.resume(returning: ())
        continuation = nil
    }
}

@MainActor
private final class SequencedSharePosting: SharePosting {
    private var results: [Result<Void, Error>]
    private(set) var submissions: [(ShareDraft, String, ShareVisibility)] = []

    init(results: [Result<Void, Error>]) {
        self.results = results
    }

    func submit(
        draft: ShareDraft,
        accountID: String,
        visibility: ShareVisibility
    ) async throws {
        submissions.append((draft, accountID, visibility))
        guard !results.isEmpty else { return }
        try results.removeFirst().get()
    }
}

private enum TestError: LocalizedError {
    case expected

    var errorDescription: String? { "expected failure" }
}

private struct ShareUnknownOutcomeError: ShareSubmissionOutcomeError, LocalizedError {
    let isSubmissionOutcomeUnknown = true
    var errorDescription: String? { "送信結果を確認できません" }
}
