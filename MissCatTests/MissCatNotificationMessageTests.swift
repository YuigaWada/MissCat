@testable import MissCat
import XCTest

private enum NotificationMessageTestError: LocalizedError {
    case failed

    var errorDescription: String? { "test failure" }
}

private final class MockNotificationMessagingRepository:
    MissCatNotificationsRepository,
    MissCatMessagingRepository
{
    let accountScope: MissCatAccountScope
    var notificationPages: [MissCatNotificationPage] = []
    var notificationRequests: [(cursor: String?, limit: Int)] = []
    var notificationError: Error?
    var notificationDelay: UInt64 = 0
    var resolvedNotifications: [String: MissCatNotification] = [:]
    var realtimeContinuation: AsyncStream<MissCatNotificationRealtimeEvent>.Continuation?

    var conversations: [MissCatConversation] = []
    var conversationError: Error?
    var messagePages: [MissCatMessagePage] = []
    var messageRequests: [(peerID: String, cursor: String?, limit: Int)] = []
    var sendResult: MissCatDirectMessage?
    var sendError: Error?
    var sendDelay: UInt64 = 0
    var sentTexts: [String] = []
    var sentRequestIDs: [UUID] = []

    init(accountID: String = "owner", host: String = "example.test") {
        accountScope = MissCatAccountScope(
            accountID: accountID,
            username: accountID,
            host: host,
            accessToken: "fixture-token"
        )
    }

    func fetchNotifications(cursor: String?, limit: Int) async throws -> MissCatNotificationPage {
        notificationRequests.append((cursor, limit))
        if notificationDelay > 0 { try await Task.sleep(nanoseconds: notificationDelay) }
        if let notificationError { throw notificationError }
        return notificationPages.isEmpty
            ? MissCatNotificationPage(notifications: [], hasMore: false)
            : notificationPages.removeFirst()
    }

    func resolveNotification(id: String) async throws -> MissCatNotification? {
        if let notificationError { throw notificationError }
        return resolvedNotifications[id]
    }

    func realtimeNotifications() -> AsyncStream<MissCatNotificationRealtimeEvent> {
        AsyncStream { realtimeContinuation = $0 }
    }

    func fetchConversations(limit _: Int) async throws -> [MissCatConversation] {
        if let conversationError { throw conversationError }
        return conversations
    }

    func fetchMessages(peer: MissCatPerson, cursor: String?, limit: Int) async throws -> MissCatMessagePage {
        messageRequests.append((peer.id, cursor, limit))
        return messagePages.isEmpty
            ? MissCatMessagePage(messages: [], hasMore: false)
            : messagePages.removeFirst()
    }

    func sendText(
        _ text: String,
        to _: MissCatPerson,
        requestID: UUID
    ) async throws -> MissCatDirectMessage {
        sentTexts.append(text)
        sentRequestIDs.append(requestID)
        if sendDelay > 0 { try await Task.sleep(nanoseconds: sendDelay) }
        if let sendError { throw sendError }
        guard let sendResult else { throw NotificationMessageTestError.failed }
        return sendResult
    }
}

@MainActor
final class MissCatNotificationMessageStoreTests: XCTestCase {
    func testAllSixNotificationVariantsHaveStablePresentationAndRoutes() {
        let actor = person("actor")
        for kind in MissCatNotificationKind.allCases {
            let item = notification(kind.rawValue, kind: kind, actor: actor)
            XCTAssertFalse(kind.localizedAction.isEmpty)
            XCTAssertFalse(kind.symbolName.isEmpty)
            if kind == .follow {
                XCTAssertEqual(item.preferredRoute, .user("actor"))
            } else {
                XCTAssertEqual(item.preferredRoute, .note("note-\(kind.rawValue)"))
            }
        }
        XCTAssertEqual(MissCatNotificationKind.allCases.count, 6)
    }

