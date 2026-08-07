import Foundation

public struct MissCatAccountScope: Equatable, Sendable {
    public let accountID: String
    public let username: String
    public let host: String
    public let accessToken: String

    public init(accountID: String, username: String, host: String, accessToken: String) {
        self.accountID = accountID
        self.username = username
        self.host = host
        self.accessToken = accessToken
    }

    public var baseURL: URL? {
        URL(string: "https://\(host)")
    }
}

public struct MissCatPerson: Identifiable, Equatable, Sendable {
    public let id: String
    public var name: String
    public var username: String
    public var host: String?
    public var avatarURL: URL?

    public init(
        id: String,
        name: String,
        username: String,
        host: String? = nil,
        avatarURL: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.username = username
        self.host = host
        self.avatarURL = avatarURL
    }

    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? username : trimmed
    }

    public var acct: String {
        guard let host, !host.isEmpty else { return "@\(username)" }
        return "@\(username)@\(host)"
    }
}

public enum MissCatNotificationKind: String, CaseIterable, Codable, Sendable {
    case follow
    case reaction
    case renote
    case reply
    case mention
    case quote

    public var localizedAction: String {
        switch self {
        case .follow: "フォローしました"
        case .reaction: "リアクションしました"
        case .renote: "Renoteしました"
        case .reply: "返信しました"
        case .mention: "メンションしました"
        case .quote: "引用しました"
        }
    }

    public var symbolName: String {
        switch self {
        case .follow: "person.badge.plus"
        case .reaction: "face.smiling"
        case .renote: "arrow.2.squarepath"
        case .reply: "arrowshape.turn.up.left"
        case .mention: "at"
        case .quote: "quote.bubble"
        }
    }
}

public struct MissCatNotification: Identifiable, Equatable, Sendable {
    public let id: String
    public let kind: MissCatNotificationKind
    public let actor: MissCatPerson
    public let createdAt: Date
    public let noteID: String?
    public let noteText: String?
    public let reaction: String?

    public init(
        id: String,
        kind: MissCatNotificationKind,
        actor: MissCatPerson,
        createdAt: Date,
        noteID: String? = nil,
        noteText: String? = nil,
        reaction: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.actor = actor
        self.createdAt = createdAt
        self.noteID = noteID
        self.noteText = noteText
        self.reaction = reaction
    }

    public var preferredRoute: MissCatNotificationRoute {
        if let noteID, kind != .follow {
            return .note(noteID)
        }
        return .user(actor.id)
    }
}

public enum MissCatNotificationRoute: Equatable, Sendable {
    case user(String)
    case note(String)
}

public struct MissCatNotificationPage: Equatable, Sendable {
    public let notifications: [MissCatNotification]
    public let hasMore: Bool

    public init(notifications: [MissCatNotification], hasMore: Bool) {
        self.notifications = notifications
        self.hasMore = hasMore
    }
}

public enum MissCatNotificationRealtimeEvent: Equatable, Sendable {
    case connected(Bool)
    case inserted(MissCatNotification)
    case failed(message: String)
}

public enum MissCatNotificationMessageLoadPhase: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case empty
    case failed(message: String)
}

public struct MissCatConversation: Identifiable, Equatable, Sendable {
    public var id: String { peer.id }
    public let peer: MissCatPerson
    public let latestMessageID: String
    public let latestText: String
    public let latestDate: Date
    public let isRead: Bool

    public init(
        peer: MissCatPerson,
        latestMessageID: String,
        latestText: String,
        latestDate: Date,
        isRead: Bool
    ) {
        self.peer = peer
        self.latestMessageID = latestMessageID
        self.latestText = latestText
        self.latestDate = latestDate
        self.isRead = isRead
    }
}

public struct MissCatDirectMessage: Identifiable, Equatable, Sendable {
    public let id: String
    public let senderID: String
    public let recipientID: String
    public let text: String
    public let createdAt: Date
    public let isRead: Bool

    public init(
        id: String,
        senderID: String,
        recipientID: String,
        text: String,
        createdAt: Date,
        isRead: Bool
    ) {
        self.id = id
        self.senderID = senderID
        self.recipientID = recipientID
        self.text = text
        self.createdAt = createdAt
        self.isRead = isRead
    }

    public func isMine(ownerAccountID: String) -> Bool {
        senderID == ownerAccountID
    }
}

public struct MissCatMessagePage: Equatable, Sendable {
    public let messages: [MissCatDirectMessage]
    public let hasMore: Bool

    public init(messages: [MissCatDirectMessage], hasMore: Bool) {
        self.messages = messages
        self.hasMore = hasMore
    }
}

public enum MissCatMessageSendState: Equatable, Sendable {
    case idle
    case sending(requestID: UUID)
    case failed(requestID: UUID, text: String, message: String)
}

public enum MissCatMessageRoute: Equatable, Sendable {
    case externalURL(URL)
    case mention(String)
    case hashtag(String)
}

public enum MissCatMessageLinkParser {
    public static func attributedString(_ text: String) -> AttributedString {
        var value = AttributedString(text)
        apply(pattern: #"https?://[^\s]+"#, prefix: nil, to: &value, source: text)
        apply(pattern: #"(?<![\p{L}\p{N}_])@[\p{L}\p{N}_-]+(?:@[\p{L}\p{N}.-]+)?"#, prefix: "misscat-mention://", to: &value, source: text)
        apply(pattern: #"(?<![\p{L}\p{N}_])#[\p{L}\p{N}_-]+"#, prefix: "misscat-hashtag://", to: &value, source: text)
        return value
    }

    public static func route(for url: URL) -> MissCatMessageRoute? {
        switch url.scheme?.lowercased() {
        case "http", "https":
            return .externalURL(url)
        case "misscat-mention":
            return .mention(url.host?.removingPercentEncoding ?? "")
        case "misscat-hashtag":
            return .hashtag(url.host?.removingPercentEncoding ?? "")
        default:
            return nil
        }
    }

    private static func apply(
        pattern: String,
        prefix: String?,
        to output: inout AttributedString,
        source: String
    ) {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return }
        let sourceRange = NSRange(source.startIndex..., in: source)
        for match in expression.matches(in: source, range: sourceRange).reversed() {
            guard let stringRange = Range(match.range, in: source),
                  let attributedRange = Range(stringRange, in: output) else { continue }
            let matched = String(source[stringRange])
            let destination: URL?
            if let prefix {
                let value = String(matched.dropFirst())
                let escaped = value.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? value
                destination = URL(string: prefix + escaped)
            } else {
                destination = URL(string: matched)
            }
            output[attributedRange].link = destination
        }
    }
}
