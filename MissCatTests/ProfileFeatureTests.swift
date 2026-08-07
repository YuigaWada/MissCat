@testable import MissCat
import Foundation
import Observation
import XCTest

final class MissCatProfileHeaderLayoutTests: XCTestCase {
    func testIdentityWidthAlwaysProducesAValidSwiftUIFrameDimension() {
        let proposedWidths: [CGFloat] = [
            -.infinity,
            -1,
            0,
            125,
            .nan,
            .infinity
        ]

        for proposedWidth in proposedWidths {
            let identityWidth = MissCatProfileHeaderLayout.identityMaxWidth(
                containerWidth: proposedWidth
            )

            XCTAssertTrue(identityWidth.isFinite, "Invalid width for \(proposedWidth)")
            XCTAssertGreaterThanOrEqual(identityWidth, 0, "Negative width for \(proposedWidth)")
        }
    }

    func testIdentityWidthPreservesLegacyGeometryWhenContainerIsWideEnough() {
        XCTAssertEqual(
            MissCatProfileHeaderLayout.identityMaxWidth(containerWidth: 390),
            264
        )
    }
}

final class MissCatProfileTransportContractTests: XCTestCase {
    private var session: URLSession!
    private let account = MissCatProfileAccount(userID: "me", instance: "example.invalid", token: "account-token")

