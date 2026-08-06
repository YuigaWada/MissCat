//
//  MissCatTests.swift
//  MissCatTests
//
//  Created by Yuiga Wada on 2019/11/07.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

@testable import MissCat
import MisskeyKit
import UIKit
import WebKit
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

final class InstanceEditorBehaviorTests: XCTestCase {
    func testNormalizationMatchesLegacyInstanceShaping() {
        XCTAssertEqual(
            MissCatInstanceEditorView.normalize(" https://misskey.io/ "),
            "misskey.io/"
        )
        XCTAssertEqual(MissCatInstanceEditorView.normalize("mi ss　key.io"), "misskey.io")
    }

    func testOnlyAnActuallyEmptyFieldFallsBackToMisskeyIO() {
        XCTAssertEqual(MissCatInstanceEditorView.resolve(""), "misskey.io")
        XCTAssertEqual(MissCatInstanceEditorView.resolve("  "), "")
    }
}

final class AuthenticationCallbackSecurityTests: XCTestCase {
    private let expected = "https://misscat.dev"
    private let sessionID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    func testExactAndNormalizedCallbackOriginsMatch() throws {
        XCTAssertTrue(matches("https://misscat.dev?session=11111111-2222-3333-4444-555555555555"))
        XCTAssertTrue(matches("https://MISSCAT.DEV:443/?session=11111111-2222-3333-4444-555555555555"))
    }

    func testSchemePortPathSessionAndShapeMustMatch() throws {
        XCTAssertFalse(matches("https://misscat.dev"))
        XCTAssertFalse(matches("http://misscat.dev?session=11111111-2222-3333-4444-555555555555"))
        XCTAssertFalse(matches("https://misscat.dev:444/?session=11111111-2222-3333-4444-555555555555"))
        XCTAssertFalse(matches("https://misscat.dev/callback?session=11111111-2222-3333-4444-555555555555"))
        XCTAssertFalse(matches("https://misscat.dev/?session=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"))
        XCTAssertFalse(matches("https://misscat.dev/?session=11111111-2222-3333-4444-555555555555&extra=true"))
        XCTAssertFalse(matches("https://misscat.dev/?session=11111111-2222-3333-4444-555555555555#complete"))
    }

    func testLookalikeEmbeddedAndEncodedCallbackURLsDoNotMatch() throws {
        let query = "session=11111111-2222-3333-4444-555555555555"
        XCTAssertFalse(matches("https://misscat.dev.evil.invalid/?\(query)"))
        XCTAssertFalse(matches("https://misscat.dev@evil.invalid/?\(query)"))
        XCTAssertFalse(matches("https://evil.invalid/?next=https://misscat.dev&\(query)"))
        XCTAssertFalse(matches("https://evil.invalid/#https://misscat.dev?\(query)"))
        XCTAssertFalse(matches("https://evil.invalid/https%3A%2F%2Fmisscat.dev?\(query)"))
        XCTAssertFalse(matches("https://%6Disscat.dev/?\(query)"))
        XCTAssertFalse(matches("https://misscat.dev/?%73ession=11111111-2222-3333-4444-555555555555"))
    }

    func testCallbackGateReportsOnlyTheFirstMatchingNavigation() throws {
        var gate = MissCatAuthenticationCallbackGate()
        let attacker = try XCTUnwrap(URL(string: "https://evil.invalid/?next=https://misscat.dev"))
        let callback = try XCTUnwrap(URL(string: "https://misscat.dev?session=11111111-2222-3333-4444-555555555555"))
        let duplicate = try XCTUnwrap(URL(string: "https://misscat.dev/?session=11111111-2222-3333-4444-555555555555"))
        let matcher: (URL) -> Bool = {
            MissCatAuthenticationCallbackMatcher.matches(
                $0,
                expectedURLString: self.expected,
                expectedSessionID: self.sessionID
            )
        }

        XCTAssertFalse(gate.shouldReport(attacker, matching: matcher))
        XCTAssertTrue(gate.shouldReport(callback, matching: matcher))
        XCTAssertFalse(gate.shouldReport(callback, matching: matcher))
        XCTAssertFalse(gate.shouldReport(duplicate, matching: matcher))
    }

