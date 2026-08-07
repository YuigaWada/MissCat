import Foundation
import SwiftUI

/// Connects the legacy welcome → terms → authorization sequence without coupling the
/// presentation layer to a specific Misskey client implementation.
public struct MissCatAuthenticationFlowView: View {
    public typealias AuthorizationRequestProvider = @MainActor (
        MissCatAuthenticationIntent,
        String
    ) async throws -> URLRequest
    public typealias LoginRequestProvider = @MainActor (String) async throws -> URLRequest

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
    private let makeLoginRequestAfterSignUp: LoginRequestProvider
    private let callbackMatches: (URL) -> Bool
    private let onCallback: (URL) -> Void
    private let onFailure: (Error) -> Void

    public init(
        initialInstance: String = "misskey.io",
        makeAuthorizationRequest: @escaping AuthorizationRequestProvider,
        makeLoginRequestAfterSignUp: @escaping LoginRequestProvider,
        callbackMatches: @escaping (URL) -> Bool,
        onCallback: @escaping (URL) -> Void,
        onFailure: @escaping (Error) -> Void
    ) {
        _instance = State(initialValue: MissCatInstanceEditorView.normalize(initialInstance))
        self.makeAuthorizationRequest = makeAuthorizationRequest
        self.makeLoginRequestAfterSignUp = makeLoginRequestAfterSignUp
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
                            onCallback: onCallback,
                            makeLoginRequestAfterSignUp: signUpLoginRequestProvider,
                            onFailure: onFailure
                        )
                    }
                }
            }
        }
        .background {
            MissCatInstanceEditorView(
                isPresented: $showsInstanceEditor,
                instance: $instance,
                onCancel: { showsInstanceEditor = false },
                onApply: { _ in }
            )
        }
        .overlay {
            if isPreparingAuthorization {
                MissCatAuthenticationLoadingOverlay(accessibilityLabel: "認証の準備中")
                    .accessibilityIdentifier("authentication.loading")
            }
        }
        .overlay(alignment: .topLeading) {
            MissCatAuthenticationMarker(identifier: "authentication.flow")
        }
    }

    private var signUpLoginRequestProvider: (@MainActor () async throws -> URLRequest)? {
        guard pendingIntent == .signUp else { return nil }
        return { try await makeLoginRequestAfterSignUp(instance) }
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

struct MissCatAuthenticationMarker: View {
    let identifier: String
    var value = "true"

    var body: some View {
        Text("marker")
            .font(.system(size: 1))
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .accessibilityLabel(identifier)
            .accessibilityValue(value)
            .accessibilityIdentifier(identifier)
    }
}
