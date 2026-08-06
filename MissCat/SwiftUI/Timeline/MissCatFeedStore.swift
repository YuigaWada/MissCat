import Combine
import Foundation

@MainActor
public final class MissCatFeedStore: ObservableObject {
    public let source: MissCatFeedSource

    @Published public private(set) var phase: MissCatFeedPhase = .idle
    @Published public private(set) var notes: [MissCatNote] = []
    @Published public private(set) var thread: MissCatNoteThread?
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var isLoadingNextPage = false
    @Published public private(set) var canLoadMore = true
    @Published public private(set) var isRealtimeConnected = false
    @Published public private(set) var actionErrorMessage: String?

    private let repository: MissCatFeedRepository
    private let pageSize: Int
    private var realtimeTask: Task<Void, Never>?

    public init(
        source: MissCatFeedSource,
        repository: MissCatFeedRepository,
        pageSize: Int = 20
    ) {
        self.source = source
        self.repository = repository
        self.pageSize = pageSize
    }

    deinit {
        realtimeTask?.cancel()
    }

    public func loadInitial() async {
        guard phase == .idle || isFailed else { return }
        phase = .loading
        actionErrorMessage = nil

        do {
            try await replaceWithInitialContent()
            startRealtimeIfNeeded()
        } catch {
            phase = .failed(message: Self.message(for: error))
        }
    }

    public func retry() async {
        stopRealtime()
        phase = .idle
        await loadInitial()
    }

    public func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            switch source {
            case let .noteDetail(noteID):
                let newThread = try await repository.fetchThread(noteID: noteID, replyLimit: pageSize)
                thread = newThread
                notes = newThread.allNotes
                phase = .loaded
            default:
                let page = try await repository.fetchPage(source: source, cursor: nil, limit: pageSize)
                notes = Self.prependingUnique(page.notes, to: notes)
                canLoadMore = canLoadMore || page.hasMore
                phase = notes.isEmpty ? .empty : .loaded
            }
        } catch {
            actionErrorMessage = Self.message(for: error)
        }
    }

    public func loadNextPageIfNeeded(currentNoteID: String) async {
        guard source.supportsPagination,
              canLoadMore,
              !isLoadingNextPage,
              notes.suffix(3).contains(where: { $0.id == currentNoteID }) else { return }

        isLoadingNextPage = true
        defer { isLoadingNextPage = false }

        do {
            let page = try await repository.fetchPage(
                source: source,
                cursor: notes.last?.id,
                limit: pageSize
            )
            notes = Self.appendingUnique(page.notes, to: notes)
            canLoadMore = page.hasMore
        } catch {
            actionErrorMessage = Self.message(for: error)
        }
    }

    public func dismissActionError() {
        actionErrorMessage = nil
    }

    public func isThreadRoot(_ note: MissCatNote) -> Bool {
        thread?.note.noteID == note.noteID
    }

    public func toggleFavorite(noteID: String) async {
        guard let note = notes.first(where: { $0.noteID == noteID }) else { return }
        let previousNotes = notes
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
            notes = previousNotes
            phase = notes.isEmpty ? .empty : .loaded
            actionErrorMessage = Self.message(for: error)
        }
    }

    public func toggleReaction(noteID: String, reaction: String) async {
        guard let current = notes.first(where: { $0.noteID == noteID }) else { return }
        let previousNotes = notes
        let previousReaction = current.myReaction

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
                if previousReaction != reaction {
                    try await repository.perform(.addReaction(noteID: noteID, reaction: reaction))
                }
            } else {
                try await repository.perform(.addReaction(noteID: noteID, reaction: reaction))
            }
        } catch {
            notes = previousNotes
            actionErrorMessage = Self.message(for: error)
        }
    }

    public func renote(noteID: String) async {
        let previousNotes = notes
        mutateNotes(noteID: noteID) { $0.renoteCount += 1 }

        do {
            try await repository.perform(.renote(noteID: noteID))
        } catch {
            notes = previousNotes
            actionErrorMessage = Self.message(for: error)
        }
    }

    public func vote(noteID: String, choice: Int) async {
        let previousNotes = notes
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
            notes = previousNotes
            actionErrorMessage = Self.message(for: error)
        }
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

    private func replaceWithInitialContent() async throws {
        switch source {
        case let .noteDetail(noteID):
            let newThread = try await repository.fetchThread(noteID: noteID, replyLimit: pageSize)
            thread = newThread
            notes = newThread.allNotes
            canLoadMore = false
        default:
            let page = try await repository.fetchPage(source: source, cursor: nil, limit: pageSize)
            thread = nil
            notes = Self.unique(page.notes)
            canLoadMore = page.hasMore
        }
        phase = notes.isEmpty ? .empty : .loaded
    }

    private func startRealtimeIfNeeded() {
        guard source.supportsRealtime, realtimeTask == nil else { return }
        let capturedIDs = notes.map(\.noteID)
        realtimeTask = Task { [weak self] in
            guard let self else { return }
            for await event in repository.realtimeEvents(source: source, capturing: capturedIDs) {
                guard !Task.isCancelled else { return }
                apply(event)
            }
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
        case let .pollVote(noteID, choice):
            mutateNotes(noteID: noteID) { note in
                guard var poll = note.poll,
                      let index = poll.choices.firstIndex(where: { $0.id == choice }) else { return }
                poll.choices[index].votes += 1
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
        let localized = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return localized.isEmpty ? "通信に失敗しました。" : localized
    }
}
