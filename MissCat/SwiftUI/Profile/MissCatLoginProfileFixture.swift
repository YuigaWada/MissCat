#if DEBUG
import Foundation
import SwiftUI

/// Runs the production SwiftUI application root and its typed Discovery and
/// Profile routes without a saved account or a live network. Deterministic
/// repositories are injected only at those repository boundaries; this stays
/// deliberately separate from the direct feature fixture below.
@MainActor
enum MissCatProfileOrdinaryRouteConfiguration {
    static let launchArgument = "--login-profile-real-ordinary-route"
    static let query = "fixture"

    static var isEnabled: Bool {
        CommandLine.arguments.contains(launchArgument)
    }

    static let account = MissCatProfileAccount(
        userID: "fixture-self",
        instance: "ordinary-route.invalid",
        token: "ordinary-route-token-not-a-secret"
    )

    static let owner = SecureUser(
        userId: account.userID,
        username: "wada",
        instance: account.instance,
        apiKey: account.token
    )

    static let repository = MissCatProfileFixtureRepository(
        account: account,
        failUnfollowOnce: false,
        failEditOnce: false
    )

    static let discoveryRepository = MissCatProfileOrdinaryDiscoveryRepository(
        owner: owner,
        profileRepository: repository
    )

    static let actionState = MissCatProfileOrdinaryActionState()

    static func record(_ action: String) {
        actionState.record(action)
    }
}

@MainActor
final class MissCatProfileOrdinaryActionState: ObservableObject {
    @Published private(set) var lastAction = "none"

    func record(_ action: String) {
        lastAction = action
    }
}

struct MissCatProfileOrdinaryAccessibilityMarker: View {
    @ObservedObject var state: MissCatProfileOrdinaryActionState

    var body: some View {
        VStack(spacing: 0) {
            marker(
                text: "ordinary profile home",
                identifier: "profile.realOrdinary.home",
                value: "ready"
            )
            marker(
                text: "ordinary profile action",
                identifier: "profile.realOrdinary.lastAction",
                value: state.lastAction
            )
        }
    }

    private func marker(text: String, identifier: String, value: String) -> some View {
        Text(text)
            .font(.system(size: 1))
            .frame(width: 2, height: 2)
            .opacity(0.01)
            .accessibilityLabel(identifier)
            .accessibilityValue(value)
            .accessibilityIdentifier(identifier)
    }
}

/// DEBUG-only data seam for the production SwiftUI Discovery composition used
/// by the durable Home -> Search -> Profile route test.
final class MissCatProfileOrdinaryDiscoveryRepository:
    MissCatDiscoveryRepository,
    MissCatNoteContextRepository
{
    let accountIdentifier: String
    let currentServerUserID: String

    private let profileRepository: MissCatProfileRepository

    init(owner: SecureUser, profileRepository: MissCatProfileRepository) {
        accountIdentifier = MissCatAccountIdentity.storageKey(
            instance: owner.instance,
            userId: owner.userId
        )
        currentServerUserID = owner.userId
        self.profileRepository = profileRepository
    }

    func fetchTrends() async throws -> [MissCatTrend] {
        [.init(tag: "Profile", chart: [1, 2, 3], usersCount: 3)]
    }

    func searchNotes(
        query: String,
        cursor: String?,
        limit: Int
    ) async throws -> MissCatDiscoveryPage<MissCatNote> {
        .init(items: [], nextCursor: nil)
    }

    func searchUsers(
        query: String,
        offset: Int,
        limit: Int
    ) async throws -> MissCatDiscoveryPage<MissCatProfileUser> {
        guard offset == 0 else { return .init(items: [], nextCursor: nil) }
        let page = try await profileRepository.users(
            kind: .search(query: query),
            cursor: nil,
            limit: limit
        )
        return .init(items: page.items, nextCursor: nil)
    }

    func fetchPage(
        source: MissCatFeedSource,
        cursor: String?,
        limit: Int
    ) async throws -> MissCatFeedPage {
        .init(notes: [], hasMore: false)
    }

    func fetchThread(noteID: String, replyLimit: Int) async throws -> MissCatNoteThread {
        throw MissCatFeedRepositoryError.unsupportedSource
    }

    func realtimeEvents(
        source: MissCatFeedSource,
        capturing noteIDs: [String]
    ) -> AsyncStream<MissCatRealtimeEvent> {
        AsyncStream { $0.finish() }
    }

    func perform(_ action: MissCatFeedAction) async throws {}

    func notePermalink(noteID: String) -> URL? { nil }

    func fetchURLPreview(for url: URL) async throws -> MissCatURLPreview {
        throw MissCatURLPreviewError.unsupportedURL
    }
}