    func testNotificationInitialLoadSortsAndDeduplicates() async {
        let repository = MockNotificationMessagingRepository()
        repository.notificationPages = [
            .init(
                notifications: [
                    notification("old", date: Date(timeIntervalSince1970: 1)),
                    notification("new", date: Date(timeIntervalSince1970: 3)),
                    notification("old", date: Date(timeIntervalSince1970: 1))
                ],
                hasMore: true
            )
        ]
        let store = MissCatNotificationsStore(repository: repository, pageSize: 3)

        await store.loadInitial()

        XCTAssertEqual(store.phase, .loaded)
        XCTAssertEqual(store.notifications.map(\.id), ["new", "old"])
        XCTAssertTrue(store.canLoadMore)
        XCTAssertEqual(repository.notificationRequests.first?.limit, 3)
    }

    func testNotificationPaginationUsesLastCursorAndDeduplicates() async {
        let repository = MockNotificationMessagingRepository()
        repository.notificationPages = [
            .init(notifications: [notification("three"), notification("two")], hasMore: true),
            .init(notifications: [notification("two"), notification("one")], hasMore: false)
        ]
        let store = MissCatNotificationsStore(repository: repository, pageSize: 2)
        await store.loadInitial()

        await store.loadNextPageIfNeeded(currentID: "two")

        XCTAssertEqual(Set(store.notifications.map(\.id)), Set(["one", "two", "three"]))
        XCTAssertEqual(repository.notificationRequests.last?.cursor, "two")
        XCTAssertFalse(store.canLoadMore)
    }

    func testNotificationRefreshFromEmptyEstablishesPaginationCursor() async {
        let repository = MockNotificationMessagingRepository()
        repository.notificationPages = [
            .init(notifications: [], hasMore: false),
            .init(notifications: [notification("three"), notification("two")], hasMore: true),
            .init(notifications: [notification("one")], hasMore: false)
        ]
        let store = MissCatNotificationsStore(repository: repository, pageSize: 2)
        await store.loadInitial()

        await store.refresh()
        await store.loadNextPageIfNeeded(currentID: "two")

        XCTAssertEqual(repository.notificationRequests.last?.cursor, "two")
        XCTAssertEqual(Set(store.notifications.map(\.id)), Set(["one", "two", "three"]))
        XCTAssertFalse(store.canLoadMore)
    }

    func testNotificationRealtimePrependsAndDeduplicates() async {
        let repository = MockNotificationMessagingRepository()
        repository.notificationPages = [.init(notifications: [notification("one")], hasMore: false)]
        let store = MissCatNotificationsStore(repository: repository)
        await store.loadInitial()
        await waitUntil { repository.realtimeContinuation != nil }

        let newer = notification("two", date: Date(timeIntervalSince1970: 50))
        repository.realtimeContinuation?.yield(.connected(true))
        repository.realtimeContinuation?.yield(.inserted(newer))
        repository.realtimeContinuation?.yield(.inserted(newer))
        await waitUntil { store.notifications.first?.id == "two" }

        XCTAssertEqual(store.notifications.filter { $0.id == "two" }.count, 1)
        XCTAssertTrue(store.isRealtimeConnected)
    }

    func testAccountSwitchRejectsOldDelayedNotificationResponse() async {
        let old = MockNotificationMessagingRepository(accountID: "old")
        old.notificationDelay = 40_000_000
        old.notificationPages = [.init(notifications: [notification("stale")], hasMore: false)]
        let new = MockNotificationMessagingRepository(accountID: "new")
        new.notificationPages = [.init(notifications: [notification("fresh")], hasMore: false)]
        let store = MissCatNotificationsStore(repository: old)

        let oldLoad = Task { await store.loadInitial() }
        await Task.yield()
        store.switchAccount(to: new)
        await store.loadInitial()
        await oldLoad.value

        XCTAssertEqual(store.accountScope.accountID, "new")
        XCTAssertEqual(store.notifications.map(\.id), ["fresh"])
    }

