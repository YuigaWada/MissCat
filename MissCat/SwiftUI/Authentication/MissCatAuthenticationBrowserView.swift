import AuthenticationServices
import Foundation
import SwiftUI

public enum MissCatAuthenticationIntent: String, Hashable, Sendable {
    case signUp
    case logIn
}

/// Controls whether the system authentication browser reuses its signed-in
/// session. The explicit account-switch case is isolated without deleting any
/// browser or application data.
public enum MissCatAuthenticationWebsiteDataPolicy: Hashable, Sendable {
    case preserveSession
    case clearForExplicitAccountSwitch
}

enum MissCatAuthenticationBrowserSessionKind: Equatable, Sendable {
    case shared
    case ephemeral
}

enum MissCatAuthenticationBrowserPolicy {
    static let callbackScheme = "misscat"

    static func sessionKind(
        for websiteDataPolicy: MissCatAuthenticationWebsiteDataPolicy
    ) -> MissCatAuthenticationBrowserSessionKind {
        switch websiteDataPolicy {
        case .preserveSession:
            .shared
        case .clearForExplicitAccountSwitch:
            .ephemeral
        }
    }

    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        let error = error as NSError
        return error.domain == ASWebAuthenticationSessionErrorDomain
            && error.code == ASWebAuthenticationSessionError.Code.canceledLogin.rawValue
    }
}

enum MissCatAuthenticationBrowserError: LocalizedError {
    case missingAuthorizationURL
    case invalidCallback

    var errorDescription: String? {
        switch self {
        case .missingAuthorizationURL:
            "認証ページを開けませんでした"
        case .invalidCallback:
            "認証結果を確認できませんでした"
        }
    }
}

/// A SwiftUI-owned authentication surface. Login is delegated to the system
/// authentication browser so the app never reads credentials or web storage.
public struct MissCatAuthenticationBrowserView: View {
    typealias AuthenticationSessionRunner = @MainActor (
        URL,
        String,
        MissCatAuthenticationBrowserSessionKind
    ) async throws -> URL
    typealias RegistrationURLHandler = @MainActor (URL) -> Void

    private enum Stage: String {
        case registration
        case authentication
    }

    public let request: URLRequest
    public let callbackMatches: (URL) -> Bool
    public let onCallback: (URL) -> Void
    public let makeLoginRequestAfterSignUp: (@MainActor () async throws -> URLRequest)?
    public let onFailure: (Error) -> Void
    public let websiteDataPolicy: MissCatAuthenticationWebsiteDataPolicy

    @Environment(\.openURL) private var openURL
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    @State private var activeRequest: URLRequest
    @State private var stage: Stage
    @State private var attempt = 0
    @State private var isAuthenticating = false
    @State private var isPreparingLogin = false
    @State private var hasOpenedRegistration = false
    @State private var hasReportedCallback = false
    @State private var authenticationWasCancelled = false
    @State private var authenticationFailureMessage: String?

    private let authenticationSessionRunner: AuthenticationSessionRunner?
    private let registrationURLHandler: RegistrationURLHandler?

    public init(
        request: URLRequest,
        callbackMatches: @escaping (URL) -> Bool,
        onCallback: @escaping (URL) -> Void,
        makeLoginRequestAfterSignUp: (@MainActor () async throws -> URLRequest)? = nil,
        websiteDataPolicy: MissCatAuthenticationWebsiteDataPolicy = .preserveSession,
        onFailure: @escaping (Error) -> Void = { _ in }
    ) {
        self.init(
            request: request,
            callbackMatches: callbackMatches,
            onCallback: onCallback,
            makeLoginRequestAfterSignUp: makeLoginRequestAfterSignUp,
            websiteDataPolicy: websiteDataPolicy,
            authenticationSessionRunner: nil,
            registrationURLHandler: nil,
            onFailure: onFailure
        )
    }

    init(
        request: URLRequest,
        callbackMatches: @escaping (URL) -> Bool,
        onCallback: @escaping (URL) -> Void,
        makeLoginRequestAfterSignUp: (@MainActor () async throws -> URLRequest)? = nil,
        websiteDataPolicy: MissCatAuthenticationWebsiteDataPolicy = .preserveSession,
        authenticationSessionRunner: AuthenticationSessionRunner?,
        registrationURLHandler: RegistrationURLHandler?,
        onFailure: @escaping (Error) -> Void = { _ in }
    ) {
        self.request = request
        self.callbackMatches = callbackMatches
        self.onCallback = onCallback
        self.makeLoginRequestAfterSignUp = makeLoginRequestAfterSignUp
        self.websiteDataPolicy = websiteDataPolicy
        self.authenticationSessionRunner = authenticationSessionRunner
        self.registrationURLHandler = registrationURLHandler
        self.onFailure = onFailure
        _activeRequest = State(initialValue: request)
        _stage = State(
            initialValue: makeLoginRequestAfterSignUp == nil ? .authentication : .registration
        )
    }

