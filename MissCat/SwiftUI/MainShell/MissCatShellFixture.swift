#if DEBUG
import Foundation
import SwiftUI

enum MissCatShellFixtureLaunch {
    enum Mode {
        case populated
        case empty
        case error
    }

    static let launchArgument = "--swiftui-shell-fixture"
    static var isRequested: Bool { CommandLine.arguments.contains(launchArgument) }

    static var mode: Mode {
        if CommandLine.arguments.contains("--swiftui-shell-fixture-empty") { return .empty }
        if CommandLine.arguments.contains("--swiftui-shell-fixture-error") { return .error }
        return .populated
    }
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

    init() {
        let provider = MissCatShellFixtureProvider(mode: MissCatShellFixtureLaunch.mode)
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
                    shell(configuration)
                }
            }
        }
        .task { await store.load() }
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
            onSearch: { presentedRoute = .search },
            onCompose: { presentedRoute = .compose },
            onSettings: { presentedRoute = .settings },
            onAccountSelected: { scope in
                Task { await store.switchAccount(to: scope) }
            },
            onTimelineSelection: store.selectTimeline,
            onReselect: { section in
                _ = store.activateFooter(destination(for: section))
            }
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
        .overlay(alignment: .bottomTrailing) {
            Text("shell-feed-bundle-ready-v1")
                .font(.system(size: 1))
                .opacity(0.01)
                .frame(width: 1, height: 1)
                .accessibilityIdentifier("migration.shell-feed.ready")
        }
        .accessibilityIdentifier("migration.shell-feed.fixture")
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
    private let accounts: [MissCatShellAccount]
    private var currentScope: MissCatShellAccountScope
    private var selections: [MissCatShellAccountScope: String] = [:]
    private var repositories: [MissCatShellAccountScope: MissCatShellFixtureRepository] = [:]

    init(mode: MissCatShellFixtureLaunch.Mode) {
        self.mode = mode
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
        selections[scope] = selectedID
    }

    func repository(for scope: MissCatShellAccountScope) throws -> any MissCatFeedRepository {
        if let repository = repositories[scope] { return repository }
        let repository = MissCatShellFixtureRepository(mode: mode)
        repositories[scope] = repository
        return repository
    }

    private func configuration(for scope: MissCatShellAccountScope) -> MissCatShellConfiguration {
        let pages = [
            MissCatTimelinePage(id: "\(scope.id)|home", title: "Home", source: .home, accountScope: scope, accessibilityID: "home"),
            MissCatTimelinePage(id: "\(scope.id)|local", title: "Local", source: .local, accountScope: scope, accessibilityID: "local"),
            MissCatTimelinePage(id: "\(scope.id)|global", title: "Global", source: .global, accountScope: scope, accessibilityID: "global")
        ]
        return MissCatShellConfiguration(
            currentScope: scope,
            accounts: accounts,
            timelinePages: pages,
            selectedTimelineID: selections[scope] ?? pages[0].id,
            appearance: MissCatShellAppearance(isDark: false, accentHex: MissCatLegacyColorHex.accent)
        )
    }
}

private final class MissCatShellFixtureRepository: MissCatFeedRepository {
    private let mode: MissCatShellFixtureLaunch.Mode

    init(mode: MissCatShellFixtureLaunch.Mode) {
        self.mode = mode
    }

    func fetchPage(source: MissCatFeedSource, cursor: String?, limit: Int) async throws -> MissCatFeedPage {
        if mode == .error { throw MissCatShellFixtureError.expected }
        if mode == .empty || cursor != nil { return MissCatFeedPage(notes: [], hasMore: false) }
        let prefix = source.accessibilityName
        return MissCatFeedPage(
            notes: (0 ..< min(limit, 8)).map { index in
                MissCatNote(
                    id: "\(prefix)-\(index)",
                    author: MissCatNoteAuthor(
                        id: "fixture-author-\(index % 3)",
                        name: ["Miss Cat", "Yuigawada", "Neko" ][index % 3],
                        username: ["misscat", "developer", "neko"][index % 3],
                        isCat: index % 2 == 0
                    ),
                    createdAt: Date(timeIntervalSince1970: 1_596_288_600 - Double(index * 180)),
                    text: index == 0 ? "SwiftUI native timeline fixture 🐈" : "Deterministic note \(index + 1)",
                    reactions: index == 0 ? [MissCatReaction(name: "👍", count: 3)] : [],
                    repliesCount: index % 2,
                    renoteCount: index % 3
                )
            },
            hasMore: false
        )
    }

    func fetchThread(noteID: String, replyLimit: Int) async throws -> MissCatNoteThread {
        throw MissCatShellFixtureError.expected
    }

    func realtimeEvents(
        source: MissCatFeedSource,
        capturing noteIDs: [String]
    ) -> AsyncStream<MissCatRealtimeEvent> {
        AsyncStream { continuation in
            continuation.yield(.connected(true))
        }
    }

    func perform(_ action: MissCatFeedAction) async throws {}
}

private enum MissCatShellFixtureError: LocalizedError {
    case expected

    var errorDescription: String? { "Fixture network error" }
}
#endif