    func testForegroundPushFiltersOwnerAndExposesTypedRoute() async {
        let repository = MockNotificationMessagingRepository(accountID: "owner")
        let resolved = notification("push", kind: .mention)
        repository.resolvedNotifications["push"] = resolved
        let store = MissCatNotificationsStore(repository: repository)

        await store.handleForegroundPush(.init(
            ownerAccountIdentifier: "other-account",
            ownerAPIUserID: "other",
            notificationID: "push"
        ))
        XCTAssertNil(store.banner)

        await store.handleForegroundPush(.init(
            ownerAccountIdentifier: "owner-account",
            ownerAPIUserID: "owner",
            notificationID: "push"
        ))
        XCTAssertEqual(store.banner?.notification.id, "push")
        XCTAssertEqual(store.takeBannerRoute(), .note("note-mention"))
        XCTAssertNil(store.banner)
    }

    func testHistorySortsLatestAndDeduplicatesPeer() async {
        let repository = MockNotificationMessagingRepository()
        repository.conversations = [
            conversation("cat", message: "old", date: Date(timeIntervalSince1970: 1)),
            conversation("dog", message: "new", date: Date(timeIntervalSince1970: 3)),
            conversation("cat", message: "latest cat", date: Date(timeIntervalSince1970: 2))
        ]
        let store = MissCatMessageHistoryStore(repository: repository)

        await store.load()

        XCTAssertEqual(store.conversations.map(\.peer.id), ["dog", "cat"])
        XCTAssertEqual(store.conversations.last?.latestText, "latest cat")
    }

    func testConversationLoadsAscendingAndPrependsOlderWithoutDuplicates() async {
        let repository = MockNotificationMessagingRepository()
        repository.messagePages = [
            .init(messages: [message("three", time: 3), message("two", time: 2)], hasMore: true),
            .init(messages: [message("two", time: 2), message("one", time: 1)], hasMore: false)
        ]
        let store = MissCatConversationStore(peer: person("peer"), repository: repository, pageSize: 2)
        await store.loadInitial()

        await store.loadOlder()

        XCTAssertEqual(store.messages.map(\.id), ["one", "two", "three"])
        XCTAssertEqual(repository.messageRequests.last?.cursor, "two")
        XCTAssertFalse(store.canLoadOlder)
    }

    func testBubbleOwnershipUsesConversationScopeNotGlobalState() async {
        let repository = MockNotificationMessagingRepository(accountID: "owner-a")
        repository.messagePages = [
            .init(messages: [message("one", sender: "owner-a", recipient: "peer", time: 1)], hasMore: false)
        ]
        let store = MissCatConversationStore(peer: person("peer"), repository: repository)
        await store.loadInitial()
        XCTAssertTrue(try! XCTUnwrap(store.messages.first).isMine(ownerAccountID: store.accountScope.accountID))

        let otherAccount = MockNotificationMessagingRepository(accountID: "owner-b")
        store.switchAccount(to: otherAccount)
        XCTAssertFalse(message("one", sender: "owner-a", recipient: "peer", time: 1).isMine(ownerAccountID: store.accountScope.accountID))
    }

    func testDoubleTapSendsExactlyOnceAndClearsMatchingDraft() async {
        let repository = MockNotificationMessagingRepository()
        repository.sendDelay = 20_000_000
        repository.sendResult = message("sent", sender: "owner", recipient: "peer", time: 4)
        let store = MissCatConversationStore(peer: person("peer"), repository: repository)
        store.draft = " hello "

        store.sendDraft()
        store.sendDraft()
        await waitUntil { store.messages.contains(where: { $0.id == "sent" }) }

        XCTAssertEqual(repository.sentTexts, ["hello"])
        XCTAssertEqual(repository.sentRequestIDs.count, 1)
        XCTAssertEqual(store.draft, "")
        XCTAssertEqual(store.sendState, .idle)
    }

