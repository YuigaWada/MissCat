import Foundation

protocol MissCatNativeAPITransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct MissCatNativeAPIURLSessionTransport: MissCatNativeAPITransport, @unchecked Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw MissCatNativeAPIError.invalidHTTPResponse
        }
        return (data, response)
    }
}

struct MissCatNativeAccount: Decodable, Equatable, Sendable {
    let id: String
    let username: String
}

struct MissCatNativeEmoji: Decodable, Equatable, Sendable {
    let name: String
    let url: String
    let category: String?
}

enum MissCatNativeServiceWorkerState: String, Decodable, Equatable, Sendable {
    case alreadySubscribed = "already-subscribed"
    case subscribed
}

enum MissCatNativeAPIError: LocalizedError, Equatable {
    case invalidCredentials
    case invalidInstance
    case invalidHTTPResponse
    case invalidResponse(endpoint: String)
    case server(status: Int, code: String?, message: String?)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            "アカウント情報を取得できませんでした"
        case .invalidInstance:
            "インスタンスのURLが正しくありません"
        case .invalidHTTPResponse:
            "サーバーからの応答を読み取れませんでした"
        case .invalidResponse:
            "サーバーから予期しない応答が返されました"
        case let .server(status, code, message):
            if let message, !message.isEmpty {
                "Misskeyがリクエストを拒否しました（HTTP \(status): \(message)）"
            } else if let code, !code.isEmpty {
                "Misskeyがリクエストを拒否しました（HTTP \(status): \(code)）"
            } else {
                "Misskeyがリクエストを拒否しました（HTTP \(status)）"
            }
        }
    }
}

/// Native client for the last compatibility endpoints that used to be routed
/// through MisskeyKit. Credentials are carried only in the Authorization
/// header, matching the app's authenticated timeline, compose, and profile
/// clients; request bodies remain safe to inspect in diagnostics.
struct MissCatNativeAPIClient: Sendable {
    static let defaultTimeout: TimeInterval = 30

    private struct MetaResponse: Decodable {
        let emojis: [MissCatNativeEmoji]?
    }

    private struct ServiceWorkerResponse: Decodable {
        let state: MissCatNativeServiceWorkerState?
    }

    private struct ErrorEnvelope: Decodable {
        struct ServerError: Decodable {
            let code: String?
            let message: String?
        }

        let error: ServerError?
    }

    private let origin: URL
    private let accessToken: String
    private let transport: any MissCatNativeAPITransport
    private let requestTimeout: TimeInterval

    init(
        instance: String,
        accessToken: String,
        transport: any MissCatNativeAPITransport = MissCatNativeAPIURLSessionTransport(),
        requestTimeout: TimeInterval = Self.defaultTimeout
    ) throws {
        guard !accessToken.isEmpty,
              accessToken.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              accessToken.rangeOfCharacter(from: .controlCharacters) == nil
        else {
            throw MissCatNativeAPIError.invalidCredentials
        }

        do {
            origin = try MissCatInstance.normalize(instance).origin
        } catch {
            throw MissCatNativeAPIError.invalidInstance
        }
        self.accessToken = accessToken
        self.transport = transport
        self.requestTimeout = requestTimeout
    }

    init(
        owner: SecureUser,
        transport: any MissCatNativeAPITransport = MissCatNativeAPIURLSessionTransport(),
        requestTimeout: TimeInterval = Self.defaultTimeout
    ) throws {
        guard let accessToken = owner.apiKey else {
            throw MissCatNativeAPIError.invalidCredentials
        }
        try self.init(
            instance: owner.instance,
            accessToken: accessToken,
            transport: transport,
            requestTimeout: requestTimeout
        )
    }

    func currentAccount() async throws -> MissCatNativeAccount {
        let endpoint = "i"
        let response: MissCatNativeAccount = try await post(endpoint: endpoint, body: [:])
        guard !response.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !response.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw MissCatNativeAPIError.invalidResponse(endpoint: endpoint)
        }
        return response
    }

    func customEmojis() async throws -> [MissCatNativeEmoji] {
        let response: MetaResponse = try await post(endpoint: "meta", body: [:])
        return response.emojis ?? []
    }

    func registerServiceWorker(
        endpoint: String,
        auth: String,
        publicKey: String
    ) async throws -> MissCatNativeServiceWorkerState {
        let apiEndpoint = "sw/register"
        let response: ServiceWorkerResponse = try await post(
            endpoint: apiEndpoint,
            body: [
                "endpoint": endpoint,
                "auth": auth,
                "publickey": publicKey
            ]
        )
        guard let state = response.state else {
            throw MissCatNativeAPIError.invalidResponse(endpoint: apiEndpoint)
        }
        return state
    }

    private func post<Response: Decodable>(
        endpoint: String,
        body: [String: String]
    ) async throws -> Response {
        let request = try makeRequest(endpoint: endpoint, body: body)
        let (data, response) = try await transport.data(for: request)
        guard (200 ..< 300).contains(response.statusCode) else {
            let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data)
            throw MissCatNativeAPIError.server(
                status: response.statusCode,
                code: envelope?.error?.code,
                message: envelope?.error?.message
            )
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw MissCatNativeAPIError.invalidResponse(endpoint: endpoint)
        }
    }

    private func makeRequest(endpoint: String, body: [String: String]) throws -> URLRequest {
        guard let url = URL(string: "/api/\(endpoint)", relativeTo: origin)?.absoluteURL else {
            throw MissCatNativeAPIError.invalidInstance
        }
        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }
}
