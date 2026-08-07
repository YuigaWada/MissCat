import XCTest

final class MissCatShellFeedUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDown() {
        app?.terminate()
        app = nil
    }

    func testTimelineTabsSupportTapAndSwipe() {
        launchFixture()
        waitForReady(page: "home")
        waitForSynchronizedPagerSelection("home")
        captureStableFixture(page: "home", name: "shell-populated")

        app.buttons["main.timeline.local"].tap()
        waitForSynchronizedPagerSelection("local")
        waitForReady(page: "local")

        let pager = app.collectionViews.firstMatch
        XCTAssertTrue(pager.waitForExistence(timeout: 5))

        pager.swipeLeft()
        waitForSynchronizedPagerSelection("global")
        waitForReady(page: "global")

        pager.swipeLeft()
        waitForSynchronizedPagerSelection("global")

        pager.swipeRight()
        waitForSynchronizedPagerSelection("local")
        waitForReady(page: "local")

        pager.swipeRight()
        waitForSynchronizedPagerSelection("home")
        waitForReady(page: "home")

        pager.swipeRight()
        waitForSynchronizedPagerSelection("home")
    }

    func testOrdinaryProductionRootOwnsShellRoutesAndAccountGeneration() {
        app.launchArguments = ["--misscat-production-root-e2e"]
        app.launch()

        XCTAssertTrue(element("production.root").waitForExistence(timeout: 10))
        waitForProductionReady(page: "home")
        waitForSynchronizedPagerSelection("home")

        app.buttons["main.tab.notifications"].tap()
        XCTAssertTrue(element("notifications.screen").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["通知はありません"].exists)
        app.buttons["main.header.account"].tap()
        app.buttons["main.account.https://social.example|fixture-cat"].tap()
        waitForProductionReady(page: "home")
        app.buttons["main.tab.notifications"].tap()
        XCTAssertTrue(element("notifications.screen").waitForExistence(timeout: 5))
        waitForAccount("https://social.example|fixture-cat")

        app.buttons["main.tab.home"].tap()
        waitForProductionReady(page: "home")
        app.buttons["main.timeline.local"].tap()
        waitForProductionPagerSelection("local")
        swipeProductionPagerRight()
        waitForProductionPagerSelection("home")
        swipeProductionPagerRight()
        waitForProductionPagerSelection("home")
        swipeProductionPagerLeft()
        waitForProductionPagerSelection("local")
        swipeProductionPagerLeft()
        waitForProductionPagerSelection("global")
        swipeProductionPagerLeft()
        waitForProductionPagerSelection("global")

        app.buttons["main.action.compose"].tap()
        XCTAssertTrue(app.buttons["compose.cancel"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts["エラー"].exists)
        app.buttons["compose.cancel"].tap()
        XCTAssertTrue(element("production.root").waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts["エラー"].exists)

        app.buttons["main.tab.messages"].tap()
        XCTAssertTrue(element("messages.history.screen").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["メッセージはありません"].exists)
        app.buttons["main.tab.profile"].tap()
        app.buttons["main.header.settings"].tap()
        XCTAssertTrue(element("settings.root.visualReady").waitForExistence(timeout: 5))
        app.buttons["settings.close"].tap()
        XCTAssertTrue(element("production.root").waitForExistence(timeout: 5))
    }

    func testFooterAccountPopoverAndCompositeScrollRestoration() {
        launchFixture()
        let homeReady = waitForReady(page: "home")
        let feed = app.scrollViews["feed.scroll"]
        XCTAssertTrue(feed.waitForExistence(timeout: 5))
        feed.swipeUp()

        let savedPosition = waitForNonTopValue(homeReady)

        app.buttons["main.tab.notifications"].tap()
        XCTAssertTrue(element("fixture.section.notifications").waitForExistence(timeout: 5))
        app.buttons["main.header.account"].tap()
        XCTAssertTrue(element("main.account.dropdown").waitForExistence(timeout: 5))
        app.buttons["main.account.https://social.example|fixture-cat"].tap()
        waitForAccount("https://social.example|fixture-cat")

        app.buttons["main.header.account"].tap()
        app.buttons["main.account.https://fixture.example|fixture-cat"].tap()
        waitForAccount("https://fixture.example|fixture-cat")
        app.buttons["main.tab.home"].tap()
        let restoredReady = waitForReady(page: "home")
        XCTAssertEqual(restoredReady.value as? String, savedPosition)

        app.buttons["main.tab.messages"].tap()
        XCTAssertTrue(element("fixture.section.chat").waitForExistence(timeout: 5))
        app.buttons["main.tab.profile"].tap()
        XCTAssertTrue(element("fixture.section.accounts").waitForExistence(timeout: 5))
        app.buttons["main.action.compose"].tap()
        XCTAssertTrue(element("fixture.route.compose").waitForExistence(timeout: 5))
    }

    func testEmptyLoadingErrorOfflineAndShellBannerFixtures() {
        launchFixture("--swiftui-shell-fixture-empty")
        XCTAssertTrue(element("feed.empty").waitForExistence(timeout: 5))
        captureStableFixture(page: "home", name: "shell-empty")

        relaunchFixture("--swiftui-shell-fixture-loading")
        XCTAssertTrue(element("feed.loading").waitForExistence(timeout: 5))
        captureStableFixture(page: "home", name: "shell-loading")

        relaunchFixture("--swiftui-shell-fixture-error")
        XCTAssertTrue(element("feed.failure").waitForExistence(timeout: 5))
        captureStableFixture(page: "home", name: "shell-error")

        relaunchFixture("--swiftui-shell-fixture-offline")
        waitForReady(page: "home")
        XCTAssertTrue(element("feed.banner.error").waitForExistence(timeout: 5))
        captureStableFixture(page: "home", name: "shell-offline")

        relaunchFixture("--swiftui-shell-fixture-persistence-error")
        waitForReady(page: "home")
        app.buttons["main.timeline.local"].tap()
        XCTAssertTrue(element("main.banner.error").waitForExistence(timeout: 5))
    }

    func testAccountsSettingsAcceptanceScreenshots() {
        let screens = [
            "accounts",
            "accounts-empty",
            "accounts-error",
            "settings-root",
            "design",
            "reaction-instances",
            "reactions",
            "licenses",
            "license-detail",
            "about"
        ]

        captureAccountsSettingsScreens(screens)
    }

    func testDesignAndAboutAcceptanceScreenshots() {
        captureAccountsSettingsScreens(["design", "about"])
    }

    func testReviewerStateIntegrityAcceptanceScreenshots() {
        captureAccountsSettingsScreens(["reaction-instances", "licenses", "license-detail"])
    }

    private func captureAccountsSettingsScreens(_ screens: [String]) {
        for screen in screens {
            launchAccountsSettingsFixture(screen: screen)
            waitForAccountsSettingsVisualReady(screen: screen)
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "candidate-accounts-settings-\(screen)"
            attachment.lifetime = .keepAlways
            add(attachment)
            app.terminate()
        }
    }

    func testAccountsNativeNavigationSwitchDeletionAndRetry() {
        launchAccountsSettingsFixture(screen: "accounts")
        waitForAccountsSettingsVisualReady(screen: "accounts")

        app.buttons["accounts.profile.fixture-wada"].tap()
        XCTAssertTrue(element("accounts.profile.screen").waitForExistence(timeout: 5))
        app.buttons["accounts.profile.back"].tap()
        XCTAssertTrue(element("accounts.visualReady").waitForExistence(timeout: 5))

        app.buttons["accounts.switch.fixture-sub"].tap()
        XCTAssertTrue(element("settings.banner").waitForExistence(timeout: 5))

        app.buttons["accounts.add"].tap()
        XCTAssertTrue(element("accounts.add.flow").waitForExistence(timeout: 5))
        app.buttons["accounts.add.close"].tap()
        XCTAssertTrue(element("accounts.visualReady").waitForExistence(timeout: 5))

        app.buttons["accounts.edit"].tap()
        app.buttons["accounts.delete.fixture-wada"].tap()
        XCTAssertTrue(app.alerts["本当に削除しますか？"].waitForExistence(timeout: 5))
        app.alerts.buttons["閉じる"].tap()
        XCTAssertTrue(element("accounts.card.fixture-wada").exists)

        app.buttons["accounts.delete.fixture-wada"].tap()
        app.alerts.buttons["はい"].tap()
        XCTAssertFalse(element("accounts.card.fixture-wada").waitForExistence(timeout: 1))

        launchAccountsSettingsFixture(screen: "accounts-error")
        XCTAssertTrue(element("settings.error").waitForExistence(timeout: 5))
        app.buttons["再試行"].tap()
        waitForAccountsSettingsVisualReady(screen: "accounts")
        XCTAssertTrue(element("accounts.list").exists)
    }

    func testLastTabOwningAccountDeletionKeepsRequiredRecoveryOnProductionBridge() {
        launchAccountsSettingsFixture(screen: "accounts-last-recovery")
        waitForAccountsSettingsVisualReady(screen: "accounts-last-recovery")
        XCTAssertTrue(element("accounts.card.fixture-wada").exists)
        XCTAssertFalse(element("accounts.card.fixture-sub").exists)

        app.buttons["accounts.edit"].tap()
        app.buttons["accounts.delete.fixture-wada"].tap()
        XCTAssertTrue(app.alerts["本当に削除しますか？"].waitForExistence(timeout: 5))
        app.alerts.buttons["はい"].tap()

        let required = element("accounts.add.required")
        XCTAssertTrue(required.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["accounts.add.close"].exists)
        XCTAssertFalse(element("accounts.card.fixture-wada").exists)

        app.swipeDown()
        XCTAssertTrue(required.waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["accounts.add.close"].exists)
    }

    func testSettingsTypedNavigationAndInteractiveEditors() {
        launchAccountsSettingsFixture(screen: "settings-root")
        XCTAssertTrue(element("settings.root.visualReady").waitForExistence(timeout: 5))

        app.buttons["settings.design"].tap()
        XCTAssertTrue(element("settings.design.visualReady").waitForExistence(timeout: 5))
        XCTAssertTrue(element("settings.design.add-tab").exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.buttons["settings.reactions"].tap()
        XCTAssertTrue(element("settings.reactions.instances.visualReady").waitForExistence(timeout: 5))
        app.buttons["settings.reactions.instance.fixture-wada"].tap()
        XCTAssertTrue(element("settings.reactions.visualReady").waitForExistence(timeout: 5))
        app.buttons["settings.reactions.add"].tap()
        XCTAssertTrue(element("settings.reactions.picker.visualReady").waitForExistence(timeout: 5))
        app.buttons["閉じる"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.buttons["settings.licenses"].tap()
        XCTAssertTrue(element("settings.licenses.visualReady").waitForExistence(timeout: 5))
        let rxSwiftLicense = app.buttons["settings.license.RxSwift"]
        for _ in 0..<5 where !rxSwiftLicense.exists || !rxSwiftLicense.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(rxSwiftLicense.waitForExistence(timeout: 5))
        XCTAssertTrue(rxSwiftLicense.isHittable)
        rxSwiftLicense.tap()
        XCTAssertTrue(element("settings.license.detail.visualReady").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "MIT License")).firstMatch.exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.buttons["settings.about"].tap()
        XCTAssertTrue(element("settings.about.visualReady").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings.about.yuigawada"].exists)
        XCTAssertTrue(app.buttons["settings.about.wada"].exists)
    }

    private func launchFixture(_ extraArguments: String...) {
        app.launchArguments = ["--swiftui-shell-fixture"] + extraArguments
        app.launch()
    }

    private func launchAccountsSettingsFixture(screen: String) {
        app.terminate()
        app.launchArguments = [
            "--swiftui-accounts-settings-acceptance",
            "--swiftui-accounts-settings-screen",
            screen
        ]
        app.launch()
    }

    private func waitForAccountsSettingsVisualReady(screen: String) {
        let identifier: String
        switch screen {
        case "accounts", "accounts-empty", "accounts-error", "accounts-last-recovery":
            identifier = "accounts.visualReady"
        case "settings-root":
            identifier = "settings.root.visualReady"
        case "design":
            identifier = "settings.design.visualReady"
        case "reaction-instances":
            identifier = "settings.reactions.instances.visualReady"
        case "reactions":
            identifier = "settings.reactions.visualReady"
        case "licenses":
            identifier = "settings.licenses.visualReady"
        case "license-detail":
            identifier = "settings.license.detail.visualReady"
        case "about":
            identifier = "settings.about.visualReady"
        default:
            XCTFail("Unknown Accounts/Settings fixture screen: \(screen)")
            return
        }
        XCTAssertTrue(element(identifier).waitForExistence(timeout: 10), "Missing visualReady for \(screen)")
        if screen == "about" {
            let completed = NSPredicate(format: "value == %@", "true")
            expectation(for: completed, evaluatedWith: element(identifier))
            waitForExpectations(timeout: 3)
        }
    }

    private func relaunchFixture(_ extraArguments: String...) {
        app.terminate()
        app.launchArguments = ["--swiftui-shell-fixture"] + extraArguments
        app.launch()
    }

    @discardableResult
    private func waitForReady(page: String) -> XCUIElement {
        let marker = element("migration.shell-feed.visual-ready.\(page)")
        XCTAssertTrue(marker.waitForExistence(timeout: 10), "Missing stable visualReady marker for \(page)")
        return marker
    }

    @discardableResult
    private func waitForProductionReady(page: String) -> XCUIElement {
        let marker = element("production.root.visual-ready.\(page)")
        XCTAssertTrue(marker.waitForExistence(timeout: 10), "Missing production visualReady marker for \(page)")
        return marker
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func waitForSynchronizedPagerSelection(_ page: String) {
        let tab = app.buttons["main.timeline.\(page)"]
        expectation(
            for: NSPredicate(format: "isSelected == true"),
            evaluatedWith: tab
        )
        waitForExpectations(timeout: 5)

        XCTAssertTrue(tab.isSelected)
        for otherPage in ["home", "local", "global"] where otherPage != page {
            XCTAssertFalse(app.buttons["main.timeline.\(otherPage)"].isSelected)
        }
    }

    private func waitForProductionPagerSelection(_ page: String) {
        waitForSynchronizedPagerSelection(page)

        let selection = element("production.timeline.selection")
        expectation(
            for: NSPredicate(format: "value == %@", page),
            evaluatedWith: selection
        )
        waitForExpectations(timeout: 5)
        waitForProductionReady(page: page)
    }

    private func swipeProductionPagerLeft() {
        dragProductionPager(from: 0.8, to: 0.2)
    }

    private func swipeProductionPagerRight() {
        dragProductionPager(from: 0.2, to: 0.8)
    }

    private func dragProductionPager(from startX: CGFloat, to endX: CGFloat) {
        let pagerSurface = element("main.content.home")
        XCTAssertTrue(pagerSurface.waitForExistence(timeout: 5))
        let start = pagerSurface.coordinate(
            withNormalizedOffset: CGVector(dx: startX, dy: 0.5)
        )
        let end = pagerSurface.coordinate(
            withNormalizedOffset: CGVector(dx: endX, dy: 0.5)
        )
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func waitForAccount(_ accountID: String) {
        let accountButton = app.buttons["main.header.account"]
        let predicate = NSPredicate(format: "value == %@", accountID)
        expectation(for: predicate, evaluatedWith: accountButton)
        waitForExpectations(timeout: 5)
    }

    private func waitForNonTopValue(_ marker: XCUIElement) -> String {
        let predicate = NSPredicate(format: "value != %@", "top")
        expectation(for: predicate, evaluatedWith: marker)
        waitForExpectations(timeout: 5)
        return marker.value as? String ?? ""
    }

    private func captureStableFixture(page: String, name: String) {
        waitForReady(page: page)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
