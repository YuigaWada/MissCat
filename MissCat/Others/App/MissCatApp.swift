//
//  MissCatApp.swift
//  MissCat
//
//  SwiftUI application entry point and migration boundary.
//

import CryptoKit
import Foundation
import SwiftUI
import UIKit

@main
struct MissCatApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var applicationState = ApplicationState()

    var body: some Scene {
        WindowGroup {
#if DEBUG
            if let probeMode = MissCatSharedKeychainE2EMode.current {
                MissCatSharedKeychainE2EView(mode: probeMode)
            } else {
                MissCatRootView()
                    .environmentObject(applicationState)
            }
#else
            MissCatRootView()
                .environmentObject(applicationState)
#endif
        }
    }
}

/// Owns app-wide navigation while screens are migrated from UIKit to SwiftUI.
///
/// Keeping the route explicit prevents a second source of truth from growing
/// inside individual views. Each legacy destination can be replaced by a
/// SwiftUI case without changing application startup again.
@MainActor
final class ApplicationState: ObservableObject {
    enum Root: Equatable {
        case resolvingSession
        case authentication
        case legacyApplication
    }

    @Published private(set) var root: Root = .resolvingSession
    @Published private(set) var isCompletingAuthentication = false
    @Published private(set) var canRetryAuthentication = false
    @Published private(set) var authenticationFlowGeneration = 0
    @Published var errorMessage: String?

    private let authenticationService = MissCatAuthenticationService()

    func resolveInitialRoute() {
        guard root == .resolvingSession else { return }

#if DEBUG
        if MissCatDiscoveryOrdinaryRouteConfiguration.isEnabled {
            Theme.shared.reset()
            Theme.shared.set()
            root = .legacyApplication
            return
        }
#endif

        let cache = Cache.UserDefaults.shared
        guard let currentUser = cache.getCurrentUser(),
              !currentUser.userId.isEmpty,
              !currentUser.instance.isEmpty,
              let apiKey = currentUser.apiKey,
              !apiKey.isEmpty
        else {
            root = .authentication
            return
        }

        // getCurrentUser() falls back to the first saved account when the
        // persisted current ID is absent or stale. Persist that fallback so
        // the legacy Theme tab resolver sees the same account.
        cache.changeCurrentUser(currentUser)
#if DEBUG
        MissCatAuthenticationProbe.runIfRequested(user: currentUser)
#endif

        Theme.shared.reset()
        Theme.shared.set()
        root = .legacyApplication
    }

    func makeAuthorizationRequest(
        intent: MissCatAuthenticationIntent,
        instance: String
    ) async throws -> URLRequest {
        try await authenticationService.makeAuthorizationRequest(
            intent: intent,
            instance: instance
        )
    }

    func makeLoginRequestAfterSignUp(instance: String) async throws -> URLRequest {
        try await authenticationService.makeLoginRequestAfterSignUp(instance: instance)
    }

    func callbackMatches(_ url: URL) -> Bool {
        authenticationService.callbackMatches(url)
    }

    func completeAuthentication(callbackURL: URL) {
        guard !isCompletingAuthentication else { return }
        canRetryAuthentication = false
        isCompletingAuthentication = true

        Task { @MainActor in
            defer { isCompletingAuthentication = false }
            do {
                _ = try await authenticationService.completeAuthentication(callbackURL: callbackURL)
                root = .legacyApplication
            } catch {
                present(error)
                canRetryAuthentication = true
            }
        }
    }

    func retryAuthentication() {
        guard canRetryAuthentication else { return }
        restartAuthenticationFlow()
    }

    func dismissAuthenticationError() {
        if canRetryAuthentication {
            restartAuthenticationFlow()
        } else {
            errorMessage = nil
        }
    }

    private func restartAuthenticationFlow() {
        // This only rebuilds the local flow after an explicit Retry/Close tap.
        // A new MiAuth session is not created until the user submits login again.
        authenticationService.invalidatePendingAuthentication()
        errorMessage = nil
        canRetryAuthentication = false
        authenticationFlowGeneration += 1
    }

    func present(_ error: Error) {
        canRetryAuthentication = false
        if root == .authentication, !isCompletingAuthentication {
            // This is the exact message shown by StartViewController when app
            // registration or the authentication host could not be reached.
            errorMessage = "インスタンスに接続できません"
        } else {
            errorMessage = error.description
        }
    }
}

struct MissCatRootView: View {
    @EnvironmentObject private var applicationState: ApplicationState

#if DEBUG
    private let acceptanceFixture = MissCatLoginProfileFixtureRoute.parse()
#endif