enum MissCatLoginProfileFixtureRoute: Equatable {
    case authentication(failPreparationOnce: Bool, failBrowserOnce: Bool)
    case profile(
        failUnfollowOnce: Bool,
        failEditOnce: Bool,
        startsAtSelfProfile: Bool,
        usesOuterShell: Bool
    )

    static func parse(_ arguments: [String] = CommandLine.arguments) -> Self? {
        guard arguments.contains("--login-profile-fixture") else { return nil }
        if arguments.contains("--login-profile-auth") {
            return .authentication(
                failPreparationOnce: arguments.contains("--login-profile-auth-prepare-error"),
                failBrowserOnce: arguments.contains("--login-profile-auth-browser-error")
            )
        }
        if arguments.contains("--login-profile-profile") {
            return .profile(
                failUnfollowOnce: arguments.contains("--login-profile-unfollow-error"),
                failEditOnce: arguments.contains("--login-profile-edit-error"),
                startsAtSelfProfile: arguments.contains("--login-profile-root-self"),
                usesOuterShell: arguments.contains("--login-profile-ordinary-shell")
            )
        }
        return nil
    }
}

struct MissCatLoginProfileFixtureRoot: View {
    let route: MissCatLoginProfileFixtureRoute

    var body: some View {
        switch route {
        case let .authentication(failPreparationOnce, failBrowserOnce):
            MissCatAuthenticationFixtureHarness(
                failPreparationOnce: failPreparationOnce,
                failBrowserOnce: failBrowserOnce
            )
        case let .profile(failUnfollowOnce, failEditOnce, startsAtSelfProfile, usesOuterShell):
            MissCatProfileFixtureHarness(
                failUnfollowOnce: failUnfollowOnce,
                failEditOnce: failEditOnce,
                startsAtSelfProfile: startsAtSelfProfile,
                usesOuterShell: usesOuterShell
            )
        }
    }
}

@MainActor
private final class MissCatAuthenticationFixtureController: ObservableObject {
    enum FixtureError: LocalizedError {
        case invalidInstance
        case preparation
        case browser

        var errorDescription: String? {
            switch self {
            case .invalidInstance: return "インスタンスURLが正しくありません"
            case .preparation: return "認証の準備に失敗しました"
            case .browser: return "認証ページを読み込めませんでした"
            }
        }
    }

    @Published var generation = 0
    @Published var errorMessage: String?
    @Published var completed = false
    @Published private(set) var callbackCount = 0

    private var shouldFailPreparation: Bool
    private var shouldFailBrowser: Bool

    init(failPreparationOnce: Bool, failBrowserOnce: Bool) {
        shouldFailPreparation = failPreparationOnce
        shouldFailBrowser = failBrowserOnce
    }

    func makeAuthorizationRequest(
        _ intent: MissCatAuthenticationIntent,
        instance: String
    ) async throws -> URLRequest {
        guard (try? MissCatInstance.normalize(instance)) != nil else {
            throw FixtureError.invalidInstance
        }
        if shouldFailPreparation {
            shouldFailPreparation = false
            throw FixtureError.preparation
        }
        let path = intent == .signUp ? "/signup" : "/miauth/fixture-session"
        return URLRequest(url: URL(string: "https://fixture.invalid\(path)")!)
    }

    func makeLoginRequestAfterSignUp(instance: String) async throws -> URLRequest {
        try await makeAuthorizationRequest(.logIn, instance: instance)
    }

