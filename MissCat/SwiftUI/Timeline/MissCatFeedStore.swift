import Combine
import Foundation

@MainActor
public final class MissCatFeedStore: ObservableObject {
    public let source: MissCatFeedSource
    public let accountScope: MissCatShellAccountScope?

    @Published public private(set) var phase: MissCatFeedPhase = .idle
    @Published public private(set) var notes: [MissCatNote] = []
    @Published public private(set) var thread: MissCatNoteThread?
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var refreshCompletionGeneration = 0
    @Published public private(set) var isLoadingNextPage = false
    @Published public private(set) var canLoadMore = true
    @Published public private(set) var isRealtimeConnected = false
    @Published public private(set) var actionErrorMessage: String?
    @Published public private(set) var canRetryAction = false

    private let repository: MissCatFeedRepository
    private let pageSize: Int
    private var initialLoadTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var paginationTask: Task<Void, Never>?
    private var contentGeneration: UInt64 = 0
    private var realtimeTask: Task<Void, Never>?
    private var realtimeGeneration = UUID()
    private var inFlightMutations = Set<MutationKey>()
    private var failedAction: RetryAction?

    private enum MutationKey: Hashable {
        case favorite(String)
        case reaction(String)
        case renote(String)
        case vote(String)
        case delete(String)
        case mute(String)
        case block(String)
        case report(String)
    }

    private enum InitialContent {
        case page(MissCatFeedPage)
        case thread(MissCatNoteThread)
    }

    private enum RetryAction {
        case favorite(String)
        case reaction(String, String)
        case renote(String)
        case vote(String, Int)
        case delete(String)
        case mute(String)
        case block(String)
        case report(String, String)
    }

    public init(
        source: MissCatFeedSource,
        repository: MissCatFeedRepository,
        accountScope: MissCatShellAccountScope? = nil,
        pageSize: Int = 20
    ) {
        self.source = source
        self.repository = repository
        self.accountScope = accountScope
        self.pageSize = pageSize
    }

    deinit {
        initialLoadTask?.cancel()
        refreshTask?.cancel()
        paginationTask?.cancel()
        realtimeTask?.cancel()
    }

    public func loadInitial() async {
        if phase == .loaded || phase == .empty {
            startRealtimeIfNeeded()
            return
        }
        if let initialLoadTask {
            await initialLoadTask.value
            return
        }
        guard phase == .idle || isFailed else { return }
        cancelContentTasks(incrementingGeneration: true)
        phase = .loading
        actionErrorMessage = nil
        let generation = contentGeneration
        let capturedScope = accountScope
        let repository = repository
        let source = source
        let pageSize = pageSize
        let task = Task { @MainActor [weak self, repository] in
            do {
                let content: InitialContent
                switch source {
                case let .noteDetail(noteID):
                    content = .thread(try await repository.fetchThread(noteID: noteID, replyLimit: pageSize))
                default:
                    content = .page(try await repository.fetchPage(source: source, cursor: nil, limit: pageSize))
                }
                guard let self, self.accepts(generation: generation, scope: capturedScope) else { return }
                self.applyInitialContent(content)
                self.initialLoadTask = nil
                self.startRealtimeIfNeeded()
            } catch is CancellationError {
                guard let self, self.accepts(generation: generation, scope: capturedScope) else { return }
                self.initialLoadTask = nil
                self.phase = self.notes.isEmpty ? .idle : .loaded
            } catch {
                guard let self, self.accepts(generation: generation, scope: capturedScope) else { return }
                self.initialLoadTask = nil
                if error as? MissCatFeedRepositoryError == .emptyResponse {
                    self.thread = nil
                    self.notes = []
                    self.canLoadMore = false
                    self.phase = .empty
                } else {
                    self.phase = .failed(message: Self.message(for: error))
                }
            }
        }
        initialLoadTask = task
        await task.value
    }

    public func retry() async {
        cancelAllFeedTasks()
        phase = .idle
        await loadInitial()
    }

