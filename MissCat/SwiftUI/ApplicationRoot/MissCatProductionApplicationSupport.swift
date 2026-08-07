import Foundation

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
