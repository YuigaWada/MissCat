import Foundation
import MisskeyKit

public protocol MissCatFeedRepository: AnyObject {
    func fetchPage(
        source: MissCatFeedSource,
        cursor: String?,
        limit: Int
    ) async throws -> MissCatFeedPage

    func fetchThread(noteID: String, replyLimit: Int) async throws -> MissCatNoteThread

    func realtimeEvents(
        source: MissCatFeedSource,
        capturing noteIDs: [String]
    ) -> AsyncStream<MissCatRealtimeEvent>

    func perform(_ action: MissCatFeedAction) async throws
}

public enum MissCatFeedRepositoryError: LocalizedError, Equatable {
    case unsupportedSource
    case invalidInstance
    case invalidResponse
    case emptyResponse
    case http(Int, String)
    case rejectedAction
    case streamingUnavailable

    public var errorDescription: String? {
        switch self {
        case .unsupportedSource: "このフィードは取得できません。"
        case .invalidInstance: "インスタンスURLが正しくありません。"
        case .invalidResponse: "サーバーから不正な応答が返されました。"
        case .emptyResponse: "サーバーからノートを取得できませんでした。"
        case let .http(_, message): message
        case .rejectedAction: "操作を完了できませんでした。"
        case .streamingUnavailable: "リアルタイム接続を開始できませんでした。"
        }
    }
}

/// Account-scoped current Misskey REST adapter. The bundled MisskeyKit remains
/// isolated to streaming until that transport is migrated separately.
public final class MissCatMisskeyFeedRepository: MissCatFeedRepository {
    private let account: MissCatFeedSession
    private let urlSession: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let misskey: MisskeyKit

    public init(session: MissCatFeedSession, urlSession: URLSession = .shared) {
        account = session
        self.urlSession = urlSession
        misskey = MisskeyKit(instance: session.instance, apiKey: session.apiKey)
    }

    convenience init?(user: SecureUser) {
        guard let apiKey = user.apiKey else { return nil }
        self.init(
            session: MissCatFeedSession(
                accountID: user.userId,
                username: user.username,
                instance: user.instance,
                apiKey: apiKey
            )
        )
    }

    public func fetchPage(
        source: MissCatFeedSource,
        cursor: String?,
        limit: Int
    ) async throws -> MissCatFeedPage {
        let boundedLimit = min(max(limit, 1), 100)

        if source == .favorites {
            let favorites: [FeedFavoriteDTO] = try await post(
                "i/favorites",
                body: FeedPageRequest(i: account.apiKey, limit: boundedLimit, untilId: cursor)
            )
            return MissCatFeedPage(
                notes: favorites.map {
                    Self.convert($0.note, isFavorite: true, itemID: $0.id)
                },
                hasMore: favorites.count >= boundedLimit
            )
        }

        let notes: [FeedNoteDTO]
        switch source {
        case .home:
            notes = try await post(
                "notes/timeline",
                body: FeedPageRequest(i: account.apiKey, limit: boundedLimit, untilId: cursor)
            )
        case .local:
            notes = try await post(
                "notes/local-timeline",
                body: FeedPageRequest(i: account.apiKey, limit: boundedLimit, untilId: cursor)
            )
        case .social:
            notes = try await post(
                "notes/hybrid-timeline",
                body: FeedPageRequest(i: account.apiKey, limit: boundedLimit, untilId: cursor)
            )
        case .global:
            notes = try await post(
                "notes/global-timeline",
                body: FeedPageRequest(i: account.apiKey, limit: boundedLimit, untilId: cursor)
            )
        case let .search(query):
            notes = try await post(
                "notes/search",
                body: FeedSearchRequest(
                    i: account.apiKey,
                    query: query,
                    limit: boundedLimit,
                    untilId: cursor
                )
            )
        case let .hashtag(tag):
            notes = try await post(
                "notes/search-by-tag",
                body: FeedTagRequest(
                    i: account.apiKey,
                    tag: tag,
                    limit: boundedLimit,
                    untilId: cursor
                )
            )
        case .favorites:
            preconditionFailure("Favorites are handled before the source switch")
        case .noteDetail:
            throw MissCatFeedRepositoryError.unsupportedSource
        }

        return MissCatFeedPage(
            notes: notes.map { Self.convert($0) },
            hasMore: notes.count >= boundedLimit
        )
    }

