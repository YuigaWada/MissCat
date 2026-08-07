import XCTest

@MainActor
final class MissCatNoteUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() {
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

    func testNativeNoteActionsRunEndToEnd() {
        app = launchCandidate(state: "content")
        XCTAssertTrue(reveal(rootAction("reaction")))
        rootAction("reaction").tap()
        XCTAssertTrue(element("reaction.picker").waitForExistence(timeout: 3))
        app.buttons["reaction.picker.choice.❤️"].tap()
        XCTAssertTrue(app.buttons["note.fixture-root.reaction.❤️"].waitForExistence(timeout: 3))

        rootAction("reply").tap()
        let replyEditor = app.textViews["compose.text"]
        XCTAssertTrue(replyEditor.waitForExistence(timeout: 3))
        replyEditor.tap()
        replyEditor.typeText("SwiftUI reply E2E")
        app.buttons["compose.submit"].tap()
        XCTAssertTrue(rootAction("reply").waitForExistence(timeout: 3))

        rootAction("renote").tap()
        XCTAssertTrue(app.buttons["note.renote.quote"].waitForExistence(timeout: 2))
        app.buttons["note.renote.quote"].tap()
        let quoteEditor = app.textViews["compose.text"]
        XCTAssertTrue(quoteEditor.waitForExistence(timeout: 3))
        quoteEditor.tap()
        quoteEditor.typeText("SwiftUI quote E2E")
        app.buttons["compose.submit"].tap()
        XCTAssertTrue(rootAction("renote").waitForExistence(timeout: 3))

        rootAction("renote").tap()
        app.buttons["note.renote.confirm"].tap()
        XCTAssertTrue(rootAction("renote").waitForExistence(timeout: 3))
    }

