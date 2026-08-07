import Foundation

@MainActor
final class MissCatLegacySettingsRepository:
    MissCatAccountManaging,
    MissCatDesignSettingsManaging,
    MissCatReactionSettingsManaging
{
    private struct CurrentAccountResponse: Decodable {
        let id: String
        let username: String?
        let name: String?
        let avatarUrl: String?
    }

    private let cache: Cache.UserDefaults
    private let session: URLSession
    private let theme: Theme
    private let emojiStorage: EmojiArchiveStorage

    init(
        cache: Cache.UserDefaults = .shared,
        session: URLSession = .shared,
        theme: Theme = .shared,
        emojiStorage: EmojiArchiveStorage = .standard
    ) {
        self.cache = cache
        self.session = session
        self.theme = theme
        self.emojiStorage = emojiStorage
    }

    func loadAccounts() async throws -> MissCatAccountSnapshot {
        let users = cache.getUsers()
        var summaries: [MissCatAccountSummary] = []
        summaries.reserveCapacity(users.count)

        for user in users {
            try Task.checkCancellation()
            summaries.append(await summary(for: user))
        }

        return MissCatAccountSnapshot(
            accounts: summaries,
            currentAccountID: cache.getCurrentUserId()
        )
    }

    func switchAccount(id: String) async throws -> MissCatAccountSnapshot {
        try Task.checkCancellation()
        guard let user = exactUser(accountIdentifier: id) else {
            throw MissCatAccountManagementError.accountNotFound
        }

        guard cache.changeCurrentUser(userId: user.accountIdentifier),
              cache.getCurrentUserId() == user.accountIdentifier,
              exactUser(accountIdentifier: user.accountIdentifier) != nil
        else {
            throw MissCatAccountManagementError.currentAccountVerificationFailed
        }

        Cache.shared.resetMyCache()
        theme.reset()
        theme.set()
        // Once the persisted current account changes, do not introduce another
        // suspension/cancellation point before returning the verified state.
        return metadataSnapshot()
    }

    func deleteAccount(id: String) async throws -> MissCatAccountDeletionResult {
        try Task.checkCancellation()
        guard let user = exactUser(accountIdentifier: id) else {
            throw MissCatAccountManagementError.accountNotFound
        }

        // Cache.UserDefaults owns the credential/metadata transaction. Do not update
        // tabs or UI state until it confirms that the Keychain entry was removed.
        guard cache.removeUser(userId: user.accountIdentifier) else {
            throw MissCatAccountManagementError.accountPersistenceFailed
        }
        let tabsChanged = theme.removeUserTabs(for: user)
        Cache.shared.resetMyCache()
        // Credential removal is the persistence boundary. Build the resulting
        // state synchronously so cancellation cannot hide a committed deletion.
        let snapshot = metadataSnapshot()
        return MissCatAccountDeletionResult(
            snapshot: snapshot,
            removedConfiguredTabs: tabsChanged
        )
    }

    func loadDesignSettings() async throws -> MissCatDesignSettingsSnapshot {
        if theme.currentModel == nil { theme.set() }
        let accounts = metadataSnapshot().accounts
        guard let model = theme.currentModel ?? Theme.Model.getDefault() else {
            return MissCatDesignSettingsSnapshot(
                tabs: MissCatDesignSettingsStore.defaultTabs(accountID: accounts.first?.id),
                mode: .light,
                accentHex: "2F7CF6",
                accounts: accounts
            )
        }

        return MissCatDesignSettingsSnapshot(
            tabs: model.tab.map(settingsTab(from:)),
            mode: model.colorMode == .light ? .light : .dark,
            accentHex: MissCatDesignSettingsStore.normalizedHex(model.mainColorHex),
            accounts: accounts
        )
    }

    func saveDesignSettings(
        _ snapshot: MissCatDesignSettingsSnapshot
    ) async throws -> MissCatDesignSaveResult {
        try Task.checkCancellation()
        let old = theme.currentModel
        let availableIDs = Set(snapshot.accounts.map(\.id))
        let fallbackOwnerID = snapshot.accounts.first?.id
        let tabs = snapshot.tabs.map { tab in
            Theme.Tab(
                name: tab.name.isEmpty ? tab.kind.defaultName : tab.name,
                kind: legacyKind(from: tab.kind),
                userId: tab.accountID.flatMap { availableIDs.contains($0) ? $0 : fallbackOwnerID }
                    ?? fallbackOwnerID,
                listId: tab.listID
            )
        }
        let newModel = Theme.Model(
            tab: tabs,
            mainColorHex: MissCatDesignSettingsStore.normalizedHex(snapshot.accentHex),
            colorMode: snapshot.mode == .light ? .light : .dark
        )
        let requiresRootRelaunch = old.map { Theme.needAllRelaunch(between: $0, and: newModel) } ?? false
        let persisted: Theme.Model
        do {
            persisted = try theme.saveAtomically(with: newModel)
        } catch {
            throw MissCatAccountManagementError.accountPersistenceFailed
        }

        return MissCatDesignSaveResult(
            snapshot: MissCatDesignSettingsSnapshot(
                tabs: persisted.tab.map(settingsTab(from:)),
                mode: persisted.colorMode == .light ? .light : .dark,
                accentHex: persisted.mainColorHex,
                accounts: snapshot.accounts
            ),
            requiresRootRelaunch: requiresRootRelaunch
        )
    }

    func loadReactionAccounts() async throws -> [MissCatReactionAccount] {
        var seen: Set<String> = []
        return cache.getUsers().compactMap { user in
            guard seen.insert(user.instance).inserted else { return nil }
            return MissCatReactionAccount(id: user.accountIdentifier, instance: user.instance)
        }
    }

    func loadReactions(accountID: String) async throws -> MissCatReactionSettingsSnapshot {
        try Task.checkCancellation()
        guard let owner = exactUser(accountIdentifier: accountID) else {
            throw MissCatAccountManagementError.accountNotFound
        }

        let saved = EmojiView.EmojiModel.getEmojis(
            type: .favs,
            owner: owner,
            storage: emojiStorage
        ) ?? []
        let history = Array((EmojiView.EmojiModel.getEmojis(
            type: .history,
            owner: owner,
            storage: emojiStorage
        ) ?? []).prefix(14))
        let favoriteModels: [EmojiView.EmojiModel]
        if saved.isEmpty {
            favoriteModels = MissCatReactionSettingsStore.legacyDefaults.map {
                EmojiView.EmojiModel(
                    rawEmoji: $0,
                    isDefault: true,
                    defaultEmoji: $0,
                    customEmojiUrl: nil
                )
            }
        } else {
            favoriteModels = saved
        }

        let defaultChoices = MissCatReactionSettingsStore.legacyDefaults.map {
            MissCatReactionItem(rawValue: $0, displayValue: $0)
        }
        let favoriteItems = favoriteModels.map { reactionItem(from: $0) }
        let historyItems = history.map { reactionItem(from: $0) }
        let categorized = categorizedReactionSections(for: owner)
        let available = unique(defaultChoices + categorized.flatMap(\.items))
        var sections: [MissCatReactionSection] = []
        if !favoriteItems.isEmpty {
            sections.append(.init(id: "favorites", title: "お気に入り", kind: .favorites, items: favoriteItems))
        }
        if !historyItems.isEmpty {
            sections.append(.init(id: "history", title: "履歴", kind: .history, items: historyItems))
        }
        sections.append(contentsOf: categorized)

        return MissCatReactionSettingsSnapshot(
            account: MissCatReactionAccount(id: owner.accountIdentifier, instance: owner.instance),
            favorites: favoriteItems,
            available: available,
            history: historyItems,
            sections: sections
        )
    }

    func saveReactions(_ snapshot: MissCatReactionSettingsSnapshot) async throws {
        try Task.checkCancellation()
        guard let owner = exactUser(accountIdentifier: snapshot.account.id),
              owner.instance == snapshot.account.instance
        else {
            throw MissCatAccountManagementError.accountNotFound
        }

        let models = snapshot.favorites.map { item in
            EmojiView.EmojiModel(
                rawEmoji: item.rawValue,
                isDefault: item.imageURL == nil,
                defaultEmoji: item.imageURL == nil ? (item.displayValue ?? item.rawValue) : nil,
                customEmojiUrl: item.imageURL?.absoluteString
            )
        }
        let persisted: [EmojiView.EmojiModel]
        do {
            persisted = try EmojiView.EmojiModel.saveEmojisChecked(
                with: models,
                type: .favs,
                owner: owner,
                storage: emojiStorage
            )
        } catch {
            throw MissCatAccountManagementError.accountPersistenceFailed
        }
        guard EmojiView.EmojiModel.archiveFieldsEqual(persisted, models) else {
            throw MissCatAccountManagementError.accountPersistenceFailed
        }
        EmojiRepository.shared.updateUserEmojis(to: .favs, owner: owner, new: persisted)
    }

    private func summary(for user: SecureUser) async -> MissCatAccountSummary {
        let cached = Cache.shared.getUserInfo(user: user)
        let fallback = MissCatAccountSummary(
            id: user.accountIdentifier,
            userID: user.userId,
            username: user.username,
            displayName: cached?.name,
            instance: user.instance
        )
        guard let token = user.apiKey, !token.isEmpty,
              let instance = try? MissCatInstance.normalize(user.instance),
              let url = URL(string: "/api/i", relativeTo: instance.origin)
        else { return fallback }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["i": token])

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200 ..< 300).contains(http.statusCode)
            else { return fallback }
            let profile = try JSONDecoder().decode(CurrentAccountResponse.self, from: data)
            guard profile.id == user.userId else { return fallback }
            return MissCatAccountSummary(
                id: user.accountIdentifier,
                userID: user.userId,
                username: profile.username ?? user.username,
                displayName: profile.name ?? cached?.name,
                instance: user.instance,
                avatarURL: profile.avatarUrl.flatMap(URL.init(string:))
            )
        } catch {
            return fallback
        }
    }

    private func metadataSnapshot() -> MissCatAccountSnapshot {
        MissCatAccountSnapshot(
            accounts: cache.getUsers().map { user in
                let cached = Cache.shared.getUserInfo(user: user)
                return MissCatAccountSummary(
                    id: user.accountIdentifier,
                    userID: user.userId,
                    username: user.username,
                    displayName: cached?.name,
                    instance: user.instance
                )
            },
            currentAccountID: cache.getCurrentUserId()
        )
    }

    private func exactUser(accountIdentifier: String) -> SecureUser? {
        cache.getUsers().first { $0.accountIdentifier == accountIdentifier }
    }

    private func settingsTab(from tab: Theme.Tab) -> MissCatSettingsTab {
        MissCatSettingsTab(
            name: tab.name,
            kind: settingsKind(from: tab.kind),
            accountID: tab.userId,
            listID: tab.listId
        )
    }

    private func settingsKind(from kind: Theme.TabKind) -> MissCatSettingsTabKind {
        switch kind {
        case .home: .home
        case .local: .local
        case .social: .social
        case .global: .global
        case .user: .user
        case .list: .list
        }
    }

    private func legacyKind(from kind: MissCatSettingsTabKind) -> Theme.TabKind {
        switch kind {
        case .home: .home
        case .local: .local
        case .social: .social
        case .global: .global
        case .user: .user
        case .list: .list
        }
    }

    private func categorizedReactionSections(for owner: SecureUser) -> [MissCatReactionSection] {
        guard let handler = EmojiHandler.getHandler(owner: owner) else {
            return [MissCatReactionSection(
                id: "standard-defaults",
                title: "標準絵文字",
                kind: .standard,
                items: MissCatReactionSettingsStore.legacyDefaults.map {
                    MissCatReactionItem(rawValue: $0, displayValue: $0)
                }
            )]
        }

        let custom = handler.categorizedCustomEmojis.keys.sorted().compactMap { category -> MissCatReactionSection? in
            let items = (handler.categorizedCustomEmojis[category] ?? []).map {
                reactionItem(from: $0, searchTerms: [category])
            }
            guard !items.isEmpty else { return nil }
            return .init(
                id: "custom-\(category)",
                title: category.isEmpty ? "カスタム" : category,
                kind: .custom,
                items: items
            )
        }
        let standard = handler.categorizedDefaultEmojis.keys.sorted().compactMap { category -> MissCatReactionSection? in
            let items = (handler.categorizedDefaultEmojis[category] ?? []).map {
                reactionItem(from: $0, searchTerms: [category])
            }
            guard !items.isEmpty else { return nil }
            return .init(
                id: "standard-\(category)",
                title: category.isEmpty ? "標準絵文字" : category,
                kind: .standard,
                items: items
            )
        }
        return custom + standard
    }

    private func reactionItem(
        from model: EmojiView.EmojiModel,
        searchTerms: [String] = []
    ) -> MissCatReactionItem {
        MissCatReactionItem(
            rawValue: model.rawEmoji,
            displayValue: model.defaultEmoji,
            imageURL: model.customEmojiUrl.flatMap(URL.init(string:)),
            searchTerms: searchTerms
        )
    }

    private func unique(_ items: [MissCatReactionItem]) -> [MissCatReactionItem] {
        var seen: Set<String> = []
        return items.filter { seen.insert($0.id).inserted }
    }

    static func persistedThemeMatches(_ persisted: Theme.Model, expected: Theme.Model) -> Bool {
        persisted.mainColorHex == expected.mainColorHex
            && persisted.colorMode == expected.colorMode
            && persisted.tab == expected.tab
    }
}