    func testSendFailureRetriesSameLogicalRequestOnce() async {
        let repository = MockNotificationMessagingRepository()
        repository.sendError = NotificationMessageTestError.failed
        repository.sendResult = message("sent", sender: "owner", recipient: "peer", time: 4)
        let store = MissCatConversationStore(peer: person("peer"), repository: repository)
        store.draft = "retry me"

        store.sendDraft()
        await waitUntil {
            if case .failed = store.sendState { return true }
            return false
        }
        let firstID = repository.sentRequestIDs.first
        repository.sendError = nil
        store.retrySend()
        await waitUntil { store.sendState == .idle }

        XCTAssertEqual(repository.sentTexts, ["retry me", "retry me"])
        XCTAssertEqual(repository.sentRequestIDs, [firstID, firstID].compactMap { $0 })
        XCTAssertEqual(store.messages.map(\.id), ["sent"])
    }

    func testCancelSendKeepsDraftAndDoesNotPublishLateResult() async {
        let repository = MockNotificationMessagingRepository()
        repository.sendDelay = 100_000_000
        repository.sendResult = message("late", sender: "owner", recipient: "peer", time: 4)
        let store = MissCatConversationStore(peer: person("peer"), repository: repository)
        store.draft = "cancel me"

        store.sendDraft()
        await Task.yield()
        store.cancelSend()
        try? await Task.sleep(nanoseconds: 120_000_000)

        XCTAssertEqual(store.sendState, .idle)
        XCTAssertEqual(store.draft, "cancel me")
        XCTAssertTrue(store.messages.isEmpty)
    }

    func testMessageLinkRoutesURLMentionAndHashtag() throws {
        XCTAssertEqual(
            MissCatMessageLinkParser.route(for: try XCTUnwrap(URL(string: "https://example.test/path"))),
            .externalURL(try XCTUnwrap(URL(string: "https://example.test/path")))
        )
        XCTAssertEqual(
            MissCatMessageLinkParser.route(for: try XCTUnwrap(URL(string: "misscat-mention://cat%40example.test"))),
            .mention("cat@example.test")
        )
        XCTAssertEqual(
            MissCatMessageLinkParser.route(for: try XCTUnwrap(URL(string: "misscat-hashtag://cats"))),
            .hashtag("cats")
        )
        let attributed = MissCatMessageLinkParser.attributedString("https://example.test @cat #cats")
        XCTAssertEqual(String(attributed.characters), "https://example.test @cat #cats")
    }

    func testDateSeparatorAppearsAtStartAndDayBoundary() async {
        let repository = MockNotificationMessagingRepository()
        repository.messagePages = [
            .init(
                messages: [
                    message("one", time: 1),
                    message("two", time: 2),
                    message("three", time: 90_000)
                ],
                hasMore: false
            )
        ]
        let store = MissCatConversationStore(peer: person("peer"), repository: repository)
        await store.loadInitial()

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        XCTAssertTrue(store.showsDateSeparator(at: 0, calendar: utc))
        XCTAssertFalse(store.showsDateSeparator(at: 1, calendar: utc))
        XCTAssertTrue(store.showsDateSeparator(at: 2, calendar: utc))
    }

    private func waitUntil(_ condition: @escaping () -> Bool) async {
        for _ in 0 ..< 300 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("condition timed out")
    }

    private func person(_ id: String) -> MissCatPerson {
        MissCatPerson(id: id, name: id.capitalized, username: id)
    }

    private func notification(
        _ id: String,
        kind: MissCatNotificationKind = .reply,
        actor: MissCatPerson? = nil,
        date: Date = Date(timeIntervalSince1970: 10)
    ) -> MissCatNotification {
        MissCatNotification(
            id: id,
            kind: kind,
            actor: actor ?? person("actor"),
            createdAt: date,
            noteID: kind == .follow ? nil : "note-\(kind.rawValue)",
            noteText: "fixture note",
            reaction: kind == .reaction ? "👍" : nil
        )
    }