    public func fetchThread(noteID: String, replyLimit: Int) async throws -> MissCatNoteThread {
        let root: FeedNoteDTO = try await post(
            "notes/show",
            body: FeedNoteRequest(i: account.apiKey, noteId: noteID)
        )

        var ancestors: [FeedNoteDTO] = []
        var visited = Set([noteID])
        var replyID = root.replyId

        // Preserve the legacy parent walk while protecting malformed cycles.
        while let currentID = replyID,
              !currentID.isEmpty,
              !visited.contains(currentID),
              ancestors.count < 64 {
            visited.insert(currentID)
            let parent: FeedNoteDTO = try await post(
                "notes/show",
                body: FeedNoteRequest(i: account.apiKey, noteId: currentID)
            )
            ancestors.append(parent)
            replyID = parent.replyId
        }

        let boundedLimit = min(max(replyLimit, 1), 100)
        let replies: [FeedNoteDTO] = try await post(
            "notes/children",
            body: FeedChildrenRequest(i: account.apiKey, noteId: noteID, limit: boundedLimit)
        )

        return MissCatNoteThread(
            ancestors: ancestors.reversed().map { Self.convert($0) },
            note: Self.convert(root),
            replies: replies.map { Self.convert($0) }
        )
    }

    public func realtimeEvents(
        source: MissCatFeedSource,
        capturing noteIDs: [String]
    ) -> AsyncStream<MissCatRealtimeEvent> {
        guard let channel = Self.channel(for: source) else {
            return AsyncStream { $0.finish() }
        }

        let misskey = self.misskey
        let account = self.account
        let initialIDs = Set(noteIDs)

        return AsyncStream { continuation in
            let connected = misskey.streaming.connect(apiKey: account.apiKey, channels: [channel]) {
                response,
                responseChannel,
                responseType,
                error in
                if let error {
                    continuation.yield(.failed(message: error.localizedDescription))
                    continuation.yield(.connected(false))
                    return
                }

                if responseType == "onConnect" {
                    continuation.yield(.connected(true))
                    initialIDs.forEach { try? misskey.streaming.captureNote(noteId: $0) }
                    return
                }

                if responseChannel == .CapturedNoteUpdated, let update = response as? NoteUpdatedModel {
                    guard let noteID = update.targetNoteId else { return }
                    switch update.type {
                    case .reacted:
                        guard let reaction = update.reaction else { return }
                        continuation.yield(
                            .reaction(
                                noteID: noteID,
                                reaction: reaction,
                                delta: 1,
                                isMine: update.userId == account.accountID
                            )
                        )
                    case .unreacted:
                        guard let reaction = update.reaction else { return }
                        continuation.yield(
                            .reaction(
                                noteID: noteID,
                                reaction: reaction,
                                delta: -1,
                                isMine: update.userId == account.accountID
                            )
                        )
                    case .pollVoted:
                        if let choice = update.choice {
                            continuation.yield(.pollVote(noteID: noteID, choice: choice))
                        }
                    case .deleted:
                        continuation.yield(.removed(noteID: noteID))
                    case .none:
                        break
                    }
                    return
                }

                // Current REST DTOs intentionally do not depend on MisskeyKit's
                // 2019 NoteModel. Streaming compatibility is audited separately.
                guard let model = response as? NoteModel else { return }
                let converted = Self.convertLegacyStreamingNote(model)
                try? misskey.streaming.captureNote(noteId: converted.noteID)
                continuation.yield(.inserted(converted))
            }

            guard connected else {
                continuation.yield(.failed(message: MissCatFeedRepositoryError.streamingUnavailable.localizedDescription))
                continuation.finish()
                return
            }

            continuation.onTermination = { _ in
                misskey.streaming.disconnect()
            }
        }
    }

    public func perform(_ action: MissCatFeedAction) async throws {
        switch action {
        case let .favorite(noteID):
            try await postWrite(
                "notes/favorites/create",
                body: FeedNoteRequest(i: account.apiKey, noteId: noteID)
            )
        case let .unfavorite(noteID):
            try await postWrite(
                "notes/favorites/delete",
                body: FeedNoteRequest(i: account.apiKey, noteId: noteID)
            )
        case let .addReaction(noteID, reaction):
            try await postWrite(
                "notes/reactions/create",
                body: FeedReactionRequest(i: account.apiKey, noteId: noteID, reaction: reaction)
            )
        case let .removeReaction(noteID):
            try await postWrite(
                "notes/reactions/delete",
                body: FeedNoteRequest(i: account.apiKey, noteId: noteID)
            )
        case let .renote(noteID):
            // notes/create returns { createdNote }, but a successful 2xx is the
            // write acknowledgement. Decoding after the write could falsely
            // report failure and make a retry create a duplicate renote.
            try await postWrite(
                "notes/create",
                body: FeedRenoteRequest(i: account.apiKey, renoteId: noteID)
            )
        case let .vote(noteID, choice):
            try await postWrite(
                "notes/polls/vote",
                body: FeedVoteRequest(i: account.apiKey, noteId: noteID, choice: choice)
            )
        }
    }

