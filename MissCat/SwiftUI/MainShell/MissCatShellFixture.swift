#if DEBUG
import Foundation
import SwiftUI

enum MissCatShellFixtureLaunch {
    enum Mode {
        case populated
        case empty
        case loading
        case error
        case offline
    }

    static let launchArgument = "--swiftui-shell-fixture"
    static var isRequested: Bool { CommandLine.arguments.contains(launchArgument) }

    static var mode: Mode {
        if CommandLine.arguments.contains("--swiftui-shell-fixture-empty") { return .empty }
        if CommandLine.arguments.contains("--swiftui-shell-fixture-loading") { return .loading }
        if CommandLine.arguments.contains("--swiftui-shell-fixture-error") { return .error }
        if CommandLine.arguments.contains("--swiftui-shell-fixture-offline") { return .offline }
        return .populated
    }

    static var rejectsPersistence: Bool {
        CommandLine.arguments.contains("--swiftui-shell-fixture-persistence-error")
    }

    static var includesSocialTimeline: Bool {
        CommandLine.arguments.contains("--swiftui-shell-fixture-four-tabs")
    }

    static var paginationEnabled: Bool {
        CommandLine.arguments.contains("--swiftui-shell-fixture-pagination")
    }

    static var usesActionTimeline: Bool {
        CommandLine.arguments.contains("--swiftui-shell-fixture-actions")
    }

    static let referenceDate = Date(timeIntervalSince1970: 1_596_289_200)
}

private enum MissCatShellFixtureRoute: String, Identifiable {
    case search
    case compose
    case settings

    var id: String { rawValue }
}

struct MissCatShellFixtureView: View {
    @StateObject private var store: MissCatShellStore
    @State private var presentedRoute: MissCatShellFixtureRoute?
    @State private var selectedDestination: TimelineDestination?

    init() {
        let provider = MissCatShellFixtureProvider(
            mode: MissCatShellFixtureLaunch.mode,
            rejectsPersistence: MissCatShellFixtureLaunch.rejectsPersistence
        )
        _store = StateObject(wrappedValue: MissCatShellStore(provider: provider))
    }

    var body: some View {
        Group {
            switch store.phase {
            case .idle, .loading:
                ProgressView("fixture loading")
                    .accessibilityIdentifier("migration.shell-feed.loading")
            case let .failed(message):
                ContentUnavailableView("Fixture failed", systemImage: "exclamationmark.triangle", description: Text(message))
                    .accessibilityIdentifier("migration.shell-feed.failure")
            case .loaded:
                if let configuration = store.configuration {
                    NavigationStack {
                        shell(configuration)
                            .toolbar(.hidden, for: .navigationBar)
                            .navigationDestination(item: $selectedDestination) { destination in
                                if let repository = store.repository(for: configuration.currentScope) {
                                    switch destination {
                                    case let .note(noteID):
                                        MissCatNoteDetailView(
                                            noteID: noteID,
                                            repository: repository,
                                            palette: configuration.appearance.palette,
                                            navigationActions: timelineNavigationActions
                                        )
                                        .toolbar(.visible, for: .navigationBar)
                                    case let .profile(userID):
                                        VStack(spacing: 12) {
                                            Image(systemName: "person.crop.circle.fill")
                                                .font(.system(size: 64))
                                            Text("@alice")
                                            Text(userID)
                                                .accessibilityIdentifier("fixture.profile.user-id")
                                            Text("profile-screen")
                                                .font(.system(size: 1))
                                                .opacity(0.01)
                                                .frame(width: 1, height: 1)
                                                .accessibilityIdentifier("fixture.profile.screen")
                                        }
                                        .navigationTitle("Profile")
                                        .toolbar(.visible, for: .navigationBar)
                                    }
                                }
                            }
                    }
                }
            }
        }
        .task { await store.load() }
        .onDisappear { store.cancelConfigurationTasks() }
        .sheet(item: $presentedRoute) { route in
            NavigationStack {
                VStack(spacing: 12) {
                    Image(systemName: fixtureSymbol(for: route))
                        .font(.system(size: 42))
                        .foregroundStyle(.tint)
                    Text(route.rawValue.capitalized)
                        .font(.title2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("閉じる") { presentedRoute = nil }
                            .accessibilityIdentifier("fixture.route.close")
                    }
                }
                .accessibilityIdentifier("fixture.route.\(route.rawValue)")
            }
        }
    }

