import Combine
import Foundation

/// Non-secret identity for all shell-owned account state. A Misskey user ID is not
/// sufficient on its own because IDs are only authoritative within an instance.
public struct MissCatShellAccountScope: Hashable, Identifiable, Sendable {
    public let instance: String
    public let userID: String
    public let username: String

    public init(instance: String, userID: String, username: String) {
        self.instance = Self.normalize(instance)
        self.userID = userID
        self.username = username
    }

    public var id: String { "\(instance)|\(userID)" }

    public var displayInstance: String {
        URLComponents(string: instance)?.host ?? instance
    }

    private static func normalize(_ instance: String) -> String {
        let trimmed = instance.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard var components = URLComponents(string: candidate),
              let host = components.host?.lowercased(),
              !host.isEmpty else {
            return trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        }

        components.scheme = (components.scheme ?? "https").lowercased()
        components.host = host
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return components.string?.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            ?? trimmed.lowercased()
    }
}

public struct MissCatShellAccount: Identifiable, Equatable, Sendable {
    public let scope: MissCatShellAccountScope
    public let displayName: String
    public let avatarURL: URL?

    public init(
        scope: MissCatShellAccountScope,
        displayName: String? = nil,
        avatarURL: URL? = nil
    ) {
        self.scope = scope
        self.displayName = displayName?.isEmpty == false ? displayName! : "@\(scope.username)"
        self.avatarURL = avatarURL
    }

    public var id: String { scope.id }
}

public struct MissCatShellAppearance: Equatable, Sendable {
    public let isDark: Bool
    public let accentHex: String

    public init(isDark: Bool, accentHex: String) {
        self.isDark = isDark
        let filtered = accentHex.uppercased().filter(\.isHexDigit)
        self.accentHex = filtered.count == 6 ? filtered : MissCatLegacyColorHex.accent
    }

    public var palette: MissCatVisualPalette {
        var palette = isDark ? MissCatVisualPalette.legacyDark : .legacyLight
        palette.accent = .init(hex: accentHex)
        return palette
    }
}

public struct MissCatShellConfiguration: Equatable, Sendable {
    public let currentScope: MissCatShellAccountScope
    public let accounts: [MissCatShellAccount]
    public let timelinePages: [MissCatTimelinePage]
    public let selectedTimelineID: String
    public let appearance: MissCatShellAppearance

    public init(
        currentScope: MissCatShellAccountScope,
        accounts: [MissCatShellAccount],
        timelinePages: [MissCatTimelinePage],
        selectedTimelineID: String,
        appearance: MissCatShellAppearance
    ) {
        self.currentScope = currentScope
        self.accounts = accounts
        self.timelinePages = timelinePages
        self.selectedTimelineID = timelinePages.contains(where: { $0.id == selectedTimelineID })
            ? selectedTimelineID
            : (timelinePages.first?.id ?? "")
        self.appearance = appearance
    }
}

public enum MissCatShellConfigurationError: LocalizedError, Equatable {
    case noCurrentAccount
    case accountNotFound
    case accountIdentityMismatch
    case missingCredential

    public var errorDescription: String? {
        switch self {
        case .noCurrentAccount: "ログイン中のアカウントがありません。"
        case .accountNotFound: "アカウントが見つかりません。"
        case .accountIdentityMismatch: "アカウントのインスタンスを確認できません。"
        case .missingCredential: "アカウントの認証情報を確認できません。"
        }
    }
}

/// The only boundary through which the native shell can see legacy Theme/Cache data.
/// Credentials stay behind this protocol and are captured by an opaque repository.
@MainActor
public protocol MissCatShellConfigurationProviding: AnyObject {
    func loadConfiguration() async throws -> MissCatShellConfiguration
    func switchAccount(to scope: MissCatShellAccountScope) async throws -> MissCatShellConfiguration
    func saveSelectedTimelineID(_ selectedID: String, for scope: MissCatShellAccountScope) async throws
    func repository(for scope: MissCatShellAccountScope) throws -> any MissCatFeedRepository
}

