import CryptoKit
import XCTest

final class MissCatShareKeychainUITests: XCTestCase {
    private static let appBundleIdentifier = "yuwd.MissCat"
    private static let fixtureUserID = "misscat-shared-keychain-fixture"
    private static let fixtureInstance = "shared-keychain-probe.invalid"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSignedAppCredentialIsReadableByEmbeddedShareExtension() throws {
        let app = XCUIApplication(bundleIdentifier: Self.appBundleIdentifier)
        addTeardownBlock {
            self.cleanupFixture(using: app)
        }

        app.terminate()
        app.launchArguments = [
            "--misscat-shared-keychain-e2e",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["keychain-probe.ready"].waitForExistence(timeout: 15))
        app.buttons["keychain-probe.launch-share"].tap()

        let missCatActivity = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "MissCat"))
            .firstMatch
        if !missCatActivity.waitForExistence(timeout: 12) {
            let moreActivity = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@", "More"))
                .firstMatch
            XCTAssertTrue(moreActivity.waitForExistence(timeout: 5))
            moreActivity.tap()
        }

        let resolvedMissCatActivity = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "MissCat"))
            .firstMatch
        XCTAssertTrue(resolvedMissCatActivity.waitForExistence(timeout: 12))
        resolvedMissCatActivity.tap()

        let available = app.staticTexts["share-keychain-proof.available"]
        let accountHash = app.staticTexts["share-keychain-proof.account-hash"]
        XCTAssertTrue(available.waitForExistence(timeout: 15))
        XCTAssertTrue(accountHash.waitForExistence(timeout: 5))
        XCTAssertEqual(available.label, "true")
        XCTAssertEqual(accountHash.label, Self.expectedFixtureAccountHash)

        cleanupFixture(using: app)
        XCTAssertTrue(app.staticTexts["keychain-probe.cleaned"].waitForExistence(timeout: 15))
    }

    private func cleanupFixture(using app: XCUIApplication) {
        app.terminate()
        app.launchArguments = [
            "--misscat-shared-keychain-e2e-cleanup",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launch()
        _ = app.staticTexts["keychain-probe.cleaned"].waitForExistence(timeout: 15)
    }

    private static var expectedFixtureAccountHash: String {
        let instance = Data(fixtureInstance.utf8).base64EncodedString()
        let userID = Data(fixtureUserID.utf8).base64EncodedString()
        let accountIdentifier = "misscat-account-v2:\(instance):\(userID)"
        return SHA256.hash(data: Data(accountIdentifier.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