    private func post<Request: Encodable, Response: Decodable>(
        _ path: String,
        body: Request
    ) async throws -> Response {
        let (data, response) = try await send(path, body: body)
        try validate(response, data: data)
        guard !data.isEmpty else { throw MissCatFeedRepositoryError.emptyResponse }
        return try decoder.decode(Response.self, from: data)
    }

    private func postWrite<Request: Encodable>(_ path: String, body: Request) async throws {
        let (data, response) = try await send(path, body: body)
        try validate(response, data: data)
    }

    private func send<Request: Encodable>(
        _ path: String,
        body: Request
    ) async throws -> (Data, URLResponse) {
        var request = try makeRequest(path: path)
        request.httpBody = try encoder.encode(body)
        return try await urlSession.data(for: request)
    }

    private func makeRequest(path: String) throws -> URLRequest {
        let raw = account.instance.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { throw MissCatFeedRepositoryError.invalidInstance }
        let normalized = raw.contains("://") ? raw : "https://\(raw)"
        guard let instanceURL = URL(string: normalized),
              let scheme = instanceURL.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            throw MissCatFeedRepositoryError.invalidInstance
        }

        let apiURL = instanceURL
            .appendingPathComponent("api", isDirectory: true)
            .appendingPathComponent(path)
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("MissCat/SwiftUI", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw MissCatFeedRepositoryError.invalidResponse
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            let envelope = try? decoder.decode(FeedAPIErrorEnvelope.self, from: data)
            let message = envelope?.error.message
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw MissCatFeedRepositoryError.http(http.statusCode, message)
        }
    }

    private static func channel(for source: MissCatFeedSource) -> SentStreamModel.Channel? {
        switch source {
        case .home: .homeTimeline
        case .local: .localTimeline
        case .social: .hybridTimeline
        case .global: .globalTimeline
        case .favorites, .search, .hashtag, .noteDetail: nil
        }
    }

    private static func convert(
        _ outer: FeedNoteDTO,
        isFavorite: Bool = false,
        itemID: String? = nil
    ) -> MissCatNote {
        let isPureRenote = outer.renote != nil && (outer.text ?? "").isEmpty
        let content = isPureRenote ? (outer.renote ?? outer) : outer
        let myReaction = content.myReaction
        let reactions = (content.reactions ?? [:])
            .map { name, count in
                MissCatReaction(name: name, count: count, isMine: name == myReaction)
            }
            .sorted { $0.name < $1.name }

        let quote: MissCatQuotedNote?
        if !isPureRenote, let quoted = outer.renote {
            quote = MissCatQuotedNote(
                noteID: quoted.id,
                author: convert(quoted.user),
                text: quoted.text ?? "",
                cw: nonEmpty(quoted.cw),
                attachments: convert(quoted.files)
            )
        } else {
            quote = nil
        }

        let poll = content.poll.map {
            MissCatPoll(
                choices: $0.choices.enumerated().map { index, choice in
                    MissCatFeedPollChoice(
                        id: index,
                        text: choice.text,
                        votes: choice.votes,
                        isVoted: choice.isVoted
                    )
                },
                allowsMultipleChoices: $0.multiple,
                expiresAt: parseDate($0.expiresAt)
            )
        }

        return MissCatNote(
            id: itemID ?? outer.id,
            noteID: content.id,
            author: convert(content.user),
            createdAt: parseDate(content.createdAt),
            text: content.text ?? "",
            cw: nonEmpty(content.cw),
            visibility: content.visibility,
            attachments: convert(content.files),
            reactions: reactions,
            repliesCount: content.repliesCount,
            renoteCount: content.renoteCount,
            replyID: nonEmpty(content.replyId),
            tags: content.tags ?? [],
            myReaction: myReaction,
            isFavorite: isFavorite,
            poll: poll,
            quotedNote: quote,
            renotedBy: isPureRenote ? convert(outer.user) : nil
        )
    }

    private static func convert(_ model: FeedUserDTO) -> MissCatNoteAuthor {
        MissCatNoteAuthor(
            id: model.id,
            name: nonEmpty(model.name) ?? model.username,
            username: model.username,
            host: nonEmpty(model.host),
            avatarURL: model.avatarUrl.flatMap(URL.init(string:)),
            isCat: model.isCat ?? false
        )
    }

    private static func convert(_ models: [FeedFileDTO]?) -> [MissCatNoteAttachment] {
        (models ?? []).map { model in
            let type = model.type.lowercased()
            let kind: MissCatAttachmentKind
            if type == "image/gif" || type == "image/apng" {
                kind = .animatedImage
            } else if type.hasPrefix("image/") {
                kind = .image
            } else if type.hasPrefix("video/") {
                kind = .video
            } else if type.hasPrefix("audio/") {
                kind = .audio
            } else {
                kind = .other
            }
            return MissCatNoteAttachment(
                id: model.id,
                name: model.name,
                kind: kind,
                url: URL(string: model.url),
                thumbnailURL: model.thumbnailUrl.flatMap(URL.init(string:)),
                isSensitive: model.isSensitive,
                width: model.properties?.width,
                height: model.properties?.height
            )
        }
    }

    private static func convertLegacyStreamingNote(_ outer: NoteModel) -> MissCatNote {
        let isPureRenote = outer.renote != nil && (outer.text ?? "").isEmpty
        let content = isPureRenote ? (outer.renote ?? outer) : outer
        let myReaction = content.myReaction
        let reactions = (content.reactions ?? []).compactMap { reaction -> MissCatReaction? in
            guard let reaction, let name = reaction.name else { return nil }
            return MissCatReaction(
                name: name,
                count: Int(reaction.count ?? "0") ?? 0,
                isMine: name == myReaction
            )
        }

        let quote: MissCatQuotedNote?
        if !isPureRenote, let quoted = outer.renote, let quotedID = quoted.id {
            quote = MissCatQuotedNote(
                noteID: quotedID,
                author: convertLegacyStreamingUser(quoted.user),
                text: quoted.text ?? "",
                cw: nonEmpty(quoted.cw),
                attachments: convertLegacyStreamingFiles(quoted.files)
            )
        } else {
            quote = nil
        }

        let poll: MissCatPoll?
        if let sourcePoll = content.poll {
            poll = MissCatPoll(
                choices: (sourcePoll.choices ?? []).enumerated().compactMap { index, choice in
                    guard let choice else { return nil }
                    return MissCatFeedPollChoice(
                        id: index,
                        text: choice.text ?? "",
                        votes: choice.votes ?? 0,
                        isVoted: choice.isVoted ?? false
                    )
                },
                allowsMultipleChoices: sourcePoll.multiple ?? false,
                expiresAt: parseDate(sourcePoll.expiresAt)
            )
        } else {
            poll = nil
        }

        let itemID = outer.id ?? content.id ?? UUID().uuidString
        let canonicalID = content.id ?? itemID
        return MissCatNote(
            id: itemID,
            noteID: canonicalID,
            author: convertLegacyStreamingUser(content.user),
            createdAt: parseDate(content.createdAt),
            text: content.text ?? "",
            cw: nonEmpty(content.cw),
            visibility: content.visibility?.rawValue ?? "public",
            attachments: convertLegacyStreamingFiles(content.files),
            reactions: reactions,
            repliesCount: content.repliesCount ?? 0,
            renoteCount: content.renoteCount ?? 0,
            replyID: nonEmpty(content.replyId),
            tags: content.tags ?? [],
            myReaction: myReaction,
            isFavorite: false,
            poll: poll,
            quotedNote: quote,
            renotedBy: isPureRenote ? convertLegacyStreamingUser(outer.user) : nil
        )
    }

    private static func convertLegacyStreamingUser(_ model: UserModel?) -> MissCatNoteAuthor {
        guard let model else {
            return MissCatNoteAuthor(id: "unknown", name: "Unknown", username: "unknown")
        }
        return MissCatNoteAuthor(
            id: model.id,
            name: nonEmpty(model.name) ?? model.username ?? "Unknown",
            username: model.username ?? "unknown",
            host: nonEmpty(model.host),
            avatarURL: URL(string: model.avatarUrl ?? ""),
            isCat: model.isCat ?? false
        )
    }

    private static func convertLegacyStreamingFiles(_ models: [File?]?) -> [MissCatNoteAttachment] {
        (models ?? []).compactMap { model in
            guard let model, let id = model.id else { return nil }
            let type = model.type?.lowercased() ?? ""
            let kind: MissCatAttachmentKind
            if type == "image/gif" || type == "image/apng" {
                kind = .animatedImage
            } else if type.hasPrefix("image/") {
                kind = .image
            } else if type.hasPrefix("video/") {
                kind = .video
            } else if type.hasPrefix("audio/") {
                kind = .audio
            } else {
                kind = .other
            }
            return MissCatNoteAttachment(
                id: id,
                name: model.name ?? "",
                kind: kind,
                url: URL(string: model.url ?? ""),
                thumbnailURL: URL(string: model.thumbnailUrl ?? ""),
                isSensitive: model.isSensitive ?? false,
                width: model.properties?.width,
                height: model.properties?.height
            )
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        if let date = fractionalDateFormatter.date(from: value) { return date }
        return basicDateFormatter.date(from: value)
    }

    private static let fractionalDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let basicDateFormatter = ISO8601DateFormatter()
}

