@preconcurrency import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import MediaPlayer

enum MissCatComposeLegacyVisibilityAdapter {
    static func value(_ visibility: MissCatComposeVisibility) -> MissCatVisibility? {
        MissCatVisibility(rawValue: visibility.rawValue)
    }
}

@MainActor
final class MissCatComposeEnvironmentStore: MissCatComposeEnvironmentProviding {
    private let cache: Cache.UserDefaults

    init(cache: Cache.UserDefaults = .shared) {
        self.cache = cache
    }

    func load() async throws -> MissCatComposeBootstrap {
        let users = cache.getUsers()
        let accounts = users.map {
            MissCatComposeAccount(
                id: $0.accountIdentifier,
                username: $0.username,
                instance: $0.instance,
                avatarURL: nil
            )
        }
        let currentID = cache.getCurrentUserId()
        let visibility = cache.getCurrentVisibility()
            .flatMap { MissCatComposeVisibility(rawValue: $0.rawValue) }
            ?? .public
        return MissCatComposeBootstrap(
            accounts: accounts,
            selectedAccountID: currentID,
            visibility: visibility
        )
    }

    func persistSelectedAccount(id: String) {
        // The authenticated application root exclusively owns the persisted
        // current account. A composer may select a submission identity only
        // when its root-provided session explicitly exposes that identity.
        _ = id
    }

    func persistVisibility(_ visibility: MissCatComposeVisibility) {
        guard let value = MissCatComposeLegacyVisibilityAdapter.value(visibility) else { return }
        cache.setCurrentVisibility(value)
    }
}

/// Immutable credentials and presentation defaults captured from one
/// authenticated root generation. Compose must never re-read a mutable global
/// current account while this session is presented.
struct MissCatComposeProductionSession: Sendable {
    struct Authorization: Sendable {
        let account: MissCatComposeAccount
        let scope: MissCatComposeAccountScope

        init(
            accountID: String,
            username: String,
            instance: String,
            avatarURL: URL? = nil,
            accessToken: String
        ) throws {
            account = MissCatComposeAccount(
                id: accountID,
                username: username,
                instance: instance,
                avatarURL: avatarURL
            )
            scope = try MissCatComposeAccountScope(
                accountID: accountID,
                instance: instance,
                accessToken: accessToken
            )
        }
    }

    let accounts: [MissCatComposeAccount]
    let selectedAccountID: String
    let scopesByAccountID: [String: MissCatComposeAccountScope]
    let visibility: MissCatComposeVisibility

    init(
        authorizations: [Authorization],
        selectedAccountID: String,
        visibility: MissCatComposeVisibility
    ) throws {
        var seen = Set<String>()
        let unique = authorizations.filter { seen.insert($0.account.id).inserted }
        guard unique.contains(where: { $0.account.id == selectedAccountID }) else {
            throw MissCatNativeComposeAPIError.invalidCredentials
        }
        accounts = unique.map(\.account)
        self.selectedAccountID = selectedAccountID
        scopesByAccountID = Dictionary(
            uniqueKeysWithValues: unique.map { ($0.account.id, $0.scope) }
        )
        self.visibility = visibility
    }
}

@MainActor
final class MissCatSessionBoundComposeEnvironment: MissCatComposeEnvironmentProviding {
    private let session: MissCatComposeProductionSession
    private let accountSelectionObserver: (String) -> Void
    private let visibilityPersistence: (String, MissCatComposeVisibility) -> Void
    private var selectedAccountID: String

    init(
        session: MissCatComposeProductionSession,
        accountSelectionObserver: @escaping (String) -> Void = { _ in },
        visibilityPersistence: @escaping (String, MissCatComposeVisibility) -> Void = { _, _ in }
    ) {
        self.session = session
        self.accountSelectionObserver = accountSelectionObserver
        self.visibilityPersistence = visibilityPersistence
        selectedAccountID = session.selectedAccountID
    }

    func load() async throws -> MissCatComposeBootstrap {
        MissCatComposeBootstrap(
            accounts: session.accounts,
            selectedAccountID: selectedAccountID,
            visibility: session.visibility
        )
    }

    func persistSelectedAccount(id: String) {
        guard session.scopesByAccountID[id] != nil else { return }
        selectedAccountID = id
        accountSelectionObserver(id)
    }