/// Deterministic, credential-free data used by UI automation and screenshot jobs.
/// It is opt-in through a debug-only launch argument and never reaches the network.
@MainActor
final class MissCatSettingsFixtureRepository:
    MissCatAccountManaging,
    MissCatDesignSettingsManaging,
    MissCatReactionSettingsManaging
{
    enum AccountMode {
        case populated
        case single
        case empty
        case failOnce
    }

    static var isEnabled: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--misscat-settings-fixture")
        #else
        false
        #endif
    }

    private var accountSnapshot: MissCatAccountSnapshot
    private var designSnapshot: MissCatDesignSettingsSnapshot
    private var reactionSnapshots: [String: MissCatReactionSettingsSnapshot]
    private var accountMode: AccountMode
    private var accountLoadCount = 0

    init(accountMode: AccountMode = .populated) {
        self.accountMode = accountMode
        let first = MissCatAccountSummary(
            id: "fixture-wada",
            username: "wada",
            displayName: "だわくん",
            instance: "misskey.example"
        )
        let second = MissCatAccountSummary(
            id: "fixture-sub",
            username: "sub",
            displayName: "Sub Account",
            instance: "social.example"
        )
        switch accountMode {
        case .empty:
            accountSnapshot = .init(accounts: [], currentAccountID: nil)
        case .single:
            accountSnapshot = .init(accounts: [first], currentAccountID: first.id)
        case .populated, .failOnce:
            accountSnapshot = .init(accounts: [first, second], currentAccountID: first.id)
        }
        designSnapshot = .init(
            tabs: [
                .init(name: "@wada", kind: .home, accountID: first.id),
                .init(name: "Local", kind: .local, accountID: first.id),
                .init(name: "Friends", kind: .list, accountID: first.id, listID: "fixture-list")
            ],
            mode: .light,
            accentHex: "2F7CF6",
            accounts: [first, second]
        )

        let account = MissCatReactionAccount(id: first.id, instance: first.instance)
        let secondAccount = MissCatReactionAccount(id: second.id, instance: second.instance)
        let favorites = MissCatReactionSettingsStore.legacyDefaults.prefix(8).map {
            MissCatReactionItem(rawValue: $0, displayValue: $0)
        }
        let custom = [
            MissCatReactionItem(
                rawValue: ":fixture_gif:",
                imageURL: Self.mediaFixtureURL(extension: "gif"),
                searchTerms: ["custom", "gif"]
            ),
            MissCatReactionItem(
                rawValue: ":fixture_apng:",
                imageURL: Self.mediaFixtureURL(extension: "apngdata"),
                searchTerms: ["custom", "apng"]
            ),
            MissCatReactionItem(
                rawValue: ":fixture_svg:",
                imageURL: Self.mediaFixtureURL(extension: "svg"),
                searchTerms: ["custom", "svg"]
            )
        ]
        func snapshot(for reactionAccount: MissCatReactionAccount) -> MissCatReactionSettingsSnapshot {
            .init(
                account: reactionAccount,
                favorites: favorites,
                available: favorites + custom,
                history: Array(favorites.prefix(4)),
                sections: [
                    .init(id: "favorites", title: "お気に入り", kind: .favorites, items: favorites),
                    .init(id: "history", title: "履歴", kind: .history, items: Array(favorites.prefix(4))),
                    .init(id: "custom-fixture", title: "Custom", kind: .custom, items: custom),
                    .init(id: "standard-fixture", title: "People", kind: .standard, items: favorites)
                ]
            )
        }
        reactionSnapshots = [
            first.id: snapshot(for: account),
            second.id: snapshot(for: secondAccount)
        ]
    }

    func loadAccounts() async throws -> MissCatAccountSnapshot {
        accountLoadCount += 1
        if accountMode == .failOnce, accountLoadCount == 1 {
            throw MissCatAccountManagementError.accountPersistenceFailed
        }
        return accountSnapshot
    }

    func switchAccount(id: String) async throws -> MissCatAccountSnapshot {
        guard accountSnapshot.accounts.contains(where: { $0.id == id }) else {
            throw MissCatAccountManagementError.accountNotFound
        }
        accountSnapshot.currentAccountID = id
        return accountSnapshot
    }

    func deleteAccount(id: String) async throws -> MissCatAccountDeletionResult {
        accountSnapshot.accounts.removeAll { $0.id == id }
        if accountSnapshot.currentAccountID == id {
            accountSnapshot.currentAccountID = accountSnapshot.accounts.first?.id
        }
        return .init(snapshot: accountSnapshot, removedConfiguredTabs: true)
    }

    func loadDesignSettings() async throws -> MissCatDesignSettingsSnapshot { designSnapshot }

    func saveDesignSettings(_ snapshot: MissCatDesignSettingsSnapshot) async throws -> MissCatDesignSaveResult {
        designSnapshot = snapshot
        return .init(snapshot: snapshot, requiresRootRelaunch: false)
    }

    func loadReactionAccounts() async throws -> [MissCatReactionAccount] {
        reactionSnapshots.values.map(\.account).sorted { $0.instance < $1.instance }
    }

    func loadReactions(accountID: String) async throws -> MissCatReactionSettingsSnapshot {
        guard let snapshot = reactionSnapshots[accountID] else {
            throw MissCatAccountManagementError.accountNotFound
        }
        return snapshot
    }

    func saveReactions(_ snapshot: MissCatReactionSettingsSnapshot) async throws {
        reactionSnapshots[snapshot.account.id] = snapshot
    }

    private static func mediaFixtureURL(extension fileExtension: String) -> URL {
        guard let url = Bundle.main.url(
            forResource: "reaction-fixture",
            withExtension: fileExtension
        ) else {
            preconditionFailure("Missing bundled reaction \(fileExtension) fixture")
        }
        return url
    }
}