    func callbackMatches(_ url: URL) -> Bool {
        url.scheme == "misscat"
            && url.host == "auth"
            && url.path.isEmpty
            && URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
                == [URLQueryItem(name: "session", value: "fixture-session")]
    }

    func runAuthenticationSession(
        url: URL,
        callbackScheme: String,
        sessionKind: MissCatAuthenticationBrowserSessionKind
    ) async throws -> URL {
        precondition(url.scheme == "https")
        precondition(callbackScheme == MissCatAuthenticationBrowserPolicy.callbackScheme)
        _ = sessionKind
        if shouldFailBrowser {
            shouldFailBrowser = false
            throw FixtureError.browser
        }
        return URL(string: "misscat://auth?session=fixture-session")!
    }

    func openRegistration(_ url: URL) {
        precondition(url == URL(string: "https://fixture.invalid/signup"))
    }

    func complete(_ url: URL) {
        guard callbackMatches(url), !completed else { return }
        callbackCount += 1
        completed = true
    }

    func fail(_ error: Error) {
        let nsError = error as NSError
        guard nsError.code != NSURLErrorCancelled else { return }
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    func retry() {
        errorMessage = nil
        generation += 1
    }

}

private struct MissCatAuthenticationFixtureHarness: View {
    @StateObject private var controller: MissCatAuthenticationFixtureController

    init(failPreparationOnce: Bool, failBrowserOnce: Bool) {
        _controller = StateObject(
            wrappedValue: MissCatAuthenticationFixtureController(
                failPreparationOnce: failPreparationOnce,
                failBrowserOnce: failBrowserOnce
            )
        )
    }

    var body: some View {
        Group {
            if controller.completed {
                VStack(spacing: 14) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.green)
                    Text("認証が完了しました").font(.headline)
                    Text("fixture callback count: \(controller.callbackCount)")
                        .font(.caption)
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("authentication.fixture.completed")
            } else {
                MissCatAuthenticationFlowView(
                    initialInstance: "misskey.io",
                    makeAuthorizationRequest: controller.makeAuthorizationRequest,
                    makeLoginRequestAfterSignUp: controller.makeLoginRequestAfterSignUp,
                    callbackMatches: controller.callbackMatches,
                    onCallback: controller.complete,
                    authenticationSessionRunner: controller.runAuthenticationSession,
                    registrationURLHandler: controller.openRegistration,
                    onFailure: controller.fail
                )
                .id(controller.generation)
            }
        }
        .alert(
            "エラー",
            isPresented: Binding(
                get: { controller.errorMessage != nil },
                set: { if !$0 { controller.errorMessage = nil } }
            )
        ) {
            Button("再試行", action: controller.retry)
                .accessibilityIdentifier("authentication.fixture.retry")
            Button("閉じる", role: .cancel) { controller.errorMessage = nil }
                .accessibilityIdentifier("authentication.fixture.close-error")
        } message: {
            Text(controller.errorMessage ?? "")
        }
        .preferredColorScheme(.light)
    }
}

final class MissCatProfileFixtureRepository: MissCatProfileRepository {
    enum FixtureError: LocalizedError {
        case follow
        case update

        var errorDescription: String? {
            switch self {
            case .follow: return "フォロー状態を更新できませんでした"
            case .update: return "プロフィールを保存できませんでした"
            }
        }
    }

    let account: MissCatProfileAccount

    private let lock = NSLock()
    private var profiles: [String: MissCatProfileUser]
    private var following: Set<String> = []
    private var shouldFailUnfollow: Bool
    private var shouldFailUpdate: Bool

