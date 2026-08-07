//
//  MissCatApp.swift
//  MissCat
//
//  SwiftUI application entry point and migration boundary.
//

import CryptoKit
import Foundation
import SwiftUI

@main
struct MissCatApp: App {
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

/// Owns authentication and the production SwiftUI application lifecycle.
/// The application root store remains the single source of truth for account,
/// navigation, and modal state.
@MainActor
final class ApplicationState: ObservableObject {
    @Published private(set) var isCompletingAuthentication = false
    @Published private(set) var canRetryAuthentication = false
    @Published private(set) var authenticationFlowGeneration = 0
    @Published var errorMessage: String?

    private let authenticationService = MissCatAuthenticationService()
    let applicationRootStore: MissCatApplicationRootStore

    init() {
        applicationRootStore = MissCatApplicationRootStore(
            sessionProvider: MissCatProductionSessionAdapter()
        )
    }

    func resolveInitialRoute() async {
        guard case .launching = applicationRootStore.phase else { return }
#if DEBUG
        let cache = Cache.UserDefaults.shared
        let restoredUser = MissCatAuthenticationBackupBridge.restoreIfRequested(cache: cache)
#endif
        await applicationRootStore.restore()
#if DEBUG
        if let currentUser = restoredUser ?? cache.getCurrentUser() {
            MissCatAuthenticationBackupBridge.preflightIfRequested(user: currentUser)
            MissCatAuthenticationBackupBridge.exportIfRequested(user: currentUser)
            MissCatAuthenticationBackupBridge.clearIfRequested(cache: cache, user: currentUser)
            MissCatAuthenticationProbe.runIfRequested(user: currentUser)
        }
#endif
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
                await applicationRootStore.restore()
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
        if applicationRootStore.phase.authenticatedSession == nil, !isCompletingAuthentication {
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
            if MissCatAccountsSettingsAcceptanceLaunch.isRequested {
                MissCatAccountsSettingsAcceptanceView()
            } else if MissCatShellFixtureLaunch.isRequested {
                MissCatShellFixtureView()
            } else {
                applicationRoot
            }
            #else
            applicationRoot
            #endif

            #if DEBUG
            if !MissCatShellFixtureLaunch.isRequested,
               !MissCatAccountsSettingsAcceptanceLaunch.isRequested,
               applicationState.isCompletingAuthentication
            {
                MissCatAuthenticationLoadingOverlay(accessibilityLabel: "認証情報を保存中")
                    .accessibilityIdentifier("authentication.completing")
            }
            #else
            if applicationState.isCompletingAuthentication {
                MissCatAuthenticationLoadingOverlay(accessibilityLabel: "認証情報を保存中")
                    .accessibilityIdentifier("authentication.completing")
            }
            #endif

            #if DEBUG
            if MissCatProfileOrdinaryRouteConfiguration.isEnabled {
                MissCatProfileOrdinaryAccessibilityMarker(
                    state: MissCatProfileOrdinaryRouteConfiguration.actionState
                )
            }
            #endif
        }
        .task {
            #if DEBUG
            guard !MissCatShellFixtureLaunch.isRequested,
                  !MissCatAccountsSettingsAcceptanceLaunch.isRequested
            else { return }
            #endif
            await applicationState.resolveInitialRoute()
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
        MissCatApplicationPhaseView(applicationState: applicationState)
    }
}

private struct MissCatApplicationPhaseView: View {
    @ObservedObject var applicationState: ApplicationState
    @Bindable private var rootStore: MissCatApplicationRootStore

    init(applicationState: ApplicationState) {
        self.applicationState = applicationState
        rootStore = applicationState.applicationRootStore
    }