    private func conversation(_ peer: String, message: String, date: Date) -> MissCatConversation {
        MissCatConversation(
            peer: person(peer),
            latestMessageID: "message-\(peer)-\(date.timeIntervalSince1970)",
            latestText: message,
            latestDate: date,
            isRead: true
        )
    }

    private func message(
        _ id: String,
        sender: String = "peer",
        recipient: String = "owner",
        time: TimeInterval
    ) -> MissCatDirectMessage {
        MissCatDirectMessage(
            id: id,
            senderID: sender,
            recipientID: recipient,
            text: id,
            createdAt: Date(timeIntervalSince1970: time),
            isRead: true
        )
    }
}

final class MissCatNotificationMessageContractTests: XCTestCase {
    func testCapabilitySelectsOnlyCompleteCurrentOrLegacySets() {
        XCTAssertEqual(
            MissCatAPIEndpointCapabilities(endpoints: [
                "chat/history", "chat/messages/user-timeline", "chat/messages/create-to-user"
            ]).directMessageAPI,
            .currentChat
        )
        XCTAssertEqual(
            MissCatAPIEndpointCapabilities(endpoints: [
                "messaging/history", "messaging/messages", "messaging/create"
            ]).directMessageAPI,
            .legacyMessaging
        )
        XCTAssertEqual(
            MissCatAPIEndpointCapabilities(endpoints: ["chat/history"]).directMessageAPI,
            .unavailable
        )
    }

    func testPushEnvelopeRequiresOwnerAndNotificationIdentifiers() {
        XCTAssertEqual(
            MissCatPushEnvelope(payload: ["ownerId": "owner", "notificationId": "notification"]),
            .init(ownerIdentifier: "owner", notificationID: "notification")
        )
        XCTAssertNil(MissCatPushEnvelope(payload: ["notificationId": "notification"]))
        XCTAssertNil(MissCatPushEnvelope(payload: ["ownerId": "owner"]))
        XCTAssertEqual(
            MissCatPushEnvelope(payload: ["owner_id": "owner", "notification_id": "notification"]),
            .init(ownerIdentifier: "owner", notificationID: "notification")
        )
    }

    func testPushOwnerResolutionPrefersCompositeAccountIdentifier() throws {
        let accounts = pushAccountsWithDuplicateUserID()
        let second = accounts[1]
        let envelope = MissCatPushEnvelope(
            ownerIdentifier: second.accountIdentifier,
            ownerInstance: accounts[0].instance,
            notificationID: "notification"
        )

        let resolved = try XCTUnwrap(MissCatPushOwnerResolver.resolve(envelope, accounts: accounts))

        XCTAssertEqual(resolved.ownerAccountIdentifier, second.accountIdentifier)
        XCTAssertEqual(resolved.ownerAPIUserID, second.apiUserID)
    }

    func testPushOwnerResolutionAllowsUniqueLegacyAPIUserID() throws {
        let account = MissCatPushAccountIdentity(
            accountIdentifier: MissCatAccountIdentity.storageKey(
                instance: "only.example",
                userId: "legacy-owner"
            ),
            apiUserID: "legacy-owner",
            instance: "only.example"
        )
        let envelope = MissCatPushEnvelope(
            ownerIdentifier: "legacy-owner",
            notificationID: "notification"
        )

        XCTAssertEqual(
            MissCatPushOwnerResolver.resolve(envelope, accounts: [account])?.ownerAccountIdentifier,
            account.accountIdentifier
        )
    }

    func testPushOwnerResolutionRejectsAmbiguousLegacyAPIUserID() {
        let envelope = MissCatPushEnvelope(
            ownerIdentifier: "same-owner",
            notificationID: "notification"
        )

        XCTAssertNil(MissCatPushOwnerResolver.resolve(
            envelope,
            accounts: pushAccountsWithDuplicateUserID()
        ))
    }