    public func refresh() async {
        if let refreshTask {
            await refreshTask.value
            return
        }
        guard !isRefreshing else { return }
        initialLoadTask?.cancel()
        initialLoadTask = nil
        paginationTask?.cancel()
        paginationTask = nil
        isLoadingNextPage = false
        stopRealtime()
        contentGeneration &+= 1
        let generation = contentGeneration
        let capturedScope = accountScope
        let repository = repository
        let source = source
        let pageSize = pageSize
        isRefreshing = true
        let task = Task { @MainActor [weak self, repository] in
            do {
                let content: InitialContent
                switch source {
                case let .noteDetail(noteID):
                    content = .thread(try await repository.fetchThread(noteID: noteID, replyLimit: pageSize))
                default:
                    content = .page(try await repository.fetchPage(source: source, cursor: nil, limit: pageSize))
                }
                guard let self, self.accepts(generation: generation, scope: capturedScope) else { return }
                self.applyRefreshContent(content)
                self.refreshCompletionGeneration &+= 1
                self.refreshTask = nil
                self.isRefreshing = false
                self.startRealtimeIfNeeded()
            } catch is CancellationError {
                guard let self, self.accepts(generation: generation, scope: capturedScope) else { return }
                self.refreshTask = nil
                self.isRefreshing = false
                self.startRealtimeIfNeeded()
            } catch {
                guard let self, self.accepts(generation: generation, scope: capturedScope) else { return }
                self.refreshTask = nil
                self.isRefreshing = false
                self.actionErrorMessage = Self.message(for: error)
                self.startRealtimeIfNeeded()
            }
        }
        refreshTask = task
        await task.value
    }

    public func loadNextPageIfNeeded(currentNoteID: String) async {
        guard source.supportsPagination,
              canLoadMore,
              !isLoadingNextPage,
              notes.suffix(3).contains(where: { $0.id == currentNoteID }) else { return }

        if let paginationTask {
            await paginationTask.value
            return
        }
        isLoadingNextPage = true
        let generation = contentGeneration
        let capturedScope = accountScope
        let repository = repository
        let source = source
        let cursor = notes.last?.id
        let pageSize = pageSize
        let task = Task { @MainActor [weak self, repository] in
            do {
                let page = try await repository.fetchPage(source: source, cursor: cursor, limit: pageSize)
                guard let self, self.accepts(generation: generation, scope: capturedScope) else { return }
                self.notes = Self.appendingUnique(page.notes, to: self.notes)
                self.canLoadMore = page.hasMore
                self.paginationTask = nil
                self.isLoadingNextPage = false
            } catch is CancellationError {
                guard let self, self.accepts(generation: generation, scope: capturedScope) else { return }
                self.paginationTask = nil
                self.isLoadingNextPage = false
            } catch {
                guard let self, self.accepts(generation: generation, scope: capturedScope) else { return }
                self.paginationTask = nil
                self.isLoadingNextPage = false
                self.actionErrorMessage = Self.message(for: error)
            }
        }
        paginationTask = task
        await task.value
    }

    public func dismissActionError() {
        actionErrorMessage = nil
        failedAction = nil
        canRetryAction = false
    }

    public func retryLastAction() async {
        guard let failedAction else { return }
        self.failedAction = nil
        actionErrorMessage = nil
        canRetryAction = false
        switch failedAction {
        case let .favorite(noteID): await toggleFavorite(noteID: noteID)
        case let .reaction(noteID, reaction): await toggleReaction(noteID: noteID, reaction: reaction)
        case let .renote(noteID): await renote(noteID: noteID)
        case let .vote(noteID, choice): await vote(noteID: noteID, choice: choice)
        case let .delete(noteID): await delete(noteID: noteID)
        case let .mute(userID): await muteUser(userID: userID)
        case let .block(userID): await blockUser(userID: userID)
        case let .report(userID, comment): await reportUser(userID: userID, comment: comment)
        }
    }

    public func isThreadRoot(_ note: MissCatNote) -> Bool {
        thread?.note.noteID == note.noteID
    }

