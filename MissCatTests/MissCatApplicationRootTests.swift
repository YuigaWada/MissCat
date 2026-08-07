@testable import MissCat
import XCTest

@MainActor
final class MissCatApplicationRootTests: XCTestCase {
    func testAccountIdentityIsInstanceScopedAndNormalized() {
        let first = account(instance: " HTTPS://Social.Example/ ", userID: "shared", username: "cat")
        let equivalent = account(instance: "social.example", userID: "shared", username: "cat")
        let otherInstance = account(instance: "other.example", userID: "shared", username: "cat")

        XCTAssertEqual(first.id, equivalent.id)
        XCTAssertEqual(first.instance, "social.example")
        XCTAssertNotEqual(first.id, otherInstance.id)
    }

    func testSessionNormalizesAccountsTabsAndSelection() {
        let current = account(instance: "one.example", userID: "one", username: "cat")
        let other = account(instance: "two.example", userID: "two", username: "dog")
        let session = MissCatApplicationSession(
            currentAccount: current,
            accounts: [other, other],
            timelineTabs: [tab("home"), tab("local"), tab("home")],
            selectedTimelineID: "missing"
        )

        XCTAssertEqual(session.accounts.map(\.id), [current.id, other.id])
        XCTAssertEqual(session.timelineTabs.map(\.id), ["home", "local"])
        XCTAssertEqual(session.selectedTimelineID, "home")
    }

    func testTabSelectionSupportsTapBothSwipeDirectionsAndExplicitBoundaries() {
        var selection = MissCatApplicationTabSelection(
            tabs: [tab("home"), tab("local"), tab("social"), tab("global")],
            selectedID: "home"
        )

        XCTAssertEqual(selection.swipeRight(), .boundary(.first, id: "home"))
        XCTAssertEqual(selection.select("social"), .changed(id: "social", origin: .tap))
        XCTAssertEqual(selection.swipeLeft(), .changed(id: "global", origin: .swipeLeft))
        XCTAssertEqual(selection.swipeLeft(), .boundary(.last, id: "global"))
        XCTAssertEqual(selection.swipeRight(), .changed(id: "social", origin: .swipeRight))
        XCTAssertEqual(selection.select("missing"), .rejected(candidate: "missing"))
        XCTAssertEqual(selection.selectedID, "social")
    }

    func testTabReplacementPreservesValidSelectionAndFallsBackWithoutWrapping() {
        var selection = MissCatApplicationTabSelection(
            tabs: [tab("home"), tab("local"), tab("global")],
            selectedID: "local"
        )

        XCTAssertEqual(
            selection.updateTabs([tab("local"), tab("social"), tab("local")]),
            .unchanged(id: "local")
        )
        XCTAssertEqual(selection.tabs.map(\.id), ["local", "social"])
        XCTAssertEqual(
            selection.updateTabs([tab("home"), tab("global")]),
            .changed(id: "home", origin: .tabsChanged)
        )
        XCTAssertEqual(selection.swipeRight(), .boundary(.first, id: "home"))
    }

    func testRouterKeepsTypedPathsPerRootAndMakesModalPresentationExclusive() {
        let primary = session(account: account(instance: "one.example", userID: "one", username: "cat"))
        let router = MissCatApplicationRouter()
        router.activate(primary)

        router.open(.note(id: "note-1"))
        XCTAssertEqual(router.path, [.note(id: "note-1")])
        XCTAssertEqual(router.selectRoot(.notifications), .selected(.notifications))
        router.open(.profile(userID: "user-2"))
        XCTAssertEqual(router.path, [.profile(userID: "user-2")])
        XCTAssertEqual(router.path(for: .home), [.note(id: "note-1")])
        XCTAssertEqual(router.selectRoot(.notifications), .reselected(.notifications))

        router.presentSheet(.accountSwitcher)
        XCTAssertEqual(router.sheetDestination, .accountSwitcher)
        router.presentFullScreen(.compose(.reply(noteID: "note-1")))
        XCTAssertNil(router.sheetDestination)
        XCTAssertEqual(router.fullScreenDestination, .compose(.reply(noteID: "note-1")))

        let secondary = session(account: account(instance: "two.example", userID: "two", username: "dog"))
        router.activate(secondary)
        XCTAssertEqual(router.activeAccountID, secondary.currentAccount.id)
        XCTAssertEqual(router.selectedSection, .home)
        XCTAssertTrue(router.path(for: .home).isEmpty)
        XCTAssertTrue(router.path(for: .notifications).isEmpty)
        XCTAssertNil(router.fullScreenDestination)
    }