    func testPushOwnerResolutionUsesExactInstanceProofForLegacyAPIUserID() throws {
        let accounts = pushAccountsWithDuplicateUserID()
        let envelope = MissCatPushEnvelope(
            ownerIdentifier: "same-owner",
            ownerInstance: "HTTPS://SECOND.EXAMPLE:443/",
            notificationID: "notification"
        )

        let resolved = try XCTUnwrap(MissCatPushOwnerResolver.resolve(envelope, accounts: accounts))

        XCTAssertEqual(resolved.ownerAccountIdentifier, accounts[1].accountIdentifier)
        XCTAssertNil(MissCatPushOwnerResolver.resolve(
            .init(
                ownerIdentifier: "same-owner",
                ownerInstance: "unknown.example",
                notificationID: "notification"
            ),
            accounts: accounts
        ))
    }

    func testPushPayloadPrefersCompositeOwnerFieldOverLegacyOwnerField() {
        let envelope = MissCatPushEnvelope(payload: [
            "ownerAccountId": "composite-owner",
            "ownerId": "legacy-owner",
            "ownerInstance": "example.test",
            "notificationId": "notification"
        ])

        XCTAssertEqual(
            envelope,
            .init(
                ownerIdentifier: "composite-owner",
                ownerInstance: "example.test",
                notificationID: "notification"
            )
        )
    }

    func testApplicationPushResolverBuildsAccountScopedRefreshAndOpenActions() throws {
        let account = MissCatPushAccountIdentity(
            accountIdentifier: "instance.example|owner",
            apiUserID: "owner",
            instance: "instance.example"
        )
        let envelope = MissCatPushEnvelope(
            ownerIdentifier: account.accountIdentifier,
            notificationID: "notification"
        )

        let refresh = try XCTUnwrap(MissCatApplicationPushResolver.resolve(
            envelope,
            accounts: [account],
            opensRoute: false
        ))
        let open = try XCTUnwrap(MissCatApplicationPushResolver.resolve(
            envelope,
            accounts: [account],
            opensRoute: true
        ))

        XCTAssertEqual(refresh.accountID.rawValue, account.accountIdentifier)
        XCTAssertEqual(refresh.action, .refreshNotifications(notificationID: "notification"))
        XCTAssertEqual(open.action, .openNotification(notificationID: "notification"))
        XCTAssertEqual(refresh.id, "instance.example|owner:notification:refresh")
        XCTAssertEqual(open.id, "instance.example|owner:notification:open")
    }

    @MainActor
    func testPushLifecycleStateRecordsRegistrationWithoutTransportTypes() {
        let state = MissCatPushLifecycleState()

        state.authorizationRequested()
        state.remoteRegistrationRequested()
        state.registered()
        XCTAssertEqual(state.phase, .registered)

        state.registrationFailed(message: "offline")
        XCTAssertEqual(state.phase, .failed(message: "offline"))
    }

    private func pushAccountsWithDuplicateUserID() -> [MissCatPushAccountIdentity] {
        ["first.example", "second.example"].map { instance in
            MissCatPushAccountIdentity(
                accountIdentifier: MissCatAccountIdentity.storageKey(
                    instance: instance,
                    userId: "same-owner"
                ),
                apiUserID: "same-owner",
                instance: instance
            )
        }
    }