    private func shell(_ configuration: MissCatShellConfiguration) -> some View {
        let palette = configuration.appearance.palette
        return MissCatMainShellView(
            timelineTabs: configuration.timelinePages.map {
                MissCatTimelineTab(id: $0.id, title: $0.title, accessibilityID: $0.accessibilityID)
            },
            selectedTimelineID: timelineBinding,
            selectedSection: sectionBinding,
            palette: palette,
            avatar: Image(systemName: "cat.fill"),
            accounts: configuration.accounts,
            currentAccountID: configuration.currentScope.id,
            bannerMessage: store.bannerMessage,
            onSearch: { presentedRoute = .search },
            onCompose: { presentedRoute = .compose },
            onSettings: { presentedRoute = .settings },
            onAccountSelected: { scope in
                store.switchAccount(to: scope)
            },
            onTimelineSelection: store.selectTimeline,
            onReselect: { section in
                _ = store.activateFooter(destination(for: section))
            },
            onDismissBanner: store.dismissBanner
        ) { section in
            switch section {
            case .home:
                MissCatTimelinePager(
                    accountScope: configuration.currentScope,
                    pages: configuration.timelinePages,
                    selectedID: timelineBinding,
                    repositoryProvider: store.repository,
                    palette: palette,
                    scrollToTopTrigger: store.homeScrollToTopGeneration,
                    relativeDateReference: MissCatShellFixtureLaunch.referenceDate,
                    visualReadyPrefix: "migration.shell-feed.visual-ready",
                    allowsLoadingVisualReady: MissCatShellFixtureLaunch.mode == .loading,
                    scrollPosition: { key in
                        Binding(
                            get: { store.timelineScrollPosition(for: key) },
                            set: { store.setTimelineScrollPosition($0, for: key) }
                        )
                    },
                    navigationActions: timelineNavigationActions,
                    onSelection: store.selectTimeline
                )
            case .notifications:
                fixtureSection(
                    title: "Notifications",
                    symbol: "bell.fill",
                    value: "scroll-to-top-\(store.notificationsScrollToTopGeneration)",
                    palette: palette
                )
            case .messages:
                fixtureSection(title: "Chat", symbol: "star.fill", value: "ready", palette: palette)
            case .profile:
                fixtureSection(title: "Accounts", symbol: "person.2.fill", value: configuration.currentScope.id, palette: palette)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("migration.shell-feed.fixture")
    }

    private var timelineNavigationActions: MissCatFeedNavigationActions {
        .init(
            openUser: { selectedDestination = .profile($0) },
            openNote: { selectedDestination = .note($0) }
        )
    }

    private enum TimelineDestination: Identifiable, Hashable {
        case note(String)
        case profile(String)

        var id: String {
            switch self {
            case let .note(value): "note:\(value)"
            case let .profile(value): "profile:\(value)"
            }
        }
    }

    private var timelineBinding: Binding<String> {
        Binding(
            get: { store.selectedTimelineID },
            set: { store.selectTimeline($0, origin: .tap) }
        )
    }

    private var sectionBinding: Binding<MissCatRootSection> {
        Binding(
            get: { store.selectedSection },
            set: { _ = store.activateFooter(destination(for: $0)) }
        )
    }

    private func destination(for section: MissCatRootSection) -> MissCatFooterDestination {
        switch section {
        case .home: .home
        case .notifications: .notifications
        case .messages: .messages
        case .profile: .profile
        }
    }

    private func fixtureSection(
        title: String,
        symbol: String,
        value: String,
        palette: MissCatVisualPalette
    ) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 40))
                .foregroundStyle(palette.accent)
            Text(title)
                .font(.title3)
                .foregroundStyle(palette.text)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.base)
        .accessibilityElement(children: .combine)
        .accessibilityValue(value)
        .accessibilityIdentifier("fixture.section.\(title.lowercased())")
    }

    private func fixtureSymbol(for route: MissCatShellFixtureRoute) -> String {
        switch route {
        case .search: "magnifyingglass"
        case .compose: "square.and.pencil"
        case .settings: "gearshape.fill"
        }
    }
}

@MainActor
private final class MissCatShellFixtureProvider: MissCatShellConfigurationProviding {
    private let mode: MissCatShellFixtureLaunch.Mode
    private let rejectsPersistence: Bool
    private let accounts: [MissCatShellAccount]
    private var currentScope: MissCatShellAccountScope
    private var selections: [MissCatShellAccountScope: String] = [:]
    private var repositories: [MissCatShellAccountScope: MissCatShellFixtureRepository] = [:]