    override func setUp() {
        super.setUp()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProfileURLProtocolStub.self]
        session = URLSession(configuration: configuration)
    }

    override func tearDown() {
        ProfileURLProtocolStub.handler = nil
        session.invalidateAndCancel()
        session = nil
        super.tearDown()
    }

    func testProfileUsesAccountScopedTokenAndCurrentEndpoint() async throws {
        var capturedRequest: URLRequest?
        ProfileURLProtocolStub.handler = { request in
            capturedRequest = request
            return Self.response(for: request, json: Self.userJSON(id: "target", username: "alice"))
        }
        let subject = MissCatRESTProfileRepository(account: account, session: session)

        let profile = try await subject.profile(userID: "target")

        XCTAssertEqual(profile.id, "target")
        XCTAssertEqual(capturedRequest?.url?.path, "/api/users/show")
        let body = try XCTUnwrap(capturedRequest?.profileBodyData).jsonObject
        XCTAssertEqual(body["i"] as? String, "account-token")
        XCTAssertEqual(body["userId"] as? String, "target")
    }

    func testTimelineTabsMapToMisskeyNotesPayload() async throws {
        var requests: [URLRequest] = []
        ProfileURLProtocolStub.handler = { request in
            requests.append(request)
            return Self.response(for: request, json: [])
        }
        let subject = MissCatRESTProfileRepository(account: account, session: session)

        for tab in MissCatProfileTimelineTab.allCases {
            _ = try await subject.notes(userID: "target", tab: tab, cursor: "older", limit: 30)
        }

        XCTAssertEqual(requests.map { $0.url?.path }, Array(repeating: "/api/users/notes", count: 3))
        let bodies = try requests.map { try XCTUnwrap($0.profileBodyData).jsonObject }
        XCTAssertEqual(bodies[0]["withReplies"] as? Bool, false)
        XCTAssertEqual(bodies[0]["withFiles"] as? Bool, false)
        XCTAssertEqual(bodies[1]["withReplies"] as? Bool, true)
        XCTAssertEqual(bodies[1]["withFiles"] as? Bool, false)
        XCTAssertEqual(bodies[2]["withReplies"] as? Bool, false)
        XCTAssertEqual(bodies[2]["withFiles"] as? Bool, true)
        XCTAssertTrue(bodies.allSatisfy { $0["withRenotes"] as? Bool == true })
        XCTAssertTrue(bodies.allSatisfy { $0["includeReplies"] == nil })
        XCTAssertTrue(bodies.allSatisfy { $0["i"] as? String == "account-token" && $0["untilId"] as? String == "older" })
    }

    func testPureRenoteDecodesCurrentNestedNoteInsteadOfRenderingAnEmptyRow() throws {
        let json: [String: Any] = [
            "id": "outer-renote",
            "createdAt": "2026-08-07T00:00:01.000Z",
            "text": NSNull(),
            "user": Self.userJSON(id: "renoter", username: "renoter"),
            "renote": [
                "id": "original-note",
                "createdAt": "2026-08-07T00:00:00.000Z",
                "text": "original body",
                "user": Self.userJSON(id: "author", username: "author"),
                "files": [],
                "repliesCount": 2,
                "renoteCount": 3,
                "reactions": ["👍": 4]
            ]
        ]

        let note = try JSONDecoder().decode(
            MissCatProfileNote.self,
            from: JSONSerialization.data(withJSONObject: json)
        )

        XCTAssertEqual(note.id, "outer-renote")
        XCTAssertEqual(note.text, "original body")
        XCTAssertEqual(note.user.id, "author")
        XCTAssertEqual(note.renotedBy?.id, "renoter")
        XCTAssertEqual(note.reactionCount, 4)
    }

    func testProfileDateParserAcceptsCurrentFractionalAndCompatiblePlainISO8601() {
        XCTAssertNotNil(MissCatProfileAPIDateParser.date(from: "2026-08-07T00:00:00.000Z"))
        XCTAssertNotNil(MissCatProfileAPIDateParser.date(from: "2026-08-07T00:00:00Z"))
        XCTAssertNil(MissCatProfileAPIDateParser.date(from: "not-a-date"))
    }

    func testFollowersAndFollowingDecodeModernRelationshipEdges() async throws {
        ProfileURLProtocolStub.handler = { request in
            let key = request.url?.path.hasSuffix("followers") == true ? "follower" : "followee"
            return Self.response(for: request, json: [["id": "relationship-id", key: Self.userJSON(id: key, username: key)]])
        }
        let subject = MissCatRESTProfileRepository(account: account, session: session)

        let followers = try await subject.users(kind: .followers(userID: "target"), cursor: nil, limit: 1)
        let following = try await subject.users(kind: .following(userID: "target"), cursor: nil, limit: 1)

        XCTAssertEqual(followers.items.map(\.id), ["follower"])
        XCTAssertEqual(following.items.map(\.id), ["followee"])
        XCTAssertEqual(followers.nextCursor, "relationship-id")
        XCTAssertEqual(following.nextCursor, "relationship-id")
    }

    func testRelationshipAcceptsCurrentArrayAndCompatibleObjectResponses() async throws {
        var responses: [Any] = [
            [["id": "target", "isFollowing": true]],
            ["id": "target", "isFollowing": false]
        ]
        var requests: [URLRequest] = []
        ProfileURLProtocolStub.handler = { request in
            requests.append(request)
            return Self.response(for: request, json: responses.removeFirst())
        }
        let subject = MissCatRESTProfileRepository(account: account, session: session)

        let currentResponse = try await subject.relationship(userID: "target")
        let compatibleResponse = try await subject.relationship(userID: "target")

        XCTAssertTrue(currentResponse)
        XCTAssertFalse(compatibleResponse)
        XCTAssertEqual(requests.map { $0.url?.path }, ["/api/users/relation", "/api/users/relation"])
        let bodies = try requests.map { try XCTUnwrap($0.profileBodyData).jsonObject }
        XCTAssertTrue(bodies.allSatisfy {
            $0["i"] as? String == "account-token" && $0["userId"] as? String == "target"
        })
    }

    func testRelationshipRejectsEmptyArrayResponse() async {
        ProfileURLProtocolStub.handler = { request in
            Self.response(for: request, json: [])
        }
        let subject = MissCatRESTProfileRepository(account: account, session: session)

        do {
            _ = try await subject.relationship(userID: "target")
            XCTFail("Expected an empty relation list to be rejected")
        } catch let DecodingError.dataCorrupted(context) {
            XCTAssertEqual(context.debugDescription, "users/relation returned an empty relation list")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testProfileUpdateSendsOnlyChangedFieldAndToken() async throws {
        var capturedBody: [String: Any] = [:]
        ProfileURLProtocolStub.handler = { request in
            capturedBody = try XCTUnwrap(request.profileBodyData).jsonObject
            return Self.response(for: request, json: Self.userJSON(id: "me", username: "alice"))
        }
        let subject = MissCatRESTProfileRepository(account: account, session: session)

        _ = try await subject.updateProfile(patch: .init(name: "New name"))

        XCTAssertEqual(capturedBody["i"] as? String, "account-token")
        XCTAssertEqual(capturedBody["name"] as? String, "New name")
        XCTAssertEqual(Set(capturedBody.keys), ["i", "name"])
    }

    func testProfileImageUpdateDistinguishesUnchangedReplacementAndExplicitRemoval() async throws {
        var capturedBodies: [[String: Any]] = []
        ProfileURLProtocolStub.handler = { request in
            capturedBodies.append(try XCTUnwrap(request.profileBodyData).jsonObject)
            return Self.response(for: request, json: Self.userJSON(id: "me", username: "alice"))
        }
        let subject = MissCatRESTProfileRepository(account: account, session: session)

        _ = try await subject.updateProfile(
            patch: .init(avatarImage: .replace(fileID: "new-avatar"))
        )
        _ = try await subject.updateProfile(
            patch: .init(avatarImage: .remove, bannerImage: .remove)
        )

        XCTAssertEqual(capturedBodies[0]["avatarId"] as? String, "new-avatar")
        XCTAssertNil(capturedBodies[0]["bannerId"])
        XCTAssertTrue(capturedBodies[1]["avatarId"] is NSNull)
        XCTAssertTrue(capturedBodies[1]["bannerId"] is NSNull)
        XCTAssertEqual(Set(capturedBodies[1].keys), ["i", "avatarId", "bannerId"])
    }

    func testDeleteUploadedProfileImageUsesCurrentDriveEndpointAndAccountToken() async throws {
        var capturedRequest: URLRequest?
        ProfileURLProtocolStub.handler = { request in
            capturedRequest = request
            return Self.response(for: request, json: [:])
        }
        let subject = MissCatRESTProfileRepository(account: account, session: session)

        try await subject.deleteProfileImage(fileID: "orphan-file")

        XCTAssertEqual(capturedRequest?.url?.path, "/api/drive/files/delete")
        let body = try XCTUnwrap(capturedRequest?.profileBodyData).jsonObject
        XCTAssertEqual(body["i"] as? String, "account-token")
        XCTAssertEqual(body["fileId"] as? String, "orphan-file")
        XCTAssertEqual(Set(body.keys), ["i", "fileId"])
    }

    func testHTTPFailureSurfacesMisskeyMessage() async {
        ProfileURLProtocolStub.handler = { request in
            Self.response(for: request, status: 401, json: ["error": ["message": "Invalid token"]])
        }
        let subject = MissCatRESTProfileRepository(account: account, session: session)

        do {
            _ = try await subject.profile(userID: "target")
            XCTFail("Expected request to fail")
        } catch {
            XCTAssertEqual(error as? MissCatProfileAPIError, .http(401, "Invalid token"))
        }
    }

    private static func response(for request: URLRequest, status: Int = 200, json: Any) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (response, try! JSONSerialization.data(withJSONObject: json))
    }

    fileprivate static func userJSON(id: String, username: String) -> [String: Any] {
        [
            "id": id,
            "name": "Alice",
            "username": username,
            "description": "Hello",
            "isCat": false,
            "followersCount": 4,
            "followingCount": 3,
            "notesCount": 2
        ]
    }
}

