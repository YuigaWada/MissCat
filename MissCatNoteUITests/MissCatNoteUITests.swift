import XCTest

final class MissCatNoteUITests: XCTestCase {
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

    func testThreadTapAndDeterministicContentScreenshot() {
        launchContent()
        rootBody.tap()
        XCTAssertTrue(app.navigationBars["Thread"].exists)
        XCTAssertTrue(reveal(app.buttons["MissCat SwiftUI migration。リンクを開く"]))
        XCTAssertTrue(reveal(replyBody))
        attachScreenshot(name: "note-detail-content", application: app)
    }

    func testMediaViewerSupportsTapAndHorizontalSwipe() {
        launchContent()
        let firstMedia = app.buttons["街の写真"]
        XCTAssertTrue(reveal(firstMedia))
        firstMedia.tap()

        XCTAssertTrue(app.staticTexts["1 / 3"].waitForExistence(timeout: 3))
        app.swipeLeft()
        XCTAssertTrue(app.staticTexts["2 / 3"].waitForExistence(timeout: 3))
        app.swipeRight()
        XCTAssertTrue(app.staticTexts["1 / 3"].waitForExistence(timeout: 3))
        attachScreenshot(name: "note-media-viewer", application: app)

        app.buttons["閉じる"].tap()
        XCTAssertTrue(app.navigationBars["Thread"].waitForExistence(timeout: 3))
    }

    func testOverflowExposesRealNoteActions() {
        launchContent()
        let overflow = app.buttons.matching(
            NSPredicate(format: "label == %@", "その他")
        ).element(boundBy: 1)
        XCTAssertTrue(reveal(overflow))
        overflow.tap()

        XCTAssertTrue(app.buttons["お気に入り"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["リンクをコピー"].exists)
        XCTAssertTrue(app.buttons["ブラウザで開く"].exists)
        XCTAssertTrue(app.buttons["削除"].exists)
        attachScreenshot(name: "note-overflow-actions", application: app)
    }

    func testTerminalEmptyErrorAndOfflineStatesHaveDeterministicMarkers() {
        for (state, title) in [
            ("empty", "ノートがありません"),
            ("error", "スレッドを読み込めません"),
            ("offline", "オフラインです"),
        ] {
            app?.terminate()
            app = launch(state: state)
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 4), state)
            attachScreenshot(name: "note-detail-\(state)", application: app)
        }
    }

    private func launch(state: String) -> XCUIApplication {
        let application = XCUIApplication()
        application.launchArguments = ["--note-detail-fixture"]
        application.launchEnvironment = [
            "MISS_CAT_NOTE_FIXTURE_STATE": state,
            "MISS_CAT_NOTE_FIXTURE_APPEARANCE": "light",
            "AppleLanguages": "(ja)",
            "AppleLocale": "ja_JP",
        ]
        application.launch()
        return application
    }

    private func launchContent() {
        app = launch(state: "content")
        XCTAssertTrue(app.navigationBars["Thread"].waitForExistence(timeout: 5))
        XCTAssertTrue(rootBody.waitForExistence(timeout: 5))
    }

    private func reveal(_ element: XCUIElement, maximumSwipes: Int = 5) -> Bool {
        if element.waitForExistence(timeout: 1), element.isHittable { return true }
        for _ in 0..<maximumSwipes {
            app.swipeUp()
            if element.waitForExistence(timeout: 1), element.isHittable { return true }
        }
        return false
    }

    private var rootBody: XCUIElement {
        app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "回転タグは安全に無視")
        ).firstMatch
    }

    private var replyBody: XCUIElement {
        app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "メディアをタップして")
        ).firstMatch
    }

    private func attachScreenshot(name: String, application: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: application.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
