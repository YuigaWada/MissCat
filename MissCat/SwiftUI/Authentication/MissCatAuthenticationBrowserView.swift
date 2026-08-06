import Foundation
import SwiftUI
import WebKit

public enum MissCatAuthenticationIntent: String, Hashable, Sendable {
    case signUp
    case logIn
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

    @State private var reloadToken = 0

    public init(
        request: URLRequest,
        callbackMatches: @escaping (URL) -> Bool,
        onCallback: @escaping (URL) -> Void,
        makeLoginRequestAfterSignUp: (@MainActor () async throws -> URLRequest)? = nil,
        onFailure: @escaping (Error) -> Void = { _ in }
    ) {
        self.request = request
        self.callbackMatches = callbackMatches
        self.onCallback = onCallback
        self.makeLoginRequestAfterSignUp = makeLoginRequestAfterSignUp
        self.onFailure = onFailure
    }

    public var body: some View {
        MissCatWebView(
            request: request,
            reloadToken: reloadToken,
            callbackMatches: callbackMatches,
            onCallback: onCallback,
            makeLoginRequestAfterSignUp: makeLoginRequestAfterSignUp,
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
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.isOpaque = false
        let legacyBackground = UIColor(hex: MissCatLegacyColorHex.authenticationBrowserBackground)
        webView.backgroundColor = legacyBackground
        webView.scrollView.backgroundColor = legacyBackground
        context.coordinator.loadedURL = request.url
        context.coordinator.clearWebsiteDataAndLoad(request, in: webView)
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

        func clearWebsiteDataAndLoad(_ request: URLRequest, in webView: WKWebView) {
            let dataStore = WKWebsiteDataStore.default()
            let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
            dataStore.fetchDataRecords(ofTypes: dataTypes) { records in
                dataStore.removeData(ofTypes: dataTypes, for: records) {
                    DispatchQueue.main.async {
                        webView.load(request)
                    }
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
    }
}
