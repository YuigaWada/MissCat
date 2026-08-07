#if DEBUG
import Foundation
import SwiftUI

enum MissCatDiscoveryFixtureConfiguration {
    static let launchArgument = "--discovery-fixture"
    static let stateEnvironmentKey = "MISS_CAT_DISCOVERY_FIXTURE_STATE"

    static var isEnabled: Bool {
        CommandLine.arguments.contains(launchArgument)
            || ProcessInfo.processInfo.environment[stateEnvironmentKey] != nil
    }

    static var isAutomatedTestRun: Bool {
        isEnabled
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    static var state: String {
        ProcessInfo.processInfo.environment[stateEnvironmentKey] ?? "content"
    }
}

/// Exercises the real application root, UIKit Home pager, page-zero factory,
/// hosting boundary, and typed SwiftUI hierarchy without installing a secret.
/// It is intentionally distinct from the direct visual-state fixture above.
enum MissCatDiscoveryOrdinaryRouteConfiguration {
    static let launchArgument = "--discovery-ordinary-route"

    static var isEnabled: Bool {
        CommandLine.arguments.contains(launchArgument)
    }

    static let session = MissCatFeedSession(
        accountID: "ordinary-route-user",
        username: "route-probe",
        instance: "ordinary-route.invalid",
        apiKey: ""
    )
}

@MainActor
struct MissCatDiscoveryFixtureRoot: View {
    private let generation: MissCatDiscoveryAccountGeneration

    init() {
        let repository = MissCatDiscoveryFixtureRepository(
            state: MissCatDiscoveryFixtureConfiguration.state
        )
        generation = MissCatDiscoveryAccountGeneration(
            session: .init(
                accountID: repository.currentServerUserID,
                username: "wada",
                instance: "fixture.example",
                apiKey: ""
            ),
            discoveryRepository: repository,
            feedRepository: repository,
            previewProfile: repository.fixtureUser,
            pageSize: 8
        )

        switch MissCatDiscoveryFixtureConfiguration.state {
        case "notes":
            generation.store.query = "SwiftUI"
            generation.store.submitSearch()
        case "users":
            generation.store.query = "SwiftUI"
            generation.store.select(.users)
            generation.store.submitSearch()
        default:
            break
        }
    }

    var body: some View {
        MissCatDiscoveryRoot(generation: generation)
        .preferredColorScheme(
            ProcessInfo.processInfo.environment["MISS_CAT_DISCOVERY_FIXTURE_APPEARANCE"] == "dark"
                ? .dark
                : .light
        )
    }
}

private final class MissCatDiscoveryFixtureRepository: MissCatDiscoveryRepository, MissCatNoteContextRepository {
    let accountIdentifier = MissCatAccountIdentity.storageKey(
        instance: "fixture.example",
        userId: "fixture-me"
    )
    let currentServerUserID = "fixture-me"

    private let state: String
    private var didFailNotePagination = false

    init(state: String) { self.state = state }

    func fetchTrends() async throws -> [MissCatTrend] {
        try await resolveState()
        if state == "empty" { return [] }
        return [
            .init(tag: "SwiftUI", chart: [2, 3, 5, 8], usersCount: 42),
            .init(tag: "Misskey", chart: [8, 5, 3, 2], usersCount: 31),
            .init(tag: "猫", chart: [1, 2, 1, 4], usersCount: 18),
            .init(tag: "iOS", chart: [3, 3, 4, 5], usersCount: 12),
        ]
    }

    func searchNotes(
        query: String,
        cursor: String?,
        limit: Int
    ) async throws -> MissCatDiscoveryPage<MissCatNote> {
        try await resolveState()
        if state == "empty" { return .init(items: [], nextCursor: nil) }
        if cursor != nil, state == "pagination-error", !didFailNotePagination {
            didFailNotePagination = true
            throw MissCatFeedRepositoryError.invalidResponse
        }

        let start = cursor == nil ? 0 : limit
        let count = cursor == nil ? limit : 3
        let notes = (start ..< start + count).map { Self.note(index: $0, query: query) }
        return .init(items: notes, nextCursor: cursor == nil ? "fixture-page-2" : nil)
    }

    func searchUsers(
        query: String,
        offset: Int,
        limit: Int
    ) async throws -> MissCatDiscoveryPage<MissCatProfileUser> {
        try await resolveState()
        if state == "empty" { return .init(items: [], nextCursor: nil) }
        let count = offset == 0 ? limit : 3
        let users = (offset ..< offset + count).map { Self.user(index: $0, query: query) }
        return .init(items: users, nextCursor: offset == 0 ? String(limit) : nil)
    }

    func fixtureUser(userID: String) -> MissCatProfileUser {
        let index = Int(userID.split(separator: "-").last ?? "0") ?? 0
        return Self.user(index: index, query: "SwiftUI")
    }

    func fetchPage(
        source: MissCatFeedSource,
        cursor: String?,
        limit: Int
    ) async throws -> MissCatFeedPage {
        let page = try await searchNotes(query: "SwiftUI", cursor: cursor, limit: limit)
        return .init(notes: page.items, hasMore: page.nextCursor != nil)
    }

    func fetchThread(noteID: String, replyLimit: Int) async throws -> MissCatNoteThread {
        let root = Self.note(index: Self.index(from: noteID), query: "SwiftUI")
        return .init(
            ancestors: [],
            note: root,
            replies: [
                MissCatNote(
                    id: "fixture-reply",
                    author: Self.author(index: 99),
                    createdAt: Date(timeIntervalSince1970: 1_700_001_000),
                    text: "検索結果から詳細画面へ移動できました。",
                    replyID: root.noteID
                ),
            ]
        )
    }

