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
