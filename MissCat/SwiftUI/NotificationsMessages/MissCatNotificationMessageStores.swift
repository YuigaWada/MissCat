import Combine
import Foundation

@MainActor
public final class MissCatNotificationsStore: ObservableObject {
    @Published public private(set) var phase: MissCatNotificationMessageLoadPhase = .idle
    @Published public private(set) var notifications: [MissCatNotification] = []
    @Published public private(set) var canLoadMore = true
    @Published public private(set) var isLoadingMore = false
    @Published public private(set) var isRealtimeConnected = false
    @Published public private(set) var actionErrorMessage: String?
    @Published public private(set) var banner: MissCatInAppNotificationBanner?

    public private(set) var accountScope: MissCatAccountScope

    private var repository: MissCatNotificationsRepository
    private let pageSize: Int
    private var scopeGeneration = UUID()
    private var realtimeTask: Task<Void, Never>?
    private var nextPageCursor: String?

    public init(repository: MissCatNotificationsRepository, pageSize: Int = 30) {
        self.repository = repository
        accountScope = repository.accountScope
        self.pageSize = pageSize
    }

    deinit {
        realtimeTask?.cancel()
    }

    public func loadInitial() async {
        guard phase == .idle || isFailed else { return }
        let generation = scopeGeneration
        phase = .loading
        actionErrorMessage = nil

        do {
            let page = try await repository.fetchNotifications(cursor: nil, limit: pageSize)
            guard generation == scopeGeneration, !Task.isCancelled else { return }
            notifications = Self.normalized(page.notifications)
            nextPageCursor = page.notifications.last?.id
            canLoadMore = page.hasMore && nextPageCursor != nil
            phase = notifications.isEmpty ? .empty : .loaded
            startRealtime(generation: generation)
        } catch {
            guard generation == scopeGeneration, !Task.isCancelled else { return }
            phase = .failed(message: Self.message(for: error))
        }
    }

    public func retry() async {
        stopRealtime()
        phase = .idle
        await loadInitial()
    }

    public func refresh() async {
        let generation = scopeGeneration
        let wasEmpty = notifications.isEmpty
        do {
            let page = try await repository.fetchNotifications(cursor: nil, limit: pageSize)
            guard generation == scopeGeneration, !Task.isCancelled else { return }
            notifications = Self.normalized(page.notifications + notifications)
            if wasEmpty {
                nextPageCursor = page.notifications.last?.id
                canLoadMore = page.hasMore && nextPageCursor != nil
            }
            phase = notifications.isEmpty ? .empty : .loaded
        } catch {
            guard generation == scopeGeneration, !Task.isCancelled else { return }
            actionErrorMessage = Self.message(for: error)
        }
    }

    public func loadNextPageIfNeeded(currentID: String) async {
        guard canLoadMore,
              !isLoadingMore,
              let nextPageCursor,
              notifications.suffix(3).contains(where: { $0.id == currentID }) else { return }
        let generation = scopeGeneration
        isLoadingMore = true
        defer { if generation == scopeGeneration { isLoadingMore = false } }

        do {
            let page = try await repository.fetchNotifications(
                cursor: nextPageCursor,
                limit: pageSize
            )
            guard generation == scopeGeneration, !Task.isCancelled else { return }
            notifications = Self.normalized(notifications + page.notifications)
            self.nextPageCursor = page.notifications.last?.id
            canLoadMore = page.hasMore && self.nextPageCursor != nil
        } catch {
            guard generation == scopeGeneration, !Task.isCancelled else { return }
            actionErrorMessage = Self.message(for: error)
        }
    }

    public func switchAccount(to repository: MissCatNotificationsRepository) {
        stopRealtime()
        scopeGeneration = UUID()
        self.repository = repository
        accountScope = repository.accountScope
        notifications = []
        nextPageCursor = nil
        canLoadMore = true
        isLoadingMore = false
        actionErrorMessage = nil
        banner = nil
        phase = .idle
    }

