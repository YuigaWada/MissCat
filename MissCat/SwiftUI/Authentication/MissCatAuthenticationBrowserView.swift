import Foundation
import SwiftUI
import WebKit

public enum MissCatAuthenticationIntent: String, Hashable, Sendable {
    case signUp
    case logIn
}

/// Controls the browser's signed-in website session independently from the
/// native MissCat account selected after MiAuth completes.
public enum MissCatAuthenticationWebsiteDataPolicy: Hashable, Sendable {
    /// Normal login, retry, and relaunch behavior. Cookies and site data remain
    /// in WebKit's persistent default store so a server sign-in is reusable.
    case preserveSession

    /// A destructive, explicit account-switch action. This must never be used
    /// for automatic error recovery or an ordinary login attempt.
    case clearForExplicitAccountSwitch
}

enum MissCatAuthenticationInitialLoadPlan: Equatable {
    case loadImmediately
    case clearSelectedInstanceThenLoad(host: String)
}

enum MissCatAuthenticationBrowserPolicy {
    static func configuration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        return configuration
    }

    static func initialLoadPlan(
        for request: URLRequest,
        websiteDataPolicy: MissCatAuthenticationWebsiteDataPolicy
    ) -> MissCatAuthenticationInitialLoadPlan {
        guard websiteDataPolicy == .clearForExplicitAccountSwitch,
              let host = request.url?.host?.lowercased(),
              !host.isEmpty
        else {
            return .loadImmediately
        }
        return .clearSelectedInstanceThenLoad(host: host)
    }

    static func shouldClearRecord(displayName: String, selectedHost: String) -> Bool {
        let record = displayName.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let host = selectedHost.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !record.isEmpty, !host.isEmpty else { return false }
        return record == host
            || record.hasSuffix(".\(host)")
            || host.hasSuffix(".\(record)")
    }

    static func performInitialLoad(
        plan: MissCatAuthenticationInitialLoadPlan,
        load: @escaping () -> Void,
        clearSelectedInstance: (_ host: String, _ completion: @escaping () -> Void) -> Void
    ) {
        switch plan {
        case .loadImmediately:
            load()
        case let .clearSelectedInstanceThenLoad(host):
            clearSelectedInstance(host, load)
        }
    }
}

struct MissCatAuthenticationCallbackGate {
    private(set) var hasReportedCallback = false

    mutating func shouldReport(
        _ url: URL,
        matching callbackMatches: (URL) -> Bool
    ) -> Bool {
        guard !hasReportedCallback, callbackMatches(url) else { return false }
        hasReportedCallback = true
        return true
    }
}

enum MissCatAuthenticationOriginMatcher {
    static func matches(_ candidate: URL, origin: URL) -> Bool {
        guard let actual = URLComponents(url: candidate, resolvingAgainstBaseURL: false),
              let expected = URLComponents(url: origin, resolvingAgainstBaseURL: false),
              actual.scheme?.lowercased() == "https",
              actual.user == nil,
              actual.password == nil,
              actual.percentEncodedHost?.contains("%") != true
        else { return false }

        return actual.host?.lowercased() == expected.host?.lowercased()
            && normalizedPort(actual) == normalizedPort(expected)
    }

    private static func normalizedPort(_ components: URLComponents) -> Int {
        components.port ?? 443
    }
}

/// A WKWebView-backed authentication surface matching the legacy full-safe-area browser.
/// Token exchange stays in the authentication service; this view only reports callback URLs.
public struct MissCatAuthenticationBrowserView: View {
    public let request: URLRequest
    public let callbackMatches: (URL) -> Bool
    public let onCallback: (URL) -> Void
    public let makeLoginRequestAfterSignUp: (@MainActor () async throws -> URLRequest)?
    public let onFailure: (Error) -> Void
    public let websiteDataPolicy: MissCatAuthenticationWebsiteDataPolicy

    @State private var reloadToken = 0

    public init(
        request: URLRequest,
        callbackMatches: @escaping (URL) -> Bool,
        onCallback: @escaping (URL) -> Void,
        makeLoginRequestAfterSignUp: (@MainActor () async throws -> URLRequest)? = nil,
        websiteDataPolicy: MissCatAuthenticationWebsiteDataPolicy = .preserveSession,
        onFailure: @escaping (Error) -> Void = { _ in }
    ) {
        self.request = request
        self.callbackMatches = callbackMatches
        self.onCallback = onCallback
        self.makeLoginRequestAfterSignUp = makeLoginRequestAfterSignUp
        self.websiteDataPolicy = websiteDataPolicy
        self.onFailure = onFailure
    }

    public var body: some View {
        MissCatWebView(
            request: request,
            reloadToken: reloadToken,
            callbackMatches: callbackMatches,
            onCallback: onCallback,
            makeLoginRequestAfterSignUp: makeLoginRequestAfterSignUp,
            websiteDataPolicy: websiteDataPolicy,
            onFailure: onFailure
        )
        .background(Color(hex: MissCatLegacyColorHex.authenticationBrowserBackground))
        .navigationBarTitleDisplayMode(.inline)
        .missCatLegacyOnboardingNavigationBar()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    reloadToken += 1
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("再読み込み")
                .accessibilityIdentifier("authentication.reload")
            }
        }
        .accessibilityIdentifier("authentication.browser")
    }
}

