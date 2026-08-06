import Foundation
import SwiftUI

// MARK: - Account-scoped domain

public struct MissCatProfileAccount: Equatable, Sendable {
    public let userID: String
    public let instance: String
    public let token: String

    public init(userID: String, instance: String, token: String) {
        self.userID = userID
        self.instance = instance
        self.token = token
    }

    fileprivate var apiBaseURL: URL? {
        let raw = instance.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        let value = raw.contains("://") ? raw : "https://\(raw)"
        return URL(string: value)?.appendingPathComponent("api", isDirectory: true)
    }
}

public struct MissCatProfileUser: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var name: String?
    public var username: String
    public var host: String?
    public var description: String?
    public var avatarURL: URL?
    public var bannerURL: URL?
    public var isCat: Bool
    public var followersCount: Int
    public var followingCount: Int
    public var notesCount: Int

    enum CodingKeys: String, CodingKey {
        case id, name, username, host, description, isCat
        case avatarURL = "avatarUrl"
        case bannerURL = "bannerUrl"
        case followersCount, followingCount, notesCount
    }

    public init(
        id: String,
        name: String? = nil,
        username: String,
        host: String? = nil,
        description: String? = nil,
        avatarURL: URL? = nil,
        bannerURL: URL? = nil,
        isCat: Bool = false,
        followersCount: Int = 0,
        followingCount: Int = 0,
        notesCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.username = username
        self.host = host
        self.description = description
        self.avatarURL = avatarURL
        self.bannerURL = bannerURL
        self.isCat = isCat
        self.followersCount = followersCount
        self.followingCount = followingCount
        self.notesCount = notesCount
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decodeIfPresent(String.self, forKey: .name)
        username = try values.decode(String.self, forKey: .username)
        host = try values.decodeIfPresent(String.self, forKey: .host)
        description = try values.decodeIfPresent(String.self, forKey: .description)
        avatarURL = try values.decodeIfPresent(URL.self, forKey: .avatarURL)
        bannerURL = try values.decodeIfPresent(URL.self, forKey: .bannerURL)
        isCat = try values.decodeIfPresent(Bool.self, forKey: .isCat) ?? false
        followersCount = try values.decodeIfPresent(Int.self, forKey: .followersCount) ?? 0
        followingCount = try values.decodeIfPresent(Int.self, forKey: .followingCount) ?? 0
        notesCount = try values.decodeIfPresent(Int.self, forKey: .notesCount) ?? 0
    }

    public var displayName: String { name?.isEmpty == false ? name! : username }
    public var acct: String { "@\(username)\(host.map { "@\($0)" } ?? "")" }
}

public struct MissCatProfileNoteFile: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let type: String
    public let url: URL?
    public let thumbnailURL: URL?

    enum CodingKeys: String, CodingKey {
        case id, type, url
        case thumbnailURL = "thumbnailUrl"
    }
}

public struct MissCatProfileNote: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let createdAt: String
    public let text: String?
    public let cw: String?
    public let user: MissCatProfileUser
    public let files: [MissCatProfileNoteFile]
    public let repliesCount: Int
    public let renoteCount: Int
    public let reactionCount: Int

    enum CodingKeys: String, CodingKey {
        case id, createdAt, text, cw, user, files, repliesCount, renoteCount, reactions
    }

    public init(
        id: String,
        createdAt: String,
        text: String?,
        cw: String? = nil,
        user: MissCatProfileUser,
        files: [MissCatProfileNoteFile] = [],
        repliesCount: Int = 0,
        renoteCount: Int = 0,
        reactionCount: Int = 0
    ) {
        self.id = id
        self.createdAt = createdAt
        self.text = text
        self.cw = cw
        self.user = user
        self.files = files
        self.repliesCount = repliesCount
        self.renoteCount = renoteCount
        self.reactionCount = reactionCount
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        createdAt = try values.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        text = try values.decodeIfPresent(String.self, forKey: .text)
        cw = try values.decodeIfPresent(String.self, forKey: .cw)
        user = try values.decode(MissCatProfileUser.self, forKey: .user)
        files = try values.decodeIfPresent([MissCatProfileNoteFile].self, forKey: .files) ?? []
        repliesCount = try values.decodeIfPresent(Int.self, forKey: .repliesCount) ?? 0
        renoteCount = try values.decodeIfPresent(Int.self, forKey: .renoteCount) ?? 0
        let reactions = try values.decodeIfPresent([String: Int].self, forKey: .reactions) ?? [:]
        reactionCount = reactions.values.reduce(0, +)
    }
}

