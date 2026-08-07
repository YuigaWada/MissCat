import Combine
import Foundation

struct MissCatComposeAccount: Identifiable, Equatable, Sendable {
    let id: String
    let username: String
    let instance: String
    var avatarURL: URL?

    var displayName: String { "\(username)@\(instance)" }
}

struct MissCatComposeTarget: Identifiable, Equatable, Sendable {
    let id: String
    let username: String
    let instance: String
    let text: String
    var avatarURL: URL?

    var mention: String {
        instance.isEmpty ? "@\(username)" : "@\(username)@\(instance)"
    }
}

enum MissCatComposeMode: Equatable, Sendable {
    case note
    case reply(MissCatComposeTarget)
    case quote(MissCatComposeTarget)
    case renote(MissCatComposeTarget)

    var target: MissCatComposeTarget? {
        switch self {
        case .note:
            nil
        case let .reply(target), let .quote(target), let .renote(target):
            target
        }
    }

    var title: String {
        switch self {
        case .note: "新しい投稿"
        case .reply: "返信"
        case .quote: "引用Renote"
        case .renote: "Renote"
        }
    }

    var isRenote: Bool {
        if case .renote = self { return true }
        return false
    }
}

enum MissCatComposeVisibility: String, CaseIterable, Identifiable, Equatable, Sendable {
    case `public`
    case home
    case followers
    case specified

    var id: String { rawValue }

    var label: String {
        switch self {
        case .public: "パブリック"
        case .home: "ホーム"
        case .followers: "フォロワー"
        case .specified: "ダイレクト"
        }
    }

    var systemImage: String {
        switch self {
        case .public: "globe"
        case .home: "house"
        case .followers: "lock"
        case .specified: "envelope"
        }
    }
}

enum MissCatComposeMediaKind: String, Equatable, Sendable {
    case image
    case video
}

struct MissCatComposeMedia: Identifiable, Equatable, Sendable {
    let id: UUID
    var kind: MissCatComposeMediaKind
    var data: Data
    var previewData: Data
    var filename: String
    var mimeType: String
    var altText: String
    var isSensitive: Bool

    init(
        id: UUID = UUID(),
        kind: MissCatComposeMediaKind,
        data: Data,
        previewData: Data? = nil,
        filename: String,
        mimeType: String,
        altText: String = "",
        isSensitive: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.data = data
        self.previewData = previewData ?? data
        self.filename = filename
        self.mimeType = mimeType
        self.altText = altText
        self.isSensitive = isSensitive
    }
}

enum MissCatPollExpiry: Equatable, Sendable {
    case never
    case duration(TimeInterval)
    case at(Date)
}

struct MissCatPollChoice: Identifiable, Equatable, Sendable {
    let id: UUID
    var text: String

    init(id: UUID = UUID(), text: String = "") {
        self.id = id
        self.text = text
    }
}

struct MissCatPollDraft: Equatable, Sendable {
    var choices: [MissCatPollChoice] = [MissCatPollChoice(), MissCatPollChoice()]
    var allowsMultiple = false
    var expiry: MissCatPollExpiry = .never
}

struct MissCatComposeDraft: Equatable, Sendable {
    var text = ""
    var hasContentWarning = false
    var contentWarning = ""
    var visibility: MissCatComposeVisibility = .public
    var visibleUserIDs: [String] = []
    var localOnly = false
    var poll: MissCatPollDraft?
    var media: [MissCatComposeMedia] = []

    var hasPostableContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !media.isEmpty
            || poll != nil
    }
}

struct MissCatPollPayload: Equatable, Sendable {
    let choices: [String]
    let allowsMultiple: Bool
    let expiresAtMilliseconds: Int64?
    let expiresAfterMilliseconds: Int64?
}

struct MissCatComposeSubmission: Equatable, Sendable {
    let accountID: String
    let mode: MissCatComposeMode
    let text: String
    let contentWarning: String?
    let visibility: MissCatComposeVisibility
    let visibleUserIDs: [String]
    let localOnly: Bool
    let noExtractMentions: Bool
    let noExtractHashtags: Bool
    let media: [MissCatComposeMedia]
    let poll: MissCatPollPayload?

    var replyID: String? {
        guard case let .reply(target) = mode else { return nil }
        return target.id
    }

