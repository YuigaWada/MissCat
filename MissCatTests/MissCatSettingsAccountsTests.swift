import XCTest
@testable import MissCat

@MainActor
final class MissCatAccountStoreTests: XCTestCase {
    func testProfileRoutingSeparatesStorageIdentityFromServerUserID() {
        let first = SecureUser(
            userId: "same-user",
            username: "first",
            instance: "first.example",
            apiKey: nil
        )
        let second = SecureUser(
            userId: "same-user",
            username: "second",
            instance: "second.example",
            apiKey: nil
        )
        let summary = MissCatAccountSummary(
            id: second.accountIdentifier,
            userID: second.userId,
            username: second.username,
            instance: second.instance
        )

        XCTAssertNotEqual(first.accountIdentifier, second.accountIdentifier)
        XCTAssertNil(MissCatSettingsBridge.profileUserID(for: summary, owner: first))
        XCTAssertEqual(
            MissCatSettingsBridge.profileUserID(for: summary, owner: second),
            "same-user"
        )
    }

    func testProductionSwitchPropagatesFailedCompositeSelectionWrite() async throws {
        let defaults = SettingsIntegrationDefaultsStore()
        let keyStore = SettingsIntegrationAPIKeyStore()
        let cache = Cache.UserDefaults(defaultsStore: defaults, apiKeyStore: keyStore)
        let first = SecureUser(
            userId: "same-user",
            username: "first",
            instance: "first.example",
            apiKey: "first-test-key"
        )
        let second = SecureUser(
            userId: "same-user",
            username: "second",
            instance: "second.example",
            apiKey: "second-test-key"
        )
        XCTAssertTrue(cache.saveUser(first))
        XCTAssertTrue(cache.saveUser(second))
        _ = cache.getUsers()
        XCTAssertEqual(cache.getCurrentUserId(), first.accountIdentifier)
        defaults.blockedSetKeys.insert("current-user-id")
        let repository = MissCatLegacySettingsRepository(cache: cache)

        do {
            _ = try await repository.switchAccount(id: second.accountIdentifier)
            XCTFail("The repository accepted a failed selection write")
        } catch {
            XCTAssertEqual(
                error as? MissCatAccountManagementError,
                .currentAccountVerificationFailed
            )
        }

        XCTAssertEqual(cache.getCurrentUserId(), first.accountIdentifier)
    }

    func testProductionProfileResponseUsesServerUserIDWhileSummaryKeepsCompositeID() async throws {
        let defaults = SettingsIntegrationDefaultsStore()
        let keyStore = SettingsIntegrationAPIKeyStore()
        let cache = Cache.UserDefaults(defaultsStore: defaults, apiKeyStore: keyStore)
        let user = SecureUser(
            userId: "server-user-id",
            username: "cached-name",
            instance: "profile.example",
            apiKey: "profile-test-key"
        )
        XCTAssertTrue(cache.saveUser(user))

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SettingsURLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        SettingsURLProtocolStub.handler = { request in
            XCTAssertEqual(request.url?.host, "profile.example")
            XCTAssertEqual(request.url?.path, "/api/i")
            return (200, Data("""
            {"id":"server-user-id","username":"verified-name","name":"Verified","avatarUrl":null}
            """.utf8))
        }
        defer { SettingsURLProtocolStub.handler = nil }
        let repository = MissCatLegacySettingsRepository(cache: cache, session: session)

        let snapshot = try await repository.loadAccounts()
        let summary = try XCTUnwrap(snapshot.accounts.first)

        XCTAssertEqual(summary.id, user.accountIdentifier)
        XCTAssertEqual(summary.userID, user.userId)
        XCTAssertEqual(summary.username, "verified-name")
        XCTAssertEqual(snapshot.currentAccountID, user.accountIdentifier)
    }

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

    func testHexDraftAllowsPartialTypingAndValidatesOnlyOnCommit() async {
        let owner = account("owner")
        let repository = FakeDesignRepository(snapshot: .init(
            tabs: [.init(name: "Home", kind: .home, accountID: owner.id)],
            mode: .light,
            accentHex: "2F7CF6",
            accounts: [owner]
        ))
        let store = MissCatDesignSettingsStore(repository: repository)
        store.load()
        await eventually { store.isReady }

        store.updateAccentHexDraft("#12a")

        XCTAssertEqual(store.accentHexDraft, "12A")
        XCTAssertEqual(store.accentHex, "2F7CF6")
        XCTAssertFalse(store.commitAccentHexDraft())

        store.updateAccentHexDraft("12abef")
        XCTAssertTrue(store.commitAccentHexDraft())
        XCTAssertEqual(store.accentHex, "12ABEF")
    }

