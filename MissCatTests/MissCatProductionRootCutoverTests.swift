@testable import MissCat
import Foundation
import XCTest

@MainActor
final class MissCatProductionRootCutoverTests: XCTestCase {
    func testOrdinaryAuthenticatedRootConstructsProductionSwiftUIAssembly() throws {
        let source = try source(named: "Others/App/MissCatApp.swift")

        XCTAssertTrue(source.contains("MissCatProductionApplicationRootView("))
        XCTAssertFalse(source.contains("LegacyApplicationView()"))
        XCTAssertFalse(source.contains("UIStoryboard(name: \"Main\""))

        let uiTestSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("MissCatUITests/MissCatShellFeedUITests.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(uiTestSource.contains("dragProductionPager(from:"))
        XCTAssertTrue(uiTestSource.contains("element(\"main.content.home\")"))
        XCTAssertTrue(uiTestSource.contains("thenDragTo: end"))
        XCTAssertFalse(uiTestSource.contains("#if arch("))

        let ledger = try String(
            contentsOf: repositoryRoot.appendingPathComponent("docs/ui-migration-surfaces.tsv"),
            encoding: .utf8
        )
        let rows = ledger.split(separator: "\n").filter { line in
            line.first?.isNumber == true
        }.map { $0.split(separator: "\t", omittingEmptySubsequences: false) }
        XCTAssertEqual(rows.count, 45)
        XCTAssertEqual(rows.filter { $0.count > 4 && $0[3] == "swiftui" }.count, 45)
        XCTAssertEqual(rows.filter { $0.count > 4 && $0[4] == "accepted" }.count, 0)
        XCTAssertEqual(rows.filter { $0.count > 4 && $0[4] == "migrating" }.count, 45)
    }

    func testProductionAssemblyHasNoStoryboardOrHomeControllerDependency() throws {
        let source = try source(
            named: "SwiftUI/ApplicationRoot/MissCatProductionApplicationRootView.swift"
        )

        XCTAssertFalse(source.contains("UIStoryboard"))
        XCTAssertFalse(source.contains("HomeViewController"))
        XCTAssertFalse(source.contains("LegacyApplicationView"))

        for nativeType in [
            "MissCatMainShellView",
            "NavigationStack(path:",
            "MissCatComposeScreen",
            "MissCatSettingsRootView",
            "MissCatAccountsRootView",
            "MissCatProfileFamilyView",
            "MissCatDiscoveryRoot",
            "MissCatNotificationsView",
            "MissCatMessageHistoryView",
            "MissCatConversationView",
            "MissCatNoteDetailView",
            "MissCatReactionPickerView",
            "MissCatApplicationShareSheet"
        ] {
            XCTAssertTrue(
                source.contains(nativeType),
                "Production assembly must construct \(nativeType) directly"
            )
        }

        let project = try String(
            contentsOf: repositoryRoot.appendingPathComponent("MissCat.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )
        XCTAssertFalse(project.contains("MissCatLegacyApplicationView"))

        let shippingRoot = repositoryRoot.appendingPathComponent("MissCat")
        let enumerator = FileManager.default.enumerator(
            at: shippingRoot,
            includingPropertiesForKeys: nil
        )
        let swiftFiles = (enumerator?.allObjects as? [URL] ?? []).filter {
            $0.pathExtension == "swift"
        }
        let shippingSource = try swiftFiles.map {
            try String(contentsOf: $0, encoding: .utf8)
        }.joined(separator: "\n")
        XCTAssertFalse(shippingSource.contains("MissCatLegacyApplicationView"))
        XCTAssertFalse(shippingSource.contains("struct LegacyApplicationView"))
    }

    func testProductionRootDefersRemotePushTransportWithoutRetainingFCMScaffolding() throws {
        let app = try source(named: "Others/App/MissCatApp.swift")
        let support = try source(
            named: "SwiftUI/ApplicationRoot/MissCatProductionApplicationSupport.swift"
        )
        let rootStore = try source(
            named: "SwiftUI/ApplicationRoot/MissCatApplicationRootStore.swift"
        )
        let authentication = try source(
            named: "SwiftUI/Authentication/MissCatAuthenticationService.swift"
        )

        for source in [app, support, rootStore, authentication] {
            XCTAssertFalse(source.contains("UIApplicationDelegateAdaptor"))
            XCTAssertFalse(source.contains("Firebase"))
            XCTAssertFalse(source.contains("Messaging"))
            XCTAssertFalse(source.contains("registerForRemoteNotifications"))
            XCTAssertFalse(source.contains("MissCatApplicationPush"))
        }
    }

    func testProductionComposeUsesRootBoundAuthorizedScopesInsteadOfGlobalAccountSelection() throws {
        let root = try source(
            named: "SwiftUI/ApplicationRoot/MissCatProductionApplicationRootView.swift"
        )
        let compose = try source(named: "SwiftUI/Compose/MissCatComposeService.swift")
        let support = try source(
            named: "SwiftUI/ApplicationRoot/MissCatProductionApplicationSupport.swift"
        )

        XCTAssertTrue(root.contains("session: composeSession"))
        XCTAssertTrue(root.contains("MissCatComposeProductionSession("))
        XCTAssertTrue(root.contains("session.accounts.compactMap"))
        XCTAssertTrue(root.contains("visibilityPersistence: coordinator.persistComposeVisibility"))
        XCTAssertFalse(root.contains("return MissCatComposeFactory.makeViewModel(mode: mode)"))
        XCTAssertTrue(compose.contains("scopesByAccountID"))
        XCTAssertTrue(compose.contains("injectedScopes[submission.accountID]"))
        XCTAssertFalse(compose.contains("cache.changeCurrentUser"))
        XCTAssertTrue(support.contains("persistedAccountID"))
        XCTAssertTrue(support.contains("recordComposeSubmissionScope"))
        XCTAssertFalse(support.contains("MissCatProductionRootE2EComposePosting"))
        XCTAssertFalse(support.contains("func persistSelectedAccount(id: String) {}"))
    }

    func testProductionOrdinaryRoutesHaveShippingCallersAndBehavioralE2E() throws {
        let root = try source(
            named: "SwiftUI/ApplicationRoot/MissCatProductionApplicationRootView.swift"
        )
        let feed = try source(named: "SwiftUI/Timeline/MissCatFeedScreens.swift")
        let row = try source(named: "SwiftUI/Timeline/MissCatNoteRow.swift")
        let discovery = try source(named: "SwiftUI/Discovery/MissCatDiscoveryViews.swift")
        let profileFamily = try source(named: "SwiftUI/Profile/MissCatProfileFamilyView.swift")
        let e2e = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("MissCatUITests/MissCatShellFeedUITests.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(root.contains("applicationNavigationActions: discoveryNavigationActions"))
        XCTAssertTrue(root.contains("openSearch: { rootStore.router.open(.search(query: $0)) }"))
        XCTAssertTrue(root.contains("share: { rootStore.router.presentSheet(.share(noteID: $0)) }"))
        XCTAssertTrue(root.contains("onOpenDestination: openProfileDestination"))
        XCTAssertTrue(root.contains("case let .profileUserList(kind)"))
        XCTAssertTrue(root.contains("case let .profileEditor(profile)"))
        XCTAssertTrue(profileFamily.contains("if shellOwnership.ownsNavigationStack"))
        XCTAssertTrue(profileFamily.contains("NavigationStack(path: $path)"))
        XCTAssertTrue(profileFamily.contains("onOpenDestination"))
        XCTAssertTrue(root.contains("request.selectReaction(reaction)"))
        XCTAssertTrue(root.contains("productionSheetE2EMarker(\"reaction:\\(noteID)\")"))
        XCTAssertTrue(root.contains("productionSheetE2EMarker(\"share:\\(noteID)\")"))
        XCTAssertTrue(feed.contains("MissCatFeedReactionRequest"))
        XCTAssertTrue(feed.contains("await store.toggleReaction("))
        XCTAssertTrue(row.contains("note.\\(note.id).overflow.share"))
        XCTAssertTrue(discovery.contains("applicationNavigationActions"))

        for destination in [
            "profile:fixture-author-0",
            "profile-list:followers-fixture-author-0",
            "note:home-0",
            "discovery",
            "search:SwiftUI",
            "reaction:home-0",
            "share:home-0",
        ] {
            XCTAssertTrue(e2e.contains(destination), "Missing behavioral E2E for \(destination)")
        }
        XCTAssertTrue(e2e.contains("profile.user.fixture-author-0"))
        XCTAssertTrue(e2e.contains("Failed optimistic mutation must roll the reaction chip back"))
        XCTAssertTrue(e2e.contains("ShareLink must reach the system activity sheet"))
        XCTAssertFalse(root.contains("UIViewControllerRepresentable"))
        XCTAssertFalse(root.contains("UIActivityViewController"))
    }

    func testSharedKeychainProbeUsesNativeShareLinkWithoutUIKitBridge() throws {
        let app = try source(named: "Others/App/MissCatApp.swift")

        XCTAssertTrue(app.contains("ShareLink("))
        XCTAssertTrue(app.contains("MissCat non-live shared-Keychain fixture"))
        XCTAssertTrue(app.contains("keychain-probe.launch-share"))
        XCTAssertFalse(app.contains("import UIKit"))
        XCTAssertFalse(app.contains("UIViewControllerRepresentable"))
        XCTAssertFalse(app.contains("UIActivityViewController"))
        XCTAssertFalse(app.contains("MissCatSharedKeychainActivityView"))
    }

    func testAuthenticationUsesNativeSwiftUIWebSessionWithoutEmbeddedWebKit() throws {
        let browser = try source(
            named: "SwiftUI/Authentication/MissCatAuthenticationBrowserView.swift"
        )
        let info = try String(
            contentsOf: repositoryRoot.appendingPathComponent("MissCat/Info.plist"),
            encoding: .utf8
        )

        XCTAssertTrue(browser.contains("@Environment(\\.webAuthenticationSession)"))
        XCTAssertTrue(browser.contains("authenticate(using:"))
        XCTAssertTrue(browser.contains("authentication.browser"))
        XCTAssertTrue(browser.contains("authentication.reload"))
        XCTAssertTrue(browser.contains("@Environment(\\.openURL)"))
        XCTAssertTrue(browser.contains("authentication.signup.continue"))
        XCTAssertFalse(browser.contains("import WebKit"))
        XCTAssertFalse(browser.contains("WKWebView"))
        XCTAssertFalse(browser.contains("localStorage"))
        XCTAssertFalse(browser.contains("UIViewRepresentable"))
        XCTAssertFalse(browser.contains("UIViewControllerRepresentable"))
        XCTAssertTrue(info.contains("CFBundleURLTypes"))
        XCTAssertTrue(info.contains("<string>misscat</string>"))
    }

    func testAuthenticationLifecycleUsesObservationInsteadOfCombineStateWrappers() throws {
        let app = try source(named: "Others/App/MissCatApp.swift")
        let authenticationRoot = repositoryRoot
            .appendingPathComponent("MissCat/SwiftUI/Authentication")
        let authenticationSources = try FileManager.default
            .contentsOfDirectory(
                at: authenticationRoot,
                includingPropertiesForKeys: nil
            )
            .filter { $0.pathExtension == "swift" }
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
        let shippingAuthenticationState = app + "\n" + authenticationSources

        XCTAssertTrue(app.contains("import Observation"))
        XCTAssertTrue(app.contains("@Observable\nfinal class ApplicationState"))
        XCTAssertTrue(app.contains("@State private var applicationState"))
        XCTAssertTrue(app.contains("@Environment(ApplicationState.self)"))
        XCTAssertTrue(app.contains(".environment(applicationState)"))

        for retiredStateAPI in [
            "import Combine",
            "ObservableObject",
            "@Published",
            "@StateObject",
            "@EnvironmentObject",
        ] {
            XCTAssertFalse(
                shippingAuthenticationState.contains(retiredStateAPI),
                "Shipping authentication state still uses \(retiredStateAPI)"
            )
        }
    }

    func testAuthenticationSurfacesExposeEveryPinnedVisualState() throws {
        let app = try source(named: "Others/App/MissCatApp.swift")
        let welcome = try source(
            named: "SwiftUI/Authentication/MissCatWelcomeView.swift"
        )
        let terms = try source(
            named: "SwiftUI/Authentication/MissCatTermsView.swift"
        )
        let instance = try source(
            named: "SwiftUI/Authentication/MissCatInstanceEditorView.swift"
        )
        let browser = try source(
            named: "SwiftUI/Authentication/MissCatAuthenticationBrowserView.swift"
        )
        let sources = [app, welcome, terms, instance, browser].joined(separator: "\n")

        for visualState in [
            "visual-ready.login-start.default",
            "visual-ready.login-start.error",
            "visual-ready.login-terms.top",
            "visual-ready.login-terms.bottom",
            "visual-ready.login-instance.default",
            "visual-ready.login-instance.invalid",
            "visual-ready.login-auth-browser.loading",
            "visual-ready.login-auth-browser.error",
            "visual-ready.login-auth-browser.callback",
        ] {
            XCTAssertTrue(
                sources.contains(visualState),
                "Missing deterministic visual-ready state: \(visualState)"
            )
        }

        XCTAssertTrue(welcome.contains("if visualIsReady {"))
        XCTAssertFalse(welcome.contains("value: visualIsReady"))
        XCTAssertTrue(instance.contains("if isPresented {"))
        XCTAssertTrue(browser.contains("visual-ready.login-auth-registration"))
    }

    func testSystemShareOracleUsesRemoteSystemIdentifiersInsteadOfAirDropAvailability() throws {
        let e2e = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("MissCatUITests/MissCatShellFeedUITests.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(e2e.contains("waitForSystemShareSheet()"))
        XCTAssertTrue(e2e.contains("identifier IN %@"))
        for identifier in [
            "ActivityListView",
            "ShareSheet.RemoteContainerView",
            "UIActivityContentView",
            "header.closeButton",
            "actionGroupCell",
        ] {
            XCTAssertTrue(e2e.contains(identifier), "Missing system share oracle: \(identifier)")
        }
        XCTAssertTrue(e2e.contains("System activity sheet must expose its close button or Copy action"))
        XCTAssertFalse(e2e.contains("AirDrop"))
        XCTAssertFalse(e2e.contains("XCUIApplication(bundleIdentifier:"))
    }

    func testNoteDetailPreservesScreenAndThreadAccessibilityBoundaries() throws {
        let feed = try source(named: "SwiftUI/Timeline/MissCatFeedScreens.swift")

        XCTAssertTrue(
            feed.contains(
                ".overlay(alignment: .topLeading) {\n            MissCatFeedAccessibilityMarker(identifier: \"note.detail.screen\")\n        }"
            )
        )
        XCTAssertTrue(feed.contains(".accessibilityIdentifier(\"note.detail.thread\")"))
        XCTAssertTrue(feed.contains("Color.clear"))
        XCTAssertTrue(feed.contains(".frame(width: 1, height: 1)"))
        XCTAssertTrue(feed.contains(".accessibilityElement(children: .ignore)"))
        XCTAssertTrue(feed.contains(".allowsHitTesting(false)"))
        XCTAssertFalse(
            feed.contains(
                ".accessibilityElement(children: .contain)\n        .accessibilityIdentifier(\"note.detail.screen\")"
            )
        )
    }

    func testProductionRouteScreensKeepRootAndChildAccessibilityIDsIndependent() throws {
        let root = try source(named: "SwiftUI/ApplicationRoot/MissCatProductionApplicationRootView.swift")
        let feed = try source(named: "SwiftUI/Timeline/MissCatFeedScreens.swift")
        let reactions = try source(named: "SwiftUI/Timeline/MissCatNoteDetailViews.swift")
        let discovery = try source(named: "SwiftUI/Discovery/MissCatDiscoveryViews.swift")
        let profile = try source(named: "SwiftUI/Profile/MissCatProfileViews.swift")

        XCTAssertTrue(
            discovery.contains(
                ".overlay(alignment: .topLeading) {\n            MissCatDiscoveryAccessibilityMarker(identifier: \"home.discovery.native-page\")\n        }"
            )
        )
        XCTAssertTrue(discovery.contains(".accessibilityIdentifier(\"discovery.trends.list\")"))
        XCTAssertTrue(discovery.contains(".accessibilityIdentifier(\"discovery.trend.\\(trend.tag)\")"))
        XCTAssertFalse(
            discovery.contains(
                ".id(generation.id)\n        .accessibilityIdentifier(\"home.discovery.native-page\")"
            )
        )

        XCTAssertTrue(
            feed.contains(
                "MissCatFeedAccessibilityMarker(identifier: \"feed.\\(store.source.accessibilityName)\")"
            )
        )
        XCTAssertTrue(feed.contains(".accessibilityIdentifier(\"feed.scroll\")"))
        XCTAssertTrue(feed.contains(".accessibilityIdentifier(\"feed.banner.error\")"))
        XCTAssertFalse(
            feed.contains(
                ".accessibilityElement(children: .contain)\n        .accessibilityIdentifier(\"feed.\\(store.source.accessibilityName)\")"
            )
        )

        XCTAssertTrue(
            root.contains(
                "MissCatProductionAccessibilityMarker(identifier: \"share.sheet\")"
            )
        )
        XCTAssertTrue(root.contains(".accessibilityIdentifier(\"share.link\")"))
        XCTAssertTrue(root.contains("ShareLink(item: url)"))
        XCTAssertFalse(
            root.contains(
                "MissCatApplicationShareSheet(url: url)\n                    .accessibilityIdentifier(\"share.sheet\")"
            )
        )

        XCTAssertTrue(reactions.contains(".accessibilityIdentifier(\"reaction.picker\")"))
        XCTAssertTrue(
            reactions.contains(
                ".accessibilityIdentifier(\"reaction.picker.choice.\\(choice.value)\")"
            )
        )
        XCTAssertTrue(profile.contains("identifier: store.isCurrentUser ? \"profile.self.screen\" : \"profile.other.screen\""))
        XCTAssertTrue(profile.contains("identifier: \"profile.count.followers\""))
    }

    private func source(named relativePath: String) throws -> String {
        return try String(
            contentsOf: repositoryRoot.appendingPathComponent("MissCat/\(relativePath)"),
            encoding: .utf8
        )
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
