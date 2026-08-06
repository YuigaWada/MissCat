import UIKit

@MainActor
final class SharePostService: SharePosting {
    private let userProvider: (String) -> SecureUser?
    private let transport: any MissCatComposeHTTPTransport
    private let requestTimeout: TimeInterval
    private let journal: MissCatComposeOperationJournalStoring
    private var activeSubmissionTask: Task<Void, Error>?

    init(
        userModel: UserModel,
        transport: any MissCatComposeHTTPTransport = MissCatComposeURLSessionTransport(),
        requestTimeout: TimeInterval = MissCatNativeComposeAPIClient.defaultTimeout,
        journal: MissCatComposeOperationJournalStoring = MissCatComposeOperationJournal()
    ) {
        userProvider = userModel.getUser(accountIdentifier:)
        self.transport = transport
        self.requestTimeout = requestTimeout
        self.journal = journal
    }

    init(
        userProvider: @escaping (String) -> SecureUser?,
        transport: any MissCatComposeHTTPTransport,
        requestTimeout: TimeInterval = MissCatNativeComposeAPIClient.defaultTimeout,
        journal: MissCatComposeOperationJournalStoring
    ) {
        self.userProvider = userProvider
        self.transport = transport
        self.requestTimeout = requestTimeout
        self.journal = journal
    }

    func submit(
        draft: ShareDraft,
        accountID: String,
        visibility: ShareVisibility
    ) async throws {
        guard activeSubmissionTask == nil else {
            throw MissCatNativeComposeAPIError.alreadySubmitting
        }

        guard let user = userProvider(accountID), user.accountIdentifier == accountID else {
            throw PostModel.PostingError.accountUnavailable
        }

        let model = try PostModel(
            user: user,
            transport: transport,
            requestTimeout: requestTimeout,
            journal: journal
        )
        let task = Task { try await model.submitNote(draft: draft, visibility: visibility) }
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
    private let accountID: String
    private let journal: MissCatComposeOperationJournalStoring

    init(
        user: SecureUser,
        transport: any MissCatComposeHTTPTransport = MissCatComposeURLSessionTransport(),
        requestTimeout: TimeInterval = MissCatNativeComposeAPIClient.defaultTimeout,
        journal: MissCatComposeOperationJournalStoring = MissCatComposeOperationJournal()
    ) throws {
        guard let apiKey = user.apiKey, !apiKey.isEmpty else {
            throw PostingError.accountUnavailable
        }
        accountID = user.accountIdentifier
        self.journal = journal
        client = MissCatNativeComposeAPIClient(
            scope: try MissCatComposeAccountScope(
                accountID: user.accountIdentifier,
                instance: user.instance,
                accessToken: apiKey
            ),
            transport: transport,
            timeout: requestTimeout
        )
    }

    func submitNote(draft: ShareDraft, visibility: ShareVisibility) async throws {
        guard draft.hasContent else { throw PostingError.emptyContent }

        let fingerprint = MissCatComposeOperationFingerprint.make(parts: [
            Data(accountID.utf8),
            Data(visibility.rawValue.utf8),
            Data(draft.text.utf8)
        ] + draft.imageData)
        var record = try resumableRecord(fingerprint: fingerprint)

        do {
            var fileIDs = Array(record.knownFileIDs.prefix(draft.imageData.count))
            for imageData in draft.imageData.dropFirst(fileIDs.count) {
                try Task.checkCancellation()
                let upload = try preparedUpload(imageData)
                record.phase = .uploading
                journal.save(record)
                fileIDs.append(try await client.upload(upload))
                record.knownFileIDs = fileIDs
                journal.save(record)
            }

            record.phase = .readyToCreateNote
            journal.save(record)
            try Task.checkCancellation()
            record.phase = .noteRequestStarted
            journal.save(record)
            let noteID = try await client.createNote(
                MissCatComposeAPINote(
                    visibility: visibility.composeAPIVisibility,
                    text: draft.text,
                    fileIDs: fileIDs
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
                let cleanupIsUnknown = await compensateOrClean(record: &record)
                if !cleanupIsUnknown { journal.remove(fingerprint: fingerprint) }
            }
            throw error
        } catch {
            let cleanupIsUnknown = await compensateOrClean(record: &record)
            if !cleanupIsUnknown { journal.remove(fingerprint: fingerprint) }
            throw error
        }
    }

    private func preparedUpload(_ data: Data) throws -> MissCatComposeAPIUpload {
        guard let image = UIImage(data: data) else { throw PostingError.invalidImage }
        guard let resizedImage = image.resized(widthUnder: 1024),
              let targetData = resizedImage.jpegData(compressionQuality: 0.5)
        else {
            throw PostingError.imageEncodingFailed
        }

        return MissCatComposeAPIUpload(
            data: targetData,
            mimeType: "image/jpeg",
            filename: UUID().uuidString + ".jpeg",
            comment: nil,
            isSensitive: false
        )
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

    private func compensateOrClean(record: inout MissCatComposeOperationRecord) async -> Bool {
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