    func testNavigatingBackWithPartialHexSavesOtherEditsUsingLastValidAccent() async {
        let owner = account("owner")
        let repository = FakeDesignRepository(snapshot: .init(
            tabs: [.init(name: "Home", kind: .home, accountID: owner.id)],
            mode: .light,
            accentHex: "2F7CF6",
            accounts: [owner]
        ))
        let store = MissCatDesignSettingsStore(repository: repository)
        store.load()
        await eventually { store.isReady }

        store.updateMode(.dark)
        store.addTab(kind: .global, accountID: owner.id)
        store.updateAccentHexDraft("12A")
        store.save()
        await eventually { repository.savedSnapshots.count == 1 && !store.isSaving }

        XCTAssertEqual(repository.savedSnapshots[0].mode, .dark)
        XCTAssertEqual(repository.savedSnapshots[0].tabs.map(\.kind), [.home, .global])
        XCTAssertEqual(repository.savedSnapshots[0].accentHex, "2F7CF6")
        XCTAssertEqual(store.accentHexDraft, "2F7CF6")
        XCTAssertEqual(
            store.presentation,
            .banner(message: "HEX入力が未完了のため、色は変更せず他の設定を保存しました")
        )
    }

    func testLoadRepairsInvalidOwnersWithoutChangingOrderedTabIdentityFields() async {
        let owner = account("valid")
        let tabs: [MissCatSettingsTab] = [
            .init(name: "World", kind: .global, accountID: "deleted"),
            .init(name: "Friends", kind: .list, accountID: nil, listID: "list-42"),
            .init(name: "Person", kind: .user, accountID: owner.id)
        ]
        let store = MissCatDesignSettingsStore(repository: FakeDesignRepository(snapshot: .init(
            tabs: tabs,
            mode: .dark,
            accentHex: "ABCDEF",
            accounts: [owner]
        )))

        store.load()
        await eventually { store.isReady }

        XCTAssertEqual(store.tabs.map(\.name), ["World", "Friends", "Person"])
        XCTAssertEqual(store.tabs.map(\.kind), [.global, .list, .user])
        XCTAssertEqual(store.tabs.map(\.accountID), [owner.id, owner.id, owner.id])
        XCTAssertEqual(store.tabs.map(\.listID), [nil, "list-42", nil])
    }

    func testFailedDesignSaveRemainsRetryable() async {
        let owner = account("owner")
        let snapshot = MissCatDesignSettingsSnapshot(
            tabs: [.init(name: "Home", kind: .home, accountID: owner.id)],
            mode: .light,
            accentHex: "2F7CF6",
            accounts: [owner]
        )
        let repository = FakeDesignRepository(snapshot: snapshot)
        repository.saveError = MissCatAccountManagementError.accountPersistenceFailed
        let store = MissCatDesignSettingsStore(repository: repository)
        store.load()
        await eventually { store.isReady }
        store.updateMode(.dark)

        store.save()
        await eventually { if case .error = store.presentation { return true }; return false }
        repository.saveError = nil
        store.retrySave()
        await eventually { repository.savedSnapshots.count == 1 && !store.isSaving }

        XCTAssertEqual(repository.savedSnapshots.first?.mode, .dark)
    }

    func testDesignSaveFinishesAfterOwningScreenCloses() async {
        let owner = account("owner")
        let repository = FakeDesignRepository(snapshot: .init(
            tabs: [.init(name: "Home", kind: .home, accountID: owner.id)],
            mode: .light,
            accentHex: "2F7CF6",
            accounts: [owner]
        ))
        repository.saveDelayNanoseconds = 100_000_000
        var store: MissCatDesignSettingsStore? = .init(repository: repository)
        store?.load()
        await eventually { store?.isReady == true }
        store?.updateMode(.dark)

        store?.save()
        store = nil
        await eventually { repository.savedSnapshots.count == 1 }

        XCTAssertEqual(repository.savedSnapshots.first?.mode, .dark)
    }