    public func handleForegroundPush(_ envelope: MissCatPushEnvelope) async {
        guard envelope.ownerAccountID == accountScope.accountID else { return }
        let generation = scopeGeneration
        do {
            guard let resolved = try await repository.resolveNotification(id: envelope.notificationID),
                  generation == scopeGeneration,
                  !Task.isCancelled else { return }
            notifications = Self.normalized([resolved] + notifications)
            phase = .loaded
            banner = MissCatInAppNotificationBanner(notification: resolved)
        } catch {
            guard generation == scopeGeneration, !Task.isCancelled else { return }
            actionErrorMessage = Self.message(for: error)
        }
    }

    public func dismissBanner() {
        banner = nil
    }

    @discardableResult
    public func takeBannerRoute() -> MissCatNotificationRoute? {
        defer { banner = nil }
        return banner?.route
    }

    public func dismissActionError() {
        actionErrorMessage = nil
    }

    public func stopRealtime() {
        realtimeTask?.cancel()
        realtimeTask = nil
        isRealtimeConnected = false
    }

    private var isFailed: Bool {
        if case .failed = phase { return true }
        return false
    }

    private func startRealtime(generation: UUID) {
        guard realtimeTask == nil else { return }
        let stream = repository.realtimeNotifications()
        realtimeTask = Task { [weak self] in
            for await event in stream {
                guard let self, !Task.isCancelled, generation == scopeGeneration else { return }
                switch event {
                case let .connected(connected):
                    isRealtimeConnected = connected
                case let .inserted(notification):
                    notifications = Self.normalized([notification] + notifications)
                    phase = .loaded
                case let .failed(message):
                    isRealtimeConnected = false
                    actionErrorMessage = message
                }
            }
        }
    }

    private static func normalized(_ input: [MissCatNotification]) -> [MissCatNotification] {
        var seen = Set<String>()
        return input
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt { return lhs.id > rhs.id }
                return lhs.createdAt > rhs.createdAt
            }
            .filter { seen.insert($0.id).inserted }
    }

    private static func message(for error: Error) -> String {
        let value = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "通信に失敗しました。" : value
    }
}

@MainActor
public final class MissCatMessageHistoryStore: ObservableObject {
    @Published public private(set) var phase: MissCatNotificationMessageLoadPhase = .idle
    @Published public private(set) var conversations: [MissCatConversation] = []

    public private(set) var accountScope: MissCatAccountScope

    private var repository: MissCatMessagingRepository
    private let limit: Int
    private var scopeGeneration = UUID()

    public init(repository: MissCatMessagingRepository, limit: Int = 100) {
        self.repository = repository
        accountScope = repository.accountScope
        self.limit = limit
    }

    public func load() async {
        guard phase == .idle || isFailed else { return }
        let generation = scopeGeneration
        phase = .loading
        do {
            let result = try await repository.fetchConversations(limit: limit)
            guard generation == scopeGeneration, !Task.isCancelled else { return }
            conversations = Self.normalized(result)
            phase = conversations.isEmpty ? .empty : .loaded
        } catch {
            guard generation == scopeGeneration, !Task.isCancelled else { return }
            phase = .failed(message: Self.message(for: error))
        }
    }

    public func retry() async {
        phase = .idle
        await load()
    }

    public func refresh() async {
        phase = .idle
        await load()
    }

    public func switchAccount(to repository: MissCatMessagingRepository) {
        scopeGeneration = UUID()
        self.repository = repository
        accountScope = repository.accountScope
        conversations = []
        phase = .idle
    }

    private var isFailed: Bool {
        if case .failed = phase { return true }
        return false
    }

    private static func normalized(_ input: [MissCatConversation]) -> [MissCatConversation] {
        var seen = Set<String>()
        return input
            .sorted { $0.latestDate > $1.latestDate }
            .filter { seen.insert($0.id).inserted }
    }

    private static func message(for error: Error) -> String {
        let value = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "通信に失敗しました。" : value
    }
}

@MainActor
public final class MissCatConversationStore: ObservableObject {
    @Published public var draft = ""
    @Published public private(set) var phase: MissCatNotificationMessageLoadPhase = .idle
    @Published public private(set) var messages: [MissCatDirectMessage] = []
    @Published public private(set) var canLoadOlder = true
    @Published public private(set) var isLoadingOlder = false
    @Published public private(set) var sendState: MissCatMessageSendState = .idle
    @Published public private(set) var actionErrorMessage: String?

    public let peer: MissCatPerson
    public private(set) var accountScope: MissCatAccountScope

