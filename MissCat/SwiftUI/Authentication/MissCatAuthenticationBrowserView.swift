import Foundation
import SwiftUI
import WebKit

public enum MissCatAuthenticationIntent: String, Hashable, Sendable {
    case signUp
    case logIn
}

/// A WKWebView-backed authentication surface matching the legacy full-safe-area browser.
/// Token exchange stays in the authentication service; this view only reports callback URLs.
public struct MissCatAuthenticationBrowserView: View {
    public let request: URLRequest
    public let callbackMatches: (URL) -> Bool
    public let onCallback: (URL) -> Void

    @State private var reloadToken = 0

    public init(
        request: URLRequest,
        callbackMatches: @escaping (URL) -> Bool,
        onCallback: @escaping (URL) -> Void
    ) {
        self.request = request
        self.callbackMatches = callbackMatches
        self.onCallback = onCallback
    }

    public var body: some View {
        MissCatWebView(
            request: request,
            reloadToken: reloadToken,
            callbackMatches: callbackMatches,
            onCallback: onCallback
        )
        .background(Color(hex: "5C6367"))
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

    func makeCoordinator() -> Coordinator {
        Coordinator(callbackMatches: callbackMatches, onCallback: onCallback)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.isOpaque = false
        let legacyBackground = UIColor(
            red: 92 / 255,
            green: 99 / 255,
            blue: 103 / 255,
            alpha: 1
        )
        webView.backgroundColor = legacyBackground
        webView.scrollView.backgroundColor = legacyBackground
        webView.load(request)
        context.coordinator.loadedURL = request.url
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.callbackMatches = callbackMatches
        context.coordinator.onCallback = onCallback

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
        var loadedURL: URL?
        var reloadToken = 0
        private var reportedCallbackURL: URL?

        init(
            callbackMatches: @escaping (URL) -> Bool,
            onCallback: @escaping (URL) -> Void
        ) {
            self.callbackMatches = callbackMatches
            self.onCallback = onCallback
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            if let url = navigationAction.request.url,
               callbackMatches(url),
               reportedCallbackURL != url {
                reportedCallbackURL = url
                onCallback(url)
            }
            decisionHandler(.allow)
        }
    }
}