public enum MissCatFooterDestination: String, CaseIterable, Identifiable, Sendable {
    case home
    case notifications
    case compose
    case messages
    case profile

    public var id: String { rawValue }

    public var rootSection: MissCatRootSection? {
        switch self {
        case .home: .home
        case .notifications: .notifications
        case .compose: nil
        case .messages: .messages
        case .profile: .profile
        }
    }
}

public enum MissCatFooterActivation: Equatable, Sendable {
    case selected(MissCatRootSection)
    case reselected(MissCatRootSection)
    case composeRequested
}

public struct MissCatFooterSelectionState: Equatable, Sendable {
    public private(set) var selectedSection: MissCatRootSection

    public init(selectedSection: MissCatRootSection = .home) {
        self.selectedSection = selectedSection
    }

    @discardableResult
    public mutating func activate(_ destination: MissCatFooterDestination) -> MissCatFooterActivation {
        guard let section = destination.rootSection else { return .composeRequested }
        guard selectedSection != section else { return .reselected(section) }
        selectedSection = section
        return .selected(section)
    }
}

@MainActor
public final class MissCatShellStore: ObservableObject {
    public enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published public private(set) var phase: Phase = .idle
    @Published public private(set) var configuration: MissCatShellConfiguration?
    @Published public private(set) var selectedSection: MissCatRootSection = .home
    @Published public private(set) var selectedTimelineID = ""
    @Published public private(set) var timelineSelectionOrigin = MissCatTimelineSelectionOrigin.initial
    @Published public private(set) var homeScrollToTopGeneration = 0
    @Published public private(set) var notificationsScrollToTopGeneration = 0
    @Published public private(set) var bannerMessage: String?

    private let provider: any MissCatShellConfigurationProviding
    private var footerState = MissCatFooterSelectionState()
    private var persistenceTask: Task<Void, Never>?
    private var configurationLoadTask: Task<Void, Never>?
    private var accountSwitchTask: Task<Void, Never>?
    private var configurationGeneration = 0
    private var accountSwitchTarget: MissCatShellAccountScope?
    private var repositories: [MissCatShellAccountScope: any MissCatFeedRepository] = [:]
    private struct PendingTimelineSelection {
        let selectedID: String
        let scope: MissCatShellAccountScope
    }
    private var pendingTimelineSelection: PendingTimelineSelection?
    private var persistenceGeneration: UInt64 = 0
    @Published private var timelineScrollPositions = MissCatTimelineScrollPositionState()

    public init(provider: any MissCatShellConfigurationProviding) {
        self.provider = provider
    }

    deinit {
        persistenceTask?.cancel()
        configurationLoadTask?.cancel()
        accountSwitchTask?.cancel()
    }

    public func load() async {
        if let configurationLoadTask {
            await configurationLoadTask.value
            return
        }
        guard phase == .idle || isFailed else { return }
        configurationGeneration &+= 1
        let generation = configurationGeneration
        phase = .loading
        let task = Task { @MainActor [weak self, provider] in
            do {
                let configuration = try await provider.loadConfiguration()
                guard let self,
                      self.configurationGeneration == generation,
                      !Task.isCancelled else { return }
                self.configurationLoadTask = nil
                self.apply(configuration)
                self.phase = .loaded
            } catch is CancellationError {
                guard let self, self.configurationGeneration == generation else { return }
                self.configurationLoadTask = nil
                self.phase = .idle
            } catch {
                guard let self, self.configurationGeneration == generation else { return }
                self.configurationLoadTask = nil
                self.phase = .failed(Self.message(for: error))
            }
        }
        configurationLoadTask = task
        await task.value
    }

    public func retry() async {
        phase = .idle
        await load()
    }

