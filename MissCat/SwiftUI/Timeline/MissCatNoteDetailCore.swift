import Combine
import Foundation

public struct MissCatURLPreview: Equatable, Sendable {
    public let sourceURL: URL
    public let resolvedURL: URL
    public let title: String
    public let description: String
    public let siteName: String?
    public let imageURL: URL?
    public let isSensitive: Bool

    public init(
        sourceURL: URL,
        resolvedURL: URL? = nil,
        title: String,
        description: String = "",
        siteName: String? = nil,
        imageURL: URL? = nil,
        isSensitive: Bool = false
    ) {
        self.sourceURL = sourceURL
        self.resolvedURL = resolvedURL ?? sourceURL
        self.title = title
        self.description = description
        self.siteName = siteName
        self.imageURL = imageURL
        self.isSensitive = isSensitive
    }
}

public struct MissCatReactionChoice: Identifiable, Equatable, Sendable {
    public let value: String
    public let label: String

    public var id: String { value }

    public init(value: String, label: String? = nil) {
        self.value = value
        self.label = label ?? value
    }

    public static let legacyDefaults = [
        MissCatReactionChoice(value: "👍"),
        MissCatReactionChoice(value: "❤️", label: "❤"),
        MissCatReactionChoice(value: "😆"),
        MissCatReactionChoice(value: "🎉"),
        MissCatReactionChoice(value: "😮"),
        MissCatReactionChoice(value: "😢"),
        MissCatReactionChoice(value: "😡"),
        MissCatReactionChoice(value: "🍮"),
        MissCatReactionChoice(value: "🐈"),
        MissCatReactionChoice(value: "✨"),
        MissCatReactionChoice(value: "👀"),
        MissCatReactionChoice(value: "🙏"),
        MissCatReactionChoice(value: "🚀"),
        MissCatReactionChoice(value: "✅"),
        MissCatReactionChoice(value: "💯"),
        MissCatReactionChoice(value: "☕"),
    ]
}

public enum MissCatURLPreviewError: LocalizedError, Equatable {
    case unsupportedURL
    case invalidInstance
    case invalidResponse
    case http(Int)

    public var errorDescription: String? {
        switch self {
        case .unsupportedURL: "このURLはプレビューできません。"
        case .invalidInstance: "インスタンスURLが正しくありません。"
        case .invalidResponse: "リンクの情報を取得できませんでした。"
        case let .http(status): "リンクの取得に失敗しました（\(status)）。"
        }
    }
}

/// Account-scoped detail capabilities.  The stable identifier is deliberately
/// composite because Misskey user IDs are only unique inside one instance.
public protocol MissCatNoteContextRepository: MissCatFeedRepository {
    var accountIdentifier: String { get }
    var currentServerUserID: String { get }
    func notePermalink(noteID: String) -> URL?
    func cachedURLPreview(for url: URL) -> MissCatURLPreview?
    func fetchURLPreview(for url: URL) async throws -> MissCatURLPreview
    func fetchReactionChoices() async throws -> [MissCatReactionChoice]
}

public extension MissCatNoteContextRepository {
    func cachedURLPreview(for url: URL) -> MissCatURLPreview? { nil }

    func fetchReactionChoices() async throws -> [MissCatReactionChoice] {
        MissCatReactionChoice.legacyDefaults
    }
}

public enum MissCatNativeMFMRenderer {
    private static let ignoredTags = ["motion", "flip", "spin", "jump", "small"]

