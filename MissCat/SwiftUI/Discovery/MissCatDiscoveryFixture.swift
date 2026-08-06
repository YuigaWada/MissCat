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

private enum MissCatDiscoveryFixtureRoute: Hashable {
    case note(String)
    case user(String)
}

struct MissCatDiscoveryFixtureRoot: View {
    @State private var path: [MissCatDiscoveryFixtureRoute] = []
    private let repository: MissCatDiscoveryFixtureRepository
    private let store: MissCatDiscoveryStore

    init() {
        let repository = MissCatDiscoveryFixtureRepository(
            state: MissCatDiscoveryFixtureConfiguration.state
        )
        self.repository = repository
        store = MissCatDiscoveryStore(repository: repository, pageSize: 8)
    }

    var body: some View {
        NavigationStack(path: $path) {
            MissCatDiscoveryScreen(
                store: store,
                instanceDisplayName: "fixture.example",
                navigationActions: .init(
                    openUser: { path.append(.user($0)) },
                    openNote: { path.append(.note($0)) }
                )
            )
            .navigationTitle("検索")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: MissCatDiscoveryFixtureRoute.self) { route in
                switch route {
                case let .note(noteID):
                    MissCatNoteDetailView(noteID: noteID, repository: repository)
                case let .user(userID):
                    MissCatDiscoveryFixtureProfile(
                        user: repository.fixtureUser(userID: userID)
                    )
                }
            }
        }
        .preferredColorScheme(
            ProcessInfo.processInfo.environment["MISS_CAT_DISCOVERY_FIXTURE_APPEARANCE"] == "dark"
                ? .dark
                : .light
        )
    }
}

private struct MissCatDiscoveryFixtureProfile: View {
    let user: MissCatProfileUser

    var body: some View {
        VStack(spacing: 0) {
            MissCatUserRow(user: user, palette: .legacyLight)
            VStack(spacing: 8) {
                Text(user.displayName).font(.title2.weight(.semibold))
                Text(user.acct).foregroundStyle(.secondary)
                Text(user.description ?? "")
            }
            .padding(24)
            Spacer()
        }
        .navigationTitle(user.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("discovery.profile.destination")
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
        .init(
            id: "fixture-note-\(index)",
            author: author(index: index),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(index * 60)),
            text: "\(query) の検索結果 \(index + 1) — SwiftUIで同じ操作感を再現しています。",
            reactions: [.init(name: "👍", count: index + 1)],
            repliesCount: index % 3,
            renoteCount: index % 4,
            tags: ["SwiftUI", "MissCat"]
        )
    }

    private static func user(index: Int, query: String) -> MissCatProfileUser {
        .init(
            id: "fixture-user-\(index)",
            name: index == 0 ? "だわくん 🧃" : "\(query) User \(index + 1)",
            username: index == 0 ? "wada" : "search\(index + 1)",
            description: "MissCatのSwiftUI検索fixtureユーザーです。",
            isCat: index.isMultiple(of: 3),
            followersCount: 100 + index,
            followingCount: 20 + index,
            notesCount: 500 + index
        )
    }
}
#endif
