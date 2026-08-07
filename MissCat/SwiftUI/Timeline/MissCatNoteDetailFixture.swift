#if DEBUG
import Foundation

/// DEBUG-only dependency configuration for exercising the ordinary Home
/// route and NotificationMessageBridge without storing a real credential.
/// It never replaces the application root and is excluded from Release builds.
@MainActor
enum MissCatNoteOrdinaryRouteConfiguration {
    static let launchArgument = "--note-actions-ordinary-route"
    static let stateEnvironmentKey = "MISS_CAT_NOTE_ORDINARY_STATE"

    static var isEnabled: Bool {
        CommandLine.arguments.contains(launchArgument)
    }

    static var state: String {
        ProcessInfo.processInfo.environment[stateEnvironmentKey] ?? "content"
    }

    static let owner = SecureUser(
        userId: "ordinary-note-owner",
        username: "wada",
        instance: "ordinary-note.invalid",
        apiKey: "ordinary-note-token"
    )

    static func makeRepository() -> any MissCatNoteContextRepository {
        MissCatNoteOrdinaryRouteRepository(state: state)
    }
}

@MainActor
enum MissCatNoteOrdinaryRouteComposeFactory {
    static func makeViewModel(mode: MissCatComposeMode) -> MissCatComposeViewModel {
        MissCatComposeViewModel(
            mode: mode,
            environment: MissCatNoteOrdinaryRouteComposeEnvironment(),
            posting: MissCatNoteOrdinaryRouteComposePosting(),
            nowPlayingProvider: MissCatEmptyNowPlayingProvider()
        )
    }
}

@MainActor
private final class MissCatNoteOrdinaryRouteComposeEnvironment: MissCatComposeEnvironmentProviding {
    func load() async throws -> MissCatComposeBootstrap {
        MissCatComposeBootstrap(
            accounts: [
                MissCatComposeAccount(
                    id: "ordinary-note-owner",
                    username: "wada",
                    instance: "ordinary-note.invalid"
                ),
            ],
            selectedAccountID: "ordinary-note-owner",
            visibility: .public
        )
    }

    func persistSelectedAccount(id: String) {}
    func persistVisibility(_ visibility: MissCatComposeVisibility) {}
}

@MainActor
private final class MissCatNoteOrdinaryRouteComposePosting: MissCatComposeSubmitting {
    func submit(
        _ submission: MissCatComposeSubmission,
        progress: @escaping (MissCatComposeUploadProgress) -> Void
    ) async throws {
        try await Task.sleep(nanoseconds: 40_000_000)
    }
}

/// `lock` serializes deterministic one-shot failure counters used by the fixture.
private final class MissCatNoteOrdinaryRouteRepository:
    MissCatNoteContextRepository,
    @unchecked Sendable
{
    let accountIdentifier = MissCatAccountIdentity.storageKey(
        instance: "ordinary-note.invalid",
        userId: "ordinary-note-owner"
    )
    let currentServerUserID = "fixture-me"

    private let state: String
    private let lock = NSLock()
    private var previewAttempts = 0
    private var reactionAttempts = 0
    private var actionAttempts = 0

    init(state: String) {
        self.state = state
    }

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

    func perform(_ action: MissCatFeedAction) async throws {
        let attempt = lock.withLock {
            actionAttempts += 1
            return actionAttempts
        }
        if state == "action-failure", attempt == 1 {
            throw MissCatFeedRepositoryError.rejectedAction
        }
    }

    func notePermalink(noteID: String) -> URL? {
        URL(string: "https://ordinary-note.invalid/notes/\(noteID)")
    }

    func cachedURLPreview(for url: URL) -> MissCatURLPreview? {
        Self.preview(for: url)
    }

    func fetchURLPreview(for url: URL) async throws -> MissCatURLPreview {
        try await Task.sleep(nanoseconds: 40_000_000)
        let attempt = lock.withLock {
            previewAttempts += 1
            return previewAttempts
        }
        if state == "preview-failure", attempt == 1 {
            throw URLError(.cannotLoadFromNetwork)
        }
        return Self.preview(for: url)
    }

    func fetchReactionChoices() async throws -> [MissCatReactionChoice] {
        let attempt = lock.withLock {
            reactionAttempts += 1
            return reactionAttempts
        }
        if state == "reaction-error", attempt == 1 {
            throw MissCatFeedRepositoryError.invalidResponse
        }
        return [
            MissCatReactionChoice(value: ":misscat:", label: "🐈"),
            MissCatReactionChoice(value: ":swiftui:", label: "🟢"),
        ]
    }

    private static func preview(for url: URL) -> MissCatURLPreview {
        MissCatURLPreview(
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
        isCat: false
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
                text: "SwiftUI版の詳細画面を確認します。"
            ),
        ],
        note: MissCatNote(
            id: "fixture-root",
            author: author,
            text: "<spin>回転タグは安全に無視</spin> **太字** とリンク\nhttps://example.com/misscat",
            visibility: "public",
            attachments: attachments,
            reactions: [
                .init(name: "👍", count: 12, isMine: true),
                .init(name: ":misscat:", count: 4),
            ],
            repliesCount: 1,
            renoteCount: 3,
            myReaction: "👍",
            isFavorite: false
        ),
        replies: [
            MissCatNote(
                id: "fixture-reply",
                author: replyAuthor,
                text: "メディアをタップして、左右にスワイプできます。",
                replyID: "fixture-root"
            ),
        ]
    )
}
#endif