    func persistVisibility(_ visibility: MissCatComposeVisibility) {
        visibilityPersistence(selectedAccountID, visibility)
    }
}

@MainActor
final class MissCatNowPlayingProvider: MissCatNowPlayingProviding {
    func current() -> MissCatNowPlaying? {
        guard let item = MPMusicPlayerController.systemMusicPlayer.nowPlayingItem else { return nil }
        let artwork = item.artwork?.image(at: CGSize(width: 600, height: 600))
            .flatMap(\.cgImage)
            .flatMap { MissCatComposeImageCodec.jpegData(from: $0, compressionQuality: 0.9) }
        return MissCatNowPlaying(
            artist: item.artist,
            title: item.title ?? "",
            artworkData: artwork
        )
    }
}

@MainActor
final class MissCatComposePostService: MissCatComposeSubmitting {
    enum ServiceError: LocalizedError {
        case accountUnavailable
        case unsupportedMedia
        case imageEncodingFailed

        var errorDescription: String? {
            switch self {
            case .accountUnavailable: "投稿に使うアカウント情報を取得できませんでした"
            case .unsupportedMedia: "添付ファイルを読み込めませんでした"
            case .imageEncodingFailed: "画像を投稿用に変換できませんでした"
            }
        }
    }

    private let userProvider: (String) -> SecureUser?
    private let injectedScopes: [String: MissCatComposeAccountScope]?
    private let scopeSelectionObserver: (String) -> Void
    private let transport: any MissCatComposeHTTPTransport
    private let requestTimeout: TimeInterval
    private let journal: MissCatComposeOperationJournalStoring
    private var activeSubmissionTask: Task<Void, Error>?

    init(
        userProvider: @escaping (String) -> SecureUser? = { Cache.UserDefaults.shared.getUser(userId: $0) },
        transport: any MissCatComposeHTTPTransport = MissCatComposeURLSessionTransport(),
        requestTimeout: TimeInterval = MissCatNativeComposeAPIClient.defaultTimeout,
        journal: MissCatComposeOperationJournalStoring = MissCatComposeOperationJournal()
    ) {
        self.userProvider = userProvider
        injectedScopes = nil
        scopeSelectionObserver = { _ in }
        self.transport = transport
        self.requestTimeout = requestTimeout
        self.journal = journal
    }

    init(
        scopesByAccountID: [String: MissCatComposeAccountScope],
        transport: any MissCatComposeHTTPTransport = MissCatComposeURLSessionTransport(),
        requestTimeout: TimeInterval = MissCatNativeComposeAPIClient.defaultTimeout,
        journal: MissCatComposeOperationJournalStoring = MissCatComposeOperationJournal(),
        scopeSelectionObserver: @escaping (String) -> Void = { _ in }
    ) {
        userProvider = { _ in nil }
        injectedScopes = scopesByAccountID
        self.scopeSelectionObserver = scopeSelectionObserver
        self.transport = transport
        self.requestTimeout = requestTimeout
        self.journal = journal
    }