    var renoteID: String? {
        switch mode {
        case let .quote(target), let .renote(target): target.id
        case .note, .reply: nil
        }
    }
}

struct MissCatComposeBootstrap: Equatable, Sendable {
    let accounts: [MissCatComposeAccount]
    let selectedAccountID: String?
    let visibility: MissCatComposeVisibility
}

struct MissCatComposeUploadProgress: Equatable, Sendable {
    let completed: Int
    let total: Int

    var fraction: Double {
        guard total > 0 else { return 1 }
        return min(max(Double(completed) / Double(total), 0), 1)
    }
}

struct MissCatNowPlaying: Equatable, Sendable {
    let artist: String?
    let title: String
    let artworkData: Data?

    var postText: String {
        guard let artist, !artist.isEmpty else { return title + " #nowplaying" }
        return "\(artist) - \(title) #nowplaying"
    }
}

@MainActor
protocol MissCatComposeEnvironmentProviding: AnyObject {
    func load() async throws -> MissCatComposeBootstrap
    func persistSelectedAccount(id: String)
    func persistVisibility(_ visibility: MissCatComposeVisibility)
}

@MainActor
protocol MissCatComposeSubmitting: AnyObject {
    func submit(
        _ submission: MissCatComposeSubmission,
        progress: @escaping (MissCatComposeUploadProgress) -> Void
    ) async throws
    func cancelActiveSubmission()
}

extension MissCatComposeSubmitting {
    func cancelActiveSubmission() {}
}

@MainActor
protocol MissCatNowPlayingProviding: AnyObject {
    func current() -> MissCatNowPlaying?
}

@MainActor
final class MissCatEmptyNowPlayingProvider: MissCatNowPlayingProviding {
    func current() -> MissCatNowPlaying? { nil }
}

enum MissCatComposeValidationError: LocalizedError, Equatable {
    case accountRequired
    case targetRequired
    case emptyPost
    case textTooLong(limit: Int)
    case contentWarningTooLong(limit: Int)
    case directRecipientRequired
    case tooManyMedia(limit: Int)
    case videoMustBeAlone
    case emptyMedia
    case altTextTooLong(limit: Int)
    case pollChoiceCount
    case emptyPollChoice
    case pollChoiceTooLong(limit: Int)
    case duplicatePollChoice
    case pollExpiryInvalid
    case renoteCannotContainComment

    var errorDescription: String? {
        switch self {
        case .accountRequired: "投稿に使うアカウントを選択してください"
        case .targetRequired: "返信またはRenoteの対象を取得できませんでした"
        case .emptyPost: "投稿内容、画像、またはアンケートを追加してください"
        case let .textTooLong(limit): "投稿内容は\(limit)文字以内にしてください"
        case let .contentWarningTooLong(limit): "注釈は\(limit)文字以内にしてください"
        case .directRecipientRequired: "ダイレクト投稿の宛先を追加してください"
        case let .tooManyMedia(limit): "添付できる画像は\(limit)枚までです"
        case .videoMustBeAlone: "動画は1件のみ添付でき、画像とは同時に投稿できません"
        case .emptyMedia: "読み込めない添付ファイルが含まれています"
        case let .altTextTooLong(limit): "代替テキストは\(limit)文字以内にしてください"
        case .pollChoiceCount: "アンケートの選択肢は2〜10件にしてください"
        case .emptyPollChoice: "アンケートの選択肢をすべて入力してください"
        case let .pollChoiceTooLong(limit): "アンケートの選択肢は\(limit)文字以内にしてください"
        case .duplicatePollChoice: "アンケートに同じ選択肢は追加できません"
        case .pollExpiryInvalid: "アンケートの終了日時を未来に設定してください"
        case .renoteCannotContainComment: "通常のRenoteにはコメントや添付を追加できません"
        }
    }
}

enum MissCatComposeSubmissionBuilder {
    static let maximumTextLength = 1_500
    static let maximumContentWarningLength = 100
    static let maximumAltTextLength = 512
    static let maximumPollChoiceLength = 50
    static let maximumMediaCount = 4

