import Foundation

public protocol MissCatFeedRepository: AnyObject, Sendable {
    func fetchPage(
        source: MissCatFeedSource,
        cursor: String?,
        limit: Int
    ) async throws -> MissCatFeedPage

    func fetchThread(noteID: String, replyLimit: Int) async throws -> MissCatNoteThread

    func fetchReplies(noteID: String, cursor: String?, limit: Int) async throws -> MissCatNoteRepliesPage

    func realtimeEvents(
        source: MissCatFeedSource,
        capturing noteIDs: [String]
    ) -> AsyncStream<MissCatRealtimeEvent>

    func perform(_ action: MissCatFeedAction) async throws
}

public extension MissCatFeedRepository {
    func fetchReplies(noteID: String, cursor: String?, limit: Int) async throws -> MissCatNoteRepliesPage {
        guard cursor == nil else {
            return MissCatNoteRepliesPage(replies: [], nextCursor: nil, hasMore: false)
        }
        let thread = try await fetchThread(noteID: noteID, replyLimit: limit)
        return MissCatNoteRepliesPage(
            replies: thread.replies,
            nextCursor: thread.repliesCursor,
            hasMore: thread.hasMoreReplies
        )
    }
}

public enum MissCatFeedRepositoryError: LocalizedError, Equatable {
    case unsupportedSource
    case invalidInstance
    case invalidResponse
    case emptyResponse
    case http(Int, String)
    case rejectedAction
    case invalidReportComment
    case streamingUnavailable

    public var errorDescription: String? {
        switch self {
        case .unsupportedSource: "このフィードは取得できません。"
        case .invalidInstance: "インスタンスURLが正しくありません。"
        case .invalidResponse: "サーバーから不正な応答が返されました。"
        case .emptyResponse: "サーバーからノートを取得できませんでした。"
        case let .http(_, message): message
        case .rejectedAction: "操作を完了できませんでした。"
        case .invalidReportComment: "通報理由は1〜2048文字で入力してください。"
        case .streamingUnavailable: "リアルタイム接続を開始できませんでした。"
        }
    }
}

protocol MissCatFeedWebSocket: AnyObject, Sendable {
    func resume()
    func send(_ message: URLSessionWebSocketTask.Message) async throws
    func receive() async throws -> URLSessionWebSocketTask.Message
    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?)
}

extension URLSessionWebSocketTask: MissCatFeedWebSocket {}

protocol MissCatFeedWebSocketFactory: AnyObject, Sendable {
    func makeWebSocket(request: URLRequest) -> any MissCatFeedWebSocket
}

private final class MissCatURLSessionFeedWebSocketFactory: MissCatFeedWebSocketFactory {
    private let urlSession: URLSession

    init(urlSession: URLSession) {
        self.urlSession = urlSession
    }

    func makeWebSocket(request: URLRequest) -> any MissCatFeedWebSocket {
        urlSession.webSocketTask(with: request)
    }
}

struct MissCatFeedRealtimeConfiguration: Equatable, Sendable {
    let maximumReconnectAttempts: Int
    let baseReconnectDelayNanoseconds: UInt64
    let maximumReconnectDelayNanoseconds: UInt64
    let resynchronizationLimit: Int

    init(
        maximumReconnectAttempts: Int = 6,
        baseReconnectDelayNanoseconds: UInt64 = 500_000_000,
        maximumReconnectDelayNanoseconds: UInt64 = 30_000_000_000,
        resynchronizationLimit: Int = 100
    ) {
        self.maximumReconnectAttempts = max(0, maximumReconnectAttempts)
        self.baseReconnectDelayNanoseconds = baseReconnectDelayNanoseconds
        self.maximumReconnectDelayNanoseconds = max(
            baseReconnectDelayNanoseconds,
            maximumReconnectDelayNanoseconds
        )
        self.resynchronizationLimit = min(max(resynchronizationLimit, 1), 100)
    }

    func reconnectDelayNanoseconds(forAttempt attempt: Int) -> UInt64 {
        let exponent = min(max(attempt - 1, 0), 63)
        let multiplier = UInt64(1) << UInt64(exponent)
        let (delay, overflow) = baseReconnectDelayNanoseconds.multipliedReportingOverflow(by: multiplier)
        return min(overflow ? UInt64.max : delay, maximumReconnectDelayNanoseconds)
    }

    static let live = MissCatFeedRealtimeConfiguration()
}

