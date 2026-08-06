import UIKit

@MainActor
final class SharePostService: SharePosting {
    private let userModel: UserModel
    private let transport: any MissCatComposeHTTPTransport
    private let requestTimeout: TimeInterval
    private var isSubmitting = false

    init(
        userModel: UserModel,
        transport: any MissCatComposeHTTPTransport = MissCatComposeURLSessionTransport(),
        requestTimeout: TimeInterval = MissCatNativeComposeAPIClient.defaultTimeout
    ) {
        self.userModel = userModel
        self.transport = transport
        self.requestTimeout = requestTimeout
    }

    func submit(
        draft: ShareDraft,
        accountID: String,
        visibility: ShareVisibility
    ) async throws {
        guard !isSubmitting else {
            throw MissCatNativeComposeAPIError.alreadySubmitting
        }
        isSubmitting = true
        defer { isSubmitting = false }

        guard let user = userModel.getUser(userId: accountID) else {
            throw PostModel.PostingError.accountUnavailable
        }

        let model = try PostModel(
            user: user,
            transport: transport,
            requestTimeout: requestTimeout
        )
        try await model.submitNote(draft: draft, visibility: visibility)
    }
}

@MainActor
final class PostModel {
    enum PostingError: LocalizedError {
        case accountUnavailable
        case emptyContent
        case invalidImage
        case imageEncodingFailed

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
            }
        }
    }

    private let client: MissCatNativeComposeAPIClient

    init(
        user: SecureUser,
        transport: any MissCatComposeHTTPTransport = MissCatComposeURLSessionTransport(),
        requestTimeout: TimeInterval = MissCatNativeComposeAPIClient.defaultTimeout
    ) throws {
        guard let apiKey = user.apiKey, !apiKey.isEmpty else {
            throw PostingError.accountUnavailable
        }
        client = MissCatNativeComposeAPIClient(
            scope: try MissCatComposeAccountScope(
                accountID: user.userId,
                instance: user.instance,
                accessToken: apiKey
            ),
            transport: transport,
            timeout: requestTimeout
        )
    }

    func submitNote(draft: ShareDraft, visibility: ShareVisibility) async throws {
        guard draft.hasContent else { throw PostingError.emptyContent }

        var fileIDs: [String] = []
        for imageData in draft.imageData {
            try Task.checkCancellation()
            fileIDs.append(try await uploadImage(imageData))
        }

        _ = try await client.createNote(
            MissCatComposeAPINote(
                visibility: visibility.composeAPIVisibility,
                text: draft.text,
                fileIDs: fileIDs
            )
        )
    }

    private func uploadImage(_ data: Data) async throws -> String {
        guard let image = UIImage(data: data) else { throw PostingError.invalidImage }
        guard let resizedImage = image.resized(widthUnder: 1024),
              let targetData = resizedImage.jpegData(compressionQuality: 0.5)
        else {
            throw PostingError.imageEncodingFailed
        }

        return try await client.upload(
            MissCatComposeAPIUpload(
                data: targetData,
                mimeType: "image/jpeg",
                filename: UUID().uuidString + ".jpeg",
                comment: nil,
                isSensitive: false
            )
        )
    }
}

private extension ShareVisibility {
    var composeAPIVisibility: MissCatComposeAPIVisibility {
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