    public func selectTimeline(
        _ candidate: String,
        origin: MissCatTimelineSelectionOrigin
    ) {
        guard let configuration else { return }
        var state = MissCatTimelineSelectionState(
            pageIDs: configuration.timelinePages.map(\.id),
            selectedID: selectedTimelineID
        )
        guard state.select(candidate, origin: origin) else { return }
        guard state.selectedID != selectedTimelineID || origin != timelineSelectionOrigin else { return }

        selectedTimelineID = state.selectedID
        timelineSelectionOrigin = origin
        pendingTimelineSelection = PendingTimelineSelection(
            selectedID: state.selectedID,
            scope: configuration.currentScope
        )
        startTimelinePersistenceIfNeeded()
    }

    @discardableResult
    public func activateFooter(_ destination: MissCatFooterDestination) -> MissCatFooterActivation {
        let activation = footerState.activate(destination)
        switch activation {
        case let .selected(section):
            selectedSection = section
        case let .reselected(section):
            if section == .home { homeScrollToTopGeneration += 1 }
            if section == .notifications { notificationsScrollToTopGeneration += 1 }
        case .composeRequested:
            break
        }
        return activation
    }

    public func switchAccount(to scope: MissCatShellAccountScope) {
        if scope == configuration?.currentScope {
            guard accountSwitchTask != nil else { return }
            accountSwitchTask?.cancel()
            accountSwitchTask = nil
            accountSwitchTarget = nil
            configurationGeneration &+= 1
            phase = configuration == nil ? .idle : .loaded
            return
        }
        guard scope != accountSwitchTarget else { return }
        cancelTimelinePersistence()
        configurationLoadTask?.cancel()
        configurationLoadTask = nil
        accountSwitchTask?.cancel()
        configurationGeneration &+= 1
        let generation = configurationGeneration
        accountSwitchTarget = scope
        phase = .loading
        accountSwitchTask = Task { @MainActor [weak self, provider] in
            do {
                let configuration = try await provider.switchAccount(to: scope)
                guard let self,
                      self.configurationGeneration == generation,
                      !Task.isCancelled else { return }
                guard configuration.currentScope == scope else {
                    throw MissCatShellConfigurationError.accountIdentityMismatch
                }
                self.accountSwitchTask = nil
                self.accountSwitchTarget = nil
                self.apply(configuration)
                self.phase = .loaded
            } catch is CancellationError {
                guard let self, self.configurationGeneration == generation else { return }
                self.accountSwitchTask = nil
                self.accountSwitchTarget = nil
                self.phase = self.configuration == nil ? .idle : .loaded
            } catch {
                guard let self, self.configurationGeneration == generation else { return }
                self.accountSwitchTask = nil
                self.accountSwitchTarget = nil
                self.phase = self.configuration == nil ? .failed(Self.message(for: error)) : .loaded
                self.bannerMessage = Self.message(for: error)
            }
        }
    }

    public func cancelConfigurationTasks() {
        configurationGeneration &+= 1
        cancelTimelinePersistence()
        configurationLoadTask?.cancel()
        accountSwitchTask?.cancel()
        configurationLoadTask = nil
        accountSwitchTask = nil
        accountSwitchTarget = nil
        phase = configuration == nil ? .idle : .loaded
    }

    public func repository(for scope: MissCatShellAccountScope) -> (any MissCatFeedRepository)? {
        guard configuration?.accounts.contains(where: { $0.scope == scope }) == true else {
            bannerMessage = Self.message(for: MissCatShellConfigurationError.accountNotFound)
            return nil
        }
        if let repository = repositories[scope] { return repository }
        do {
            let repository = try provider.repository(for: scope)
            repositories[scope] = repository
            return repository
        } catch {
            bannerMessage = Self.message(for: error)
            return nil
        }
    }

    public func dismissBanner() {
        bannerMessage = nil
    }

    public func timelineScrollPosition(for key: MissCatTimelineScrollKey) -> String? {
        timelineScrollPositions.position(for: key)
    }

    public func setTimelineScrollPosition(_ noteID: String?, for key: MissCatTimelineScrollKey) {
        timelineScrollPositions.setPosition(noteID, for: key)
    }

