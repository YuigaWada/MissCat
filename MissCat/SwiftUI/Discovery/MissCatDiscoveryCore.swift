import Combine
import Foundation

public struct MissCatTrend: Decodable, Equatable, Identifiable, Sendable {
    public let tag: String
    public let chart: [Double]
    public let usersCount: Int

    public var id: String { tag }

    public init(tag: String, chart: [Double] = [], usersCount: Int = 0) {
        self.tag = tag
        self.chart = chart
        self.usersCount = usersCount
    }
}

public struct MissCatDiscoveryPage<Element: Equatable & Sendable>: Equatable, Sendable {
    public let items: [Element]
    public let nextCursor: String?

    public init(items: [Element], nextCursor: String?) {
        self.items = items
        self.nextCursor = nextCursor
    }
}

public enum MissCatDiscoveryTab: String, CaseIterable, Identifiable, Sendable {
    case notes
    case users

    public var id: String { rawValue }

    public var legacyTitle: String {
        switch self {
        case .notes: "投稿"
        case .users: "ユーザー"
        }
    }
}

public enum MissCatDiscoveryPhase: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case empty
    case offline
    case failed(String)

    public var isTerminal: Bool {
        switch self {
        case .loaded, .empty, .offline, .failed: true
        case .idle, .loading: false
        }
    }
}

public struct MissCatDiscoveryResultState<Element: Equatable & Sendable>: Equatable, Sendable {
    public var items: [Element]
    public var phase: MissCatDiscoveryPhase
    public var nextCursor: String?
    public var isLoadingMore: Bool
    public var paginationError: String?

    public init(
        items: [Element] = [],
        phase: MissCatDiscoveryPhase = .idle,
        nextCursor: String? = nil,
        isLoadingMore: Bool = false,
        paginationError: String? = nil
    ) {
        self.items = items
        self.phase = phase
        self.nextCursor = nextCursor
        self.isLoadingMore = isLoadingMore
        self.paginationError = paginationError
    }
}

public protocol MissCatDiscoveryRepository: AnyObject {
    var accountIdentifier: String { get }
    var currentServerUserID: String { get }

    func fetchTrends() async throws -> [MissCatTrend]
    func searchNotes(query: String, cursor: String?, limit: Int) async throws -> MissCatDiscoveryPage<MissCatNote>
    func searchUsers(query: String, offset: Int, limit: Int) async throws -> MissCatDiscoveryPage<MissCatProfileUser>
}

public enum MissCatDiscoveryRepositoryError: LocalizedError, Equatable {
    case invalidInstance
    case invalidResponse
    case emptyResponse
    case http(Int, String)

    public var errorDescription: String? {
        switch self {
        case .invalidInstance: "インスタンスURLが正しくありません。"
        case .invalidResponse: "サーバーから不正な応答が返されました。"
        case .emptyResponse: "サーバーからデータを取得できませんでした。"
        case let .http(_, message): message
        }
    }
}

/// Current Misskey transport for trends plus note/user search. Note decoding is
/// deliberately shared with the native feed repository so a search result and
/// an ordinary timeline render exactly the same note model.
public final class MissCatMisskeyDiscoveryRepository: MissCatDiscoveryRepository {
    public let accountIdentifier: String
    public let currentServerUserID: String

    private let session: MissCatFeedSession
    private let urlSession: URLSession
    private let feedRepository: MissCatFeedRepository
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(session: MissCatFeedSession, urlSession: URLSession = .shared) {
        self.session = session
        self.urlSession = urlSession
        feedRepository = MissCatMisskeyFeedRepository(session: session, urlSession: urlSession)
        accountIdentifier = session.compositeAccountID
        currentServerUserID = session.accountID
    }

    public func fetchTrends() async throws -> [MissCatTrend] {
        try await post("hashtags/trend", body: DiscoveryEmptyRequest())
    }

    public func searchNotes(
        query: String,
        cursor: String?,
        limit: Int
    ) async throws -> MissCatDiscoveryPage<MissCatNote> {
        let page = try await feedRepository.fetchPage(
            source: .search(query: query),
            cursor: cursor,
            limit: limit
        )
        return MissCatDiscoveryPage(
            items: page.notes,
            nextCursor: page.hasMore ? page.notes.last?.id : nil
        )
    }

