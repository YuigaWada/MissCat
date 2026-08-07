//
//  MissCatApp.swift
//  MissCat
//
//  SwiftUI application entry point and migration boundary.
//

import Foundation
import SwiftUI
import UIKit

@main
struct MissCatApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var applicationState = ApplicationState()

    var body: some Scene {
        WindowGroup {
            MissCatRootView()
                .environmentObject(applicationState)
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
        cache.changeCurrentUser(userId: currentUser.userId)
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

    var body: some View {
        ZStack {
            #if DEBUG
            if MissCatFrozenLegacyShellReferenceLaunch.isRequested {
                MissCatFrozenLegacyShellReferenceView()
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
               !MissCatFrozenLegacyShellReferenceLaunch.isRequested,
               applicationState.isCompletingAuthentication {
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
            guard !MissCatShellFixtureLaunch.isRequested,
                  !MissCatFrozenLegacyShellReferenceLaunch.isRequested
            else { return }
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
        guard let url = URL(string: "https://\(instance)/api/i") else {
            return result(status: 0, decodeSuccess: false, savedUserIDMatches: false)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["i": apiKey])

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
