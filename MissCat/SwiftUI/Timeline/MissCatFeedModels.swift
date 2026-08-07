import Foundation

/// Account-scoped values needed by the feed stack. Keeping the API key here avoids
/// coupling the SwiftUI feature to the legacy account cache and makes previews/tests injectable.
public struct MissCatFeedSession: Equatable, Sendable {
    public let accountID: String
    public let username: String
    public let instance: String
    public let apiKey: String

    public init(accountID: String, username: String, instance: String, apiKey: String) {
        self.accountID = accountID
        self.username = username
        self.instance = instance
        self.apiKey = apiKey
    }

    public var scope: MissCatShellAccountScope {
        MissCatShellAccountScope(instance: instance, userID: accountID, username: username)
    }

    public var compositeAccountID: String {
        MissCatAccountIdentity.storageKey(instance: instance, userId: accountID)
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
        if case .noteDetail = self { return false }
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
    public var isCat: Bool

    public init(
        id: String,
        name: String,
        username: String,
        host: String? = nil,
        avatarURL: URL? = nil,
        isCat: Bool = false
    ) {
        self.id = id
        self.name = name
        self.username = username
        self.host = host
        self.avatarURL = avatarURL
        self.isCat = isCat
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
    public var isSensitive: Bool
    public var width: Int?
    public var height: Int?

    public init(
        id: String,
        name: String,
        kind: MissCatAttachmentKind,
        url: URL?,
        thumbnailURL: URL? = nil,
        isSensitive: Bool = false,
        width: Int? = nil,
        height: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.url = url
        self.thumbnailURL = thumbnailURL
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

    public init(name: String, count: Int, isMine: Bool = false) {
        self.name = name
        self.count = count
        self.isMine = isMine
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

    public init(
        noteID: String,
        author: MissCatNoteAuthor,
        text: String,
        cw: String? = nil,
        attachments: [MissCatNoteAttachment] = []
    ) {
        self.noteID = noteID
        self.author = author
        self.text = text
        self.cw = cw
        self.attachments = attachments
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

    public init(
        id: String,
        noteID: String? = nil,
        author: MissCatNoteAuthor,
        createdAt: Date? = nil,
        text: String = "",
        cw: String? = nil,
        visibility: String = "public",
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
        renotedBy: MissCatNoteAuthor? = nil
    ) {
        self.id = id
        self.noteID = noteID ?? id
        self.author = author
        self.createdAt = createdAt
        self.text = text
        self.cw = cw
        self.visibility = visibility
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

public struct MissCatNoteThread: Equatable, Sendable {
    public let ancestors: [MissCatNote]
    public let note: MissCatNote
    public let replies: [MissCatNote]

    public init(ancestors: [MissCatNote], note: MissCatNote, replies: [MissCatNote]) {
        self.ancestors = ancestors
        self.note = note
        self.replies = replies
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