public struct MissCatProfilePage<Element> {
    public let items: [Element]
    public let nextCursor: String?

    public init(items: [Element], nextCursor: String?) {
        self.items = items
        self.nextCursor = nextCursor
    }
}

public enum MissCatProfileTimelineTab: String, CaseIterable, Identifiable, Sendable {
    case notes
    case notesAndReplies
    case media

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .notes: return "Notes"
        case .notesAndReplies: return "Notes & Replies"
        case .media: return "Media"
        }
    }

    fileprivate var includesReplies: Bool { self == .notesAndReplies }
    fileprivate var onlyFiles: Bool { self == .media }
}

public enum MissCatUserListKind: Equatable, Sendable {
    case followers(userID: String)
    case following(userID: String)
    case search(query: String)

    public var title: String {
        switch self {
        case .followers: return "Followers"
        case .following: return "Following"
        case .search: return "ユーザー検索"
        }
    }
}

public struct MissCatProfileUpdatePatch: Encodable, Equatable, Sendable {
    public var name: String?
    public var description: String?
    public var isCat: Bool?
    public var avatarID: String?
    public var bannerID: String?

    enum CodingKeys: String, CodingKey {
        case name, description, isCat
        case avatarID = "avatarId"
        case bannerID = "bannerId"
    }

    public init(
        name: String? = nil,
        description: String? = nil,
        isCat: Bool? = nil,
        avatarID: String? = nil,
        bannerID: String? = nil
    ) {
        self.name = name
        self.description = description
        self.isCat = isCat
        self.avatarID = avatarID
        self.bannerID = bannerID
    }

    public var isEmpty: Bool {
        name == nil && description == nil && isCat == nil && avatarID == nil && bannerID == nil
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encodeIfPresent(name, forKey: .name)
        try values.encodeIfPresent(description, forKey: .description)
        try values.encodeIfPresent(isCat, forKey: .isCat)
        try values.encodeIfPresent(avatarID, forKey: .avatarID)
        try values.encodeIfPresent(bannerID, forKey: .bannerID)
    }
}

public enum MissCatLoadPhase: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case empty
    case failed(String)
}

public enum MissCatProfileAPIError: LocalizedError, Equatable {
    case invalidInstance
    case invalidResponse
    case http(Int, String)

    public var errorDescription: String? {
        switch self {
        case .invalidInstance: return "インスタンスURLが正しくありません"
        case .invalidResponse: return "サーバーから不正な応答が返されました"
        case let .http(_, message): return message
        }
    }
}

public protocol MissCatProfileRepository {
    var account: MissCatProfileAccount { get }
    func profile(userID: String) async throws -> MissCatProfileUser
    func relationship(userID: String) async throws -> Bool
    func notes(userID: String, tab: MissCatProfileTimelineTab, cursor: String?, limit: Int) async throws -> MissCatProfilePage<MissCatProfileNote>
    func users(kind: MissCatUserListKind, cursor: String?, limit: Int) async throws -> MissCatProfilePage<MissCatProfileUser>
    func setFollowing(_ following: Bool, userID: String) async throws
    func uploadProfileImage(data: Data, filename: String, progress: @escaping (Double) -> Void) async throws -> String
    func updateProfile(patch: MissCatProfileUpdatePatch) async throws -> MissCatProfileUser
}

// MARK: - Current Misskey REST transport

public final class MissCatRESTProfileRepository: MissCatProfileRepository {
    public let account: MissCatProfileAccount
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(account: MissCatProfileAccount, session: URLSession = .shared) {
        self.account = account
        self.session = session
    }

    public func profile(userID: String) async throws -> MissCatProfileUser {
        try await post("users/show", body: UserBody(i: account.token, userId: userID))
    }

    public func relationship(userID: String) async throws -> Bool {
        let response: RelationshipResponse = try await post(
            "users/relation",
            body: UserBody(i: account.token, userId: userID)
        )
        return response.isFollowing
    }

