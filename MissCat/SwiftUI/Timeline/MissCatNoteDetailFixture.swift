#if DEBUG
import Foundation
import SwiftUI

enum MissCatNoteDetailFixtureConfiguration {
    static let launchArgument = "--note-detail-fixture"
    static let stateEnvironmentKey = "MISS_CAT_NOTE_FIXTURE_STATE"

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

struct MissCatNoteDetailFixtureRoot: View {
    private let repository = MissCatNoteDetailFixtureRepository(
        state: MissCatNoteDetailFixtureConfiguration.state
    )

    var body: some View {
        NavigationStack {
            MissCatNoteDetailView(noteID: "fixture-root", repository: repository)
        }
        .preferredColorScheme(
            ProcessInfo.processInfo.environment["MISS_CAT_NOTE_FIXTURE_APPEARANCE"] == "dark"
                ? .dark
                : .light
        )
    }
}

private final class MissCatNoteDetailFixtureRepository: MissCatNoteContextRepository {
    let accountIdentifier = MissCatAccountIdentity.storageKey(
        instance: "fixture.example",
        userId: "fixture-me"
    )
    let currentServerUserID = "fixture-me"
    private let state: String

    init(state: String) { self.state = state }

    func fetchPage(
        source: MissCatFeedSource,
        cursor: String?,
        limit: Int
    ) async throws -> MissCatFeedPage {
        .init(notes: [], hasMore: false)
    }

    func fetchThread(noteID: String, replyLimit: Int) async throws -> MissCatNoteThread {
        switch state {
        case "loading":
            try await Task.sleep(nanoseconds: 3_600_000_000_000)
            throw CancellationError()
        case "empty":
            throw MissCatFeedRepositoryError.emptyResponse
        case "error":
            throw MissCatFeedRepositoryError.invalidResponse
        case "offline":
            throw URLError(.notConnectedToInternet)
        default:
            return Self.thread
        }
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
        try await Task.sleep(nanoseconds: 40_000_000)
        return MissCatURLPreview(
            sourceURL: url,
            title: "MissCat SwiftUI migration",
            description: "Legacy design, native interactions, and deterministic visual evidence.",
            siteName: "fixture.example"
        )
    }

    private static let author = MissCatNoteAuthor(
        id: "fixture-me",
        name: "だわくん 🧃",
        username: "wada",
        isCat: true
    )

    private static let replyAuthor = MissCatNoteAuthor(
        id: "fixture-reply-user",
        name: "MissCat reviewer",
        username: "reviewer",
        host: "remote.example"
    )

    private static let attachments: [MissCatNoteAttachment] = [
        .init(id: "fixture-media-1", name: "街の写真", kind: .image, url: nil, width: 1200, height: 800),
        .init(id: "fixture-media-2", name: "猫の写真", kind: .image, url: nil, width: 800, height: 1200),
        .init(id: "fixture-media-3", name: "短い動画", kind: .video, url: nil),
    ]

    private static let thread = MissCatNoteThread(
        ancestors: [
            MissCatNote(
                id: "fixture-ancestor",
                author: replyAuthor,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                text: "SwiftUI版の詳細画面を確認します。"
            ),
        ],
        note: MissCatNote(
            id: "fixture-root",
            author: author,
            createdAt: Date(timeIntervalSince1970: 1_700_000_060),
            text: "<spin>回転タグは安全に無視</spin> **太字** とリンク https://example.com/misscat",
            visibility: "public",
            attachments: attachments,
            reactions: [
                .init(name: "👍", count: 12, isMine: true),
                .init(name: ":misscat:", count: 4),
            ],
            repliesCount: 1,
            renoteCount: 3,
            tags: ["SwiftUI", "MissCat"],
            myReaction: "👍",
            isFavorite: false,
            poll: .init(choices: [
                .init(id: 0, text: "同じデザイン", votes: 9),
                .init(id: 1, text: "新しい挙動", votes: 3),
            ])
        ),
        replies: [
            MissCatNote(
                id: "fixture-reply",
                author: replyAuthor,
                createdAt: Date(timeIntervalSince1970: 1_700_000_120),
                text: "メディアをタップして、左右にスワイプできます。",
                replyID: "fixture-root"
            ),
        ]
    )
}
#endif
