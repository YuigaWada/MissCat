#if DEBUG
import Foundation
import SwiftUI

enum MissCatLoginProfileFixtureRoute: Equatable {
    case authentication(failPreparationOnce: Bool, failBrowserOnce: Bool)
    case profile(failUnfollowOnce: Bool, failEditOnce: Bool)

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
                failEditOnce: arguments.contains("--login-profile-edit-error")
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
        case let .profile(failUnfollowOnce, failEditOnce):
            MissCatProfileFixtureHarness(
                failUnfollowOnce: failUnfollowOnce,
                failEditOnce: failEditOnce
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
        if shouldFailBrowser {
            shouldFailBrowser = false
            return URLRequest(
                url: URL(fileURLWithPath: "/misscat-fixture/missing-authentication.html")
            )
        }
        return URLRequest(url: Self.authorizationDocumentURL(intent: intent))
    }

    func makeLoginRequestAfterSignUp(instance: String) async throws -> URLRequest {
        try await makeAuthorizationRequest(.logIn, instance: instance)
    }

    func callbackMatches(_ url: URL) -> Bool {
        url.scheme == "misscat-fixture" && url.host == "authentication" && url.path == "/complete"
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

    private static func authorizationDocumentURL(intent: MissCatAuthenticationIntent) -> URL {
        let title = intent == .logIn ? "ログインを許可" : "新規登録を続ける"
        let html = """
        <!doctype html><html lang='ja'><head>
        <meta name='viewport' content='width=device-width,initial-scale=1'>
        <style>body{font-family:-apple-system;background:#fff;color:#222;margin:0;padding:32px}main{max-width:560px;margin:auto}.card{border:1px solid #ddd;border-radius:14px;padding:24px}a{display:block;background:#86b900;color:white;text-align:center;text-decoration:none;border-radius:24px;padding:13px;margin-top:28px;font-weight:600}</style>
        </head><body><main><div class='card'><h1>\(title)</h1><p>fixture.invalid が MissCat へのアクセスを要求しています。</p><ul><li>アカウント情報を見る</li><li>投稿とフォローを操作する</li></ul><a href='misscat-fixture://authentication/complete'>認証を完了</a></div></main></body></html>
        """
        let encoded = html.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        return URL(string: "data:text/html;charset=utf-8,\(encoded)")!
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
    private let account = MissCatProfileAccount(
        userID: "fixture-self",
        instance: "fixture.invalid",
        token: "fixture-token-not-a-secret"
    )
    private let repository: MissCatProfileFixtureRepository

    init(failUnfollowOnce: Bool, failEditOnce: Bool) {
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
    }

    var body: some View {
        MissCatProfileFamilyView(
            root: .searchResults(query: "fixture"),
            account: account,
            palette: .legacyLight,
            repositoryFactory: { _ in repository }
        )
        .preferredColorScheme(.light)
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