    @ViewBuilder
    var body: some View {
#if DEBUG
        if MissCatDiscoveryFixtureConfiguration.isEnabled {
            MissCatDiscoveryFixtureRoot()
        } else if MissCatNoteDetailFixtureConfiguration.isEnabled {
            MissCatNoteDetailFixtureRoot()
        } else if let acceptanceFixture {
            MissCatLoginProfileFixtureRoot(route: acceptanceFixture)
        } else {
            productionRoot
        }
#else
        productionRoot
#endif
    }

    private var productionRoot: some View {
        ZStack {
            #if DEBUG
            if MissCatShellFixtureLaunch.isRequested {
                MissCatShellFixtureView()
            } else {
                applicationRoot
            }
            #else
            applicationRoot
            #endif

            #if DEBUG
            if !MissCatShellFixtureLaunch.isRequested, applicationState.isCompletingAuthentication {
                MissCatAuthenticationLoadingOverlay(accessibilityLabel: "認証情報を保存中")
                    .accessibilityIdentifier("authentication.completing")
            }
            #else
            if applicationState.isCompletingAuthentication {
                MissCatAuthenticationLoadingOverlay(accessibilityLabel: "認証情報を保存中")
                    .accessibilityIdentifier("authentication.completing")
            }
            #endif
        }
        .task {
            #if DEBUG
            guard !MissCatShellFixtureLaunch.isRequested else { return }
            #endif
            applicationState.resolveInitialRoute()
        }
        .alert(
            "エラー",
            isPresented: Binding(
                get: { applicationState.errorMessage != nil },
                set: { if !$0 { applicationState.errorMessage = nil } }
            )
        ) {
            if applicationState.canRetryAuthentication {
                Button("再試行") { applicationState.retryAuthentication() }
            }
            Button(
                "閉じる",
                role: applicationState.canRetryAuthentication ? .cancel : .destructive
            ) {
                applicationState.dismissAuthenticationError()
            }
        } message: {
            Text(applicationState.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var applicationRoot: some View {
        switch applicationState.root {
        case .resolvingSession:
            MissCatLaunchView()
        case .authentication:
            MissCatAuthenticationFlowView(
                makeAuthorizationRequest: applicationState.makeAuthorizationRequest,
                makeLoginRequestAfterSignUp: applicationState.makeLoginRequestAfterSignUp,
                callbackMatches: applicationState.callbackMatches,
                onCallback: applicationState.completeAuthentication,
                onFailure: applicationState.present
            )
            .id(applicationState.authenticationFlowGeneration)
        case .legacyApplication:
            LegacyApplicationView()
                .ignoresSafeArea()
        }
    }
}

/// Temporary compatibility boundary for screens that have not yet been
/// rewritten. The storyboard remains a resource so behavior and visual
/// baselines stay available during the screen-by-screen SwiftUI migration.
struct LegacyApplicationView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        guard let root = UIStoryboard(name: "Main", bundle: .main).instantiateInitialViewController() else {
            preconditionFailure("Main.storyboard must provide its legacy root view controller")
        }

        return root
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

#if DEBUG
enum MissCatPersistenceProbeLaunch {
    static var isRequested: Bool {
        MissCatSharedKeychainE2EMode.current != nil
    }
}

private enum MissCatSharedKeychainE2EMode {
    case prepare
    case verifyRelaunch
    case cleanup
    case verifyCleanup

    static var current: Self? {
        if CommandLine.arguments.contains("--misscat-shared-keychain-e2e-verify-cleanup") {
            return .verifyCleanup
        }
        if CommandLine.arguments.contains("--misscat-shared-keychain-e2e-cleanup") {
            return .cleanup
        }
        if CommandLine.arguments.contains("--misscat-shared-keychain-e2e-verify-relaunch") {
            return .verifyRelaunch
        }
        if CommandLine.arguments.contains("--misscat-shared-keychain-e2e") {
            return .prepare
        }
        return nil
    }
}

/// Debug-only host for an XCTest-driven, signed app-to-extension Keychain
/// check. The fixture instance uses the reserved `.invalid` TLD and its value
/// is never sent to the network or returned by the Share process.
private struct MissCatSharedKeychainE2EView: View {
    private enum Phase: Equatable {
        case working
        case ready
        case relaunched
        case cleaned
        case cleanupVerified
        case failed
    }

    private enum Fixture {
        static let appGroup = "group.yuwd.MissCat"
        static let requestKey = "share-credential-proof.requested"
        static let resultKey = "share-credential-proof.available"
        static let accountHashKey = "share-credential-proof.account-hash"
        static let previousAccountKey = "share-credential-proof.previous-account"
        static let credentialHashKey = "share-credential-proof.credential-hash"
        static let deleteCommittedKey = "share-credential-proof.delete-committed"
        static let userID = "misscat-shared-keychain-fixture"
        static let username = "non-live-fixture"
        static let instance = "shared-keychain-probe.invalid"

        static var accountIdentifier: String {
            MissCatAccountIdentity.storageKey(instance: instance, userId: userID)
        }

        static func hash(_ value: String) -> String {
            SHA256.hash(data: Data(value.utf8))
                .map { String(format: "%02x", $0) }
                .joined()
        }
    }

    let mode: MissCatSharedKeychainE2EMode
    @State private var phase: Phase = .working
    @State private var isPresentingShareSheet = false

    var body: some View {
        VStack(spacing: 24) {
            Text("MissCat shared-Keychain E2E")
                .font(.headline)

            switch phase {
            case .working:
                ProgressView()
                    .accessibilityIdentifier("keychain-probe.working")
            case .ready:
                Text("Fixture ready")
                    .accessibilityIdentifier("keychain-probe.ready")
            case .relaunched:
                Text("true")
                    .accessibilityIdentifier("keychain-probe.relaunch-read")
                Button("Open MissCat Share Extension") {
                    isPresentingShareSheet = true
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("keychain-probe.launch-share")
            case .cleaned:
                Text("Fixture cleaned")
                    .accessibilityIdentifier("keychain-probe.cleaned")
            case .cleanupVerified:
                Text("true")
                    .accessibilityIdentifier("keychain-probe.cleanup-verified")
            case .failed:
                Text("Fixture operation failed")
                    .accessibilityIdentifier("keychain-probe.failed")
            }
        }
        .padding(32)
        .task {
            switch mode {
            case .prepare:
                phase = prepareFixture() ? .ready : .failed
            case .verifyRelaunch:
                phase = verifyRelaunchedFixture() ? .relaunched : .failed
            case .cleanup:
                phase = cleanupFixture() ? .cleaned : .failed
            case .verifyCleanup:
                phase = verifyCleanedFixture() ? .cleanupVerified : .failed
            }
        }
        .sheet(isPresented: $isPresentingShareSheet) {
            MissCatSharedKeychainActivityView(
                activityItems: ["MissCat non-live shared-Keychain fixture"]
            )
        }
    }

    private func prepareFixture() -> Bool {
        guard let defaults = Foundation.UserDefaults(suiteName: Fixture.appGroup) else {
            return false
        }

        let cache = Cache.UserDefaults.shared
        let stalePrevious = defaults.string(forKey: Fixture.previousAccountKey)
        let currentAccount = cache.getCurrentUserId()
        let previousAccount = currentAccount == Fixture.accountIdentifier
            ? stalePrevious
            : currentAccount

        if cache.getUser(userId: Fixture.accountIdentifier) != nil,
           !cache.removeUser(userId: Fixture.accountIdentifier)
        {
            return false
        }
        if let previousAccount, previousAccount != Fixture.accountIdentifier {
            defaults.set(previousAccount, forKey: Fixture.previousAccountKey)
        } else {
            defaults.removeObject(forKey: Fixture.previousAccountKey)
        }
        defaults.removeObject(forKey: Fixture.resultKey)
        defaults.removeObject(forKey: Fixture.accountHashKey)
        defaults.removeObject(forKey: Fixture.credentialHashKey)
        defaults.removeObject(forKey: Fixture.deleteCommittedKey)
        defaults.set(false, forKey: Fixture.requestKey)

        let credential = UUID().uuidString + UUID().uuidString
        let fixture = SecureUser(
            userId: Fixture.userID,
            username: Fixture.username,
            instance: Fixture.instance,
            apiKey: credential
        )
        guard let installed = cache.installAuthenticatedUser(fixture),
              installed.accountIdentifier == Fixture.accountIdentifier,
              installed.apiKey == credential,
              cache.getCurrentUserId() == Fixture.accountIdentifier
        else {
            return false
        }

        defaults.set(Fixture.hash(credential), forKey: Fixture.credentialHashKey)
        return defaults.synchronize()
    }

    private func verifyRelaunchedFixture() -> Bool {
        guard let defaults = Foundation.UserDefaults(suiteName: Fixture.appGroup),
              let expectedCredentialHash = defaults.string(forKey: Fixture.credentialHashKey),
              !expectedCredentialHash.isEmpty,
              let fixture = Cache.UserDefaults.shared.getUser(userId: Fixture.accountIdentifier),
              fixture.accountIdentifier == Fixture.accountIdentifier,
              let credential = fixture.apiKey,
              !credential.isEmpty,
              Fixture.hash(credential) == expectedCredentialHash,
              Cache.UserDefaults.shared.getCurrentUserId() == Fixture.accountIdentifier
        else {
            return false
        }

        defaults.removeObject(forKey: Fixture.resultKey)
        defaults.removeObject(forKey: Fixture.accountHashKey)
        defaults.set(true, forKey: Fixture.requestKey)
        return defaults.synchronize()
    }

    private func cleanupFixture() -> Bool {
        guard let defaults = Foundation.UserDefaults(suiteName: Fixture.appGroup) else {
            return false
        }

        let cache = Cache.UserDefaults.shared
        let fixtureExists = cache.getUser(userId: Fixture.accountIdentifier) != nil
        if fixtureExists, !cache.removeUser(userId: Fixture.accountIdentifier) {
            return false
        }

        if let previousAccount = defaults.string(forKey: Fixture.previousAccountKey),
           previousAccount != Fixture.accountIdentifier
        {
            _ = cache.changeCurrentUser(userId: previousAccount)
        }

        defaults.removeObject(forKey: Fixture.requestKey)
        defaults.removeObject(forKey: Fixture.resultKey)
        defaults.removeObject(forKey: Fixture.accountHashKey)
        defaults.removeObject(forKey: Fixture.credentialHashKey)
        defaults.set(true, forKey: Fixture.deleteCommittedKey)
        guard defaults.synchronize() else { return false }
        return cache.getUser(userId: Fixture.accountIdentifier) == nil
    }

    private func verifyCleanedFixture() -> Bool {
        guard let defaults = Foundation.UserDefaults(suiteName: Fixture.appGroup),
              defaults.bool(forKey: Fixture.deleteCommittedKey),
              Cache.UserDefaults.shared.getUser(userId: Fixture.accountIdentifier) == nil,
              let credentialAvailable = try? Cache.UserDefaults.shared
                .hasPersistedCredentialForVerification(accountIdentifier: Fixture.accountIdentifier),
              !credentialAvailable,
              Cache.UserDefaults.shared.getCurrentUserId() != Fixture.accountIdentifier
        else {
            return false
        }

        defaults.removeObject(forKey: Fixture.requestKey)
        defaults.removeObject(forKey: Fixture.resultKey)
        defaults.removeObject(forKey: Fixture.accountHashKey)
        defaults.removeObject(forKey: Fixture.previousAccountKey)
        defaults.removeObject(forKey: Fixture.credentialHashKey)
        defaults.removeObject(forKey: Fixture.deleteCommittedKey)
        return defaults.synchronize()
    }
}

private struct MissCatSharedKeychainActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

#if DEBUG
private enum MissCatAuthenticationProbe {
    private static let launchArgument = "--auth-api-probe"
    private static let appGroup = "group.yuwd.MissCat"
    private static let resultKey = "auth-api-probe-result"

    private struct APIResponse: Decodable {
        let id: String
    }

    static func runIfRequested(user: SecureUser) {
        guard CommandLine.arguments.contains(launchArgument),
              let apiKey = user.apiKey,
              !apiKey.isEmpty,
              let defaults = UserDefaults(suiteName: appGroup)
        else { return }

        defaults.removeObject(forKey: resultKey)
        let savedUserID = user.userId
        let instance = user.instance.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        Task {
            let result = await requestIdentity(
                instance: instance,
                apiKey: apiKey,
                savedUserID: savedUserID
            )
            defaults.set(result, forKey: resultKey)
            defaults.synchronize()
        }
    }

    private static func requestIdentity(
        instance: String,
        apiKey: String,
        savedUserID: String
    ) async -> [String: Any] {
        let request: URLRequest
        do {
            request = try MissCatAuthenticatedIdentityRequestBuilder.request(
                instance: instance,
                accessToken: apiKey
            )
        } catch {
            return result(status: 0, decodeSuccess: false, savedUserIDMatches: false)
        }

        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }

        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let responseID = try? JSONDecoder().decode(APIResponse.self, from: data).id
            return result(
                status: status,
                decodeSuccess: responseID != nil,
                savedUserIDMatches: responseID == savedUserID
            )
        } catch {
            return result(status: 0, decodeSuccess: false, savedUserIDMatches: false)
        }
    }

    private static func result(
        status: Int,
        decodeSuccess: Bool,
        savedUserIDMatches: Bool
    ) -> [String: Any] {
        [
            "status": status,
            "decodeSuccess": decodeSuccess,
            "savedUserIDMatches": savedUserIDMatches,
            "completedAt": Date().timeIntervalSince1970
        ]
    }
}
#endif