    init(mode: MissCatShellFixtureLaunch.Mode, rejectsPersistence: Bool = false) {
        self.mode = mode
        self.rejectsPersistence = rejectsPersistence
        let primary = MissCatShellAccountScope(instance: "fixture.example", userID: "fixture-cat", username: "misscat")
        let secondary = MissCatShellAccountScope(instance: "social.example", userID: "fixture-cat", username: "misscat")
        currentScope = primary
        accounts = [
            MissCatShellAccount(scope: primary, displayName: "Miss Cat"),
            MissCatShellAccount(scope: secondary, displayName: "Miss Cat Social")
        ]
    }

    func loadConfiguration() async throws -> MissCatShellConfiguration {
        configuration(for: currentScope)
    }

    func switchAccount(to scope: MissCatShellAccountScope) async throws -> MissCatShellConfiguration {
        guard accounts.contains(where: { $0.scope == scope }) else {
            throw MissCatShellConfigurationError.accountNotFound
        }
        currentScope = scope
        return configuration(for: scope)
    }

    func saveSelectedTimelineID(_ selectedID: String, for scope: MissCatShellAccountScope) async throws {
        if rejectsPersistence { throw MissCatShellFixtureError.persistence }
        selections[scope] = selectedID
    }

    func repository(for scope: MissCatShellAccountScope) throws -> any MissCatFeedRepository {
        if let repository = repositories[scope] { return repository }
        let repository = MissCatShellFixtureRepository(mode: mode, scope: scope)
        repositories[scope] = repository
        return repository
    }

    private func configuration(for scope: MissCatShellAccountScope) -> MissCatShellConfiguration {
        var pages = [
            MissCatTimelinePage(id: "\(scope.id)|home", title: "Home", source: .home, accountScope: scope, accessibilityID: "home"),
            MissCatTimelinePage(id: "\(scope.id)|local", title: "Local", source: .local, accountScope: scope, accessibilityID: "local"),
            MissCatTimelinePage(id: "\(scope.id)|global", title: "Global", source: .global, accountScope: scope, accessibilityID: "global")
        ]
        if MissCatShellFixtureLaunch.includesSocialTimeline {
            pages.insert(
                MissCatTimelinePage(
                    id: "\(scope.id)|social",
                    title: "Social",
                    source: .social,
                    accountScope: scope,
                    accessibilityID: "social"
                ),
                at: 2
            )
        }
        return MissCatShellConfiguration(
            currentScope: scope,
            accounts: accounts,
            timelinePages: pages,
            selectedTimelineID: selections[scope] ?? pages[0].id,
            appearance: MissCatShellAppearance(isDark: false, accentHex: MissCatLegacyColorHex.accent)
        )
    }
}

private final class MissCatShellFixtureRepository: MissCatNoteContextRepository {
    private let mode: MissCatShellFixtureLaunch.Mode
    private let scope: MissCatShellAccountScope
    private var initialPageRequestCount = 0
    private var detailThreadRequestCount = 0

    init(mode: MissCatShellFixtureLaunch.Mode, scope: MissCatShellAccountScope) {
        self.mode = mode
        self.scope = scope
    }

