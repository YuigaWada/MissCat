//
//  MissCatTests.swift
//  MissCatTests
//
//  Created by Yuiga Wada on 2019/11/07.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

@testable import MissCat
import UIKit
import XCTest

class MissCatTests: XCTestCase {
    override func setUp() {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    func testExample() {
        let text = NSTextAttachment()
    }
}

final class WelcomeVisualLayoutTests: XCTestCase {
    func testReferenceStoryboardFramesAreRecoveredFromSafeAreaLayout() {
        let safeTop: CGFloat = 48
        let layout = MissCatWelcomeLayout(
            contentSize: CGSize(width: 414, height: 814),
            safeTop: safeTop,
            safeBottom: 34
        )

        XCTAssertEqual(layout.canvasHeight, 896, accuracy: 0.001)
        XCTAssertEqual(layout.backgroundOffsetY, -48, accuracy: 0.001)
        XCTAssertEqual(layout.logoCenterY + safeTop, 340, accuracy: 0.001)
        XCTAssertEqual(layout.taglineCenterY + safeTop, 409.5, accuracy: 0.001)
        XCTAssertEqual(layout.buttonHeight, 51, accuracy: 0.001)
        XCTAssertEqual(layout.buttonsTopY + safeTop, 711, accuracy: 0.001)
        XCTAssertEqual(layout.changeInstanceCenterY + safeTop, 797, accuracy: 0.001)
        XCTAssertEqual(layout.instanceCenterY + safeTop, 843, accuracy: 0.001)
    }

    func testIPhone16ProUsesFullCanvasForProportionalButtonHeight() {
        let safeTop: CGFloat = 62
        let layout = MissCatWelcomeLayout(
            contentSize: CGSize(width: 402, height: 778),
            safeTop: safeTop,
            safeBottom: 34
        )

        XCTAssertEqual(layout.canvasHeight, 874, accuracy: 0.001)
        XCTAssertEqual(layout.buttonHeight, 49.7477, accuracy: 0.001)
        XCTAssertEqual(layout.buttonsTopY + safeTop, 690.2523, accuracy: 0.001)
        XCTAssertEqual(layout.changeInstanceCenterY + safeTop, 775, accuracy: 0.001)
        XCTAssertEqual(layout.instanceCenterY + safeTop, 821, accuracy: 0.001)
        XCTAssertEqual(MissCatLegacyMetrics.welcomeButtonFontSize, 15, accuracy: 0.001)
        XCTAssertEqual(MissCatLegacyMetrics.welcomeChangeInstanceFontSize, 15, accuracy: 0.001)
    }
}

final class OnboardingVisualTokenTests: XCTestCase {
    func testTermsMetricsMatchLegacyStoryboard() {
        XCTAssertEqual(MissCatLegacyMetrics.termsTextFontSize, 11, accuracy: 0.001)
        XCTAssertEqual(MissCatLegacyMetrics.termsTextHorizontalInset, 5, accuracy: 0.001)
        XCTAssertEqual(MissCatLegacyMetrics.termsTextVerticalInset, 8, accuracy: 0.001)
        XCTAssertEqual(MissCatLegacyMetrics.termsAgreementTopGap, 15, accuracy: 0.001)
        XCTAssertEqual(MissCatLegacyMetrics.termsAgreementTrailingInset, 20, accuracy: 0.001)
        XCTAssertEqual(MissCatLegacyMetrics.termsAgreementHeight, 30, accuracy: 0.001)
        XCTAssertEqual(MissCatLegacyMetrics.termsAgreementFontSize, 15, accuracy: 0.001)
    }

    func testAuthenticationChromeMatchesLegacyUIKitValues() {
        XCTAssertEqual(MissCatLegacyColorHex.authenticationBrowserBackground, "5C6367")
        XCTAssertEqual(MissCatLegacyMetrics.authenticationLoadingDialogSize, 95, accuracy: 0.001)
        XCTAssertEqual(MissCatLegacyMetrics.authenticationModalScrimOpacity, 0.20, accuracy: 0.001)
    }
}

private enum FakeAPIKeyStoreError: Error {
    case readFailed
    case writeFailed
    case removeFailed
}

private final class FakeAPIKeyStore: AccountAPIKeyStoring {
    var values: [String: String] = [:]
    var readShouldFail = false
    var writeShouldFail = false
    var removeShouldFail = false

    func apiKey(for userId: String) throws -> String? {
        if readShouldFail { throw FakeAPIKeyStoreError.readFailed }
        return values[userId]
    }

    func setAPIKey(_ apiKey: String, for userId: String) throws {
        if writeShouldFail { throw FakeAPIKeyStoreError.writeFailed }
        values[userId] = apiKey
    }

    func removeAPIKey(for userId: String) throws {
        if removeShouldFail { throw FakeAPIKeyStoreError.removeFailed }
        values.removeValue(forKey: userId)
    }
}

final class AccountPersistenceTests: XCTestCase {
    private var suiteName = ""
    private var defaults: Foundation.UserDefaults!
    private var keyStore: FakeAPIKeyStore!
    private var subject: Cache.UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "yuwd.MissCatTests.AccountPersistence.\(UUID().uuidString)"
        defaults = Foundation.UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        keyStore = FakeAPIKeyStore()
        subject = Cache.UserDefaults(userDefaults: defaults, apiKeyStore: keyStore)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        subject = nil
        keyStore = nil
        defaults = nil
        super.tearDown()
    }