    func testMailboxQueuesBeforeReadinessFlushesFIFOAndRejectsWrongAccount() async {
        let firstAccount = account(instance: "one.example", userID: "one", username: "cat")
        let secondAccount = account(instance: "two.example", userID: "two", username: "dog")
        let mailbox = MissCatApplicationPushMailbox(capacity: 4)
        let first = push("delivery-1", account: firstAccount, notificationID: "notification-1")
        let second = push("delivery-2", account: firstAccount, notificationID: "notification-2")
        let wrong = push("delivery-3", account: secondAccount, notificationID: "notification-3")
        let wrongAfterReady = push(
            "delivery-4",
            account: secondAccount,
            notificationID: "notification-4"
        )

        let firstAdmission = await mailbox.enqueue(first)
        let secondAdmission = await mailbox.enqueue(second)
        let wrongAdmission = await mailbox.enqueue(wrong)
        let duplicateAdmission = await mailbox.enqueue(first)
        XCTAssertEqual(firstAdmission, .queued)
        XCTAssertEqual(secondAdmission, .queued)
        XCTAssertEqual(wrongAdmission, .queued)
        XCTAssertEqual(duplicateAdmission, .duplicate)

        let deliveries = await mailbox.setRootReady(for: firstAccount.id)
        XCTAssertEqual(deliveries, [first, second])
        let readyWrongAdmission = await mailbox.enqueue(wrongAfterReady)
        XCTAssertEqual(
            readyWrongAdmission,
            .rejected(.accountMismatch(expected: firstAccount.id, received: secondAccount.id))
        )
        let snapshot = await mailbox.snapshot()
        XCTAssertTrue(snapshot.isRootReady)
        XCTAssertEqual(snapshot.pendingCount, 0)
        XCTAssertEqual(snapshot.rejectedCount, 2)
        XCTAssertEqual(snapshot.duplicateCount, 1)
    }

    func testMailboxIsBoundedAndReportsDroppedPushes() async {
        let owner = account(instance: "one.example", userID: "one", username: "cat")
        let mailbox = MissCatApplicationPushMailbox(capacity: 2)
        let first = push("delivery-1", account: owner, notificationID: "notification-1")
        let second = push("delivery-2", account: owner, notificationID: "notification-2")
        let third = push("delivery-3", account: owner, notificationID: "notification-3")

        let firstAdmission = await mailbox.enqueue(first)
        let secondAdmission = await mailbox.enqueue(second)
        let thirdAdmission = await mailbox.enqueue(third)
        XCTAssertEqual(firstAdmission, .queued)
        XCTAssertEqual(secondAdmission, .queued)
        XCTAssertEqual(thirdAdmission, .queued)
        let snapshot = await mailbox.snapshot()
        XCTAssertEqual(snapshot.pendingCount, 2)
        XCTAssertEqual(snapshot.droppedCount, 1)
        let deliveries = await mailbox.setRootReady(for: owner.id)
        XCTAssertEqual(deliveries, [second, third])
    }

    func testPushQueuedBeforeRestoreRoutesOnlyAfterMatchingRootIsReady() async {
        let owner = account(instance: "one.example", userID: "one", username: "cat")
        let provider = ImmediateApplicationSessionProvider(restored: session(account: owner))
        let store = MissCatApplicationRootStore(sessionProvider: provider)
        let pending = push("delivery-1", account: owner, notificationID: "notification-1")

        let admission = await store.receivePush(pending)
        XCTAssertEqual(admission, .queued)
        XCTAssertNil(store.router.latestPush)

        await store.restore()

        XCTAssertEqual(store.phase.authenticatedSession?.currentAccount.id, owner.id)
        XCTAssertEqual(store.router.selectedSection, .notifications)
        XCTAssertEqual(store.router.path, [.notification(id: "notification-1")])
        XCTAssertEqual(store.router.latestPush, pending)
    }

