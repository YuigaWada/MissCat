import Foundation

public protocol MissCatNotificationsRepository: AnyObject {
    var accountScope: MissCatAccountScope { get }

    func fetchNotifications(cursor: String?, limit: Int) async throws -> MissCatNotificationPage
    func resolveNotification(id: String) async throws -> MissCatNotification?
    func realtimeNotifications() -> AsyncStream<MissCatNotificationRealtimeEvent>
}

public protocol MissCatMessagingRepository: AnyObject {
    var accountScope: MissCatAccountScope { get }

    func fetchConversations(limit: Int) async throws -> [MissCatConversation]
    func fetchMessages(peer: MissCatPerson, cursor: String?, limit: Int) async throws -> MissCatMessagePage
    func sendText(_ text: String, to peer: MissCatPerson, requestID: UUID) async throws -> MissCatDirectMessage
}

public enum MissCatDirectMessageAPI: Equatable, Sendable {
    case currentChat
    case legacyMessaging
    case unavailable
}

public struct MissCatAPIEndpointCapabilities: Equatable, Sendable {
    public let endpoints: Set<String>

    public init(endpoints: Set<String>) {
        self.endpoints = endpoints
    }

    public var directMessageAPI: MissCatDirectMessageAPI {
        let current = [
            "chat/history",
            "chat/messages/user-timeline",
            "chat/messages/create-to-user"
        ]
        if current.allSatisfy(endpoints.contains) {
            return .currentChat
        }

        let legacy = ["messaging/history", "messaging/messages", "messaging/create"]
        if legacy.allSatisfy(endpoints.contains) {
            return .legacyMessaging
        }
        return .unavailable
    }
}

public enum MissCatNotificationMessagingError: LocalizedError, Equatable {
    case invalidInstance
    case invalidResponse
    case server(status: Int)
    case directMessagesUnavailable(host: String)
    case missingConversationPeer
    case rejectedEmptyMessage

    public var errorDescription: String? {
        switch self {
        case .invalidInstance:
            "インスタンスのURLが正しくありません。"
        case .invalidResponse:
            "サーバーからの応答を読み取れませんでした。"
        case let .server(status):
            "サーバーがリクエストを拒否しました（\(status)）。"
        case let .directMessagesUnavailable(host):
            "\(host) は対応するチャットAPIを公開していません。"
        case .missingConversationPeer:
            "会話相手を特定できませんでした。"
        case .rejectedEmptyMessage:
            "メッセージを入力してください。"
        }
    }
}

public protocol MissCatHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct MissCatURLSessionTransport: MissCatHTTPTransport, @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MissCatNotificationMessagingError.invalidResponse
        }
        return (data, httpResponse)
    }
}

