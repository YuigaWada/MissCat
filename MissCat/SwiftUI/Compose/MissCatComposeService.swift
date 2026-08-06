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
    private var isSubmitting = false

    init(
        userProvider: @escaping (String) -> SecureUser? = { Cache.UserDefaults.shared.getUser(userId: $0) },
        transport: any MissCatComposeHTTPTransport = MissCatComposeURLSessionTransport(),
        requestTimeout: TimeInterval = MissCatNativeComposeAPIClient.defaultTimeout
    ) {
        self.userProvider = userProvider
        self.transport = transport
        self.requestTimeout = requestTimeout
    }

    func submit(
        _ submission: MissCatComposeSubmission,
        progress: @escaping (MissCatComposeUploadProgress) -> Void
    ) async throws {
        guard !isSubmitting else {
            throw MissCatNativeComposeAPIError.alreadySubmitting
        }
        isSubmitting = true
        defer { isSubmitting = false }

        guard let user = userProvider(submission.accountID),
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

        var fileIDs: [String] = []
        for (index, media) in submission.media.enumerated() {
            try Task.checkCancellation()
            let upload = try await preparedUpload(for: media)
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
        let visibility = MissCatComposeAPIVisibility(rawValue: submission.visibility.rawValue) ?? .public
        _ = try await client.createNote(
            MissCatComposeAPINote(
                visibility: visibility,
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