    public func searchUsers(
        query: String,
        offset: Int,
        limit: Int
    ) async throws -> MissCatDiscoveryPage<MissCatProfileUser> {
        let boundedLimit = min(max(limit, 1), 100)
        let users: [MissCatProfileUser] = try await post(
            "users/search",
            body: DiscoveryUserSearchRequest(
                i: session.apiKey,
                query: query,
                offset: max(0, offset),
                limit: boundedLimit,
                origin: "combined",
                detail: true
            )
        )
        return MissCatDiscoveryPage(
            items: users,
            nextCursor: users.count >= boundedLimit ? String(max(0, offset) + users.count) : nil
        )
    }

    private func post<Request: Encodable, Response: Decodable>(
        _ endpoint: String,
        body: Request
    ) async throws -> Response {
        var request = try makeRequest(endpoint: endpoint)
        request.httpBody = try encoder.encode(body)
        let (data, response) = try await urlSession.data(for: request)
        try validate(response, data: data)
        guard !data.isEmpty else { throw MissCatDiscoveryRepositoryError.emptyResponse }
        return try decoder.decode(Response.self, from: data)
    }

    private func makeRequest(endpoint: String) throws -> URLRequest {
        let raw = session.instance.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { throw MissCatDiscoveryRepositoryError.invalidInstance }
        let normalized = raw.contains("://") ? raw : "https://\(raw)"
        guard let instanceURL = URL(string: normalized),
              let scheme = instanceURL.scheme?.lowercased(),
              scheme == "https" || scheme == "http"
        else { throw MissCatDiscoveryRepositoryError.invalidInstance }

        let url = instanceURL
            .appendingPathComponent("api", isDirectory: true)
            .appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("MissCat/SwiftUI", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw MissCatDiscoveryRepositoryError.invalidResponse
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            let envelope = try? decoder.decode(DiscoveryAPIErrorEnvelope.self, from: data)
            let message = envelope?.error.message
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw MissCatDiscoveryRepositoryError.http(http.statusCode, message)
        }
    }
}

private struct DiscoveryEmptyRequest: Encodable {}

private struct DiscoveryUserSearchRequest: Encodable {
    let i: String
    let query: String
    let offset: Int
    let limit: Int
    let origin: String
    let detail: Bool
}

private struct DiscoveryAPIErrorEnvelope: Decodable {
    struct Payload: Decodable { let message: String }
    let error: Payload
}

@MainActor
public final class MissCatDiscoveryStore: ObservableObject {
    @Published public var query = ""
    @Published public private(set) var committedQuery = ""
    @Published public var selectedTab: MissCatDiscoveryTab = .notes
    @Published public private(set) var trends: [MissCatTrend] = []
    @Published public private(set) var trendPhase: MissCatDiscoveryPhase = .idle
    @Published public private(set) var noteResults = MissCatDiscoveryResultState<MissCatNote>()
    @Published public private(set) var userResults = MissCatDiscoveryResultState<MissCatProfileUser>()
    @Published public private(set) var accountIdentifier: String
    @Published public private(set) var currentServerUserID: String

    private var repository: MissCatDiscoveryRepository
    private let pageSize: Int
    private var generation = UUID()
    private var trendGeneration = UUID()
    private var trendTask: Task<Void, Never>?
    private var noteTask: Task<Void, Never>?
    private var userTask: Task<Void, Never>?

    public init(repository: MissCatDiscoveryRepository, pageSize: Int = 20) {
        self.repository = repository
        self.pageSize = min(max(pageSize, 1), 100)
        accountIdentifier = repository.accountIdentifier
        currentServerUserID = repository.currentServerUserID
    }

    deinit {
        trendTask?.cancel()
        noteTask?.cancel()
        userTask?.cancel()
    }

    public var showsTrends: Bool { committedQuery.isEmpty }

    public var visualReady: Bool {
        if showsTrends { return trendPhase.isTerminal }
        switch selectedTab {
        case .notes: return noteResults.phase.isTerminal
        case .users: return userResults.phase.isTerminal
        }
    }