    func fetchPage(source: MissCatFeedSource, cursor: String?, limit: Int) async throws -> MissCatFeedPage {
        if mode == .loading {
            try await Task.sleep(nanoseconds: UInt64.max)
            throw CancellationError()
        }
        if mode == .error { throw MissCatShellFixtureError.expected }
        if mode == .empty { return MissCatFeedPage(notes: [], hasMore: false) }
        if let cursor {
            guard MissCatShellFixtureLaunch.paginationEnabled else {
                return MissCatFeedPage(notes: [], hasMore: false)
            }
            let prefix = source.accessibilityName
            return MissCatFeedPage(
                notes: (0 ..< 5).map { index in
                    MissCatNote(
                        id: "\(prefix)-page2-\(index)",
                        author: MissCatNoteAuthor(
                            id: "fixture-page2-author",
                            name: "More Cat",
                            username: "morecat"
                        ),
                        createdAt: MissCatShellFixtureLaunch.referenceDate.addingTimeInterval(-3600 - Double(index)),
                        text: "Paginated note \(index + 1) after \(cursor)"
                    )
                },
                hasMore: false
            )
        }
        initialPageRequestCount += 1
        if initialPageRequestCount > 1 {
            try await Task.sleep(nanoseconds: 3_000_000_000)
        }
        let prefix = source.accessibilityName
        if !MissCatShellFixtureLaunch.usesActionTimeline {
            let notes = [
                MissCatNote(
                    id: "\(prefix)-0",
                    author: MissCatNoteAuthor(
                        id: "fixture-author-syuilo",
                        name: "しゅいろ",
                        username: "syuilo",
                        localAvatarImageName: "TimelineFixtureAvatarSyuilo"
                    ),
                    createdAt: MissCatShellFixtureLaunch.referenceDate.addingTimeInterval(-57),
                    text: "PowerShell7 入れてみた",
                    attachments: [
                        MissCatNoteAttachment(
                            id: "fixture-terminal",
                            name: "PowerShell 7",
                            kind: .image,
                            url: nil,
                            localImageName: "TimelineFixtureTerminal"
                        )
                    ],
                    reactions: [MissCatReaction(name: "😮", count: 1)]
                ),
                MissCatNote(
                    id: "\(prefix)-1",
                    author: MissCatNoteAuthor(
                        id: "fixture-author-liquid",
                        name: "さー :verified:",
                        username: "u1_liquid",
                        localAvatarImageName: "TimelineFixtureAvatarLiquid",
                        localEmojis: ["verified": "TimelineFixtureEmojiVerified"]
                    ),
                    createdAt: MissCatShellFixtureLaunch.referenceDate.addingTimeInterval(-120),
                    text: "コピペみすった",
                    reactions: [MissCatReaction(name: "😌", count: 2, isMine: true)]
                ),
                MissCatNote(
                    id: "\(prefix)-2",
                    author: MissCatNoteAuthor(
                        id: "fixture-author-wada",
                        name: "だわくん :yellow: :verified: :erai:",
                        username: "wada",
                        localAvatarImageName: "TimelineFixtureAvatarWada",
                        localEmojis: [
                            "yellow": "TimelineFixtureEmojiYellow",
                            "verified": "TimelineFixtureEmojiVerified",
                            "erai": "TimelineFixtureEmojiErai"
                        ]
                    ),
                    createdAt: MissCatShellFixtureLaunch.referenceDate.addingTimeInterval(-180),
                    text: "スクショ撮る 🐈\n ",
                    reactions: [MissCatReaction(name: "😆", count: 1)]
                ),
                MissCatNote(
                    id: "\(prefix)-3",
                    author: MissCatNoteAuthor(
                        id: "fixture-author-aqz",
                        name: "aqz",
                        username: "aqz",
                        localAvatarImageName: "TimelineFixtureAvatarAqz"
                    ),
                    createdAt: MissCatShellFixtureLaunch.referenceDate.addingTimeInterval(-360),
                    text: "18時過ぎに停電したので1hは経ってるにゃ"
                )
            ]
            return MissCatFeedPage(
                notes: Array(notes.prefix(min(limit, notes.count))),
                hasMore: false
            )
        }
        return MissCatFeedPage(
            notes: (0 ..< min(limit, 30)).map { index in
                MissCatNote(
                    id: "\(prefix)-\(index)",
                    author: MissCatNoteAuthor(
                        id: "fixture-author-\(index % 3)",
                        name: ["Miss Cat", "Yuigawada", "Neko" ][index % 3],
                        username: ["misscat", "developer", "neko"][index % 3],
                        isCat: index % 2 == 0
                    ),
                    createdAt: Date(timeIntervalSince1970: 1_596_288_600 - Double(index * 180)),
                    text: index == 0
                        ? "SwiftUI native timeline fixture 🐈 @alice https://fixture.example/notes/\(prefix)-0 #SwiftUI"
                        : "Deterministic note \(index + 1)",
                    reactions: index == 0 ? [MissCatReaction(name: "👍", count: 3)] : [],
                    repliesCount: index % 2,
                    renoteCount: index % 3
                )
            },
            hasMore: MissCatShellFixtureLaunch.paginationEnabled
        )
    }