    private var repository: MissCatMessagingRepository
    private let pageSize: Int
    private var scopeGeneration = UUID()
    private var sendTask: Task<Void, Never>?

    public init(
        peer: MissCatPerson,
        repository: MissCatMessagingRepository,
        pageSize: Int = 40
    ) {
        self.peer = peer
        self.repository = repository
        accountScope = repository.accountScope
        self.pageSize = pageSize
    }

    deinit {
        sendTask?.cancel()
    }

    public func loadInitial() async {
        guard phase == .idle || isFailed else { return }
        let generation = scopeGeneration
        phase = .loading
        do {
            let page = try await repository.fetchMessages(peer: peer, cursor: nil, limit: pageSize)
            guard generation == scopeGeneration, !Task.isCancelled else { return }
            messages = Self.normalized(page.messages)
            canLoadOlder = page.hasMore
            phase = messages.isEmpty ? .empty : .loaded
        } catch {
            guard generation == scopeGeneration, !Task.isCancelled else { return }
            phase = .failed(message: Self.message(for: error))
        }
    }

    public func retryLoad() async {
        phase = .idle
        await loadInitial()
    }

    public func loadOlder() async {
        guard canLoadOlder, !isLoadingOlder, let cursor = messages.first?.id else { return }
        let generation = scopeGeneration
        isLoadingOlder = true
        defer { if generation == scopeGeneration { isLoadingOlder = false } }
        do {
            let page = try await repository.fetchMessages(peer: peer, cursor: cursor, limit: pageSize)
            guard generation == scopeGeneration, !Task.isCancelled else { return }
            messages = Self.normalized(page.messages + messages)
            canLoadOlder = page.hasMore
            phase = messages.isEmpty ? .empty : .loaded
        } catch {
            guard generation == scopeGeneration, !Task.isCancelled else { return }
            actionErrorMessage = Self.message(for: error)
        }
    }

    public func sendDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, sendTask == nil else { return }
        startSend(text: text, requestID: UUID())
    }

    public func retrySend() {
        guard case let .failed(requestID, text, _) = sendState, sendTask == nil else { return }
        startSend(text: text, requestID: requestID)
    }

    public func cancelSend() {
        sendTask?.cancel()
        sendTask = nil
        sendState = .idle
    }

    public func switchAccount(to repository: MissCatMessagingRepository) {
        cancelSend()
        scopeGeneration = UUID()
        self.repository = repository
        accountScope = repository.accountScope
        messages = []
        canLoadOlder = true
        isLoadingOlder = false
        actionErrorMessage = nil
        phase = .idle
    }

    public func dismissActionError() {
        actionErrorMessage = nil
    }

    public func showsDateSeparator(at index: Int, calendar: Calendar = .current) -> Bool {
        guard messages.indices.contains(index) else { return false }
        guard index > 0 else { return true }
        return !calendar.isDate(messages[index - 1].createdAt, inSameDayAs: messages[index].createdAt)
    }

    private var isFailed: Bool {
        if case .failed = phase { return true }
        return false
    }

    private func startSend(text: String, requestID: UUID) {
        let generation = scopeGeneration
        sendState = .sending(requestID: requestID)
        sendTask = Task { [weak self] in
            guard let self else { return }
            do {
                let message = try await repository.sendText(text, to: peer, requestID: requestID)
                guard generation == scopeGeneration, !Task.isCancelled else { return }
                messages = Self.normalized(messages + [message])
                phase = .loaded
                if draft.trimmingCharacters(in: .whitespacesAndNewlines) == text {
                    draft = ""
                }
                sendState = .idle
            } catch {
                guard generation == scopeGeneration, !Task.isCancelled else { return }
                sendState = .failed(requestID: requestID, text: text, message: Self.message(for: error))
            }
            if generation == scopeGeneration {
                sendTask = nil
            }
        }
    }

    private static func normalized(_ input: [MissCatDirectMessage]) -> [MissCatDirectMessage] {
        var byID: [String: MissCatDirectMessage] = [:]
        input.forEach { byID[$0.id] = $0 }
        return byID.values.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt { return lhs.id < rhs.id }
            return lhs.createdAt < rhs.createdAt
        }
    }

    private static func message(for error: Error) -> String {
        let value = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "通信に失敗しました。" : value
    }
}
