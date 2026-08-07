import XCTest

@MainActor
final class MissCatLoginProfileUITests: XCTestCase {
    private var app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
    }

    func testProductionLaunchWithoutFixtureArgumentsUsesSwiftUIAuthenticationRoot() {
        app.launchArguments = []
        app.launchEnvironment = [
            "AppleLanguages": "(ja)",
            "AppleLocale": "ja_JP",
            "TZ": "Asia/Tokyo"
        ]
        app.launch()

        XCTAssertTrue(element("authentication.flow").waitForExistence(timeout: 10))
        XCTAssertTrue(element("welcome.screen").exists)
        XCTAssertTrue(app.buttons["welcome.login"].exists)
        XCTAssertTrue(app.buttons["welcome.signup"].exists)
        XCTAssertFalse(element("profile.searchResults.root").exists)
    }

    func testAuthenticationInstanceValidationBackCancelAndCallback() {
        launch("--login-profile-auth")
        XCTAssertTrue(element("welcome.screen").waitForExistence(timeout: 10))
        capture("04-start-current")

        setInstance("javascript:alert(1)", captureName: "06-instance-selector-current")
        app.buttons["welcome.login"].tap()
        XCTAssertTrue(element("terms.screen").waitForExistence(timeout: 5))
        capture("05-terms-current")
        app.buttons["terms.agree"].tap()
        let validationAlert = app.alerts["エラー"]
        XCTAssertTrue(validationAlert.waitForExistence(timeout: 5))
        XCTAssertTrue(validationAlert.staticTexts["インスタンスURLが正しくありません"].exists)
        validationAlert.buttons["閉じる"].tap()

        tapNavigationBack()
        XCTAssertTrue(element("welcome.screen").waitForExistence(timeout: 5))
        setInstance("https://fixture.invalid/")
        XCTAssertTrue(element("welcome.instance").label.contains("fixture.invalid"))

        app.buttons["welcome.login"].tap()
        app.buttons["terms.agree"].tap()
        XCTAssertTrue(element("authentication.browser").waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["authentication.reload"].exists)
        capture("07-auth-web-current")

        // Cancelling the browser returns to Terms without creating a callback.
        tapNavigationBack()
        XCTAssertTrue(element("terms.screen").waitForExistence(timeout: 5))
        tapNavigationBack()
        XCTAssertTrue(element("welcome.screen").waitForExistence(timeout: 5))

        app.buttons["welcome.login"].tap()
        app.buttons["terms.agree"].tap()
        let complete = app.links["認証を完了"]
        XCTAssertTrue(complete.waitForExistence(timeout: 10))
        complete.tap()
        XCTAssertTrue(element("authentication.fixture.completed").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["fixture callback count: 1"].exists)
    }

    func testAuthenticationPreparationAndBrowserErrorsRetryWithoutLiveNetwork() {
        launch("--login-profile-auth", "--login-profile-auth-prepare-error")
        advanceToAuthorization()
        let preparationAlert = app.alerts["エラー"]
        XCTAssertTrue(preparationAlert.waitForExistence(timeout: 5))
        XCTAssertTrue(preparationAlert.staticTexts["認証の準備に失敗しました"].exists)
        preparationAlert.buttons["再試行"].tap()
        XCTAssertTrue(element("welcome.screen").waitForExistence(timeout: 5))
        advanceToAuthorization()
        XCTAssertTrue(element("authentication.browser").waitForExistence(timeout: 10))

        relaunch("--login-profile-auth", "--login-profile-auth-browser-error")
        advanceToAuthorization()
        let browserAlert = app.alerts["エラー"]
        XCTAssertTrue(browserAlert.waitForExistence(timeout: 10))
        browserAlert.buttons["再試行"].tap()
        XCTAssertTrue(element("welcome.screen").waitForExistence(timeout: 5))
        advanceToAuthorization()
        XCTAssertTrue(app.links["認証を完了"].waitForExistence(timeout: 10))
    }

    func testAuthenticationSystemCancellationRetriesTheSamePendingRequest() {
        launch("--login-profile-auth", "--login-profile-auth-cancel-browser")
        advanceToAuthorization()

        let cancelSession = app.buttons["authentication.fixture.cancel-session"]
        XCTAssertTrue(cancelSession.waitForExistence(timeout: 10))
        cancelSession.tap()

        let retry = app.buttons["authentication.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        retry.tap()

        let completeSession = app.buttons["authentication.fixture.complete-session"]
        XCTAssertTrue(completeSession.waitForExistence(timeout: 10))
        completeSession.tap()
        XCTAssertTrue(element("authentication.fixture.completed").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["fixture callback count: 1"].exists)
        XCTAssertEqual(element("authentication.fixture.session-request-count").value as? String, "2")
        XCTAssertEqual(element("authentication.fixture.authorization-request-count").value as? String, "1")
    }

    func testAuthenticationSignUpRequiresTermsAndExplicitLoginHandoff() {
        launch("--login-profile-auth")
        XCTAssertTrue(element("welcome.screen").waitForExistence(timeout: 10))
        app.buttons["welcome.signup"].tap()
        XCTAssertTrue(element("terms.screen").waitForExistence(timeout: 5))
        app.buttons["terms.agree"].tap()

        XCTAssertTrue(app.buttons["authentication.signup.continue"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["authentication.fixture.complete-session"].exists)
        app.buttons["authentication.signup.continue"].tap()

        let completeSession = app.buttons["authentication.fixture.complete-session"]
        XCTAssertTrue(completeSession.waitForExistence(timeout: 10))
        completeSession.tap()
        XCTAssertTrue(element("authentication.fixture.completed").waitForExistence(timeout: 5))
        XCTAssertEqual(element("authentication.fixture.registration-open-count").value as? String, "1")
        XCTAssertEqual(element("authentication.fixture.authorization-request-count").value as? String, "2")
    }

    func testSearchResultProfileTabsAndRelationshipNavigation() {
        launch("--login-profile-profile")
        waitForUserList()
        capture("25-user-results-current")
        app.buttons["profile.user.fixture-target"].tap()
        waitForProfile("profile.other.screen")
        capture("26-profile-current")

        app.buttons["profile.tab.media"].tap()
        waitForSelectedTab("profile.tab.media")
        let pager = element("profile.timeline.pager")
        XCTAssertTrue(pager.waitForExistence(timeout: 5))
        pager.swipeRight()
        waitForSelectedTab("profile.tab.notesAndReplies")
        pager.swipeRight()
        waitForSelectedTab("profile.tab.notes")

        app.buttons["profile.count.followers"].tap()
        waitForUserList()
        XCTAssertEqual(app.navigationBars.firstMatch.identifier, "Followers")
        capture("27-followers-current")
        app.buttons["profile.user.fixture-friend"].tap()
        waitForProfile("profile.other.screen")
        XCTAssertTrue(app.buttons["profile.action.back"].isHittable)
        app.buttons["profile.action.back"].tap()
        waitForUserList()
        tapNavigationBack()
        waitForProfile("profile.other.screen")
    }

    func testSearchResultSelfProfileBackReturnsToTheSameResults() {
        launch("--login-profile-profile")
        waitForSearchResults()

        app.buttons["profile.user.fixture-self"].tap()
        waitForProfile("profile.self.screen")
        let back = app.buttons["profile.action.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        XCTAssertTrue(back.isHittable)
        back.tap()

        waitForSearchResults()
        XCTAssertTrue(app.buttons["profile.user.fixture-target"].exists)
        XCTAssertTrue(app.buttons["profile.user.fixture-self"].exists)
    }

    func testRootSelfProfileKeepsEditAndSettingsWithoutNestedBack() {
        launch("--login-profile-profile", "--login-profile-root-self")
        waitForProfile("profile.self.screen")

        XCTAssertFalse(app.buttons["profile.action.back"].exists)
        XCTAssertTrue(app.buttons["profile.action.edit"].isHittable)
        XCTAssertTrue(app.buttons["profile.action.settings"].isHittable)
        assertSingleBottomBar()
    }

    func testOrdinarySearchShellOwnsOneFooterAndPreservesAllNestedRoutes() {
        launch("--login-profile-profile", "--login-profile-ordinary-shell")
        waitForSearchResults()
        assertSingleBottomBar()
        capture("25-user-results-ordinary-shell-current")

        app.buttons["profile.user.fixture-self"].tap()
        waitForProfile("profile.self.screen")
        XCTAssertTrue(app.buttons["profile.action.back"].isHittable)
        assertSingleBottomBar()
        app.buttons["profile.action.back"].tap()
        waitForSearchResults()
        XCTAssertTrue(app.buttons["profile.user.fixture-target"].exists)
        XCTAssertTrue(app.buttons["profile.user.fixture-self"].exists)

        app.buttons["profile.user.fixture-target"].tap()
        waitForProfile("profile.other.screen")
        assertSingleBottomBar()
        capture("26-profile-ordinary-shell-current")

        app.buttons["profile.action.settings"].tap()
        waitForValue("settings", identifier: "profile.ordinaryShell.lastAction")
        app.buttons["profile.avatar"].tap()
        waitForValue("image", identifier: "profile.ordinaryShell.lastAction")
        tapBiographyLink(horizontal: 0.9, vertical: 0.5)
        waitForValue("url", identifier: "profile.ordinaryShell.lastAction")

        app.buttons["profile.count.followers"].tap()
        waitForUserList()
        assertSingleBottomBar()
        app.buttons["profile.user.fixture-self"].tap()
        waitForProfile("profile.self.screen")
        assertSingleBottomBar()
        XCTAssertTrue(app.buttons["profile.action.back"].isHittable)

        tapBiographyLink(horizontal: 0.2, vertical: 0.85)
        waitForValue("url", identifier: "profile.ordinaryShell.lastAction")

        app.buttons["profile.action.back"].tap()
        waitForUserList()
        XCTAssertEqual(app.navigationBars.firstMatch.identifier, "Followers")
        tapNavigationBack()
        waitForProfile("profile.other.screen")
        app.buttons["profile.action.back"].tap()
        waitForSearchResults()
        XCTAssertTrue(app.buttons["profile.user.fixture-target"].exists)
        XCTAssertTrue(app.buttons["profile.user.fixture-self"].exists)
        assertSingleBottomBar()

        app.buttons["main.action.compose"].tap()
        waitForValue("compose", identifier: "profile.ordinaryShell.lastAction")
        app.buttons["main.tab.profile"].tap()
        waitForValue("root.profile", identifier: "profile.ordinaryShell.lastAction")
        app.buttons["main.tab.home"].tap()
        waitForValue("root.home", identifier: "profile.ordinaryShell.lastAction")
    }

    func testRealLegacyHomeSearchRouteHostsTheTypedProfileFamily() {
        launchRealOrdinaryRoute()
        XCTAssertFalse(app.launchArguments.contains("--login-profile-fixture"))

        waitForNativeProfileSearchResults()
        XCTAssertTrue(element("profile.realOrdinary.lastAction").waitForExistence(timeout: 5))
        assertSingleBottomBar()
        capture("25-user-results-real-ordinary-route-current")

        // Native SwiftUI Search still participates in the ordinary Home pager.
        let searchRoot = app.textFields["discovery.query"]
        XCTAssertTrue(searchRoot.isHittable)
        app.swipeLeft()
        let hidden = NSPredicate(format: "isHittable == false")
        expectation(for: hidden, evaluatedWith: searchRoot)
        waitForExpectations(timeout: 5)
        app.swipeRight()
        waitForNativeProfileSearchResults()

        app.buttons["discovery.user.fixture-self"].tap()
        waitForProfile("profile.self.screen")
        XCTAssertTrue(app.buttons["profile.action.back"].isHittable)
        assertSingleBottomBar()
        app.buttons["profile.action.back"].tap()
        waitForNativeProfileSearchResults()

        app.buttons["discovery.user.fixture-target"].tap()
        waitForProfile("profile.other.screen")
        assertSingleBottomBar()
        capture("26-profile-real-ordinary-route-current")

        app.buttons["profile.tab.media"].tap()
        waitForSelectedTab("profile.tab.media")
        let pager = element("profile.timeline.pager")
        XCTAssertTrue(pager.waitForExistence(timeout: 5))

        // Media is the trailing page: swiping left must saturate at the edge.
        pager.swipeLeft()
        waitForSelectedTab("profile.tab.media")

        pager.swipeRight()
        waitForSelectedTab("profile.tab.notesAndReplies")

        // Walk to the leading page, prove its boundary, and return in the
        // opposite direction so both real pager gestures are exercised.
        pager.swipeRight()
        waitForSelectedTab("profile.tab.notes")
        pager.swipeRight()
        waitForSelectedTab("profile.tab.notes")
        pager.swipeLeft()
        waitForSelectedTab("profile.tab.notesAndReplies")
        pager.swipeLeft()
        waitForSelectedTab("profile.tab.media")
        pager.swipeLeft()
        waitForSelectedTab("profile.tab.media")

        app.buttons["profile.action.settings"].tap()
        waitForValue("settings", identifier: "profile.realOrdinary.lastAction")
        app.buttons["profile.avatar"].tap()
        waitForValue("image", identifier: "profile.realOrdinary.lastAction")
        tapBiographyLink(horizontal: 0.9, vertical: 0.5)
        waitForValue("hashtag", identifier: "profile.realOrdinary.lastAction")

        app.buttons["profile.count.followers"].tap()
        waitForUserList()
        XCTAssertEqual(app.navigationBars.firstMatch.identifier, "Followers")
        assertSingleBottomBar()
        app.buttons["profile.user.fixture-self"].tap()
        waitForProfile("profile.self.screen")
        XCTAssertTrue(app.buttons["profile.action.back"].isHittable)
        assertSingleBottomBar()
        app.buttons["profile.action.back"].tap()
        waitForUserList()
        tapNavigationBack()
        waitForProfile("profile.other.screen")
        app.buttons["profile.action.back"].tap()
        waitForNativeProfileSearchResults()
        assertSingleBottomBar()

        XCTAssertTrue(app.buttons["main.action.compose"].isHittable)
        XCTAssertTrue(app.buttons["main.tab.profile"].isHittable)
        XCTAssertTrue(app.buttons["main.tab.home"].isHittable)
    }

    func testFollowUnfollowFailureRollsBackThenRetrySucceeds() {
        launch("--login-profile-profile", "--login-profile-unfollow-error")
        openTargetProfile()

        app.buttons["profile.action.follow"].tap()
        waitForButtonLabel("フォロー解除", identifier: "profile.action.follow")
        app.buttons["profile.action.follow"].tap()
        app.sheets.buttons["Unfollow"].tap()
        let alert = app.alerts["フォロー操作に失敗しました"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["閉じる"].tap()
        waitForButtonLabel("フォロー解除", identifier: "profile.action.follow")

        app.buttons["profile.action.follow"].tap()
        app.sheets.buttons["Unfollow"].tap()
        waitForButtonLabel("フォロー", identifier: "profile.action.follow")
    }

    func testEditCancelImageStateAndSuccessfulSave() {
        launch("--login-profile-profile")
        openSelfProfile()
        capture("26-profile-self-current")
        app.buttons["profile.action.edit"].tap()
        waitForValue("1", identifier: "profile.edit.requestCount")
        let editor = element("profile.edit.screen")
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        assertImageState("avatar=existing;banner=existing")
        capture("28-edit-profile-current")

        replaceText(identifier: "profile.edit.name", with: "破棄する名前")
        app.buttons["profile.edit.close"].tap()
        XCTAssertTrue(element("profile.self.screen").waitForExistence(timeout: 5))
        app.buttons["profile.action.edit"].tap()
        XCTAssertEqual(app.textFields["profile.edit.name"].value as? String, "だわくん")

        removeImage(menu: "profile.edit.avatar", action: "profile.edit.avatar.remove")
        removeImage(menu: "profile.edit.banner", action: "profile.edit.banner.remove")
        assertImageState("avatar=removed;banner=removed")
        replaceText(identifier: "profile.edit.name", with: "保存した名前")
        app.buttons["profile.edit.save"].tap()
        XCTAssertTrue(element("profile.self.screen").waitForExistence(timeout: 5))
        XCTAssertTrue(element("profile.identity").label.contains("保存した名前"))
    }

    func testEditFailureRetainsDraftAndRetrySucceeds() {
        launch("--login-profile-profile", "--login-profile-edit-error")
        openSelfProfile()
        app.buttons["profile.action.edit"].tap()
        waitForValue("1", identifier: "profile.edit.requestCount")
        replaceText(identifier: "profile.edit.name", with: "再試行する名前")
        app.buttons["profile.edit.save"].tap()
        XCTAssertTrue(app.buttons["profile.edit.retry"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["profile.edit.name"].value as? String, "再試行する名前")
        app.buttons["profile.edit.retry"].tap()
        XCTAssertTrue(element("profile.self.screen").waitForExistence(timeout: 5))
        XCTAssertTrue(element("profile.identity").label.contains("再試行する名前"))
    }

    private func launch(_ arguments: String...) {
        app.launchArguments = ["--login-profile-fixture"] + arguments
        app.launchEnvironment = [
            "AppleLanguages": "(ja)",
            "AppleLocale": "ja_JP",
            "TZ": "Asia/Tokyo"
        ]
        app.launch()
    }

    private func launchRealOrdinaryRoute() {
        app.launchArguments = ["--login-profile-real-ordinary-route"]
        app.launchEnvironment = [
            "AppleLanguages": "(ja)",
            "AppleLocale": "ja_JP",
            "TZ": "Asia/Tokyo"
        ]
        app.launch()
    }

    private func relaunch(_ arguments: String...) {
        app.terminate()
        launch(arguments)
    }

    private func launch(_ arguments: [String]) {
        app.launchArguments = ["--login-profile-fixture"] + arguments
        app.launchEnvironment = [
            "AppleLanguages": "(ja)",
            "AppleLocale": "ja_JP",
            "TZ": "Asia/Tokyo"
        ]
        app.launch()
    }

    private func advanceToAuthorization() {
        XCTAssertTrue(element("welcome.screen").waitForExistence(timeout: 10))
        app.buttons["welcome.login"].tap()
        XCTAssertTrue(app.buttons["terms.agree"].waitForExistence(timeout: 5))
        app.buttons["terms.agree"].tap()
    }

    private func setInstance(_ value: String, captureName: String? = nil) {
        app.buttons["welcome.change-instance"].tap()
        // SwiftUI alert text fields are hosted by UIKit and do not consistently
        // forward their SwiftUI accessibility identifier on current simulators.
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        if let captureName { capture(captureName) }
        field.tap()
        field.typeText(value)
        app.alerts.buttons["変更"].tap()
    }

    private func openTargetProfile() {
        waitForUserList()
        app.buttons["profile.user.fixture-target"].tap()
        waitForProfile("profile.other.screen")
    }

    private func openSelfProfile() {
        waitForUserList()
        app.buttons["profile.user.fixture-self"].tap()
        waitForProfile("profile.self.screen")
    }

    private func waitForUserList() {
        XCTAssertTrue(element("profile.userList.visualReady").waitForExistence(timeout: 10))
        XCTAssertTrue(element("profile.user.fixture-target").waitForExistence(timeout: 5) || element("profile.user.fixture-friend").exists)
    }

    private func waitForSearchResults() {
        XCTAssertTrue(element("profile.searchResults.root").waitForExistence(timeout: 10))
        waitForUserList()
    }

    private func waitForNativeProfileSearchResults() {
        XCTAssertTrue(element("home.discovery.native-page").waitForExistence(timeout: 10))
        XCTAssertTrue(element("discovery.users.list").waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["discovery.user.fixture-target"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["discovery.user.fixture-self"].exists)
    }

    private func waitForProfile(_ identifier: String) {
        XCTAssertTrue(element(identifier).waitForExistence(timeout: 10))
        let ready = element("profile.visualReady")
        XCTAssertTrue(ready.waitForExistence(timeout: 10))
        let predicate = NSPredicate(format: "value == %@", "true")
        expectation(for: predicate, evaluatedWith: ready)
        waitForExpectations(timeout: 10)
    }

    private func waitForSelectedTab(_ identifier: String) {
        let tab = app.buttons[identifier]
        let predicate = NSPredicate(format: "isSelected == true")
        expectation(for: predicate, evaluatedWith: tab)
        waitForExpectations(timeout: 5)
    }

    private func waitForButtonLabel(_ label: String, identifier: String) {
        let button = app.buttons[identifier]
        let predicate = NSPredicate(format: "label == %@", label)
        expectation(for: predicate, evaluatedWith: button)
        waitForExpectations(timeout: 5)
    }

    private func waitForValue(_ value: String, identifier: String) {
        let marker = element(identifier)
        XCTAssertTrue(marker.waitForExistence(timeout: 5))
        let predicate = NSPredicate(format: "value == %@", value)
        expectation(for: predicate, evaluatedWith: marker)
        waitForExpectations(timeout: 5)
    }

    private func assertSingleBottomBar() {
        XCTAssertEqual(app.buttons.matching(identifier: "main.action.compose").count, 1)
        for section in ["home", "notifications", "messages", "profile"] {
            XCTAssertEqual(app.buttons.matching(identifier: "main.tab.\(section)").count, 1)
        }
        let explicitMarkers = app.descendants(matching: .any).matching(identifier: "main.bottom-bar")
        XCTAssertLessThanOrEqual(explicitMarkers.count, 1)
    }

    private func tapBiographyLink(horizontal: CGFloat, vertical: CGFloat) {
        let biography = app.staticTexts["profile.biography"]
        XCTAssertTrue(biography.waitForExistence(timeout: 5))
        biography.coordinate(
            withNormalizedOffset: CGVector(dx: horizontal, dy: vertical)
        ).tap()
    }

    private func replaceText(identifier: String, with value: String) {
        let field = app.textFields[identifier]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.press(forDuration: 1.0)
        if app.menuItems["すべてを選択"].waitForExistence(timeout: 2) {
            app.menuItems["すべてを選択"].tap()
        } else if app.menuItems["Select All"].exists {
            app.menuItems["Select All"].tap()
        }
        field.typeText(value)
    }

    private func removeImage(menu: String, action: String) {
        app.buttons[menu].tap()
        let identified = app.buttons[action]
        if identified.waitForExistence(timeout: 2) {
            identified.tap()
        } else {
            app.buttons["画像を削除"].tap()
        }
    }

    private func assertImageState(_ value: String) {
        let images = element("profile.edit.images")
        XCTAssertTrue(images.waitForExistence(timeout: 5))
        XCTAssertEqual(images.value as? String, value)
    }

    private func tapNavigationBack() {
        let button = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