    public func toggleFavorite(noteID: String) async {
        let mutationKey = MutationKey.favorite(noteID)
        guard inFlightMutations.insert(mutationKey).inserted else { return }
        defer { inFlightMutations.remove(mutationKey) }

        guard let note = notes.first(where: { $0.noteID == noteID }) else { return }
        let previousIndex = notes.firstIndex(where: { $0.noteID == noteID })
        let shouldFavorite = !note.isFavorite

        if source == .favorites, !shouldFavorite {
            notes.removeAll { $0.noteID == noteID }
            phase = notes.isEmpty ? .empty : .loaded
        } else {
            mutateNotes(noteID: noteID) { $0.isFavorite = shouldFavorite }
        }

        do {
            try await repository.perform(
                shouldFavorite ? .favorite(noteID: noteID) : .unfavorite(noteID: noteID)
            )
        } catch {
            if let index = notes.firstIndex(where: { $0.noteID == noteID }) {
                notes[index].isFavorite = note.isFavorite
            } else if let previousIndex {
                notes.insert(note, at: min(previousIndex, notes.endIndex))
            }
            phase = notes.isEmpty ? .empty : .loaded
            recordFailure(.favorite(noteID), error: error)
        }
    }

    public func toggleReaction(noteID: String, reaction: String) async {
        let mutationKey = MutationKey.reaction(noteID)
        guard inFlightMutations.insert(mutationKey).inserted else { return }
        defer { inFlightMutations.remove(mutationKey) }

        guard let current = notes.first(where: { $0.noteID == noteID }) else { return }
        let previousReaction = current.myReaction
        var removedPreviousReaction = false

        mutateNotes(noteID: noteID) { note in
            if let previousReaction {
                Self.changeReaction(previousReaction, delta: -1, isMine: false, in: &note)
            }
            if previousReaction != reaction {
                Self.changeReaction(reaction, delta: 1, isMine: true, in: &note)
                note.myReaction = reaction
            } else {
                note.myReaction = nil
            }
        }

        do {
            if let previousReaction {
                try await repository.perform(.removeReaction(noteID: noteID))
                removedPreviousReaction = true
                if previousReaction != reaction {
                    try await repository.perform(.addReaction(noteID: noteID, reaction: reaction))
                }
            } else {
                try await repository.perform(.addReaction(noteID: noteID, reaction: reaction))
            }
        } catch {
            if removedPreviousReaction, let previousReaction, previousReaction != reaction {
                mutateNotes(noteID: noteID) { note in
                    Self.changeReaction(reaction, delta: -1, isMine: false, in: &note)
                    note.myReaction = nil
                }
            } else {
                mutateNotes(noteID: noteID) { note in
                    if previousReaction != reaction {
                        Self.changeReaction(reaction, delta: -1, isMine: false, in: &note)
                    }
                    if let previousReaction {
                        Self.changeReaction(previousReaction, delta: 1, isMine: true, in: &note)
                        note.myReaction = previousReaction
                    } else {
                        note.myReaction = nil
                    }
                }
            }
            recordFailure(.reaction(noteID, reaction), error: error)
        }
    }

    public func renote(noteID: String) async {
        let mutationKey = MutationKey.renote(noteID)
        guard inFlightMutations.insert(mutationKey).inserted else { return }
        defer { inFlightMutations.remove(mutationKey) }

        mutateNotes(noteID: noteID) { $0.renoteCount += 1 }

        do {
            try await repository.perform(.renote(noteID: noteID))
        } catch {
            mutateNotes(noteID: noteID) { $0.renoteCount = max(0, $0.renoteCount - 1) }
            recordFailure(.renote(noteID), error: error)
        }
    }

    public func vote(noteID: String, choice: Int) async {
        let mutationKey = MutationKey.vote(noteID)
        guard inFlightMutations.insert(mutationKey).inserted else { return }
        defer { inFlightMutations.remove(mutationKey) }

        guard let note = notes.first(where: { $0.noteID == noteID }),
              let poll = note.poll,
              poll.expiresAt.map({ $0 > Date() }) ?? true,
              let selectedChoice = poll.choices.first(where: { $0.id == choice }),
              !selectedChoice.isVoted,
              poll.allowsMultipleChoices || !poll.choices.contains(where: \.isVoted)
        else { return }

        mutateNotes(noteID: noteID) { note in
            guard var poll = note.poll,
                  let index = poll.choices.firstIndex(where: { $0.id == choice }) else { return }
            poll.choices[index].votes += 1
            poll.choices[index].isVoted = true
            note.poll = poll
        }

        do {
            try await repository.perform(.vote(noteID: noteID, choice: choice))
        } catch {
            mutateNotes(noteID: noteID) { note in
                guard var poll = note.poll,
                      let index = poll.choices.firstIndex(where: { $0.id == choice }) else { return }
                poll.choices[index].votes = max(0, poll.choices[index].votes - 1)
                poll.choices[index].isVoted = false
                note.poll = poll
            }
            recordFailure(.vote(noteID, choice), error: error)
        }
    }

