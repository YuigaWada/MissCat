import Foundation
import SwiftUI

/// Connects the legacy welcome → terms → authorization sequence without coupling the
/// presentation layer to a specific Misskey client implementation.
public struct MissCatAuthenticationFlowView: View {
    public typealias AuthorizationRequestProvider = @MainActor (
        MissCatAuthenticationIntent,
        String
    ) async throws -> URLRequest

    private enum Destination: Hashable {
        case terms
        case browser
    }

    @State private var instance: String
    @State private var path: [Destination] = []
    @State private var pendingIntent: MissCatAuthenticationIntent = .logIn
    @State private var authorizationRequest: URLRequest?
    @State private var isPreparingAuthorization = false
    @State private var showsInstanceEditor = false

    private let makeAuthorizationRequest: AuthorizationRequestProvider
    private let callbackMatches: (URL) -> Bool
    private let onCallback: (URL) -> Void
    private let onFailure: (Error) -> Void

    public init(
        initialInstance: String = "misskey.io",
        makeAuthorizationRequest: @escaping AuthorizationRequestProvider,
        callbackMatches: @escaping (URL) -> Bool,
        onCallback: @escaping (URL) -> Void,
        onFailure: @escaping (Error) -> Void
    ) {
        _instance = State(initialValue: MissCatInstanceEditorView.normalize(initialInstance))
        self.makeAuthorizationRequest = makeAuthorizationRequest
        self.callbackMatches = callbackMatches
        self.onCallback = onCallback
        self.onFailure = onFailure
    }

    public var body: some View {
        NavigationStack(path: $path) {
            MissCatWelcomeView(
                instance: instance,
                onSignUp: { begin(.signUp) },
                onLogIn: { begin(.logIn) },
                onChangeInstance: { showsInstanceEditor = true }
            )
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .terms:
                    MissCatTermsView(onAgree: prepareAuthorization)
                case .browser:
                    if let authorizationRequest {
                        MissCatAuthenticationBrowserView(
                            request: authorizationRequest,
                            callbackMatches: callbackMatches,
                            onCallback: onCallback
                        )
                    }
                }
            }
        }
        .sheet(isPresented: $showsInstanceEditor) {
            MissCatInstanceEditorView(
                instance: $instance,
                onCancel: { showsInstanceEditor = false },
                onApply: { _ in showsInstanceEditor = false }
            )
        }
        .overlay {
            if isPreparingAuthorization {
                ZStack {
                    Color.black.opacity(0.18).ignoresSafeArea()
                    ProgressView()
                        .controlSize(.large)
                        .padding(22)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel("認証の準備中")
                        .accessibilityIdentifier("authentication.loading")
                }
            }
        }
        .accessibilityIdentifier("authentication.flow")
    }

    private func begin(_ intent: MissCatAuthenticationIntent) {
        pendingIntent = intent
        path.append(.terms)
    }

    private func prepareAuthorization() {
        guard !isPreparingAuthorization else { return }
        isPreparingAuthorization = true

        Task { @MainActor in
            defer { isPreparingAuthorization = false }
            do {
                authorizationRequest = try await makeAuthorizationRequest(pendingIntent, instance)
                path.append(.browser)
            } catch {
                onFailure(error)
            }
        }
    }
}