@MainActor
final class MissCatProfileStoreTests: XCTestCase {
    private let account = MissCatProfileAccount(userID: "me", instance: "example.invalid", token: "token-a")

    func testFollowChangesOnlyAfterServerSuccess() async {
        let repository = ProfileRepositorySpy(account: account)
        repository.followDelayNanoseconds = 150_000_000
        let store = MissCatProfileStore(account: account, userID: "other", repositoryFactory: { _ in repository })

        store.setFollowing(true)
        XCTAssertFalse(store.isFollowing)
        XCTAssertEqual(store.followPhase, .loading)

        await waitUntil { store.followPhase == .loaded }
        XCTAssertTrue(store.isFollowing)
        XCTAssertEqual(repository.followCalls, [true])
    }

    func testFollowFailureRollsBackToLastServerConfirmedState() async {
        let repository = ProfileRepositorySpy(account: account)
        repository.followError = StubError.failed
        let store = MissCatProfileStore(account: account, userID: "other", repositoryFactory: { _ in repository })

        store.setFollowing(true)
        await waitUntil { store.followPhase.isFailed }

        XCTAssertFalse(store.isFollowing)
        XCTAssertEqual(repository.followCalls, [true])
        XCTAssertNotNil(store.followErrorMessage)

        repository.followError = nil
        store.retryFollowing()
        await waitUntil { store.followPhase == .loaded }

        XCTAssertTrue(store.isFollowing)
        XCTAssertNil(store.followErrorMessage)
        XCTAssertEqual(repository.followCalls, [true, true])
    }