    private func matches(_ value: String) -> Bool {
        guard let url = URL(string: value) else { return false }
        return MissCatAuthenticationCallbackMatcher.matches(
            url,
            expectedURLString: expected,
            expectedSessionID: sessionID
        )
    }
}

@MainActor
final class AuthenticationWebsiteDataPolicyTests: XCTestCase {
    private let loginRequest = URLRequest(
        url: URL(string: "https://misskey.io/miauth/test-session")!
    )

    func testAuthenticationBrowserDefaultsToPreservingWebsiteData() {
        let browser = MissCatAuthenticationBrowserView(
            request: loginRequest,
            callbackMatches: { _ in false },
            onCallback: { _ in }
        )

        XCTAssertEqual(browser.websiteDataPolicy, .preserveSession)
    }

    func testNormalAuthenticationUsesPersistentDefaultWebsiteDataStore() {
        let configuration = MissCatAuthenticationBrowserPolicy.configuration()

        XCTAssertTrue(configuration.websiteDataStore.isPersistent)
        XCTAssertTrue(configuration.websiteDataStore === WKWebsiteDataStore.default())
    }

    func testNormalLoginRetryAndRelaunchNeverClearWebsiteData() {
        var loadCount = 0
        var clearedHosts: [String] = []

        for _ in 0..<3 {
            let plan = MissCatAuthenticationBrowserPolicy.initialLoadPlan(
                for: loginRequest,
                websiteDataPolicy: .preserveSession
            )
            MissCatAuthenticationBrowserPolicy.performInitialLoad(
                plan: plan,
                load: { loadCount += 1 },
                clearSelectedInstance: { host, completion in
                    clearedHosts.append(host)
                    completion()
                }
            )
        }

        XCTAssertEqual(loadCount, 3)
        XCTAssertTrue(clearedHosts.isEmpty)
    }

    func testWebsiteDataClearingRequiresExplicitAccountSwitchAndLoadsOnce() {
        let plan = MissCatAuthenticationBrowserPolicy.initialLoadPlan(
            for: loginRequest,
            websiteDataPolicy: .clearForExplicitAccountSwitch
        )
        var loadCount = 0
        var clearedHosts: [String] = []

        MissCatAuthenticationBrowserPolicy.performInitialLoad(
            plan: plan,
            load: { loadCount += 1 },
            clearSelectedInstance: { host, completion in
                clearedHosts.append(host)
                completion()
            }
        )

        XCTAssertEqual(clearedHosts, ["misskey.io"])
        XCTAssertEqual(loadCount, 1)
    }

    func testExplicitClearScopesRecordsToSelectedInstanceDomain() {
        XCTAssertTrue(MissCatAuthenticationBrowserPolicy.shouldClearRecord(
            displayName: "misskey.io",
            selectedHost: "misskey.io"
        ))
        XCTAssertTrue(MissCatAuthenticationBrowserPolicy.shouldClearRecord(
            displayName: ".misskey.io",
            selectedHost: "auth.misskey.io"
        ))
        XCTAssertFalse(MissCatAuthenticationBrowserPolicy.shouldClearRecord(
            displayName: "misskey.io.evil.invalid",
            selectedHost: "misskey.io"
        ))
        XCTAssertFalse(MissCatAuthenticationBrowserPolicy.shouldClearRecord(
            displayName: "",
            selectedHost: "misskey.io"
        ))
    }

    func testInvalidExplicitClearRequestFallsBackToNonDestructiveLoad() {
        let request = URLRequest(url: URL(string: "about:blank")!)

        XCTAssertEqual(
            MissCatAuthenticationBrowserPolicy.initialLoadPlan(
                for: request,
                websiteDataPolicy: .clearForExplicitAccountSwitch
            ),
            .loadImmediately
        )
    }
}

private enum FakeMiAuthTransportError: Error {
    case failed
}

private final class FakeMiAuthTransport: MissCatMiAuthTransport {
    var results: [Result<MissCatMiAuthHTTPResponse, Error>]
    private(set) var requests: [URLRequest] = []

    init(results: [Result<MissCatMiAuthHTTPResponse, Error>]) {
        self.results = results
    }

    func send(_ request: URLRequest) async throws -> MissCatMiAuthHTTPResponse {
        requests.append(request)
        guard !results.isEmpty else { throw FakeMiAuthTransportError.failed }
        return try results.removeFirst().get()
    }
}