/// Native URLSession adapter for the notification/chat bundle. It deliberately does not expose
/// MisskeyKit models or a global current account to the SwiftUI domain.
public final class MissCatNativeNotificationMessagingRepository:
    MissCatNotificationsRepository,
    MissCatMessagingRepository,
    @unchecked Sendable
{
    public let accountScope: MissCatAccountScope

    private let transport: MissCatHTTPTransport
    private let webSocketSession: URLSession
    private let decoder: JSONDecoder
    private let capabilityCache = MissCatEndpointCapabilityCache()

    public init(
        accountScope: MissCatAccountScope,
        transport: MissCatHTTPTransport = MissCatURLSessionTransport(),
        webSocketSession: URLSession = .shared
    ) {
        self.accountScope = accountScope
        self.transport = transport
        self.webSocketSession = webSocketSession
        decoder = JSONDecoder()
    }

    public func fetchNotifications(cursor: String?, limit: Int) async throws -> MissCatNotificationPage {
        var body: [String: Any] = [
            "limit": limit,
            "markAsRead": true,
            "includeTypes": MissCatNotificationKind.allCases.map(\.rawValue)
        ]
        if let cursor { body["untilId"] = cursor }
        let response: [APINotification] = try await post("i/notifications", body: body)
        let notifications = response.compactMap(\.domainValue)
        return MissCatNotificationPage(
            notifications: notifications,
            hasMore: response.count >= limit
        )
    }

    public func resolveNotification(id: String) async throws -> MissCatNotification? {
        let response: [APINotification] = try await post(
            "i/notifications",
            body: ["limit": 100, "markAsRead": false]
        )
        return response.first(where: { $0.id == id })?.domainValue
    }

    public func realtimeNotifications() -> AsyncStream<MissCatNotificationRealtimeEvent> {
        guard !accountScope.host.isEmpty else {
            return AsyncStream { continuation in
                continuation.yield(.failed(message: MissCatNotificationMessagingError.invalidInstance.localizedDescription))
                continuation.finish()
            }
        }
        var components = URLComponents()
        components.scheme = "wss"
        components.host = accountScope.host
        components.path = "/streaming"
        components.queryItems = [URLQueryItem(name: "i", value: accountScope.accessToken)]
        guard let url = components.url else {
            return AsyncStream { continuation in
                continuation.yield(.failed(message: MissCatNotificationMessagingError.invalidInstance.localizedDescription))
                continuation.finish()
            }
        }

        let session = webSocketSession
        let decoder = decoder
        return AsyncStream { continuation in
            let channelID = UUID().uuidString
            let socket = session.webSocketTask(with: url)
            socket.resume()

            let connect: [String: Any] = [
                "type": "connect",
                "body": ["channel": "main", "id": channelID]
            ]
            if let data = try? JSONSerialization.data(withJSONObject: connect),
               let text = String(data: data, encoding: .utf8) {
                socket.send(.string(text)) { error in
                    if let error {
                        continuation.yield(.failed(message: error.localizedDescription))
                    } else {
                        continuation.yield(.connected(true))
                    }
                }
            }

            let receiveTask = Task {
                while !Task.isCancelled {
                    do {
                        let message = try await socket.receive()
                        let data: Data
                        switch message {
                        case let .data(value): data = value
                        case let .string(value): data = Data(value.utf8)
                        @unknown default: continue
                        }
                        guard let envelope = try? decoder.decode(APIStreamingEnvelope.self, from: data),
                              envelope.body.id == channelID,
                              envelope.body.type == "notification",
                              let notification = envelope.body.body.domainValue else { continue }
                        continuation.yield(.inserted(notification))
                    } catch {
                        guard !Task.isCancelled else { return }
                        continuation.yield(.connected(false))
                        continuation.yield(.failed(message: error.localizedDescription))
                        return
                    }
                }
            }

            continuation.onTermination = { _ in
                receiveTask.cancel()
                socket.cancel(with: .goingAway, reason: nil)
            }
        }
    }

    public func fetchConversations(limit: Int) async throws -> [MissCatConversation] {
        let capability = try await endpointCapabilities().directMessageAPI
        let response: [APIChatMessage]
        switch capability {
        case .currentChat:
            response = try await post("chat/history", body: ["limit": limit, "room": false])
        case .legacyMessaging:
            response = try await post("messaging/history", body: ["limit": limit])
        case .unavailable:
            throw MissCatNotificationMessagingError.directMessagesUnavailable(host: accountScope.host)
        }

        var seen = Set<String>()
        return response.compactMap { value in
            guard let conversation = value.conversation(ownerID: accountScope.accountID),
                  seen.insert(conversation.id).inserted else { return nil }
            return conversation
        }
    }

    public func fetchMessages(
        peer: MissCatPerson,
        cursor: String?,
        limit: Int
    ) async throws -> MissCatMessagePage {
        let capability = try await endpointCapabilities().directMessageAPI
        var body: [String: Any] = ["limit": limit]
        if let cursor { body["untilId"] = cursor }

        let response: [APIChatMessage]
        switch capability {
        case .currentChat:
            body["userId"] = peer.id
            response = try await post("chat/messages/user-timeline", body: body)
        case .legacyMessaging:
            body["userId"] = peer.id
            body["markAsRead"] = true
            response = try await post("messaging/messages", body: body)
        case .unavailable:
            throw MissCatNotificationMessagingError.directMessagesUnavailable(host: accountScope.host)
        }

        return MissCatMessagePage(
            messages: response.compactMap(\.domainValue),
            hasMore: response.count >= limit
        )
    }

    public func sendText(
        _ text: String,
        to peer: MissCatPerson,
        requestID _: UUID
    ) async throws -> MissCatDirectMessage {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MissCatNotificationMessagingError.rejectedEmptyMessage }

        let capability = try await endpointCapabilities().directMessageAPI
        let response: APIChatMessage
        switch capability {
        case .currentChat:
            response = try await post(
                "chat/messages/create-to-user",
                body: ["toUserId": peer.id, "text": trimmed]
            )
        case .legacyMessaging:
            response = try await post(
                "messaging/create",
                body: ["userId": peer.id, "text": trimmed]
            )
        case .unavailable:
            throw MissCatNotificationMessagingError.directMessagesUnavailable(host: accountScope.host)
        }
        guard let message = response.domainValue else {
            throw MissCatNotificationMessagingError.invalidResponse
        }
        return message
    }

    public func endpointCapabilities() async throws -> MissCatAPIEndpointCapabilities {
        try await capabilityCache.value { [weak self] in
            guard let self else { throw CancellationError() }
            let values: [String] = try await self.post("endpoints", body: [:], authenticated: false)
            return MissCatAPIEndpointCapabilities(endpoints: Set(values))
        }
    }

    public func resolvePerson(acct: String) async throws -> MissCatPerson {
        let normalized = acct.trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        let components = normalized.split(separator: "@", maxSplits: 1).map(String.init)
        guard let username = components.first, !username.isEmpty else {
            throw MissCatNotificationMessagingError.missingConversationPeer
        }
        var body: [String: Any] = ["username": username]
        if components.count == 2, !components[1].isEmpty {
            body["host"] = components[1]
        }
        let user: APIUser = try await post("users/show", body: body)
        return user.domainValue
    }

    private func post<Response: Decodable>(
        _ endpoint: String,
        body: [String: Any],
        authenticated: Bool = true
    ) async throws -> Response {
        guard let baseURL = accountScope.baseURL else {
            throw MissCatNotificationMessagingError.invalidInstance
        }
        var request = URLRequest(url: baseURL.appendingPathComponent("api/\(endpoint)"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authenticated {
            request.setValue("Bearer \(accountScope.accessToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await transport.data(for: request)
        guard (200 ..< 300).contains(response.statusCode) else {
            throw MissCatNotificationMessagingError.server(status: response.statusCode)
        }
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw MissCatNotificationMessagingError.invalidResponse
        }
    }
}

private actor MissCatEndpointCapabilityCache {
    private var cached: MissCatAPIEndpointCapabilities?

    func value(
        loader: @Sendable () async throws -> MissCatAPIEndpointCapabilities
    ) async throws -> MissCatAPIEndpointCapabilities {
        if let cached { return cached }
        let loaded = try await loader()
        cached = loaded
        return loaded
    }
}

private struct APIUser: Decodable {
    let id: String
    let name: String?
    let username: String
    let host: String?
    let avatarUrl: URL?

    var domainValue: MissCatPerson {
        MissCatPerson(
            id: id,
            name: name ?? username,
            username: username,
            host: host,
            avatarURL: avatarUrl
        )
    }
}

private struct APINote: Decodable {
    let id: String
    let text: String?
}

private struct APINotification: Decodable {
    let id: String
    let createdAt: String
    let type: String
    let user: APIUser?
    let note: APINote?
    let reaction: String?

    var domainValue: MissCatNotification? {
        guard let kind = MissCatNotificationKind(rawValue: type), let user else { return nil }
        return MissCatNotification(
            id: id,
            kind: kind,
            actor: user.domainValue,
            createdAt: MissCatAPIDateParser.date(createdAt),
            noteID: note?.id,
            noteText: note?.text,
            reaction: reaction
        )
    }
}

private struct APIStreamingEnvelope: Decodable {
    struct Body: Decodable {
        let id: String
        let type: String
        let body: APINotification
    }

    let type: String
    let body: Body
}

private struct APIChatMessage: Decodable {
    let id: String
    let createdAt: String
    let fromUserId: String?
    let toUserId: String?
    let userId: String?
    let recipientId: String?
    let fromUser: APIUser?
    let toUser: APIUser?
    let user: APIUser?
    let recipient: APIUser?
    let text: String?
    let isRead: Bool?

    var domainValue: MissCatDirectMessage? {
        guard let sender = fromUserId ?? userId,
              let recipient = toUserId ?? recipientId else { return nil }
        return MissCatDirectMessage(
            id: id,
            senderID: sender,
            recipientID: recipient,
            text: text ?? "",
            createdAt: MissCatAPIDateParser.date(createdAt),
            isRead: isRead ?? false
        )
    }

    func conversation(ownerID: String) -> MissCatConversation? {
        let senderID = fromUserId ?? userId
        let receiverID = toUserId ?? recipientId
        let peer: APIUser?
        if senderID == ownerID {
            peer = toUser ?? recipient
        } else if receiverID == ownerID {
            peer = fromUser ?? user
        } else {
            return nil
        }
        guard let peer else { return nil }
        return MissCatConversation(
            peer: peer.domainValue,
            latestMessageID: id,
            latestText: text ?? "",
            latestDate: MissCatAPIDateParser.date(createdAt),
            isRead: isRead ?? false
        )
    }
}

private enum MissCatAPIDateParser {
    static func date(_ value: String) -> Date {
        fractional.date(from: value) ?? plain.date(from: value) ?? .distantPast
    }

    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plain = ISO8601DateFormatter()
}
