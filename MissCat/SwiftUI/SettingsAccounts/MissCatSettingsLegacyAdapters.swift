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

    init(
        cache: Cache.UserDefaults = .shared,
        session: URLSession = .shared
    ) {
        self.cache = cache
        self.session = session
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
        guard cache.getUser(userId: id) != nil else {
            throw MissCatAccountManagementError.accountNotFound
        }

        cache.changeCurrentUser(userId: id)
        guard cache.getCurrentUserId() == id,
              cache.getUser(userId: id) != nil
        else {
            throw MissCatAccountManagementError.currentAccountVerificationFailed
        }

        Cache.shared.resetMyCache()
        Theme.shared.reset()
        Theme.shared.set()
        return try await loadAccounts()
    }

    func deleteAccount(id: String) async throws -> MissCatAccountDeletionResult {
        try Task.checkCancellation()
        guard let user = cache.getUser(userId: id) else {
            throw MissCatAccountManagementError.accountNotFound
        }

        // Cache.UserDefaults owns the credential/metadata transaction. Do not update
        // tabs or UI state until it confirms that the Keychain entry was removed.
        guard cache.removeUser(userId: id) else {
            throw MissCatAccountManagementError.accountPersistenceFailed
        }
        let tabsChanged = Theme.shared.removeUserTabs(for: user)
        Cache.shared.resetMyCache()
        let snapshot = try await loadAccounts()
        return MissCatAccountDeletionResult(
            snapshot: snapshot,
            removedConfiguredTabs: tabsChanged
        )
    }

    func loadDesignSettings() async throws -> MissCatDesignSettingsSnapshot {
        if Theme.shared.currentModel == nil { Theme.shared.set() }
        let accounts = try await loadAccounts().accounts
        guard let model = Theme.shared.currentModel ?? Theme.Model.getDefault() else {
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
        let old = Theme.shared.currentModel
        let availableIDs = Set(snapshot.accounts.map(\.id))
        let tabs = snapshot.tabs.map { tab in
            Theme.Tab(
                name: tab.name.isEmpty ? tab.kind.defaultName : tab.name,
                kind: legacyKind(from: tab.kind),
                userId: tab.accountID.flatMap { availableIDs.contains($0) ? $0 : nil },
                listId: tab.listID
            )
        }
        let newModel = Theme.Model(
            tab: tabs,
            mainColorHex: MissCatDesignSettingsStore.normalizedHex(snapshot.accentHex),
            colorMode: snapshot.mode == .light ? .light : .dark
        )
        let requiresRootRelaunch = old.map { Theme.needAllRelaunch(between: $0, and: newModel) } ?? false
        Theme.shared.save(with: newModel)

        guard let persisted = Theme.Model.get(),
              persisted.mainColorHex == newModel.mainColorHex,
              persisted.colorMode == newModel.colorMode,
              persisted.tab.count == newModel.tab.count
        else {
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
            return MissCatReactionAccount(id: user.userId, instance: user.instance)
        }
    }

    func loadReactions(accountID: String) async throws -> MissCatReactionSettingsSnapshot {
        try Task.checkCancellation()
        guard let owner = cache.getUser(userId: accountID) else {
            throw MissCatAccountManagementError.accountNotFound
        }

        let saved = EmojiView.EmojiModel.getEmojis(type: .favs, owner: owner) ?? []
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
        let handlerChoices = availableEmojiModels(for: owner).map(reactionItem(from:))
        let available = unique(defaultChoices + handlerChoices)

        return MissCatReactionSettingsSnapshot(
            account: MissCatReactionAccount(id: owner.userId, instance: owner.instance),
            favorites: favoriteModels.map(reactionItem(from:)),
            available: available
        )
    }

    func saveReactions(_ snapshot: MissCatReactionSettingsSnapshot) async throws {
        try Task.checkCancellation()
        guard let owner = cache.getUser(userId: snapshot.account.id),
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
        EmojiView.EmojiModel.saveEmojis(with: models, type: .favs, owner: owner)
        EmojiRepository.shared.updateUserEmojis(to: .favs, owner: owner, new: models)

        let persisted = EmojiView.EmojiModel.getEmojis(type: .favs, owner: owner) ?? []
        guard persisted.map(\.rawEmoji) == models.map(\.rawEmoji) else {
            throw MissCatAccountManagementError.accountPersistenceFailed
        }
    }

    private func summary(for user: SecureUser) async -> MissCatAccountSummary {
        let cached = Cache.shared.getUserInfo(user: user)
        let fallback = MissCatAccountSummary(
            id: user.userId,
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
                id: user.userId,
                username: profile.username ?? user.username,
                displayName: profile.name ?? cached?.name,
                instance: user.instance,
                avatarURL: profile.avatarUrl.flatMap(URL.init(string:))
            )
        } catch {
            return fallback
        }
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

    private func availableEmojiModels(for owner: SecureUser) -> [EmojiView.EmojiModel] {
        guard let handler = EmojiHandler.getHandler(owner: owner) else { return [] }
        return handler.categorizedDefaultEmojis.keys.sorted().flatMap { handler.categorizedDefaultEmojis[$0] ?? [] }
            + handler.categorizedCustomEmojis.keys.sorted().flatMap { handler.categorizedCustomEmojis[$0] ?? [] }
    }

    private func reactionItem(from model: EmojiView.EmojiModel) -> MissCatReactionItem {
        MissCatReactionItem(
            rawValue: model.rawEmoji,
            displayValue: model.defaultEmoji,
            imageURL: model.customEmojiUrl.flatMap(URL.init(string:))
        )
    }

    private func unique(_ items: [MissCatReactionItem]) -> [MissCatReactionItem] {
        var seen: Set<String> = []
        return items.filter { seen.insert($0.id).inserted }
    }
}