    func testNativeNotificationRequestUsesCurrentEndpointAndBearerContract() async throws {
        let transport = QueueHTTPTransport(responses: [
            .init(
                status: 200,
                body: #"[{"id":"notification","createdAt":"2026-08-07T00:00:00.000Z","type":"reaction","user":{"id":"actor","name":"Cat","username":"cat"},"note":{"id":"note","text":"hello"},"reaction":"👍"}]"#
            )
        ])
        let repository = nativeRepository(transport: transport)

        let page = try await repository.fetchNotifications(cursor: "cursor", limit: 25)

        XCTAssertEqual(page.notifications.first?.kind, .reaction)
        XCTAssertEqual(page.notifications.first?.preferredRoute, .note("note"))
        let capturedRequests = await transport.requests()
        let request = try XCTUnwrap(capturedRequests.first)
        XCTAssertEqual(request.url?.path, "/api/i/notifications")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-token")
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["untilId"] as? String, "cursor")
        XCTAssertEqual(json["limit"] as? Int, 25)
        XCTAssertEqual(json["markAsRead"] as? Bool, true)
        XCTAssertNil(json["i"])
    }

    func testNativeCurrentChatContractsHistoryTimelineAndSend() async throws {
        let endpoints = #"["i/notifications","chat/history","chat/messages/user-timeline","chat/messages/create-to-user"]"#
        let history = #"[{"id":"history","createdAt":"2026-08-07T00:00:00.000Z","fromUserId":"owner","toUserId":"peer","fromUser":{"id":"owner","name":"Owner","username":"owner"},"toUser":{"id":"peer","name":"Peer","username":"peer"},"text":"latest","isRead":true}]"#
        let timeline = #"[{"id":"old","createdAt":"2026-08-06T00:00:00.000Z","fromUserId":"peer","toUserId":"owner","text":"old","reactions":[]}]"#
        let sent = #"{"id":"sent","createdAt":"2026-08-07T00:00:01.000Z","fromUserId":"owner","toUserId":"peer","text":"hello","reactions":[]}"#
        let transport = QueueHTTPTransport(responses: [
            .init(status: 200, body: endpoints),
            .init(status: 200, body: history),
            .init(status: 200, body: timeline),
            .init(status: 200, body: sent)
        ])
        let repository = nativeRepository(transport: transport)

        let conversations = try await repository.fetchConversations(limit: 10)
        let peer = try XCTUnwrap(conversations.first?.peer)
        let page = try await repository.fetchMessages(peer: peer, cursor: "cursor", limit: 40)
        let message = try await repository.sendText(" hello ", to: peer, requestID: UUID())

        XCTAssertEqual(conversations.first?.peer.id, "peer")
        XCTAssertEqual(page.messages.first?.id, "old")
        XCTAssertEqual(message.id, "sent")
        let requests = await transport.requests()
        XCTAssertEqual(
            requests.map { $0.url?.path ?? "" },
            [
                "/api/endpoints", "/api/chat/history",
                "/api/chat/messages/user-timeline",
                "/api/chat/messages/create-to-user"
            ]
        )
        let sendBody = try XCTUnwrap(requests.last?.httpBody)
        let sendJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: sendBody) as? [String: Any])
        XCTAssertEqual(sendJSON["toUserId"] as? String, "peer")
        XCTAssertEqual(sendJSON["text"] as? String, "hello")
    }

    func testNativeLegacyMessagingContractsRemainComplete() async throws {
        let endpoints = #"["messaging/history","messaging/messages","messaging/create"]"#
        let history = #"[{"id":"history","createdAt":"2026-08-07T00:00:00.000Z","userId":"owner","recipientId":"peer","user":{"id":"owner","name":"Owner","username":"owner"},"recipient":{"id":"peer","name":"Peer","username":"peer"},"text":"latest","isRead":true}]"#
        let timeline = #"[{"id":"old","createdAt":"2026-08-06T00:00:00.000Z","userId":"peer","recipientId":"owner","text":"old","isRead":true}]"#
        let sent = #"{"id":"sent","createdAt":"2026-08-07T00:00:01.000Z","userId":"owner","recipientId":"peer","text":"hello","isRead":false}"#
        let transport = QueueHTTPTransport(responses: [
            .init(status: 200, body: endpoints),
            .init(status: 200, body: history),
            .init(status: 200, body: timeline),
            .init(status: 200, body: sent)
        ])
        let repository = nativeRepository(transport: transport)

        let conversations = try await repository.fetchConversations(limit: 10)
        let peer = try XCTUnwrap(conversations.first?.peer)
        _ = try await repository.fetchMessages(peer: peer, cursor: "cursor", limit: 40)
        _ = try await repository.sendText("hello", to: peer, requestID: UUID())

        let requests = await transport.requests()
        XCTAssertEqual(
            requests.map { $0.url?.path ?? "" },
            [
                "/api/endpoints", "/api/messaging/history",
                "/api/messaging/messages",
                "/api/messaging/create"
            ]
        )
        let timelineBody = try XCTUnwrap(requests[2].httpBody)
        let timelineJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: timelineBody) as? [String: Any])
        XCTAssertEqual(timelineJSON["userId"] as? String, "peer")
        XCTAssertEqual(timelineJSON["markAsRead"] as? Bool, true)
        let sendBody = try XCTUnwrap(requests.last?.httpBody)
        let sendJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: sendBody) as? [String: Any])
        XCTAssertEqual(sendJSON["userId"] as? String, "peer")
        XCTAssertEqual(sendJSON["text"] as? String, "hello")
    }

    func testNativeRepositoryReportsUnavailableChatWithoutInventingEndpoint() async throws {
        let transport = QueueHTTPTransport(responses: [
            .init(status: 200, body: #"["i/notifications"]"#)
        ])
        let repository = nativeRepository(transport: transport)

        do {
            _ = try await repository.fetchConversations(limit: 10)
            XCTFail("Expected unavailable API")
        } catch {
            XCTAssertEqual(
                error as? MissCatNotificationMessagingError,
                .directMessagesUnavailable(host: "example.test")
            )
        }
        let requests = await transport.requests()
        XCTAssertEqual(requests.map { $0.url?.path }, ["/api/endpoints"])
    }

    func testNativeMentionResolutionUsesCurrentUsersShowContract() async throws {
        let transport = QueueHTTPTransport(responses: [
            .init(
                status: 200,
                body: #"{"id":"person","name":"Cat","username":"cat","host":"remote.test","avatarUrl":"https://cdn.test/cat.png"}"#
            )
        ])
        let repository = nativeRepository(transport: transport)

        let person = try await repository.resolvePerson(acct: "@cat@remote.test")

        XCTAssertEqual(person.id, "person")
        XCTAssertEqual(person.acct, "@cat@remote.test")
        let requests = await transport.requests()
        XCTAssertEqual(requests.map { $0.url?.path }, ["/api/users/show"])
        let body = try XCTUnwrap(requests.first?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["username"] as? String, "cat")
        XCTAssertEqual(json["host"] as? String, "remote.test")
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-token")
    }

    private func nativeRepository(
        transport: QueueHTTPTransport
    ) -> MissCatNativeNotificationMessagingRepository {
        MissCatNativeNotificationMessagingRepository(
            accountScope: .init(
                accountID: "owner",
                username: "owner",
                host: "example.test",
                accessToken: "fixture-token"
            ),
            transport: transport
        )
    }
}

@MainActor
final class MissCatNotificationMessageOrdinaryRouteTests: XCTestCase {
    func testNotificationReselectCoordinatorEmitsDeterministicScrollRequest() {
        let coordinator = MissCatNotificationScrollCoordinator()

        coordinator.scrollToTop()
        coordinator.scrollToTop()

        XCTAssertEqual(coordinator.request, 2)
    }
}

private actor QueueHTTPTransport: MissCatHTTPTransport {
    struct Response {
        let status: Int
        let body: String
    }

    private var queued: [Response]
    private var captured: [URLRequest] = []

    init(responses: [Response]) {
        queued = responses
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        captured.append(request)
        guard !queued.isEmpty else { throw NotificationMessageTestError.failed }
        let response = queued.removeFirst()
        let http = try XCTUnwrap(
            HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: response.status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )
        )
        return (Data(response.body.utf8), http)
    }

    func requests() -> [URLRequest] {
        captured
    }
}