    func testPushForAnotherAccountIsRejectedWhenRestoreCompletes() async {
        let current = account(instance: "one.example", userID: "same", username: "cat")
        let other = account(instance: "two.example", userID: "same", username: "cat")
        let provider = ImmediateApplicationSessionProvider(restored: session(account: current))
        let store = MissCatApplicationRootStore(sessionProvider: provider)
        let pending = push("delivery-1", account: other, notificationID: "notification-1")

        let admission = await store.receivePush(pending)
        XCTAssertEqual(admission, .queued)
        await store.restore()

        XCTAssertNil(store.router.latestPush)
        XCTAssertTrue(store.router.path.isEmpty)
        let snapshot = await store.pushMailbox.snapshot()
        XCTAssertEqual(snapshot.rejectedCount, 1)
        XCTAssertEqual(
            snapshot.lastRejection,
            .accountMismatch(expected: current.id, received: other.id)
        )
    }

    func testPushAfterReadinessDeliversImmediatelyAndRefreshDoesNotNavigate() async {
        let owner = account(instance: "one.example", userID: "one", username: "cat")
        let provider = ImmediateApplicationSessionProvider(restored: session(account: owner))
        let store = MissCatApplicationRootStore(sessionProvider: provider)
        await store.restore()
        let refresh = MissCatApplicationPush(
            id: "delivery-refresh",
            accountID: owner.id,
            action: .refreshNotifications(notificationID: "notification-1")
        )

        let admission = await store.receivePush(refresh)
        XCTAssertEqual(admission, .delivered)
        XCTAssertEqual(store.router.latestPush, refresh)
        XCTAssertEqual(store.router.pushDeliveryGeneration, 1)
        XCTAssertEqual(store.router.selectedSection, .home)
        XCTAssertTrue(store.router.path.isEmpty)
    }

    func testLaterAccountSwitchWinsWhenCanceledProviderReturnsLate() async {
        let primary = account(instance: "one.example", userID: "one", username: "cat")
        let secondary = account(instance: "two.example", userID: "two", username: "dog")
        let tertiary = account(instance: "three.example", userID: "three", username: "fox")
        let provider = ControlledApplicationSessionProvider(restored: session(account: primary))
        let store = MissCatApplicationRootStore(sessionProvider: provider)
        await store.restore()

        let firstSwitch = Task { await store.switchAccount(to: secondary.id) }
        await waitUntil { await provider.hasPendingSwitch(to: secondary.id) }
        let secondSwitch = Task { await store.switchAccount(to: tertiary.id) }
        await waitUntil { await provider.hasPendingSwitch(to: tertiary.id) }

        await provider.resumeSwitch(with: session(account: tertiary), for: tertiary.id)
        await secondSwitch.value
        await provider.resumeSwitch(with: session(account: secondary), for: secondary.id)
        await firstSwitch.value

        XCTAssertEqual(store.phase.authenticatedSession?.currentAccount.id, tertiary.id)
        XCTAssertEqual(store.router.activeAccountID, tertiary.id)
        XCTAssertNil(store.lastErrorMessage)
    }

    func testCanceledNonCooperativeRestoreCannotPublishLateSession() async {
        let owner = account(instance: "one.example", userID: "one", username: "cat")
        let provider = ControlledRestoreApplicationSessionProvider()
        let store = MissCatApplicationRootStore(sessionProvider: provider)
        let restore = Task { await store.restore() }
        await waitUntil { await provider.hasPendingRestore }

        await store.cancelPendingTransition()
        await provider.resumeRestore(with: session(account: owner))
        await restore.value

        XCTAssertEqual(store.phase, .launching)
        XCTAssertNil(store.router.activeAccountID)
    }

    func testSwitchIdentityMismatchRestoresPreviousSessionAndPublishesError() async {
        let primary = account(instance: "one.example", userID: "one", username: "cat")
        let requested = account(instance: "two.example", userID: "two", username: "dog")
        let wrong = account(instance: "three.example", userID: "three", username: "fox")
        let provider = ImmediateApplicationSessionProvider(
            restored: session(account: primary),
            switched: [requested.id: session(account: wrong)]
        )
        let store = MissCatApplicationRootStore(sessionProvider: provider)
        await store.restore()

        await store.switchAccount(to: requested.id)

        XCTAssertEqual(store.phase.authenticatedSession?.currentAccount.id, primary.id)
        XCTAssertEqual(store.router.activeAccountID, primary.id)
        XCTAssertEqual(store.lastErrorMessage, "The selected account did not match the restored session.")
    }

