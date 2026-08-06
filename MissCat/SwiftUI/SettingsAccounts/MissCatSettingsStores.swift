import Combine
import Foundation

@MainActor
public final class MissCatAccountStore: ObservableObject {
    public enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published public private(set) var phase: Phase = .idle
    @Published public private(set) var accounts: [MissCatAccountSummary] = []
    @Published public private(set) var currentAccountID: String?
    @Published public var isEditing = false
    @Published public var accountPendingDeletion: MissCatAccountSummary?
    @Published public private(set) var busyAccountID: String?
    @Published public var presentation: MissCatSettingsPresentation?

    private let repository: any MissCatAccountManaging
    private var operation: Task<Void, Never>?

    public init(repository: any MissCatAccountManaging) {
        self.repository = repository
    }

    deinit {
        operation?.cancel()
    }

    public func load() {
        replaceOperation { [weak self] in
            guard let self else { return }
            phase = .loading
            do {
                let snapshot = try await repository.loadAccounts()
                try Task.checkCancellation()
                apply(snapshot)
                phase = .loaded
            } catch is CancellationError {
                return
            } catch {
                phase = .failed(Self.message(for: error))
            }
        }
    }

    public func retry() {
        load()
    }

    public func requestDeletion(_ account: MissCatAccountSummary) {
        guard busyAccountID == nil else { return }
        accountPendingDeletion = account
    }

    public func cancelDeletion() {
        accountPendingDeletion = nil
    }

    public func confirmDeletion(
        onConfiguredTabsChanged: @escaping () -> Void = {},
        onAllAccountsDeleted: @escaping () -> Void = {}
    ) {
        guard let account = accountPendingDeletion else { return }
        accountPendingDeletion = nil
        replaceOperation { [weak self] in
            guard let self else { return }
            busyAccountID = account.id
            defer { busyAccountID = nil }
            do {
                try Task.checkCancellation()
                let result = try await repository.deleteAccount(id: account.id)
                // Persistence is an atomic boundary from the store's perspective. Once it
                // succeeds, always reflect it even if the surrounding screen is dismissed.
                apply(result.snapshot)
                phase = .loaded
                presentation = .banner(message: "アカウントを削除しました")
                if result.removedConfiguredTabs { onConfiguredTabsChanged() }
                if result.snapshot.accounts.isEmpty { onAllAccountsDeleted() }
            } catch is CancellationError {
                return
            } catch {
                presentation = .error(title: "エラー", message: Self.message(for: error))
            }
        }
    }

    public func switchAccount(
        id: String,
        onSwitched: @escaping () -> Void = {}
    ) {
        guard id != currentAccountID, accounts.contains(where: { $0.id == id }) else { return }
        replaceOperation { [weak self] in
            guard let self else { return }
            busyAccountID = id
            defer { busyAccountID = nil }
            do {
                try Task.checkCancellation()
                let snapshot = try await repository.switchAccount(id: id)
                apply(snapshot)
                phase = .loaded
                presentation = .banner(message: "アカウントを切り替えました")
                onSwitched()
            } catch is CancellationError {
                return
            } catch {
                presentation = .error(title: "エラー", message: Self.message(for: error))
            }
        }
    }

    public func dismissPresentation() {
        presentation = nil
    }

    private func apply(_ snapshot: MissCatAccountSnapshot) {
        accounts = snapshot.accounts
        currentAccountID = snapshot.currentAccountID
    }

    private func replaceOperation(_ body: @escaping @MainActor () async -> Void) {
        operation?.cancel()
        operation = Task { @MainActor in await body() }
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "データ処理に失敗しました"
    }
}

@MainActor
public final class MissCatDesignSettingsStore: ObservableObject {
    @Published public private(set) var isLoading = false
    @Published public private(set) var isSaving = false
    @Published public var tabs: [MissCatSettingsTab] = []
    @Published public var mode: MissCatThemeMode = .light
    @Published public var accentHex = "2F7CF6"
    @Published public private(set) var accounts: [MissCatAccountSummary] = []
    @Published public var presentation: MissCatSettingsPresentation?

    private let repository: any MissCatDesignSettingsManaging
    private var loadTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var hasLoaded = false

    public init(repository: any MissCatDesignSettingsManaging) {
        self.repository = repository
    }

    deinit {
        loadTask?.cancel()
        saveTask?.cancel()
    }

