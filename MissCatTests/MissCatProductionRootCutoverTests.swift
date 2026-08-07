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

    func testAppDelegateDeliversResolvedPushesToApplicationMailbox() throws {
        let source = try source(named: "Others/App/AppDelegate.swift")

        XCTAssertTrue(source.contains("MissCatApplicationPushIngress"))
        XCTAssertTrue(source.contains("receive("))
        XCTAssertFalse(source.contains("HomeViewController"))
        XCTAssertFalse(source.contains("rootViewController"))
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
        let e2e = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("MissCatUITests/MissCatShellFeedUITests.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(root.contains("applicationNavigationActions: discoveryNavigationActions"))
        XCTAssertTrue(root.contains("openSearch: { rootStore.router.open(.search(query: $0)) }"))
        XCTAssertTrue(root.contains("share: { rootStore.router.presentSheet(.share(noteID: $0)) }"))
        XCTAssertTrue(root.contains("request.selectReaction(reaction)"))
        XCTAssertTrue(root.contains("productionSheetE2EMarker(\"reaction:\\(noteID)\")"))
        XCTAssertTrue(root.contains("productionSheetE2EMarker(\"share:\\(noteID)\")"))
        XCTAssertTrue(feed.contains("MissCatFeedReactionRequest"))
        XCTAssertTrue(feed.contains("await store.toggleReaction("))
        XCTAssertTrue(row.contains("note.\\(note.id).overflow.share"))
        XCTAssertTrue(discovery.contains("applicationNavigationActions"))

        for destination in [
            "profile:fixture-author-0",
            "note:home-0",
            "discovery",
            "search:SwiftUI",
            "reaction:home-0",
            "share:home-0",
        ] {
            XCTAssertTrue(e2e.contains(destination), "Missing behavioral E2E for \(destination)")
        }
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
