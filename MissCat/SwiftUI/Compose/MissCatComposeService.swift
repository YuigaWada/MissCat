@preconcurrency import AVFoundation
import Foundation
import MediaPlayer
import MisskeyKit
import UIKit

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
        cache.changeCurrentUser(userId: id)
    }

    func persistVisibility(_ visibility: MissCatComposeVisibility) {
        guard let value = Visibility(rawValue: visibility.rawValue) else { return }
        cache.setCurrentVisibility(value)
    }
}

@MainActor
final class MissCatNowPlayingProvider: MissCatNowPlayingProviding {
    func current() -> MissCatNowPlaying? {
        guard let item = MPMusicPlayerController.systemMusicPlayer.nowPlayingItem else { return nil }
        let artwork = item.artwork?.image(at: CGSize(width: 600, height: 600))
            .flatMap { $0.jpegData(compressionQuality: 0.9) }
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

        guard let user = userProvider(submission.accountID),
              user.accountIdentifier == submission.accountID,
              let apiKey = user.apiKey,
              !apiKey.isEmpty
        else {
            throw ServiceError.accountUnavailable
        }

        let scope = try MissCatComposeAccountScope(
            accountID: submission.accountID,
            instance: user.instance,
            accessToken: apiKey
        )
        let client = MissCatNativeComposeAPIClient(
            scope: scope,
            transport: transport,
            timeout: requestTimeout
        )

        let fingerprint = operationFingerprint(for: submission)
        var record = try resumableRecord(fingerprint: fingerprint)

        do {
            var fileIDs = Array(record.knownFileIDs.prefix(submission.media.count))
            if !fileIDs.isEmpty {
                progress(MissCatComposeUploadProgress(completed: fileIDs.count, total: submission.media.count))
            }
            for (index, media) in submission.media.enumerated() where index >= fileIDs.count {
                try Task.checkCancellation()
                let upload = try await preparedUpload(for: media)
                record.phase = .uploading
                journal.save(record)
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
                journal.save(record)
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
            journal.save(record)
            try Task.checkCancellation()
            record.phase = .noteRequestStarted
            journal.save(record)
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
            journal.save(record)
            try Task.checkCancellation()
            journal.remove(fingerprint: fingerprint)
        } catch let error as MissCatNativeComposeAPIError {
            if case .outcomeUnknown = error {
                record.phase = .outcomeUnknown
                journal.save(record)
            } else {
                let cleanupIsUnknown = await compensateOrClean(record: &record, client: client)
                if !cleanupIsUnknown { journal.remove(fingerprint: fingerprint) }
            }
            throw error
        } catch {
            let cleanupIsUnknown = await compensateOrClean(record: &record, client: client)
            if !cleanupIsUnknown { journal.remove(fingerprint: fingerprint) }
            throw error
        }
    }

    private func resumableRecord(fingerprint: String) throws -> MissCatComposeOperationRecord {
        guard var existing = journal.record(fingerprint: fingerprint) else {
            let record = MissCatComposeOperationRecord(fingerprint: fingerprint)
            journal.save(record)
            return record
        }
        switch existing.phase {
        case .outcomeUnknown, .noteRequestStarted:
            existing.phase = .outcomeUnknown
            journal.save(existing)
            throw MissCatNativeComposeAPIError.outcomeUnknown(endpoint: "notes/create")
        case .noteCreated:
            throw MissCatNativeComposeAPIError.alreadyCreated
        case .preparing, .uploading, .readyToCreateNote:
            return existing
        }
    }

    private func compensateOrClean(
        record: inout MissCatComposeOperationRecord,
        client: MissCatNativeComposeAPIClient
    ) async -> Bool {
        if let noteID = record.createdNoteID {
            guard !record.noteDeleteAttempted else { return true }
            record.noteDeleteAttempted = true
            journal.save(record)
            let cleanup = Task { try await client.deleteNote(id: noteID) }
            if (try? await cleanup.value) == nil {
                record.phase = .outcomeUnknown
                journal.save(record)
                return true
            }
            return false
        }

        for fileID in record.knownFileIDs where !record.cleanupAttemptedFileIDs.contains(fileID) {
            record.cleanupAttemptedFileIDs.append(fileID)
            journal.save(record)
            let cleanup = Task { try await client.deleteFile(id: fileID) }
            _ = try? await cleanup.value
        }
        return false
    }

    private func operationFingerprint(for submission: MissCatComposeSubmission) -> String {
        var parts = [
            Data(submission.accountID.utf8),
            Data(String(describing: submission.mode).utf8),
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

    private func preparedUpload(for media: MissCatComposeMedia) async throws -> (data: Data, mimeType: String, filename: String) {
        switch media.kind {
        case .image:
            guard let image = UIImage(data: media.data) else { throw ServiceError.unsupportedMedia }
            guard let resized = image.missCatResized(widthUnder: 1_024),
                  let data = resized.jpegData(compressionQuality: 0.5)
            else {
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

private extension UIImage {
    func missCatResized(widthUnder maximumWidth: CGFloat) -> UIImage? {
        guard size.width > maximumWidth else { return self }
        let ratio = maximumWidth / size.width
        let canvasSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        let renderer = UIGraphicsImageRenderer(size: canvasSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: canvasSize))
        }
    }
}