private struct FeedPageRequest: Encodable {
    let i: String
    let limit: Int
    let untilId: String?
}

private struct FeedSearchRequest: Encodable {
    let i: String
    let query: String
    let limit: Int
    let untilId: String?
}

private struct FeedTagRequest: Encodable {
    let i: String
    let tag: String
    let limit: Int
    let untilId: String?
}

private struct FeedNoteRequest: Encodable {
    let i: String
    let noteId: String
}

private struct FeedChildrenRequest: Encodable {
    let i: String
    let noteId: String
    let limit: Int
}

private struct FeedReactionRequest: Encodable {
    let i: String
    let noteId: String
    let reaction: String
}

private struct FeedRenoteRequest: Encodable {
    let i: String
    let renoteId: String
}

private struct FeedVoteRequest: Encodable {
    let i: String
    let noteId: String
    let choice: Int
}

private struct FeedFavoriteDTO: Decodable {
    let id: String
    let createdAt: String
    let noteId: String
    let note: FeedNoteDTO
}

private final class FeedNoteDTO: Decodable {
    let id: String
    let createdAt: String
    let text: String?
    let cw: String?
    let user: FeedUserDTO
    let replyId: String?
    let renote: FeedNoteDTO?
    let visibility: String
    let files: [FeedFileDTO]?
    let tags: [String]?
    let poll: FeedPollDTO?
    let emojis: [String: String]?
    let reactions: [String: Int]?
    let renoteCount: Int
    let repliesCount: Int
    let myReaction: String?