    func testDesignFailureSurvivesRootCloseAndCanRetryAfterReopen() async {
        let owner = account("owner")
        let repository = FakeDesignRepository(snapshot: .init(
            tabs: [.init(name: "Home", kind: .home, accountID: owner.id)],
            mode: .light,
            accentHex: "2F7CF6",
            accounts: [owner]
        ))
        repository.saveError = MissCatAccountManagementError.accountPersistenceFailed
        var original: MissCatDesignSettingsStore? = .init(repository: repository)
        original?.load()
        await eventually { original?.isReady == true }
        original?.updateMode(.dark)
        original?.save()
        await eventually { if case .error = original?.presentation { return true }; return false }
        original = nil

        repository.saveError = nil
        let reopened = MissCatDesignSettingsStore(repository: repository)
        reopened.load()
        await eventually { if case .error = reopened.presentation { return true }; return false }
        reopened.retrySave()
        await eventually { repository.savedSnapshots.count == 1 && !reopened.isSaving }

        XCTAssertEqual(repository.savedSnapshots.first?.mode, .dark)
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

    func testPickerSearchCoversFavoritesHistoryCustomAndStandardSections() async {
        let account = MissCatReactionAccount(id: "owner", instance: "example.test")
        let favorite = MissCatReactionItem(rawValue: "👍", displayValue: "👍")
        let custom = MissCatReactionItem(
            rawValue: ":misscat:",
            imageURL: URL(string: "https://example.test/misscat.gif"),
            searchTerms: ["animals", "cat"]
        )
        let standard = MissCatReactionItem(rawValue: "smile", displayValue: "😄", searchTerms: ["people"])
        let snapshot = MissCatReactionSettingsSnapshot(
            account: account,
            favorites: [favorite],
            available: [favorite, custom, standard],
            history: Array(repeating: favorite, count: 20),
            sections: [
                .init(id: "favorites", title: "お気に入り", kind: .favorites, items: [favorite]),
                .init(id: "history", title: "履歴", kind: .history, items: [favorite]),
                .init(id: "custom-animals", title: "Animals", kind: .custom, items: [custom]),
                .init(id: "standard-people", title: "People", kind: .standard, items: [standard])
            ]
        )
        XCTAssertEqual(snapshot.history.count, 14)
        let store = MissCatReactionSettingsStore(repository: FakeReactionRepository(
            accounts: [account], snapshot: snapshot
        ))
        store.load(accountID: account.id)
        await eventually { store.snapshot != nil }

        XCTAssertEqual(store.pickerSections.map(\.kind), [.favorites, .history, .custom, .standard])
        store.searchQuery = "cat"
        XCTAssertEqual(store.pickerSections.map(\.kind), [.custom])
        XCTAssertEqual(store.pickerSections.first?.items, [custom])
    }

    func testAccountReloadDoesNotCancelReactionSave() async {
        let account = MissCatReactionAccount(id: "owner", instance: "example.test")
        let first = MissCatReactionItem(rawValue: "1", displayValue: "1")
        let second = MissCatReactionItem(rawValue: "2", displayValue: "2")
        let repository = FakeReactionRepository(
            accounts: [account],
            snapshot: .init(account: account, favorites: [first], available: [first, second])
        )
        repository.saveDelayNanoseconds = 100_000_000
        let store = MissCatReactionSettingsStore(repository: repository)
        store.load(accountID: account.id)
        await eventually { store.snapshot != nil }
        store.add(second)

        store.saveIfNeeded()
        store.loadAccounts()
        await eventually { repository.savedSnapshots.count == 1 && !store.isSaving }

        XCTAssertEqual(repository.savedSnapshots.first?.favorites, [first, second])
    }

    func testFailedReactionSaveRemainsRetryable() async {
        let account = MissCatReactionAccount(id: "owner", instance: "example.test")
        let first = MissCatReactionItem(rawValue: "1", displayValue: "1")
        let second = MissCatReactionItem(rawValue: "2", displayValue: "2")
        let repository = FakeReactionRepository(
            accounts: [account],
            snapshot: .init(account: account, favorites: [first], available: [first, second])
        )
        repository.saveError = MissCatAccountManagementError.accountPersistenceFailed
        let store = MissCatReactionSettingsStore(repository: repository)
        store.load(accountID: account.id)
        await eventually { store.snapshot != nil }
        store.add(second)

        store.saveIfNeeded()
        await eventually { if case .error = store.presentation { return true }; return false }
        repository.saveError = nil
        store.retrySave()
        await eventually { repository.savedSnapshots.count == 1 && !store.isSaving }

        XCTAssertEqual(repository.savedSnapshots.first?.favorites, [first, second])
    }
}

final class MissCatEmojiArchiveTests: XCTestCase {
    func testSecureArchiveRoundTripAndCorruptDataRecovery() throws {
        let items = [EmojiView.EmojiModel(
            rawEmoji: ":misscat:",
            isDefault: false,
            defaultEmoji: nil,
            customEmojiUrl: "https://example.test/misscat.apng"
        )]
        let data = try EmojiView.EmojiModel.archiveEmojis(items)
        let decoded = EmojiView.EmojiModel.decodeStoredEmojis(data)

        XCTAssertEqual(decoded?.map(\.rawEmoji), [":misscat:"])
        XCTAssertNil(EmojiView.EmojiModel.decodeStoredEmojis(Data([0x00, 0x01, 0x02])))
    }

    func testLegacyNonSecureArchiveCanBeReadForMigration() throws {
        let items = [EmojiView.EmojiModel(
            rawEmoji: "👍",
            isDefault: true,
            defaultEmoji: "👍",
            customEmojiUrl: nil
        )]
        let legacy = try NSKeyedArchiver.archivedData(
            withRootObject: items,
            requiringSecureCoding: false
        )

        XCTAssertEqual(EmojiView.EmojiModel.decodeStoredEmojis(legacy)?.map(\.rawEmoji), ["👍"])
    }

