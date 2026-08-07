import Combine
import Foundation

@MainActor
private enum MissCatSettingsSaveRecovery {
    static var design: MissCatDesignSettingsSnapshot?
    static var reactions: [String: MissCatReactionSettingsSnapshot] = [:]
}

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
    @Published public private(set) var requiresAccountRecovery = false

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
        onConfiguredTabsChanged: @escaping () -> Void = {}
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
                // Empty-account recovery belongs to the live SwiftUI root. Never
                // synchronously rebuild/detach that root before it can present the
                // required add-account flow. A non-empty tab mutation still needs
                // the authenticated shell to rebuild its configured pager.
                if !requiresAccountRecovery, result.removedConfiguredTabs {
                    onConfiguredTabsChanged()
                }
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
        requiresAccountRecovery = snapshot.accounts.isEmpty
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
    @Published public var accentHexDraft = "2F7CF6"
    @Published public private(set) var accounts: [MissCatAccountSummary] = []
    @Published public var presentation: MissCatSettingsPresentation?

    private let repository: any MissCatDesignSettingsManaging
    private var loadTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var hasLoaded = false
    private var isDirty = false
    private var failedSave: MissCatDesignSettingsSnapshot?
    private var failedSaveCallback: (() -> Void)?
    private var failedSaveSuccessMessage = "デザイン設定を保存しました"

    public init(repository: any MissCatDesignSettingsManaging) {
        self.repository = repository
    }

    public var isReady: Bool { hasLoaded && !isLoading }

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
                tabs = Self.repairInvalidOwners(in: snapshot.tabs, accounts: snapshot.accounts)
                mode = snapshot.mode
                accentHex = Self.normalizedHex(snapshot.accentHex)
                accentHexDraft = accentHex
                accounts = snapshot.accounts
                hasLoaded = true
                isDirty = false
                if let recovery = MissCatSettingsSaveRecovery.design {
                    failedSave = recovery
                    presentation = .error(
                        title: "エラー",
                        message: "前回保存できなかったデザイン設定があります"
                    )
                }
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
        isDirty = true
    }

    public func removeTabs(at offsets: IndexSet) {
        tabs.remove(atOffsets: offsets)
        if tabs.isEmpty {
            tabs = Self.defaultTabs(accountID: accounts.first?.id)
            presentation = .banner(message: "既定のタブ構成に戻しました")
        }
        isDirty = true
    }

    public func moveTabs(from source: IndexSet, to destination: Int) {
        tabs.move(fromOffsets: source, toOffset: destination)
        isDirty = true
    }

    public func updateName(id: UUID, name: String) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        isDirty = true
    }

    public func updateOwner(tabID: UUID, accountID: String) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }),
              let account = accounts.first(where: { $0.id == accountID })
        else { return }
        tabs[index].accountID = accountID
        if tabs[index].kind == .home {
            tabs[index].name = "@\(account.username)"
        }
        isDirty = true
    }

    public func updateMode(_ value: MissCatThemeMode) {
        mode = value
        isDirty = true
    }

    public func setAccentHex(_ value: String) {
        let normalized = Self.normalizedHex(value)
        accentHex = normalized
        accentHexDraft = normalized
        isDirty = true
    }

    public func updateAccentHexDraft(_ value: String) {
        accentHexDraft = String(value.uppercased().filter { $0.isHexDigit }.prefix(6))
        isDirty = true
    }

    @discardableResult
    public func commitAccentHexDraft() -> Bool {
        guard let value = Self.validatedHex(accentHexDraft) else {
            presentation = .error(title: "エラー", message: "HEXは6桁の16進数で入力してください")
            return false
        }
        accentHex = value
        accentHexDraft = value
        return true
    }

    public func save(onRootRelaunchRequired: @escaping () -> Void = {}) {
        guard hasLoaded, !isSaving else { return }
        let successMessage: String
        if let value = Self.validatedHex(accentHexDraft) {
            accentHex = value
            accentHexDraft = value
            successMessage = "デザイン設定を保存しました"
        } else {
            // Navigating back must not discard valid tab or mode edits just because
            // the user left a partial HEX value in the text field. Keep the last
            // committed accent and visibly explain what was preserved.
            accentHexDraft = accentHex
            successMessage = "HEX入力が未完了のため、色は変更せず他の設定を保存しました"
        }
        let snapshot = MissCatDesignSettingsSnapshot(
            tabs: Self.repairInvalidOwners(in: tabs, accounts: accounts),
            mode: mode,
            accentHex: accentHex,
            accounts: accounts
        )
        persist(
            snapshot,
            successMessage: successMessage,
            onRootRelaunchRequired: onRootRelaunchRequired
        )
    }

    public func retrySave() {
        guard !isSaving, let snapshot = failedSave else { return }
        let callback = failedSaveCallback ?? {}
        presentation = nil
        persist(
            snapshot,
            successMessage: failedSaveSuccessMessage,
            onRootRelaunchRequired: callback
        )
    }

    private func persist(
        _ snapshot: MissCatDesignSettingsSnapshot,
        successMessage: String,
        onRootRelaunchRequired: @escaping () -> Void
    ) {
        failedSave = snapshot
        failedSaveCallback = onRootRelaunchRequired
        failedSaveSuccessMessage = successMessage
        saveTask = Task { @MainActor in
            isSaving = true
            defer { isSaving = false }
            do {
                try Task.checkCancellation()
                let result = try await repository.saveDesignSettings(snapshot)
                tabs = result.snapshot.tabs
                mode = result.snapshot.mode
                accentHex = Self.normalizedHex(result.snapshot.accentHex)
                accentHexDraft = accentHex
                isDirty = false
                failedSave = nil
                failedSaveCallback = nil
                failedSaveSuccessMessage = "デザイン設定を保存しました"
                MissCatSettingsSaveRecovery.design = nil
                presentation = .banner(message: successMessage)
                if result.requiresRootRelaunch { onRootRelaunchRequired() }
            } catch is CancellationError {
                return
            } catch {
                MissCatSettingsSaveRecovery.design = snapshot
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
        validatedHex(value) ?? "2F7CF6"
    }

    public static func validatedHex(_ value: String) -> String? {
        let filtered = value.uppercased().filter { $0.isHexDigit }
        guard filtered.count == 6 else { return nil }
        return filtered
    }

    public static func repairInvalidOwners(
        in tabs: [MissCatSettingsTab],
        accounts: [MissCatAccountSummary]
    ) -> [MissCatSettingsTab] {
        guard let fallback = accounts.first?.id else { return tabs }
        let valid = Set(accounts.map(\.id))
        return tabs.map { tab in
            var repaired = tab
            if tab.accountID.map({ !valid.contains($0) }) ?? true {
                repaired.accountID = fallback
            }
            return repaired
        }
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
    @Published public var searchQuery = ""
    @Published public var presentation: MissCatSettingsPresentation?

    private let repository: any MissCatReactionSettingsManaging
    private var accountsTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var isDirty = false
    private var failedSave: MissCatReactionSettingsSnapshot?

    public init(repository: any MissCatReactionSettingsManaging) {
        self.repository = repository
    }

    deinit {
        accountsTask?.cancel()
        loadTask?.cancel()
    }

    public var favorites: [MissCatReactionItem] {
        snapshot?.favorites ?? []
    }

    public var available: [MissCatReactionItem] {
        snapshot?.available ?? []
    }

    public var pickerSections: [MissCatReactionSection] {
        guard let snapshot else { return [] }
        let explicit = snapshot.sections
        let base = explicit.isEmpty
            ? [MissCatReactionSection(id: "available", title: "絵文字", kind: .standard, items: snapshot.available)]
            : explicit
        return base.compactMap { section in
            let items = section.items.filter { $0.matches(searchQuery) }
            guard !items.isEmpty else { return nil }
            return MissCatReactionSection(id: section.id, title: section.title, kind: section.kind, items: items)
        }
    }

    public func loadAccounts() {
        accountsTask?.cancel()
        accountsTask = Task { @MainActor [weak self] in
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
        loadTask?.cancel()
        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if let saveTask {
                await saveTask.value
            }
            guard !isDirty else {
                presentation = .error(title: "エラー", message: "保存できなかったお気に入りを再試行してください")
                return
            }
            isLoading = true
            defer { isLoading = false }
            do {
                let value = try await repository.loadReactions(accountID: accountID)
                try Task.checkCancellation()
                snapshot = value
                isDirty = false
                if let recovery = MissCatSettingsSaveRecovery.reactions[accountID] {
                    failedSave = recovery
                    presentation = .error(
                        title: "エラー",
                        message: "前回保存できなかったお気に入りがあります"
                    )
                }
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
        persist(value)
    }

    public func retrySave() {
        guard !isSaving, let value = failedSave else { return }
        presentation = nil
        snapshot = value
        isDirty = true
        persist(value)
    }

    private func persist(_ value: MissCatReactionSettingsSnapshot) {
        failedSave = value
        saveTask = Task { @MainActor in
            isSaving = true
            defer { isSaving = false }
            do {
                try Task.checkCancellation()
                try await repository.saveReactions(value)
                if snapshot == value { isDirty = false }
                failedSave = nil
                MissCatSettingsSaveRecovery.reactions[value.account.id] = nil
                presentation = .banner(message: "お気に入りを保存しました")
            } catch is CancellationError {
                return
            } catch {
                MissCatSettingsSaveRecovery.reactions[value.account.id] = value
                presentation = .error(title: "エラー", message: Self.message(for: error))
            }
        }
    }

    public func dismissPresentation() {
        presentation = nil
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "データ処理に失敗しました"
    }
}