    public func loadTrends() {
        guard showsTrends, trendPhase == .idle else { return }
        requestTrends()
    }

    public func retryTrends() {
        trendTask?.cancel()
        trendGeneration = UUID()
        requestTrends()
    }

    public func select(_ tab: MissCatDiscoveryTab) {
        selectedTab = tab
    }

    public func activateTrend(_ trend: MissCatTrend) {
        query = "#\(trend.tag)"
        selectedTab = .notes
        submitSearch()
    }

    public func submitSearch() {
        let cleaned = query.trimmingCharacters(in: .whitespacesAndNewlines)
        query = cleaned
        guard !cleaned.isEmpty else {
            resetToTrends()
            loadTrends()
            return
        }

        cancelResultTasks()
        generation = UUID()
        committedQuery = cleaned
        noteResults = MissCatDiscoveryResultState(phase: .loading)
        userResults = MissCatDiscoveryResultState(phase: .loading)
        requestNotes(cursor: nil, append: false)
        requestUsers(offset: 0, append: false)
    }

    public func cancelSearch() {
        query = ""
        resetToTrends()
        loadTrends()
    }

    public func retry(_ tab: MissCatDiscoveryTab) {
        guard !committedQuery.isEmpty else { return }
        switch tab {
        case .notes:
            noteTask?.cancel()
            noteResults = MissCatDiscoveryResultState(phase: .loading)
            requestNotes(cursor: nil, append: false)
        case .users:
            userTask?.cancel()
            userResults = MissCatDiscoveryResultState(phase: .loading)
            requestUsers(offset: 0, append: false)
        }
    }

    public func loadMoreNotesIfNeeded(currentNoteID: String) {
        guard noteResults.items.suffix(3).contains(where: { $0.id == currentNoteID }),
              let cursor = noteResults.nextCursor,
              !noteResults.isLoadingMore,
              noteResults.paginationError == nil
        else { return }
        requestNotes(cursor: cursor, append: true)
    }

    public func retryNotePagination() {
        guard let cursor = noteResults.nextCursor, !noteResults.isLoadingMore else { return }
        requestNotes(cursor: cursor, append: true)
    }

    public func loadMoreUsersIfNeeded(currentUserID: String) {
        guard userResults.items.suffix(3).contains(where: { $0.id == currentUserID }),
              let cursor = userResults.nextCursor,
              let offset = Int(cursor),
              !userResults.isLoadingMore,
              userResults.paginationError == nil
        else { return }
        requestUsers(offset: offset, append: true)
    }

    public func retryUserPagination() {
        guard let cursor = userResults.nextCursor,
              let offset = Int(cursor),
              !userResults.isLoadingMore
        else { return }
        requestUsers(offset: offset, append: true)
    }

    public func switchRepository(_ repository: MissCatDiscoveryRepository) {
        cancelAllTasks()
        generation = UUID()
        trendGeneration = UUID()
        self.repository = repository
        accountIdentifier = repository.accountIdentifier
        currentServerUserID = repository.currentServerUserID
        query = ""
        committedQuery = ""
        selectedTab = .notes
        trends = []
        trendPhase = .idle
        noteResults = MissCatDiscoveryResultState()
        userResults = MissCatDiscoveryResultState()
        loadTrends()
    }

    func waitForPendingTasksForTesting() async {
        let tasks = [trendTask, noteTask, userTask].compactMap { $0 }
        for task in tasks { await task.value }
    }

    private func requestTrends() {
        trendTask?.cancel()
        trendPhase = .loading
        let token = trendGeneration
        let repository = self.repository
        trendTask = Task { [weak self] in
            do {
                let values = try await repository.fetchTrends()
                try Task.checkCancellation()
                guard let self, self.trendGeneration == token else { return }
                self.trends = Self.uniqueTrends(values)
                self.trendPhase = self.trends.isEmpty ? .empty : .loaded
            } catch is CancellationError {
            } catch {
                guard let self, self.trendGeneration == token else { return }
                self.trendPhase = Self.phase(for: error)
            }
        }
    }

