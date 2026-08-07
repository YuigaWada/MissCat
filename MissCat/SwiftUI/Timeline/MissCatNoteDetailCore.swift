import Combine
import CoreGraphics
import Foundation
import ImageIO

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
    public let emojiURL: URL?
    public let aliases: [String]
    public let category: String?
    public let isLocalOnly: Bool
    public let isSensitive: Bool

    public var id: String { value }

    public init(
        value: String,
        label: String? = nil,
        emojiURL: URL? = nil,
        aliases: [String] = [],
        category: String? = nil,
        isLocalOnly: Bool = false,
        isSensitive: Bool = false
    ) {
        self.value = value
        self.label = label ?? value
        self.emojiURL = emojiURL
        self.aliases = aliases
        self.category = category
        self.isLocalOnly = isLocalOnly
        self.isSensitive = isSensitive
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

enum MissCatReactionSelectionPolicy {
    static let serverLikeValue = "\u{2764}"

    static func selectableChoices(
        catalog: [MissCatReactionChoice],
        existingReactions: [MissCatReaction],
        noteAuthorHost: String?,
        reactionAcceptance: String?
    ) -> [MissCatReactionChoice] {
        if reactionAcceptance == "likeOnly" {
            return [MissCatReactionChoice(value: serverLikeValue, label: serverLikeValue)]
        }

        let permittedCatalog = catalog.filter { choice in
            if choice.isLocalOnly, noteAuthorHost != nil { return false }
            if choice.isSensitive,
               reactionAcceptance == "nonSensitiveOnly"
                || reactionAcceptance == "nonSensitiveOnlyForLocalLikeOnlyForRemote" {
                return false
            }
            return true
        }
        let permittedValues = Set(permittedCatalog.map(\.value))
        let existingUnicode = existingReactions.compactMap { reaction -> MissCatReactionChoice? in
            if permittedValues.contains(reaction.name) { return nil }
            guard reaction.emojiURL == nil,
                  isUnicodeEmoji(reaction.name) else { return nil }
            return MissCatReactionChoice(value: reaction.name)
        }
        return unique(permittedCatalog + existingUnicode)
    }

    private static func isUnicodeEmoji(_ value: String) -> Bool {
        guard !value.isEmpty,
              !value.hasPrefix(":"),
              !value.hasSuffix(":") else { return false }
        return value.unicodeScalars.contains { scalar in
            scalar.properties.isEmoji || scalar.properties.isEmojiPresentation
        }
    }

    private static func unique(_ choices: [MissCatReactionChoice]) -> [MissCatReactionChoice] {
        var values = Set<String>()
        return choices.filter { values.insert($0.value).inserted }
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
    func cachedURLPreview(for url: URL) -> MissCatURLPreview?
    func fetchURLPreview(for url: URL) async throws -> MissCatURLPreview
    func fetchReactionChoices() async throws -> [MissCatReactionChoice]
    func resolveMention(_ acct: String) async throws -> String
}

public extension MissCatNoteContextRepository {
    func cachedURLPreview(for url: URL) -> MissCatURLPreview? { nil }

    func fetchReactionChoices() async throws -> [MissCatReactionChoice] {
        MissCatReactionChoice.legacyDefaults
    }

    func resolveMention(_ acct: String) async throws -> String {
        throw MissCatMentionResolutionError.unsupported(acct)
    }
}

public enum MissCatMentionResolutionError: LocalizedError, Equatable {
    case invalidAccount(String)
    case unsupported(String)

    public var errorDescription: String? {
        switch self {
        case .invalidAccount: "メンション先を特定できませんでした。"
        case .unsupported: "この画面ではメンション先を開けません。"
        }
    }
}

@MainActor
public final class MissCatNoteVisualReadiness: ObservableObject {
    @Published public private(set) var isReady = false
    @Published public private(set) var hasFailures = false

    private var expected = Set<String>()
    private var terminal = Set<String>()
    private var failed = Set<String>()
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
        failed.remove(key)
        hasFailures = !failed.isEmpty
        scheduleEvaluation()
    }

    public func fail(_ key: String) {
        guard !key.isEmpty else { return }
        terminal.insert(key)
        failed.insert(key)
        hasFailures = true
        scheduleEvaluation()
    }

    public func setModelTerminal(_ value: Bool) {
        modelIsTerminal = value
        scheduleEvaluation()
    }

    private func scheduleEvaluation() {
        stabilizationTask?.cancel()
        isReady = false
        guard modelIsTerminal,
              expected.isSubset(of: terminal),
              expected.isDisjoint(with: failed) else { return }
        stabilizationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled, let self,
                  self.modelIsTerminal,
                  self.expected.isSubset(of: self.terminal),
                  self.expected.isDisjoint(with: self.failed) else { return }
            self.isReady = true
        }
    }
}

