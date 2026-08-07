import FirebaseCore
import FirebaseMessaging
import Foundation
import UserNotifications

@MainActor
final class MissCatApplicationLifecycleCoordinator {
    static let shared = MissCatApplicationLifecycleCoordinator()

    let pushState = MissCatPushLifecycleState()
    private lazy var transportDelegate = MissCatPushTransportDelegate(
        onEnvelope: { [weak self] envelope, opensRoute in
            Task { @MainActor [weak self] in self?.routePush(envelope, opensRoute: opensRoute) }
        },
        onRegistrationToken: { [weak self] in
            Task { @MainActor [weak self] in
                self?.pushState.registered()
                self?.prepareSavedUsers()
            }
        }
    )

    func applicationDidFinishLaunching() -> Bool {
#if DEBUG
        let isRunningUnitTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        if MissCatShellFixtureLaunch.isRequested
            || MissCatPersistenceProbeLaunch.isRequested
            || MissCatAccountsSettingsAcceptanceLaunch.isRequested
            || MissCatProductionRootE2ELaunch.isRequested
            || isRunningUnitTests
        {
            return false
        }
#endif

        Theme.shared.set()

#if DEBUG
        if MissCatProfileOrdinaryRouteConfiguration.isEnabled
            || MissCatLoginProfileFixtureRoute.parse() != nil
            || MissCatNoteOrdinaryRouteConfiguration.isEnabled
            || MissCatDiscoveryFixtureConfiguration.isAutomatedTestRun
            || MissCatDiscoveryOrdinaryRouteConfiguration.isEnabled
        {
            return false
        }
#endif

        configurePushTransport()
        prepareSavedUsers()
        return true
    }

    func remoteRegistrationRequested() {
        pushState.remoteRegistrationRequested()
    }

    func applicationDidBecomeActive() {
        UNUserNotificationCenter.current().setBadgeCount(0)
    }

    func receiveRemoteNotification(_ payload: [AnyHashable: Any], opensRoute: Bool) {
        guard let envelope = MissCatPushEnvelope(payload: payload) else { return }
        routePush(envelope, opensRoute: opensRoute)
    }

    func didRegisterForRemoteNotifications(deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
        pushState.registered()
    }

    func didFailToRegisterForRemoteNotifications(error: Error) {
        pushState.registrationFailed(message: error.localizedDescription)
    }

    private func configurePushTransport() {
        if FirebaseApp.app() == nil { FirebaseApp.configure() }
        Messaging.messaging().delegate = transportDelegate
        let center = UNUserNotificationCenter.current()
        center.delegate = transportDelegate
        pushState.authorizationRequested()
        center.requestAuthorization(options: [.badge, .sound, .alert]) { _, error in
            guard let error else { return }
            Task { @MainActor [weak self] in
                self?.pushState.registrationFailed(message: error.localizedDescription)
            }
        }
    }

    private func prepareSavedUsers() {
        Cache.UserDefaults.shared.getUsers().forEach { user in
#if targetEnvironment(simulator)
            MisscatApi(apiKeyManager: MockApiKeyManager(), and: user).registerSw()
#else
            MisscatApi(apiKeyManager: ApiKeyManager(), and: user).registerSw()
#endif
            MissCatEmojiCatalog.prepare(for: user)
        }
    }

    private func routePush(_ envelope: MissCatPushEnvelope, opensRoute: Bool) {
        let accounts = Cache.UserDefaults.shared.getUsers().map {
            MissCatPushAccountIdentity(
                accountIdentifier: $0.accountIdentifier,
                apiUserID: $0.userId,
                instance: $0.instance
            )
        }
        guard let push = MissCatApplicationPushResolver.resolve(
            envelope,
            accounts: accounts,
            opensRoute: opensRoute
        ) else { return }
        Task { await MissCatApplicationPushIngress.shared.receive(push) }
    }
}