typealias MissCatFeedReconnectSleep = @Sendable (UInt64) async throws -> Void

/// Account-scoped current Misskey REST and native WebSocket adapter.
public final class MissCatMisskeyFeedRepository: MissCatNoteContextRepository, Sendable {
    private let account: MissCatFeedSession
    private let urlSession: URLSession
    private let webSocketFactory: any MissCatFeedWebSocketFactory
    private let realtimeConfiguration: MissCatFeedRealtimeConfiguration
    private let makeStreamID: @Sendable () -> String
    private let reconnectSleep: MissCatFeedReconnectSleep

    public convenience init(session: MissCatFeedSession, urlSession: URLSession = .shared) {
        self.init(
            session: session,
            urlSession: urlSession,
            webSocketFactory: MissCatURLSessionFeedWebSocketFactory(urlSession: urlSession)
        )
    }

    init(
        session: MissCatFeedSession,
        urlSession: URLSession = .shared,
        webSocketFactory: any MissCatFeedWebSocketFactory,
        realtimeConfiguration: MissCatFeedRealtimeConfiguration = .live,
        makeStreamID: @escaping @Sendable () -> String = { UUID().uuidString },
        reconnectSleep: @escaping MissCatFeedReconnectSleep = { nanoseconds in
            try await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        account = session
        self.urlSession = urlSession
        self.webSocketFactory = webSocketFactory
        self.realtimeConfiguration = realtimeConfiguration
        self.makeStreamID = makeStreamID
        self.reconnectSleep = reconnectSleep
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
                    Self.convert(
                        $0.note,
                        isFavorite: true,
                        itemID: $0.id,
                        instanceOrigin: account.instanceOrigin
                    )
                },
                hasMore: favorites.count >= boundedLimit
            )
        }

        let notes: [FeedNoteDTO]
        switch source {
        case .home:
            notes = try await post(
                "notes/timeline",
                body: FeedTimelinePageRequest(
                    i: account.apiKey,
                    limit: boundedLimit,
                    untilId: cursor,
                    allowPartial: false,
                    includeMyRenotes: true,
                    includeRenotedMyNotes: true,
                    includeLocalRenotes: true,
                    withFiles: false,
                    withRenotes: true
                )
            )
        case .local:
            notes = try await post(
                "notes/local-timeline",
                body: FeedTimelinePageRequest(
                    i: account.apiKey,
                    limit: boundedLimit,
                    untilId: cursor,
                    allowPartial: false,
                    withFiles: false,
                    withRenotes: true,
                    withReplies: false
                )
            )
        case .social:
            notes = try await post(
                "notes/hybrid-timeline",
                body: FeedTimelinePageRequest(
                    i: account.apiKey,
                    limit: boundedLimit,
                    untilId: cursor,
                    allowPartial: false,
                    includeMyRenotes: true,
                    includeRenotedMyNotes: true,
                    includeLocalRenotes: true,
                    withFiles: false,
                    withRenotes: true,
                    withReplies: false
                )
            )
        case .global:
            notes = try await post(
                "notes/global-timeline",
                body: FeedTimelinePageRequest(
                    i: account.apiKey,
                    limit: boundedLimit,
                    untilId: cursor,
                    withFiles: false,
                    withRenotes: true
                )
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
        case let .user(userID, includeReplies, withFiles):
            guard !(includeReplies && withFiles) else {
                throw MissCatFeedRepositoryError.unsupportedSource
            }
            notes = try await post(
                "users/notes",
                body: FeedUserTimelineRequest(
                    i: account.apiKey,
                    userId: userID,
                    withReplies: includeReplies,
                    withRenotes: true,
                    withFiles: withFiles,
                    limit: boundedLimit,
                    untilId: cursor
                )
            )
        case let .userList(listID):
            notes = try await post(
                "notes/user-list-timeline",
                body: FeedUserListTimelineRequest(
                    i: account.apiKey,
                    listId: listID,
                    limit: boundedLimit,
                    untilId: cursor,
                    allowPartial: true
                )
            )
        case .favorites:
            preconditionFailure("Favorites are handled before the source switch")
        case .noteDetail:
            throw MissCatFeedRepositoryError.unsupportedSource
        }

        return MissCatFeedPage(
            notes: notes.map { Self.convert($0, instanceOrigin: account.instanceOrigin) },
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
        let repliesPage = try await fetchReplies(noteID: noteID, cursor: nil, limit: boundedLimit)

        return MissCatNoteThread(
            ancestors: ancestors.reversed().map {
                Self.convert($0, instanceOrigin: account.instanceOrigin)
            },
            note: Self.convert(root, instanceOrigin: account.instanceOrigin),
            replies: repliesPage.replies,
            repliesCursor: repliesPage.nextCursor,
            hasMoreReplies: repliesPage.hasMore
        )
    }

    public func fetchReplies(
        noteID: String,
        cursor: String?,
        limit: Int
    ) async throws -> MissCatNoteRepliesPage {
        let boundedLimit = min(max(limit, 1), 100)
        // Misskey's official endpoint declares untilId as a pagination cursor:
        // https://github.com/misskey-dev/misskey/blob/00f66349766dc61298c66129ded5fdeb29e93f41/packages/backend/src/server/api/endpoints/notes/children.ts
        let replies: [FeedNoteDTO] = try await post(
            "notes/children",
            body: FeedChildrenRequest(
                i: account.apiKey,
                noteId: noteID,
                limit: boundedLimit,
                untilId: cursor
            )
        )
        let converted = replies.map { Self.convert($0, instanceOrigin: account.instanceOrigin) }
        return MissCatNoteRepliesPage(
            replies: converted,
            nextCursor: converted.last?.noteID,
            hasMore: replies.count >= boundedLimit
        )
    }

    public func realtimeEvents(
        source: MissCatFeedSource,
        capturing noteIDs: [String]
    ) -> AsyncStream<MissCatRealtimeEvent> {
        guard let channel = Self.channel(for: source) else {
            return AsyncStream { $0.finish() }
        }

        let request: URLRequest
        do {
            request = try makeStreamingRequest()
        } catch {
            return AsyncStream { continuation in
                continuation.yield(
                    .failed(message: MissCatFeedRepositoryError.streamingUnavailable.localizedDescription)
                )
                continuation.finish()
            }
        }

        let connection = MissCatFeedRealtimeConnection(
            request: request,
            channel: channel,
            streamID: makeStreamID(),
            accountID: account.accountID,
            instanceOrigin: account.instanceOrigin,
            initialNoteIDs: Set(noteIDs.filter { !$0.isEmpty }),
            webSocketFactory: webSocketFactory,
            configuration: realtimeConfiguration,
            reconnectSleep: reconnectSleep,
            resynchronize: { [weak self] limit in
                guard let self else { throw CancellationError() }
                return try await self.fetchPage(source: source, cursor: nil, limit: limit)
            }
        )

        return AsyncStream { continuation in
            let runner = Task {
                await connection.run(continuation: continuation)
            }

            continuation.onTermination = { _ in
                runner.cancel()
                Task { await connection.stop() }
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
        case let .delete(noteID):
            try await postWrite(
                "notes/delete",
                body: FeedNoteRequest(i: account.apiKey, noteId: noteID)
            )
        case let .mute(userID):
            try await postWrite(
                "mute/create",
                body: FeedUserRequest(i: account.apiKey, userId: userID)
            )
        case let .block(userID):
            try await postWrite(
                "blocking/create",
                body: FeedUserRequest(i: account.apiKey, userId: userID)
            )
        case let .report(userID, comment):
            guard let comment = MissCatReportComment.normalized(comment) else {
                throw MissCatFeedRepositoryError.invalidReportComment
            }
            try await postWrite(
                "users/report-abuse",
                body: FeedAbuseReportRequest(i: account.apiKey, userId: userID, comment: comment)
            )
        }
    }

    public var accountIdentifier: String { account.compositeAccountID }
    public var currentServerUserID: String { account.accountID }

    public func notePermalink(noteID: String) -> URL? {
        guard let origin = try? normalizedInstanceOrigin() else { return nil }
        return origin.appendingPathComponent("notes").appendingPathComponent(noteID)
    }

    public func resolveMention(_ acct: String) async throws -> String {
        let normalized = acct.trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        let components = normalized.split(separator: "@", maxSplits: 1).map(String.init)
        guard let username = components.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              !username.isEmpty else {
            throw MissCatMentionResolutionError.invalidAccount(acct)
        }

        let localHost = try normalizedInstanceOrigin().host?.lowercased()
        let suppliedHost = components.count == 2
            ? components[1].trimmingCharacters(in: .whitespacesAndNewlines)
            : nil
        let host = suppliedHost?.lowercased() == localHost ? nil : suppliedHost
        let user: FeedUserDTO = try await post(
            "users/show",
            body: FeedUserShowRequest(i: account.apiKey, username: username, host: host)
        )
        return user.id
    }

    public func fetchURLPreview(for url: URL) async throws -> MissCatURLPreview {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            throw MissCatURLPreviewError.unsupportedURL
        }
        let origin = try normalizedInstanceOrigin()
        guard var components = URLComponents(
            url: origin.appendingPathComponent("url"),
            resolvingAgainstBaseURL: false
        ) else { throw MissCatURLPreviewError.invalidInstance }
        components.queryItems = [URLQueryItem(name: "url", value: url.absoluteString)]
        guard let endpoint = components.url else { throw MissCatURLPreviewError.invalidInstance }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("MissCat/SwiftUI", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MissCatURLPreviewError.invalidResponse
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw MissCatURLPreviewError.http(http.statusCode)
        }
        let dto: FeedURLPreviewDTO
        do {
            dto = try JSONDecoder().decode(FeedURLPreviewDTO.self, from: data)
        } catch {
            throw MissCatURLPreviewError.invalidResponse
        }
        let resolvedURL = dto.url.flatMap(URL.init(string:)) ?? url
        return MissCatURLPreview(
            sourceURL: url,
            resolvedURL: resolvedURL,
            title: dto.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? resolvedURL.host
                ?? url.absoluteString,
            description: dto.description ?? "",
            siteName: dto.sitename,
            imageURL: dto.thumbnail.flatMap(URL.init(string:)),
            isSensitive: dto.sensitive ?? false
        )
    }

    public func fetchReactionChoices() async throws -> [MissCatReactionChoice] {
        async let emojiResponse: FeedEmojisResponse = post(
            "emojis",
            body: FeedTokenRequest(i: account.apiKey)
        )
        async let meResponse: FeedMeRolesDTO = post(
            "i",
            body: FeedTokenRequest(i: account.apiKey)
        )
        let (emojiEnvelope, me) = try await (emojiResponse, meResponse)
        let roleIDs = Set((me.roles ?? []).map(\.id))

        return emojiEnvelope.emojis
            .filter { emoji in
                guard let restrictedRoleIDs = emoji.roleIdsThatCanBeUsedThisEmojiAsReaction,
                      !restrictedRoleIDs.isEmpty else { return true }
                return !roleIDs.isDisjoint(with: restrictedRoleIDs)
            }
            .compactMap { emoji in
                let emojiURL = MissCatEmojiURLResolver.resolvedURL(
                    explicitURL: emoji.url,
                    name: emoji.name,
                    instanceOrigin: account.instanceOrigin
                )
                guard let emojiURL else { return nil }
                return MissCatReactionChoice(
                    value: ":\(emoji.name):",
                    label: emoji.name,
                    emojiURL: emojiURL,
                    aliases: emoji.aliases,
                    category: emoji.category,
                    isLocalOnly: emoji.localOnly ?? false,
                    isSensitive: emoji.isSensitive ?? false
                )
            }
            .sorted { lhs, rhs in
                lhs.value.localizedStandardCompare(rhs.value) == .orderedAscending
            }
    }

    private func post<Request: Encodable, Response: Decodable>(
        _ path: String,
        body: Request
    ) async throws -> Response {
        let (data, response) = try await send(path, body: body)
        try validate(response, data: data)
        guard !data.isEmpty else { throw MissCatFeedRepositoryError.emptyResponse }
        return try JSONDecoder().decode(Response.self, from: data)
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
        request.httpBody = try JSONEncoder().encode(body)
        return try await urlSession.data(for: request)
    }

    private func makeRequest(path: String) throws -> URLRequest {
        guard let instanceURL = account.instanceOrigin else {
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

    private func normalizedInstanceOrigin() throws -> URL {
        guard let origin = account.instanceOrigin else {
            throw MissCatURLPreviewError.invalidInstance
        }
        return origin
    }

    private func makeStreamingRequest() throws -> URLRequest {
        guard let origin = account.instanceOrigin,
              var components = URLComponents(url: origin, resolvingAgainstBaseURL: false) else {
            throw MissCatFeedRepositoryError.invalidInstance
        }

        components.scheme = "wss"
        components.path = "/streaming"
        components.query = nil
        components.fragment = nil
        guard let url = components.url else {
            throw MissCatFeedRepositoryError.invalidInstance
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("Bearer \(account.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("MissCat/SwiftUI", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw MissCatFeedRepositoryError.invalidResponse
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            let envelope = try? JSONDecoder().decode(FeedAPIErrorEnvelope.self, from: data)
            let message = envelope?.error.message
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw MissCatFeedRepositoryError.http(http.statusCode, message)
        }
    }

    private static func channel(for source: MissCatFeedSource) -> String? {
        switch source {
        case .home: "homeTimeline"
        case .local: "localTimeline"
        case .social: "hybridTimeline"
        case .global: "globalTimeline"
        case .favorites, .search, .hashtag, .user, .userList, .noteDetail: nil
        }
    }

    fileprivate static func convert(
        _ outer: FeedNoteDTO,
        isFavorite: Bool = false,
        itemID: String? = nil,
        instanceOrigin: URL? = nil
    ) -> MissCatNote {
        let isPureRenote = outer.renote != nil && (outer.text ?? "").isEmpty
        let content = isPureRenote ? (outer.renote ?? outer) : outer
        let myReaction = content.myReaction
        let reactions = (content.reactions ?? [:])
            .map { name, count in
                MissCatReaction(
                    name: name,
                    count: count,
                    isMine: name == myReaction,
                    emojiURL: MissCatEmojiURLResolver.reactionURL(
                        for: name,
                        explicit: content.reactionEmojis,
                        instanceOrigin: instanceOrigin
                    )
                )
            }
            .sorted { $0.name < $1.name }

        let quote: MissCatQuotedNote?
        if !isPureRenote, let quoted = outer.renote {
            quote = MissCatQuotedNote(
                noteID: quoted.id,
                author: convert(quoted.user, instanceOrigin: instanceOrigin),
                text: quoted.text ?? "",
                cw: nonEmpty(quoted.cw),
                attachments: convert(quoted.files),
                emojis: MissCatEmojiURLResolver.mergedURLs(
                    explicit: quoted.emojis,
                    sources: [quoted.text, quoted.cw] + (quoted.poll?.choices.map(\.text) ?? []),
                    authorHost: quoted.user.host,
                    instanceOrigin: instanceOrigin
                )
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
            author: convert(content.user, instanceOrigin: instanceOrigin),
            createdAt: parseDate(content.createdAt),
            text: content.text ?? "",
            cw: nonEmpty(content.cw),
            visibility: content.visibility,
            reactionAcceptance: content.reactionAcceptance,
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
            renotedBy: isPureRenote
                ? convert(outer.user, instanceOrigin: instanceOrigin)
                : nil,
            emojis: MissCatEmojiURLResolver.mergedURLs(
                explicit: content.emojis,
                sources: [content.text, content.cw] + (content.poll?.choices.map(\.text) ?? []),
                authorHost: content.user.host,
                instanceOrigin: instanceOrigin
            )
        )
    }

    private static func convert(
        _ model: FeedUserDTO,
        instanceOrigin: URL? = nil
    ) -> MissCatNoteAuthor {
        MissCatNoteAuthor(
            id: model.id,
            name: nonEmpty(model.name) ?? model.username,
            username: model.username,
            host: nonEmpty(model.host),
            avatarURL: model.avatarUrl.flatMap(URL.init(string:)),
            isCat: model.isCat ?? false,
            emojis: MissCatEmojiURLResolver.mergedURLs(
                explicit: model.emojis,
                sources: [model.name],
                authorHost: model.host,
                instanceOrigin: instanceOrigin
            )
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

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }
}

private actor MissCatFeedRealtimeConnection {
    typealias Resynchronize = @Sendable (Int) async throws -> MissCatFeedPage

    private let request: URLRequest
    private let channel: String
    private let streamID: String
    private let accountID: String
    private let instanceOrigin: URL?
    private let webSocketFactory: any MissCatFeedWebSocketFactory
    private let configuration: MissCatFeedRealtimeConfiguration
    private let reconnectSleep: MissCatFeedReconnectSleep
    private let resynchronize: Resynchronize
    private let decoder = JSONDecoder()

    private var capturedNoteIDs: Set<String>
    private var activeSocket: (any MissCatFeedWebSocket)?
    private var activeGeneration = 0
    private var hasAcknowledgedConnection = false
    private var stopped = false

    init(
        request: URLRequest,
        channel: String,
        streamID: String,
        accountID: String,
        instanceOrigin: URL?,
        initialNoteIDs: Set<String>,
        webSocketFactory: any MissCatFeedWebSocketFactory,
        configuration: MissCatFeedRealtimeConfiguration,
        reconnectSleep: @escaping MissCatFeedReconnectSleep,
        resynchronize: @escaping Resynchronize
    ) {
        self.request = request
        self.channel = channel
        self.streamID = streamID
        self.accountID = accountID
        self.instanceOrigin = instanceOrigin
        capturedNoteIDs = initialNoteIDs
        self.webSocketFactory = webSocketFactory
        self.configuration = configuration
        self.reconnectSleep = reconnectSleep
        self.resynchronize = resynchronize
    }

    func run(continuation: AsyncStream<MissCatRealtimeEvent>.Continuation) async {
        var reconnectAttempt = 0

        while !stopped, !Task.isCancelled {
            activeGeneration += 1
            let generation = activeGeneration
            let socket = webSocketFactory.makeWebSocket(request: request)
            activeSocket = socket
            var acknowledged = false

            do {
                socket.resume()
                try await sendConnect(to: socket)

                while !stopped, !Task.isCancelled, isCurrent(socket, generation: generation) {
                    let message = try await socket.receive()
                    guard isCurrent(socket, generation: generation),
                          let envelope = Self.envelope(from: message) else { continue }

                    if !acknowledged {
                        guard Self.isAcknowledgement(envelope, streamID: streamID) else { continue }
                        acknowledged = true
                        reconnectAttempt = 0

                        try await subscribeToCapturedNotes(on: socket, generation: generation)
                        if hasAcknowledgedConnection {
                            do {
                                try await resynchronizeTimeline(
                                    on: socket,
                                    generation: generation,
                                    continuation: continuation
                                )
                                continuation.yield(.connected(true))
                            } catch is CancellationError {
                                throw CancellationError()
                            } catch {
                                continuation.yield(
                                    .failed(
                                        message: MissCatFeedRepositoryError.streamingUnavailable.localizedDescription
                                    )
                                )
                            }
                        } else {
                            hasAcknowledgedConnection = true
                            continuation.yield(.connected(true))
                        }
                        continue
                    }

                    try await handle(
                        envelope,
                        on: socket,
                        generation: generation,
                        continuation: continuation
                    )
                }
            } catch is CancellationError {
                break
            } catch {
                guard !stopped, !Task.isCancelled, isCurrent(socket, generation: generation) else {
                    break
                }

                activeSocket = nil
                socket.cancel(with: .goingAway, reason: nil)
                continuation.yield(.connected(false))
                reconnectAttempt += 1

                guard reconnectAttempt <= configuration.maximumReconnectAttempts else {
                    continuation.yield(
                        .failed(message: MissCatFeedRepositoryError.streamingUnavailable.localizedDescription)
                    )
                    continuation.finish()
                    return
                }

                let delay = configuration.reconnectDelayNanoseconds(forAttempt: reconnectAttempt)
                do {
                    try await reconnectSleep(delay)
                } catch {
                    break
                }
            }
        }

        continuation.finish()
    }

    func stop() async {
        guard !stopped else { return }
        stopped = true
        activeGeneration += 1
        guard let socket = activeSocket else { return }
        activeSocket = nil

        for noteID in capturedNoteIDs.sorted() {
            try? await sendUnsubscribe(noteID: noteID, to: socket)
        }
        try? await sendDisconnect(to: socket)
        socket.cancel(with: .goingAway, reason: nil)
    }

    private func handle(
        _ envelope: [String: Any],
        on socket: any MissCatFeedWebSocket,
        generation: Int,
        continuation: AsyncStream<MissCatRealtimeEvent>.Continuation
    ) async throws {
        guard let type = envelope["type"] as? String else { return }

        if type == "channel" {
            guard let body = envelope["body"] as? [String: Any],
                  body["id"] as? String == streamID,
                  body["type"] as? String == "note",
                  let noteObject = body["body"] as? [String: Any],
                  JSONSerialization.isValidJSONObject(noteObject),
                  isCurrent(socket, generation: generation) else { return }

            let data = try JSONSerialization.data(withJSONObject: noteObject)
            let noteDTO = try decoder.decode(FeedNoteDTO.self, from: data)
            let note = MissCatMisskeyFeedRepository.convert(
                noteDTO,
                instanceOrigin: instanceOrigin
            )
            for noteID in Self.identities(for: note) where capturedNoteIDs.insert(noteID).inserted {
                try await sendSubscribe(noteID: noteID, to: socket)
            }
            guard isCurrent(socket, generation: generation) else { return }
            continuation.yield(.inserted(note))
            return
        }

        guard type == "noteUpdated",
              let update = envelope["body"] as? [String: Any],
              let noteID = update["id"] as? String,
              capturedNoteIDs.contains(noteID),
              let updateType = update["type"] as? String,
              let updateBody = update["body"] as? [String: Any],
              isCurrent(socket, generation: generation) else { return }

        switch updateType {
        case "reacted", "unreacted":
            guard let reaction = updateBody["reaction"] as? String else { return }
            let userID = updateBody["userId"] as? String
            continuation.yield(
                .reaction(
                    noteID: noteID,
                    reaction: reaction,
                    delta: updateType == "reacted" ? 1 : -1,
                    isMine: userID == accountID
                )
            )
        case "pollVoted":
            guard let choice = updateBody["choice"] as? Int else { return }
            let userID = updateBody["userId"] as? String
            continuation.yield(
                .pollVote(noteID: noteID, choice: choice, isMine: userID == accountID)
            )
        case "deleted":
            guard updateBody["deletedAt"] as? String != nil else { return }
            continuation.yield(.removed(noteID: noteID))
        default:
            return
        }
    }

    private func resynchronizeTimeline(
        on socket: any MissCatFeedWebSocket,
        generation: Int,
        continuation: AsyncStream<MissCatRealtimeEvent>.Continuation
    ) async throws {
        let page = try await resynchronize(configuration.resynchronizationLimit)
        guard isCurrent(socket, generation: generation) else { return }

        // The store prepends inserts, so replay oldest-to-newest to preserve REST order.
        for note in page.notes.reversed() {
            guard isCurrent(socket, generation: generation) else { return }
            let noteIDs = Self.identities(for: note)
            let wasCaptured = noteIDs.contains { capturedNoteIDs.contains($0) }
            for noteID in noteIDs where capturedNoteIDs.insert(noteID).inserted {
                try await sendSubscribe(noteID: noteID, to: socket)
            }
            continuation.yield(wasCaptured ? .replaced(note) : .inserted(note))
        }
    }

    private static func identities(for note: MissCatNote) -> [String] {
        Array(Set([note.id, note.noteID])).sorted()
    }

    private func subscribeToCapturedNotes(
        on socket: any MissCatFeedWebSocket,
        generation: Int
    ) async throws {
        for noteID in capturedNoteIDs.sorted() {
            guard isCurrent(socket, generation: generation) else { return }
            try await sendSubscribe(noteID: noteID, to: socket)
        }
    }

    private func sendConnect(to socket: any MissCatFeedWebSocket) async throws {
        try await send(
            [
                "type": "connect",
                "body": [
                    "channel": channel,
                    "id": streamID,
                    "params": [String: Any](),
                    "pong": true,
                ] as [String: Any],
            ],
            to: socket
        )
    }

    private func sendSubscribe(noteID: String, to socket: any MissCatFeedWebSocket) async throws {
        try await send(
            ["type": "subNote", "body": ["id": noteID]],
            to: socket
        )
    }

    private func sendUnsubscribe(noteID: String, to socket: any MissCatFeedWebSocket) async throws {
        try await send(
            ["type": "unsubNote", "body": ["id": noteID]],
            to: socket
        )
    }

    private func sendDisconnect(to socket: any MissCatFeedWebSocket) async throws {
        try await send(
            ["type": "disconnect", "body": ["id": streamID]],
            to: socket
        )
    }

    private func send(
        _ object: [String: Any],
        to socket: any MissCatFeedWebSocket
    ) async throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        guard let text = String(data: data, encoding: .utf8) else {
            throw MissCatFeedRepositoryError.streamingUnavailable
        }
        try await socket.send(.string(text))
    }

    private func isCurrent(_ socket: any MissCatFeedWebSocket, generation: Int) -> Bool {
        guard !stopped,
              generation == activeGeneration,
              let activeSocket else { return false }
        return ObjectIdentifier(activeSocket) == ObjectIdentifier(socket)
    }

    private static func envelope(
        from message: URLSessionWebSocketTask.Message
    ) -> [String: Any]? {
        let data: Data
        switch message {
        case let .string(text):
            guard let encoded = text.data(using: .utf8) else { return nil }
            data = encoded
        case let .data(messageData):
            data = messageData
        @unknown default:
            return nil
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func isAcknowledgement(_ envelope: [String: Any], streamID: String) -> Bool {
        guard envelope["type"] as? String == "connected",
              let body = envelope["body"] as? [String: Any] else { return false }
        return body["id"] as? String == streamID
    }
}

private struct FeedTokenRequest: Encodable {
    let i: String
}

private struct FeedEmojisResponse: Decodable, Sendable {
    let emojis: [FeedEmojiDTO]
}

private struct FeedEmojiDTO: Decodable, Sendable {
    let name: String
    let aliases: [String]
    let category: String?
    let url: String?
    let localOnly: Bool?
    let isSensitive: Bool?
    let roleIdsThatCanBeUsedThisEmojiAsReaction: [String]?
}

private struct FeedMeRolesDTO: Decodable, Sendable {
    struct Role: Decodable, Sendable {
        let id: String
    }

    let roles: [Role]?
}

private struct FeedPageRequest: Encodable {
    let i: String
    let limit: Int
    let untilId: String?
}

/// Pins the ordinary timeline semantics instead of relying on server defaults
/// that have changed between Misskey releases. Unsupported keys remain absent
/// for endpoints whose current schema does not declare them.
private struct FeedTimelinePageRequest: Encodable {
    let i: String
    let limit: Int
    let untilId: String?
    let allowPartial: Bool?
    let includeMyRenotes: Bool?
    let includeRenotedMyNotes: Bool?
    let includeLocalRenotes: Bool?
    let withFiles: Bool?
    let withRenotes: Bool
    let withReplies: Bool?

    init(
        i: String,
        limit: Int,
        untilId: String?,
        allowPartial: Bool? = nil,
        includeMyRenotes: Bool? = nil,
        includeRenotedMyNotes: Bool? = nil,
        includeLocalRenotes: Bool? = nil,
        withFiles: Bool?,
        withRenotes: Bool,
        withReplies: Bool? = nil
    ) {
        self.i = i
        self.limit = limit
        self.untilId = untilId
        self.allowPartial = allowPartial
        self.includeMyRenotes = includeMyRenotes
        self.includeRenotedMyNotes = includeRenotedMyNotes
        self.includeLocalRenotes = includeLocalRenotes
        self.withFiles = withFiles
        self.withRenotes = withRenotes
        self.withReplies = withReplies
    }
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

private struct FeedUserTimelineRequest: Encodable {
    let i: String
    let userId: String
    let withReplies: Bool
    let withRenotes: Bool
    let withFiles: Bool
    let limit: Int
    let untilId: String?
}

private struct FeedUserListTimelineRequest: Encodable {
    let i: String
    let listId: String
    let limit: Int
    let untilId: String?
    let allowPartial: Bool
}

private struct FeedNoteRequest: Encodable {
    let i: String
    let noteId: String
}

private struct FeedChildrenRequest: Encodable {
    let i: String
    let noteId: String
    let limit: Int
    let untilId: String?
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

private struct FeedUserRequest: Encodable {
    let i: String
    let userId: String
}

private struct FeedUserShowRequest: Encodable {
    let i: String
    let username: String
    let host: String?
}

private struct FeedAbuseReportRequest: Encodable {
    let i: String
    let userId: String
    let comment: String
}

private struct FeedURLPreviewDTO: Decodable {
    let title: String?
    let description: String?
    let thumbnail: String?
    let sitename: String?
    let sensitive: Bool?
    let url: String?
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
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
    let reactionAcceptance: String?
    let files: [FeedFileDTO]?
    let tags: [String]?
    let poll: FeedPollDTO?
    let emojis: [String: String]?
    let reactionEmojis: [String: String]?
    let reactions: [String: Int]?
    let renoteCount: Int
    let repliesCount: Int
    let myReaction: String?

    enum CodingKeys: String, CodingKey {
        case id, createdAt, text, cw, user, replyId, renote, visibility, reactionAcceptance
        case files, tags, poll, emojis, reactionEmojis, reactions, renoteCount, repliesCount, myReaction
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
        reactionAcceptance = try values.decodeIfPresent(String.self, forKey: .reactionAcceptance)
        files = try values.decodeIfPresent([FeedFileDTO].self, forKey: .files)
        tags = try values.decodeIfPresent([String].self, forKey: .tags)
        poll = try values.decodeIfPresent(FeedPollDTO.self, forKey: .poll)
        emojis = try values.decodeIfPresent([String: String].self, forKey: .emojis)
        reactionEmojis = try values.decodeIfPresent([String: String].self, forKey: .reactionEmojis)
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