    static func build(
        mode: MissCatComposeMode,
        draft: MissCatComposeDraft,
        accountID: String?,
        now: Date = Date()
    ) throws -> MissCatComposeSubmission {
        guard let accountID, !accountID.isEmpty else {
            throw MissCatComposeValidationError.accountRequired
        }
        if mode != .note, mode.target?.id.isEmpty != false {
            throw MissCatComposeValidationError.targetRequired
        }
        guard draft.text.count <= maximumTextLength else {
            throw MissCatComposeValidationError.textTooLong(limit: maximumTextLength)
        }
        guard draft.contentWarning.count <= maximumContentWarningLength else {
            throw MissCatComposeValidationError.contentWarningTooLong(limit: maximumContentWarningLength)
        }
        if draft.visibility == .specified,
           normalizedUserIDs(draft.visibleUserIDs).isEmpty
        {
            throw MissCatComposeValidationError.directRecipientRequired
        }

        try validateMedia(draft.media)
        let poll = try draft.poll.map { try pollPayload(from: $0, now: now) }

        if mode.isRenote {
            guard !draft.hasPostableContent,
                  !draft.hasContentWarning,
                  !draft.localOnly,
                  draft.visibility == .public
            else {
                throw MissCatComposeValidationError.renoteCannotContainComment
            }
        } else if !draft.hasPostableContent {
            throw MissCatComposeValidationError.emptyPost
        }

        let normalizedContentWarning = draft.contentWarning
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return MissCatComposeSubmission(
            accountID: accountID,
            mode: mode,
            text: draft.text,
            contentWarning: draft.hasContentWarning && !normalizedContentWarning.isEmpty
                ? normalizedContentWarning
                : nil,
            visibility: draft.visibility,
            visibleUserIDs: draft.visibility == .specified
                ? normalizedUserIDs(draft.visibleUserIDs)
                : [],
            localOnly: draft.localOnly,
            noExtractMentions: false,
            noExtractHashtags: false,
            media: draft.media,
            poll: poll
        )
    }

    static func pollPayload(
        from draft: MissCatPollDraft,
        now: Date
    ) throws -> MissCatPollPayload {
        guard (2 ... 10).contains(draft.choices.count) else {
            throw MissCatComposeValidationError.pollChoiceCount
        }
        let choices = draft.choices.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard choices.allSatisfy({ !$0.isEmpty }) else {
            throw MissCatComposeValidationError.emptyPollChoice
        }
        guard choices.allSatisfy({ $0.count <= maximumPollChoiceLength }) else {
            throw MissCatComposeValidationError.pollChoiceTooLong(limit: maximumPollChoiceLength)
        }
        let foldedChoices = choices.map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) }
        guard Set(foldedChoices).count == foldedChoices.count else {
            throw MissCatComposeValidationError.duplicatePollChoice
        }

        let expiresAt: Int64?
        let expiresAfter: Int64?
        switch draft.expiry {
        case .never:
            expiresAt = nil
            expiresAfter = nil
        case let .duration(interval):
            guard interval > 0 else { throw MissCatComposeValidationError.pollExpiryInvalid }
            expiresAt = nil
            expiresAfter = Int64(interval * 1_000)
        case let .at(date):
            guard date > now else { throw MissCatComposeValidationError.pollExpiryInvalid }
            expiresAt = Int64(date.timeIntervalSince1970 * 1_000)
            expiresAfter = nil
        }

        return MissCatPollPayload(
            choices: choices,
            allowsMultiple: draft.allowsMultiple,
            expiresAtMilliseconds: expiresAt,
            expiresAfterMilliseconds: expiresAfter
        )
    }

    static func validateMedia(_ media: [MissCatComposeMedia]) throws {
        guard media.count <= maximumMediaCount else {
            throw MissCatComposeValidationError.tooManyMedia(limit: maximumMediaCount)
        }
        guard media.allSatisfy({ !$0.data.isEmpty }) else {
            throw MissCatComposeValidationError.emptyMedia
        }
        guard media.allSatisfy({ $0.altText.count <= maximumAltTextLength }) else {
            throw MissCatComposeValidationError.altTextTooLong(limit: maximumAltTextLength)
        }
        let videos = media.filter { $0.kind == .video }
        if !videos.isEmpty, media.count != 1 {
            throw MissCatComposeValidationError.videoMustBeAlone
        }
    }

    private static func normalizedUserIDs(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return nil }
            return trimmed
        }
    }
}

