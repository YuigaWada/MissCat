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
        XCTAssertTrue(app.buttons["投稿"].isSelected)

        app.buttons["ユーザー"].tap()
        XCTAssertTrue(firstUser.waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["ユーザー"].isSelected)
        attachScreenshot("discovery-search-users")
        dragResults(from: app.buttons["投稿"], to: app.buttons["ユーザー"])
        XCTAssertTrue(noteResult.waitForExistence(timeout: 4))
        dragResults(from: app.buttons["ユーザー"], to: app.buttons["投稿"])
        XCTAssertTrue(firstUser.waitForExistence(timeout: 4))
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

    private func dragResults(from source: XCUIElement, to destination: XCUIElement) {
        let start = source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = destination.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