    @ViewBuilder
    var body: some View {
        switch rootStore.phase {
        case .launching:
            MissCatLaunchView()
        case .signedOut, .failed:
            MissCatAuthenticationFlowView(
                makeAuthorizationRequest: applicationState.makeAuthorizationRequest,
                makeLoginRequestAfterSignUp: applicationState.makeLoginRequestAfterSignUp,
                callbackMatches: applicationState.callbackMatches,
                onCallback: applicationState.completeAuthentication,
                onFailure: applicationState.present
            )
            .id(applicationState.authenticationFlowGeneration)
        case let .authenticated(session),
             let .switching(current: session, target: _),
             let .signingOut(current: session):
            MissCatProductionApplicationRootView(
                rootStore: applicationState.applicationRootStore,
                session: session
            )
            .id(session.currentAccount.id)
        }
    }
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
                ShareLink(item: "MissCat non-live shared-Keychain fixture") {
                    Text("Open MissCat Share Extension")
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

#endif

#if DEBUG
enum MissCatAuthenticationBackupCodec {
    struct Payload: Codable {
        let version: Int
        let userID: String
        let username: String
        let instance: String
        let accessToken: String
        let createdAt: Date
    }

    static func seal(user: SecureUser, keyData: Data, createdAt: Date = Date()) throws -> Data {
        guard keyData.count == 32 else { throw CodecError.invalidKey }
        guard let token = user.apiKey, !token.isEmpty else { throw CodecError.invalidPayload }
        let payload = Payload(
            version: 1,
            userID: user.userId,
            username: user.username,
            instance: user.normalizedInstance,
            accessToken: token,
            createdAt: createdAt
        )
        return try seal(payload: payload, keyData: keyData)
    }

    static func seal(payload: Payload, keyData: Data) throws -> Data {
        guard keyData.count == 32 else { throw CodecError.invalidKey }
        let plaintext = try JSONEncoder().encode(payload)
        let sealed = try AES.GCM.seal(plaintext, using: SymmetricKey(data: keyData))
        guard let combined = sealed.combined else { throw CodecError.couldNotSeal }
        return combined
    }

    static func open(encrypted: Data, keyData: Data) throws -> SecureUser {
        guard keyData.count == 32 else { throw CodecError.invalidKey }
        let sealed = try AES.GCM.SealedBox(combined: encrypted)
        let plaintext = try AES.GCM.open(sealed, using: SymmetricKey(data: keyData))
        let payload = try JSONDecoder().decode(Payload.self, from: plaintext)
        guard payload.version == 1,
              !payload.userID.isEmpty,
              !payload.username.isEmpty,
              !payload.instance.isEmpty,
              !payload.accessToken.isEmpty
        else { throw CodecError.invalidPayload }
        return SecureUser(
            userId: payload.userID,
            username: payload.username,
            instance: payload.instance,
            apiKey: payload.accessToken
        )
    }

    enum CodecError: Error {
        case invalidKey
        case couldNotSeal
        case invalidPayload
    }
}

struct MissCatAuthenticationBackupClearPolicy {
    struct Receipt: Codable {
        let accountIdentifier: String
        let backupDigest: String
        let completedAt: Date
    }

    static func permitsClear(
        receipt: Receipt?,
        user: SecureUser,
        now: Date = Date()
    ) -> Bool {
        guard let receipt,
              receipt.accountIdentifier == user.accountIdentifier,
              receipt.backupDigest.count == 64,
              now.timeIntervalSince(receipt.completedAt) >= 0,
              now.timeIntervalSince(receipt.completedAt) <= 300
        else { return false }
        return true
    }
}

private enum MissCatAuthenticationBackupBridge {
    private static let appGroup = "group.yuwd.MissCat"
    private static let exportArgument = "--auth-backup-export"
    private static let restoreArgument = "--auth-backup-restore"
    private static let clearArgument = "--auth-backup-clear"
    private static let preflightArgument = "--auth-backup-preflight"
    private static let nonceArgument = "--auth-backup-nonce"
    private static let keyFilename = ".misscat-auth-backup-key"
    private static let inputFilename = ".misscat-auth-backup-input.enc"
    private static let outputFilename = ".misscat-auth-backup-output.enc"
    private static let resultKey = "auth-backup-result"
    private static let preflightReceiptKey = "auth-backup-preflight-receipt"

    static func preflightIfRequested(user: SecureUser) {
        guard CommandLine.arguments.contains(preflightArgument) else { return }
        guard let nonce = requestNonce(),
              let container = containerURL(),
              let defaults = UserDefaults(suiteName: appGroup)
        else {
            record(operation: "preflight", success: false, nonce: requestNonce())
            return
        }

        let keyURL = container.appendingPathComponent(keyFilename)
        let inputURL = container.appendingPathComponent(inputFilename)
        defer {
            try? FileManager.default.removeItem(at: keyURL)
            try? FileManager.default.removeItem(at: inputURL)
        }

        do {
            let keyData = try Data(contentsOf: keyURL)
            let encrypted = try Data(contentsOf: inputURL)
            let candidate = try MissCatAuthenticationBackupCodec.open(
                encrypted: encrypted,
                keyData: keyData
            )
            guard candidate.accountIdentifier == user.accountIdentifier,
                  candidate.apiKey == user.apiKey
            else { throw BackupError.identityMismatch }
            let receipt = MissCatAuthenticationBackupClearPolicy.Receipt(
                accountIdentifier: candidate.accountIdentifier,
                backupDigest: SHA256.hash(data: encrypted).map { String(format: "%02x", $0) }.joined(),
                completedAt: Date()
            )
            defaults.set(try JSONEncoder().encode(receipt), forKey: preflightReceiptKey)
            guard defaults.synchronize() else { throw BackupError.couldNotPersist }
            record(
                operation: "preflight",
                success: true,
                nonce: nonce,
                instance: candidate.normalizedInstance
            )
        } catch {
            defaults.removeObject(forKey: preflightReceiptKey)
            defaults.synchronize()
            record(operation: "preflight", success: false, nonce: nonce)
        }
    }

    static func exportIfRequested(user: SecureUser) {
        guard CommandLine.arguments.contains(exportArgument) else { return }
        guard let nonce = requestNonce(),
              let container = containerURL(),
              let defaults = UserDefaults(suiteName: appGroup),
              user.apiKey?.isEmpty == false
        else {
            record(operation: "export", success: false, nonce: requestNonce())
            return
        }

        let keyURL = container.appendingPathComponent(keyFilename)
        let outputURL = container.appendingPathComponent(outputFilename)
        defer { try? FileManager.default.removeItem(at: keyURL) }

        do {
            let keyData = try Data(contentsOf: keyURL)
            let combined = try MissCatAuthenticationBackupCodec.seal(
                user: user,
                keyData: keyData
            )
            try combined.write(to: outputURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: outputURL.path
            )
            defaults.removeObject(forKey: resultKey)
            record(
                operation: "export",
                success: true,
                nonce: nonce,
                instance: user.normalizedInstance
            )
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            record(operation: "export", success: false, nonce: nonce)
        }
    }

    static func restoreIfRequested(cache: Cache.UserDefaults) -> SecureUser? {
        guard CommandLine.arguments.contains(restoreArgument) else { return nil }
        guard let nonce = requestNonce(),
              let container = containerURL()
        else {
            record(operation: "restore", success: false, nonce: requestNonce())
            return nil
        }

        let keyURL = container.appendingPathComponent(keyFilename)
        let inputURL = container.appendingPathComponent(inputFilename)
        defer {
            try? FileManager.default.removeItem(at: keyURL)
            try? FileManager.default.removeItem(at: inputURL)
        }

        do {
            let keyData = try Data(contentsOf: keyURL)
            let encrypted = try Data(contentsOf: inputURL)
            let candidate = try MissCatAuthenticationBackupCodec.open(
                encrypted: encrypted,
                keyData: keyData
            )
            guard let restored = cache.installAuthenticatedUser(candidate),
                  restored.accountIdentifier == candidate.accountIdentifier,
                  restored.apiKey == candidate.apiKey
            else { throw BackupError.couldNotPersist }

            record(
                operation: "restore",
                success: true,
                nonce: nonce,
                instance: restored.normalizedInstance
            )
            return restored
        } catch {
            record(operation: "restore", success: false, nonce: nonce)
            return nil
        }
    }

    static func clearIfRequested(cache: Cache.UserDefaults, user: SecureUser) {
        guard CommandLine.arguments.contains(clearArgument) else { return }
        guard let nonce = requestNonce(),
              let defaults = UserDefaults(suiteName: appGroup),
              let receiptData = defaults.data(forKey: preflightReceiptKey),
              let receipt = try? JSONDecoder().decode(
                  MissCatAuthenticationBackupClearPolicy.Receipt.self,
                  from: receiptData
              ),
              MissCatAuthenticationBackupClearPolicy.permitsClear(
                  receipt: receipt,
                  user: user
              )
        else {
            record(operation: "clear", success: false, nonce: requestNonce())
            return
        }
        defaults.removeObject(forKey: preflightReceiptKey)
        guard defaults.synchronize() else {
            record(operation: "clear", success: false, nonce: nonce)
            return
        }
        let accountIdentifier = user.accountIdentifier
        let removed = cache.removeUser(userId: accountIdentifier)
        let credentialStillExists = (try? cache.hasPersistedCredentialForVerification(
            accountIdentifier: accountIdentifier
        )) ?? true
        record(
            operation: "clear",
            success: removed && !credentialStillExists && cache.getUser(userId: accountIdentifier) == nil,
            nonce: nonce,
            instance: user.normalizedInstance
        )
    }

    private static func containerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    private static func requestNonce() -> String? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: nonceArgument),
              arguments.indices.contains(index + 1)
        else { return nil }
        let value = arguments[index + 1]
        guard UUID(uuidString: value) != nil else { return nil }
        return value.lowercased()
    }

