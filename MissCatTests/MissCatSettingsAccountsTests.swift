import XCTest
@testable import MissCat

@MainActor
final class MissCatAccountStoreTests: XCTestCase {
    func testLoadPreservesRepositoryOrderAndCurrentSelection() async {
        let first = account("first", username: "one")
        let second = account("second", username: "two")
        let repository = FakeAccountRepository(
            snapshot: .init(accounts: [first, second], currentAccountID: second.id)
        )
        let store = MissCatAccountStore(repository: repository)

        store.load()
        await eventually { store.phase == .loaded }

        XCTAssertEqual(store.accounts.map(\.id), ["first", "second"])
        XCTAssertEqual(store.currentAccountID, "second")
        XCTAssertEqual(repository.loadCount, 1)
    }

    func testNewLoadCancelsAndSupersedesPreviousLoad() async {
        let repository = FakeAccountRepository(
            snapshot: .init(accounts: [account("stale")], currentAccountID: "stale")
        )
        repository.loadDelayNanoseconds = 200_000_000
        let store = MissCatAccountStore(repository: repository)

        store.load()
        await Task.yield()
        repository.loadDelayNanoseconds = 0
        repository.snapshot = .init(accounts: [account("fresh")], currentAccountID: "fresh")
        store.load()
        await eventually { store.phase == .loaded && store.accounts.first?.id == "fresh" }

        XCTAssertEqual(store.accounts.map(\.id), ["fresh"])
        XCTAssertEqual(store.currentAccountID, "fresh")
    }

    func testSwitchUpdatesSnapshotExactlyOnceAndCallsRelaunch() async {
        let one = account("one")
        let two = account("two")
        let repository = FakeAccountRepository(
            snapshot: .init(accounts: [one, two], currentAccountID: one.id)
        )
        let store = MissCatAccountStore(repository: repository)
        store.load()
        await eventually { store.phase == .loaded }
        var relaunches = 0

        store.switchAccount(id: two.id) { relaunches += 1 }
        await eventually { store.currentAccountID == two.id }

        XCTAssertEqual(repository.switchedIDs, [two.id])
        XCTAssertEqual(relaunches, 1)
        XCTAssertEqual(store.presentation, .banner(message: "アカウントを切り替えました"))
    }

    func testSwitchIgnoresCurrentAndUnknownAccounts() async {
        let one = account("one")
        let repository = FakeAccountRepository(
            snapshot: .init(accounts: [one], currentAccountID: one.id)
        )
        let store = MissCatAccountStore(repository: repository)
        store.load()
        await eventually { store.phase == .loaded }

        store.switchAccount(id: one.id)
        store.switchAccount(id: "unknown")
        await Task.yield()

        XCTAssertTrue(repository.switchedIDs.isEmpty)
    }

    func testDeletionRequiresConfirmationBeforePersistence() async {
        let one = account("one")
        let repository = FakeAccountRepository(
            snapshot: .init(accounts: [one], currentAccountID: one.id)
        )
        let store = MissCatAccountStore(repository: repository)
        store.load()
        await eventually { store.phase == .loaded }

        store.requestDeletion(one)
        store.cancelDeletion()
        await Task.yield()

        XCTAssertTrue(repository.deletedIDs.isEmpty)
        XCTAssertEqual(store.accounts, [one])
    }

    func testDeletionPublishesTabAndLastAccountEffectsAfterSuccess() async {
        let one = account("one")
        let repository = FakeAccountRepository(
            snapshot: .init(accounts: [one], currentAccountID: one.id)
        )
        repository.deletionResult = .init(
            snapshot: .init(accounts: [], currentAccountID: nil),
            removedConfiguredTabs: true
        )
        let store = MissCatAccountStore(repository: repository)
        store.load()
        await eventually { store.phase == .loaded }
        var tabsChanged = 0
        var allDeleted = 0

        store.requestDeletion(one)
        store.confirmDeletion(
            onConfiguredTabsChanged: { tabsChanged += 1 },
            onAllAccountsDeleted: { allDeleted += 1 }
        )
        await eventually { store.accounts.isEmpty && repository.deletedIDs == [one.id] }

        XCTAssertEqual(tabsChanged, 1)
        XCTAssertEqual(allDeleted, 1)
        XCTAssertNil(store.currentAccountID)
        XCTAssertEqual(store.presentation, .banner(message: "アカウントを削除しました"))
    }