    func testLegacyDecoderRejectsAnArchiveContainingAnUnapprovedClass() throws {
        let hostile = try NSKeyedArchiver.archivedData(
            withRootObject: [HostileEmojiArchiveObject()],
            requiringSecureCoding: false
        )

        XCTAssertNil(EmojiView.EmojiModel.decodeStoredEmojis(hostile))
    }

    func testDecoderRejectsSecureCodingSubclassBeforeInstantiation() throws {
        HostileEmojiModelSubclass.decodeCount = 0
        let hostile = try NSKeyedArchiver.archivedData(
            withRootObject: [HostileEmojiModelSubclass(
                rawEmoji: ":hostile:",
                isDefault: false,
                defaultEmoji: nil,
                customEmojiUrl: "https://example.test/hostile.svg"
            )],
            requiringSecureCoding: true
        )

        XCTAssertFalse(EmojiView.EmojiModel.hasExactArchiveClassGraph(hostile))
        XCTAssertNil(EmojiView.EmojiModel.decodeStoredEmojis(hostile))
        XCTAssertEqual(HostileEmojiModelSubclass.decodeCount, 0)
    }

    func testExactArchiveComparisonCoversOrderAndAllPersistedFields() {
        let expected = [
            EmojiView.EmojiModel(
                rawEmoji: ":cat:",
                isDefault: false,
                defaultEmoji: nil,
                customEmojiUrl: "https://example.test/cat.gif"
            ),
            EmojiView.EmojiModel(
                rawEmoji: "👍",
                isDefault: true,
                defaultEmoji: "👍",
                customEmojiUrl: nil
            )
        ]
        let exact = expected.map {
            EmojiView.EmojiModel(
                rawEmoji: $0.rawEmoji,
                isDefault: $0.isDefault,
                defaultEmoji: $0.defaultEmoji,
                customEmojiUrl: $0.customEmojiUrl
            )
        }
        let wrongDefaultFlag = [
            EmojiView.EmojiModel(
                rawEmoji: ":cat:",
                isDefault: true,
                defaultEmoji: nil,
                customEmojiUrl: "https://example.test/cat.gif"
            ),
            exact[1]
        ]
        let wrongDefaultEmoji = [
            exact[0],
            EmojiView.EmojiModel(
                rawEmoji: "👍",
                isDefault: true,
                defaultEmoji: "👎",
                customEmojiUrl: nil
            )
        ]
        let wrongURL = [
            EmojiView.EmojiModel(
                rawEmoji: ":cat:",
                isDefault: false,
                defaultEmoji: nil,
                customEmojiUrl: "https://example.test/other.gif"
            ),
            exact[1]
        ]

        XCTAssertTrue(EmojiView.EmojiModel.archiveFieldsEqual(exact, expected))
        XCTAssertFalse(EmojiView.EmojiModel.archiveFieldsEqual(Array(exact.reversed()), expected))
        XCTAssertFalse(EmojiView.EmojiModel.archiveFieldsEqual(wrongDefaultFlag, expected))
        XCTAssertFalse(EmojiView.EmojiModel.archiveFieldsEqual(wrongDefaultEmoji, expected))
        XCTAssertFalse(EmojiView.EmojiModel.archiveFieldsEqual(wrongURL, expected))
    }

    func testFailedReactionReadbackRestoresPreviousArchiveAndVersion() throws {
        let owner = SecureUser(
            userId: "fixture-account",
            username: "fixture",
            instance: "example.test",
            apiKey: nil
        )
        let previous = [EmojiView.EmojiModel(
            rawEmoji: "👍",
            isDefault: true,
            defaultEmoji: "👍",
            customEmojiUrl: nil
        )]
        let replacement = [EmojiView.EmojiModel(
            rawEmoji: ":cat:",
            isDefault: false,
            defaultEmoji: nil,
            customEmojiUrl: "https://example.test/cat.gif"
        )]
        let key = EmojiView.EmojiModel.getKey(type: .favs, owner: owner)
        let storage = InMemoryEmojiArchiveStorage(
            data: [key: try EmojiView.EmojiModel.archiveEmojis(previous)],
            versions: ["\(key).secure-archive-version": 2]
        )
        storage.corruptNextDataWrite = true

        XCTAssertThrowsError(try EmojiView.EmojiModel.saveEmojisChecked(
            with: replacement,
            type: .favs,
            owner: owner,
            storage: storage.interface
        ))

        let restoredData = try XCTUnwrap(storage.data[key])
        let restored = try XCTUnwrap(EmojiView.EmojiModel.decodeStoredEmojis(restoredData))
        XCTAssertTrue(EmojiView.EmojiModel.archiveFieldsEqual(restored, previous))
        XCTAssertEqual(storage.versions["\(key).secure-archive-version"], 2)
    }