    public func load() {
        guard !hasLoaded else { return }
        loadTask?.cancel()
        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            isLoading = true
            defer { isLoading = false }
            do {
                let snapshot = try await repository.loadDesignSettings()
                try Task.checkCancellation()
                tabs = snapshot.tabs
                mode = snapshot.mode
                accentHex = Self.normalizedHex(snapshot.accentHex)
                accounts = snapshot.accounts
                hasLoaded = true
            } catch is CancellationError {
                return
            } catch {
                presentation = .error(title: "エラー", message: Self.message(for: error))
            }
        }
    }

    public func addTab(kind: MissCatSettingsTabKind, accountID: String?) {
        let owner = accounts.first(where: { $0.id == accountID })
        let name = kind == .home ? "@\(owner?.username ?? "")" : kind.defaultName
        tabs.append(MissCatSettingsTab(name: name, kind: kind, accountID: owner?.id))
    }

    public func removeTabs(at offsets: IndexSet) {
        tabs.remove(atOffsets: offsets)
        if tabs.isEmpty {
            tabs = Self.defaultTabs(accountID: accounts.first?.id)
            presentation = .banner(message: "既定のタブ構成に戻しました")
        }
    }

    public func moveTabs(from source: IndexSet, to destination: Int) {
        tabs.move(fromOffsets: source, toOffset: destination)
    }

    public func updateName(id: UUID, name: String) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func updateOwner(tabID: UUID, accountID: String) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }),
              let account = accounts.first(where: { $0.id == accountID })
        else { return }
        tabs[index].accountID = accountID
        if tabs[index].kind == .home {
            tabs[index].name = "@\(account.username)"
        }
    }

    public func setAccentHex(_ value: String) {
        accentHex = Self.normalizedHex(value)
    }

    public func save(onRootRelaunchRequired: @escaping () -> Void = {}) {
        guard hasLoaded, !isSaving else { return }
        saveTask?.cancel()
        let snapshot = MissCatDesignSettingsSnapshot(
            tabs: tabs,
            mode: mode,
            accentHex: Self.normalizedHex(accentHex),
            accounts: accounts
        )
        saveTask = Task { @MainActor [weak self] in
            guard let self else { return }
            isSaving = true
            defer { isSaving = false }
            do {
                try Task.checkCancellation()
                let result = try await repository.saveDesignSettings(snapshot)
                tabs = result.snapshot.tabs
                mode = result.snapshot.mode
                accentHex = Self.normalizedHex(result.snapshot.accentHex)
                presentation = .banner(message: "デザイン設定を保存しました")
                if result.requiresRootRelaunch { onRootRelaunchRequired() }
            } catch is CancellationError {
                return
            } catch {
                presentation = .error(title: "エラー", message: Self.message(for: error))
            }
        }
    }

    public func dismissPresentation() {
        presentation = nil
    }

    public static func defaultTabs(accountID: String?) -> [MissCatSettingsTab] {
        [
            MissCatSettingsTab(name: "Home", kind: .home, accountID: accountID),
            MissCatSettingsTab(name: "Local", kind: .local, accountID: accountID),
            MissCatSettingsTab(name: "Global", kind: .global, accountID: accountID)
        ]
    }

    public static func normalizedHex(_ value: String) -> String {
        let filtered = value.uppercased().filter { $0.isHexDigit }
        guard filtered.count == 6 else { return "2F7CF6" }
        return filtered
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "データ処理に失敗しました"
    }
}

@MainActor
public final class MissCatReactionSettingsStore: ObservableObject {
    public static let legacyDefaults = ["👍", "❤️", "😆", "🤔", "😮", "🎉", "💢", "😥", "😇", "🍮", "🤯"]

    @Published public private(set) var accounts: [MissCatReactionAccount] = []
    @Published public private(set) var snapshot: MissCatReactionSettingsSnapshot?
    @Published public private(set) var isLoading = false
    @Published public private(set) var isSaving = false
    @Published public var isEditing = false
    @Published public var showsPicker = false
    @Published public var presentation: MissCatSettingsPresentation?

    private let repository: any MissCatReactionSettingsManaging
    private var operation: Task<Void, Never>?
    private var isDirty = false

    public init(repository: any MissCatReactionSettingsManaging) {
        self.repository = repository
    }

    deinit {
        operation?.cancel()
    }

    public var favorites: [MissCatReactionItem] {
        snapshot?.favorites ?? []
    }

    public var available: [MissCatReactionItem] {
        snapshot?.available ?? []
    }

    public func loadAccounts() {
        replaceOperation { [weak self] in
            guard let self else { return }
            isLoading = true
            defer { isLoading = false }
            do {
                let values = try await repository.loadReactionAccounts()
                try Task.checkCancellation()
                accounts = values
            } catch is CancellationError {
                return
            } catch {
                presentation = .error(title: "エラー", message: Self.message(for: error))
            }
        }
    }

    public func load(accountID: String) {
        replaceOperation { [weak self] in
            guard let self else { return }
            isLoading = true
            defer { isLoading = false }
            do {
                let value = try await repository.loadReactions(accountID: accountID)
                try Task.checkCancellation()
                snapshot = value
                isDirty = false
            } catch is CancellationError {
                return
            } catch {
                presentation = .error(title: "エラー", message: Self.message(for: error))
            }
        }
    }

    public func add(_ item: MissCatReactionItem) {
        guard var value = snapshot, !value.favorites.contains(item) else { return }
        value.favorites.append(item)
        snapshot = value
        isDirty = true
        showsPicker = false
    }

    public func remove(_ item: MissCatReactionItem) {
        guard isEditing, var value = snapshot else { return }
        value.favorites.removeAll { $0.id == item.id }
        snapshot = value
        isEditing = false
        isDirty = true
    }

    public func move(from source: IndexSet, to destination: Int) {
        guard var value = snapshot else { return }
        value.favorites.move(fromOffsets: source, toOffset: destination)
        snapshot = value
        isDirty = true
    }

    public func saveIfNeeded() {
        guard isDirty, let value = snapshot, !isSaving else { return }
        replaceOperation { [weak self] in
            guard let self else { return }
            isSaving = true
            defer { isSaving = false }
            do {
                try Task.checkCancellation()
                try await repository.saveReactions(value)
                isDirty = false
                presentation = .banner(message: "お気に入りを保存しました")
            } catch is CancellationError {
                return
            } catch {
                presentation = .error(title: "エラー", message: Self.message(for: error))
            }
        }
    }

    public func dismissPresentation() {
        presentation = nil
    }

    private func replaceOperation(_ body: @escaping @MainActor () async -> Void) {
        operation?.cancel()
        operation = Task { @MainActor in await body() }
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "データ処理に失敗しました"
    }
}