    func testDeletionFailureLeavesVisibleSnapshotUnchanged() async {
        let one = account("one")
        let repository = FakeAccountRepository(
            snapshot: .init(accounts: [one], currentAccountID: one.id)
        )
        repository.deleteError = MissCatAccountManagementError.accountPersistenceFailed
        let store = MissCatAccountStore(repository: repository)
        store.load()
        await eventually { store.phase == .loaded }

        store.requestDeletion(one)
        store.confirmDeletion()
        await eventually {
            if case .error = store.presentation { return true }
            return false
        }

        XCTAssertEqual(store.accounts, [one])
        XCTAssertEqual(store.currentAccountID, one.id)
    }
}

@MainActor
final class MissCatDesignSettingsStoreTests: XCTestCase {
    func testLoadAndEditPreserveLegacyThemeContract() async {
        let owner = account("owner", username: "wada")
        let original = MissCatDesignSettingsSnapshot(
            tabs: [
                .init(name: "Home", kind: .home, accountID: owner.id),
                .init(name: "Local", kind: .local, accountID: owner.id)
            ],
            mode: .light,
            accentHex: "2f7cf6",
            accounts: [owner]
        )
        let repository = FakeDesignRepository(snapshot: original)
        let store = MissCatDesignSettingsStore(repository: repository)

        store.load()
        await eventually { !store.isLoading && store.tabs.count == 2 }
        store.addTab(kind: .global, accountID: owner.id)
        store.updateName(id: store.tabs[2].id, name: "World")
        store.moveTabs(from: IndexSet(integer: 2), to: 0)

        XCTAssertEqual(store.accentHex, "2F7CF6")
        XCTAssertEqual(store.tabs.map(\.name), ["World", "Home", "Local"])
        XCTAssertEqual(store.tabs.map(\.kind), [.global, .home, .local])
    }

    func testRemovingEveryTabRestoresExactLegacyDefaults() async {
        let owner = account("owner")
        let repository = FakeDesignRepository(snapshot: .init(
            tabs: [.init(name: "Only", kind: .home, accountID: owner.id)],
            mode: .light,
            accentHex: "2F7CF6",
            accounts: [owner]
        ))
        let store = MissCatDesignSettingsStore(repository: repository)
        store.load()
        await eventually { store.tabs.count == 1 }

        store.removeTabs(at: IndexSet(integer: 0))

        XCTAssertEqual(store.tabs.map(\.name), ["Home", "Local", "Global"])
        XCTAssertEqual(store.tabs.map(\.kind), [.home, .local, .global])
        XCTAssertTrue(store.tabs.allSatisfy { $0.accountID == owner.id })
    }

    func testChangingHomeOwnerUpdatesDisplayName() async {
        let first = account("first", username: "one")
        let second = account("second", username: "two")
        let repository = FakeDesignRepository(snapshot: .init(
            tabs: [.init(name: "@one", kind: .home, accountID: first.id)],
            mode: .light,
            accentHex: "2F7CF6",
            accounts: [first, second]
        ))
        let store = MissCatDesignSettingsStore(repository: repository)
        store.load()
        await eventually { store.tabs.count == 1 }

        store.updateOwner(tabID: store.tabs[0].id, accountID: second.id)

        XCTAssertEqual(store.tabs[0].accountID, second.id)
        XCTAssertEqual(store.tabs[0].name, "@two")
    }

    func testSavePublishesRelaunchOnlyWhenRepositoryRequiresIt() async {
        let owner = account("owner")
        let snapshot = MissCatDesignSettingsSnapshot(
            tabs: [.init(name: "Home", kind: .home, accountID: owner.id)],
            mode: .light,
            accentHex: "2F7CF6",
            accounts: [owner]
        )
        let repository = FakeDesignRepository(snapshot: snapshot)
        repository.requiresRelaunch = true
        let store = MissCatDesignSettingsStore(repository: repository)
        store.load()
        await eventually { !store.isLoading && store.tabs.count == 1 }
        var relaunches = 0

        store.mode = .dark
        store.save { relaunches += 1 }
        await eventually { repository.savedSnapshots.count == 1 && !store.isSaving }

        XCTAssertEqual(repository.savedSnapshots.first?.mode, .dark)
        XCTAssertEqual(relaunches, 1)
    }