    public func notes(
        userID: String,
        tab: MissCatProfileTimelineTab,
        cursor: String?,
        limit: Int
    ) async throws -> MissCatProfilePage<MissCatProfileNote> {
        let body = NotesBody(
            i: account.token,
            userId: userID,
            includeReplies: tab.includesReplies,
            withFiles: tab.onlyFiles,
            limit: limit,
            untilId: cursor
        )
        let values: [MissCatProfileNote] = try await post("users/notes", body: body)
        return page(values, limit: limit, cursor: { $0.id })
    }

    public func users(
        kind: MissCatUserListKind,
        cursor: String?,
        limit: Int
    ) async throws -> MissCatProfilePage<MissCatProfileUser> {
        switch kind {
        case let .followers(userID):
            let edges: [FollowEdge] = try await post(
                "users/followers",
                body: FollowListBody(i: account.token, userId: userID, limit: limit, untilId: cursor)
            )
            let users = edges.compactMap { $0.follower ?? $0.user }
            let next = edges.count == limit ? edges.last.flatMap { $0.id ?? $0.follower?.id ?? $0.user?.id } : nil
            return .init(items: users, nextCursor: next)
        case let .following(userID):
            let edges: [FollowEdge] = try await post(
                "users/following",
                body: FollowListBody(i: account.token, userId: userID, limit: limit, untilId: cursor)
            )
            let users = edges.compactMap { $0.followee ?? $0.user }
            let next = edges.count == limit ? edges.last.flatMap { $0.id ?? $0.followee?.id ?? $0.user?.id } : nil
            return .init(items: users, nextCursor: next)
        case let .search(query):
            let offset = Int(cursor ?? "0") ?? 0
            let users: [MissCatProfileUser] = try await post(
                "users/search",
                body: SearchBody(i: account.token, query: query, limit: limit, offset: offset, origin: "combined", detail: true)
            )
            let next = users.count == limit ? String(offset + users.count) : nil
            return .init(items: users, nextCursor: next)
        }
    }

    public func setFollowing(_ following: Bool, userID: String) async throws {
        let endpoint = following ? "following/create" : "following/delete"
        let _: EmptyResponse = try await post(endpoint, body: UserBody(i: account.token, userId: userID))
    }

    public func uploadProfileImage(
        data: Data,
        filename: String,
        progress: @escaping (Double) -> Void
    ) async throws -> String {
        let boundary = "MissCat-\(UUID().uuidString)"
        var request = try makeRequest(path: "drive/files/create")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let body = Self.multipartBody(
            boundary: boundary,
            token: account.token,
            data: data,
            filename: filename
        )
        let delegate = UploadProgressDelegate(progress: progress)
        progress(0)
        let (responseData, response) = try await session.upload(for: request, from: body, delegate: delegate)
        try validate(response, data: responseData)
        let file = try decoder.decode(DriveFileResponse.self, from: responseData)
        progress(1)
        return file.id
    }

    public func updateProfile(patch: MissCatProfileUpdatePatch) async throws -> MissCatProfileUser {
        let body = UpdateBody(token: account.token, patch: patch)
        return try await post("i/update", body: body)
    }

    private func page<Element>(_ values: [Element], limit: Int, cursor: (Element) -> String) -> MissCatProfilePage<Element> {
        .init(items: values, nextCursor: values.count == limit ? values.last.map(cursor) : nil)
    }

    private func post<Request: Encodable, Response: Decodable>(
        _ path: String,
        body: Request
    ) async throws -> Response {
        var request = try makeRequest(path: path)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
        if Response.self == EmptyResponse.self, data.isEmpty {
            return EmptyResponse() as! Response
        }
        return try decoder.decode(Response.self, from: data)
    }

    private func makeRequest(path: String) throws -> URLRequest {
        guard let base = account.apiBaseURL else { throw MissCatProfileAPIError.invalidInstance }
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("MissCat/SwiftUI", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw MissCatProfileAPIError.invalidResponse }
        guard (200 ..< 300).contains(http.statusCode) else {
            let error = try? decoder.decode(APIErrorEnvelope.self, from: data)
            let message = error?.error.message ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw MissCatProfileAPIError.http(http.statusCode, message)
        }
    }