    func testLegacyInstanceSpellingMovesOnceToCanonicalSecureKeyWithoutAccountSecrets() throws {
        let owner = SecureUser(
            userId: "https://example.test|same-server-user-id",
            username: "fixture",
            instance: "example.test",
            apiKey: "fixture-token-must-not-be-persisted"
        )
        let item = EmojiView.EmojiModel(
            rawEmoji: ":cat:",
            isDefault: false,
            defaultEmoji: nil,
            customEmojiUrl: "https://example.test/cat.svg"
        )
        let legacyKey = "favs-HTTPS://Example.TEST/"
        let legacyData = try NSKeyedArchiver.archivedData(
            withRootObject: [item],
            requiringSecureCoding: false
        )
        let storage = InMemoryEmojiArchiveStorage(
            data: [legacyKey: legacyData],
            versions: ["\(legacyKey).secure-archive-version": 1]
        )

        let migrated = EmojiView.EmojiModel.getEmojis(
            type: .favs,
            owner: owner,
            storage: storage.interface
        )
        let canonicalKey = EmojiView.EmojiModel.getKey(type: .favs, owner: owner)

        XCTAssertEqual(migrated?.map(\.rawEmoji), [":cat:"])
        XCTAssertNil(storage.data[legacyKey])
        XCTAssertNil(storage.versions["\(legacyKey).secure-archive-version"])
        XCTAssertNotNil(storage.data[canonicalKey])
        XCTAssertEqual(storage.versions["\(canonicalKey).secure-archive-version"], 2)
        XCTAssertFalse(storage.keys.contains { $0.contains(owner.userId) })
        for forbidden in [owner.userId, owner.apiKey].compactMap({ $0 }) {
            XCTAssertFalse(storage.keys.contains { $0.contains(forbidden) })
            XCTAssertTrue(storage.data.values.allSatisfy { data in
                data.range(of: Data(forbidden.utf8)) == nil
                    && data.range(of: forbidden.data(using: .utf16LittleEndian) ?? Data()) == nil
            })
        }

        let firstCanonicalData = storage.data[canonicalKey]
        let secondRead = EmojiView.EmojiModel.getEmojis(
            type: .favs,
            owner: owner,
            storage: storage.interface
        )
        XCTAssertEqual(secondRead?.map(\.rawEmoji), [":cat:"])
        XCTAssertEqual(storage.data[canonicalKey], firstCanonicalData)
    }
}

final class MissCatThemeProductionContractTests: XCTestCase {
    func testTabOwnerMigrationUsesCompositeIDsAndRepairsAmbiguousOrMissingOwners() {
        let first = SecureUser(
            userId: "same-user",
            username: "first",
            instance: "first.example",
            apiKey: nil
        )
        let second = SecureUser(
            userId: "same-user",
            username: "second",
            instance: "second.example",
            apiKey: nil
        )
        let fallback = SecureUser(
            userId: "fallback-user",
            username: "fallback",
            instance: "fallback.example",
            apiKey: nil
        )
        let unique = SecureUser(
            userId: "unique-user",
            username: "unique",
            instance: "unique.example",
            apiKey: nil
        )
        let users = [first, second, fallback, unique]

        XCTAssertEqual(
            Theme.resolvedTabOwnerIdentifier(
                second.accountIdentifier,
                users: users,
                fallbackAccountIdentifier: fallback.accountIdentifier
            ),
            second.accountIdentifier
        )
        XCTAssertEqual(
            Theme.resolvedTabOwnerIdentifier(
                unique.userId,
                users: users,
                fallbackAccountIdentifier: fallback.accountIdentifier
            ),
            unique.accountIdentifier
        )
        XCTAssertEqual(
            Theme.resolvedTabOwnerIdentifier(
                "same-user",
                users: users,
                fallbackAccountIdentifier: fallback.accountIdentifier
            ),
            fallback.accountIdentifier
        )
        XCTAssertEqual(
            Theme.resolvedTabOwnerIdentifier(
                nil,
                users: users,
                fallbackAccountIdentifier: fallback.accountIdentifier
            ),
            fallback.accountIdentifier
        )
        XCTAssertEqual(
            Theme.resolvedTabOwnerIdentifier(
                "missing-user",
                users: users,
                fallbackAccountIdentifier: fallback.accountIdentifier
            ),
            fallback.accountIdentifier
        )
    }

    func testTabRemovalDropsBareLegacyOwnerOnlyWhenUnambiguous() {
        let composite = "https://first.example|same-user"
        let bare = "same-user"
        let other = "https://second.example|same-user"
        let tabs = [
            Theme.Tab(name: "First", kind: .home, userId: composite, listId: nil),
            Theme.Tab(name: "Legacy", kind: .local, userId: bare, listId: nil),
            Theme.Tab(name: "Second", kind: .global, userId: other, listId: nil)
        ]

        let ambiguous = Theme.removingTabs(
            forAccountIdentifier: composite,
            legacyUserID: nil,
            from: tabs,
            defaults: []
        )
        XCTAssertEqual(ambiguous.tabs.map(\.userId), [bare, other])

        let unique = Theme.removingTabs(
            forAccountIdentifier: composite,
            legacyUserID: bare,
            from: tabs,
            defaults: []
        )
        XCTAssertEqual(unique.tabs.map(\.userId), [other])
    }