    private func requestNotes(cursor: String?, append: Bool) {
        noteTask?.cancel()
        let token = generation
        let repository = self.repository
        let query = committedQuery
        if append {
            noteResults.isLoadingMore = true
            noteResults.paginationError = nil
        } else {
            noteResults.phase = .loading
        }

        noteTask = Task { [weak self] in
            do {
                guard let self else { return }
                let page = try await repository.searchNotes(
                    query: query,
                    cursor: cursor,
                    limit: self.pageSize
                )
                try Task.checkCancellation()
                guard self.generation == token, self.committedQuery == query else { return }
                let existing = append ? self.noteResults.items : []
                self.noteResults.items = Self.uniqueNotes(existing + page.items)
                self.noteResults.nextCursor = page.nextCursor
                self.noteResults.isLoadingMore = false
                self.noteResults.paginationError = nil
                self.noteResults.phase = self.noteResults.items.isEmpty ? .empty : .loaded
            } catch is CancellationError {
            } catch {
                guard let self, self.generation == token, self.committedQuery == query else { return }
                self.noteResults.isLoadingMore = false
                if append {
                    self.noteResults.paginationError = Self.message(for: error)
                } else {
                    self.noteResults.phase = Self.phase(for: error)
                }
            }
        }
    }

    private func requestUsers(offset: Int, append: Bool) {
        userTask?.cancel()
        let token = generation
        let repository = self.repository
        let query = committedQuery
        if append {
            userResults.isLoadingMore = true
            userResults.paginationError = nil
        } else {
            userResults.phase = .loading
        }

        userTask = Task { [weak self] in
            do {
                guard let self else { return }
                let page = try await repository.searchUsers(
                    query: query,
                    offset: offset,
                    limit: self.pageSize
                )
                try Task.checkCancellation()
                guard self.generation == token, self.committedQuery == query else { return }
                let existing = append ? self.userResults.items : []
                self.userResults.items = Self.uniqueUsers(existing + page.items)
                self.userResults.nextCursor = page.nextCursor
                self.userResults.isLoadingMore = false
                self.userResults.paginationError = nil
                self.userResults.phase = self.userResults.items.isEmpty ? .empty : .loaded
            } catch is CancellationError {
            } catch {
                guard let self, self.generation == token, self.committedQuery == query else { return }
                self.userResults.isLoadingMore = false
                if append {
                    self.userResults.paginationError = Self.message(for: error)
                } else {
                    self.userResults.phase = Self.phase(for: error)
                }
            }
        }
    }

    private func resetToTrends() {
        cancelResultTasks()
        generation = UUID()
        committedQuery = ""
        selectedTab = .notes
        noteResults = MissCatDiscoveryResultState()
        userResults = MissCatDiscoveryResultState()
    }

    private func cancelResultTasks() {
        noteTask?.cancel()
        userTask?.cancel()
        noteTask = nil
        userTask = nil
    }

    private func cancelAllTasks() {
        trendTask?.cancel()
        trendTask = nil
        cancelResultTasks()
    }

    private static func uniqueTrends(_ values: [MissCatTrend]) -> [MissCatTrend] {
        var seen = Set<String>()
        return values.filter { !$0.tag.isEmpty && seen.insert($0.tag.lowercased()).inserted }
    }

    private static func uniqueNotes(_ values: [MissCatNote]) -> [MissCatNote] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.id).inserted }
    }

    private static func uniqueUsers(_ values: [MissCatProfileUser]) -> [MissCatProfileUser] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.id).inserted }
    }

    private static func phase(for error: Error) -> MissCatDiscoveryPhase {
        if isOffline(error) { return .offline }
        return .failed(message(for: error))
    }

    private static func isOffline(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        return [
            URLError.Code.notConnectedToInternet,
            .networkConnectionLost,
            .dataNotAllowed,
            .cannotFindHost,
            .cannotConnectToHost,
        ].contains(urlError.code)
    }

    private static func message(for error: Error) -> String {
        if isOffline(error) { return "インターネットに接続できません。" }
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? "データを読み込めませんでした。" : message
    }
}