    func testSignOutClearsAccountNavigationPresentationAndMailbox() async {
        let owner = account(instance: "one.example", userID: "one", username: "cat")
        let provider = ImmediateApplicationSessionProvider(restored: session(account: owner))
        let store = MissCatApplicationRootStore(sessionProvider: provider)
        await store.restore()
        store.router.open(.note(id: "note-1"))
        store.router.presentSheet(.settings)

        await store.signOut()

        XCTAssertEqual(store.phase, .signedOut)
        XCTAssertNil(store.router.activeAccountID)
        XCTAssertTrue(store.router.path.isEmpty)
        XCTAssertNil(store.router.sheetDestination)
        let snapshot = await store.pushMailbox.snapshot()
        XCTAssertFalse(snapshot.isRootReady)
        XCTAssertEqual(snapshot.pendingCount, 0)
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        condition: @escaping () async -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("Timed out waiting for asynchronous state")
    }
}

private actor ImmediateApplicationSessionProvider: MissCatApplicationSessionProviding {
    let restored: MissCatApplicationSession?
    let switched: [MissCatApplicationAccountID: MissCatApplicationSession]

    init(
        restored: MissCatApplicationSession?,
        switched: [MissCatApplicationAccountID: MissCatApplicationSession] = [:]
    ) {
        self.restored = restored
        self.switched = switched
    }

    func restoreSession() async throws -> MissCatApplicationSession? {
        restored
    }

    func switchSession(to accountID: MissCatApplicationAccountID) async throws -> MissCatApplicationSession {
        guard let session = switched[accountID] else { throw ApplicationRootTestError.missingSession }
        return session
    }

    func signOut(accountID: MissCatApplicationAccountID) async throws {}
}

private actor ControlledApplicationSessionProvider: MissCatApplicationSessionProviding {
    let restored: MissCatApplicationSession
    private var pendingSwitches: [
        MissCatApplicationAccountID: CheckedContinuation<MissCatApplicationSession, Never>
    ] = [:]

    init(restored: MissCatApplicationSession) {
        self.restored = restored
    }

    func restoreSession() async throws -> MissCatApplicationSession? {
        restored
    }

    func switchSession(to accountID: MissCatApplicationAccountID) async throws -> MissCatApplicationSession {
        await withCheckedContinuation { continuation in
            pendingSwitches[accountID] = continuation
        }
    }

    func signOut(accountID: MissCatApplicationAccountID) async throws {}

    func hasPendingSwitch(to accountID: MissCatApplicationAccountID) -> Bool {
        pendingSwitches[accountID] != nil
    }

    func resumeSwitch(
        with session: MissCatApplicationSession,
        for accountID: MissCatApplicationAccountID
    ) {
        pendingSwitches.removeValue(forKey: accountID)?.resume(returning: session)
    }
}

private actor ControlledRestoreApplicationSessionProvider: MissCatApplicationSessionProviding {
    private var continuation: CheckedContinuation<MissCatApplicationSession?, Never>?

    var hasPendingRestore: Bool { continuation != nil }

    func restoreSession() async throws -> MissCatApplicationSession? {
        await withCheckedContinuation { continuation = $0 }
    }

    func switchSession(to accountID: MissCatApplicationAccountID) async throws -> MissCatApplicationSession {
        throw ApplicationRootTestError.missingSession
    }

    func signOut(accountID: MissCatApplicationAccountID) async throws {}

    func resumeRestore(with session: MissCatApplicationSession?) {
        continuation?.resume(returning: session)
        continuation = nil
    }
}

private enum ApplicationRootTestError: LocalizedError {
    case missingSession

    var errorDescription: String? { "Missing test session" }
}

private func account(
    instance: String,
    userID: String,
    username: String
) -> MissCatApplicationAccount {
    MissCatApplicationAccount(
        instance: instance,
        userID: userID,
        username: username,
        displayName: username.capitalized
    )
}

private func tab(_ id: String) -> MissCatTimelineTab {
    MissCatTimelineTab(id: id, title: id.capitalized)
}

private func session(account: MissCatApplicationAccount) -> MissCatApplicationSession {
    MissCatApplicationSession(
        currentAccount: account,
        accounts: [account],
        timelineTabs: [tab("home"), tab("local"), tab("global")],
        selectedTimelineID: "home"
    )
}

private func push(
    _ id: String,
    account: MissCatApplicationAccount,
    notificationID: String
) -> MissCatApplicationPush {
    MissCatApplicationPush(
        id: id,
        accountID: account.id,
        action: .openNotification(notificationID: notificationID)
    )
}
