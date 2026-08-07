import Foundation

enum MissCatReportComment {
    static let maximumLength = 2_048

    static func normalized(_ rawValue: String) -> String? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= maximumLength else { return nil }
        return value
    }

    static func clamped(_ rawValue: String) -> String {
        String(rawValue.prefix(maximumLength))
    }
}

/// Account-scoped values needed by the feed stack. Keeping the API key here avoids
/// coupling the SwiftUI feature to the legacy account cache and makes previews/tests injectable.
public struct MissCatFeedSession: Equatable, Sendable {
    public let accountID: String
    public let username: String
    public let instance: String
    public let apiKey: String
    public let instanceOrigin: URL?

    public init(accountID: String, username: String, instance: String, apiKey: String) {
        self.accountID = accountID
        self.username = username
        self.instance = instance
        self.apiKey = apiKey
        instanceOrigin = MissCatFeedInstanceOrigin.resolve(instance)
    }

    public var scope: MissCatShellAccountScope {
        MissCatShellAccountScope(instance: instance, userID: accountID, username: username)
    }

    public var compositeAccountID: String {
        MissCatAccountIdentity.storageKey(instance: instance, userId: accountID)
    }
}

enum MissCatFeedInstanceOrigin {
    static func resolve(_ rawValue: String) -> URL? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        let normalized = value.contains("://") ? value : "https://\(value)"
        guard !normalized.hasSuffix(":"),
              var components = URLComponents(string: normalized),
              components.scheme?.lowercased() == "https",
              components.user == nil,
              components.password == nil,
              components.percentEncodedPath.isEmpty,
              components.query == nil,
              components.fragment == nil,
              let host = components.host?.lowercased(),
              !host.isEmpty,
              !host.hasSuffix("."),
              components.percentEncodedHost?.contains("%") != true,
              components.url != nil else { return nil }

        if let port = components.port, !(1 ... 65_535).contains(port) {
            return nil
        }

        components.scheme = "https"
        components.host = host
        components.path = ""
        if components.port == 443 {
            components.port = nil
        }
        guard let origin = components.url,
              origin.scheme == "https",
              origin.host == host else { return nil }
        return origin
    }
}

/// Resolves the two custom-emoji response shapes shipped by Misskey servers.
/// Older/current-compatible payloads can include explicit URL dictionaries,
/// while Misskey 2023.12+ also defines canonical `/emoji/<name>.webp` routes.
enum MissCatEmojiURLResolver {
    private static let shortcodeExpression = try! NSRegularExpression(
        pattern: #":([A-Za-z0-9_\-]+(?:@[A-Za-z0-9.-]+)?):"#
    )

    static func mergedURLs(
        explicit values: [String: String]?,
        sources: [String?],
        authorHost: String?,
        instanceOrigin: URL?
    ) -> [String: URL] {
        // Misskey's API promises bare names, but older forks have emitted both
        // `foo` and `:foo:` in the same dictionary. Normalising those keys with
        // Dictionary(uniqueKeysWithValues:) traps the process. Prefer the bare
        // spelling deterministically and ignore invalid/duplicate candidates.
        let explicitEntries = (values ?? [:]).sorted { lhs, rhs in
            let lhsName = normalizedName(lhs.key)
            let rhsName = normalizedName(rhs.key)
            if lhsName != rhsName { return lhsName < rhsName }
            let lhsIsBare = lhs.key == lhsName
            let rhsIsBare = rhs.key == rhsName
            if lhsIsBare != rhsIsBare { return lhsIsBare }
            return lhs.key < rhs.key
        }
        var result: [String: URL] = [:]
        for (key, value) in explicitEntries {
            let name = normalizedName(key)
            guard !name.isEmpty,
                  isValidRouteName(name),
                  result[name] == nil,
                  let url = resolvedExplicitURL(value, relativeTo: instanceOrigin)
            else { continue }
            result[name] = url
        }
        for source in sources.compactMap({ $0 }) {
            for name in shortcodeNames(in: source) where result[name] == nil {
                result[name] = canonicalURL(
                    for: name,
                    authorHost: authorHost,
                    instanceOrigin: instanceOrigin
                )
            }
        }
        return result
    }

