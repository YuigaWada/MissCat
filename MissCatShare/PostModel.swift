import MisskeyKit
import UIKit

@MainActor
final class SharePostService: SharePosting {
    private let userModel: UserModel

    init(userModel: UserModel) {
        self.userModel = userModel
    }

    func submit(
        draft: ShareDraft,
        accountID: String,
        visibility: ShareVisibility
    ) async throws {
        guard let user = userModel.getUser(userId: accountID) else {
            throw PostModel.PostingError.accountUnavailable
        }

        let model = PostModel(user: user)
        guard model.isAvailable else { throw PostModel.PostingError.accountUnavailable }
        try await model.submitNote(draft: draft, visibility: visibility)
    }
}

final class PostModel {
    enum PostingError: LocalizedError {
        case accountUnavailable
        case emptyContent
        case invalidImage
        case imageEncodingFailed
        case uploadFailed
        case postFailed

        var errorDescription: String? {
            switch self {
            case .accountUnavailable:
                "投稿に使うアカウント情報を取得できませんでした"
            case .emptyContent:
                "投稿するテキストまたは画像がありません"
            case .invalidImage:
                "共有された画像を読み込めませんでした"
            case .imageEncodingFailed:
                "共有された画像を投稿用に変換できませんでした"
            case .uploadFailed:
                "画像のアップロードに失敗しました"
            case .postFailed:
                "送信に失敗しました。通信状態を確認して再試行してください"
            }
        }
    }

    private let misskey: MisskeyKit?

    var isAvailable: Bool { misskey != nil }

    init(user: SecureUser) {
        guard let apiKey = user.apiKey, !apiKey.isEmpty else {
            misskey = nil
            return
        }

        let misskey = MisskeyKit()
        misskey.changeInstance(instance: user.instance)
        misskey.auth.setAPIKey(apiKey)
        self.misskey = misskey
    }

    func submitNote(draft: ShareDraft, visibility: ShareVisibility) async throws {
        guard misskey != nil else { throw PostingError.accountUnavailable }
        guard draft.hasContent else { throw PostingError.emptyContent }

        var fileIDs: [String] = []
        for imageData in draft.imageData {
            fileIDs.append(try await uploadImage(imageData))
        }

        try await createNote(
            text: draft.text,
            fileIDs: fileIDs,
            visibility: visibility.misskeyVisibility
        )
    }

    private func uploadImage(_ data: Data) async throws -> String {
        guard let image = UIImage(data: data) else { throw PostingError.invalidImage }
        guard let resizedImage = image.resized(widthUnder: 1024),
              let targetData = resizedImage.jpegData(compressionQuality: 0.5)
        else {
            throw PostingError.imageEncodingFailed
        }

        return try await withCheckedThrowingContinuation { continuation in
            guard let misskey else {
                continuation.resume(throwing: PostingError.accountUnavailable)
                return
            }
            misskey.drive.createFile(
                fileData: targetData,
                fileType: "image/jpeg",
                name: UUID().uuidString + ".jpeg",
                isSensitive: false,
                force: false
            ) { result, error in
                if error != nil {
                    continuation.resume(throwing: PostingError.uploadFailed)
                } else if let id = result?.id, !id.isEmpty {
                    continuation.resume(returning: id)
                } else {
                    continuation.resume(throwing: PostingError.uploadFailed)
                }
            }
        }
    }

    private func createNote(
        text: String,
        fileIDs: [String],
        visibility: Visibility
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            guard let misskey else {
                continuation.resume(throwing: PostingError.accountUnavailable)
                return
            }
            misskey.notes.createNote(
                visibility: visibility,
                text: text,
                fileIds: fileIDs
            ) { post, error in
                if post != nil, error == nil {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: PostingError.postFailed)
                }
            }
        }
    }
}

private extension ShareVisibility {
    var misskeyVisibility: Visibility {
        switch self {
        case .public:
            .public
        case .home:
            .home
        case .followers:
            .followers
        }
    }
}

private extension UIImage {
    func resized(widthUnder maximumWidth: CGFloat) -> UIImage? {
        guard size.width > maximumWidth else { return self }
        return resized(withPercentage: maximumWidth / size.width)
    }

    func resized(withPercentage percentage: CGFloat) -> UIImage? {
        guard percentage > 0 else { return nil }
        let canvasSize = CGSize(width: size.width * percentage, height: size.height * percentage)
        UIGraphicsBeginImageContextWithOptions(canvasSize, false, scale)
        defer { UIGraphicsEndImageContext() }
        draw(in: CGRect(origin: .zero, size: canvasSize))
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}
