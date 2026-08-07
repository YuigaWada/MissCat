@testable import MissCat
import CoreGraphics
import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers
import XCTest

final class ShareExtensionSwiftUIBoundaryTests: XCTestCase {
    func testOnlyPrincipalControllerRetainsTheRequiredUIKitBoundary() throws {
        let entry = try source("MissCatShare/ShareViewController.swift")
        let composer = try source("MissCatShare/ShareComposerView.swift")
        let input = try source("MissCatShare/ShareInputLoader.swift")
        let post = try source("MissCatShare/PostModel.swift")

        XCTAssertTrue(entry.contains("import UIKit"))
        XCTAssertTrue(entry.contains("import SwiftUI"))
        XCTAssertTrue(entry.contains("final class ShareViewController: UIViewController"))
        XCTAssertTrue(entry.contains("UIHostingController"))
        XCTAssertTrue(entry.contains("extensionContext"))
        XCTAssertTrue(entry.contains("ShareExtensionRootView"))
        for misplacedResponsibility in [
            "ShareInputLoader", "ShareComposerViewModel", "SharePostService", "loadSharedContent"
        ] {
            XCTAssertFalse(
                entry.contains(misplacedResponsibility),
                "Principal boundary owns non-host responsibility: \(misplacedResponsibility)"
            )
        }
        for forbidden in ["UILabel", "UIStackView", "UIImage", "UIViewRepresentable"] {
            XCTAssertFalse(entry.contains(forbidden), "Principal boundary leaked visual UIKit: \(forbidden)")
        }

        XCTAssertTrue(composer.contains("import SwiftUI"))
        XCTAssertTrue(composer.contains("ShareCredentialReadProofView"))
        XCTAssertTrue(composer.contains("share-keychain-proof.available"))
        XCTAssertTrue(composer.contains("share-keychain-proof.account-hash"))
        for source in [composer, input, post] {
            XCTAssertFalse(source.contains("import UIKit"))
            XCTAssertFalse(source.contains("UIImage"))
            XCTAssertFalse(source.contains("UIGraphics"))
            XCTAssertFalse(source.contains("UIViewControllerRepresentable"))
        }
    }

    func testShareExtensionKeepsSystemPrincipalClassAndNativeSwiftUIRatioBaseline() throws {
        let info = try source("MissCatShare/Info.plist")
        let baselineData = try Data(
            contentsOf: repositoryRoot.appendingPathComponent(
                "config/swiftui-share-framework-ratio-baseline.json"
            )
        )
        let baseline = try XCTUnwrap(
            JSONSerialization.jsonObject(with: baselineData) as? [String: Any]
        )
        let counts = try XCTUnwrap(baseline["counts"] as? [String: Int])

        XCTAssertTrue(info.contains("com.apple.share-services"))
        XCTAssertTrue(info.contains("NSExtensionPrincipalClass"))
        XCTAssertTrue(info.contains("$(PRODUCT_MODULE_NAME).ShareViewController"))
        XCTAssertEqual(baseline["target"] as? String, "MissCatShare")
        XCTAssertEqual(counts["total_swift"], 8)
        XCTAssertEqual(counts["uikit_only"], 0)
        XCTAssertEqual(counts["swiftui_only"], 1)
        XCTAssertEqual(counts["hybrid"], 1)
        XCTAssertEqual(counts["neutral"], 6)
    }

    private func source(_ relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

final class ShareImageCodecTests: XCTestCase {
    func testPreviewDecodeAndJPEGPreparationRemainUIKitFreeAndBounded() throws {
        let sourceData = try makePNG(width: 2_048, height: 8)
        let preview = try XCTUnwrap(ShareImageCodec.decode(sourceData))
        XCTAssertEqual(preview.width, 2_048)
        XCTAssertEqual(preview.height, 8)

        let jpeg = try ShareImageCodec.prepareJPEG(
            sourceData,
            maximumWidth: 1_024,
            compressionQuality: 0.5
        )
        let imageSource = try XCTUnwrap(
            CGImageSourceCreateWithData(jpeg as CFData, nil)
        )
        let prepared = try XCTUnwrap(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))

        XCTAssertEqual(CGImageSourceGetType(imageSource) as String?, UTType.jpeg.identifier)
        XCTAssertEqual(prepared.width, 1_024)
        XCTAssertEqual(prepared.height, 4)
    }

    private func makePNG(width: Int, height: Int) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.1, green: 0.5, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}

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
        let proof = ShareCredentialReadProof(
            accountIdentifierHash: ShareCredentialReadProof.accountHash(accountID),
            credentialAvailable: true
        )