    private static func record(
        operation: String,
        success: Bool,
        nonce: String?,
        instance: String? = nil
    ) {
        guard let defaults = UserDefaults(suiteName: appGroup) else { return }
        var value: [String: Any] = [
            "operation": operation,
            "success": success,
            "nonce": nonce ?? "invalid",
            "completedAt": Date().timeIntervalSince1970
        ]
        if let instance { value["instance"] = instance }
        defaults.set(value, forKey: resultKey)
        defaults.synchronize()
    }

    private enum BackupError: Error {
        case couldNotPersist
        case identityMismatch
    }
}

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
            async let identityResult = requestIdentity(
                instance: instance,
                apiKey: apiKey,
                savedUserID: savedUserID
            )
            async let emojiResult = requestCustomEmojis(instance: instance, apiKey: apiKey)
            async let timelineResult = requestTimeline(
                instance: instance,
                apiKey: apiKey,
                userID: user.userId,
                username: user.username
            )
            var result = await identityResult
            result.merge(await emojiResult) { _, latest in latest }
            result.merge(await timelineResult) { _, latest in latest }
            defaults.set(result, forKey: resultKey)
            defaults.synchronize()
        }
    }

    private static func requestCustomEmojis(
        instance: String,
        apiKey: String
    ) async -> [String: Any] {
        do {
            let client = try MissCatNativeAPIClient(
                instance: instance,
                accessToken: apiKey
            )
            let emojis = try await client.customEmojis()
            return [
                "customEmojisDecodeSuccess": true,
                "customEmojiCount": emojis.count,
            ]
        } catch {
            return [
                "customEmojisDecodeSuccess": false,
                "customEmojiCount": 0,
            ]
        }
    }

    private static func requestTimeline(
        instance: String,
        apiKey: String,
        userID: String,
        username: String
    ) async -> [String: Any] {
        let session = MissCatFeedSession(
            accountID: userID,
            username: username,
            instance: instance,
            apiKey: apiKey
        )
        let configuration = URLSessionConfiguration.ephemeral
        let urlSession = URLSession(configuration: configuration)
        defer { urlSession.invalidateAndCancel() }

        do {
            let repository = MissCatMisskeyFeedRepository(
                session: session,
                urlSession: urlSession
            )
            let page = try await repository.fetchPage(source: .home, cursor: nil, limit: 1)
            return [
                "timelineDecodeSuccess": true,
                "timelineNoteCount": page.notes.count,
            ]
        } catch {
            return [
                "timelineDecodeSuccess": false,
                "timelineNoteCount": 0,
            ]
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
