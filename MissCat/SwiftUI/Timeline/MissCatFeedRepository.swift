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
    case emptyResponse
    case rejectedAction
    case streamingUnavailable

    public var errorDescription: String? {
        switch self {
        case .unsupportedSource: "このフィードは取得できません。"
        case .emptyResponse: "サーバーからノートを取得できませんでした。"
        case .rejectedAction: "操作を完了できませんでした。"
        case .streamingUnavailable: "リアルタイム接続を開始できませんでした。"
        }
    }
}

/// Live adapter for the app's bundled MisskeyKit. SwiftUI views only depend on
/// `MissCatFeedRepository`, so API changes and account switching stay isolated here.
public final class MissCatMisskeyFeedRepository: MissCatFeedRepository {
    private let session: MissCatFeedSession
    private let misskey: MisskeyKit

    public init(session: MissCatFeedSession) {
        self.session = session
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
        let cursor = cursor ?? ""
        let models: [NoteModel]

        switch source {
        case .home:
            models = try await notes { callback in
                self.misskey.notes.getTimeline(limit: limit, untilId: cursor, completion: callback)
            }
        case .local:
            models = try await notes { callback in
                // The legacy screen included sensitive local media; keep that behavior.
                self.misskey.notes.getLocalTimeline(
                    excludeNsfw: false,
                    limit: limit,
                    untilId: cursor,
                    completion: callback
                )
            }
        case .social:
            models = try await notes { callback in
                self.misskey.notes.getHybridTimeline(limit: limit, untilId: cursor, completion: callback)
            }
        case .global:
            models = try await notes { callback in
                self.misskey.notes.getGlobalTimeline(limit: limit, untilId: cursor, completion: callback)
            }
        case .favorites:
            models = try await notes { callback in
                self.misskey.users.getAllFavorites(limit: limit, untilId: cursor, completion: callback)
            }
        case let .search(query):
            models = try await notes { callback in
                self.misskey.search.notes(query: query, limit: limit, untilId: cursor, result: callback)
            }
        case let .hashtag(tag):
            models = try await notes { callback in
                self.misskey.search.notesByTag(tag: tag, limit: limit, untilId: cursor, completion: callback)
            }
        case .noteDetail:
            throw MissCatFeedRepositoryError.unsupportedSource
        }

        let favorited = source == .favorites
        return MissCatFeedPage(
            notes: models.map { Self.convert($0, isFavorite: favorited) },
            hasMore: models.count >= limit
        )
    }

    public func fetchThread(noteID: String, replyLimit: Int) async throws -> MissCatNoteThread {
        let root = try await note { callback in
            self.misskey.notes.showNote(noteId: noteID, result: callback)
        }

        var ancestors: [NoteModel] = []
        var visited = Set([noteID])
        var replyID = root.replyId

        // Match the legacy recursive parent walk while protecting malformed cycles.
        while let currentID = replyID, !currentID.isEmpty, !visited.contains(currentID), ancestors.count < 64 {
            visited.insert(currentID)
            let parent = try await note { callback in
                self.misskey.notes.showNote(noteId: currentID, result: callback)
            }
            ancestors.append(parent)
            replyID = parent.replyId
        }

        let replies = try await notes { callback in
            self.misskey.notes.getChildren(noteId: noteID, limit: replyLimit, result: callback)
        }

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
        let session = self.session
        let initialIDs = Set(noteIDs)

        return AsyncStream { continuation in
            let connected = misskey.streaming.connect(apiKey: session.apiKey, channels: [channel]) {
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
                                isMine: update.userId == session.accountID
                            )
                        )
                    case .unreacted:
                        guard let reaction = update.reaction else { return }
                        continuation.yield(
                            .reaction(
                                noteID: noteID,
                                reaction: reaction,
                                delta: -1,
                                isMine: update.userId == session.accountID
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

                guard let model = response as? NoteModel else { return }
                let converted = Self.convert(model)
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
            try await boolean { self.misskey.notes.createFavorite(noteId: noteID, result: $0) }
        case let .unfavorite(noteID):
            try await boolean { self.misskey.notes.deleteFavorite(noteId: noteID, result: $0) }
        case let .addReaction(noteID, reaction):
            try await boolean {
                self.misskey.notes.createReaction(noteId: noteID, reaction: reaction, result: $0)
            }
        case let .removeReaction(noteID):
            try await boolean { self.misskey.notes.deleteReaction(noteId: noteID, result: $0) }
        case let .renote(noteID):
            _ = try await note { self.misskey.notes.renote(renoteId: noteID, completion: $0) }
        case let .vote(noteID, choice):
            try await boolean { self.misskey.notes.vote(noteId: noteID, choice: choice, result: $0) }
        }
    }

    private func notes(
        _ request: (@escaping NotesCallBack) -> Void
    ) async throws -> [NoteModel] {
        try await withCheckedThrowingContinuation { continuation in
            request { models, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: models ?? [])
                }
            }
        }
    }

    private func note(
        _ request: (@escaping OneNoteCallBack) -> Void
    ) async throws -> NoteModel {
        try await withCheckedThrowingContinuation { continuation in
            request { model, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let model {
                    continuation.resume(returning: model)
                } else {
                    continuation.resume(throwing: MissCatFeedRepositoryError.emptyResponse)
                }
            }
        }
    }

    private func boolean(
        _ request: (@escaping BooleanCallBack) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            request { succeeded, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if succeeded {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: MissCatFeedRepositoryError.rejectedAction)
                }
            }
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

    private static func convert(_ outer: NoteModel, isFavorite: Bool = false) -> MissCatNote {
        let isPureRenote = outer.renote != nil && (outer.text ?? "").isEmpty
        let content = isPureRenote ? (outer.renote ?? outer) : outer
        let author = convert(content.user)
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
                author: convert(quoted.user),
                text: quoted.text ?? "",
                cw: nonEmpty(quoted.cw),
                attachments: convert(quoted.files)
            )
        } else {
            quote = nil
        }

        let poll: MissCatPoll?
        if let sourcePoll = content.poll {
            poll = MissCatPoll(
                choices: (sourcePoll.choices ?? []).enumerated().compactMap { index, choice in
                    guard let choice else { return nil }
                    return MissCatPollChoice(
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
            author: author,
            createdAt: parseDate(content.createdAt),
            text: content.text ?? "",
            cw: nonEmpty(content.cw),
            visibility: content.visibility?.rawValue ?? "public",
            attachments: convert(content.files),
            reactions: reactions,
            repliesCount: content.repliesCount ?? 0,
            renoteCount: content.renoteCount ?? 0,
            replyID: nonEmpty(content.replyId),
            tags: content.tags ?? [],
            myReaction: myReaction,
            isFavorite: isFavorite,
            poll: poll,
            quotedNote: quote,
            renotedBy: isPureRenote ? convert(outer.user) : nil
        )
    }

    private static func convert(_ model: UserModel?) -> MissCatNoteAuthor {
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

    private static func convert(_ models: [File?]?) -> [MissCatNoteAttachment] {
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