        XCTAssertEqual(
            proof.accountIdentifierHash,
            ShareCredentialReadProof.accountHash(accountID)
        )
        XCTAssertTrue(proof.credentialAvailable)
        XCTAssertFalse(proof.description.localizedCaseInsensitiveContains("token"))
        XCTAssertFalse(proof.description.localizedCaseInsensitiveContains("secret"))
        XCTAssertFalse(proof.description.contains(accountID))
    }

    func testSignedCredentialProbeInvokesExactCompositeAccountAndStoresOnlyProof() {
        let first = ShareAccount(userID: "same-user", username: "cat", instance: "one.example")
        let second = ShareAccount(userID: "same-user", username: "cat", instance: "two.example")
        var requestedAccountID: String?
        var storedProof: ShareCredentialReadProof?

        let invoked = ShareCredentialReadProbe.invokeIfRequested(
            arguments: [ShareCredentialReadProbe.launchArgument],
            accountIdentifier: second.id,
            read: { accountID in
                requestedAccountID = accountID
                return ShareCredentialReadProof(
                    accountIdentifierHash: ShareCredentialReadProof.accountHash(accountID),
                    credentialAvailable: true
                )
            },
            store: { storedProof = $0 }
        )

        XCTAssertTrue(invoked)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(requestedAccountID, second.id)
        XCTAssertEqual(storedProof?.accountIdentifierHash, ShareCredentialReadProof.accountHash(second.id))
        XCTAssertFalse(storedProof?.description.contains(second.id) == true)
    }

    func testActiveCancelCancelsPostingBeforeTerminalCompletion() async {
        let posting = SuspendedSharePosting()
        let viewModel = makeViewModel(posting: posting)
        viewModel.load(ShareDraft(text: "cancel share", imageData: []))
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

    func testOutcomeUnknownIsVisibleAndCannotBeRetried() async {
        let posting = SequencedSharePosting(results: [.failure(UnknownShareError())])
        let viewModel = makeViewModel(posting: posting)
        viewModel.load(ShareDraft(text: "ambiguous", imageData: []))

        let firstAttempt = await viewModel.submit()
        XCTAssertFalse(firstAttempt)
        XCTAssertEqual(viewModel.phase, .outcomeUnknown)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.canPost)
        let retryAttempt = await viewModel.submit()
        XCTAssertFalse(retryAttempt)
        XCTAssertEqual(posting.submissions.count, 1)
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
final class ShareRequestTerminalArbiterTests: XCTestCase {
    func testCompleteCancelRaceFinishesHostExactlyOnce() {
        let completeFirst = ShareRequestTerminalArbiter()
        XCTAssertTrue(completeFirst.resolve(.completed))
        XCTAssertFalse(completeFirst.resolve(.cancelled))
        XCTAssertEqual(completeFirst.terminal, .completed)

        let cancelFirst = ShareRequestTerminalArbiter()
        XCTAssertTrue(cancelFirst.resolve(.cancelled))
        XCTAssertFalse(cancelFirst.resolve(.completed))
        XCTAssertEqual(cancelFirst.terminal, .cancelled)
    }
}

@MainActor
final class SharePostServiceTraceTests: XCTestCase {
    func testJSONMultipartOrderAndExactCompositeCredentialBinding() async throws {
        let first = SecureUser(
            userId: "same-user",
            username: "cat",
            instance: "one.example",
            apiKey: "one-share-token"
        )
        let second = SecureUser(
            userId: "same-user",
            username: "cat",
            instance: "two.example",
            apiKey: "two-share-token"
        )
        let users = [first.accountIdentifier: first, second.accountIdentifier: second]
        let transport = ShareTraceTransport(responses: [
            .success(status: 200, data: Data(#"{"id":"share-file"}"#.utf8)),
            .success(status: 200, data: Data(#"{"createdNote":{"id":"share-note"}}"#.utf8))
        ])
        let service = SharePostService(
            userProvider: { users[$0] },
            transport: transport,
            journal: ShareMemoryJournal()
        )
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2))
        let imageData = renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }.pngData()!

        try await service.submit(
            draft: ShareDraft(text: "shared text", imageData: [imageData]),
            accountID: second.accountIdentifier,
            visibility: .followers
        )

        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.url?.path }, [
            "/api/drive/files/create", "/api/notes/create"
        ])
        XCTAssertTrue(requests.allSatisfy { $0.url?.host == "two.example" })
        XCTAssertTrue(requests.allSatisfy {
            $0.value(forHTTPHeaderField: "Authorization") == "Bearer two-share-token"
        })
        XCTAssertTrue(requests.allSatisfy {
            $0.value(forHTTPHeaderField: "Authorization") != "Bearer one-share-token"
        })
        XCTAssertTrue(requests.allSatisfy {
            $0.value(forHTTPHeaderField: "Idempotency-Key") == nil
        })

        let multipart = String(decoding: try XCTUnwrap(requests[0].httpBody), as: UTF8.self)
        let fields = ["name=\"name\"", "name=\"isSensitive\"", "name=\"force\"", "name=\"file\""]
        let offsets = try fields.map { field in
            try XCTUnwrap(multipart.range(of: field)?.lowerBound).utf16Offset(in: multipart)
        }
        XCTAssertEqual(offsets, offsets.sorted())
        XCTAssertFalse(multipart.contains("name=\"comment\""))
        XCTAssertTrue(multipart.contains("name=\"isSensitive\"\r\n\r\nfalse"))
        XCTAssertFalse(multipart.contains("two-share-token"))

        let noteBody = try XCTUnwrap(requests[1].httpBody)
        let note = try XCTUnwrap(JSONSerialization.jsonObject(with: noteBody) as? [String: Any])
        XCTAssertEqual(note["text"] as? String, "shared text")
        XCTAssertEqual(note["visibility"] as? String, "followers")
        XCTAssertEqual(note["fileIds"] as? [String], ["share-file"])
    }

    func testTimeoutBecomesDurableOutcomeUnknownAndBlocksSameShareRetry() async throws {
        let user = SecureUser(
            userId: "share-unknown",
            username: "cat",
            instance: "unknown.example",
            apiKey: "share-unknown-token"
        )
        let transport = ShareFailingTransport()
        let journal = ShareMemoryJournal()
        let service = SharePostService(
            userProvider: { _ in user },
            transport: transport,
            journal: journal
        )

        for _ in 0 ..< 2 {
            do {
                try await service.submit(
                    draft: ShareDraft(text: "unknown share body", imageData: []),
                    accountID: user.accountIdentifier,
                    visibility: .public
                )
                XCTFail("Expected outcomeUnknown")
            } catch let error as MissCatNativeComposeAPIError {
                XCTAssertEqual(error, .outcomeUnknown(endpoint: "notes/create"))
            }
        }

        let requestCount = await transport.requestCount
        XCTAssertEqual(requestCount, 1)
        let journalData = try JSONEncoder().encode(try XCTUnwrap(journal.records.values.first))
        XCTAssertNil(journalData.range(of: Data("share-unknown-token".utf8)))
        XCTAssertNil(journalData.range(of: Data("unknown share body".utf8)))
    }

    func testDisplayMetadataDriftStillBlocksSameShareOperationAfterRelaunch() async throws {
        let originalUser = SecureUser(
            userId: "share-drift",
            username: "before",
            instance: "drift.example",
            apiKey: "share-drift-token"
        )
        let driftedUser = SecureUser(
            userId: "share-drift",
            username: "after",
            instance: "drift.example",
            apiKey: "share-drift-token"
        )
        let transport = ShareFailingTransport()
        let journal = ShareMemoryJournal()
        let draft = ShareDraft(text: "stable share request", imageData: [])

        let originalService = SharePostService(
            userProvider: { _ in originalUser },
            transport: transport,
            journal: journal
        )
        do {
            try await originalService.submit(
                draft: draft,
                accountID: originalUser.accountIdentifier,
                visibility: .home
            )
            XCTFail("Expected outcomeUnknown")
        } catch let error as MissCatNativeComposeAPIError {
            XCTAssertEqual(error, .outcomeUnknown(endpoint: "notes/create"))
        }

        let relaunchedService = SharePostService(
            userProvider: { _ in driftedUser },
            transport: transport,
            journal: journal
        )
        do {
            try await relaunchedService.submit(
                draft: draft,
                accountID: driftedUser.accountIdentifier,
                visibility: .home
            )
            XCTFail("Expected durable outcomeUnknown")
        } catch let error as MissCatNativeComposeAPIError {
            XCTAssertEqual(error, .outcomeUnknown(endpoint: "notes/create"))
        }

        let requestCount = await transport.requestCount
        XCTAssertEqual(requestCount, 1)
    }

    func testMismatchedShareJournalIdentityAndIllegalPhaseRejectBeforeMutation() async throws {
        let user = SecureUser(
            userId: "share-bound",
            username: "cat",
            instance: "share-bound.example",
            apiKey: "share-bound-token"
        )
        let journal = ShareMemoryJournal()
        let transport = ShareTraceTransport(responses: [])
        let model = try PostModel(user: user, transport: transport, journal: journal)
        let draft = ShareDraft(text: "bound share request", imageData: [])
        let expected = model.operationIdentity(draft: draft, visibility: .followers)
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
                operation: .note,
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
            )
        ]

        for mismatch in mismatches {
            journal.set(
                MissCatComposeOperationRecord(identity: mismatch),
                for: expected.fingerprint
            )
            do {
                try await model.submitNote(draft: draft, visibility: .followers)
                XCTFail("Expected mismatched Share identity to fail closed")
            } catch let error as MissCatNativeComposeAPIError {
                XCTAssertEqual(error, .outcomeUnknown(endpoint: "journal"))
            }
        }

        journal.set(
            MissCatComposeOperationRecord(identity: expected, phase: .noteCreated),
            for: expected.fingerprint
        )
        do {
            try await model.submitNote(draft: draft, visibility: .followers)
            XCTFail("Expected illegal Share phase to fail closed")
        } catch let error as MissCatNativeComposeAPIError {
            XCTAssertEqual(error, .outcomeUnknown(endpoint: "journal"))
        }
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testShareOrphanDeleteFailurePersistsAndBlocksRelaunch() async throws {
        let user = SecureUser(
            userId: "share-orphan",
            username: "cat",
            instance: "share-orphan.example",
            apiKey: "share-orphan-token"
        )
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2))
        let imageData = renderer.image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }.pngData()!
        let draft = ShareDraft(text: "share cleanup", imageData: [imageData])
        let transport = ShareTraceTransport(responses: [
            .success(status: 200, data: Data(#"{"id":"share-orphan-file"}"#.utf8)),
            .success(status: 422, data: Data(#"{"error":{"code":"INVALID_PARAM"}}"#.utf8)),
            .failure(.timedOut)
        ])
        let journal = ShareMemoryJournal()
        let service = SharePostService(
            userProvider: { _ in user },
            transport: transport,
            journal: journal
        )

        do {
            try await service.submit(
                draft: draft,
                accountID: user.accountIdentifier,
                visibility: .public
            )
            XCTFail("Expected server rejection")
        } catch let error as MissCatNativeComposeAPIError {
            guard case .server(status: 422, code: "INVALID_PARAM", message: nil, id: nil) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        let retained = try XCTUnwrap(journal.records.values.first)
        XCTAssertEqual(retained.phase, .outcomeUnknown)
        XCTAssertEqual(retained.uncertainEndpoint, "drive/files/delete")
        XCTAssertEqual(retained.cleanupAttemptedFileIDs, ["share-orphan-file"])
        do {
            try await service.submit(
                draft: draft,
                accountID: user.accountIdentifier,
                visibility: .public
            )
            XCTFail("Expected pending cleanup to block relaunch")
        } catch let error as MissCatNativeComposeAPIError {
            XCTAssertEqual(error, .outcomeUnknown(endpoint: "drive/files/delete"))
        }
        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.url?.path }, [
            "/api/drive/files/create", "/api/notes/create", "/api/drive/files/delete"
        ])
    }

    func testShareNoteDeleteFailurePersistsAndBlocksRelaunch() async throws {
        let user = SecureUser(
            userId: "share-note-delete",
            username: "cat",
            instance: "share-note-delete.example",
            apiKey: "share-note-delete-token"
        )
        let transport = ShareTraceTransport(responses: [
            .success(status: 200, data: Data(#"{"createdNote":{"id":"share-retained-note"}}"#.utf8)),
            .failure(.timedOut)
        ])
        let journal = ShareMemoryJournal()
        var service: SharePostService!
        service = SharePostService(
            userProvider: { _ in user },
            transport: transport,
            journal: journal
        )
        let draft = ShareDraft(text: "share note cleanup", imageData: [])
        journal.onSave = { record in
            if record.phase == .noteCreated { service.cancelActiveSubmission() }
        }

        do {
            try await service.submit(
                draft: draft,
                accountID: user.accountIdentifier,
                visibility: .public
            )
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Compensation was attempted before cancellation returned.
        }
        journal.onSave = nil

        let retained = try XCTUnwrap(journal.records.values.first)
        XCTAssertEqual(retained.phase, .outcomeUnknown)
        XCTAssertEqual(retained.uncertainEndpoint, "notes/delete")
        XCTAssertEqual(retained.createdNoteID, "share-retained-note")
        XCTAssertTrue(retained.noteDeleteAttempted)
        do {
            try await service.submit(
                draft: draft,
                accountID: user.accountIdentifier,
                visibility: .public
            )
            XCTFail("Expected pending cleanup to block relaunch")
        } catch let error as MissCatNativeComposeAPIError {
            XCTAssertEqual(error, .outcomeUnknown(endpoint: "notes/delete"))
        }
        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.url?.path }, [
            "/api/notes/create", "/api/notes/delete"
        ])
    }

    func testShareServiceCancellationReachesActiveTransport() async throws {
        let user = SecureUser(
            userId: "share-cancel",
            username: "cat",
            instance: "cancel.example",
            apiKey: "share-cancel-token"
        )
        let transport = SuspendedShareHTTPTransport()
        let service = SharePostService(
            userProvider: { _ in user },
            transport: transport,
            journal: ShareMemoryJournal()
        )
        let task = Task { @MainActor in
            try await service.submit(
                draft: ShareDraft(text: "cancel active share", imageData: []),
                accountID: user.accountIdentifier,
                visibility: .home
            )
        }
        await transport.waitUntilRequested()

        service.cancelActiveSubmission()

        do {
            try await task.value
            XCTFail("Expected outcomeUnknown")
        } catch let error as MissCatNativeComposeAPIError {
            XCTAssertEqual(error, .outcomeUnknown(endpoint: "notes/create"))
        }
        let cancellationCount = await transport.cancellationCount
        XCTAssertEqual(cancellationCount, 1)
    }
}

@MainActor
private final class SuspendedSharePosting: SharePosting {
    private var continuation: CheckedContinuation<Void, Error>?
    private var calledWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var submissions: [(ShareDraft, String, ShareVisibility)] = []
    private(set) var cancelCount = 0

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

    func cancelActiveSubmission() {
        cancelCount += 1
        continuation?.resume(throwing: CancellationError())
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

private struct UnknownShareError: ShareOutcomeUnknownError, LocalizedError {
    let isOutcomeUnknown = true
    var errorDescription: String? { "送信結果を確認できません" }
}

private final class ShareMemoryJournal: MissCatComposeOperationJournalStoring {
    private(set) var records: [String: MissCatComposeOperationRecord] = [:]
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

private actor ShareTraceTransport: MissCatComposeHTTPTransport {
    enum Response: Sendable {
        case success(status: Int, data: Data)
        case failure(URLError.Code)
    }

    private(set) var requests: [URLRequest] = []
    private var responses: [Response]

    init(responses: [Response]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !responses.isEmpty else { throw URLError(.badServerResponse) }
        let response = responses.removeFirst()
        switch response {
        case let .success(status, data):
            return (
                data,
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: status,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!
            )
        case let .failure(code):
            throw URLError(code)
        }
    }
}

private actor ShareFailingTransport: MissCatComposeHTTPTransport {
    private(set) var requestCount = 0

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requestCount += 1
        throw URLError(.timedOut)
    }
}

private actor SuspendedShareHTTPTransport: MissCatComposeHTTPTransport {
    private(set) var cancellationCount = 0
    private var continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>?
    private var requestedWaiters: [CheckedContinuation<Void, Never>] = []
    private var hasRequested = false

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        hasRequested = true
        requestedWaiters.forEach { $0.resume() }
        requestedWaiters.removeAll()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation = $0 }
        } onCancel: {
            Task { await self.cancelPendingRequest() }
        }
    }

    func waitUntilRequested() async {
        if hasRequested { return }
        await withCheckedContinuation { requestedWaiters.append($0) }
    }

    private func cancelPendingRequest() {
        cancellationCount += 1
        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume(throwing: CancellationError())
    }
}