    private static func multipartBody(boundary: String, token: String, data: Data, filename: String) -> Data {
        let safeFilename = filename.replacingOccurrences(of: "\"", with: "")
        var result = Data()
        result.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"i\"\r\n\r\n\(token)\r\n")
        result.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(safeFilename)\"\r\nContent-Type: image/jpeg\r\n\r\n")
        result.append(data)
        result.append("\r\n--\(boundary)--\r\n")
        return result
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}

private struct UserBody: Encodable {
    let i: String
    let userId: String
}

private struct NotesBody: Encodable {
    let i: String
    let userId: String
    let includeReplies: Bool
    let withFiles: Bool
    let limit: Int
    let untilId: String?
}

private struct FollowListBody: Encodable {
    let i: String
    let userId: String
    let limit: Int
    let untilId: String?
}

private struct SearchBody: Encodable {
    let i: String
    let query: String
    let limit: Int
    let offset: Int
    let origin: String
    let detail: Bool
}

private struct RelationshipResponse: Decodable {
    let isFollowing: Bool
}

private struct FollowEdge: Decodable {
    let id: String?
    let follower: MissCatProfileUser?
    let followee: MissCatProfileUser?
    let user: MissCatProfileUser?
}

private struct DriveFileResponse: Decodable {
    let id: String
}

private struct EmptyResponse: Codable {}

private struct APIErrorEnvelope: Decodable {
    struct APIError: Decodable { let message: String }
    let error: APIError
}

private struct UpdateBody: Encodable {
    let token: String
    let patch: MissCatProfileUpdatePatch

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(token, forKey: .token)
        try values.encodeIfPresent(patch.name, forKey: .name)
        try values.encodeIfPresent(patch.description, forKey: .description)
        try values.encodeIfPresent(patch.isCat, forKey: .isCat)
        try values.encodeIfPresent(patch.avatarID, forKey: .avatarID)
        try values.encodeIfPresent(patch.bannerID, forKey: .bannerID)
    }

    enum CodingKeys: String, CodingKey {
        case token = "i"
        case name, description, isCat
        case avatarID = "avatarId"
        case bannerID = "bannerId"
    }
}