    init(account: MissCatProfileAccount, failUnfollowOnce: Bool, failEditOnce: Bool) {
        self.account = account
        shouldFailUnfollow = failUnfollowOnce
        shouldFailUpdate = failEditOnce
        let avatar = URL(string: "misscat-fixture://avatar")
        let banner = URL(string: "misscat-fixture://banner")
        profiles = [
            "fixture-self": .init(
                id: "fixture-self",
                name: "だわくん",
                username: "wada",
                description: "Swift, Python, C++, C#, Vue\niOS向けMisskeyのクライアント作ってるよ、完成しつつあるよ\nhttps://github.com/YuigaWada",
                avatarURL: avatar,
                bannerURL: banner,
                isCat: true,
                followersCount: 103,
                followingCount: 84,
                notesCount: 1_494
            ),
            "fixture-target": .init(
                id: "fixture-target",
                name: "しゅいろ",
                username: "syuilo",
                host: "fixture.invalid",
                description: "分散SNSを作っています。 #Misskey",
                avatarURL: avatar,
                bannerURL: banner,
                followersCount: 24_100,
                followingCount: 321,
                notesCount: 8_420
            ),
            "fixture-friend": .init(
                id: "fixture-friend",
                name: "Alice",
                username: "alice",
                host: "fixture.invalid",
                description: "Fixture follower",
                avatarURL: avatar,
                bannerURL: banner,
                isCat: true,
                followersCount: 42,
                followingCount: 21,
                notesCount: 99
            )
        ]
    }

    func profile(userID: String) async throws -> MissCatProfileUser {
        try lock.withLock {
            guard let profile = profiles[userID] else { throw MissCatProfileAPIError.http(404, "User not found") }
            return profile
        }
    }

    func relationship(userID: String) async throws -> Bool {
        lock.withLock { following.contains(userID) }
    }

    func notes(
        userID: String,
        tab: MissCatProfileTimelineTab,
        cursor: String?,
        limit: Int
    ) async throws -> MissCatProfilePage<MissCatProfileNote> {
        guard cursor == nil else { return .init(items: [], nextCursor: nil) }
        let author = try await profile(userID: userID)
        let all = [
            MissCatProfileNote(
                id: "fixture-note-1",
                createdAt: "2026-08-07T00:00:00.000Z",
                text: "アプリから通知を送るってどうやることだ",
                user: author,
                repliesCount: 1,
                renoteCount: 2,
                reactions: ["❤": 2]
            ),
            MissCatProfileNote(
                id: "fixture-note-2",
                createdAt: "2026-08-06T23:58:00.000Z",
                text: "SwiftUIプロフィール fixture",
                user: author,
                repliesCount: 0,
                renoteCount: 1,
                reactions: ["👍": 3]
            )
        ]
        return .init(items: tab == .media ? [] : all, nextCursor: nil)
    }

    func users(
        kind: MissCatUserListKind,
        cursor: String?,
        limit: Int
    ) async throws -> MissCatProfilePage<MissCatProfileUser> {
        guard cursor == nil else { return .init(items: [], nextCursor: nil) }
        let values: [MissCatProfileUser] = lock.withLock {
            switch kind {
            case .search:
                return ["fixture-target", "fixture-self", "fixture-friend"].compactMap { profiles[$0] }
            case .followers:
                return ["fixture-friend", "fixture-self"].compactMap { profiles[$0] }
            case .following:
                return ["fixture-self", "fixture-friend"].compactMap { profiles[$0] }
            }
        }
        return .init(items: values, nextCursor: nil)
    }

    func setFollowing(_ value: Bool, userID: String) async throws {
        try lock.withLock {
            if !value, shouldFailUnfollow {
                shouldFailUnfollow = false
                throw FixtureError.follow
            }
            if value { following.insert(userID) } else { following.remove(userID) }
        }
    }

    func uploadProfileImage(
        data: Data,
        filename: String,
        progress: @escaping (Double) -> Void
    ) async throws -> String {
        progress(0.5)
        progress(1)
        return "fixture-upload-\(filename)"
    }

    func deleteProfileImage(fileID: String) async throws {}

    func updateProfile(patch: MissCatProfileUpdatePatch) async throws -> MissCatProfileUser {
        try lock.withLock {
            if shouldFailUpdate {
                shouldFailUpdate = false
                throw FixtureError.update
            }
            guard var profile = profiles[account.userID] else {
                throw MissCatProfileAPIError.http(404, "User not found")
            }
            if let name = patch.name { profile.name = name }
            if let description = patch.description { profile.description = description }
            if let isCat = patch.isCat { profile.isCat = isCat }
            switch patch.avatarImage {
            case .unchanged: break
            case .replace: profile.avatarURL = URL(string: "misscat-fixture://avatar/replacement")
            case .remove: profile.avatarURL = nil
            }
            switch patch.bannerImage {
            case .unchanged: break
            case .replace: profile.bannerURL = URL(string: "misscat-fixture://banner/replacement")
            case .remove: profile.bannerURL = nil
            }
            profiles[account.userID] = profile
            return profile
        }
    }
}