    func submit(
        _ submission: MissCatComposeSubmission,
        progress: @escaping (MissCatComposeUploadProgress) -> Void
    ) async throws {
        guard activeSubmissionTask == nil else {
            throw MissCatNativeComposeAPIError.alreadySubmitting
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { throw CancellationError() }
            try await performSubmission(submission, progress: progress)
        }
        activeSubmissionTask = task
        defer { activeSubmissionTask = nil }
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    func cancelActiveSubmission() {
        activeSubmissionTask?.cancel()
    }

    private func performSubmission(
        _ submission: MissCatComposeSubmission,
        progress: @escaping (MissCatComposeUploadProgress) -> Void
    ) async throws {

        let scope: MissCatComposeAccountScope
        if let injectedScopes {
            guard let injectedScope = injectedScopes[submission.accountID],
                  injectedScope.accountID == submission.accountID
            else {
                throw ServiceError.accountUnavailable
            }
            scope = injectedScope
        } else {
            guard let user = userProvider(submission.accountID),
                  user.accountIdentifier == submission.accountID,
                  let apiKey = user.apiKey,
                  !apiKey.isEmpty
            else {
                throw ServiceError.accountUnavailable
            }
            scope = try MissCatComposeAccountScope(
                accountID: submission.accountID,
                instance: user.instance,
                accessToken: apiKey
            )
        }
        scopeSelectionObserver(scope.accountID)
        let client = MissCatNativeComposeAPIClient(
            scope: scope,
            transport: transport,
            timeout: requestTimeout
        )

        let identity = operationIdentity(for: submission, scope: scope)
        let fingerprint = identity.fingerprint
        var record = try resumableRecord(identity: identity)

        do {
            var fileIDs = Array(record.knownFileIDs.prefix(submission.media.count))
            if !fileIDs.isEmpty {
                progress(MissCatComposeUploadProgress(completed: fileIDs.count, total: submission.media.count))
            }
            for (index, media) in submission.media.enumerated() where index >= fileIDs.count {
                try Task.checkCancellation()
                let upload = try await preparedUpload(for: media)
                record.phase = .uploadRequestStarted
                record.uncertainEndpoint = nil
                try saveJournal(record)
                let fileID = try await client.upload(
                    MissCatComposeAPIUpload(
                        data: upload.data,
                        mimeType: upload.mimeType,
                        filename: upload.filename,
                        comment: media.altText.isEmpty ? nil : media.altText,
                        isSensitive: media.isSensitive
                    )
                )
                fileIDs.append(fileID)
                record.knownFileIDs = fileIDs
                record.phase = .uploading
                record.uncertainEndpoint = nil
                try saveJournal(record)
                progress(MissCatComposeUploadProgress(completed: index + 1, total: submission.media.count))
            }

            let poll = submission.poll.map {
                MissCatComposeAPIPoll(
                    choices: $0.choices,
                    multiple: $0.allowsMultiple,
                    expiresAt: $0.expiresAtMilliseconds,
                    expiredAfter: $0.expiresAfterMilliseconds
                )
            }
            record.phase = .readyToCreateNote
            record.uncertainEndpoint = nil
            try saveJournal(record)
            try Task.checkCancellation()
            record.phase = .noteRequestStarted
            record.uncertainEndpoint = nil
            try saveJournal(record)
            let noteID = try await client.createNote(
                MissCatComposeAPINote(
                    visibility: submission.visibility.composeAPIVisibility,
                    visibleUserIDs: submission.visibleUserIDs,
                    text: submission.text,
                    contentWarning: submission.contentWarning,
                    localOnly: submission.localOnly,
                    noExtractMentions: submission.noExtractMentions,
                    noExtractHashtags: submission.noExtractHashtags,
                    noExtractEmojis: false,
                    fileIDs: fileIDs,
                    replyID: submission.replyID,
                    renoteID: submission.renoteID,
                    poll: poll
                )
            )
            record.createdNoteID = noteID
            record.phase = .noteCreated
            record.uncertainEndpoint = nil
            try saveJournal(record)
            try Task.checkCancellation()
            guard journal.remove(fingerprint: fingerprint) else {
                throw MissCatNativeComposeAPIError.journalUnavailable
            }
        } catch let error as MissCatNativeComposeAPIError {
            if case let .outcomeUnknown(endpoint) = error {
                record.phase = .outcomeUnknown
                record.uncertainEndpoint = endpoint
                _ = journal.save(record)
            } else {
                let cleanupIsUnknown = await compensateOrClean(record: &record, client: client)
                if !cleanupIsUnknown { _ = journal.remove(fingerprint: fingerprint) }
            }
            throw error
        } catch {
            let cleanupIsUnknown = await compensateOrClean(record: &record, client: client)
            if !cleanupIsUnknown { _ = journal.remove(fingerprint: fingerprint) }
            throw error
        }
    }

    private func resumableRecord(
        identity: MissCatComposeOperationRecord.Identity
    ) throws -> MissCatComposeOperationRecord {
        guard var existing = journal.record(fingerprint: identity.fingerprint) else {
            let record = MissCatComposeOperationRecord(identity: identity)
            try saveJournal(record)
            return record
        }
        guard existing.isValid(for: identity) else {
            let blocked = MissCatComposeOperationRecord(
                identity: identity,
                phase: .outcomeUnknown,
                uncertainEndpoint: "journal"
            )
            _ = journal.save(blocked)
            throw MissCatNativeComposeAPIError.outcomeUnknown(endpoint: "journal")
        }
        switch existing.phase {
        case .outcomeUnknown:
            _ = journal.save(existing)
            throw MissCatNativeComposeAPIError.outcomeUnknown(
                endpoint: existing.uncertainEndpoint ?? "journal"
            )
        case .uploadRequestStarted:
            existing.phase = .outcomeUnknown
            existing.uncertainEndpoint = "drive/files/create"
            _ = journal.save(existing)
            throw MissCatNativeComposeAPIError.outcomeUnknown(endpoint: "drive/files/create")
        case .noteRequestStarted:
            existing.phase = .outcomeUnknown
            existing.uncertainEndpoint = "notes/create"
            _ = journal.save(existing)
            throw MissCatNativeComposeAPIError.outcomeUnknown(endpoint: "notes/create")
        case .cleanupPending:
            let endpoint = existing.createdNoteID == nil ? "drive/files/delete" : "notes/delete"
            existing.phase = .outcomeUnknown
            existing.uncertainEndpoint = endpoint
            _ = journal.save(existing)
            throw MissCatNativeComposeAPIError.outcomeUnknown(endpoint: endpoint)
        case .noteCreated:
            throw MissCatNativeComposeAPIError.alreadyCreated
        case .preparing, .uploading, .readyToCreateNote:
            return existing
        }
    }

    private func saveJournal(_ record: MissCatComposeOperationRecord) throws {
        guard journal.save(record) else {
            throw MissCatNativeComposeAPIError.journalUnavailable
        }
    }

    private func compensateOrClean(
        record: inout MissCatComposeOperationRecord,
        client: MissCatNativeComposeAPIClient
    ) async -> Bool {
        if let noteID = record.createdNoteID {
            guard !record.noteDeleteAttempted else { return true }
            record.noteDeleteAttempted = true
            record.phase = .cleanupPending
            record.uncertainEndpoint = nil
            guard journal.save(record) else { return true }
            let cleanup = Task { try await client.deleteNote(id: noteID) }
            if (try? await cleanup.value) == nil {
                record.phase = .outcomeUnknown
                record.uncertainEndpoint = "notes/delete"
                _ = journal.save(record)
                return true
            }
            return false
        }

        for fileID in record.knownFileIDs where !record.cleanupAttemptedFileIDs.contains(fileID) {
            record.cleanupAttemptedFileIDs.append(fileID)
            record.phase = .cleanupPending
            record.uncertainEndpoint = nil
            guard journal.save(record) else { return true }
            let cleanup = Task { try await client.deleteFile(id: fileID) }
            if (try? await cleanup.value) == nil {
                record.phase = .outcomeUnknown
                record.uncertainEndpoint = "drive/files/delete"
                _ = journal.save(record)
                return true
            }
        }
        return false
    }

    func operationFingerprint(for submission: MissCatComposeSubmission) -> String {
        var parts = [
            Data(submission.accountID.utf8),
            Data(operation(for: submission.mode).rawValue.utf8),
            Data(submission.text.utf8),
            Data((submission.contentWarning ?? "").utf8),
            Data(submission.visibility.rawValue.utf8),
            Data(submission.visibleUserIDs.joined(separator: "\u{1f}").utf8),
            Data("\(submission.localOnly)|\(submission.noExtractMentions)|\(submission.noExtractHashtags)".utf8),
            Data((submission.replyID ?? "").utf8),
            Data((submission.renoteID ?? "").utf8)
        ]
        for media in submission.media {
            parts.append(Data("\(media.kind.rawValue)|\(media.filename)|\(media.mimeType)|\(media.altText)|\(media.isSensitive)".utf8))
            parts.append(media.data)
        }
        if let poll = submission.poll {
            parts.append(Data(poll.choices.joined(separator: "\u{1f}").utf8))
            parts.append(Data("\(poll.allowsMultiple)|\(poll.expiresAtMilliseconds ?? -1)|\(poll.expiresAfterMilliseconds ?? -1)".utf8))
        }
        return MissCatComposeOperationFingerprint.make(parts: parts)
    }

    func operationIdentity(
        for submission: MissCatComposeSubmission,
        scope: MissCatComposeAccountScope
    ) -> MissCatComposeOperationRecord.Identity {
        MissCatComposeOperationRecord.Identity(
            fingerprint: operationFingerprint(for: submission),
            operation: operation(for: submission.mode),
            accountIdentifierHash: MissCatComposeOperationFingerprint.accountHash(submission.accountID),
            instanceOriginHash: MissCatComposeOperationFingerprint.make(parts: [Data(scope.origin.absoluteString.utf8)]),
            mediaCount: submission.media.count
        )
    }

    private func operation(
        for mode: MissCatComposeMode
    ) -> MissCatComposeOperationRecord.Identity.Operation {
        switch mode {
        case .note: .note
        case .reply: .reply
        case .quote: .quote
        case .renote: .renote
        }
    }

    private func preparedUpload(for media: MissCatComposeMedia) async throws -> (data: Data, mimeType: String, filename: String) {
        switch media.kind {
        case .image:
            guard MissCatComposeImageCodec.decode(media.data) != nil else {
                throw ServiceError.unsupportedMedia
            }
            guard let data = MissCatComposeImageCodec.jpegData(
                from: media.data,
                maximumWidth: 1_024,
                compressionQuality: 0.5
            ) else {
                throw ServiceError.imageEncodingFailed
            }
            return (data, "image/jpeg", media.filename.replacingPathExtension(with: "jpeg"))
        case .video:
            guard !media.data.isEmpty else { throw ServiceError.unsupportedMedia }
            if media.mimeType == "video/mp4" || media.filename.lowercased().hasSuffix(".mp4") {
                return (media.data, "video/mp4", media.filename.replacingPathExtension(with: "mp4"))
            }
            let converted = try await Self.convertToMP4(media.data)
            return (converted, "video/mp4", media.filename.replacingPathExtension(with: "mp4"))
        }
    }

    private static func convertToMP4(_ data: Data) async throws -> Data {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("misscat-compose-\(UUID().uuidString)", isDirectory: true)
        let inputURL = temporaryDirectory.appendingPathComponent("input.mov")
        let outputURL = temporaryDirectory.appendingPathComponent("output.mp4")
        do {
            try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
            try data.write(to: inputURL, options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: temporaryDirectory)
            throw ServiceError.unsupportedMedia
        }
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let asset = AVURLAsset(url: inputURL)
        guard let exporter = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw ServiceError.unsupportedMedia
        }
        exporter.outputURL = outputURL
        exporter.outputFileType = .mp4
        exporter.shouldOptimizeForNetworkUse = true
        let exporterBox = MissCatUncheckedSendableBox(exporter)

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                exporterBox.value.exportAsynchronously {
                    let exporter = exporterBox.value
                    if exporter.status == .completed {
                        continuation.resume(returning: ())
                    } else if exporter.status == .cancelled {
                        continuation.resume(throwing: CancellationError())
                    } else {
                        continuation.resume(throwing: ServiceError.unsupportedMedia)
                    }
                }
            }
        } onCancel: {
            exporterBox.value.cancelExport()
        }
        guard let converted = try? Data(contentsOf: outputURL), !converted.isEmpty else {
            throw ServiceError.unsupportedMedia
        }
        return converted
    }
}