private struct MissCatWebView: UIViewRepresentable {
    let request: URLRequest
    let reloadToken: Int
    let callbackMatches: (URL) -> Bool
    let onCallback: (URL) -> Void
    let makeLoginRequestAfterSignUp: (@MainActor () async throws -> URLRequest)?
    let websiteDataPolicy: MissCatAuthenticationWebsiteDataPolicy
    let onFailure: (Error) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            callbackMatches: callbackMatches,
            onCallback: onCallback,
            makeLoginRequestAfterSignUp: makeLoginRequestAfterSignUp,
            onFailure: onFailure
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = MissCatAuthenticationBrowserPolicy.configuration()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.isOpaque = false
        let legacyBackground = UIColor(
            Color(hex: MissCatLegacyColorHex.authenticationBrowserBackground)
        )
        webView.backgroundColor = legacyBackground
        webView.scrollView.backgroundColor = legacyBackground
        context.coordinator.loadedURL = request.url
        context.coordinator.loadInitialRequest(
            request,
            websiteDataPolicy: websiteDataPolicy,
            dataStore: configuration.websiteDataStore,
            in: webView
        )
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.callbackMatches = callbackMatches
        context.coordinator.onCallback = onCallback
        context.coordinator.makeLoginRequestAfterSignUp = makeLoginRequestAfterSignUp
        context.coordinator.onFailure = onFailure

        if context.coordinator.reloadToken != reloadToken {
            context.coordinator.reloadToken = reloadToken
            webView.reload()
        } else if context.coordinator.loadedURL != request.url {
            context.coordinator.loadedURL = request.url
            webView.load(request)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var callbackMatches: (URL) -> Bool
        var onCallback: (URL) -> Void
        var makeLoginRequestAfterSignUp: (@MainActor () async throws -> URLRequest)?
        var onFailure: (Error) -> Void
        var loadedURL: URL?
        var reloadToken = 0
        private var callbackGate = MissCatAuthenticationCallbackGate()
        private var requestedLoginAfterSignUp = false

        init(
            callbackMatches: @escaping (URL) -> Bool,
            onCallback: @escaping (URL) -> Void,
            makeLoginRequestAfterSignUp: (@MainActor () async throws -> URLRequest)?,
            onFailure: @escaping (Error) -> Void
        ) {
            self.callbackMatches = callbackMatches
            self.onCallback = onCallback
            self.makeLoginRequestAfterSignUp = makeLoginRequestAfterSignUp
            self.onFailure = onFailure
        }

        func loadInitialRequest(
            _ request: URLRequest,
            websiteDataPolicy: MissCatAuthenticationWebsiteDataPolicy,
            dataStore: WKWebsiteDataStore,
            in webView: WKWebView
        ) {
            let plan = MissCatAuthenticationBrowserPolicy.initialLoadPlan(
                for: request,
                websiteDataPolicy: websiteDataPolicy
            )
            MissCatAuthenticationBrowserPolicy.performInitialLoad(
                plan: plan,
                load: { webView.load(request) },
                clearSelectedInstance: { host, completion in
                    self.clearWebsiteData(
                        for: host,
                        in: dataStore,
                        completion: completion
                    )
                }
            )
        }

        private func clearWebsiteData(
            for selectedHost: String,
            in dataStore: WKWebsiteDataStore,
            completion: @escaping () -> Void
        ) {
            let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
            dataStore.fetchDataRecords(ofTypes: dataTypes) { records in
                let selectedRecords = records.filter {
                    MissCatAuthenticationBrowserPolicy.shouldClearRecord(
                        displayName: $0.displayName,
                        selectedHost: selectedHost
                    )
                }
                guard !selectedRecords.isEmpty else {
                    DispatchQueue.main.async(execute: completion)
                    return
                }
                dataStore.removeData(ofTypes: dataTypes, for: selectedRecords) {
                    DispatchQueue.main.async(execute: completion)
                }
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            if callbackGate.hasReportedCallback {
                decisionHandler(.cancel)
                return
            }

            if let url = navigationAction.request.url,
               callbackMatches(url) {
                if callbackGate.shouldReport(url, matching: callbackMatches) {
                    onCallback(url)
                }
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
            guard !requestedLoginAfterSignUp,
                  let makeLoginRequestAfterSignUp,
                  let signUpOrigin = loadedURL,
                  let currentURL = webView.url,
                  MissCatAuthenticationOriginMatcher.matches(currentURL, origin: signUpOrigin)
            else { return }

            // The legacy web flow used the localStorage token itself as a signal.
            // Only inspect a boolean on the selected instance origin; the token
            // never leaves the web content process or enters native logs/state.
            let script = "(() => { try { return localStorage.getItem('i') !== null; } catch (_) { return false; } })()"
            webView.evaluateJavaScript(script) { result, _ in
                guard result as? Bool == true else { return }
                self.requestedLoginAfterSignUp = true

                Task { @MainActor in
                    do {
                        let request = try await makeLoginRequestAfterSignUp()
                        self.loadedURL = request.url
                        webView.load(request)
                    } catch {
                        self.requestedLoginAfterSignUp = false
                        self.onFailure(error)
                    }
                }
            }
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation?,
            withError error: Error
        ) {
            reportNavigationFailure(error)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation?,
            withError error: Error
        ) {
            reportNavigationFailure(error)
        }

        private func reportNavigationFailure(_ error: Error) {
            let nsError = error as NSError
            guard nsError.domain != NSURLErrorDomain || nsError.code != NSURLErrorCancelled else { return }
            onFailure(error)
        }
    }
}
