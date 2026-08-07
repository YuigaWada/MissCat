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

final class AccountsListStoryboardRegressionTests: XCTestCase {
    func testAccountsListSceneInstantiatesAndLoadsWithoutStaleOutlets() {
        XCTAssertTrue(Thread.isMainThread)

        let storyboard = UIStoryboard(
            name: "Main",
            bundle: Bundle(for: AccountsListViewController.self)
        )
        let viewController = storyboard.instantiateViewController(withIdentifier: "accounts-list")

        XCTAssertTrue(viewController is AccountsListViewController)
        viewController.loadViewIfNeeded()
        XCTAssertNotNil(viewController.view)
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
        XCTAssertEqual(layout.backgroundOffsetY, 0, accuracy: 0.001)
        XCTAssertEqual(layout.gradientStartPoint.x, -0.324067, accuracy: 0.000001)
        XCTAssertEqual(layout.gradientStartPoint.y, 0.675933, accuracy: 0.000001)
        XCTAssertEqual(layout.gradientEndPoint.x, 1.324067, accuracy: 0.000001)
        XCTAssertEqual(layout.gradientEndPoint.y, 0.324067, accuracy: 0.000001)
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

    func installAuthenticatedUser(_ user: SecureUser) -> SecureUser? {
        guard saveShouldSucceed else { return nil }
        let previousUser = savedUser
        let previousCurrentUserID = currentUserID
        savedUser = SecureUser(
            userId: user.userId,
            username: user.username,
            instance: user.instance,
            apiKey: user.apiKey
        )
        currentUserID = user.accountIdentifier
        guard verificationShouldSucceed, let savedUser else {
            self.savedUser = previousUser
            currentUserID = previousCurrentUserID
            return nil
        }
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

    func testMiAuthCheckResponseAndIdentityRequestPreserveExactTokenAndInstance() throws {
        let token = UUID().uuidString + "/" + UUID().uuidString
        let responseData = try JSONSerialization.data(withJSONObject: [
            "ok": true,
            "token": token,
            "user": ["id": "server-user-id", "username": "fixture-user"]
        ])

        let response = try JSONDecoder().decode(MissCatMiAuthCheckResponse.self, from: responseData)
        let decodedToken = try XCTUnwrap(response.token)
        XCTAssertTrue(decodedToken == token)

        let request = try MissCatAuthenticatedIdentityRequestBuilder.request(
            instance: "https://AUTH.Example.invalid:8443/",
            accessToken: decodedToken
        )
        XCTAssertTrue(request.url?.scheme == "https")
        XCTAssertTrue(request.url?.host == "auth.example.invalid")
        XCTAssertTrue(request.url?.port == 8443)
        XCTAssertTrue(request.url?.path == "/api/i")
        XCTAssertTrue(request.httpMethod == "POST")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Authorization") == "Bearer " + token)
        XCTAssertTrue(request.httpBody == Data("{}".utf8))
        XCTAssertFalse(request.httpBody?.range(of: Data(token.utf8)) != nil)
    }

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

    func testAuthorizationPermissionsCoverEveryTimelineMutation() {
        let permissions = Set(MissCatAuthenticationService.appPermissions)
        let requiredTimelinePermissions: Set<String> = [
            "write:notes",
            "write:reactions",
            "write:favorites",
            "write:mutes",
            "write:blocks",
            "write:report-abuse",
            "write:votes"
        ]

        XCTAssertTrue(
            requiredTimelinePermissions.isSubset(of: permissions),
            "Missing timeline permissions: \(requiredTimelinePermissions.subtracting(permissions).sorted())"
        )
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
        XCTAssertEqual(
            fixture.store.currentUserID,
            MissCatAccountIdentity.storageKey(instance: "misskey.io", userId: "user-1")
        )
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
        XCTAssertNil(fixture.store.savedUser)
        XCTAssertNil(fixture.store.currentUserID)
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
    var writeFailureAccountIDs: Set<String> = []
    var listedAccountIDs: [String]?
    var corruptAccountIDs: Set<String> = []
    var readResults: [String: [String?]] = [:]
    var removeFailureAccountIDs: Set<String> = []
    var onSet: ((String, String) -> Void)?
    private(set) var setCounts: [String: Int] = [:]

    func apiKey(for accountID: String) throws -> String? {
        if readShouldFail { throw FakeAPIKeyStoreError.readFailed }
        if corruptAccountIDs.contains(accountID) { return nil }
        if var queued = readResults[accountID], !queued.isEmpty {
            let result = queued.removeFirst()
            readResults[accountID] = queued
            return result
        }
        return values[accountID]
    }

    func setAPIKey(_ apiKey: String, for accountID: String) throws {
        if writeShouldFail || writeFailureAccountIDs.contains(accountID) {
            throw FakeAPIKeyStoreError.writeFailed
        }
        setCounts[accountID, default: 0] += 1
        values[accountID] = apiKey
        onSet?(accountID, apiKey)
    }

    func removeAPIKey(for accountID: String) throws {
        if removeShouldFail || removeFailureAccountIDs.contains(accountID) {
            throw FakeAPIKeyStoreError.removeFailed
        }
        values.removeValue(forKey: accountID)
    }

    func allAccountIDs() throws -> [String] {
        listedAccountIDs ?? Array(values.keys)
    }
}

private final class FakeAccountDefaultsStore: AccountDefaultsStoring {
    var values: [String: Any] = [:]
    var forcedDataValues: [String: Data] = [:]
    var forcedNilDataKeys: Set<String> = []
    var forcedStringValues: [String: String] = [:]
    var forcedNilStringKeys: Set<String> = []
    var blockedSetKeys: Set<String> = []
    var blockedRemoveKeys: Set<String> = []
    var synchronizes = true
    var synchronizeResults: [Bool] = []

    func object(forKey defaultName: String) -> Any? {
        values[defaultName]
    }

    func data(forKey defaultName: String) -> Data? {
        if forcedNilDataKeys.contains(defaultName) { return nil }
        if let forced = forcedDataValues[defaultName] { return forced }
        return values[defaultName] as? Data
    }

    func string(forKey defaultName: String) -> String? {
        if forcedNilStringKeys.contains(defaultName) { return nil }
        if let forced = forcedStringValues[defaultName] { return forced }
        return values[defaultName] as? String
    }

    func set(_ value: Any?, forKey defaultName: String) {
        guard !blockedSetKeys.contains(defaultName) else { return }
        values[defaultName] = value
    }

    func removeObject(forKey defaultName: String) {
        guard !blockedRemoveKeys.contains(defaultName) else { return }
        values.removeValue(forKey: defaultName)
    }

    func synchronize() -> Bool {
        if !synchronizeResults.isEmpty { return synchronizeResults.removeFirst() }
        return synchronizes
    }
}

private struct LegacyAccountPersistenceRecoveryJournalFixture: Encodable {
    enum Phase: String, Encodable {
        case preparing
        case rollbackRequired
        case commitRequired
    }

    let transactionID: String
    let accountID: String
    let previousMetadata: Data?
    let previousCurrentAccountID: String?
    let desiredMetadata: Data
    let desiredCurrentAccountID: String?
    let hadPreviousAPIKey: Bool
    let backupKey: String
    let proposedKey: String
    let phase: Phase
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
        XCTAssertEqual(keyStore.values[user.accountIdentifier], testAPIKey)
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
        XCTAssertEqual(keyStore.values[makeUser(id: "user-a").accountIdentifier], testAPIKey)
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
        XCTAssertEqual(subject.getCurrentUserId(), makeUser(id: "user-b").accountIdentifier)

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
        XCTAssertEqual(
            keyStore.values[makeUser(id: "user-a").accountIdentifier],
            "test-key-not-a-credential"
        )
        XCTAssertEqual(subject.getCurrentUserId(), makeUser(id: "user-a").accountIdentifier)
    }

    func testDeleteDefaultsFailureRollsBackCredentialMetadataAndCurrentSelection() throws {
        let defaultsStore = FakeAccountDefaultsStore()
        let store = FakeAPIKeyStore()
        let localSubject = Cache.UserDefaults(defaultsStore: defaultsStore, apiKeyStore: store)
        let user = makeUser(id: "delete-defaults")
        XCTAssertTrue(localSubject.saveUser(user))
        XCTAssertTrue(localSubject.changeCurrentUser(userId: user.accountIdentifier))
        defaultsStore.blockedSetKeys = ["saved-user"]

        XCTAssertFalse(localSubject.removeUser(userId: user.accountIdentifier))

        defaultsStore.blockedSetKeys = []
        let recovered = try localSubject.getUsersThrowing()
        XCTAssertEqual(recovered.map(\.accountIdentifier), [user.accountIdentifier])
        XCTAssertEqual(store.values[user.accountIdentifier], "test-key-not-a-credential")
        XCTAssertEqual(localSubject.getCurrentUserId(), user.accountIdentifier)
        XCTAssertNil(defaultsStore.values["account-persistence-recovery-v1"])
    }

    func testDeleteFalseSynchronizeRollsBackBeforeCanonicalCredentialDeletion() throws {
        let defaultsStore = FakeAccountDefaultsStore()
        let store = FakeAPIKeyStore()
        let localSubject = Cache.UserDefaults(defaultsStore: defaultsStore, apiKeyStore: store)
        let user = makeUser(id: "delete-sync")
        XCTAssertTrue(localSubject.saveUser(user))
        XCTAssertTrue(localSubject.changeCurrentUser(userId: user.accountIdentifier))
        // preparing journal, rollback journal, then desired metadata/current.
        defaultsStore.synchronizeResults = [true, true, false]

        XCTAssertFalse(localSubject.removeUser(userId: user.accountIdentifier))

        let recovered = try localSubject.getUsersThrowing()
        XCTAssertEqual(recovered.map(\.accountIdentifier), [user.accountIdentifier])
        XCTAssertEqual(store.values[user.accountIdentifier], "test-key-not-a-credential")
        XCTAssertEqual(localSubject.getCurrentUserId(), user.accountIdentifier)
    }

    func testInterruptedDeletePreparingPhaseLeavesOriginalAccountIntact() throws {
        let defaultsStore = FakeAccountDefaultsStore()
        let store = FakeAPIKeyStore()
        let localSubject = Cache.UserDefaults(defaultsStore: defaultsStore, apiKeyStore: store)
        let user = makeUser(id: "delete-preparing")
        XCTAssertTrue(localSubject.saveUser(user))
        store.writeShouldFail = true

        XCTAssertFalse(localSubject.removeUser(userId: user.accountIdentifier))

        store.writeShouldFail = false
        let recovered = try localSubject.getUsersThrowing()
        XCTAssertEqual(recovered.map(\.accountIdentifier), [user.accountIdentifier])
        XCTAssertEqual(store.values[user.accountIdentifier], "test-key-not-a-credential")
    }

    func testInterruptedCommittedDeleteFinishesWithoutCredentialResurrection() throws {
        let defaultsStore = FakeAccountDefaultsStore()
        let store = FakeAPIKeyStore()
        let localSubject = Cache.UserDefaults(defaultsStore: defaultsStore, apiKeyStore: store)
        let user = makeUser(id: "delete-commit")
        XCTAssertTrue(localSubject.saveUser(user))
        defaultsStore.blockedRemoveKeys = ["account-persistence-recovery-v1"]

        XCTAssertFalse(localSubject.removeUser(userId: user.accountIdentifier))
        XCTAssertNil(store.values[user.accountIdentifier])
        let journal = try XCTUnwrap(defaultsStore.values["account-persistence-recovery-v1"] as? Data)
        XCTAssertNil(journal.range(of: Data("test-key-not-a-credential".utf8)))

        defaultsStore.blockedRemoveKeys = []
        let resumed = Cache.UserDefaults(defaultsStore: defaultsStore, apiKeyStore: store)
        XCTAssertTrue(try resumed.getUsersThrowing().isEmpty)
        XCTAssertNil(store.values[user.accountIdentifier])
        XCTAssertNil(defaultsStore.values["account-persistence-recovery-v1"])
    }

    func testCommittedDeleteStagingCleanupFailureRemainsFailClosedUntilRetry() throws {
        let defaultsStore = FakeAccountDefaultsStore()
        let store = FakeAPIKeyStore()
        let localSubject = Cache.UserDefaults(defaultsStore: defaultsStore, apiKeyStore: store)
        let user = makeUser(id: "delete-cleanup")
        XCTAssertTrue(localSubject.saveUser(user))
        var backupKey: String?
        store.onSet = { accountID, _ in
            guard accountID.hasPrefix("__MissCatAccountPersistenceStaging.v1."),
                  accountID.hasSuffix(".backup") else { return }
            backupKey = accountID
            store.removeFailureAccountIDs.insert(accountID)
        }

        XCTAssertFalse(localSubject.removeUser(userId: user.accountIdentifier))
        XCTAssertNil(store.values[user.accountIdentifier])
        XCTAssertNotNil(defaultsStore.values["account-persistence-recovery-v1"])
        XCTAssertTrue(localSubject.getUsers().isEmpty)
        let stagedKey = try XCTUnwrap(backupKey)
        XCTAssertNotNil(store.values[stagedKey])

        store.onSet = nil
        store.removeFailureAccountIDs = []
        let resumed = Cache.UserDefaults(defaultsStore: defaultsStore, apiKeyStore: store)
        XCTAssertTrue(try resumed.getUsersThrowing().isEmpty)
        XCTAssertNil(store.values[stagedKey])
        XCTAssertNil(defaultsStore.values["account-persistence-recovery-v1"])
    }

    func testLegacyJournalWithoutOperationReplaysAsUpsert() throws {
        let defaultsStore = FakeAccountDefaultsStore()
        let store = FakeAPIKeyStore()
        let localSubject = Cache.UserDefaults(defaultsStore: defaultsStore, apiKeyStore: store)
        let user = makeUser(id: "legacy-journal")
        let desiredMetadata = try JSONEncoder().encode([
            SecureUser(
                userId: user.userId,
                username: user.username,
                instance: user.instance,
                apiKey: nil
            )
        ])
        let proposedKey = "misscat.persistence.staging.legacy.proposed"
        let backupKey = "misscat.persistence.staging.legacy.backup"
        store.values[proposedKey] = "legacy-proposed-key-not-a-credential"
        let fixture = LegacyAccountPersistenceRecoveryJournalFixture(
            transactionID: "legacy",
            accountID: user.accountIdentifier,
            previousMetadata: nil,
            previousCurrentAccountID: nil,
            desiredMetadata: desiredMetadata,
            desiredCurrentAccountID: user.accountIdentifier,
            hadPreviousAPIKey: false,
            backupKey: backupKey,
            proposedKey: proposedKey,
            phase: .commitRequired
        )
        defaultsStore.values["account-persistence-recovery-v1"] = try JSONEncoder().encode(fixture)

        let recovered = try localSubject.getUsersThrowing()

        XCTAssertEqual(recovered.map(\.accountIdentifier), [user.accountIdentifier])
        XCTAssertEqual(recovered.first?.apiKey, "legacy-proposed-key-not-a-credential")
        XCTAssertNil(store.values[proposedKey])
        XCTAssertNil(defaultsStore.values["account-persistence-recovery-v1"])
    }

    func testCurrentSelectionSynchronizeFailureRestoresPreviousValue() {
        let defaultsStore = FakeAccountDefaultsStore()
        let store = FakeAPIKeyStore()
        let localSubject = Cache.UserDefaults(defaultsStore: defaultsStore, apiKeyStore: store)
        let user = makeUser(id: "selection-sync")
        XCTAssertTrue(localSubject.saveUser(user))
        defaultsStore.synchronizes = false

        XCTAssertFalse(localSubject.changeCurrentUser(userId: user.accountIdentifier))
        XCTAssertNil(localSubject.getCurrentUserId())
    }

    func testCurrentUserRepairsStaleIdentifierDeterministically() {
        XCTAssertTrue(subject.saveUser(makeUser(id: "user-a")))
        XCTAssertTrue(subject.saveUser(makeUser(id: "user-b")))
        subject.changeCurrentUser(userId: "missing-user")

        XCTAssertEqual(subject.getCurrentUser()?.userId, "user-a")
        XCTAssertEqual(subject.getCurrentUserId(), makeUser(id: "user-a").accountIdentifier)
    }

    func testInvalidAccountSwitchLeavesCurrentSelectionUnchanged() {
        let existing = makeUser(id: "existing")
        XCTAssertTrue(subject.saveUser(existing))
        XCTAssertTrue(subject.changeCurrentUser(userId: existing.accountIdentifier))

        XCTAssertFalse(subject.changeCurrentUser(userId: "missing-account"))

        XCTAssertEqual(subject.getCurrentUserId(), existing.accountIdentifier)
    }

    func testSameUserIDOnDifferentInstancesUsesIsolatedMetadataKeysAndSelection() throws {
        let first = makeUser(id: "shared-id", instance: "https://ONE.example:443/")
        let second = makeUser(id: "shared-id", instance: "two.example", apiKey: "second-test-key")

        XCTAssertTrue(subject.saveUser(first))
        XCTAssertTrue(subject.saveUser(second))

        let users = subject.getUsers()
        XCTAssertEqual(Set(users.map(\.accountIdentifier)), Set([first.accountIdentifier, second.accountIdentifier]))
        XCTAssertEqual(keyStore.values[first.accountIdentifier], "test-key-not-a-credential")
        XCTAssertEqual(keyStore.values[second.accountIdentifier], "second-test-key")

        subject.changeCurrentUser(userId: second.accountIdentifier)
        XCTAssertEqual(subject.getCurrentUserId(), second.accountIdentifier)
        XCTAssertEqual(subject.getCurrentUser()?.instance, "two.example")

        XCTAssertTrue(subject.removeUser(userId: first.accountIdentifier))
        XCTAssertEqual(subject.getUsers().map(\.accountIdentifier), [second.accountIdentifier])
        XCTAssertEqual(keyStore.values[second.accountIdentifier], "second-test-key")
    }

    func testLegacyUserIDKeyAndCurrentSelectionMigrateToNormalizedCompoundIdentity() throws {
        let legacy = makeUser(id: "legacy-id", instance: "https://EXAMPLE.invalid:443/")
        defaults.set(try JSONEncoder().encode([legacy]), forKey: "saved-user")
        defaults.set("legacy-id", forKey: "current-user-id")
        keyStore.values["legacy-id"] = "legacy-key-not-a-credential"

        let users = try subject.getUsersThrowing()
        let migrated = try XCTUnwrap(users.first)

        XCTAssertEqual(migrated.instance, "example.invalid")
        XCTAssertEqual(keyStore.values[migrated.accountIdentifier], "legacy-key-not-a-credential")
        XCTAssertEqual(subject.getCurrentUserId(), migrated.accountIdentifier)
    }

    func testNormalizedDuplicateMetadataKeepsLastEntryOnly() throws {
        let first = makeUser(id: "same", instance: "https://EXAMPLE.invalid/")
        let replacement = SecureUser(
            userId: "same",
            username: "replacement",
            instance: "example.invalid",
            apiKey: nil
        )
        defaults.set(try JSONEncoder().encode([first, replacement]), forKey: "saved-user")
        keyStore.values[replacement.accountIdentifier] = "dedupe-key-not-a-credential"

        let users = try subject.getUsersThrowing()

        XCTAssertEqual(users.count, 1)
        XCTAssertEqual(users.first?.username, "replacement")
    }

    func testExistingAccountTokenReplacementRestoresVerifiedKeyAndSanitizedMetadata() throws {
        let oldAPIKey = "old-key-not-a-credential"
        let newAPIKey = "new-key-not-a-credential"
        let existing = SecureUser(
            userId: "existing",
            username: "original-name",
            instance: "example.invalid",
            apiKey: oldAPIKey
        )
        XCTAssertTrue(subject.saveUser(existing))
        subject.changeCurrentUser(userId: existing.accountIdentifier)
        let replacement = SecureUser(
            userId: existing.userId,
            username: "replacement-name",
            instance: existing.instance,
            apiKey: newAPIKey
        )
        keyStore.readResults[existing.accountIdentifier] = [
            oldAPIKey, oldAPIKey, newAPIKey, "mismatched-read-back", oldAPIKey, oldAPIKey
        ]

        XCTAssertNil(subject.installAuthenticatedUser(replacement))

        let users = try subject.getUsersThrowing()
        XCTAssertEqual(users.map(\.accountIdentifier), [existing.accountIdentifier])
        XCTAssertEqual(users.first?.username, "original-name")
        XCTAssertEqual(users.first?.apiKey, oldAPIKey)
        XCTAssertEqual(subject.getCurrentUserId(), existing.accountIdentifier)
        XCTAssertEqual(keyStore.values[existing.accountIdentifier], oldAPIKey)
        try assertSanitizedMetadata(excludes: [oldAPIKey, newAPIKey], defaults: defaults)
        XCTAssertNil(defaults.data(forKey: "account-persistence-recovery-v1"))
    }

    func testNewAccountRemovalFailureStaysFailClosedUntilRecoveryRetry() throws {
        let apiKey = "candidate-key-not-a-credential"
        let candidate = makeUser(id: "candidate", apiKey: apiKey)
        keyStore.readResults[candidate.accountIdentifier] = [nil, apiKey, "mismatched-read-back"]
        keyStore.removeFailureAccountIDs = [candidate.accountIdentifier]

        XCTAssertNil(subject.installAuthenticatedUser(candidate))
        XCTAssertTrue(subject.getUsers().isEmpty)
        XCTAssertEqual(keyStore.values[candidate.accountIdentifier], apiKey)
        let journal = try XCTUnwrap(defaults.data(forKey: "account-persistence-recovery-v1"))
        XCTAssertNil(journal.range(of: Data(apiKey.utf8)))
        XCTAssertNil(defaults.data(forKey: "saved-user"))

        keyStore.removeFailureAccountIDs = []
        let resumed = Cache.UserDefaults(userDefaults: defaults, apiKeyStore: keyStore)
        XCTAssertTrue(try resumed.getUsersThrowing().isEmpty)
        XCTAssertNil(keyStore.values[candidate.accountIdentifier])
        XCTAssertNil(defaults.data(forKey: "account-persistence-recovery-v1"))
    }

    func testDefaultsRestoreReadbackFailureBlocksEnumerationUntilVerifiedRetry() throws {
        let defaultsStore = FakeAccountDefaultsStore()
        let store = FakeAPIKeyStore()
        let localSubject = Cache.UserDefaults(defaultsStore: defaultsStore, apiKeyStore: store)
        let oldAPIKey = "old-key-not-a-credential"
        let newAPIKey = "new-key-not-a-credential"
        let existing = SecureUser(
            userId: "existing",
            username: "original-name",
            instance: "example.invalid",
            apiKey: oldAPIKey
        )
        XCTAssertTrue(localSubject.saveUser(existing))
        XCTAssertTrue(localSubject.changeCurrentUser(userId: existing.accountIdentifier))
        let replacement = SecureUser(
            userId: existing.userId,
            username: "replacement-name",
            instance: existing.instance,
            apiKey: newAPIKey
        )
        store.onSet = { accountID, value in
            if accountID == existing.accountIdentifier, value == newAPIKey {
                defaultsStore.forcedNilDataKeys.insert("saved-user")
            }
        }

        XCTAssertNil(localSubject.installAuthenticatedUser(replacement))
        XCTAssertTrue(localSubject.getUsers().isEmpty)
        XCTAssertEqual(store.values[existing.accountIdentifier], oldAPIKey)
        let journal = try XCTUnwrap(defaultsStore.values["account-persistence-recovery-v1"] as? Data)
        XCTAssertNil(journal.range(of: Data(oldAPIKey.utf8)))
        XCTAssertNil(journal.range(of: Data(newAPIKey.utf8)))

        defaultsStore.forcedNilDataKeys = []
        store.onSet = nil
        let resumed = Cache.UserDefaults(defaultsStore: defaultsStore, apiKeyStore: store)
        let recovered = try resumed.getUsersThrowing()
        XCTAssertEqual(recovered.map(\.accountIdentifier), [existing.accountIdentifier])
        XCTAssertEqual(recovered.first?.username, "original-name")
        XCTAssertEqual(recovered.first?.apiKey, oldAPIKey)
        XCTAssertNil(defaultsStore.values["account-persistence-recovery-v1"])
    }

    func testLegacyPlaintextInstallFailureNeverRestoresRawMetadata() throws {
        let legacyAPIKey = "legacy-key-not-a-credential"
        let candidateAPIKey = "candidate-key-not-a-credential"
        let legacy = makeUser(id: "legacy", apiKey: legacyAPIKey)
        defaults.set(try JSONEncoder().encode([legacy]), forKey: "saved-user")
        let candidate = makeUser(id: "candidate", apiKey: candidateAPIKey)
        keyStore.readResults[candidate.accountIdentifier] = [
            nil, candidateAPIKey, "mismatched-read-back"
        ]

        XCTAssertNil(subject.installAuthenticatedUser(candidate))

        let users = try subject.getUsersThrowing()
        XCTAssertEqual(users.map(\.accountIdentifier), [legacy.accountIdentifier])
        XCTAssertEqual(users.first?.apiKey, legacyAPIKey)
        try assertSanitizedMetadata(
            excludes: [legacyAPIKey, candidateAPIKey],
            defaults: defaults
        )
        XCTAssertNil(keyStore.values[candidate.accountIdentifier])
    }

    func testInterruptedCommittedInstallFinishesOnNextRecoveryAttempt() throws {
        let defaultsStore = FakeAccountDefaultsStore()
        defaultsStore.blockedRemoveKeys = ["account-persistence-recovery-v1"]
        let store = FakeAPIKeyStore()
        let localSubject = Cache.UserDefaults(defaultsStore: defaultsStore, apiKeyStore: store)
        let apiKey = "committed-key-not-a-credential"
        let candidate = makeUser(id: "committed", apiKey: apiKey)

        XCTAssertNil(localSubject.installAuthenticatedUser(candidate))
        XCTAssertTrue(localSubject.getUsers().isEmpty)
        let journal = try XCTUnwrap(defaultsStore.values["account-persistence-recovery-v1"] as? Data)
        XCTAssertNil(journal.range(of: Data(apiKey.utf8)))

        defaultsStore.blockedRemoveKeys = []
        let resumed = Cache.UserDefaults(defaultsStore: defaultsStore, apiKeyStore: store)
        let users = try resumed.getUsersThrowing()
        XCTAssertEqual(users.map(\.accountIdentifier), [candidate.accountIdentifier])
        XCTAssertEqual(users.first?.apiKey, apiKey)
        XCTAssertNil(defaultsStore.values["account-persistence-recovery-v1"])
    }

    func testPersistTreatsFalseSynchronizeAsFailureAndRecoversPreparingJournal() throws {
        let defaultsStore = FakeAccountDefaultsStore()
        defaultsStore.synchronizes = false
        let store = FakeAPIKeyStore()
        let localSubject = Cache.UserDefaults(defaultsStore: defaultsStore, apiKeyStore: store)
        let candidate = makeUser(id: "false-sync")

        XCTAssertFalse(localSubject.saveUser(candidate))
        XCTAssertNil(store.values[candidate.accountIdentifier])

        defaultsStore.synchronizes = true
        XCTAssertTrue(try localSubject.getUsersThrowing().isEmpty)
        XCTAssertNil(defaultsStore.values["account-persistence-recovery-v1"])
    }

    private func assertSanitizedMetadata(
        excludes secrets: [String],
        defaults: Foundation.UserDefaults,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let data = try XCTUnwrap(defaults.data(forKey: "saved-user"), file: file, line: line)
        let metadata = try JSONDecoder().decode([SecureUser].self, from: data)
        XCTAssertTrue(metadata.allSatisfy { $0.apiKey == nil }, file: file, line: line)
        for secret in secrets {
            XCTAssertNil(data.range(of: Data(secret.utf8)), file: file, line: line)
        }
    }

    private func makeUser(
        id: String,
        instance: String = "example.invalid",
        apiKey: String = "test-key-not-a-credential"
    ) -> SecureUser {
        return SecureUser(userId: id,
                          username: "test-user",
                          instance: instance,
                          apiKey: apiKey)
    }
}

final class AccountKeychainMigrationTests: XCTestCase {
    func testCopiesAndVerifiesEveryEntryBeforeWritingCompletionMarker() {
        let old = FakeAPIKeyStore()
        old.values = ["account-a": "value-a", "account-b": "value-b"]
        let new = FakeAPIKeyStore()

        XCTAssertTrue(AccountKeychainMigrator().migrate(from: old, to: new))
        XCTAssertEqual(new.values["account-a"], "value-a")
        XCTAssertEqual(new.values["account-b"], "value-b")
        XCTAssertEqual(new.values[AccountKeychainMigrator.completionMarker], "true")
    }

    func testInterruptedMigrationLeavesMarkerAbsentAndResumesVerifiedEntries() {
        let old = FakeAPIKeyStore()
        old.values = ["account-a": "value-a", "account-b": "value-b"]
        let new = FakeAPIKeyStore()
        new.values["account-a"] = "value-a"
        new.writeFailureAccountIDs = ["account-b"]

        XCTAssertFalse(AccountKeychainMigrator().migrate(from: old, to: new))
        XCTAssertNil(new.values[AccountKeychainMigrator.completionMarker])
        XCTAssertEqual(new.setCounts["account-a"], nil)

        new.writeFailureAccountIDs = []
        XCTAssertTrue(AccountKeychainMigrator().migrate(from: old, to: new))
        XCTAssertEqual(new.values["account-b"], "value-b")
        XCTAssertEqual(new.values[AccountKeychainMigrator.completionMarker], "true")
    }

    func testMixedDestinationIsCorrectedBeforeCompletion() {
        let old = FakeAPIKeyStore()
        old.values = ["account-a": "source-a", "account-b": "source-b"]
        let new = FakeAPIKeyStore()
        new.values = ["account-a": "source-a", "account-b": "stale-b"]

        XCTAssertTrue(AccountKeychainMigrator().migrate(from: old, to: new))
        XCTAssertEqual(new.values["account-b"], "source-b")
        XCTAssertEqual(new.values[AccountKeychainMigrator.completionMarker], "true")
    }

    func testCorruptListedSourceLeavesMigrationResumable() {
        let old = FakeAPIKeyStore()
        old.values = ["account-a": "value-a"]
        old.listedAccountIDs = ["account-a", "corrupt-entry"]
        let new = FakeAPIKeyStore()

        XCTAssertFalse(AccountKeychainMigrator().migrate(from: old, to: new))
        XCTAssertEqual(new.values["account-a"], "value-a")
        XCTAssertNil(new.values[AccountKeychainMigrator.completionMarker])

        old.values["corrupt-entry"] = "recovered-value"
        XCTAssertTrue(AccountKeychainMigrator().migrate(from: old, to: new))
        XCTAssertEqual(new.values["corrupt-entry"], "recovered-value")
        XCTAssertEqual(new.values[AccountKeychainMigrator.completionMarker], "true")
    }
}