private extension MissCatComposeVisibility {
    var composeAPIVisibility: MissCatComposeAPIVisibility {
        switch self {
        case .public: .public
        case .home: .home
        case .followers: .followers
        case .specified: .specified
        }
    }
}

private final class MissCatUncheckedSendableBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

private extension String {
    func replacingPathExtension(with pathExtension: String) -> String {
        let base = (self as NSString).deletingPathExtension
        return (base.isEmpty ? UUID().uuidString : base) + "." + pathExtension
    }
}

enum MissCatComposeImageCodec {
    static func decode(_ data: Data, maximumWidth: CGFloat? = nil) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let rawWidth = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let rawHeight = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              rawWidth > 0,
              rawHeight > 0
        else {
            return nil
        }

        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let swapsDimensions = (5 ... 8).contains(orientation)
        let displayWidth = swapsDimensions ? rawHeight : rawWidth
        let scale = maximumWidth.map { min(1, Double($0) / displayWidth) } ?? 1
        let maximumPixelSize = max(1, Int(ceil(max(rawWidth, rawHeight) * scale)))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    static func jpegData(
        from data: Data,
        maximumWidth: CGFloat,
        compressionQuality: CGFloat
    ) -> Data? {
        guard let image = decode(data, maximumWidth: maximumWidth) else { return nil }
        return jpegData(from: image, compressionQuality: compressionQuality)
    }

    static func jpegData(from image: CGImage, compressionQuality: CGFloat) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            "public.jpeg" as CFString,
            1,
            nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: compressionQuality] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