    static func reactionURL(
        for reaction: String,
        explicit values: [String: String]?,
        instanceOrigin: URL?
    ) -> URL? {
        let name = normalizedName(reaction)
        if let rawURL = values?[reaction] ?? values?[name],
           let explicitURL = resolvedExplicitURL(rawURL, relativeTo: instanceOrigin) {
            return explicitURL
        }
        guard reaction.hasPrefix(":"), reaction.hasSuffix(":"), reaction.count > 2 else {
            return nil
        }
        return canonicalURL(for: name, authorHost: nil, instanceOrigin: instanceOrigin)
    }

    static func resolvedURL(
        explicitURL: String?,
        name: String,
        instanceOrigin: URL?
    ) -> URL? {
        if let explicitURL,
           let resolved = resolvedExplicitURL(explicitURL, relativeTo: instanceOrigin) {
            return resolved
        }
        return canonicalURL(for: name, authorHost: nil, instanceOrigin: instanceOrigin)
    }

    static func shortcodeNames(in source: String) -> Set<String> {
        let range = NSRange(source.startIndex..., in: source)
        return Set(shortcodeExpression.matches(in: source, range: range).compactMap { match in
            guard match.numberOfRanges == 2,
                  let range = Range(match.range(at: 1), in: source) else { return nil }
            return normalizedName(String(source[range]))
        })
    }

    static func canonicalURL(
        for rawName: String,
        authorHost: String?,
        instanceOrigin: URL?
    ) -> URL? {
        guard let instanceOrigin,
              isAllowedRemoteURL(instanceOrigin) else { return nil }
        var name = normalizedName(rawName)
        guard !name.isEmpty, !name.contains("/"), !name.contains("\\") else { return nil }

        if name.hasSuffix("@.") {
            name.removeLast(2)
        } else if !name.contains("@"),
                  let host = authorHost?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !host.isEmpty {
            name += "@\(host.lowercased())"
        }
        guard !name.isEmpty, isValidRouteName(name) else { return nil }
        return instanceOrigin
            .appendingPathComponent("emoji", isDirectory: true)
            .appendingPathComponent("\(name).webp")
    }

    private static func normalizedName(_ rawValue: String) -> String {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix(":"), value.hasSuffix(":"), value.count >= 2 {
            value.removeFirst()
            value.removeLast()
        }
        return value
    }

    private static func resolvedExplicitURL(_ rawValue: String, relativeTo origin: URL?) -> URL? {
        guard !rawValue.hasPrefix("//") else { return nil }
        guard let url = URL(string: rawValue) else { return nil }
        let resolved: URL?
        if url.scheme != nil {
            resolved = url
        } else {
            resolved = origin.flatMap { URL(string: rawValue, relativeTo: $0)?.absoluteURL }
        }
        return resolved.flatMap { isAllowedRemoteURL($0) ? $0 : nil }
    }

    static func isAllowedRemoteURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              url.host?.isEmpty == false,
              url.user == nil,
              url.password == nil else { return false }
        return true
    }

    private static func isValidRouteName(_ name: String) -> Bool {
        name.range(
            of: #"^[A-Za-z0-9_\-]+(?:@[A-Za-z0-9.-]+)?$"#,
            options: .regularExpression
        ) != nil
    }
}

public enum MissCatFeedSource: Equatable, Sendable {
    case home
    case local
    case social
    case global
    case favorites
    case search(query: String)
    case hashtag(tag: String)
    case user(userID: String, includeReplies: Bool, withFiles: Bool)
    case userList(listID: String)
    case noteDetail(noteID: String)

    public var accessibilityName: String {
        switch self {
        case .home: "home"
        case .local: "local"
        case .social: "social"
        case .global: "global"
        case .favorites: "favorites"
        case .search: "search-results"
        case .hashtag: "hashtag-results"
        case .user: "user-timeline"
        case .userList: "user-list-timeline"
        case .noteDetail: "note-detail"
        }
    }

    public var supportsPagination: Bool {
        return true
    }

    public var supportsRealtime: Bool {
        switch self {
        case .home, .local, .social, .global: true
        case .favorites, .search, .hashtag, .user, .userList, .noteDetail: false
        }
    }

