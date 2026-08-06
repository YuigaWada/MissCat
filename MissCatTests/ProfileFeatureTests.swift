@testable import MissCat
import Foundation
import XCTest

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
        XCTAssertEqual(bodies[0]["includeReplies"] as? Bool, false)
        XCTAssertEqual(bodies[0]["withFiles"] as? Bool, false)
        XCTAssertEqual(bodies[1]["includeReplies"] as? Bool, true)
        XCTAssertEqual(bodies[1]["withFiles"] as? Bool, false)
        XCTAssertEqual(bodies[2]["includeReplies"] as? Bool, false)
        XCTAssertEqual(bodies[2]["withFiles"] as? Bool, true)
        XCTAssertTrue(bodies.allSatisfy { $0["i"] as? String == "account-token" && $0["untilId"] as? String == "older" })
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

private final class ProfileRepositorySpy: MissCatProfileRepository {
    let account: MissCatProfileAccount
    var profileValue: MissCatProfileUser
    var profileDelayNanoseconds: UInt64 = 0
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
    var uploadError: Error?
    var updatePatches: [MissCatProfileUpdatePatch] = []
    var updateError: Error?

    init(account: MissCatProfileAccount) {
        self.account = account
        profileValue = makeUser(id: account.userID)
    }

    func profile(userID: String) async throws -> MissCatProfileUser {
        profileCalls.append(userID)
        if profileDelayNanoseconds > 0 { try await Task.sleep(nanoseconds: profileDelayNanoseconds) }
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

    func uploadProfileImage(data: Data, filename: String, progress: @escaping (Double) -> Void) async throws -> String {
        uploadFilenames.append(filename)
        progress(0.5)
        if let uploadError { throw uploadError }
        progress(1)
        return "uploaded-file"
    }

    func updateProfile(patch: MissCatProfileUpdatePatch) async throws -> MissCatProfileUser {
        updatePatches.append(patch)
        if let updateError { throw updateError }
        return profileValue
    }
}

private final class ProfileURLProtocolStub: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

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
