import Foundation
import MisskeyKit

enum MissCatAuthenticationCallbackMatcher {
    static func matches(
        _ candidate: URL,
        expectedURLString: String,
        expectedSessionID: UUID
    ) -> Bool {
        guard let expected = URLComponents(string: expectedURLString),
              let actual = URLComponents(url: candidate, resolvingAgainstBaseURL: false),
              let queryItems = actual.queryItems,
              queryItems.count == 1,
              queryItems[0].name == "session",
              queryItems[0].value == expectedSessionID.uuidString.lowercased(),
              actual.user == nil,
              actual.password == nil,
              actual.fragment == nil,
              actual.percentEncodedHost?.contains("%") != true,
              actual.percentEncodedQuery?.contains("%") != true
        else { return false }

        return normalizedScheme(actual) == normalizedScheme(expected)
            && normalizedHost(actual) == normalizedHost(expected)
            && normalizedPort(actual) == normalizedPort(expected)
            && normalizedPath(actual) == normalizedPath(expected)
    }

    private static func normalizedScheme(_ components: URLComponents) -> String? {
        components.scheme?.lowercased()
    }

    private static func normalizedHost(_ components: URLComponents) -> String? {
        guard let host = components.host?.lowercased(),
              !host.isEmpty,
              !host.hasSuffix(".")
        else { return nil }
        return host
    }

    private static func normalizedPort(_ components: URLComponents) -> Int? {
        if let port = components.port {
            return port
        }

        switch normalizedScheme(components) {
        case "https":
            return 443
        case "http":
            return 80
        default:
            return nil
        }
    }

    private static func normalizedPath(_ components: URLComponents) -> String {
        components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
    }
}

protocol MissCatAuthenticationAccountStoring: AnyObject {
    func saveUser(_ user: SecureUser) -> Bool
    func changeCurrentUser(userId id: String)
    func getUser(userId: String) -> SecureUser?
}

extension Cache.UserDefaults: MissCatAuthenticationAccountStoring {}

@MainActor
final class MissCatAuthenticationService {
    static let callbackURLString = "https://misscat.dev"
    static let appPermissions = [
        "read:account",
        "write:account",
        "read:blocks",
        "write:blocks",
        "read:drive",
        "write:drive",
        "read:favorites",
        "write:favorites",
        "read:following",
        "write:following",
        "read:messaging",
        "write:messaging",
        "read:mutes",
        "write:mutes",
        "write:notes",
        "read:notifications",
        "write:notifications",
        "read:reactions",
        "write:reactions",
        "write:votes",
        "read:pages",
        "write:pages",
        "write:page-likes",
        "read:page-likes",
        "read:user-groups",
        "write:user-groups"
    ]

    private enum PendingState: Equatable {
        case awaitingCallback
        case checking
    }

    private struct PendingSession {
        let instance: MissCatInstance
        let id: UUID
        var state: PendingState
    }

    private let misskey: MisskeyKit
    private let transport: MissCatMiAuthTransport
    private let uuidGenerator: () -> UUID
    private let accountStore: MissCatAuthenticationAccountStoring
    private let performsPostLoginActions: Bool

    private var pendingSignUpInstance: MissCatInstance?
    private var pendingSession: PendingSession?

    init(
        misskey: MisskeyKit = .shared,
        transport: MissCatMiAuthTransport = MissCatURLSessionMiAuthTransport(),
        uuidGenerator: @escaping () -> UUID = UUID.init,
        accountStore: MissCatAuthenticationAccountStoring = Cache.UserDefaults.shared,
        performsPostLoginActions: Bool = true
    ) {
        self.misskey = misskey
        self.transport = transport
        self.uuidGenerator = uuidGenerator
        self.accountStore = accountStore
        self.performsPostLoginActions = performsPostLoginActions
    }

    func makeAuthorizationRequest(
        intent: MissCatAuthenticationIntent,
        instance: String
    ) async throws -> URLRequest {
        let normalizedInstance = try MissCatInstance.normalize(instance)
        invalidatePendingAuthentication()
        misskey.auth.setAPIKey("")
        misskey.changeInstance(instance: normalizedInstance.identifier)

        switch intent {
        case .signUp:
            pendingSignUpInstance = normalizedInstance
            return URLRequest(url: normalizedInstance.origin)
        case .logIn:
            return try makeFreshLoginRequest(instance: normalizedInstance)
        }
    }

    func makeLoginRequestAfterSignUp(instance: String) async throws -> URLRequest {
        let normalizedInstance = try MissCatInstance.normalize(instance)
        guard pendingSignUpInstance == normalizedInstance else {
            throw AuthenticationError.expiredSession
        }
        return try makeFreshLoginRequest(instance: normalizedInstance)
    }

    func callbackMatches(_ url: URL) -> Bool {
        guard let pendingSession,
              pendingSession.state == .awaitingCallback
        else { return false }

        return MissCatAuthenticationCallbackMatcher.matches(
            url,
            expectedURLString: Self.callbackURLString,
            expectedSessionID: pendingSession.id
        )
    }