    /// A Swift-native, side-effect-free presentation path for new screens.  It
    /// never bridges a caller-owned UIFont into CoreText.
    public static func render(_ source: String) -> AttributedString {
        var normalized = source
        for tag in ignoredTags {
            normalized = normalized
                .replacingOccurrences(of: "<\(tag)>", with: "")
                .replacingOccurrences(of: "</\(tag)>", with: "")
        }
        normalized = normalized
            .replacingOccurrences(of: "***", with: "")
            .replacingOccurrences(of: "(((", with: "")
            .replacingOccurrences(of: ")))", with: "")

        var result = AttributedString()
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, line) in lines.enumerated() {
            let sourceLine = String(line)
            let parsed = (try? AttributedString(
                markdown: sourceLine,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )) ?? AttributedString(sourceLine)
            result.append(parsed)
            if index < lines.index(before: lines.endIndex) {
                result.append(AttributedString("\n"))
            }
        }
        let renderedText = String(result.characters)
        let fullRange = NSRange(renderedText.startIndex..., in: renderedText)

        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            for match in detector.matches(in: renderedText, range: fullRange) {
                guard let url = match.url,
                      let swiftRange = Range(match.range, in: renderedText),
                      let attributedRange = Range(swiftRange, in: result) else { continue }
                result[attributedRange].link = url
            }
        }
        return result
    }

    public static func previewURLs(in source: String, limit: Int = 1) -> [URL] {
        guard limit > 0,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return [] }

        let range = NSRange(source.startIndex..., in: source)
        var seen = Set<String>()
        return detector.matches(in: source, range: range).compactMap { match in
            guard let url = match.url,
                  let scheme = url.scheme?.lowercased(),
                  scheme == "https" || scheme == "http",
                  seen.insert(url.absoluteString).inserted else { return nil }
            return url
        }.prefix(limit).map { $0 }
    }
}

@MainActor
public final class MissCatNoteVisualReadiness: ObservableObject {
    @Published public private(set) var isReady = false

    private var expected = Set<String>()
    private var terminal = Set<String>()
    private var modelIsTerminal = false
    private var stabilizationTask: Task<Void, Never>?

    public init() {}

    deinit { stabilizationTask?.cancel() }

    public func register(_ key: String) {
        guard !key.isEmpty, expected.insert(key).inserted else { return }
        scheduleEvaluation()
    }

    public func complete(_ key: String) {
        guard !key.isEmpty else { return }
        terminal.insert(key)
        scheduleEvaluation()
    }

    public func setModelTerminal(_ value: Bool) {
        modelIsTerminal = value
        scheduleEvaluation()
    }

    private func scheduleEvaluation() {
        stabilizationTask?.cancel()
        isReady = false
        guard modelIsTerminal, expected.isSubset(of: terminal) else { return }
        stabilizationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled, let self,
                  self.modelIsTerminal,
                  self.expected.isSubset(of: self.terminal) else { return }
            self.isReady = true
        }
    }
}

@MainActor
public final class MissCatURLPreviewStore: ObservableObject {
    public enum Phase: Equatable {
        case idle
        case loading
        case loaded(MissCatURLPreview)
        case failed(String)
    }

    @Published public private(set) var phase: Phase = .idle
    public let fallbackPreview: MissCatURLPreview
    private let sourceURL: URL
    private let repository: any MissCatNoteContextRepository
    private let cache: MissCatURLPreviewCache
    private var task: Task<Void, Never>?
    private var generation = 0

    public init(
        sourceURL: URL,
        repository: any MissCatNoteContextRepository,
        cache: MissCatURLPreviewCache? = nil
    ) {
        self.sourceURL = sourceURL
        self.repository = repository
        self.cache = cache ?? .shared
        fallbackPreview = repository.cachedURLPreview(for: sourceURL) ?? MissCatURLPreview(
            sourceURL: sourceURL,
            title: sourceURL.host ?? sourceURL.absoluteString,
            siteName: sourceURL.host
        )
    }

    deinit {
        generation += 1
        task?.cancel()
    }