    func testRemovingThreeBoundTabsReportsChangeWhenDefaultsAlsoHaveThreeTabs() {
        let bound = [
            Theme.Tab(name: "A", kind: .home, userId: "owner", listId: nil),
            Theme.Tab(name: "B", kind: .local, userId: "owner", listId: nil),
            Theme.Tab(name: "C", kind: .global, userId: "owner", listId: nil)
        ]
        let defaults = Theme.Model.getDefault()?.tab ?? []

        let result = Theme.removingTabs(for: "owner", from: bound, defaults: defaults)

        XCTAssertTrue(result.changed)
        XCTAssertEqual(result.tabs, defaults)
        XCTAssertEqual(result.tabs.count, 3)
    }

    @MainActor
    func testProductionAdapterReadbackChecksOrderedNameKindOwnerAndListID() {
        let tabs = [
            Theme.Tab(name: "Home", kind: .home, userId: "owner-a", listId: nil),
            Theme.Tab(name: "Friends", kind: .list, userId: "owner-b", listId: "list-42")
        ]
        let expected = Theme.Model(tab: tabs, mainColorHex: "ABCDEF", colorMode: .dark)
        let exact = Theme.Model(tab: tabs, mainColorHex: "ABCDEF", colorMode: .dark)
        let reordered = Theme.Model(tab: Array(tabs.reversed()), mainColorHex: "ABCDEF", colorMode: .dark)
        let wrongOwner = Theme.Model(
            tab: [tabs[0], Theme.Tab(name: "Friends", kind: .list, userId: "owner-a", listId: "list-42")],
            mainColorHex: "ABCDEF",
            colorMode: .dark
        )
        let wrongList = Theme.Model(
            tab: [tabs[0], Theme.Tab(name: "Friends", kind: .list, userId: "owner-b", listId: "list-99")],
            mainColorHex: "ABCDEF",
            colorMode: .dark
        )

        XCTAssertTrue(MissCatLegacySettingsRepository.persistedThemeMatches(exact, expected: expected))
        XCTAssertFalse(MissCatLegacySettingsRepository.persistedThemeMatches(reordered, expected: expected))
        XCTAssertFalse(MissCatLegacySettingsRepository.persistedThemeMatches(wrongOwner, expected: expected))
        XCTAssertFalse(MissCatLegacySettingsRepository.persistedThemeMatches(wrongList, expected: expected))
    }

    func testProductionThemeSaveRollsBackBytesAndRuntimeWithoutPublishingOnReadbackMismatch() throws {
        let old = Theme.Model(
            tab: [Theme.Tab(name: "Local", kind: .local, userId: "owner", listId: nil)],
            mainColorHex: "2F7CF6",
            colorMode: .light
        )
        let oldData = try JSONEncoder().encode(old)
        let storage = InMemoryThemeStorage(data: oldData)
        var publications = 0
        let theme = Theme(
            modelStorage: storage.interface,
            persistencePublishObserver: { _ in publications += 1 }
        )
        theme.currentModel = old
        storage.corruptNextWrite = true
        let candidate = Theme.Model(
            tab: [Theme.Tab(name: "World", kind: .global, userId: "owner", listId: "list-42")],
            mainColorHex: "ABCDEF",
            colorMode: .dark
        )

        XCTAssertThrowsError(try theme.saveAtomically(with: candidate))

        XCTAssertEqual(storage.data, oldData)
        XCTAssertTrue(theme.currentModel === old)
        XCTAssertTrue(try XCTUnwrap(Theme.Model.decode(storage.data ?? Data())).isEqual(to: old))
        XCTAssertEqual(publications, 0)
    }