    func testAccountSwitchCancelsOldTasksAndUsesNewAccount() async {
        let first = ProfileRepositorySpy(account: account)
        first.profileDelayNanoseconds = 800_000_000
        first.profileValue = makeUser(id: "stale")
        let secondAccount = MissCatProfileAccount(userID: "me-b", instance: "second.invalid", token: "token-b")
        let second = ProfileRepositorySpy(account: secondAccount)
        second.profileValue = makeUser(id: "me-b")
        let store = MissCatProfileStore(account: account, userID: "me", repositoryFactory: { value in
            value == secondAccount ? second : first
        })

        store.reloadProfile()
        store.switchAccount(secondAccount)
        await waitUntil { store.profile?.id == "me-b" }
        try? await Task.sleep(nanoseconds: 900_000_000)

        XCTAssertEqual(store.profile?.id, "me-b")
        XCTAssertEqual(store.userID, "me-b")
        XCTAssertEqual(second.profileCalls, ["me-b"])
    }

    func testTimelinePagingDeduplicatesAndPreservesPerTabPosition() async {
        let repository = ProfileRepositorySpy(account: account)
        let firstNote = makeNote(id: "n1")
        repository.notePages[nil] = .init(items: [firstNote], nextCursor: "older")
        repository.notePages["older"] = .init(items: [firstNote, makeNote(id: "n2")], nextCursor: nil)
        let store = MissCatProfileStore(account: account, userID: "other", repositoryFactory: { _ in repository })

        store.loadTimeline(.notes)
        await waitUntil { store.timelines[.notes]?.phase == .loaded }
        store.setTopVisibleNoteID("n1", for: .notes)
        store.loadMoreIfNeeded(tab: .notes, currentNoteID: "n1")
        await waitUntil { store.timelines[.notes]?.notes.count == 2 }

        XCTAssertEqual(store.timelines[.notes]?.notes.map(\.id), ["n1", "n2"])
        XCTAssertEqual(store.timelines[.notes]?.topVisibleNoteID, "n1")
        XCTAssertNil(store.timelines[.media]?.topVisibleNoteID)
        XCTAssertEqual(repository.noteCursors, [nil, "older"])
    }

    func testRapidReverseAndBoundaryTabTransitions() {
        var state = MissCatProfileTabSelectionState()
        state.move(-1)
        XCTAssertEqual(state.selected, .notes)
        state.move(1)
        state.move(1)
        state.move(1)
        XCTAssertEqual(state.selected, .media)
        state.move(-1)
        XCTAssertEqual(state.selected, .notesAndReplies)
        for tab in [MissCatProfileTimelineTab.media, .notes, .media, .notesAndReplies, .notes] {
            state.select(tab)
        }
        XCTAssertEqual(state.selected, .notes)
    }

    func testSelfProfileDoesNotCallRelationshipEndpoint() async {
        let repository = ProfileRepositorySpy(account: account)
        repository.profileValue = makeUser(id: "me")
        let store = MissCatProfileStore(account: account, userID: "me", repositoryFactory: { _ in repository })

        store.reloadProfile()
        await waitUntil { store.profilePhase == .loaded }

        XCTAssertTrue(store.isCurrentUser)
        XCTAssertEqual(repository.relationshipCalls, [])
    }

    func testObservationTracksProfileTabBindingMutation() async {
        let repository = ProfileRepositorySpy(account: account)
        let store = MissCatProfileStore(
            account: account,
            userID: "other",
            repositoryFactory: { _ in repository }
        )
        let changed = expectation(description: "Observation reports the selected-tab binding mutation")

        withObservationTracking {
            _ = store.selectedTab
        } onChange: {
            changed.fulfill()
        }
        store.selectedTab = .media

        await fulfillment(of: [changed], timeout: 1)
        XCTAssertEqual(store.selectedTab, .media)
    }