    public func load() {
        guard phase == .idle else { return }
        phase = .loading
        generation += 1
        let requestGeneration = generation
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let preview = try await cache.value(
                    accountIdentifier: repository.accountIdentifier,
                    sourceURL: sourceURL,
                    repository: repository
                )
                guard !Task.isCancelled, requestGeneration == generation else { return }
                phase = .loaded(preview)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, requestGeneration == generation else { return }
                let message: String
                if let urlError = error as? URLError,
                   [.notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
                    .cannotFindHost, .cannotLoadFromNetwork, .timedOut].contains(urlError.code) {
                    message = "インターネットに接続できません。"
                } else {
                    message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                phase = .failed(message.isEmpty ? "リンクの情報を取得できませんでした。" : message)
            }
        }
    }

    public func retry() {
        task?.cancel()
        cache.remove(accountIdentifier: repository.accountIdentifier, sourceURL: sourceURL)
        phase = .idle
        load()
    }

    public func cancel() {
        generation += 1
        task?.cancel()
        task = nil
    }
}

@MainActor
public final class MissCatURLPreviewCache {
    public static let shared = MissCatURLPreviewCache()

    private struct Entry {
        let preview: MissCatURLPreview
        let expiresAt: Date
    }

    private var entries: [String: Entry] = [:]
    private var requests: [String: Task<MissCatURLPreview, Error>] = [:]
    private let timeToLive: TimeInterval
    private let now: () -> Date

    public init(timeToLive: TimeInterval = 300, now: @escaping () -> Date = Date.init) {
        self.timeToLive = timeToLive
        self.now = now
    }

    public func value(
        accountIdentifier: String,
        sourceURL: URL,
        repository: any MissCatNoteContextRepository
    ) async throws -> MissCatURLPreview {
        let key = Self.key(accountIdentifier: accountIdentifier, sourceURL: sourceURL)
        if let entry = entries[key], entry.expiresAt > now() {
            return entry.preview
        }
        if let request = requests[key] {
            return try await request.value
        }

        let request = Task { try await repository.fetchURLPreview(for: sourceURL) }
        requests[key] = request
        do {
            let preview = try await request.value
            entries[key] = Entry(preview: preview, expiresAt: now().addingTimeInterval(timeToLive))
            requests[key] = nil
            return preview
        } catch {
            requests[key] = nil
            throw error
        }
    }

    public func remove(accountIdentifier: String, sourceURL: URL) {
        let key = Self.key(accountIdentifier: accountIdentifier, sourceURL: sourceURL)
        entries[key] = nil
    }

    public func removeAll() {
        entries.removeAll()
        for request in requests.values { request.cancel() }
        requests.removeAll()
    }

    private static func key(accountIdentifier: String, sourceURL: URL) -> String {
        "\(accountIdentifier)|\(sourceURL.absoluteString)"
    }
}

@MainActor
public final class MissCatReactionPickerStore: ObservableObject {
    public enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published public private(set) var phase: Phase = .idle
    @Published public private(set) var choices: [MissCatReactionChoice] = []
    @Published public var query = ""
    private let repository: any MissCatNoteContextRepository
    private var task: Task<Void, Never>?

    public init(repository: any MissCatNoteContextRepository) {
        self.repository = repository
    }

    deinit { task?.cancel() }

    public var filteredChoices: [MissCatReactionChoice] {
        guard !query.isEmpty else { return choices }
        return choices.filter {
            $0.value.localizedCaseInsensitiveContains(query)
                || $0.label.localizedCaseInsensitiveContains(query)
        }
    }

    public func load() {
        guard phase == .idle else { return }
        phase = .loading
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let remote = try await repository.fetchReactionChoices()
                guard !Task.isCancelled else { return }
                choices = Self.unique(MissCatReactionChoice.legacyDefaults + remote)
                phase = .loaded
            } catch {
                guard !Task.isCancelled else { return }
                choices = MissCatReactionChoice.legacyDefaults
                phase = .failed(error.localizedDescription)
            }
        }
    }

    public func retry() {
        task?.cancel()
        phase = .idle
        load()
    }

    private static func unique(_ choices: [MissCatReactionChoice]) -> [MissCatReactionChoice] {
        var values = Set<String>()
        return choices.filter { values.insert($0.value).inserted }
    }
}

public enum MissCatNoteOverflowAction: Equatable, Sendable {
    case copyLink
    case openInBrowser
    case favorite
    case unfavorite
    case muteUser
    case delete
}