private final class MissCatPushTransportDelegate: NSObject,
    UNUserNotificationCenterDelegate,
    MessagingDelegate
{
    private let onEnvelope: (MissCatPushEnvelope, Bool) -> Void
    private let onRegistrationToken: () -> Void

    init(
        onEnvelope: @escaping (MissCatPushEnvelope, Bool) -> Void,
        onRegistrationToken: @escaping () -> Void
    ) {
        self.onEnvelope = onEnvelope
        self.onRegistrationToken = onRegistrationToken
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard fcmToken?.isEmpty == false else { return }
        onRegistrationToken()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if let envelope = MissCatPushEnvelope(payload: notification.request.content.userInfo) {
            onEnvelope(envelope, false)
        }
        completionHandler([])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let envelope = MissCatPushEnvelope(
            payload: response.notification.request.content.userInfo
        ) {
            onEnvelope(envelope, true)
        }
        completionHandler()
    }
}

/// Exact Cache/Theme adapter used by the production application lifecycle.
/// The application root never compares a bare Misskey user ID when changing
/// the active account.
@MainActor
final class MissCatProductionSessionAdapter: MissCatApplicationSessionProviding {
    private let cache: Cache.UserDefaults
    private let shellProvider: MissCatLegacyShellConfigurationProvider

    init(
        cache: Cache.UserDefaults = .shared,
        defaults: UserDefaults = .standard
    ) {
        self.cache = cache
        shellProvider = MissCatLegacyShellConfigurationProvider(cache: cache, defaults: defaults)
    }

    func restoreSession() async throws -> MissCatApplicationSession? {
#if DEBUG
        if MissCatProductionRootE2ELaunch.isRequested {
            return MissCatProductionRootE2ELaunch.session(
                for: MissCatProductionRootE2EState.shared.persistedAccountID
            )
        }
#endif
        guard let current = cache.getCurrentUser(),
              current.apiKey?.isEmpty == false
        else { return nil }
        guard cache.changeCurrentUser(userId: current.accountIdentifier) else {
            throw MissCatShellConfigurationError.accountIdentityMismatch
        }
        Theme.shared.reset()
        Theme.shared.set()
        return try await makeSession()
    }

    func switchSession(
        to accountID: MissCatApplicationAccountID
    ) async throws -> MissCatApplicationSession {
#if DEBUG
        if MissCatProductionRootE2ELaunch.isRequested {
            guard MissCatProductionRootE2ELaunch.session.accounts.contains(where: { $0.id == accountID })
            else { throw MissCatShellConfigurationError.accountNotFound }
            MissCatProductionRootE2EState.shared.commitRootAccount(accountID)
            return MissCatProductionRootE2ELaunch.session(for: accountID)
        }
#endif
        guard cache.getUsers().contains(where: { $0.accountIdentifier == accountID.rawValue })
        else { throw MissCatShellConfigurationError.accountNotFound }
        guard cache.changeCurrentUser(userId: accountID.rawValue),
              cache.getCurrentUserId() == accountID.rawValue
        else { throw MissCatShellConfigurationError.accountIdentityMismatch }
        Theme.shared.reset()
        Theme.shared.set()
        let session = try await makeSession()
        guard session.currentAccount.id == accountID else {
            throw MissCatApplicationSessionError.accountIdentityMismatch
        }
        return session
    }

    func signOut(accountID: MissCatApplicationAccountID) async throws {
#if DEBUG
        if MissCatProductionRootE2ELaunch.isRequested { return }
#endif
        guard cache.getUsers().contains(where: { $0.accountIdentifier == accountID.rawValue })
        else { throw MissCatShellConfigurationError.accountNotFound }
        guard cache.removeUser(userId: accountID.rawValue) else {
            throw MissCatAccountManagementError.accountPersistenceFailed
        }
        Theme.shared.reset()
    }

    private func makeSession() async throws -> MissCatApplicationSession {
        let configuration = try await shellProvider.loadConfiguration()
        guard let currentUser = cache.getCurrentUser(),
              currentUser.accountIdentifier == cache.getCurrentUserId()
        else { throw MissCatShellConfigurationError.noCurrentAccount }
        let users = cache.getUsers()
        let accounts = users.map { user -> MissCatApplicationAccount in
            let scope = MissCatShellAccountScope(
                instance: user.instance,
                userID: user.userId,
                username: user.username
            )
            let shellAccount = configuration.accounts.first(where: { $0.scope == scope })
            return MissCatApplicationAccount(
                instance: user.instance,
                userID: user.userId,
                username: user.username,
                displayName: shellAccount?.displayName,
                avatarURL: shellAccount?.avatarURL
            )
        }
        let current = accounts.first(where: { $0.id.rawValue == currentUser.accountIdentifier })
            ?? MissCatApplicationAccount(
                instance: currentUser.instance,
                userID: currentUser.userId,
                username: currentUser.username
            )
        return MissCatApplicationSession(
            currentAccount: current,
            accounts: accounts,
            timelineTabs: configuration.timelinePages.map {
                MissCatTimelineTab(
                    id: $0.id,
                    title: $0.title,
                    accessibilityID: $0.accessibilityID
                )
            },
            selectedTimelineID: configuration.selectedTimelineID
        )
    }
}