private final class FakeAuthenticationAccountStore: MissCatAuthenticationAccountStoring {
    var saveShouldSucceed = true
    var verificationShouldSucceed = true
    private(set) var savedUser: SecureUser?
    private(set) var currentUserID: String?

    func saveUser(_ user: SecureUser) -> Bool {
        guard saveShouldSucceed else { return false }
        savedUser = SecureUser(
            userId: user.userId,
            username: user.username,
            instance: user.instance,
            apiKey: user.apiKey
        )
        return true
    }

    func changeCurrentUser(userId id: String) {
        currentUserID = id
    }

    func getUser(userId: String) -> SecureUser? {
        guard verificationShouldSucceed,
              savedUser?.userId == userId,
              let savedUser
        else { return nil }
        return SecureUser(
            userId: savedUser.userId,
            username: savedUser.username,
            instance: savedUser.instance,
            apiKey: savedUser.apiKey
        )
    }
}

private final class UUIDSequence {
    private var values: [UUID]

    init(_ values: [UUID]) {
        self.values = values
    }

    func next() -> UUID {
        precondition(!values.isEmpty)
        return values.removeFirst()
    }
}

@MainActor
final class MiAuthAuthenticationTests: XCTestCase {
    private let firstSession = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let secondSession = UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!
    private let testToken = "unit-test-token-not-a-real-credential"