    public func delete(noteID: String) async {
        let mutationKey = MutationKey.delete(noteID)
        guard inFlightMutations.insert(mutationKey).inserted else { return }
        defer { inFlightMutations.remove(mutationKey) }

        do {
            try await repository.perform(.delete(noteID: noteID))
            notes.removeAll { $0.id == noteID || $0.noteID == noteID }
            synchronizeThread()
            phase = notes.isEmpty ? .empty : .loaded
        } catch {
            recordFailure(.delete(noteID), error: error)
        }
    }

    public func muteUser(userID: String) async {
        let mutationKey = MutationKey.mute(userID)
        guard inFlightMutations.insert(mutationKey).inserted else { return }
        defer { inFlightMutations.remove(mutationKey) }

        do {
            try await repository.perform(.mute(userID: userID))
            notes.removeAll { $0.author.id == userID }
            synchronizeThread()
            phase = notes.isEmpty ? .empty : .loaded
        } catch {
            recordFailure(.mute(userID), error: error)
        }
    }

    public func blockUser(userID: String) async {
        let mutationKey = MutationKey.block(userID)
        guard inFlightMutations.insert(mutationKey).inserted else { return }
        defer { inFlightMutations.remove(mutationKey) }

        do {
            try await repository.perform(.block(userID: userID))
            notes.removeAll { $0.author.id == userID }
            synchronizeThread()
            phase = notes.isEmpty ? .empty : .loaded
        } catch {
            recordFailure(.block(userID), error: error)
        }
    }

    public func reportUser(userID: String, comment: String) async {
        guard let normalized = MissCatReportComment.normalized(comment) else { return }
        let mutationKey = MutationKey.report(userID)
        guard inFlightMutations.insert(mutationKey).inserted else { return }
        defer { inFlightMutations.remove(mutationKey) }

        do {
            try await repository.perform(.report(userID: userID, comment: normalized))
        } catch {
            recordFailure(.report(userID, normalized), error: error)
        }
    }

    public func stopRealtime() {
        realtimeGeneration = UUID()
        realtimeTask?.cancel()
        realtimeTask = nil
        isRealtimeConnected = false
    }

    public func cancelAllFeedTasks() {
        cancelContentTasks(incrementingGeneration: true)
        stopRealtime()
        if phase == .loading {
            phase = notes.isEmpty ? .idle : .loaded
        }
    }

    private var isFailed: Bool {
        if case .failed = phase { return true }
        return false
    }

    private func cancelContentTasks(incrementingGeneration: Bool) {
        if incrementingGeneration {
            contentGeneration &+= 1
        }
        initialLoadTask?.cancel()
        refreshTask?.cancel()
        paginationTask?.cancel()
        initialLoadTask = nil
        refreshTask = nil
        paginationTask = nil
        isRefreshing = false
        isLoadingNextPage = false
    }

    private func accepts(generation: UInt64, scope: MissCatShellAccountScope?) -> Bool {
        !Task.isCancelled && contentGeneration == generation && accountScope == scope
    }

    private func recordFailure(_ action: RetryAction, error: Error) {
        failedAction = action
        canRetryAction = true
        actionErrorMessage = Self.message(for: error)
    }

    private func applyInitialContent(_ content: InitialContent) {
        switch content {
        case let .thread(newThread):
            thread = newThread
            notes = newThread.allNotes
            canLoadMore = false
        case let .page(page):
            thread = nil
            notes = Self.unique(page.notes)
            canLoadMore = page.hasMore
        }
        phase = notes.isEmpty ? .empty : .loaded
    }

    private func applyRefreshContent(_ content: InitialContent) {
        switch content {
        case let .thread(newThread):
            thread = newThread
            notes = newThread.allNotes
            canLoadMore = false
        case let .page(page):
            thread = nil
            notes = Self.prependingUnique(page.notes, to: notes)
            canLoadMore = canLoadMore || page.hasMore
        }
        phase = notes.isEmpty ? .empty : .loaded
    }