    public var isNoteDetail: Bool {
        if case .noteDetail = self { return true }
        return false
    }
}

public struct MissCatNoteAuthor: Equatable, Sendable {
    public let id: String
    public var name: String
    public var username: String
    public var host: String?
    public var avatarURL: URL?
    public var localAvatarImageName: String?
    public var isCat: Bool
    public var emojis: [String: URL]
    public var localEmojis: [String: String]

    public init(
        id: String,
        name: String,
        username: String,
        host: String? = nil,
        avatarURL: URL? = nil,
        localAvatarImageName: String? = nil,
        isCat: Bool = false,
        emojis: [String: URL] = [:],
        localEmojis: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.username = username
        self.host = host
        self.avatarURL = avatarURL
        self.localAvatarImageName = localAvatarImageName
        self.isCat = isCat
        self.emojis = emojis
        self.localEmojis = localEmojis
    }

    public var acct: String {
        guard let host, !host.isEmpty else { return "@\(username)" }
        return "@\(username)@\(host)"
    }
}

public enum MissCatAttachmentKind: Equatable, Sendable {
    case image
    case animatedImage
    case video
    case audio
    case other
}

public struct MissCatNoteAttachment: Identifiable, Equatable, Sendable {
    public let id: String
    public var name: String
    public var kind: MissCatAttachmentKind
    public var url: URL?
    public var thumbnailURL: URL?
    public var localImageName: String?
    public var isSensitive: Bool
    public var width: Int?
    public var height: Int?

    public init(
        id: String,
        name: String,
        kind: MissCatAttachmentKind,
        url: URL?,
        thumbnailURL: URL? = nil,
        localImageName: String? = nil,
        isSensitive: Bool = false,
        width: Int? = nil,
        height: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.url = url
        self.thumbnailURL = thumbnailURL
        self.localImageName = localImageName
        self.isSensitive = isSensitive
        self.width = width
        self.height = height
    }
}

public struct MissCatReaction: Identifiable, Equatable, Sendable {
    public var id: String { name }
    public let name: String
    public var count: Int
    public var isMine: Bool
    public var emojiURL: URL?

    public init(name: String, count: Int, isMine: Bool = false, emojiURL: URL? = nil) {
        self.name = name
        self.count = count
        self.isMine = isMine
        self.emojiURL = emojiURL
    }
}

public struct MissCatFeedPollChoice: Identifiable, Equatable, Sendable {
    public let id: Int
    public let text: String
    public var votes: Int
    public var isVoted: Bool

    public init(id: Int, text: String, votes: Int, isVoted: Bool = false) {
        self.id = id
        self.text = text
        self.votes = votes
        self.isVoted = isVoted
    }
}

public struct MissCatPoll: Equatable, Sendable {
    public var choices: [MissCatFeedPollChoice]
    public let allowsMultipleChoices: Bool
    public let expiresAt: Date?

    public init(
        choices: [MissCatFeedPollChoice],
        allowsMultipleChoices: Bool = false,
        expiresAt: Date? = nil
    ) {
        self.choices = choices
        self.allowsMultipleChoices = allowsMultipleChoices
        self.expiresAt = expiresAt
    }
}

/// A non-recursive snapshot used for quote notes. It carries everything the compact
/// quoted-note presentation needs without creating a recursive value type.
public struct MissCatQuotedNote: Equatable, Sendable {
    public let noteID: String
    public let author: MissCatNoteAuthor
    public let text: String
    public let cw: String?
    public let attachments: [MissCatNoteAttachment]
    public let emojis: [String: URL]

    public init(
        noteID: String,
        author: MissCatNoteAuthor,
        text: String,
        cw: String? = nil,
        attachments: [MissCatNoteAttachment] = [],
        emojis: [String: URL] = [:]
    ) {
        self.noteID = noteID
        self.author = author
        self.text = text
        self.cw = cw
        self.attachments = attachments
        self.emojis = emojis
    }
}