private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate {
    private let progress: (Double) -> Void

    init(progress: @escaping (Double) -> Void) {
        self.progress = progress
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        progress(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
    }
}

// MARK: - Deterministic tab behavior

public struct MissCatProfileTabSelectionState: Equatable, Sendable {
    public private(set) var selected: MissCatProfileTimelineTab

    public init(selected: MissCatProfileTimelineTab = .notes) {
        self.selected = selected
    }

    public mutating func select(_ tab: MissCatProfileTimelineTab) {
        selected = tab
    }

    public mutating func move(_ delta: Int) {
        let tabs = MissCatProfileTimelineTab.allCases
        guard let index = tabs.firstIndex(of: selected) else { return }
        selected = tabs[min(max(index + delta, tabs.startIndex), tabs.index(before: tabs.endIndex))]
    }
}

// MARK: - Profile and timeline state

@MainActor
public final class MissCatProfileStore: ObservableObject {
    public struct TimelineState: Equatable {
        public var notes: [MissCatProfileNote] = []
        public var phase: MissCatLoadPhase = .idle
        public var nextCursor: String?
        public var topVisibleNoteID: String?
    }

    @Published public private(set) var profile: MissCatProfileUser?
    @Published public private(set) var profilePhase: MissCatLoadPhase = .idle
    @Published public private(set) var isFollowing = false
    @Published public private(set) var followPhase: MissCatLoadPhase = .idle
    @Published public var selectedTab: MissCatProfileTimelineTab = .notes
    @Published public private(set) var timelines: [MissCatProfileTimelineTab: TimelineState] = [:]
    @Published public private(set) var account: MissCatProfileAccount
    @Published public private(set) var userID: String

    public var isCurrentUser: Bool { account.userID == userID }

    private let repositoryFactory: (MissCatProfileAccount) -> MissCatProfileRepository
    private var repository: MissCatProfileRepository
    private var generation = UUID()
    private var profileTask: Task<Void, Never>?
    private var followTask: Task<Void, Never>?
    private var timelineTasks: [MissCatProfileTimelineTab: Task<Void, Never>] = [:]

    public init(
        account: MissCatProfileAccount,
        userID: String,
        repositoryFactory: @escaping (MissCatProfileAccount) -> MissCatProfileRepository = { MissCatRESTProfileRepository(account: $0) }
    ) {
        self.account = account
        self.userID = userID
        self.repositoryFactory = repositoryFactory
        repository = repositoryFactory(account)
        MissCatProfileTimelineTab.allCases.forEach { timelines[$0] = TimelineState() }
    }

    deinit {
        profileTask?.cancel()
        followTask?.cancel()
        timelineTasks.values.forEach { $0.cancel() }
    }

    public func load() {
        reloadProfile()
        loadTimeline(selectedTab)
    }

    public func reloadProfile() {
        profileTask?.cancel()
        let generation = self.generation
        let repository = self.repository
        let userID = self.userID
        profilePhase = .loading
        profileTask = Task { [weak self] in
            do {
                let profile = try await repository.profile(userID: userID)
                try Task.checkCancellation()
                let relation = profile.id == repository.account.userID ? false : try await repository.relationship(userID: userID)
                try Task.checkCancellation()
                guard let self, self.generation == generation else { return }
                self.profile = profile
                self.isFollowing = relation
                self.profilePhase = .loaded
                self.followPhase = .loaded
            } catch is CancellationError {
            } catch {
                guard let self, self.generation == generation else { return }
                self.profilePhase = .failed(error.localizedDescription)
            }
        }
    }

    public func selectTab(_ tab: MissCatProfileTimelineTab) {
        selectedTab = tab
        loadTimeline(tab)
    }

    public func setTopVisibleNoteID(_ id: String?, for tab: MissCatProfileTimelineTab) {
        timelines[tab, default: TimelineState()].topVisibleNoteID = id
    }

    public func loadTimeline(_ tab: MissCatProfileTimelineTab, reload: Bool = false) {
        var state = timelines[tab, default: TimelineState()]
        if !reload, state.phase == .loaded || state.phase == .empty || state.phase == .loading { return }
        timelineTasks[tab]?.cancel()
        if reload { state = TimelineState(topVisibleNoteID: state.topVisibleNoteID) }
        state.phase = .loading
        timelines[tab] = state
        requestTimeline(tab: tab, cursor: nil, append: false)
    }

    public func loadMoreIfNeeded(tab: MissCatProfileTimelineTab, currentNoteID: String) {
        guard let state = timelines[tab],
              state.notes.suffix(4).contains(where: { $0.id == currentNoteID }),
              state.nextCursor != nil,
              state.phase != .loading
        else { return }
        requestTimeline(tab: tab, cursor: state.nextCursor, append: true)
    }

    public func retryTimeline(_ tab: MissCatProfileTimelineTab) {
        loadTimeline(tab, reload: true)
    }

    public func setFollowing(_ shouldFollow: Bool) {
        guard !isCurrentUser, followPhase != .loading else { return }
        followTask?.cancel()
        let generation = self.generation
        let repository = self.repository
        let userID = self.userID
        followPhase = .loading
        followTask = Task { [weak self] in
            do {
                try await repository.setFollowing(shouldFollow, userID: userID)
                try Task.checkCancellation()
                guard let self, self.generation == generation else { return }
                self.isFollowing = shouldFollow
                self.followPhase = .loaded
            } catch is CancellationError {
            } catch {
                guard let self, self.generation == generation else { return }
                // The prior server-confirmed value remains visible (rollback/no optimism).
                self.followPhase = .failed(error.localizedDescription)
            }
        }
    }

    public func switchAccount(_ account: MissCatProfileAccount) {
        let wasOwnProfile = isCurrentUser
        cancelAllTasks()
        generation = UUID()
        self.account = account
        repository = repositoryFactory(account)
        if wasOwnProfile { userID = account.userID }
        profile = nil
        profilePhase = .idle
        isFollowing = false
        followPhase = .idle
        timelines = Dictionary(uniqueKeysWithValues: MissCatProfileTimelineTab.allCases.map { ($0, TimelineState()) })
        selectedTab = .notes
        load()
    }

    public func applyUpdatedProfile(_ profile: MissCatProfileUser) {
        guard profile.id == userID else { return }
        self.profile = profile
        profilePhase = .loaded
    }

    private func requestTimeline(tab: MissCatProfileTimelineTab, cursor: String?, append: Bool) {
        let generation = self.generation
        let repository = self.repository
        let userID = self.userID
        timelines[tab, default: TimelineState()].phase = .loading
        timelineTasks[tab] = Task { [weak self] in
            do {
                let page = try await repository.notes(userID: userID, tab: tab, cursor: cursor, limit: 30)
                try Task.checkCancellation()
                guard let self, self.generation == generation else { return }
                var state = self.timelines[tab, default: TimelineState()]
                let combined = append ? state.notes + page.items : page.items
                state.notes = Self.uniqued(combined)
                state.nextCursor = page.nextCursor
                state.phase = state.notes.isEmpty ? .empty : .loaded
                self.timelines[tab] = state
            } catch is CancellationError {
            } catch {
                guard let self, self.generation == generation else { return }
                self.timelines[tab, default: TimelineState()].phase = .failed(error.localizedDescription)
            }
        }
    }

    private func cancelAllTasks() {
        profileTask?.cancel()
        followTask?.cancel()
        timelineTasks.values.forEach { $0.cancel() }
        timelineTasks.removeAll()
    }

    private static func uniqued(_ notes: [MissCatProfileNote]) -> [MissCatProfileNote] {
        var seen = Set<String>()
        return notes.filter { seen.insert($0.id).inserted }
    }
}

// MARK: - Generic user lists and search

@MainActor
public final class MissCatUserListStore: ObservableObject {
    @Published public private(set) var users: [MissCatProfileUser] = []
    @Published public private(set) var phase: MissCatLoadPhase = .idle
    @Published public var query: String
    @Published public private(set) var account: MissCatProfileAccount
    public private(set) var kind: MissCatUserListKind

    private let repositoryFactory: (MissCatProfileAccount) -> MissCatProfileRepository
    private var repository: MissCatProfileRepository
    private var nextCursor: String?
    private var task: Task<Void, Never>?
    private var generation = UUID()

    public init(
        account: MissCatProfileAccount,
        kind: MissCatUserListKind,
        repositoryFactory: @escaping (MissCatProfileAccount) -> MissCatProfileRepository = { MissCatRESTProfileRepository(account: $0) }
    ) {
        self.account = account
        self.kind = kind
        self.repositoryFactory = repositoryFactory
        repository = repositoryFactory(account)
        if case let .search(query) = kind { self.query = query } else { query = "" }
    }

    deinit { task?.cancel() }

    public func load(reload: Bool = false) {
        guard phase != .loading else { return }
        if reload {
            users = []
            nextCursor = nil
        } else if phase == .loaded || phase == .empty {
            return
        }
        request(cursor: nil, append: false)
    }

    public func submitSearch() {
        let cleaned = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            task?.cancel()
            users = []
            phase = .idle
            return
        }
        kind = .search(query: cleaned)
        load(reload: true)
    }

    public func retry() { load(reload: true) }

    public func loadMoreIfNeeded(currentUserID: String) {
        guard users.suffix(4).contains(where: { $0.id == currentUserID }),
              nextCursor != nil,
              phase != .loading
        else { return }
        request(cursor: nextCursor, append: true)
    }

    public func switchAccount(_ account: MissCatProfileAccount) {
        task?.cancel()
        generation = UUID()
        self.account = account
        repository = repositoryFactory(account)
        users = []
        nextCursor = nil
        phase = .idle
        load()
    }

    private func request(cursor: String?, append: Bool) {
        task?.cancel()
        phase = .loading
        let generation = self.generation
        let repository = self.repository
        let kind = self.kind
        task = Task { [weak self] in
            do {
                let page = try await repository.users(kind: kind, cursor: cursor, limit: 40)
                try Task.checkCancellation()
                guard let self, self.generation == generation else { return }
                var ids = Set((append ? self.users : []).map(\.id))
                let fresh = page.items.filter { ids.insert($0.id).inserted }
                self.users = append ? self.users + fresh : fresh
                self.nextCursor = page.nextCursor
                self.phase = self.users.isEmpty ? .empty : .loaded
            } catch is CancellationError {
            } catch {
                guard let self, self.generation == generation else { return }
                self.phase = .failed(error.localizedDescription)
            }
        }
    }
}