/// Actor-safe notification ingress. It shares the root mailbox so pushes that
/// arrive before SwiftUI installs its receiver remain queued for restoration.
actor MissCatApplicationPushIngress {
    static let shared = MissCatApplicationPushIngress()

    nonisolated let mailbox = MissCatApplicationPushMailbox()
    private var receiver: (@MainActor @Sendable (MissCatApplicationPush) async -> Void)?

    func install(
        receiver: @escaping @MainActor @Sendable (MissCatApplicationPush) async -> Void
    ) {
        self.receiver = receiver
    }

    func receive(_ push: MissCatApplicationPush) async {
        if let receiver {
            await receiver(push)
        } else {
            _ = await mailbox.enqueue(push)
        }
    }
}

#if DEBUG
enum MissCatProductionRootE2ELaunch {
    static let argument = "--misscat-production-root-e2e"
    static var isRequested: Bool { CommandLine.arguments.contains(argument) }

    static let primary = MissCatApplicationAccount(
        instance: "fixture.example",
        userID: "fixture-cat",
        username: "misscat",
        displayName: "Miss Cat"
    )
    static let secondary = MissCatApplicationAccount(
        instance: "social.example",
        userID: "fixture-cat",
        username: "misscat",
        displayName: "Miss Cat Social"
    )

    static var session: MissCatApplicationSession { session(for: primary.id) }

    static func composeSession(
        for accountID: MissCatApplicationAccountID
    ) throws -> MissCatComposeProductionSession {
        let authorizations = try [primary, secondary].map { account in
            try MissCatComposeProductionSession.Authorization(
                accountID: account.id.rawValue,
                username: account.username,
                instance: account.instance,
                avatarURL: account.avatarURL,
                accessToken: account.id == secondary.id
                    ? "fixture-secondary-compose-token"
                    : "fixture-primary-compose-token"
            )
        }
        return try MissCatComposeProductionSession(
            authorizations: authorizations,
            selectedAccountID: accountID.rawValue,
            visibility: .public
        )
    }

    static func session(for accountID: MissCatApplicationAccountID) -> MissCatApplicationSession {
        let current = accountID == secondary.id ? secondary : primary
        let tabs = ["home", "local", "global"].map {
            MissCatTimelineTab(
                id: "\(current.id.rawValue)|\($0)",
                title: $0.capitalized,
                accessibilityID: $0
            )
        }
        return MissCatApplicationSession(
            currentAccount: current,
            accounts: [primary, secondary],
            timelineTabs: tabs,
            selectedTimelineID: tabs[0].id
        )
    }
}

@MainActor
final class MissCatProductionRootE2EState {
    static let shared = MissCatProductionRootE2EState()

    private(set) var persistedAccountID = MissCatProductionRootE2ELaunch.primary.id
    private(set) var composeSelectionRequests: [String] = []
    private(set) var composeSubmissionAccountID: String?

    func commitRootAccount(_ accountID: MissCatApplicationAccountID) {
        persistedAccountID = accountID
    }

    func recordComposeSelection(_ accountID: String) {
        composeSelectionRequests.append(accountID)
    }

    func recordComposeSubmissionScope(_ accountID: String) {
        composeSubmissionAccountID = accountID
    }

    var lastComposeSelectionRequest: String? { composeSelectionRequests.last }
}

struct MissCatProductionRootE2EComposeTransport: MissCatComposeHTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (Data(#"{"createdNote":{"id":"fixture-created-note"}}"#.utf8), response)
    }
}
#endif