public struct MissCatNote: Identifiable, Equatable, Sendable {
    /// Timeline item identity. A pure renote keeps its outer note ID for stable deduplication.
    public let id: String
    /// Canonical note identity used for detail navigation and note actions.
    public let noteID: String
    public let author: MissCatNoteAuthor
    public var createdAt: Date?
    public var text: String
    public var cw: String?
    public var visibility: String
    public var reactionAcceptance: String?
    public var attachments: [MissCatNoteAttachment]
    public var reactions: [MissCatReaction]
    public var repliesCount: Int
    public var renoteCount: Int
    public var replyID: String?
    public var tags: [String]
    public var myReaction: String?
    public var isFavorite: Bool
    public var poll: MissCatPoll?
    public var quotedNote: MissCatQuotedNote?
    public var renotedBy: MissCatNoteAuthor?
    public var emojis: [String: URL]

    public init(
        id: String,
        noteID: String? = nil,
        author: MissCatNoteAuthor,
        createdAt: Date? = nil,
        text: String = "",
        cw: String? = nil,
        visibility: String = "public",
        reactionAcceptance: String? = nil,
        attachments: [MissCatNoteAttachment] = [],
        reactions: [MissCatReaction] = [],
        repliesCount: Int = 0,
        renoteCount: Int = 0,
        replyID: String? = nil,
        tags: [String] = [],
        myReaction: String? = nil,
        isFavorite: Bool = false,
        poll: MissCatPoll? = nil,
        quotedNote: MissCatQuotedNote? = nil,
        renotedBy: MissCatNoteAuthor? = nil,
        emojis: [String: URL] = [:]
    ) {
        self.id = id
        self.noteID = noteID ?? id
        self.author = author
        self.createdAt = createdAt
        self.text = text
        self.cw = cw
        self.visibility = visibility
        self.reactionAcceptance = reactionAcceptance
        self.attachments = attachments
        self.reactions = reactions
        self.repliesCount = repliesCount
        self.renoteCount = renoteCount
        self.replyID = replyID
        self.tags = tags
        self.myReaction = myReaction
        self.isFavorite = isFavorite
        self.poll = poll
        self.quotedNote = quotedNote
        self.renotedBy = renotedBy
        self.emojis = emojis
    }
}

public struct MissCatFeedPage: Equatable, Sendable {
    public let notes: [MissCatNote]
    public let hasMore: Bool

    public init(notes: [MissCatNote], hasMore: Bool) {
        self.notes = notes
        self.hasMore = hasMore
    }
}

public struct MissCatNoteRepliesPage: Equatable, Sendable {
    public let replies: [MissCatNote]
    public let nextCursor: String?
    public let hasMore: Bool

    public init(replies: [MissCatNote], nextCursor: String?, hasMore: Bool) {
        self.replies = replies
        self.nextCursor = nextCursor
        self.hasMore = hasMore
    }
}

public struct MissCatNoteThread: Equatable, Sendable {
    public let ancestors: [MissCatNote]
    public let note: MissCatNote
    public let replies: [MissCatNote]
    public let repliesCursor: String?
    public let hasMoreReplies: Bool

    public init(
        ancestors: [MissCatNote],
        note: MissCatNote,
        replies: [MissCatNote],
        repliesCursor: String? = nil,
        hasMoreReplies: Bool = false
    ) {
        self.ancestors = ancestors
        self.note = note
        self.replies = replies
        self.repliesCursor = repliesCursor
        self.hasMoreReplies = hasMoreReplies
    }

    public var allNotes: [MissCatNote] { ancestors + [note] + replies }
}

public enum MissCatFeedAction: Equatable, Sendable {
    case favorite(noteID: String)
    case unfavorite(noteID: String)
    case addReaction(noteID: String, reaction: String)
    case removeReaction(noteID: String)
    case renote(noteID: String)
    case vote(noteID: String, choice: Int)
    case delete(noteID: String)
    case mute(userID: String)
    case block(userID: String)
    case report(userID: String, comment: String)
}

public enum MissCatRealtimeEvent: Equatable, Sendable {
    case connected(Bool)
    case inserted(MissCatNote)
    case replaced(MissCatNote)
    case removed(noteID: String)
    case reaction(noteID: String, reaction: String, delta: Int, isMine: Bool)
    case pollVote(noteID: String, choice: Int, isMine: Bool)
    case failed(message: String)
}

public enum MissCatFeedPhase: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case empty
    case failed(message: String)
}