private struct MissCatProfileFixtureHarness: View {
    @StateObject private var actionRecorder = MissCatProfileFixtureActionRecorder()

    private let account = MissCatProfileAccount(
        userID: "fixture-self",
        instance: "fixture.invalid",
        token: "fixture-token-not-a-secret"
    )
    private let repository: MissCatProfileFixtureRepository
    private let startsAtSelfProfile: Bool
    private let usesOuterShell: Bool

    init(
        failUnfollowOnce: Bool,
        failEditOnce: Bool,
        startsAtSelfProfile: Bool,
        usesOuterShell: Bool
    ) {
        let account = MissCatProfileAccount(
            userID: "fixture-self",
            instance: "fixture.invalid",
            token: "fixture-token-not-a-secret"
        )
        repository = MissCatProfileFixtureRepository(
            account: account,
            failUnfollowOnce: failUnfollowOnce,
            failEditOnce: failEditOnce
        )
        self.startsAtSelfProfile = startsAtSelfProfile
        self.usesOuterShell = usesOuterShell
    }

    var body: some View {
        Group {
            if usesOuterShell {
                VStack(spacing: 0) {
                    profileFamily(shellOwnership: .outerShell, actions: actionRecorder.actions)

                    MissCatBottomBar(
                        selectedSection: Binding(
                            get: { actionRecorder.selectedSection },
                            set: { actionRecorder.selectRoot($0) }
                        ),
                        palette: .legacyLight,
                        onCompose: actionRecorder.compose,
                        onReselect: actionRecorder.selectRoot
                    )
                }
                .overlay(alignment: .topLeading) {
                    MissCatProfileFixtureValueMarker(
                        identifier: "profile.ordinaryShell.lastAction",
                        value: actionRecorder.lastAction
                    )
                }
            } else {
                profileFamily(shellOwnership: .profileFamily, actions: .init())
            }
        }
        .preferredColorScheme(.light)
    }

    private func profileFamily(
        shellOwnership: MissCatProfileShellOwnership,
        actions: MissCatProfileFamilyActions
    ) -> some View {
        MissCatProfileFamilyView(
            root: startsAtSelfProfile ? .profile(userID: account.userID) : .searchResults(query: "fixture"),
            account: account,
            palette: .legacyLight,
            shellOwnership: shellOwnership,
            repositoryFactory: { _ in repository },
            actions: actions
        )
    }
}

@MainActor
private final class MissCatProfileFixtureActionRecorder: ObservableObject {
    @Published var selectedSection: MissCatRootSection = .profile
    @Published private(set) var lastAction = "none"

    var actions: MissCatProfileFamilyActions {
        MissCatProfileFamilyActions(
            onExit: { [weak self] in self?.record("exit") },
            onOpenURL: { [weak self] _ in self?.record("url") },
            onOpenImage: { [weak self] _ in self?.record("image") },
            onOpenSettings: { [weak self] in self?.record("settings") },
            onSelectRoot: { [weak self] in self?.selectRoot($0) },
            onCompose: { [weak self] in self?.compose() }
        )
    }

    func selectRoot(_ section: MissCatRootSection) {
        selectedSection = section
        record("root.\(section.rawValue)")
    }

    func compose() {
        record("compose")
    }

    private func record(_ action: String) {
        lastAction = action
    }
}

private struct MissCatProfileFixtureValueMarker: View {
    let identifier: String
    let value: String

    var body: some View {
        Text("fixture action")
            .font(.system(size: 1))
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .accessibilityLabel(identifier)
            .accessibilityValue(value)
            .accessibilityIdentifier(identifier)
    }
}

private extension NSLock {
    func withLock<Result>(_ operation: () throws -> Result) rethrows -> Result {
        lock()
        defer { unlock() }
        return try operation()
    }
}
#endif