    func testSaveStoresOnlySanitizedMetadataInSharedDefaults() throws {
        let testAPIKey = "test-api-key-not-a-credential"
        let user = makeUser(id: "user-a", apiKey: testAPIKey)

        XCTAssertTrue(subject.saveUser(user))

        let data = try XCTUnwrap(defaults.data(forKey: "saved-user"))
        let metadata = try JSONDecoder().decode([SecureUser].self, from: data)
        XCTAssertEqual(metadata.map { $0.userId }, ["user-a"])
        XCTAssertNil(metadata.first?.apiKey)
        XCTAssertNil(data.range(of: Data(testAPIKey.utf8)))
        XCTAssertEqual(keyStore.values["user-a"], testAPIKey)
        XCTAssertNil(user.apiKey)
    }

    func testSaveReturnsFalseWhenKeyStoreWriteFails() {
        keyStore.writeShouldFail = true

        XCTAssertFalse(subject.saveUser(makeUser(id: "user-a")))
        XCTAssertNil(defaults.data(forKey: "saved-user"))
    }

    func testSaveReturnsFalseWhenKeyStoreVerificationReadFails() {
        keyStore.readShouldFail = true

        XCTAssertFalse(subject.saveUser(makeUser(id: "user-a")))
        XCTAssertNil(defaults.data(forKey: "saved-user"))
    }

    func testThrowingReadPropagatesKeyStoreFailureWithoutDeletingMetadata() throws {
        XCTAssertTrue(subject.saveUser(makeUser(id: "user-a")))
        keyStore.readShouldFail = true

        XCTAssertThrowsError(try subject.getUsersThrowing())

        let data = try XCTUnwrap(defaults.data(forKey: "saved-user"))
        let metadata = try JSONDecoder().decode([SecureUser].self, from: data)
        XCTAssertEqual(metadata.map { $0.userId }, ["user-a"])
        XCTAssertNil(metadata.first?.apiKey)
    }

    func testLegacyPlaintextKeyIsMigratedAndScrubbed() throws {
        let testAPIKey = "legacy-test-key-not-a-credential"
        defaults.set(try JSONEncoder().encode([makeUser(id: "user-a", apiKey: testAPIKey)]),
                     forKey: "saved-user")

        let users = try subject.getUsersThrowing()

        XCTAssertEqual(users.first?.apiKey, testAPIKey)
        XCTAssertEqual(keyStore.values["user-a"], testAPIKey)
        let data = try XCTUnwrap(defaults.data(forKey: "saved-user"))
        let metadata = try JSONDecoder().decode([SecureUser].self, from: data)
        XCTAssertNil(metadata.first?.apiKey)
        XCTAssertNil(data.range(of: Data(testAPIKey.utf8)))
    }

    func testLegacyPlaintextKeyIsScrubbedWhenKeyStoreReadFails() throws {
        let testAPIKey = "legacy-test-key-not-a-credential"
        defaults.set(try JSONEncoder().encode([makeUser(id: "user-a", apiKey: testAPIKey)]),
                     forKey: "saved-user")
        keyStore.readShouldFail = true

        XCTAssertThrowsError(try subject.getUsersThrowing())

        let data = try XCTUnwrap(defaults.data(forKey: "saved-user"))
        let metadata = try JSONDecoder().decode([SecureUser].self, from: data)
        XCTAssertEqual(metadata.map { $0.userId }, ["user-a"])
        XCTAssertNil(metadata.first?.apiKey)
        XCTAssertNil(data.range(of: Data(testAPIKey.utf8)))
        XCTAssertTrue(keyStore.values.isEmpty)
    }

    func testRemovingAccountsRepairsAndThenClearsCurrentUserId() {
        XCTAssertTrue(subject.saveUser(makeUser(id: "user-a")))
        XCTAssertTrue(subject.saveUser(makeUser(id: "user-b")))
        subject.changeCurrentUser(userId: "user-a")

        XCTAssertTrue(subject.removeUser(userId: "user-a"))
        XCTAssertEqual(subject.getCurrentUserId(), "user-b")

        XCTAssertTrue(subject.removeUser(userId: "user-b"))
        XCTAssertNil(subject.getCurrentUserId())
    }

    func testRemoveFailureKeepsMetadataCredentialAndCurrentSelection() throws {
        XCTAssertTrue(subject.saveUser(makeUser(id: "user-a")))
        subject.changeCurrentUser(userId: "user-a")
        keyStore.removeShouldFail = true

        XCTAssertFalse(subject.removeUser(userId: "user-a"))

        let data = try XCTUnwrap(defaults.data(forKey: "saved-user"))
        let metadata = try JSONDecoder().decode([SecureUser].self, from: data)
        XCTAssertEqual(metadata.map { $0.userId }, ["user-a"])
        XCTAssertEqual(keyStore.values["user-a"], "test-key-not-a-credential")
        XCTAssertEqual(subject.getCurrentUserId(), "user-a")
    }

    func testCurrentUserRepairsStaleIdentifierDeterministically() {
        XCTAssertTrue(subject.saveUser(makeUser(id: "user-a")))
        XCTAssertTrue(subject.saveUser(makeUser(id: "user-b")))
        subject.changeCurrentUser(userId: "missing-user")

        XCTAssertEqual(subject.getCurrentUser()?.userId, "user-a")
        XCTAssertEqual(subject.getCurrentUserId(), "user-a")
    }

    private func makeUser(id: String, apiKey: String = "test-key-not-a-credential") -> SecureUser {
        return SecureUser(userId: id,
                          username: "test-user",
                          instance: "example.invalid",
                          apiKey: apiKey)
    }
}