    @MainActor
    func testProductionDesignAdapterSurfacesInjectedReadbackFailureAfterRollback() async throws {
        let old = Theme.Model(
            tab: [Theme.Tab(name: "Local", kind: .local, userId: "owner", listId: nil)],
            mainColorHex: "2F7CF6",
            colorMode: .light
        )
        let oldData = try JSONEncoder().encode(old)
        let storage = InMemoryThemeStorage(data: oldData)
        let theme = Theme(modelStorage: storage.interface)
        theme.currentModel = old
        storage.corruptNextWrite = true
        let repository = MissCatLegacySettingsRepository(theme: theme)
        let owner = account("owner")
        let snapshot = MissCatDesignSettingsSnapshot(
            tabs: [.init(name: "World", kind: .global, accountID: owner.id)],
            mode: .dark,
            accentHex: "ABCDEF",
            accounts: [owner]
        )

        do {
            _ = try await repository.saveDesignSettings(snapshot)
            XCTFail("The adapter accepted an unpersisted theme")
        } catch {
            XCTAssertEqual(
                error as? MissCatAccountManagementError,
                .accountPersistenceFailed
            )
        }

        XCTAssertEqual(storage.data, oldData)
        XCTAssertTrue(theme.currentModel === old)
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

    func testLicenseCatalogExactlyMatchesBundledCocoaPodsAcknowledgementContent() throws {
        let catalog = LicenseTableViewController.getOssDescription()
        let expected = LicenseTableViewController.podfileLockDependencyNames
        let authoritative = try XCTUnwrap(
            LicenseTableViewController.bundledAcknowledgementCatalog(
                in: Bundle(for: LicenseTableViewController.self)
            )
        )

        XCTAssertEqual(catalog.keys.sorted(), expected.sorted())
        XCTAssertEqual(catalog, authoritative)
        XCTAssertEqual(catalog.count, 22)
        for name in expected {
            XCTAssertEqual(catalog[name], authoritative[name], "Acknowledgement text differs for \(name)")
        }
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

    @MainActor
    func testReactionPickerReadinessWaitsForEveryRegisteredMediaCell() {
        let readiness = MissCatReactionMediaReadiness()
        readiness.register("gif")
        readiness.register("apng")
        readiness.finishInitialRegistrationPass()

        XCTAssertFalse(readiness.isReady)
        readiness.complete("gif", succeeded: true)
        XCTAssertFalse(readiness.isReady)
        readiness.complete("apng", succeeded: true)
        XCTAssertTrue(readiness.isReady)

        readiness.register("svg")
        XCTAssertFalse(readiness.isReady)
        readiness.complete("svg", succeeded: true)
        XCTAssertTrue(readiness.isReady)
    }

    @MainActor
    func testReactionPickerDecodeFailureIsTerminalVisibleAndNeverReady() {
        let readiness = MissCatReactionMediaReadiness()
        readiness.register("broken")
        readiness.finishInitialRegistrationPass()

        readiness.complete("broken", succeeded: false)

        XCTAssertFalse(readiness.isReady)
        XCTAssertEqual(readiness.failureMessage, "リアクション画像を読み込めませんでした")
    }

    func testReactionVisualFixturesAreBundledGIFAPNGAndSVGFiles() throws {
        let bundle = Bundle(for: MissCatLegacySettingsRepository.self)
        let gif = try XCTUnwrap(bundle.url(forResource: "reaction-fixture", withExtension: "gif"))
        let apng = try XCTUnwrap(bundle.url(forResource: "reaction-fixture", withExtension: "apngdata"))
        let svg = try XCTUnwrap(bundle.url(forResource: "reaction-fixture", withExtension: "svg"))
        let gifData = try Data(contentsOf: gif)
        let apngData = try Data(contentsOf: apng)
        let svgData = try Data(contentsOf: svg)

        XCTAssertTrue(String(data: gifData.prefix(6), encoding: .ascii)?.hasPrefix("GIF") == true)
        XCTAssertNotNil(apngData.range(of: Data("acTL".utf8)))
        XCTAssertTrue(String(data: svgData, encoding: .utf8)?.contains("<svg") == true)
        XCTAssertEqual(MFMImageView.imageFormat(gifData), .gif)
        XCTAssertEqual(MFMImageView.imageFormat(apngData), .apng)
        XCTAssertEqual(MFMImageView.imageFormat(svgData), .other)
        XCTAssertTrue([gif, apng, svg].allSatisfy(\.isFileURL))
    }

    @MainActor
    func testProductionImageViewDecodesEveryLocalFixtureAndRejectsInvalidFixture() async throws {
        let bundle = Bundle(for: MissCatLegacySettingsRepository.self)
        let valid = [
            try XCTUnwrap(bundle.url(forResource: "reaction-fixture", withExtension: "gif")),
            try XCTUnwrap(bundle.url(forResource: "reaction-fixture", withExtension: "apngdata")),
            try XCTUnwrap(bundle.url(forResource: "reaction-fixture", withExtension: "svg"))
        ]

        for url in valid {
            let loaded = expectation(description: "decode \(url.lastPathComponent)")
            let imageView = MFMImageView(frame: CGRect(x: 0, y: 0, width: 32, height: 32))
            imageView.setImage(url: url.absoluteString) { succeeded in
                XCTAssertTrue(succeeded, "Production decoder rejected \(url.lastPathComponent)")
                loaded.fulfill()
            }
            await fulfillment(of: [loaded], timeout: 3)
            imageView.prepareForReuse()
        }

        let invalid = try XCTUnwrap(
            bundle.url(forResource: "reaction-fixture", withExtension: "invalid")
        )
        let rejected = expectation(description: "reject invalid fixture")
        let imageView = MFMImageView(frame: CGRect(x: 0, y: 0, width: 32, height: 32))
        imageView.setImage(url: invalid.absoluteString) { succeeded in
            XCTAssertFalse(succeeded)
            rejected.fulfill()
        }
        await fulfillment(of: [rejected], timeout: 3)
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
    var saveDelayNanoseconds: UInt64 = 0
    var saveError: Error?
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
        if saveDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: saveDelayNanoseconds)
        }
        if let saveError { throw saveError }
        savedSnapshots.append(snapshot)
        self.snapshot = snapshot
        return .init(snapshot: snapshot, requiresRootRelaunch: requiresRelaunch)
    }
}

@MainActor
private final class FakeReactionRepository: MissCatReactionSettingsManaging {
    var accounts: [MissCatReactionAccount]
    var snapshot: MissCatReactionSettingsSnapshot
    var saveDelayNanoseconds: UInt64 = 0
    var saveError: Error?
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
        if saveDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: saveDelayNanoseconds)
        }
        if let saveError { throw saveError }
        savedSnapshots.append(snapshot)
        self.snapshot = snapshot
    }
}