    public var body: some View {
        ZStack {
            Color(hex: MissCatLegacyColorHex.authenticationBrowserBackground)
                .ignoresSafeArea()

            switch stage {
            case .registration:
                registrationInstructions
            case .authentication:
                authenticationStatus
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .missCatLegacyOnboardingNavigationBar()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: retryCurrentStage) {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isAuthenticating || isPreparingLogin)
                .accessibilityLabel("再読み込み")
                .accessibilityIdentifier("authentication.reload")
            }
        }
        .accessibilityIdentifier("authentication.browser")
        .overlay(alignment: .topLeading) {
            MissCatAuthenticationMarker(identifier: visualReadyIdentifier)
        }
        .onAppear(perform: openRegistrationIfNeeded)
        .task(id: authenticationTaskID) {
            await authenticateIfNeeded()
        }
    }

    private var registrationInstructions: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 42, weight: .regular))
            Text("アカウント登録")
                .font(.title3.weight(.semibold))
            Text("ブラウザで登録を完了してから、MissCatに戻ってログインへ進んでください。")
                .font(.body)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: continueAfterSignUp) {
                HStack(spacing: 8) {
                    if isPreparingLogin {
                        ProgressView().tint(.white)
                    }
                    Text("登録後にログインへ進む")
                    Image(systemName: "arrow.right")
                }
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .frame(minHeight: 48)
                .background(Color(hex: "86B900"), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isPreparingLogin)
            .accessibilityIdentifier("authentication.signup.continue")
        }
        .foregroundStyle(.white)
        .padding(28)
        .frame(maxWidth: 420)
    }

    @ViewBuilder
    private var authenticationStatus: some View {
        VStack(spacing: 18) {
            if hasReportedCallback {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 40, weight: .regular))
                Text("認証結果を確認しています")
                    .font(.headline)
            } else if let authenticationFailureMessage {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 40, weight: .regular))
                Text(authenticationFailureMessage)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Button("再試行", action: retryAuthentication)
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: "86B900"))
                    .accessibilityIdentifier("authentication.retry")
            } else if authenticationWasCancelled {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 40, weight: .regular))
                Text("認証がキャンセルされました")
                    .font(.headline)
                Button("再試行", action: retryAuthentication)
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: "86B900"))
                    .accessibilityIdentifier("authentication.retry")
            } else {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                Text("認証ページを開いています")
                    .font(.headline)
            }
        }
        .foregroundStyle(.white)
        .padding(28)
    }

    private var authenticationTaskID: String {
        "\(stage.rawValue):\(attempt):\(activeRequest.url?.absoluteString ?? "missing")"
    }

    private var visualReadyIdentifier: String {
        if hasReportedCallback {
            return "visual-ready.login-auth-browser.callback"
        }
        if authenticationFailureMessage != nil || authenticationWasCancelled {
            return "visual-ready.login-auth-browser.error"
        }
        return "visual-ready.login-auth-browser.loading"
    }

    private func openRegistrationIfNeeded() {
        guard stage == .registration, !hasOpenedRegistration else { return }
        hasOpenedRegistration = true
        openRegistration()
    }

    private func openRegistration() {
        guard let url = activeRequest.url else {
            onFailure(MissCatAuthenticationBrowserError.missingAuthorizationURL)
            return
        }

        if let registrationURLHandler {
            registrationURLHandler(url)
        } else {
            openURL(url)
        }
    }

    private func continueAfterSignUp() {
        guard let makeLoginRequestAfterSignUp, !isPreparingLogin else { return }
        isPreparingLogin = true

        Task { @MainActor in
            defer { isPreparingLogin = false }
            do {
                activeRequest = try await makeLoginRequestAfterSignUp()
                authenticationWasCancelled = false
                stage = .authentication
            } catch {
                onFailure(error)
            }
        }
    }

    private func retryCurrentStage() {
        switch stage {
        case .registration:
            openRegistration()
        case .authentication:
            retryAuthentication()
        }
    }

    private func retryAuthentication() {
        authenticationWasCancelled = false
        authenticationFailureMessage = nil
        attempt += 1
    }

    @MainActor
    private func authenticateIfNeeded() async {
        guard stage == .authentication,
              !isAuthenticating,
              !hasReportedCallback,
              !authenticationWasCancelled
        else { return }
        guard let url = activeRequest.url else {
            onFailure(MissCatAuthenticationBrowserError.missingAuthorizationURL)
            return
        }

        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            let callbackURL = try await runAuthenticationSession(using: url)
            guard callbackMatches(callbackURL) else {
                let error = MissCatAuthenticationBrowserError.invalidCallback
                authenticationFailureMessage = error.localizedDescription
                onFailure(error)
                return
            }
            guard !hasReportedCallback else { return }
            hasReportedCallback = true
            onCallback(callbackURL)
        } catch {
            if MissCatAuthenticationBrowserPolicy.isCancellation(error) {
                authenticationWasCancelled = true
            } else {
                authenticationFailureMessage = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
                onFailure(error)
            }
        }
    }

    @MainActor
    private func runAuthenticationSession(using url: URL) async throws -> URL {
        let kind = MissCatAuthenticationBrowserPolicy.sessionKind(for: websiteDataPolicy)
        if let authenticationSessionRunner {
            return try await authenticationSessionRunner(
                url,
                MissCatAuthenticationBrowserPolicy.callbackScheme,
                kind
            )
        }

        let browserSession: WebAuthenticationSession.BrowserSession = switch kind {
        case .shared: .shared
        case .ephemeral: .ephemeral
        }
        return try await webAuthenticationSession.authenticate(using: url,
            callbackURLScheme: MissCatAuthenticationBrowserPolicy.callbackScheme,
            preferredBrowserSession: browserSession
        )
    }
}