    func testInvalidHexFallsBackToLegacyAccent() {
        XCTAssertEqual(MissCatDesignSettingsStore.normalizedHex("#89d5e8"), "89D5E8")
        XCTAssertEqual(MissCatDesignSettingsStore.normalizedHex("invalid"), "2F7CF6")
        XCTAssertEqual(MissCatDesignSettingsStore.normalizedHex("123"), "2F7CF6")
    }
}

@MainActor
final class MissCatReactionSettingsStoreTests: XCTestCase {
    func testLoadAddDedupeEditDeleteAndSave() async {
        let account = MissCatReactionAccount(id: "owner", instance: "example.test")
        let thumbs = MissCatReactionItem(rawValue: "👍", displayValue: "👍")
        let heart = MissCatReactionItem(rawValue: "❤️", displayValue: "❤️")
        let repository = FakeReactionRepository(
            accounts: [account],
            snapshot: .init(account: account, favorites: [thumbs], available: [thumbs, heart])
        )
        let store = MissCatReactionSettingsStore(repository: repository)

        store.loadAccounts()
        await eventually { store.accounts == [account] }
        store.load(accountID: account.id)
        await eventually { store.favorites == [thumbs] }
        store.add(thumbs)
        XCTAssertEqual(store.favorites, [thumbs])
        store.add(heart)
        XCTAssertEqual(store.favorites, [thumbs, heart])

        store.remove(thumbs)
        XCTAssertEqual(store.favorites, [thumbs, heart], "delete must be edit-only")
        store.isEditing = true
        store.remove(thumbs)
        XCTAssertEqual(store.favorites, [heart])
        XCTAssertFalse(store.isEditing, "legacy UI exits delete mode after one deletion")

        store.saveIfNeeded()
        await eventually { repository.savedSnapshots.count == 1 && !store.isSaving }
        XCTAssertEqual(repository.savedSnapshots.first?.favorites, [heart])
    }

    func testMoveUsesStableReactionIdentity() async {
        let account = MissCatReactionAccount(id: "owner", instance: "example.test")
        let first = MissCatReactionItem(rawValue: "1", displayValue: "1")
        let second = MissCatReactionItem(rawValue: "2", displayValue: "2")
        let third = MissCatReactionItem(rawValue: "3", displayValue: "3")
        let repository = FakeReactionRepository(
            accounts: [account],
            snapshot: .init(account: account, favorites: [first, second, third], available: [])
        )
        let store = MissCatReactionSettingsStore(repository: repository)
        store.load(accountID: account.id)
        await eventually { store.favorites.count == 3 }

        store.move(from: IndexSet(integer: 0), to: 3)

        XCTAssertEqual(store.favorites.map(\.rawValue), ["2", "3", "1"])
    }

    func testLegacyPresetContractIsExact() {
        XCTAssertEqual(
            MissCatReactionSettingsStore.legacyDefaults,
            ["👍", "❤️", "😆", "🤔", "😮", "🎉", "💢", "😥", "😇", "🍮", "🤯"]
        )
    }
}

final class MissCatSettingsVisualContractTests: XCTestCase {
    func testRecoveredLegacyGeometry() {
        XCTAssertEqual(MissCatSettingsLegacyMetrics.settingsHeaderHeight, 60)
        XCTAssertEqual(MissCatSettingsLegacyMetrics.settingsRowHeight, 43.5)
        XCTAssertEqual(MissCatSettingsLegacyMetrics.accountToolbarHeight, 50)
        XCTAssertEqual(MissCatSettingsLegacyMetrics.accountCardHeight, 120)
        XCTAssertEqual(MissCatSettingsLegacyMetrics.accountHorizontalInset, 10)
        XCTAssertEqual(MissCatSettingsLegacyMetrics.accountCornerRadius, 8)
        XCTAssertEqual(MissCatSettingsLegacyMetrics.reactionGridColumns, 8)
        XCTAssertEqual(MissCatSettingsLegacyMetrics.emptyImageSize, 170)
        XCTAssertEqual(MissCatSettingsLegacyMetrics.aboutLogoHeight, 112)
        XCTAssertEqual(MissCatSettingsLegacyMetrics.aboutDeveloperRowHeight, 70)
    }

