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
                id: $0.userId,
                username: $0.username,
                instance: $0.instance,
                avatarURL: nil
            )
        }
        let currentID = cache.getCurrentUser()?.userId
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
        case uploadFailed
        case postFailed

        var errorDescription: String? {
            switch self {
            case .accountUnavailable: "投稿に使うアカウント情報を取得できませんでした"
            case .unsupportedMedia: "添付ファイルを読み込めませんでした"
            case .imageEncodingFailed: "画像を投稿用に変換できませんでした"
            case .uploadFailed: "添付ファイルのアップロードに失敗しました"
            case .postFailed: "送信に失敗しました。通信状態を確認して再試行してください"
            }
        }
    }

    private let userProvider: (String) -> SecureUser?

    init(userProvider: @escaping (String) -> SecureUser? = { Cache.UserDefaults.shared.getUser(userId: $0) }) {
        self.userProvider = userProvider
    }

    func submit(
        _ submission: MissCatComposeSubmission,
        progress: @escaping (MissCatComposeUploadProgress) -> Void
    ) async throws {
        guard let user = userProvider(submission.accountID),
              let apiKey = user.apiKey,
              !apiKey.isEmpty
        else {
            throw ServiceError.accountUnavailable
        }

        let misskey = MisskeyKit()
        misskey.changeInstance(instance: user.instance)
        misskey.auth.setAPIKey(apiKey)

        var fileIDs: [String] = []
        for (index, media) in submission.media.enumerated() {
            let upload = try preparedUpload(for: media)
            let fileID = try await uploadFile(upload, media: media, using: misskey)
            fileIDs.append(fileID)
            progress(MissCatComposeUploadProgress(completed: index + 1, total: submission.media.count))
        }

        let poll = submission.poll.map {
            Poll(
                choices: $0.choices,
                multiple: $0.allowsMultiple,
                expiresAt: $0.expiresAtMilliseconds.map(String.init),
                expiredAfter: $0.expiresAfterMilliseconds.map(String.init)
            )
        }
        try await createNote(
            submission,
            fileIDs: fileIDs,
            poll: poll,
            using: misskey
        )
    }

    private func preparedUpload(for media: MissCatComposeMedia) throws -> (data: Data, mimeType: String, filename: String) {
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
            return (media.data, media.mimeType, media.filename)
        }
    }

    private func uploadFile(
        _ upload: (data: Data, mimeType: String, filename: String),
        media: MissCatComposeMedia,
        using misskey: MisskeyKit
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            misskey.drive.createFile(
                fileData: upload.data,
                fileType: upload.mimeType,
                name: upload.filename,
                isSensitive: media.isSensitive,
                force: false,
                comment: media.altText
            ) { result, error in
                if error == nil, let id = result?.id, !id.isEmpty {
                    continuation.resume(returning: id)
                } else {
                    continuation.resume(throwing: ServiceError.uploadFailed)
                }
            }
        }
    }

    private func createNote(
        _ submission: MissCatComposeSubmission,
        fileIDs: [String],
        poll: Poll?,
        using misskey: MisskeyKit
    ) async throws {
        let visibility = Visibility(rawValue: submission.visibility.rawValue) ?? .public
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let callback: OneNoteCallBack = { note, error in
                if note != nil, error == nil {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: ServiceError.postFailed)
                }
            }

            if let renoteID = submission.renoteID {
                misskey.notes.renote(
                    renoteId: renoteID,
                    quote: submission.text,
                    visibility: visibility,
                    visibleUserIds: submission.visibleUserIDs,
                    cw: submission.contentWarning ?? "",
                    viaMobile: true,
                    localOnly: submission.localOnly,
                    noExtractMentions: submission.noExtractMentions,
                    noExtractHashtags: submission.noExtractHashtags,
                    noExtractEmojis: false,
                    fileIds: fileIDs,
                    poll: poll,
                    completion: callback
                )
            } else {
                misskey.notes.createNote(
                    visibility: visibility,
                    visibleUserIds: submission.visibleUserIDs,
                    text: submission.text,
                    cw: submission.contentWarning ?? "",
                    viaMobile: true,
                    localOnly: submission.localOnly,
                    noExtractMentions: submission.noExtractMentions,
                    noExtractHashtags: submission.noExtractHashtags,
                    noExtractEmojis: false,
                    fileIds: fileIDs,
                    replyId: submission.replyID ?? "",
                    poll: poll,
                    completion: callback
                )
            }
        }
    }
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