    func testAuthorizationURLUsesNormalizedHTTPSInstanceAndEncodedOptions() async throws {
        let fixture = makeFixture()

        let request = try await fixture.service.makeAuthorizationRequest(
            intent: .logIn,
            instance: "  https://MISSKEY.IO:443/  "
        )
        let url = try XCTUnwrap(request.url)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })

        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "misskey.io")
        XCTAssertEqual(url.path, "/miauth/11111111-2222-3333-4444-555555555555")
        XCTAssertEqual(items["name"]!, "MissCat")
        XCTAssertEqual(items["callback"]!, MissCatAuthenticationService.callbackURLString)
        XCTAssertEqual(items["permission"]!, MissCatAuthenticationService.appPermissions.joined(separator: ","))
        XCTAssertTrue(url.absoluteString.contains("callback=https://misscat.dev"))
        XCTAssertTrue(url.absoluteString.contains("permission=read:account"))
    }

    func testAuthorizationPermissionsCoverCurrentAndLegacyChatContracts() {
        let permissions = MissCatAuthenticationService.appPermissions

        XCTAssertEqual(Set(permissions).count, permissions.count)
        XCTAssertTrue(permissions.contains("read:chat"))
        XCTAssertTrue(permissions.contains("write:chat"))
        XCTAssertTrue(permissions.contains("read:messaging"))
        XCTAssertTrue(permissions.contains("write:messaging"))
    }

    func testEveryLoginAttemptUsesAFreshUUID() async throws {
        let fixture = makeFixture(sessionIDs: [firstSession, secondSession])

        let first = try await fixture.service.makeAuthorizationRequest(intent: .logIn, instance: "misskey.io")
        let second = try await fixture.service.makeAuthorizationRequest(intent: .logIn, instance: "misskey.io")

        XCTAssertEqual(first.url?.path, "/miauth/11111111-2222-3333-4444-555555555555")
        XCTAssertEqual(second.url?.path, "/miauth/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
        XCTAssertNotEqual(first.url, second.url)
    }

    func testInstanceNormalizationRejectsNonHTTPSAndURLSmuggling() throws {
        XCTAssertEqual(try MissCatInstance.normalize("misskey.io").identifier, "misskey.io")
        XCTAssertEqual(try MissCatInstance.normalize("https://MISSKEY.IO:443/").identifier, "misskey.io")
        XCTAssertEqual(try MissCatInstance.normalize("misskey.example:8443").identifier, "misskey.example:8443")

        for invalid in [
            "http://misskey.io",
            "https://user@misskey.io",
            "https://misskey.io/path",
            "https://misskey.io?next=evil.invalid",
            "https://misskey.io#fragment",
            "https://misskey.io.",
            "https://%6Disskey.io"
        ] {
            XCTAssertThrowsError(try MissCatInstance.normalize(invalid), invalid)
        }
    }

    func testSignUpStartsAtInstanceRootThenCreatesMiAuthSessionWithoutUsingWebToken() async throws {
        let fixture = makeFixture()

        let signUp = try await fixture.service.makeAuthorizationRequest(intent: .signUp, instance: "misskey.io")
        XCTAssertEqual(signUp.url?.absoluteString, "https://misskey.io")

        let login = try await fixture.service.makeLoginRequestAfterSignUp(instance: "misskey.io")
        XCTAssertEqual(login.url?.path, "/miauth/11111111-2222-3333-4444-555555555555")
        await XCTAssertThrowsAuthenticationError(.expiredSession) {
            _ = try await fixture.service.makeLoginRequestAfterSignUp(instance: "evil.invalid")
        }
    }

    func testSuccessfulCheckDecodesOnlyMinimalUserAndInstallsPersistedCredential() async throws {
        let body = """
        {
          "ok": true,
          "token": "\(testToken)",
          "user": {
            "id": "user-1",
            "username": "wada",
            "avatarUrl": {"future": "shape"},
            "roles": "changed-server-field",
            "followersCount": [1, 2, 3]
          },
          "futureTopLevelField": {"anything": true}
        }
        """
        let fixture = makeFixture(results: [.success(response(body))])
        let callback = try await startAndMakeCallback(fixture.service, sessionID: firstSession)

        let user = try await fixture.service.completeAuthentication(callbackURL: callback)

        XCTAssertEqual(user.userId, "user-1")
        XCTAssertEqual(user.username, "wada")
        XCTAssertEqual(user.instance, "misskey.io")
        XCTAssertEqual(user.apiKey, testToken)
        XCTAssertEqual(fixture.store.currentUserID, "user-1")
        XCTAssertEqual(fixture.misskey.auth.getAPIKey(), testToken)
        XCTAssertEqual(fixture.transport.requests.count, 1)
        XCTAssertEqual(fixture.transport.requests.first?.httpMethod, "POST")
        XCTAssertEqual(
            fixture.transport.requests.first?.url?.path,
            "/api/miauth/11111111-2222-3333-4444-555555555555/check"
        )
        XCTAssertEqual(fixture.transport.requests.first?.httpBody, Data("{}".utf8))
        XCTAssertFalse(fixture.service.callbackMatches(callback))
    }

    func testCheckIsExactlyOnceAndCallbackCannotBeReplayed() async throws {
        let fixture = makeFixture(results: [.success(successResponse())])
        let callback = try await startAndMakeCallback(fixture.service, sessionID: firstSession)

        _ = try await fixture.service.completeAuthentication(callbackURL: callback)
        await XCTAssertThrowsAuthenticationError(.invalidCallback) {
            _ = try await fixture.service.completeAuthentication(callbackURL: callback)
        }

        XCTAssertEqual(fixture.transport.requests.count, 1)
    }

    func testDeniedMissingTokenAndMissingUserAreDistinctErrors() async throws {
        let cases: [(String, MissCatAuthenticationService.AuthenticationError)] = [
            ("{\"ok\":false}", .authorizationDenied),
            ("{\"ok\":true,\"user\":{\"id\":\"u\",\"username\":\"wada\"}}", .missingAccessToken),
            ("{\"ok\":true,\"token\":\"t\"}", .missingUser)
        ]

        for (body, expectedError) in cases {
            let fixture = makeFixture(results: [.success(response(body))])
            let callback = try await startAndMakeCallback(fixture.service, sessionID: firstSession)
            await XCTAssertThrowsAuthenticationError(expectedError) {
                _ = try await fixture.service.completeAuthentication(callbackURL: callback)
            }
            XCTAssertEqual(fixture.transport.requests.count, 1)
        }
    }

    func testHTTPNonJSONAndTransportFailuresAreDistinctErrors() async throws {
        let cases: [(Result<MissCatMiAuthHTTPResponse, Error>, MissCatAuthenticationService.AuthenticationError)] = [
            (.success(response("server unavailable", statusCode: 503)), .serverRejected(statusCode: 503)),
            (.success(response("<html>not json</html>")), .invalidServerResponse),
            (.failure(FakeMiAuthTransportError.failed), .requestFailed)
        ]

        for (result, expectedError) in cases {
            let fixture = makeFixture(results: [result])
            let callback = try await startAndMakeCallback(fixture.service, sessionID: firstSession)
            await XCTAssertThrowsAuthenticationError(expectedError) {
                _ = try await fixture.service.completeAuthentication(callbackURL: callback)
            }
        }
    }

    func testPersistenceMustVerifyBeforeCredentialIsInstalled() async throws {
        let fixture = makeFixture(results: [.success(successResponse())])
        fixture.store.verificationShouldSucceed = false
        let callback = try await startAndMakeCallback(fixture.service, sessionID: firstSession)

        await XCTAssertThrowsAuthenticationError(.couldNotPersistAccount) {
            _ = try await fixture.service.completeAuthentication(callbackURL: callback)
        }

        XCTAssertNil(fixture.misskey.auth.getAPIKey())
        XCTAssertEqual(fixture.transport.requests.count, 1)
    }

    func testUserInitiatedRetryAfterFailureRequiresNewSessionAndRejectsOldCallback() async throws {
        let fixture = makeFixture(
            results: [
                .success(response("unavailable", statusCode: 503)),
                .success(successResponse())
            ],
            sessionIDs: [firstSession, secondSession]
        )
        let oldCallback = try await startAndMakeCallback(fixture.service, sessionID: firstSession)
        await XCTAssertThrowsAuthenticationError(.serverRejected(statusCode: 503)) {
            _ = try await fixture.service.completeAuthentication(callbackURL: oldCallback)
        }

        // Failure alone must not create or check another server-side session.
        await Task.yield()
        XCTAssertEqual(fixture.transport.requests.count, 1)
        XCTAssertFalse(fixture.service.callbackMatches(oldCallback))

        _ = try await fixture.service.makeAuthorizationRequest(intent: .logIn, instance: "misskey.io")
        let newCallback = callbackURL(sessionID: secondSession)
        XCTAssertEqual(fixture.transport.requests.count, 1)
        XCTAssertFalse(fixture.service.callbackMatches(oldCallback))
        XCTAssertTrue(fixture.service.callbackMatches(newCallback))

        _ = try await fixture.service.completeAuthentication(callbackURL: newCallback)
        XCTAssertEqual(fixture.transport.requests.count, 2)
        XCTAssertEqual(fixture.transport.requests.last?.url?.path, "/api/miauth/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee/check")
    }

    private typealias Fixture = (
        service: MissCatAuthenticationService,
        transport: FakeMiAuthTransport,
        store: FakeAuthenticationAccountStore,
        misskey: MisskeyKit
    )

    private func makeFixture(
        results: [Result<MissCatMiAuthHTTPResponse, Error>] = [],
        sessionIDs: [UUID]? = nil
    ) -> Fixture {
        let transport = FakeMiAuthTransport(results: results)
        let store = FakeAuthenticationAccountStore()
        let misskey = MisskeyKit()
        let sequence = UUIDSequence(sessionIDs ?? [firstSession])
        let service = MissCatAuthenticationService(
            misskey: misskey,
            transport: transport,
            uuidGenerator: sequence.next,
            accountStore: store,
            performsPostLoginActions: false
        )
        return (service, transport, store, misskey)
    }

    private func startAndMakeCallback(
        _ service: MissCatAuthenticationService,
        sessionID: UUID
    ) async throws -> URL {
        _ = try await service.makeAuthorizationRequest(intent: .logIn, instance: "misskey.io")
        let callback = callbackURL(sessionID: sessionID)
        XCTAssertTrue(service.callbackMatches(callback))
        return callback
    }

    private func callbackURL(sessionID: UUID) -> URL {
        URL(string: "https://misscat.dev?session=\(sessionID.uuidString.lowercased())")!
    }

    private func successResponse() -> MissCatMiAuthHTTPResponse {
        response("{\"ok\":true,\"token\":\"\(testToken)\",\"user\":{\"id\":\"user-1\",\"username\":\"wada\"}}")
    }

    private func response(_ body: String, statusCode: Int = 200) -> MissCatMiAuthHTTPResponse {
        MissCatMiAuthHTTPResponse(data: Data(body.utf8), statusCode: statusCode)
    }

    private func XCTAssertThrowsAuthenticationError<T>(
        _ expected: MissCatAuthenticationService.AuthenticationError,
        operation: () async throws -> T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as MissCatAuthenticationService.AuthenticationError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
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