    func testInjectedProfileStoreIsRetainedOnlyForViewLifetime() {
        let repository = ProfileRepositorySpy(account: account)
        var store: MissCatProfileStore? = MissCatProfileStore(
            account: account,
            userID: "other",
            repositoryFactory: { _ in repository }
        )
        weak var retainedStore = store
        var screen: MissCatProfileScreen? = MissCatProfileScreen(store: store!)

        store = nil
        XCTAssertNotNil(screen)
        XCTAssertNotNil(retainedStore)

        screen = nil
        XCTAssertNil(retainedStore)
    }

    func testDeinitializingProfileStoreCancelsInFlightProfileRequest() async {
        let repository = ProfileRepositorySpy(account: account)
        repository.profileDelayNanoseconds = 3_600_000_000_000
        var store: MissCatProfileStore? = MissCatProfileStore(
            account: account,
            userID: "other",
            repositoryFactory: { _ in repository }
        )
        weak var releasedStore = store

        store?.reloadProfile()
        await waitUntil { repository.profileCalls == ["other"] }
        store = nil
        await waitUntil { repository.profileCancellationCount == 1 }

        XCTAssertNil(releasedStore)
    }
}

@MainActor
final class MissCatProfileEditorAndUserListTests: XCTestCase {
    private let account = MissCatProfileAccount(userID: "me", instance: "example.invalid", token: "token")

    func testEditingOneFieldDoesNotEraseOtherFields() async {
        let repository = ProfileRepositorySpy(account: account)
        let baseline = makeUser(id: "me", name: "Before", description: "Keep me", isCat: true)
        repository.profileValue = makeUser(id: "me", name: "After", description: "Keep me", isCat: true)
        let store = MissCatProfileEditorStore(account: account, profile: baseline, repositoryFactory: { _ in repository })
        store.name = "After"

        store.save()
        await waitUntil { store.phase == .loaded }

        XCTAssertEqual(repository.updatePatches, [.init(name: "After")])
        XCTAssertEqual(store.savedProfile?.description, "Keep me")
    }

    func testAvatarUploadReportsProgressAndAddsOnlyAvatarID() async {
        let repository = ProfileRepositorySpy(account: account)
        let baseline = makeUser(id: "me")
        repository.profileValue = baseline
        let store = MissCatProfileEditorStore(account: account, profile: baseline, repositoryFactory: { _ in repository })
        store.setAvatarData(Data([1, 2, 3]))

        store.save()
        await waitUntil { store.phase == .loaded }

        XCTAssertEqual(repository.uploadFilenames, ["avatar.jpg"])
        XCTAssertEqual(repository.updatePatches, [.init(avatarID: "uploaded-file")])
        XCTAssertEqual(store.uploadProgress, 1)
    }

    func testResettingSelectedImageRestoresUnchangedPatch() async {
        let repository = ProfileRepositorySpy(account: account)
        let baseline = makeUser(id: "me")
        repository.profileValue = baseline
        let store = MissCatProfileEditorStore(account: account, profile: baseline, repositoryFactory: { _ in repository })

        store.setAvatarData(Data([1]))
        XCTAssertTrue(store.hasAvatarChange)
        store.resetAvatar()
        XCTAssertFalse(store.hasAvatarChange)

        store.save()
        await waitUntil { store.phase == .loaded }

        XCTAssertTrue(repository.uploadFilenames.isEmpty)
        XCTAssertTrue(repository.updatePatches.isEmpty)
    }

    func testRemovingExistingImagesSendsExplicitRemovalWithoutUpload() async {
        let repository = ProfileRepositorySpy(account: account)
        repository.profileValue = makeUser(id: "me")
        let baseline = MissCatProfileUser(
            id: "me",
            username: "me",
            avatarURL: URL(string: "https://example.invalid/avatar.jpg"),
            bannerURL: URL(string: "https://example.invalid/banner.jpg")
        )
        let store = MissCatProfileEditorStore(account: account, profile: baseline, repositoryFactory: { _ in repository })

        store.removeAvatar()
        store.removeBanner()
        store.save()
        await waitUntil { store.phase == .loaded }

        XCTAssertEqual(
            repository.updatePatches,
            [.init(avatarImage: .remove, bannerImage: .remove)]
        )
        XCTAssertTrue(repository.uploadFilenames.isEmpty)
    }

