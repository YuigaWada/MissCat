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

        app.buttons["main.timeline.local"].tap()
        waitForPagerSelection("local")
        waitForReady(page: "local")

        let pager = app.collectionViews.firstMatch
        XCTAssertTrue(pager.waitForExistence(timeout: 5))
        pager.swipeLeft()
        waitForPagerSelection("global")
        waitForReady(page: "global")
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

    private func launchFixture(_ extraArguments: String...) {
        app.launchArguments = ["--swiftui-shell-fixture"] + extraArguments
        app.launch()
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

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func waitForPagerSelection(_ page: String) {
        let tab = app.buttons["main.timeline.\(page)"]
        let predicate = NSPredicate(format: "isSelected == true")
        expectation(for: predicate, evaluatedWith: tab)
        waitForExpectations(timeout: 5)
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
