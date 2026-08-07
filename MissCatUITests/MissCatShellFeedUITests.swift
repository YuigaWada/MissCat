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

        app.buttons["main.tab.notifications"].tap()
        XCTAssertTrue(element("notifications.screen").waitForExistence(timeout: 5))
        app.buttons["main.header.account"].tap()
        app.buttons["main.account.https://fixture.example|fixture-cat"].tap()
        waitForProductionReady(page: "home")
        app.buttons["main.tab.notifications"].tap()
        XCTAssertTrue(element("notifications.screen").waitForExistence(timeout: 5))
        waitForAccount("https://fixture.example|fixture-cat")
        app.buttons["main.tab.home"].tap()
        waitForProductionReady(page: "home")

        let persistedAccount = element("production.root.persisted-account")
        XCTAssertTrue(persistedAccount.waitForExistence(timeout: 5))
        let persistedAccountBeforeCompose = persistedAccount.value as? String
        XCTAssertFalse(persistedAccountBeforeCompose?.isEmpty ?? true)
        let primaryComposeAccountID =
            "misscat-account-v2:Zml4dHVyZS5leGFtcGxl:Zml4dHVyZS1jYXQ="
        let secondaryComposeAccountID =
            "misscat-account-v2:c29jaWFsLmV4YW1wbGU=:Zml4dHVyZS1jYXQ="
        XCTAssertEqual(persistedAccountBeforeCompose, primaryComposeAccountID)

        app.buttons["main.action.compose"].tap()
        XCTAssertTrue(app.buttons["compose.cancel"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts["エラー"].exists)
        app.buttons["compose.account"].tap()
        XCTAssertTrue(element("compose.account.screen").waitForExistence(timeout: 5))
        let composeAccounts = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "compose.account.misscat-account-v2:")
        )
        XCTAssertEqual(
            composeAccounts.count,
            2,
            "Production Compose must preserve every root-authorized account"
        )
        app.buttons["compose.account.\(secondaryComposeAccountID)"].tap()
        app.buttons["compose.cancel"].tap()
        XCTAssertTrue(element("production.root").waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts["エラー"].exists)
        XCTAssertEqual(persistedAccount.value as? String, persistedAccountBeforeCompose)
        XCTAssertEqual(
            element("production.root.compose-selection-request").value as? String,
            secondaryComposeAccountID
        )
        app.buttons["main.tab.notifications"].tap()
        XCTAssertTrue(element("notifications.screen").waitForExistence(timeout: 5))
        waitForAccount("https://fixture.example|fixture-cat")
        app.buttons["main.tab.home"].tap()
        waitForProductionReady(page: "home")

        app.buttons["main.action.compose"].tap()
        XCTAssertTrue(app.buttons["compose.cancel"].waitForExistence(timeout: 5))
        app.buttons["compose.account"].tap()
        XCTAssertTrue(element("compose.account.screen").waitForExistence(timeout: 5))
        app.buttons["compose.account.\(secondaryComposeAccountID)"].tap()
        let composeText = app.textViews["compose.text"]
        XCTAssertTrue(composeText.waitForExistence(timeout: 5))
        composeText.tap()
        composeText.typeText("production scope isolation")
        app.buttons["compose.submit"].tap()
        XCTAssertTrue(element("production.root").waitForExistence(timeout: 10))
        XCTAssertEqual(persistedAccount.value as? String, persistedAccountBeforeCompose)
        XCTAssertEqual(
            element("production.root.compose-submission-account").value as? String,
            secondaryComposeAccountID
        )
        let isolationEvidence = XCTAttachment(
            string: [
                "persisted=\(persistedAccount.value as? String ?? "missing")",
                "selected=\(element("production.root.compose-selection-request").value as? String ?? "missing")",
                "submitted=\(element("production.root.compose-submission-account").value as? String ?? "missing")",
            ].joined(separator: "\n")
        )
        isolationEvidence.name = "production-compose-account-isolation-state"
        isolationEvidence.lifetime = .keepAlways
        add(isolationEvidence)
        app.buttons["main.tab.notifications"].tap()
        XCTAssertTrue(element("notifications.screen").waitForExistence(timeout: 5))
        waitForAccount("https://fixture.example|fixture-cat")

        app.buttons["main.tab.messages"].tap()
        XCTAssertTrue(element("messages.history.screen").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["メッセージはありません"].exists)
        app.buttons["main.tab.profile"].tap()
        app.buttons["main.header.settings"].tap()
        XCTAssertTrue(element("settings.root.visualReady").waitForExistence(timeout: 5))
        app.buttons["settings.close"].tap()
        XCTAssertTrue(element("production.root").waitForExistence(timeout: 5))
    }

    func testProductionRootOwnsProfileDiscoveryDetailReactionAndSystemShareRoutes() {
        app.launchArguments = ["--misscat-production-root-e2e"]
        app.launch()

        XCTAssertTrue(element("production.root").waitForExistence(timeout: 10))
        waitForProductionReady(page: "home")
        assertProductionAccountGenerationIsPrimary()
        waitForProductionRoute("root:home")

        app.buttons["note.home-0.author"].tap()
        waitForProductionRoute("profile:fixture-author-0")
        XCTAssertTrue(element("profile.other.screen").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["profile.action.back"].waitForExistence(timeout: 5))
        assertProductionAccountGenerationIsPrimary()

        captureProductionRoute(name: "production-profile-route")
        app.buttons["profile.count.followers"].tap()
        waitForProductionRoute("profile-list:followers-fixture-author-0")
        waitForProductionValue(identifier: "profile.userList.visualReady", value: "true")
        XCTAssertTrue(element("profile.user.fixture-author-0").waitForExistence(timeout: 5))
        captureProductionRoute(name: "production-profile-followers-route")

        element("profile.user.fixture-author-0").tap()
        waitForProductionRoute("profile:fixture-author-0")
        XCTAssertTrue(element("profile.other.screen").waitForExistence(timeout: 5))
        app.buttons["profile.action.back"].tap()
        waitForProductionRoute("profile-list:followers-fixture-author-0")
        XCTAssertTrue(app.buttons["production.route.back"].waitForExistence(timeout: 5))
        app.buttons["production.route.back"].tap()
        waitForProductionRoute("profile:fixture-author-0")
        XCTAssertTrue(app.buttons["profile.action.back"].waitForExistence(timeout: 5))
        app.buttons["profile.action.back"].tap()
        waitForProductionRoute("root:home")

        let noteBody = element("note.home-0.body")
        XCTAssertTrue(noteBody.waitForExistence(timeout: 5))
        noteBody.tap()
        waitForProductionRoute("note:home-0")
        XCTAssertTrue(element("note.detail.screen").waitForExistence(timeout: 5))
        XCTAssertTrue(element("note.detail.thread").waitForExistence(timeout: 5))
        assertProductionAccountGenerationIsPrimary()
        app.buttons["production.route.back"].tap()
        waitForProductionRoute("root:home")

        app.buttons["main.timeline.search"].tap()
        waitForProductionRoute("discovery")
        XCTAssertTrue(element("home.discovery.native-page").waitForExistence(timeout: 5))
        XCTAssertTrue(element("discovery.trends.list").waitForExistence(timeout: 5))
        app.buttons["discovery.trend.SwiftUI"].tap()
        waitForProductionRoute("search:SwiftUI")
        XCTAssertTrue(element("feed.search-results").waitForExistence(timeout: 5))
        assertProductionAccountGenerationIsPrimary()
        app.buttons["production.route.back"].tap()
        waitForProductionRoute("discovery")
        app.buttons["production.route.back"].tap()
        waitForProductionRoute("root:home")

        app.buttons["note.home-0.action.reaction"].tap()
        waitForProductionSheet("reaction:home-0")
        XCTAssertTrue(element("reaction.picker").waitForExistence(timeout: 5))
        let thumbsUp = element("reaction.picker.choice.👍")
        XCTAssertTrue(thumbsUp.waitForExistence(timeout: 5))
        thumbsUp.tap()
        XCTAssertTrue(element("feed.banner.error").waitForExistence(timeout: 5))
        XCTAssertFalse(
            element("note.home-0.reaction.👍").exists,
            "Failed optimistic mutation must roll the reaction chip back"
        )
        app.buttons["feed.banner.dismiss"].tap()

        app.buttons["note.home-0.action.reaction"].tap()
        waitForProductionSheet("reaction:home-0")
        let retryThumbsUp = element("reaction.picker.choice.👍")
        XCTAssertTrue(retryThumbsUp.waitForExistence(timeout: 5))
        retryThumbsUp.tap()
        XCTAssertTrue(
            element("note.home-0.reaction.👍").waitForExistence(timeout: 5),
            "Successful retry must commit the reaction mutation"
        )
        XCTAssertFalse(element("feed.banner.error").exists)
        assertProductionAccountGenerationIsPrimary()

        app.buttons["note.home-0.action.overflow"].tap()
        XCTAssertTrue(
            app.buttons["note.home-0.overflow.share"].waitForExistence(timeout: 5)
        )
        app.buttons["note.home-0.overflow.share"].tap()
        waitForProductionSheet("share:home-0")
        XCTAssertTrue(element("share.sheet").waitForExistence(timeout: 5))
        let shareLink = app.buttons["share.link"]
        XCTAssertTrue(shareLink.waitForExistence(timeout: 5))
        shareLink.tap()
        waitForSystemShareSheet()
        captureProductionRoute(name: "production-system-share-sheet")
    }

    func testFourConfiguredTimelineTabsSupportOrdinaryTapSwipeAndBoundaries() {
        launchFixture("--swiftui-shell-fixture-four-tabs")
        waitForReady(page: "home")
        waitForSynchronizedPagerSelection("home")

        app.buttons["main.timeline.social"].tap()
        waitForSynchronizedPagerSelection("social")
        waitForReady(page: "social")

        let pager = app.collectionViews.firstMatch
        XCTAssertTrue(pager.waitForExistence(timeout: 5))
        pager.swipeLeft()
        waitForSynchronizedPagerSelection("global")
        waitForReady(page: "global")
        pager.swipeLeft()
        waitForSynchronizedPagerSelection("global")

        pager.swipeRight()
        waitForSynchronizedPagerSelection("social")
        pager.swipeRight()
        waitForSynchronizedPagerSelection("local")
        pager.swipeRight()
        waitForSynchronizedPagerSelection("home")
        pager.swipeRight()
        waitForSynchronizedPagerSelection("home")
    }

    func testTimelineRefreshPaginationActionsAndDetailNavigation() {
        launchFixture(
            "--swiftui-shell-fixture-actions",
            "--swiftui-shell-fixture-pagination"
        )
        waitForReady(page: "home")
        let feed = app.scrollViews["feed.scroll"]
        XCTAssertTrue(feed.waitForExistence(timeout: 5))

        let refreshCompletion = element("feed.refresh.completed")
        XCTAssertTrue(refreshCompletion.waitForExistence(timeout: 3))
        XCTAssertEqual(refreshCompletion.value as? String, "0")
        feed.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.18))
            .press(
                forDuration: 0.15,
                thenDragTo: feed.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.82))
            )
        expectation(
            for: NSPredicate(format: "value == %@", "1"),
            evaluatedWith: refreshCompletion
        )
        waitForExpectations(timeout: 5)

        let firstReaction = app.buttons["note.home-0.action.reaction"]
        XCTAssertTrue(firstReaction.waitForExistence(timeout: 5))
        firstReaction.tap()
        XCTAssertTrue(element("reaction.picker").waitForExistence(timeout: 3))
        app.buttons["reaction.picker.choice.❤️"].tap()
        XCTAssertTrue(app.buttons["note.home-0.reaction.❤️"].waitForExistence(timeout: 3))

        app.buttons["note.home-0.action.reply"].tap()
        let editor = app.textViews["compose.text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.tap()
        editor.typeText("Timeline reply E2E")
        app.buttons["compose.submit"].tap()
        XCTAssertTrue(firstReaction.waitForExistence(timeout: 5))

        let renote = app.buttons["note.home-0.action.renote"]
        XCTAssertTrue(renote.waitForExistence(timeout: 5))
        renote.tap()
        let quote = app.buttons["timeline.renote.quote"]
        XCTAssertTrue(quote.waitForExistence(timeout: 3))
        quote.tap()
        XCTAssertEqual(element("compose.mode").label, "引用Renote")
        let quoteEditor = app.textViews["compose.text"]
        XCTAssertTrue(quoteEditor.waitForExistence(timeout: 3))
        quoteEditor.tap()
        quoteEditor.typeText("Timeline quote E2E")
        app.buttons["compose.submit"].tap()
        XCTAssertTrue(renote.waitForExistence(timeout: 5))

        renote.tap()
        let confirmRenote = app.buttons["timeline.renote.confirm"]
        XCTAssertTrue(confirmRenote.waitForExistence(timeout: 3))
        confirmRenote.tap()
        XCTAssertTrue(renote.waitForExistence(timeout: 5))

        app.buttons["note.home-0.action.overflow"].tap()
        let copyText = app.buttons["note.home-0.overflow.copy-text"]
        XCTAssertTrue(copyText.waitForExistence(timeout: 3))
        copyText.tap()
        waitForClipboardValue(
            "SwiftUI native timeline fixture 🐈 @alice https://fixture.example/notes/home-0 #SwiftUI"
        )

        let overflow = app.buttons["note.home-0.action.overflow"]
        XCTAssertTrue(overflow.waitForExistence(timeout: 3))
        overflow.tap()
        let copyLink = app.buttons["note.home-0.overflow.copy-link"]
        XCTAssertTrue(copyLink.waitForExistence(timeout: 3))
        copyLink.tap()
        waitForClipboardValue("https://fixture.example/notes/home-0")

        XCTAssertTrue(overflow.waitForExistence(timeout: 3))
        overflow.tap()
        XCTAssertTrue(app.buttons["note.home-0.overflow.share"].exists)
        XCTAssertTrue(app.buttons["note.home-0.overflow.block"].exists)
        let report = app.buttons["note.home-0.overflow.report"]
        XCTAssertTrue(report.waitForExistence(timeout: 3))
        report.tap()
        XCTAssertTrue(app.alerts["このユーザーを通報"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["timeline.report.confirm"].isEnabled)
        app.alerts.buttons["キャンセル"].tap()

        app.buttons["note.home-0.action.overflow"].tap()
        let showDetail = app.buttons["note.home-0.overflow.detail"]
        XCTAssertTrue(showDetail.waitForExistence(timeout: 3))
        showDetail.tap()
        XCTAssertTrue(element("note.detail.screen").waitForExistence(timeout: 5))
        XCTAssertTrue(element("note.detail.thread").exists)

        let thirdReply = element("note.row.home-0-reply-page3")
        for _ in 0..<8 where !thirdReply.exists {
            element("note.detail.thread").swipeUp()
        }
        XCTAssertTrue(thirdReply.waitForExistence(timeout: 5))
        XCTAssertEqual(
            app.descendants(matching: .any)
                .matching(identifier: "note.row.home-0-reply-page1").count,
            1
        )
        XCTAssertEqual(
            app.descendants(matching: .any)
                .matching(identifier: "note.row.home-0-reply-page2").count,
            1
        )
        let terminal = element("note.detail.pagination.terminal")
        XCTAssertTrue(terminal.waitForExistence(timeout: 3))
        XCTAssertEqual(terminal.value as? String, "3")
        XCTAssertEqual(element("note.detail.pagination.cursor").value as? String, "home-0-reply-page3")

        let detailRefreshCompletion = element("note.detail.refresh.completed")
        XCTAssertEqual(detailRefreshCompletion.value as? String, "0")
        app.buttons["note.detail.refresh"].tap()
        expectation(
            for: NSPredicate(format: "value == %@", "1"),
            evaluatedWith: detailRefreshCompletion
        )
        waitForExpectations(timeout: 5)
        XCTAssertTrue(element("note.row.home-0-reply-refreshed").waitForExistence(timeout: 3))
        XCTAssertFalse(element("note.row.home-0-reply-page2").exists)
        XCTAssertEqual(element("note.detail.pagination.terminal").value as? String, "1")
        XCTAssertEqual(
            element("note.detail.pagination.cursor").value as? String,
            "home-0-reply-refreshed"
        )

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(feed.waitForExistence(timeout: 5))
        let pageTwo = element("note.row.home-page2-0")
        for _ in 0..<12 where !pageTwo.exists {
            feed.swipeUp()
        }
        XCTAssertTrue(pageTwo.waitForExistence(timeout: 5))
    }

    func testTimelineMentionResolvesToNativeProfile() {
        launchFixture("--swiftui-shell-fixture-actions")
        waitForReady(page: "home")

        let body = element("note.home-0.body")
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        XCTAssertTrue(body.label.localizedCaseInsensitiveContains("alice"))
        body.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.2)).tap()

        XCTAssertTrue(element("fixture.profile.screen").waitForExistence(timeout: 5))
        XCTAssertEqual(element("fixture.profile.user-id").label, "fixture-mentioned-user")
    }

    func testTimelineSharePresentsSystemActivitySheet() {
        launchFixture("--swiftui-shell-fixture-actions")
        waitForReady(page: "home")

        app.buttons["note.home-0.action.overflow"].tap()
        let share = app.buttons["note.home-0.overflow.share"]
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        share.tap()

        let activityList = app.otherElements["ActivityListView"]
        XCTAssertTrue(
            activityList.waitForExistence(timeout: 5),
            "ShareLink did not present the native activity sheet"
        )
        activityList.swipeDown()
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
        XCTAssertFalse(app.buttons["settings.license.Firebase"].exists)
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
        XCTAssertTrue(marker.waitForExistence(timeout: 20), "Missing stable visualReady marker for \(page)")
        return marker
    }

    @discardableResult
    private func waitForProductionReady(page: String) -> XCUIElement {
        let marker = element("production.root.visual-ready.\(page)")
        XCTAssertTrue(marker.waitForExistence(timeout: 10), "Missing production visualReady marker for \(page)")
        return marker
    }

    private func waitForProductionRoute(_ route: String) {
        waitForProductionValue(identifier: "production.root.route", value: route)
    }

    private func waitForProductionSheet(_ destination: String) {
        waitForProductionValue(identifier: "production.sheet.destination", value: destination)
    }

    @discardableResult
    private func waitForSystemShareSheet() -> XCUIElement {
        let remoteContainerIdentifiers = [
            "ActivityListView",
            "ShareSheet.RemoteContainerView",
            "UIActivityContentView",
        ]
        let remoteContainer = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier IN %@", remoteContainerIdentifiers))
            .firstMatch
        XCTAssertTrue(
            remoteContainer.waitForExistence(timeout: 8),
            "ShareLink must reach the system activity sheet"
        )

        // The share UI is owned by a remote system process, but XCTest projects it into
        // the host app's accessibility tree. Keep the query rooted at `app`; do not launch
        // or infer a second XCUIApplication from the remote process PID.
        let auxiliarySystemControl = app.descendants(matching: .any)
            .matching(
                NSPredicate(
                    format: "identifier == %@ OR (identifier == %@ AND label == %@)",
                    "header.closeButton",
                    "actionGroupCell",
                    "Copy"
                )
            )
            .firstMatch
        XCTAssertTrue(
            auxiliarySystemControl.waitForExistence(timeout: 5),
            "System activity sheet must expose its close button or Copy action"
        )
        return remoteContainer
    }

    private func waitForProductionValue(identifier: String, value: String) {
        let marker = element(identifier)
        XCTAssertTrue(marker.waitForExistence(timeout: 5), "Missing marker \(identifier)")
        expectation(
            for: NSPredicate(format: "value == %@", value),
            evaluatedWith: marker
        )
        waitForExpectations(timeout: 5)
    }

    private func assertProductionAccountGenerationIsPrimary() {
        waitForProductionValue(
            identifier: "production.root.persisted-account",
            value: "misscat-account-v2:Zml4dHVyZS5leGFtcGxl:Zml4dHVyZS1jYXQ="
        )
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
        for otherPage in ["home", "local", "social", "global"] where otherPage != page {
            let candidate = app.buttons["main.timeline.\(otherPage)"]
            if candidate.exists {
                XCTAssertFalse(candidate.isSelected)
            }
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

    private func waitForClipboardValue(_ expected: String) {
        let probe = element("fixture.clipboard.value")
        XCTAssertTrue(probe.waitForExistence(timeout: 3))
        expectation(
            for: NSPredicate(format: "value == %@", expected),
            evaluatedWith: probe
        )
        waitForExpectations(timeout: 3)
    }

    private func captureStableFixture(page: String, name: String) {
        waitForReady(page: page)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func captureProductionRoute(name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
