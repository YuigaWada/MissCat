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

    func testRouterPathObservationInvalidatesAfterTypedRouteMutation() {
        let router = MissCatApplicationRouter()
        let invalidatedPath = expectation(description: "Router path invalidated")

        withObservationTracking {
            _ = router.path
        } onChange: {
            invalidatedPath.fulfill()
        }

        router.open(.profile(userID: "fixture-author-0"))

        wait(for: [invalidatedPath], timeout: 0.1)
        XCTAssertEqual(router.path, [.profile(userID: "fixture-author-0")])
    }

    func testRouterKeepsNestedProfileFamilyDestinationsOnTheProductionStack() {
        let router = MissCatApplicationRouter()
        let profile = MissCatProfileUser(
            id: "fixture-author-0",
            name: "Route Author",
            username: "route-author"
        )

        router.open(.profile(userID: profile.id))
        router.open(.profileUserList(.followers(userID: profile.id)))
        router.open(.profileEditor(profile))

        XCTAssertEqual(
            router.path,
            [
                .profile(userID: profile.id),
                .profileUserList(.followers(userID: profile.id)),
                .profileEditor(profile),
            ]
        )

        router.pop()
        XCTAssertEqual(router.path.last, .profileUserList(.followers(userID: profile.id)))
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

    func testSignOutClearsAccountNavigationAndPresentation() async {
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
