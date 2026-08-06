//
//  MissCatApp.swift
//  MissCat
//
//  SwiftUI application entry point and migration boundary.
//

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
    @Published var errorMessage: String?

    private let authenticationService = MissCatAuthenticationService()
    private var callbackURLToRetry: URL?

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
        callbackURLToRetry = callbackURL
        canRetryAuthentication = false
        isCompletingAuthentication = true

        Task { @MainActor in
            defer { isCompletingAuthentication = false }
            do {
                _ = try await authenticationService.completeAuthentication(callbackURL: callbackURL)
                callbackURLToRetry = nil
                root = .legacyApplication
            } catch {
                present(error)
                canRetryAuthentication = true
            }
        }
    }

    func retryAuthentication() {
        guard let callbackURLToRetry else { return }
        errorMessage = nil
        completeAuthentication(callbackURL: callbackURLToRetry)
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
            case .legacyApplication:
                LegacyApplicationView()
                    .ignoresSafeArea()
            }

            if applicationState.isCompletingAuthentication {
                MissCatAuthenticationLoadingOverlay(accessibilityLabel: "認証情報を保存中")
                    .accessibilityIdentifier("authentication.completing")
            }
        }
        .task { applicationState.resolveInitialRoute() }
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
                applicationState.errorMessage = nil
            }
        } message: {
            Text(applicationState.errorMessage ?? "")
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