    func waitForPendingPersistence() async {
        await persistenceTask?.value
    }

    func waitForPendingAccountSwitch() async {
        await accountSwitchTask?.value
    }

    private var isFailed: Bool {
        if case .failed = phase { return true }
        return false
    }

    private func apply(_ configuration: MissCatShellConfiguration) {
        let authorizedScopes = Set(configuration.accounts.map(\.scope))
        repositories = repositories.filter { authorizedScopes.contains($0.key) }
        self.configuration = configuration
        selectedTimelineID = configuration.selectedTimelineID
        timelineSelectionOrigin = .initial
    }

    private func startTimelinePersistenceIfNeeded() {
        guard persistenceTask == nil else { return }
        let generation = persistenceGeneration
        persistenceTask = Task { @MainActor [weak self, provider] in
            while let self,
                  self.persistenceGeneration == generation,
                  !Task.isCancelled,
                  let pending = self.pendingTimelineSelection {
                self.pendingTimelineSelection = nil
                do {
                    try await provider.saveSelectedTimelineID(
                        pending.selectedID,
                        for: pending.scope
                    )
                } catch is CancellationError {
                    break
                } catch {
                    self.bannerMessage = Self.message(for: error)
                }
            }
            guard let self, self.persistenceGeneration == generation else { return }
            self.persistenceTask = nil
        }
    }

    private func cancelTimelinePersistence() {
        persistenceGeneration &+= 1
        pendingTimelineSelection = nil
        persistenceTask?.cancel()
        persistenceTask = nil
    }

    private static func message(for error: Error) -> String {
        let value = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "データ処理に失敗しました。" : trimmed
    }
}

/// Adapter retained only until the account/theme kernel replaces Cache and Theme.
/// No SwiftUI view reaches either legacy singleton directly.
@MainActor
final class MissCatLegacyShellConfigurationProvider: MissCatShellConfigurationProviding {
    private let cache: Cache.UserDefaults
    private let defaults: Foundation.UserDefaults
    private let selectionKeyPrefix = "swiftui-shell-selected-timeline-v1"

    init(
        cache: Cache.UserDefaults = .shared,
        defaults: Foundation.UserDefaults = .standard
    ) {
        self.cache = cache
        self.defaults = defaults
    }

    func loadConfiguration() async throws -> MissCatShellConfiguration {
        try Task.checkCancellation()
        guard let currentUser = cache.getCurrentUser() else {
            throw MissCatShellConfigurationError.noCurrentAccount
        }
        return try makeConfiguration(currentUser: currentUser)
    }

    func switchAccount(to scope: MissCatShellAccountScope) async throws -> MissCatShellConfiguration {
        try Task.checkCancellation()
        guard let user = exactUser(for: scope) else {
            throw MissCatShellConfigurationError.accountNotFound
        }
        cache.changeCurrentUser(userId: user.userId)
        guard let persisted = cache.getCurrentUser(), self.scope(for: persisted) == scope else {
            throw MissCatShellConfigurationError.accountIdentityMismatch
        }
        Theme.shared.reset()
        Theme.shared.set()
        return try makeConfiguration(currentUser: persisted)
    }

    func saveSelectedTimelineID(
        _ selectedID: String,
        for scope: MissCatShellAccountScope
    ) async throws {
        try Task.checkCancellation()
        defaults.set(selectedID, forKey: selectionKey(for: scope))
    }

    func repository(for scope: MissCatShellAccountScope) throws -> any MissCatFeedRepository {
        guard let user = exactUser(for: scope) else {
            throw MissCatShellConfigurationError.accountNotFound
        }
        guard user.apiKey?.isEmpty == false,
              let repository = MissCatMisskeyFeedRepository(user: user) else {
            throw MissCatShellConfigurationError.missingCredential
        }
        return repository
    }