@MainActor
final class MissCatCustomEmojiCache {
    static let shared = MissCatCustomEmojiCache()

    private let storage = NSCache<NSURL, CGImage>()

    init(countLimit: Int = 256) {
        storage.countLimit = countLimit
        storage.totalCostLimit = 32 * 1_024 * 1_024
    }

    func image(for url: URL) -> CGImage? {
        storage.object(forKey: url as NSURL)
    }

    func insert(_ image: CGImage, for url: URL) {
        storage.setObject(
            image,
            forKey: url as NSURL,
            cost: image.bytesPerRow * image.height
        )
    }
}

enum MissCatCustomEmojiLoadError: Error, Equatable {
    case unsupportedURL
    case unsupportedMIME
    case invalidResponse
    case invalidImage
    case http(Int)
    case payloadTooLarge
    case dimensionsTooLarge
}

enum MissCatCustomEmojiImageDecoder {
    static let maximumPayloadBytes = 4_000_000
    static let maximumDimension = 4_096
    static let maximumDecodedPixels = 16_777_216

    nonisolated static func decode(_ data: Data) throws -> CGImage {
        guard !data.isEmpty,
              data.count <= maximumPayloadBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
        else { throw MissCatCustomEmojiLoadError.invalidImage }
        try validateDimensions(width: width, height: height)
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary)
        else { throw MissCatCustomEmojiLoadError.invalidImage }
        return image
    }

    nonisolated static func validateDimensions(width: Int, height: Int) throws {
        guard width > 0, height > 0 else {
            throw MissCatCustomEmojiLoadError.invalidImage
        }
        guard width <= maximumDimension,
              height <= maximumDimension,
              width <= maximumDecodedPixels / height else {
            throw MissCatCustomEmojiLoadError.dimensionsTooLarge
        }
    }

    nonisolated static func decodeOffMain(_ data: Data) async throws -> CGImage {
        try await Task.detached(priority: .utility) {
            try decode(data)
        }.value
    }
}

enum MissCatCustomEmojiTransportPolicy {
    static func validate(url: URL) throws {
        guard MissCatEmojiURLResolver.isAllowedRemoteURL(url) else {
            throw MissCatCustomEmojiLoadError.unsupportedURL
        }
    }

    static func validate(response: HTTPURLResponse) throws {
        guard (200 ..< 300).contains(response.statusCode) else {
            throw MissCatCustomEmojiLoadError.http(response.statusCode)
        }
        guard response.mimeType?.lowercased().hasPrefix("image/") == true else {
            throw MissCatCustomEmojiLoadError.unsupportedMIME
        }
        let expectedLength = response.expectedContentLength
        guard expectedLength < 0
                || expectedLength <= Int64(MissCatCustomEmojiImageDecoder.maximumPayloadBytes)
        else { throw MissCatCustomEmojiLoadError.payloadTooLarge }
    }
}

@MainActor
final class MissCatCustomEmojiStore: ObservableObject {
    typealias DataLoader = @Sendable (URL) async throws -> Data

    @Published private(set) var imageByName: [String: CGImage] = [:]

    private var emojis: [String: URL]
    private var readiness: MissCatNoteVisualReadiness?
    private let cache: MissCatCustomEmojiCache
    private let loader: DataLoader
    private var loadedURLsByName: [String: URL] = [:]