enum MissCatComposeTextInsertion {
    static func appendingMention(username: String, instance: String?, to text: String) -> String {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        guard !trimmedUsername.isEmpty else { return text }
        let trimmedInstance = instance?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let token = trimmedInstance.isEmpty
            ? "@\(trimmedUsername)"
            : "@\(trimmedUsername)@\(trimmedInstance.trimmingCharacters(in: CharacterSet(charactersIn: "@")))"
        return append(token: token, to: text)
    }

    static func appendingHashtag(_ hashtag: String, to text: String) -> String {
        let value = hashtag.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard !value.isEmpty else { return text }
        return append(token: "#\(value)", to: text)
    }

    private static func append(token: String, to text: String) -> String {
        guard !text.isEmpty else { return token + " " }
        return text.hasSuffix(" ") || text.hasSuffix("\n")
            ? text + token + " "
            : text + " " + token + " "
    }
}

@MainActor
final class MissCatComposeViewModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        case ready
        case uploading(MissCatComposeUploadProgress)
        case submitting
        case failed
        case outcomeUnknown
        case completed
        case cancelled
    }

    @Published var draft: MissCatComposeDraft
    @Published var selectedAccountID: String?
    @Published private(set) var accounts: [MissCatComposeAccount] = []
    @Published private(set) var phase: Phase = .loading
    @Published private(set) var errorMessage: String?
    @Published private(set) var nowPlaying: MissCatNowPlaying?

    let mode: MissCatComposeMode
    private let environment: MissCatComposeEnvironmentProviding
    private let posting: MissCatComposeSubmitting
    private let nowPlayingProvider: MissCatNowPlayingProviding
    private var initialDraft: MissCatComposeDraft
    private var submissionTask: Task<Bool, Never>?
    private var submissionID: UUID?

    init(
        mode: MissCatComposeMode,
        draft: MissCatComposeDraft = MissCatComposeDraft(),
        environment: MissCatComposeEnvironmentProviding,
        posting: MissCatComposeSubmitting,
        nowPlayingProvider: MissCatNowPlayingProviding? = nil
    ) {
        self.mode = mode
        self.draft = draft
        self.initialDraft = draft
        self.environment = environment
        self.posting = posting
        self.nowPlayingProvider = nowPlayingProvider ?? MissCatEmptyNowPlayingProvider()
    }

    var selectedAccount: MissCatComposeAccount? {
        accounts.first { $0.id == selectedAccountID }
    }

    var remainingCharacterCount: Int {
        MissCatComposeSubmissionBuilder.maximumTextLength - draft.text.count
    }

    var canSubmit: Bool {
        guard phase == .ready || phase == .failed else { return false }
        return (try? makeSubmission()) != nil
    }

    var hasUnsavedChanges: Bool {
        draft != initialDraft
    }

    func load() async {
        guard phase != .submitting, phase != .completed, phase != .cancelled else { return }
        phase = .loading
        errorMessage = nil
        do {
            let bootstrap = try await environment.load()
            accounts = bootstrap.accounts
            selectedAccountID = bootstrap.accounts.contains(where: { $0.id == bootstrap.selectedAccountID })
                ? bootstrap.selectedAccountID
                : bootstrap.accounts.first?.id
            if !mode.isRenote, draft.visibility == .public {
                draft.visibility = bootstrap.visibility
            }
            nowPlaying = nowPlayingProvider.current()
            guard !accounts.isEmpty else {
                throw MissCatComposeValidationError.accountRequired
            }
            initialDraft = draft
            phase = .ready
        } catch {
            errorMessage = error.localizedDescription
            phase = .failed
        }
    }

    func selectAccount(_ id: String) {
        guard accounts.contains(where: { $0.id == id }) else { return }
        selectedAccountID = id
        environment.persistSelectedAccount(id: id)
    }

    func selectVisibility(_ visibility: MissCatComposeVisibility) {
        draft.visibility = visibility
        if visibility != .specified {
            draft.visibleUserIDs = []
        }
        environment.persistVisibility(visibility)
    }

    func insertMention(username: String, instance: String?) {
        draft.text = MissCatComposeTextInsertion.appendingMention(
            username: username,
            instance: instance,
            to: draft.text
        )
    }

    func insertHashtag(_ hashtag: String) {
        draft.text = MissCatComposeTextInsertion.appendingHashtag(hashtag, to: draft.text)
    }

    func addNowPlaying() {
        guard let nowPlaying else { return }
        let value = nowPlaying.postText
        draft.text = draft.text.isEmpty ? value : draft.text + "\n" + value
        if let artworkData = nowPlaying.artworkData, !artworkData.isEmpty {
            let media = MissCatComposeMedia(
                kind: .image,
                data: artworkData,
                filename: "now-playing.jpeg",
                mimeType: "image/jpeg",
                altText: nowPlaying.title
            )
            try? addMedia([media])
        }
    }

    func addMedia(_ newMedia: [MissCatComposeMedia]) throws {
        let candidate = draft.media + newMedia
        try MissCatComposeSubmissionBuilder.validateMedia(candidate)
        draft.media = candidate
    }

    func removeMedia(id: UUID) {
        draft.media.removeAll { $0.id == id }
    }

    func replaceMedia(id: UUID, data: Data, previewData: Data? = nil) {
        guard let index = draft.media.firstIndex(where: { $0.id == id }) else { return }
        draft.media[index].data = data
        draft.media[index].previewData = previewData ?? data
    }

    func updateMediaMetadata(id: UUID, altText: String, isSensitive: Bool) {
        guard let index = draft.media.firstIndex(where: { $0.id == id }) else { return }
        draft.media[index].altText = altText
        draft.media[index].isSensitive = isSensitive
    }

    func dismissError() {
        errorMessage = nil
        if phase == .failed {
            phase = accounts.isEmpty ? .loading : .ready
        }
    }

    func submit() async -> Bool {
        guard phase == .ready || phase == .failed else { return false }
        let submission: MissCatComposeSubmission
        do {
            submission = try makeSubmission()
        } catch {
            errorMessage = error.localizedDescription
            phase = .failed
            return false
        }

        errorMessage = nil
        phase = submission.media.isEmpty
            ? .submitting
            : .uploading(MissCatComposeUploadProgress(completed: 0, total: submission.media.count))

        let operationID = UUID()
        submissionID = operationID
        let task = Task { @MainActor [weak self] in
            guard let self else { return false }
            do {
                try await posting.submit(submission) { [weak self] progress in
                    guard let self, self.submissionID == operationID, !self.isTerminal else { return }
                    self.phase = progress.completed >= progress.total ? .submitting : .uploading(progress)
                }
                guard resolveTerminal(.completed, operationID: operationID) else { return false }
                initialDraft = draft
                return true
            } catch let error as MissCatNativeComposeAPIError {
                if case .outcomeUnknown = error {
                    errorMessage = error.localizedDescription
                    _ = resolveTerminal(.outcomeUnknown, operationID: operationID)
                } else if !isTerminal {
                    errorMessage = error.localizedDescription
                    phase = .failed
                }
                return false
            } catch is CancellationError {
                _ = resolveTerminal(.cancelled, operationID: operationID)
                return false
            } catch {
                guard !isTerminal else { return false }
                errorMessage = error.localizedDescription
                phase = .failed
                return false
            }
        }
        submissionTask = task
        let result = await task.value
        if submissionID == operationID {
            submissionTask = nil
            submissionID = nil
        }
        return result
    }

    func cancel() {
        switch phase {
        case .completed, .cancelled, .outcomeUnknown:
            return
        case .loading, .ready, .uploading, .submitting, .failed:
            phase = .cancelled
            posting.cancelActiveSubmission()
            submissionTask?.cancel()
        }
    }

    private var isTerminal: Bool {
        phase == .completed || phase == .cancelled || phase == .outcomeUnknown
    }

    @discardableResult
    private func resolveTerminal(_ terminal: Phase, operationID: UUID) -> Bool {
        guard submissionID == operationID, !isTerminal else { return false }
        phase = terminal
        return true
    }

    private func makeSubmission() throws -> MissCatComposeSubmission {
        try MissCatComposeSubmissionBuilder.build(
            mode: mode,
            draft: draft,
            accountID: selectedAccountID
        )
    }
}
