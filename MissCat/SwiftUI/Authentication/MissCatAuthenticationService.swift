import Foundation
import MisskeyKit

@MainActor
final class MissCatAuthenticationService {
    static let callbackURLString = "https://misscat.dev"

    private let misskey: MisskeyKit
    private let misskeyIOAppSecret = "0fRSNkKKl9hcZTGrUSyZOb19n8UUVkxw"
    private let appPermissions = [
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

    private var pendingAppSecret: String?
    private var pendingInstance: String?

    init(misskey: MisskeyKit = .shared) {
        self.misskey = misskey
    }

    func makeAuthorizationRequest(
        intent: MissCatAuthenticationIntent,
        instance: String
    ) async throws -> URLRequest {
        let normalizedInstance = MissCatInstanceEditorView.normalize(instance)
        guard let instanceURL = URL(string: "https://\(normalizedInstance)"),
              instanceURL.host != nil
        else {
            throw AuthenticationError.invalidInstance
        }

        misskey.auth.setAPIKey("")
        misskey.changeInstance(instance: normalizedInstance)

        let appSecret = try await fetchAppSecret(for: normalizedInstance)
        pendingInstance = normalizedInstance
        pendingAppSecret = appSecret

        switch intent {
        case .signUp:
            return URLRequest(url: instanceURL)
        case .logIn:
            return try await startLoginSession(appSecret: appSecret)
        }
    }

    func makeLoginRequestAfterSignUp(instance: String) async throws -> URLRequest {
        let normalizedInstance = MissCatInstanceEditorView.normalize(instance)
        guard pendingInstance == normalizedInstance,
              let pendingAppSecret
        else {
            throw AuthenticationError.expiredSession
        }

        misskey.changeInstance(instance: normalizedInstance)
        return try await startLoginSession(appSecret: pendingAppSecret)
    }

    func callbackMatches(_ url: URL) -> Bool {
        url.absoluteString.contains(Self.callbackURLString)
    }

    func completeAuthentication(callbackURL: URL) async throws -> SecureUser {
        guard callbackMatches(callbackURL),
              let instance = pendingInstance
        else {
            throw AuthenticationError.invalidCallback
        }

        let apiKey = try await exchangeAccessToken()
        misskey.changeInstance(instance: instance)
        misskey.auth.setAPIKey(apiKey)
        let user = try await fetchCurrentUser()

        let secureUser = SecureUser(
            userId: user.id,
            username: user.username ?? "",
            instance: instance,
            apiKey: apiKey
        )
        guard Cache.UserDefaults.shared.saveUser(secureUser) else {
            throw AuthenticationError.couldNotPersistAccount
        }

        Cache.UserDefaults.shared.changeCurrentUser(userId: user.id)
        secureUser.apiKey = apiKey

        guard let persistedUser = Cache.UserDefaults.shared.getUser(userId: user.id),
              let persistedAPIKey = persistedUser.apiKey,
              !persistedAPIKey.isEmpty
        else {
            throw AuthenticationError.couldNotPersistAccount
        }

        EmojiHandler.setHandler(owner: persistedUser)
        registerPushNotifications(for: persistedUser)
        Theme.shared.reset()
        Theme.shared.set()

        pendingAppSecret = nil
        pendingInstance = nil
        return persistedUser
    }

    private func fetchAppSecret(for instance: String) async throws -> String {
        guard instance != "misskey.io" else { return misskeyIOAppSecret }

        return try await withCheckedThrowingContinuation { continuation in
            misskey.app.create(
                name: "MissCat",
                description: "MissCat is a flexible Misskey client for iOS!",
                permission: appPermissions,
                callbackUrl: Self.callbackURLString
            ) { app, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let secret = app?.secret, !secret.isEmpty {
                    continuation.resume(returning: secret)
                } else {
                    continuation.resume(throwing: AuthenticationError.missingServerResponse)
                }
            }
        }
    }

    private func startLoginSession(appSecret: String) async throws -> URLRequest {
        try await withCheckedThrowingContinuation { continuation in
            misskey.auth.startSession(appSecret: appSecret) { auth, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let urlString = auth?.token?.url,
                          let url = URL(string: urlString)
                {
                    continuation.resume(returning: URLRequest(url: url))
                } else {
                    continuation.resume(throwing: AuthenticationError.missingServerResponse)
                }
            }
        }
    }

    private func exchangeAccessToken() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            misskey.auth.getAccessToken { auth, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if auth != nil,
                          let apiKey = self.misskey.auth.getAPIKey(),
                          !apiKey.isEmpty
                {
                    continuation.resume(returning: apiKey)
                } else {
                    continuation.resume(throwing: AuthenticationError.missingServerResponse)
                }
            }
        }
    }

    private func fetchCurrentUser() async throws -> UserModel {
        try await withCheckedThrowingContinuation { continuation in
            misskey.users.i { user, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let user {
                    continuation.resume(returning: user)
                } else {
                    continuation.resume(throwing: AuthenticationError.missingServerResponse)
                }
            }
        }
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
    enum AuthenticationError: LocalizedError {
        case invalidInstance
        case expiredSession
        case invalidCallback
        case missingServerResponse
        case couldNotPersistAccount

        var errorDescription: String? {
            switch self {
            case .invalidInstance:
                "インスタンスのURLが正しくありません"
            case .expiredSession:
                "認証セッションの有効期限が切れました。もう一度お試しください"
            case .invalidCallback:
                "認証結果を確認できませんでした"
            case .missingServerResponse:
                "サーバーから認証情報を取得できませんでした"
            case .couldNotPersistAccount:
                "アカウント情報を安全に保存できませんでした"
            }
        }
    }
}