    func testCancelAfterUploadStartsDeletesReturnedOrphan() async {
        let repository = ProfileRepositorySpy(account: account)
        repository.profileValue = makeUser(id: "me")
        repository.uploadIDs = ["cancelled-upload"]
        repository.uploadDelayNanoseconds = 150_000_000
        let store = MissCatProfileEditorStore(account: account, profile: makeUser(id: "me"), repositoryFactory: { _ in repository })
        store.setAvatarData(Data([1]))

        store.save()
        await waitUntil { repository.uploadFilenames == ["avatar.jpg"] }
        store.cancelSave()
        await waitUntil { repository.deletedFileIDs == ["cancelled-upload"] }

        XCTAssertEqual(store.phase, .idle)
        XCTAssertTrue(repository.updatePatches.isEmpty)
        XCTAssertEqual(store.avatarData, Data([1]))
    }

    func testDroppingEditorDuringSuspendedUploadDeallocatesAndDeletesLateOrphan() async {
        let repository = SuspendedProfileUploadRepository(account: account)
        var store: MissCatProfileEditorStore? = MissCatProfileEditorStore(
            account: account,
            profile: makeUser(id: "me"),
            repositoryFactory: { _ in repository }
        )
        weak var releasedStore = store
        store?.setAvatarData(Data([1]))

        store?.save()
        await repository.waitUntilUploadStarted()
        store = nil

        XCTAssertNil(releasedStore)

        repository.resolveUpload(fileID: "late-orphan")
        await waitUntil { repository.deletedFileIDs == ["late-orphan"] }

        XCTAssertEqual(repository.deletedFileIDs, ["late-orphan"])
        XCTAssertTrue(repository.updatePatches.isEmpty)
        XCTAssertNil(releasedStore)
    }

    func testSupersedingInFlightUploadCleansOldFileAndSavesReplacement() async {
        let repository = ProfileRepositorySpy(account: account)
        repository.profileValue = makeUser(id: "me")
        repository.uploadIDs = ["superseded-upload", "replacement-upload"]
        repository.uploadDelayNanoseconds = 150_000_000
        let store = MissCatProfileEditorStore(account: account, profile: makeUser(id: "me"), repositoryFactory: { _ in repository })
        store.setAvatarData(Data([1]))

        store.save()
        await waitUntil { repository.uploadFilenames.count == 1 }
        store.setAvatarData(Data([2]))
        await waitUntil { repository.deletedFileIDs == ["superseded-upload"] }
        repository.uploadDelayNanoseconds = 0
        store.save()
        await waitUntil { store.phase == .loaded }

        XCTAssertEqual(repository.deletedFileIDs, ["superseded-upload"])
        XCTAssertEqual(repository.uploadData, [Data([1]), Data([2])])
        XCTAssertEqual(repository.updatePatches, [.init(avatarID: "replacement-upload")])
    }

    func testProfileUpdateFailureDeletesEveryUploadedFileAndKeepsDraftForRetry() async {
        let repository = ProfileRepositorySpy(account: account)
        repository.profileValue = makeUser(id: "me")
        repository.uploadIDs = ["failed-avatar", "failed-banner"]
        repository.updateError = StubError.failed
        let store = MissCatProfileEditorStore(account: account, profile: makeUser(id: "me"), repositoryFactory: { _ in repository })
        store.setAvatarData(Data([1]))
        store.setBannerData(Data([2]))

        store.save()
        await waitUntil { store.phase.isFailed }

        XCTAssertEqual(repository.deletedFileIDs, ["failed-avatar", "failed-banner"])
        XCTAssertEqual(store.avatarData, Data([1]))
        XCTAssertEqual(store.bannerData, Data([2]))
        XCTAssertEqual(
            repository.updatePatches,
            [.init(avatarID: "failed-avatar", bannerID: "failed-banner")]
        )
    }

    func testEditorFailureCanRetryWithoutLosingDraft() async {
        let repository = ProfileRepositorySpy(account: account)
        repository.profileValue = makeUser(id: "me", name: "After")
        repository.updateError = StubError.failed
        let store = MissCatProfileEditorStore(account: account, profile: makeUser(id: "me", name: "Before"), repositoryFactory: { _ in repository })
        store.name = "After"

        store.save()
        await waitUntil { store.phase.isFailed }
        XCTAssertEqual(store.name, "After")

        repository.updateError = nil
        store.retry()
        await waitUntil { store.phase == .loaded }
        XCTAssertEqual(repository.updatePatches.count, 2)
    }