    convenience init(
        emojis: [String: URL],
        readiness: MissCatNoteVisualReadiness?
    ) {
        self.init(
            emojis: emojis,
            readiness: readiness,
            cache: .shared,
            loader: Self.liveLoader
        )
    }

    init(
        emojis: [String: URL],
        readiness: MissCatNoteVisualReadiness?,
        cache: MissCatCustomEmojiCache,
        loader: @escaping DataLoader
    ) {
        self.emojis = emojis
        self.readiness = readiness
        self.cache = cache
        self.loader = loader
    }

    func load() async {
        let entries = emojis.sorted { $0.key < $1.key }
        let currentReadiness = readiness
        let registeredKeys = Set(entries.map { assetKey($0.value) })
        var terminalKeys = Set<String>()
        for (_, url) in entries {
            let key = assetKey(url)
            currentReadiness?.register(key)
        }
        defer {
            // A disappearing/cancelled row must not leave the feed pending
            // forever. Transport/decode failures are recorded separately and
            // intentionally do not become visual-acceptance success.
            registeredKeys.subtracting(terminalKeys).forEach {
                currentReadiness?.complete($0)
            }
        }

        for (name, url) in entries where loadedURLsByName[name] != url {
            guard !Task.isCancelled else { return }
            imageByName[name] = nil
            loadedURLsByName[name] = nil
            if let image = cache.image(for: url) {
                imageByName[name] = image
                loadedURLsByName[name] = url
                currentReadiness?.complete(assetKey(url))
                terminalKeys.insert(assetKey(url))
                continue
            }
            do {
                let data = try await loader(url)
                try Task.checkCancellation()
                let image = try await MissCatCustomEmojiImageDecoder.decodeOffMain(data)
                try Task.checkCancellation()
                cache.insert(image, for: url)
                imageByName[name] = image
                loadedURLsByName[name] = url
                currentReadiness?.complete(assetKey(url))
            } catch {
                if error is CancellationError { return }
                currentReadiness?.fail(assetKey(url))
            }
            terminalKeys.insert(assetKey(url))
        }
    }

    func load(
        emojis: [String: URL],
        readiness: MissCatNoteVisualReadiness?
    ) async {
        self.emojis = emojis
        self.readiness = readiness
        await load()
    }

    private func assetKey(_ url: URL) -> String {
        "note-asset:\(url.absoluteString)"
    }

    static let liveLoader: DataLoader = { url in
        try MissCatCustomEmojiTransportPolicy.validate(url: url)
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        request.timeoutInterval = 20
        request.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("MissCat/SwiftUI", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MissCatCustomEmojiLoadError.invalidResponse
        }
        try MissCatCustomEmojiTransportPolicy.validate(response: http)
        var data = Data()
        if http.expectedContentLength > 0 {
            data.reserveCapacity(
                min(
                    Int(http.expectedContentLength),
                    MissCatCustomEmojiImageDecoder.maximumPayloadBytes
                )
            )
        }
        for try await byte in bytes {
            guard data.count < MissCatCustomEmojiImageDecoder.maximumPayloadBytes else {
                throw MissCatCustomEmojiLoadError.payloadTooLarge
            }
            data.append(byte)
        }
        return data
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
                || $0.aliases.contains(where: { $0.localizedCaseInsensitiveContains(query) })
                || ($0.category?.localizedCaseInsensitiveContains(query) ?? false)
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
    case copyText
    case copyLink
    case share
    case openInBrowser
    case favorite
    case unfavorite
    case muteUser
    case blockUser
    case reportUser
    case delete
}

public protocol MissCatClipboardWriting: AnyObject {
    @MainActor func write(_ value: String)
}

public struct MissCatNoteClipboardActions {
    private let writer: any MissCatClipboardWriting

    public init(writer: any MissCatClipboardWriting) {
        self.writer = writer
    }

    @MainActor
    public func copyText(_ text: String) {
        writer.write(text)
    }

    @MainActor
    public func copyLink(_ url: URL) {
        writer.write(url.absoluteString)
    }
}