// MARK: - Partial profile editor and upload state

@MainActor
public final class MissCatProfileEditorStore: ObservableObject {
    @Published public var name: String
    @Published public var biography: String
    @Published public var isCat: Bool
    @Published public private(set) var avatarData: Data?
    @Published public private(set) var bannerData: Data?
    @Published public private(set) var phase: MissCatLoadPhase = .idle
    @Published public private(set) var uploadProgress = 0.0
    @Published public private(set) var savedProfile: MissCatProfileUser?
    @Published public private(set) var account: MissCatProfileAccount

    private var baseline: MissCatProfileUser
    private let repositoryFactory: (MissCatProfileAccount) -> MissCatProfileRepository
    private var repository: MissCatProfileRepository
    private var saveTask: Task<Void, Never>?
    private var generation = UUID()

    public init(
        account: MissCatProfileAccount,
        profile: MissCatProfileUser,
        repositoryFactory: @escaping (MissCatProfileAccount) -> MissCatProfileRepository = { MissCatRESTProfileRepository(account: $0) }
    ) {
        self.account = account
        baseline = profile
        name = profile.name ?? ""
        biography = profile.description ?? ""
        isCat = profile.isCat
        self.repositoryFactory = repositoryFactory
        repository = repositoryFactory(account)
    }

