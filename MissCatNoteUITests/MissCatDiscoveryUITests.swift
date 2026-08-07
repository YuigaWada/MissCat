import XCTest

final class MissCatDiscoveryUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() {
        app?.terminate()
        app = nil
        super.tearDown()
    }

    func testTrendTapSearchesAndResultTabsSupportTapAndSwipe() {
        app = launch(state: "content")
        XCTAssertTrue(app.staticTexts["Fixture.exampleでのトレンド"].waitForExistence(timeout: 5))
        attachScreenshot("discovery-trends")

        app.buttons["discovery.trend.SwiftUI"].tap()
        XCTAssertTrue(noteResult.waitForExistence(timeout: 5))
        XCTAssertTrue(notesTab.isSelected)

        // Swiping right at the first page is a boundary no-op. This begins in
        // the center of the result pane rather than on the tab strip.
        XCTAssertTrue(noteList.waitForExistence(timeout: 4))
        noteList.swipeRight()
        XCTAssertTrue(notesTab.isSelected)
        XCTAssertTrue(noteResult.exists)

        usersTab.tap()
        XCTAssertTrue(firstUser.waitForExistence(timeout: 4))
        XCTAssertTrue(usersTab.isSelected)
        attachScreenshot("discovery-search-users")

        // A real right swipe starts in the user result pane and returns to the
        // note page. It must update the same selected-tab state as a tap.
        XCTAssertTrue(userList.waitForExistence(timeout: 4))
        userList.swipeRight()
        XCTAssertTrue(noteResult.waitForExistence(timeout: 4))
        XCTAssertTrue(notesTab.isSelected)

        // A real left swipe starts in the note result pane and advances to the
        // user page. A second left swipe proves the last-page boundary.
        XCTAssertTrue(noteList.waitForExistence(timeout: 4))
        noteList.swipeLeft()
        XCTAssertTrue(firstUser.waitForExistence(timeout: 4))
        XCTAssertTrue(usersTab.isSelected)
        XCTAssertTrue(userList.waitForExistence(timeout: 4))
        userList.swipeLeft()
        XCTAssertTrue(usersTab.isSelected)
        XCTAssertTrue(firstUser.exists)
        attachScreenshot("discovery-result-pane-swipe-boundaries")
    }

    func testKeyboardSearchAndResultNavigation() {
        app = launch(state: "content")
        let query = app.textFields["discovery.query"]
        XCTAssertTrue(query.waitForExistence(timeout: 4))
        query.tap()
        query.typeText("native")
        query.typeText("\n")

        XCTAssertTrue(noteResult.waitForExistence(timeout: 5))
        noteResult.tap()
        XCTAssertTrue(app.navigationBars["Thread"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "詳細画面へ移動")
        ).firstMatch.waitForExistence(timeout: 5))
        attachScreenshot("discovery-note-navigation")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.buttons["ユーザー"].tap()
        XCTAssertTrue(firstUser.waitForExistence(timeout: 4))
        firstUser.tap()
        XCTAssertTrue(app.navigationBars["だわくん 🧃"].waitForExistence(timeout: 4))
        attachScreenshot("discovery-user-navigation")
    }

    func testPaginationFailureCanRetryWithoutLosingExistingResults() {
        app = launch(state: "pagination-error")
        app.buttons["discovery.trend.SwiftUI"].tap()
        XCTAssertTrue(noteResult.waitForExistence(timeout: 5))

        for _ in 0 ..< 5 { app.swipeUp() }
        let retry = app.buttons["discovery.pagination.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "検索結果 8")
        ).firstMatch.exists)
        retry.tap()
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "検索結果 9")
        ).firstMatch.waitForExistence(timeout: 5))
        attachScreenshot("discovery-pagination-recovered")
    }

    func testEmptyErrorAndOfflineStatesExposeDeterministicVisualReady() {
        for (state, title) in [
            ("empty", "トレンドはありません"),
            ("error", "トレンドを読み込めませんでした"),
            ("offline", "オフラインです"),
        ] {
            app?.terminate()
            app = launch(state: state)
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 5), state)
            XCTAssertEqual(app.staticTexts["discovery.visualReady"].value as? String, "true", state)
            attachScreenshot("discovery-\(state)")
        }
    }

    func testLoadingStateIsVisibleAndDoesNotClaimVisualReadiness() {
        app = launch(state: "loading")

        let loading = app.descendants(matching: .any)["discovery.trends.loading"]
        XCTAssertTrue(loading.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["トレンドを読み込み中…"].exists)
        XCTAssertFalse(app.staticTexts["discovery.visualReady"].exists)
        XCTAssertFalse(app.staticTexts["discovery.visualReady"].waitForExistence(timeout: 0.5))
        attachScreenshot("discovery-loading-unready")
    }

    private func launch(state: String) -> XCUIApplication {
        let application = XCUIApplication()
        application.launchArguments = ["--discovery-fixture"]
        application.launchEnvironment = [
            "MISS_CAT_DISCOVERY_FIXTURE_STATE": state,
            "MISS_CAT_DISCOVERY_FIXTURE_APPEARANCE": "light",
            "AppleLanguages": "(ja)",
            "AppleLocale": "ja_JP",
        ]
        application.launch()
        return application
    }

    private var noteResult: XCUIElement {
        app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "検索結果 1")
        ).firstMatch
    }

    private var firstUser: XCUIElement {
        app.buttons["discovery.user.fixture-user-0"]
    }

    private var notesTab: XCUIElement {
        app.buttons["discovery.tab.notes"]
    }

    private var usersTab: XCUIElement {
        app.buttons["discovery.tab.users"]
    }

    private var noteList: XCUIElement {
        app.scrollViews["discovery.notes.list"]
    }

    private var userList: XCUIElement {
        app.scrollViews["discovery.users.list"]
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