    func fetchThread(noteID: String, replyLimit: Int) async throws -> MissCatNoteThread {
        detailThreadRequestCount += 1
        let note = MissCatNote(
            id: noteID,
            author: MissCatNoteAuthor(
                id: scope.userID,
                name: "Miss Cat",
                username: scope.username,
                isCat: true
            ),
            createdAt: MissCatShellFixtureLaunch.referenceDate.addingTimeInterval(-600),
            text: "SwiftUI native timeline fixture 🐈 https://fixture.example/notes/\(noteID) #SwiftUI",
            reactions: [MissCatReaction(name: "👍", count: 3)],
            repliesCount: 1,
            renoteCount: 2
        )
        guard MissCatShellFixtureLaunch.paginationEnabled else {
            return MissCatNoteThread(ancestors: [], note: note, replies: [])
        }
        if detailThreadRequestCount > 1 {
            return MissCatNoteThread(
                ancestors: [],
                note: note,
                replies: [Self.detailReply(id: "\(noteID)-reply-refreshed")],
                repliesCursor: "\(noteID)-reply-refreshed",
                hasMoreReplies: false
            )
        }
        return MissCatNoteThread(
            ancestors: [],
            note: note,
            replies: [Self.detailReply(id: "\(noteID)-reply-page1")],
            repliesCursor: "\(noteID)-reply-page1",
            hasMoreReplies: true
        )
    }

    func fetchReplies(
        noteID: String,
        cursor: String?,
        limit: Int
    ) async throws -> MissCatNoteRepliesPage {
        switch cursor {
        case "\(noteID)-reply-page1":
            return MissCatNoteRepliesPage(
                replies: [
                    Self.detailReply(id: "\(noteID)-reply-page1"),
                    Self.detailReply(id: "\(noteID)-reply-page2"),
                ],
                nextCursor: "\(noteID)-reply-page2",
                hasMore: true
            )
        case "\(noteID)-reply-page2":
            return MissCatNoteRepliesPage(
                replies: [
                    Self.detailReply(id: "\(noteID)-reply-page2"),
                    Self.detailReply(id: "\(noteID)-reply-page3"),
                ],
                nextCursor: "\(noteID)-reply-page3",
                hasMore: false
            )
        default:
            return MissCatNoteRepliesPage(replies: [], nextCursor: nil, hasMore: false)
        }
    }

    func realtimeEvents(
        source: MissCatFeedSource,
        capturing noteIDs: [String]
    ) -> AsyncStream<MissCatRealtimeEvent> {
        AsyncStream { continuation in
            if mode == .offline {
                continuation.yield(.connected(false))
                continuation.yield(.failed(message: "Fixture offline"))
                continuation.finish()
            } else {
                continuation.yield(.connected(true))
            }
        }
    }

    func perform(_ action: MissCatFeedAction) async throws {}

    var accountIdentifier: String { scope.id }
    var currentServerUserID: String { scope.userID }

    func notePermalink(noteID: String) -> URL? {
        URL(string: "https://fixture.example/notes/\(noteID)")
    }

    func cachedURLPreview(for url: URL) -> MissCatURLPreview? {
        MissCatURLPreview(
            sourceURL: url,
            title: "MissCat SwiftUI timeline",
            description: "Deterministic URL preview fixture",
            siteName: "fixture.example"
        )
    }

    func fetchURLPreview(for url: URL) async throws -> MissCatURLPreview {
        cachedURLPreview(for: url)!
    }

    func fetchReactionChoices() async throws -> [MissCatReactionChoice] {
        [.init(value: "👍"), .init(value: "❤️"), .init(value: ":misscat:")]
    }

    func resolveMention(_ acct: String) async throws -> String {
        guard acct == "alice" || acct == "alice@fixture.example" else {
            throw MissCatMentionResolutionError.invalidAccount(acct)
        }
        return "fixture-mentioned-user"
    }

    private static func detailReply(id: String) -> MissCatNote {
        MissCatNote(
            id: id,
            author: MissCatNoteAuthor(
                id: "fixture-detail-replier",
                name: "Reply Cat",
                username: "replycat"
            ),
            createdAt: MissCatShellFixtureLaunch.referenceDate.addingTimeInterval(-900),
            text: "Deterministic detail reply \(id)"
        )
    }
}

private enum MissCatShellFixtureError: LocalizedError {
    case expected
    case persistence

    var errorDescription: String? {
        switch self {
        case .expected: "Fixture network error"
        case .persistence: "Fixture persistence error"
        }
    }
}
#endif
