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
    func fetchURLPreview(for url: URL) async throws -> MissCatURLPreview
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

        var result = (try? AttributedString(
            markdown: normalized,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(normalized)
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
    private let sourceURL: URL
    private let repository: any MissCatNoteContextRepository
    private var task: Task<Void, Never>?

    public init(sourceURL: URL, repository: any MissCatNoteContextRepository) {
        self.sourceURL = sourceURL
        self.repository = repository
    }

    deinit { task?.cancel() }

    public func load() {
        guard phase == .idle else { return }
        phase = .loading
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let preview = try await repository.fetchURLPreview(for: sourceURL)
                guard !Task.isCancelled else { return }
                phase = .loaded(preview)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                phase = .failed(message.isEmpty ? "リンクの情報を取得できませんでした。" : message)
            }
        }
    }

    public func retry() {
        task?.cancel()
        phase = .idle
        load()
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