@objc(HostileEmojiArchiveObject)
private final class HostileEmojiArchiveObject: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool { true }

    override init() {
        super.init()
    }

    required init?(coder: NSCoder) {
        super.init()
    }

    func encode(with coder: NSCoder) {}
}

@objc(HostileEmojiModelSubclass)
private final class HostileEmojiModelSubclass: EmojiView.EmojiModel {
    static var decodeCount = 0
    override class var supportsSecureCoding: Bool { true }

    override init(
        rawEmoji: String,
        isDefault: Bool,
        defaultEmoji: String?,
        customEmojiUrl: String?,
        isFake: Bool = false
    ) {
        super.init(
            rawEmoji: rawEmoji,
            isDefault: isDefault,
            defaultEmoji: defaultEmoji,
            customEmojiUrl: customEmojiUrl,
            isFake: isFake
        )
    }

    required init?(coder aDecoder: NSCoder) {
        Self.decodeCount += 1
        super.init(coder: aDecoder)
    }
}

private final class InMemoryThemeStorage {
    var data: Data?
    var corruptNextWrite = false

    init(data: Data?) {
        self.data = data
    }

    var interface: ThemeModelStorage {
        ThemeModelStorage(
            data: { [weak self] _ in self?.data },
            setData: { [weak self] data, _ in
                guard let self else { return }
                if corruptNextWrite {
                    corruptNextWrite = false
                    self.data = Data([0x00, 0x01, 0x02])
                } else {
                    self.data = data
                }
            }
        )
    }
}

private final class InMemoryEmojiArchiveStorage {
    var data: [String: Data]
    var versions: [String: Int]
    var corruptNextDataWrite = false

    init(data: [String: Data] = [:], versions: [String: Int] = [:]) {
        self.data = data
        self.versions = versions
    }

    var keys: [String] {
        Array(Set(data.keys).union(versions.keys))
    }

    var interface: EmojiArchiveStorage {
        EmojiArchiveStorage(
            data: { [weak self] in self?.data[$0] },
            version: { [weak self] in self?.versions[$0] },
            setData: { [weak self] value, key in
                guard let self else { return }
                if corruptNextDataWrite {
                    corruptNextDataWrite = false
                    data[key] = Data([0x00, 0x01, 0x02])
                } else {
                    data[key] = value
                }
            },
            setVersion: { [weak self] value, key in self?.versions[key] = value },
            keys: { [weak self] in self?.keys ?? [] }
        )
    }
}

private final class SettingsIntegrationDefaultsStore: AccountDefaultsStoring {
    var values: [String: Any] = [:]
    var blockedSetKeys: Set<String> = []

    func object(forKey defaultName: String) -> Any? { values[defaultName] }
    func data(forKey defaultName: String) -> Data? { values[defaultName] as? Data }
    func string(forKey defaultName: String) -> String? { values[defaultName] as? String }

    func set(_ value: Any?, forKey defaultName: String) {
        guard !blockedSetKeys.contains(defaultName) else { return }
        values[defaultName] = value
    }

    func removeObject(forKey defaultName: String) {
        values.removeValue(forKey: defaultName)
    }

    func synchronize() -> Bool { true }
}

private final class SettingsIntegrationAPIKeyStore: AccountAPIKeyStoring {
    var values: [String: String] = [:]

    func apiKey(for accountID: String) throws -> String? { values[accountID] }
    func setAPIKey(_ apiKey: String, for accountID: String) throws { values[accountID] = apiKey }
    func removeAPIKey(for accountID: String) throws { values.removeValue(forKey: accountID) }
    func allAccountIDs() throws -> [String] { Array(values.keys) }
}

private final class SettingsURLProtocolStub: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (statusCode, data) = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
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