    func realtimeEvents(
        source: MissCatFeedSource,
        capturing noteIDs: [String]
    ) -> AsyncStream<MissCatRealtimeEvent> {
        AsyncStream { $0.finish() }
    }

    func perform(_ action: MissCatFeedAction) async throws {}

    func notePermalink(noteID: String) -> URL? {
        URL(string: "https://fixture.example/notes/\(noteID)")
    }

    func fetchURLPreview(for url: URL) async throws -> MissCatURLPreview {
        .init(sourceURL: url, title: "MissCat Search")
    }

    private func resolveState() async throws {
        switch state {
        case "loading":
            try await Task.sleep(nanoseconds: 3_600_000_000_000)
            throw CancellationError()
        case "error":
            throw MissCatFeedRepositoryError.invalidResponse
        case "offline":
            throw URLError(.notConnectedToInternet)
        default:
            return
        }
    }

    private static func index(from noteID: String) -> Int {
        Int(noteID.split(separator: "-").last ?? "0") ?? 0
    }

    private static func author(index: Int) -> MissCatNoteAuthor {
        .init(
            id: "fixture-user-\(index)",
            name: index == 0 ? "だわくん 🧃" : "検索ユーザー \(index + 1)",
            username: index == 0 ? "wada" : "search\(index + 1)",
            isCat: index.isMultiple(of: 3)
        )
    }

    private static func note(index: Int, query: String) -> MissCatNote {
        let visibleQuery = query.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        return .init(
            id: "fixture-note-\(index)",
            author: author(index: index),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(index * 60)),
            text: "\(visibleQuery) の検索結果 \(index + 1) — SwiftUIで同じ操作感を再現しています。",
            reactions: [.init(name: "👍", count: 1)],
            repliesCount: 0,
            renoteCount: 0,
            tags: ["SwiftUI", "MissCat"]
        )
    }

    private static func user(index: Int, query: String) -> MissCatProfileUser {
        let visibleQuery = query.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        return .init(
            id: "fixture-user-\(index)",
            name: index == 0 ? "だわくん 🧃" : "\(visibleQuery) User \(index + 1)",
            username: index == 0 ? "wada" : "search\(index + 1)",
            description: "MissCatのSwiftUI検索fixtureユーザーです。",
            isCat: index.isMultiple(of: 3),
            followersCount: 100 + index,
            followingCount: 20 + index,
            notesCount: 500 + index
        )
    }
}

/// Deterministic, credential-free data used only after the ordinary app route
/// has reached Home's production page factory. It does not replace the app root.
final class MissCatDiscoveryOrdinaryRouteRepository: MissCatDiscoveryRepository, MissCatNoteContextRepository {
    let accountIdentifier = MissCatDiscoveryOrdinaryRouteConfiguration.session.compositeAccountID
    let currentServerUserID = MissCatDiscoveryOrdinaryRouteConfiguration.session.accountID

    func fetchTrends() async throws -> [MissCatTrend] {
        [
            .init(tag: "OrdinaryRoute", chart: [1, 2, 3], usersCount: 3),
            .init(tag: "SwiftUI", chart: [3, 2, 1], usersCount: 2),
        ]
    }

    func searchNotes(
        query: String,
        cursor: String?,
        limit: Int
    ) async throws -> MissCatDiscoveryPage<MissCatNote> {
        .init(items: cursor == nil ? [Self.note(query: query)] : [], nextCursor: nil)
    }

    func searchUsers(
        query: String,
        offset: Int,
        limit: Int
    ) async throws -> MissCatDiscoveryPage<MissCatProfileUser> {
        .init(items: offset == 0 ? [user("ordinary-route-profile")] : [], nextCursor: nil)
    }

    func user(_ userID: String) -> MissCatProfileUser {
        .init(
            id: userID,
            name: "Ordinary Route",
            username: "route-probe",
            description: "Production Home page-zero route"
        )
    }

    func fetchPage(
        source: MissCatFeedSource,
        cursor: String?,
        limit: Int
    ) async throws -> MissCatFeedPage {
        let query: String
        switch source {
        case let .search(value): query = value
        case let .hashtag(tag): query = "#\(tag)"
        default: query = "OrdinaryRoute"
        }
        return .init(notes: cursor == nil ? [Self.note(query: query)] : [], hasMore: false)
    }

    func fetchThread(noteID: String, replyLimit: Int) async throws -> MissCatNoteThread {
        .init(ancestors: [], note: Self.note(query: noteID), replies: [])
    }

    func realtimeEvents(
        source: MissCatFeedSource,
        capturing noteIDs: [String]
    ) -> AsyncStream<MissCatRealtimeEvent> {
        AsyncStream { $0.finish() }
    }

    func perform(_ action: MissCatFeedAction) async throws {}

    func notePermalink(noteID: String) -> URL? {
        URL(string: "https://ordinary-route.invalid/notes/\(noteID)")
    }

    func fetchURLPreview(for url: URL) async throws -> MissCatURLPreview {
        .init(sourceURL: url, title: "Ordinary route")
    }

    private static func note(query: String) -> MissCatNote {
        .init(
            id: "ordinary-route-note",
            author: .init(
                id: "ordinary-route-profile",
                name: "Ordinary Route",
                username: "route-probe"
            ),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            text: "\(query) reached native discovery through Home index 0.",
            tags: ["OrdinaryRoute"]
        )
    }
}
#endif