    private func makeConfiguration(currentUser: SecureUser) throws -> MissCatShellConfiguration {
        if Theme.shared.currentModel == nil { Theme.shared.set() }
        let users = cache.getUsers()
        let currentScope = scope(for: currentUser)
        let accounts = users.map { user in
            let scope = scope(for: user)
            return MissCatShellAccount(scope: scope)
        }
        let theme = Theme.shared.currentModel ?? Theme.Model.getDefault()
        let pages = Self.makePages(theme: theme, users: users, currentScope: currentScope)
        let selectedID = defaults.string(forKey: selectionKey(for: currentScope)) ?? pages.first?.id ?? ""
        return MissCatShellConfiguration(
            currentScope: currentScope,
            accounts: accounts,
            timelinePages: pages,
            selectedTimelineID: selectedID,
            appearance: MissCatShellAppearance(
                isDark: theme?.colorMode == .dark,
                accentHex: theme?.mainColorHex ?? MissCatLegacyColorHex.accent
            )
        )
    }

    private static func makePages(
        theme: Theme.Model?,
        users: [SecureUser],
        currentScope: MissCatShellAccountScope
    ) -> [MissCatTimelinePage] {
        let scopes = users.map {
            MissCatShellAccountScope(instance: $0.instance, userID: $0.userId, username: $0.username)
        }
        var occurrenceCounts: [String: Int] = [:]
        let pages = (theme?.tab ?? []).enumerated().compactMap { index, tab -> MissCatTimelinePage? in
            guard let scope = resolvePageOwnerScope(
                userID: tab.userId,
                among: scopes,
                currentScope: currentScope
            ) else { return nil }
            let source: MissCatFeedSource
            switch tab.kind {
            case .home: source = .home
            case .local: source = .local
            case .social: source = .social
            case .global: source = .global
            case .user:
                source = .user(
                    userID: tab.userId ?? scope.userID,
                    includeReplies: false,
                    withFiles: false
                )
            case .list:
                guard let listID = tab.listId, !listID.isEmpty else { return nil }
                source = .userList(listID: listID)
            }

            let signature = "\(scope.id)|\(tab.kind.rawValue)|\(tab.listId ?? "")"
            let occurrence = occurrenceCounts[signature, default: 0]
            occurrenceCounts[signature] = occurrence + 1
            let title = tab.name == "___Home___" ? "Home" : (tab.name.isEmpty ? tab.kind.rawValue.capitalized : tab.name)
            return MissCatTimelinePage(
                id: "\(signature)|\(occurrence)",
                title: title,
                source: source,
                accountScope: scope,
                accessibilityID: "configured-\(index)-\(tab.kind.rawValue)"
            )
        }

        guard pages.isEmpty else { return pages }
        return [
            .init(id: "\(currentScope.id)|home|0", title: "Home", source: .home, accountScope: currentScope, accessibilityID: "configured-0-home"),
            .init(id: "\(currentScope.id)|local|0", title: "Local", source: .local, accountScope: currentScope, accessibilityID: "configured-1-local"),
            .init(id: "\(currentScope.id)|global|0", title: "Global", source: .global, accountScope: currentScope, accessibilityID: "configured-2-global")
        ]
    }

    static func resolvePageOwnerScope(
        userID: String?,
        among scopes: [MissCatShellAccountScope],
        currentScope: MissCatShellAccountScope
    ) -> MissCatShellAccountScope? {
        let requestedUserID = userID ?? currentScope.userID
        if requestedUserID == currentScope.userID {
            return scopes.contains(currentScope) ? currentScope : nil
        }

        let matches = scopes.filter { $0.userID == requestedUserID }
        return matches.count == 1 ? matches[0] : nil
    }

    private func exactUser(for target: MissCatShellAccountScope) -> SecureUser? {
        cache.getUsers().first { scope(for: $0) == target }
    }

    private func scope(for user: SecureUser) -> MissCatShellAccountScope {
        MissCatShellAccountScope(instance: user.instance, userID: user.userId, username: user.username)
    }

    private func selectionKey(for scope: MissCatShellAccountScope) -> String {
        "\(selectionKeyPrefix).\(scope.id)"
    }
}