    func testLicenseCatalogRetainsAllLegacyEntries() {
        let catalog = LicenseTableViewController.getOssDescription()
        let expected = [
            "APNGKit", "Agrume", "Cache", "ChromaColorPicker", "Eureka",
            "FloatingPanel", "Gifu", "MessageKit", "MisskeyKit", "PolioPager",
            "RxCocoa", "RxDataSources", "RxSwift", "SkeletonView", "Starscream",
            "SwiftLinkPreview", "XLPagerTabStrip", "XLActionController", "YanagiText",
            "photo-editor"
        ]

        XCTAssertEqual(catalog.keys.sorted(), expected.sorted())
        XCTAssertEqual(catalog.count, 20)
        XCTAssertTrue(catalog.values.allSatisfy { $0.count > 200 })
        XCTAssertTrue(catalog.values.joined(separator: "\n").contains("License"))
    }

    func testSettingsRoutesCoverAllLegacyDestinations() {
        let routes: [MissCatSettingsRoute] = [
            .design,
            .reactionInstances,
            .reactions(accountID: "fixture"),
            .licenses,
            .license(name: "MisskeyKit"),
            .about
        ]
        XCTAssertEqual(Set(routes).count, 6)
    }
}

@MainActor
private final class FakeAccountRepository: MissCatAccountManaging {
    var snapshot: MissCatAccountSnapshot
    var deletionResult: MissCatAccountDeletionResult?
    var loadDelayNanoseconds: UInt64 = 0
    var deleteError: Error?
    private(set) var loadCount = 0
    private(set) var switchedIDs: [String] = []
    private(set) var deletedIDs: [String] = []

    init(snapshot: MissCatAccountSnapshot) {
        self.snapshot = snapshot
    }

    func loadAccounts() async throws -> MissCatAccountSnapshot {
        loadCount += 1
        if loadDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: loadDelayNanoseconds)
        }
        return snapshot
    }

    func switchAccount(id: String) async throws -> MissCatAccountSnapshot {
        switchedIDs.append(id)
        snapshot.currentAccountID = id
        return snapshot
    }

    func deleteAccount(id: String) async throws -> MissCatAccountDeletionResult {
        deletedIDs.append(id)
        if let deleteError { throw deleteError }
        if let deletionResult {
            snapshot = deletionResult.snapshot
            return deletionResult
        }
        snapshot.accounts.removeAll { $0.id == id }
        if snapshot.currentAccountID == id { snapshot.currentAccountID = snapshot.accounts.first?.id }
        return .init(snapshot: snapshot, removedConfiguredTabs: false)
    }
}

@MainActor
private final class FakeDesignRepository: MissCatDesignSettingsManaging {
    var snapshot: MissCatDesignSettingsSnapshot
    var requiresRelaunch = false
    private(set) var savedSnapshots: [MissCatDesignSettingsSnapshot] = []

    init(snapshot: MissCatDesignSettingsSnapshot) {
        self.snapshot = snapshot
    }

    func loadDesignSettings() async throws -> MissCatDesignSettingsSnapshot {
        snapshot
    }

    func saveDesignSettings(
        _ snapshot: MissCatDesignSettingsSnapshot
    ) async throws -> MissCatDesignSaveResult {
        savedSnapshots.append(snapshot)
        self.snapshot = snapshot
        return .init(snapshot: snapshot, requiresRootRelaunch: requiresRelaunch)
    }
}

@MainActor
private final class FakeReactionRepository: MissCatReactionSettingsManaging {
    var accounts: [MissCatReactionAccount]
    var snapshot: MissCatReactionSettingsSnapshot
    private(set) var savedSnapshots: [MissCatReactionSettingsSnapshot] = []

    init(accounts: [MissCatReactionAccount], snapshot: MissCatReactionSettingsSnapshot) {
        self.accounts = accounts
        self.snapshot = snapshot
    }

    func loadReactionAccounts() async throws -> [MissCatReactionAccount] {
        accounts
    }

    func loadReactions(accountID: String) async throws -> MissCatReactionSettingsSnapshot {
        snapshot
    }

    func saveReactions(_ snapshot: MissCatReactionSettingsSnapshot) async throws {
        savedSnapshots.append(snapshot)
        self.snapshot = snapshot
    }
}

private func account(
    _ id: String,
    username: String = "user",
    instance: String = "example.test"
) -> MissCatAccountSummary {
    MissCatAccountSummary(
        id: id,
        username: username,
        displayName: username,
        instance: instance
    )
}

@MainActor
private func eventually(
    timeout: TimeInterval = 2,
    condition: @escaping @MainActor () -> Bool
) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition(), Date() < deadline {
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
    XCTAssertTrue(condition(), "condition was not satisfied before timeout")
}