    private func startRealtimeIfNeeded() {
        guard source.supportsRealtime, realtimeTask == nil else { return }
        let capturedIDs = notes.map(\.noteID)
        let streamGeneration = UUID()
        let generation = contentGeneration
        let capturedScope = accountScope
        let repository = repository
        let source = source
        realtimeGeneration = streamGeneration
        realtimeTask = Task { @MainActor [weak self, repository] in
            for await event in repository.realtimeEvents(source: source, capturing: capturedIDs) {
                guard let self,
                      self.realtimeGeneration == streamGeneration,
                      self.accepts(generation: generation, scope: capturedScope)
                else { return }
                self.apply(event)
            }
            guard let self,
                  self.realtimeGeneration == streamGeneration,
                  self.accepts(generation: generation, scope: capturedScope)
            else { return }
            self.realtimeTask = nil
            self.isRealtimeConnected = false
        }
    }

    private func apply(_ event: MissCatRealtimeEvent) {
        switch event {
        case let .connected(connected):
            isRealtimeConnected = connected
        case let .inserted(note):
            notes = Self.prependingUnique([note], to: notes)
            phase = .loaded
        case let .replaced(note):
            if let index = notes.firstIndex(where: { $0.id == note.id || $0.noteID == note.noteID }) {
                notes[index] = note
            }
        case let .removed(noteID):
            notes.removeAll { $0.id == noteID || $0.noteID == noteID }
            phase = notes.isEmpty ? .empty : .loaded
        case let .reaction(noteID, reaction, delta, isMine):
            mutateNotes(noteID: noteID) { note in
                Self.changeReaction(reaction, delta: delta, isMine: isMine && delta > 0, in: &note)
                if isMine {
                    note.myReaction = delta > 0 ? reaction : nil
                }
            }
        case let .pollVote(noteID, choice, isMine):
            mutateNotes(noteID: noteID) { note in
                guard var poll = note.poll,
                      let index = poll.choices.firstIndex(where: { $0.id == choice }) else { return }
                poll.choices[index].votes += 1
                if isMine {
                    if !poll.allowsMultipleChoices {
                        for choiceIndex in poll.choices.indices {
                            poll.choices[choiceIndex].isVoted = false
                        }
                    }
                    poll.choices[index].isVoted = true
                }
                note.poll = poll
            }
        case let .failed(message):
            isRealtimeConnected = false
            actionErrorMessage = message
        }
    }

    private func mutateNotes(noteID: String, mutation: (inout MissCatNote) -> Void) {
        for index in notes.indices where notes[index].id == noteID || notes[index].noteID == noteID {
            mutation(&notes[index])
        }
        synchronizeThread()
    }

    private func synchronizeThread() {
        guard let current = thread else { return }
        let byID = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        thread = MissCatNoteThread(
            ancestors: current.ancestors.compactMap { byID[$0.id] },
            note: byID[current.note.id] ?? current.note,
            replies: current.replies.compactMap { byID[$0.id] }
        )
    }

    private static func changeReaction(
        _ reaction: String,
        delta: Int,
        isMine: Bool,
        in note: inout MissCatNote
    ) {
        if let index = note.reactions.firstIndex(where: { $0.name == reaction }) {
            note.reactions[index].count = max(0, note.reactions[index].count + delta)
            note.reactions[index].isMine = isMine
            if note.reactions[index].count == 0 {
                note.reactions.remove(at: index)
            }
        } else if delta > 0 {
            note.reactions.append(MissCatReaction(name: reaction, count: delta, isMine: isMine))
        }
    }

    private static func unique(_ values: [MissCatNote]) -> [MissCatNote] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.id).inserted }
    }

    private static func prependingUnique(
        _ incoming: [MissCatNote],
        to existing: [MissCatNote]
    ) -> [MissCatNote] {
        unique(incoming + existing)
    }

    private static func appendingUnique(
        _ incoming: [MissCatNote],
        to existing: [MissCatNote]
    ) -> [MissCatNote] {
        unique(existing + incoming)
    }

    private static func message(for error: Error) -> String {
        if let urlError = error as? URLError,
           [
               URLError.Code.notConnectedToInternet,
               .networkConnectionLost,
               .dataNotAllowed,
           ].contains(urlError.code)
        {
            return "インターネットに接続できません。"
        }
        let localized = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return localized.isEmpty ? "通信に失敗しました。" : localized
    }
}