    enum CodingKeys: String, CodingKey {
        case id, createdAt, text, cw, user, replyId, renote, visibility
        case files, tags, poll, emojis, reactions, renoteCount, repliesCount, myReaction
    }

    required init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        createdAt = try values.decode(String.self, forKey: .createdAt)
        text = try values.decodeIfPresent(String.self, forKey: .text)
        cw = try values.decodeIfPresent(String.self, forKey: .cw)
        user = try values.decode(FeedUserDTO.self, forKey: .user)
        replyId = try values.decodeIfPresent(String.self, forKey: .replyId)
        renote = try values.decodeIfPresent(FeedNoteDTO.self, forKey: .renote)
        visibility = try values.decodeIfPresent(String.self, forKey: .visibility) ?? "public"
        files = try values.decodeIfPresent([FeedFileDTO].self, forKey: .files)
        tags = try values.decodeIfPresent([String].self, forKey: .tags)
        poll = try values.decodeIfPresent(FeedPollDTO.self, forKey: .poll)
        emojis = try values.decodeIfPresent([String: String].self, forKey: .emojis)
        reactions = try values.decodeIfPresent([String: Int].self, forKey: .reactions)
        renoteCount = try values.decodeIfPresent(Int.self, forKey: .renoteCount) ?? 0
        repliesCount = try values.decodeIfPresent(Int.self, forKey: .repliesCount) ?? 0
        myReaction = try values.decodeIfPresent(String.self, forKey: .myReaction)
    }
}

private struct FeedUserDTO: Decodable {
    let id: String
    let name: String?
    let username: String
    let host: String?
    let avatarUrl: String?
    let isCat: Bool?
    // Modern Misskey exposes this as a dictionary, not the legacy array model.
    let emojis: [String: String]?
}

private struct FeedFileDTO: Decodable {
    struct Properties: Decodable {
        let width: Int?
        let height: Int?
    }

    let id: String
    let name: String
    let type: String
    let url: String
    let thumbnailUrl: String?
    let isSensitive: Bool
    let properties: Properties?
}

private struct FeedPollDTO: Decodable {
    struct Choice: Decodable {
        let isVoted: Bool
        let text: String
        let votes: Int
    }

    let expiresAt: String?
    let multiple: Bool
    let choices: [Choice]
}

private struct FeedAPIErrorEnvelope: Decodable {
    struct APIError: Decodable {
        let message: String
    }

    let error: APIError
}