    func testNativeOverflowOwnOtherConfirmationsAndActionRetry() {
        app = launchCandidate(state: "content")
        XCTAssertTrue(reveal(rootAction("overflow")))
        rootAction("overflow").tap()
        XCTAssertTrue(app.buttons["削除"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["このユーザーをミュート"].exists)
        app.buttons["削除"].tap()
        XCTAssertTrue(app.alerts["ノートを削除しますか？"].waitForExistence(timeout: 2))
        app.buttons["キャンセル"].tap()

        XCTAssertTrue(revealFromTop(otherAction("overflow")))
        otherAction("overflow").tap()
        XCTAssertTrue(app.buttons["このユーザーをミュート"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["削除"].exists)
        app.buttons["このユーザーをミュート"].tap()
        XCTAssertTrue(app.alerts["このユーザーをミュートしますか？"].waitForExistence(timeout: 2))
        app.buttons["キャンセル"].tap()

        app.terminate()
        app = launchCandidate(state: "action-failure")
        XCTAssertTrue(reveal(rootAction("renote")))
        rootAction("renote").tap()
        app.buttons["note.renote.confirm"].tap()
        XCTAssertTrue(app.alerts["エラー"].waitForExistence(timeout: 3))
        app.alerts["エラー"].buttons["再試行"].tap()
        XCTAssertFalse(app.alerts["エラー"].waitForExistence(timeout: 1))
    }

    func testNativeURLAndReactionFailuresRetryToContent() {
        app = launchCandidate(state: "preview-failure")
        XCTAssertTrue(reveal(app.buttons["note.url-preview.retry"]))
        XCTAssertTrue(app.buttons["note.url-preview.fallback"].exists)
        XCTAssertTrue(app.buttons["note.url-preview.content"].exists)
        app.buttons["note.url-preview.retry"].tap()
        XCTAssertTrue(app.buttons["note.url-preview.content"].waitForExistence(timeout: 4))

        app.terminate()
        app = launchCandidate(state: "reaction-error")
        XCTAssertTrue(reveal(rootAction("reaction")))
        rootAction("reaction").tap()
        XCTAssertTrue(app.buttons["reaction.picker.retry"].waitForExistence(timeout: 3))
        app.buttons["reaction.picker.retry"].tap()
        XCTAssertTrue(app.buttons["reaction.picker.choice.:misscat:"].waitForExistence(timeout: 3))
    }

    func testOrdinaryNotificationRouteRunsTypedActionsWithoutFixtureRoot() {
        app = launchCandidate(state: "content")
        XCTAssertEqual(app.launchArguments, ["--note-actions-ordinary-route"])
        XCTAssertTrue(app.navigationBars["Thread"].waitForExistence(timeout: 5))

        XCTAssertTrue(reveal(rootAction("reaction")))
        rootAction("reaction").tap()
        app.buttons["reaction.picker.choice.❤️"].tap()
        XCTAssertTrue(app.buttons["note.fixture-root.reaction.❤️"].waitForExistence(timeout: 3))

        XCTAssertTrue(reveal(app.buttons["街の写真"]))
        app.buttons["街の写真"].tap()
        XCTAssertTrue(app.staticTexts["1 / 3"].waitForExistence(timeout: 3))
        app.swipeLeft()
        XCTAssertTrue(app.staticTexts["2 / 3"].waitForExistence(timeout: 3))
        app.buttons["閉じる"].tap()

        XCTAssertTrue(reveal(rootAction("overflow")))
        rootAction("overflow").tap()
        app.buttons["リンクをコピー"].tap()
        XCTAssertTrue(rootAction("overflow").waitForExistence(timeout: 3))

        rootAction("overflow").tap()
        app.buttons["お気に入り"].tap()
        XCTAssertTrue(rootAction("overflow").waitForExistence(timeout: 3))
    }

    func testOrdinaryNotificationRouteConfirmsDeleteAndMuteCallbacks() {
        app = launchCandidate(state: "content")
        XCTAssertTrue(reveal(rootAction("overflow")))
        rootAction("overflow").tap()
        app.buttons["削除"].tap()
        let deleteAlert = app.alerts["ノートを削除しますか？"]
        XCTAssertTrue(deleteAlert.waitForExistence(timeout: 2))
        deleteAlert.buttons["削除"].tap()
        XCTAssertTrue(waitForDisappearance(deleteAlert))

        app.terminate()
        app = launchCandidate(state: "content")
        XCTAssertTrue(revealFromTop(otherAction("overflow")))
        otherAction("overflow").tap()
        app.buttons["このユーザーをミュート"].tap()
        let muteAlert = app.alerts["このユーザーをミュートしますか？"]
        XCTAssertTrue(muteAlert.waitForExistence(timeout: 2))
        muteAlert.buttons["ミュート"].tap()
        XCTAssertTrue(waitForDisappearance(muteAlert))
    }

    /// Candidate captures enter through the ordinary UIKit Home and typed
    /// notification-note route, then compare against immutable references.
    func testNativeNoteFamilyCandidateCaptures() {
        captureCandidate(state: "content")

        app.terminate()
        app = launchCandidate(state: "content")
        XCTAssertTrue(reveal(rootAction("reaction")))
        rootAction("reaction").tap()
        XCTAssertTrue(element("reaction.picker").waitForExistence(timeout: 3))
        attachScreenshot(name: "candidate-note-reaction-picker", application: app)

        app.terminate()
        app = launchCandidate(state: "content")
        XCTAssertTrue(reveal(rootAction("reply")))
        rootAction("reply").tap()
        XCTAssertTrue(app.staticTexts["compose.mode"].waitForExistence(timeout: 3))
        attachScreenshot(name: "candidate-note-reply-compose", application: app)

        app.terminate()
        app = launchCandidate(state: "content")
        XCTAssertTrue(reveal(rootAction("renote")))
        rootAction("renote").tap()
        app.buttons["note.renote.quote"].tap()
        XCTAssertTrue(app.staticTexts["compose.mode"].waitForExistence(timeout: 3))
        attachScreenshot(name: "candidate-note-quote-compose", application: app)

        app.terminate()
        app = launchCandidate(state: "content")
        XCTAssertTrue(reveal(rootAction("overflow")))
        rootAction("overflow").tap()
        XCTAssertTrue(app.buttons["削除"].waitForExistence(timeout: 2))
        attachScreenshot(name: "candidate-note-overflow-own", application: app)

        app.terminate()
        app = launchCandidate(state: "content")
        XCTAssertTrue(reveal(otherAction("overflow")))
        otherAction("overflow").tap()
        XCTAssertTrue(app.buttons["このユーザーをミュート"].waitForExistence(timeout: 2))
        attachScreenshot(name: "candidate-note-overflow-other", application: app)

        app.terminate()
        app = launchCandidate(state: "preview-failure")
        XCTAssertTrue(reveal(app.buttons["note.url-preview.retry"]))
        attachScreenshot(name: "candidate-note-preview-failure", application: app)

        app.terminate()
        app = launchCandidate(state: "content")
        XCTAssertTrue(reveal(rootAction("overflow")))
        rootAction("overflow").tap()
        app.buttons["削除"].tap()
        XCTAssertTrue(app.alerts["ノートを削除しますか？"].waitForExistence(timeout: 2))
        attachScreenshot(name: "candidate-note-delete-confirmation", application: app)
    }

    private func launch(state: String) -> XCUIApplication {
        let application = XCUIApplication()
        application.launchArguments = ["--note-actions-ordinary-route"]
        application.launchEnvironment = [
            "MISS_CAT_NOTE_ORDINARY_STATE": state,
            "AppleLanguages": "(ja)",
            "AppleLocale": "ja_JP",
        ]
        application.launch()
        return application
    }

    private func launchCandidate(state: String) -> XCUIApplication {
        let application = XCUIApplication()
        application.launchArguments = ["--note-actions-ordinary-route"]
        application.launchEnvironment = [
            "MISS_CAT_NOTE_ORDINARY_STATE": state,
            "MISS_CAT_NOTE_CANDIDATE_BUILD": "swiftui-note-actions-v1",
            "AppleLanguages": "(ja)",
            "AppleLocale": "ja_JP",
        ]
        application.launch()
        return application
    }

    private func captureCandidate(state: String) {
        app?.terminate()
        app = launchCandidate(state: state)
        XCTAssertTrue(app.navigationBars["Thread"].waitForExistence(timeout: 5))
        XCTAssertTrue(rootBody.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["note.url-preview.content"].waitForExistence(timeout: 5))
        attachScreenshot(name: "candidate-note-\(state)", application: app)
    }

    private func rootAction(_ action: String) -> XCUIElement {
        app.buttons["note.fixture-root.action.\(action)"]
    }

    private func otherAction(_ action: String) -> XCUIElement {
        app.buttons["note.fixture-ancestor.action.\(action)"]
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
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

    private func revealFromTop(_ element: XCUIElement, maximumSwipes: Int = 5) -> Bool {
        for _ in 0..<maximumSwipes { app.swipeDown() }
        return reveal(element, maximumSwipes: maximumSwipes)
    }

    private func waitForDisappearance(
        _ element: XCUIElement,
        timeout: TimeInterval = 2
    ) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
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