    func testUserSearchPagesByOffsetAndDeduplicates() async {
        let repository = ProfileRepositorySpy(account: account)
        repository.userPages[nil] = .init(items: [makeUser(id: "u1")], nextCursor: "40")
        repository.userPages["40"] = .init(items: [makeUser(id: "u1"), makeUser(id: "u2")], nextCursor: nil)
        let store = MissCatUserListStore(account: account, kind: .search(query: "ali"), repositoryFactory: { _ in repository })

        store.load()
        await waitUntil { store.phase == .loaded }
        store.loadMoreIfNeeded(currentUserID: "u1")
        await waitUntil { store.users.count == 2 }

        XCTAssertEqual(store.users.map(\.id), ["u1", "u2"])
        XCTAssertEqual(repository.userCursors, [nil, "40"])
    }

    func testProfileVisualMetricsMatchLegacyStoryboardContract() {
        XCTAssertEqual(MissCatLegacyMetrics.referenceCanvas, CGSize(width: 414, height: 896))
        XCTAssertEqual(MissCatLegacyMetrics.profileHeaderHeight, 436.5)
        XCTAssertEqual(MissCatLegacyMetrics.profileBannerHeight, 153.5)
        XCTAssertEqual(MissCatLegacyMetrics.profileAvatarDiameter, 78)
        XCTAssertEqual(MissCatLegacyMetrics.profileBiographyTop, 181)
        XCTAssertEqual(MissCatLegacyMetrics.profileCountsWidth, 226)
        XCTAssertEqual(MissCatLegacyMetrics.profileActionWidth, 105)
        XCTAssertEqual(MissCatLegacyMetrics.profileTabsHeight, 46)
    }
}

/// The `@MainActor` profile tests serialize all access to this mutable spy.
private final class ProfileRepositorySpy: MissCatProfileRepository, @unchecked Sendable {
    let account: MissCatProfileAccount
    var profileValue: MissCatProfileUser
    var profileDelayNanoseconds: UInt64 = 0
    var profileCancellationCount = 0
    var profileCalls: [String] = []
    var relationshipValue = false
    var relationshipCalls: [String] = []
    var notePages: [String?: MissCatProfilePage<MissCatProfileNote>] = [:]
    var noteCursors: [String?] = []
    var userPages: [String?: MissCatProfilePage<MissCatProfileUser>] = [:]
    var userCursors: [String?] = []
    var followCalls: [Bool] = []
    var followDelayNanoseconds: UInt64 = 0
    var followError: Error?
    var uploadFilenames: [String] = []
    var uploadData: [Data] = []
    var uploadIDs: [String] = ["uploaded-file"]
    var uploadDelayNanoseconds: UInt64 = 0
    var uploadError: Error?
    var deletedFileIDs: [String] = []
    var updatePatches: [MissCatProfileUpdatePatch] = []
    var updateError: Error?

    init(account: MissCatProfileAccount) {
        self.account = account
        profileValue = makeUser(id: account.userID)
    }

    func profile(userID: String) async throws -> MissCatProfileUser {
        profileCalls.append(userID)
        if profileDelayNanoseconds > 0 {
            do {
                try await Task.sleep(nanoseconds: profileDelayNanoseconds)
            } catch is CancellationError {
                profileCancellationCount += 1
                throw CancellationError()
            }
        }
        return profileValue
    }

    func relationship(userID: String) async throws -> Bool {
        relationshipCalls.append(userID)
        return relationshipValue
    }

    func notes(userID: String, tab: MissCatProfileTimelineTab, cursor: String?, limit: Int) async throws -> MissCatProfilePage<MissCatProfileNote> {
        noteCursors.append(cursor)
        return notePages[cursor] ?? .init(items: [], nextCursor: nil)
    }

    func users(kind: MissCatUserListKind, cursor: String?, limit: Int) async throws -> MissCatProfilePage<MissCatProfileUser> {
        userCursors.append(cursor)
        return userPages[cursor] ?? .init(items: [], nextCursor: nil)
    }