    deinit { saveTask?.cancel() }

    public func setAvatarData(_ data: Data?) { avatarData = data }
    public func setBannerData(_ data: Data?) { bannerData = data }

    public func save() {
        guard phase != .loading else { return }
        saveTask?.cancel()
        phase = .loading
        uploadProgress = 0
        let generation = self.generation
        let repository = self.repository
        let name = self.name
        let biography = self.biography
        let isCat = self.isCat
        let avatarData = self.avatarData
        let bannerData = self.bannerData
        let baseline = self.baseline
        saveTask = Task { [weak self] in
            do {
                var patch = MissCatProfileUpdatePatch(
                    name: name == (baseline.name ?? "") ? nil : name,
                    description: biography == (baseline.description ?? "") ? nil : biography,
                    isCat: isCat == baseline.isCat ? nil : isCat
                )
                let uploadCount = [avatarData, bannerData].compactMap { $0 }.count
                var completedUploads = 0

                if let avatarData {
                    patch.avatarID = try await repository.uploadProfileImage(data: avatarData, filename: "avatar.jpg") { value in
                        Task { @MainActor [weak self] in
                            guard let self, self.generation == generation else { return }
                            self.uploadProgress = (Double(completedUploads) + value) / Double(max(1, uploadCount))
                        }
                    }
                    completedUploads += 1
                }
                if let bannerData {
                    patch.bannerID = try await repository.uploadProfileImage(data: bannerData, filename: "banner.jpg") { value in
                        Task { @MainActor [weak self] in
                            guard let self, self.generation == generation else { return }
                            self.uploadProgress = (Double(completedUploads) + value) / Double(max(1, uploadCount))
                        }
                    }
                }

                try Task.checkCancellation()
                let updated = patch.isEmpty ? baseline : try await repository.updateProfile(patch: patch)
                try Task.checkCancellation()
                guard let self, self.generation == generation else { return }
                self.savedProfile = updated
                self.baseline = updated
                self.avatarData = nil
                self.bannerData = nil
                self.uploadProgress = uploadCount == 0 ? 0 : 1
                self.phase = .loaded
            } catch is CancellationError {
            } catch {
                guard let self, self.generation == generation else { return }
                self.phase = .failed(error.localizedDescription)
            }
        }
    }

    public func retry() { save() }

    public func switchAccount(_ account: MissCatProfileAccount, profile: MissCatProfileUser) {
        saveTask?.cancel()
        generation = UUID()
        self.account = account
        repository = repositoryFactory(account)
        baseline = profile
        name = profile.name ?? ""
        biography = profile.description ?? ""
        isCat = profile.isCat
        avatarData = nil
        bannerData = nil
        uploadProgress = 0
        savedProfile = nil
        phase = .idle
    }
}