    func completeAuthentication(callbackURL: URL) async throws -> SecureUser {
        guard var session = pendingSession,
              session.state == .awaitingCallback,
              MissCatAuthenticationCallbackMatcher.matches(
                  callbackURL,
                  expectedURLString: Self.callbackURLString,
                  expectedSessionID: session.id
              )
        else {
            throw AuthenticationError.invalidCallback
        }

        // A MiAuth session is one-shot. Mark it before the first suspension so
        // concurrent or replayed callbacks can never issue a second check.
        session.state = .checking
        pendingSession = session
        defer { pendingSession = nil }

        let request = try MissCatMiAuthRequestBuilder.checkRequest(
            instance: session.instance,
            sessionID: session.id
        )
        let httpResponse: MissCatMiAuthHTTPResponse
        do {
            httpResponse = try await transport.send(request)
        } catch {
            throw AuthenticationError.requestFailed
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw AuthenticationError.serverRejected(statusCode: httpResponse.statusCode)
        }

        let response: MissCatMiAuthCheckResponse
        do {
            response = try JSONDecoder().decode(
                MissCatMiAuthCheckResponse.self,
                from: httpResponse.data
            )
        } catch {
            throw AuthenticationError.invalidServerResponse
        }

        guard response.ok else {
            throw AuthenticationError.authorizationDenied
        }
        guard let apiKey = response.token, !apiKey.isEmpty else {
            throw AuthenticationError.missingAccessToken
        }
        guard let user = response.user,
              !user.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !user.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw AuthenticationError.missingUser
        }

        let secureUser = SecureUser(
            userId: user.id,
            username: user.username,
            instance: session.instance.identifier,
            apiKey: apiKey
        )
        guard accountStore.saveUser(secureUser) else {
            throw AuthenticationError.couldNotPersistAccount
        }

        accountStore.changeCurrentUser(userId: user.id)
        guard let persistedUser = accountStore.getUser(userId: user.id),
              persistedUser.userId == user.id,
              persistedUser.instance == session.instance.identifier,
              persistedUser.apiKey == apiKey
        else {
            throw AuthenticationError.couldNotPersistAccount
        }

        misskey.changeInstance(instance: session.instance.identifier)
        misskey.auth.setAPIKey(apiKey)

        if performsPostLoginActions {
            EmojiHandler.setHandler(owner: persistedUser)
            registerPushNotifications(for: persistedUser)
            Theme.shared.reset()
            Theme.shared.set()
        }

        return persistedUser
    }

    func invalidatePendingAuthentication() {
        pendingSignUpInstance = nil
        pendingSession = nil
    }

    private func makeFreshLoginRequest(instance: MissCatInstance) throws -> URLRequest {
        let sessionID = uuidGenerator()
        pendingSignUpInstance = nil
        pendingSession = PendingSession(
            instance: instance,
            id: sessionID,
            state: .awaitingCallback
        )

        let url = try MissCatMiAuthRequestBuilder.authorizationURL(
            instance: instance,
            sessionID: sessionID,
            callbackURLString: Self.callbackURLString,
            permissions: Self.appPermissions
        )
        return URLRequest(url: url)
    }

    private func registerPushNotifications(for user: SecureUser) {
        #if targetEnvironment(simulator)
            MisscatApi(apiKeyManager: MockApiKeyManager(), and: user).registerSw()
        #else
            MisscatApi(apiKeyManager: ApiKeyManager(), and: user).registerSw()
        #endif
    }
}

extension MissCatAuthenticationService {
    enum AuthenticationError: LocalizedError, Equatable {
        case invalidInstance
        case expiredSession
        case invalidCallback
        case requestFailed
        case serverRejected(statusCode: Int)
        case invalidServerResponse
        case authorizationDenied
        case missingAccessToken
        case missingUser
        case couldNotPersistAccount

        var errorDescription: String? {
            switch self {
            case .invalidInstance:
                "インスタンスのURLが正しくありません"
            case .expiredSession:
                "認証セッションの有効期限が切れました。もう一度お試しください"
            case .invalidCallback:
                "認証結果を確認できませんでした"
            case .requestFailed:
                "認証サーバーに接続できませんでした"
            case let .serverRejected(statusCode):
                "認証サーバーがエラーを返しました（HTTP \(statusCode)）"
            case .invalidServerResponse:
                "認証サーバーから不正な応答を受信しました"
            case .authorizationDenied:
                "アクセスが許可されませんでした。もう一度お試しください"
            case .missingAccessToken:
                "認証サーバーからアクセストークンを取得できませんでした"
            case .missingUser:
                "認証サーバーからユーザー情報を取得できませんでした"
            case .couldNotPersistAccount:
                "アカウント情報を安全に保存できませんでした"
            }
        }
    }
}