    func setFollowing(_ following: Bool, userID: String) async throws {
        followCalls.append(following)
        if followDelayNanoseconds > 0 { try await Task.sleep(nanoseconds: followDelayNanoseconds) }
        if let followError { throw followError }
    }

    func uploadProfileImage(
        data: Data,
        filename: String,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> String {
        uploadFilenames.append(filename)
        uploadData.append(data)
        progress(0.5)
        if uploadDelayNanoseconds > 0 { try await Task.sleep(nanoseconds: uploadDelayNanoseconds) }
        if let uploadError { throw uploadError }
        progress(1)
        return uploadIDs.isEmpty ? "uploaded-file" : uploadIDs.removeFirst()
    }

    func deleteProfileImage(fileID: String) async throws {
        deletedFileIDs.append(fileID)
    }

    func updateProfile(patch: MissCatProfileUpdatePatch) async throws -> MissCatProfileUser {
        updatePatches.append(patch)
        if let updateError { throw updateError }
        return profileValue
    }
}

/// The owning `@MainActor` test serializes this deliberately non-cooperative repository.
private final class SuspendedProfileUploadRepository: MissCatProfileRepository, @unchecked Sendable {
    let account: MissCatProfileAccount
    private var uploadContinuation: CheckedContinuation<String, Never>?
    private var uploadWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var deletedFileIDs: [String] = []
    private(set) var updatePatches: [MissCatProfileUpdatePatch] = []

    init(account: MissCatProfileAccount) {
        self.account = account
    }

    func profile(userID: String) async throws -> MissCatProfileUser { makeUser(id: userID) }
    func relationship(userID: String) async throws -> Bool { false }
    func notes(
        userID: String,
        tab: MissCatProfileTimelineTab,
        cursor: String?,
        limit: Int
    ) async throws -> MissCatProfilePage<MissCatProfileNote> {
        .init(items: [], nextCursor: nil)
    }
    func users(
        kind: MissCatUserListKind,
        cursor: String?,
        limit: Int
    ) async throws -> MissCatProfilePage<MissCatProfileUser> {
        .init(items: [], nextCursor: nil)
    }
    func setFollowing(_ following: Bool, userID: String) async throws {}

    func uploadProfileImage(
        data: Data,
        filename: String,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> String {
        uploadWaiters.forEach { $0.resume() }
        uploadWaiters.removeAll()
        return await withCheckedContinuation { uploadContinuation = $0 }
    }

    func waitUntilUploadStarted() async {
        if uploadContinuation != nil { return }
        await withCheckedContinuation { uploadWaiters.append($0) }
    }

    func resolveUpload(fileID: String) {
        uploadContinuation?.resume(returning: fileID)
        uploadContinuation = nil
    }

    func deleteProfileImage(fileID: String) async throws {
        deletedFileIDs.append(fileID)
    }

    func updateProfile(patch: MissCatProfileUpdatePatch) async throws -> MissCatProfileUser {
        updatePatches.append(patch)
        return makeUser(id: account.userID)
    }
}

private final class ProfileURLProtocolStub: URLProtocol {
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
            let (response, data) = try XCTUnwrap(Self.handler)(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private enum StubError: Error { case failed }

@MainActor
private func waitUntil(
    timeoutNanoseconds: UInt64 = 2_000_000_000,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ condition: @escaping () -> Bool
) async {
    let interval: UInt64 = 10_000_000
    var elapsed: UInt64 = 0
    while elapsed < timeoutNanoseconds {
        if condition() { return }
        try? await Task.sleep(nanoseconds: interval)
        elapsed += interval
    }
    XCTFail("Condition was not satisfied before timeout", file: file, line: line)
}

private func makeUser(
    id: String,
    name: String = "Alice",
    description: String = "Hello",
    isCat: Bool = false
) -> MissCatProfileUser {
    .init(id: id, name: name, username: id, description: description, isCat: isCat)
}

private func makeNote(id: String) -> MissCatProfileNote {
    .init(id: id, createdAt: "2026-08-07T00:00:00.000Z", text: id, user: makeUser(id: "author"))
}

private extension Data {
    var jsonObject: [String: Any] {
        get throws {
            try XCTUnwrap(JSONSerialization.jsonObject(with: self) as? [String: Any])
        }
    }
}

private extension URLRequest {
    var profileBodyData: Data? {
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

private extension MissCatLoadPhase {
    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}
