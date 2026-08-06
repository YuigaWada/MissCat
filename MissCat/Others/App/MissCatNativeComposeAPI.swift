import Foundation

struct MissCatComposeAccountScope: Sendable {
    let accountID: String
    let origin: URL
    fileprivate let accessToken: String

    init(accountID: String, instance: String, accessToken: String) throws {
        guard !accountID.isEmpty,
              !accessToken.isEmpty,
              accessToken.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              accessToken.rangeOfCharacter(from: .controlCharacters) == nil
        else {
            throw MissCatNativeComposeAPIError.invalidCredentials
        }

        let candidate = instance.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = candidate.contains("://") ? candidate : "https://\(candidate)"
        guard var components = URLComponents(string: value),
              components.scheme?.lowercased() == "https",
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              components.percentEncodedPath.isEmpty || components.percentEncodedPath == "/",
              let host = components.host?.lowercased(),
              !host.isEmpty,
              !host.hasSuffix("."),
              components.percentEncodedHost?.contains("%") != true,
              components.port.map({ (1 ... 65_535).contains($0) }) ?? true
        else {
            throw MissCatNativeComposeAPIError.invalidInstance
        }

        components.scheme = "https"
        components.host = host
        components.path = ""
        if components.port == 443 {
            components.port = nil
        }
        guard let origin = components.url else {
            throw MissCatNativeComposeAPIError.invalidInstance
        }

        self.accountID = accountID
        self.origin = origin
        self.accessToken = accessToken
    }
}

enum MissCatComposeAPIVisibility: String, Encodable, Sendable {
    case `public`
    case home
    case followers
    case specified
}

struct MissCatComposeAPIUpload: Sendable {
    let data: Data
    let mimeType: String
    let filename: String
    let comment: String?
    let isSensitive: Bool
}

struct MissCatComposeAPIPoll: Encodable, Sendable {
    let choices: [String]
    let multiple: Bool
    let expiresAt: Int64?
    let expiredAfter: Int64?
}

struct MissCatComposeAPINote: Sendable {
    let visibility: MissCatComposeAPIVisibility
    let visibleUserIDs: [String]
    let text: String
    let contentWarning: String?
    let localOnly: Bool
    let noExtractMentions: Bool
    let noExtractHashtags: Bool
    let noExtractEmojis: Bool
    let fileIDs: [String]
    let replyID: String?
    let renoteID: String?
    let poll: MissCatComposeAPIPoll?

    init(
        visibility: MissCatComposeAPIVisibility,
        visibleUserIDs: [String] = [],
        text: String,
        contentWarning: String? = nil,
        localOnly: Bool = false,
        noExtractMentions: Bool = false,
        noExtractHashtags: Bool = false,
        noExtractEmojis: Bool = false,
        fileIDs: [String] = [],
        replyID: String? = nil,
        renoteID: String? = nil,
        poll: MissCatComposeAPIPoll? = nil
    ) {
        self.visibility = visibility
        self.visibleUserIDs = visibleUserIDs
        self.text = text
        self.contentWarning = contentWarning
        self.localOnly = localOnly
        self.noExtractMentions = noExtractMentions
        self.noExtractHashtags = noExtractHashtags
        self.noExtractEmojis = noExtractEmojis
        self.fileIDs = fileIDs
        self.replyID = replyID
        self.renoteID = renoteID
        self.poll = poll
    }
}

protocol MissCatComposeHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct MissCatComposeURLSessionTransport: MissCatComposeHTTPTransport, @unchecked Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw MissCatNativeComposeAPIError.invalidHTTPResponse
        }
        return (data, response)
    }
}

enum MissCatNativeComposeAPIError: LocalizedError, Equatable {
    case invalidCredentials
    case invalidInstance
    case invalidUpload
    case invalidHTTPResponse
    case invalidResponse(endpoint: String)
    case server(status: Int, code: String?, message: String?, id: String?)
    case alreadySubmitting

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            "投稿に使うアカウント情報を取得できませんでした"
        case .invalidInstance:
            "投稿先インスタンスのURLが正しくありません"
        case .invalidUpload:
            "添付ファイルをアップロード用に準備できませんでした"
        case .invalidHTTPResponse:
            "サーバーからの応答を読み取れませんでした"
        case .invalidResponse:
            "サーバーから予期しない応答が返されました"
        case let .server(status, code, message, _):
            if let message, !message.isEmpty {
                "Misskeyがリクエストを拒否しました（HTTP \(status): \(message)）"
            } else if let code, !code.isEmpty {
                "Misskeyがリクエストを拒否しました（HTTP \(status): \(code)）"
            } else {
                "Misskeyがリクエストを拒否しました（HTTP \(status)）"
            }
        case .alreadySubmitting:
            "この投稿はすでに送信中です"
        }
    }
}

struct MissCatNativeComposeAPIClient: Sendable {
    static let defaultTimeout: TimeInterval = 60

    private let scope: MissCatComposeAccountScope
    private let transport: any MissCatComposeHTTPTransport
    private let timeout: TimeInterval

    init(
        scope: MissCatComposeAccountScope,
        transport: any MissCatComposeHTTPTransport = MissCatComposeURLSessionTransport(),
        timeout: TimeInterval = defaultTimeout
    ) {
        self.scope = scope
        self.transport = transport
        self.timeout = max(1, timeout)
    }

    func upload(_ upload: MissCatComposeAPIUpload) async throws -> String {
        guard !upload.data.isEmpty,
              !upload.filename.isEmpty,
              !upload.mimeType.isEmpty,
              upload.mimeType.rangeOfCharacter(from: .newlines) == nil
        else {
            throw MissCatNativeComposeAPIError.invalidUpload
        }

        let boundary = "MissCat-\(UUID().uuidString)"
        var request = try authenticatedRequest(path: "/api/drive/files/create")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = MultipartBody(boundary: boundary)
            .addingField(name: "name", value: upload.filename)
            .addingOptionalField(name: "comment", value: upload.comment)
            .addingField(name: "isSensitive", value: upload.isSensitive ? "true" : "false")
            .addingField(name: "force", value: "false")
            .addingFile(
                name: "file",
                filename: upload.filename,
                mimeType: upload.mimeType,
                data: upload.data
            )
            .finalized()
        request.setValue(String(request.httpBody?.count ?? 0), forHTTPHeaderField: "Content-Length")

        let data = try await successfulData(for: request)
        guard let response = try? JSONDecoder().decode(DriveFileResponse.self, from: data),
              !response.id.isEmpty
        else {
            throw MissCatNativeComposeAPIError.invalidResponse(endpoint: "drive/files/create")
        }
        return response.id
    }

    func createNote(_ note: MissCatComposeAPINote) async throws -> String {
        var request = try authenticatedRequest(path: "/api/notes/create")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = NoteRequest(note)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        request.httpBody = try encoder.encode(body)

        let data = try await successfulData(for: request)
        guard let response = try? JSONDecoder().decode(NoteCreateResponse.self, from: data),
              !response.createdNote.id.isEmpty
        else {
            throw MissCatNativeComposeAPIError.invalidResponse(endpoint: "notes/create")
        }
        return response.createdNote.id
    }

    private func authenticatedRequest(path: String) throws -> URLRequest {
        guard var components = URLComponents(url: scope.origin, resolvingAgainstBaseURL: false) else {
            throw MissCatNativeComposeAPIError.invalidInstance
        }
        components.percentEncodedPath = path
        guard let url = components.url else {
            throw MissCatNativeComposeAPIError.invalidInstance
        }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(scope.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func successfulData(for request: URLRequest) async throws -> Data {
        try Task.checkCancellation()
        let (data, response) = try await transport.data(for: request)
        try Task.checkCancellation()
        guard (200 ..< 300).contains(response.statusCode) else {
            let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data)
            throw MissCatNativeComposeAPIError.server(
                status: response.statusCode,
                code: redacted(envelope?.error.code),
                message: redacted(envelope?.error.message),
                id: redacted(envelope?.error.id)
            )
        }
        return data
    }

    private func redacted(_ value: String?) -> String? {
        guard let value else { return nil }
        let withoutToken = value.replacingOccurrences(of: scope.accessToken, with: "<redacted>")
        return String(withoutToken.prefix(512))
    }
}

private struct NoteRequest: Encodable {
    let visibility: MissCatComposeAPIVisibility
    let visibleUserIds: [String]
    let text: String?
    let cw: String?
    let localOnly: Bool
    let noExtractMentions: Bool
    let noExtractHashtags: Bool
    let noExtractEmojis: Bool
    let fileIds: [String]?
    let replyId: String?
    let renoteId: String?
    let poll: MissCatComposeAPIPoll?

    init(_ note: MissCatComposeAPINote) {
        visibility = note.visibility
        visibleUserIds = note.visibleUserIDs
        text = note.text.isEmpty ? nil : note.text
        cw = note.contentWarning.flatMap { $0.isEmpty ? nil : $0 }
        localOnly = note.localOnly
        noExtractMentions = note.noExtractMentions
        noExtractHashtags = note.noExtractHashtags
        noExtractEmojis = note.noExtractEmojis
        fileIds = note.fileIDs.isEmpty ? nil : note.fileIDs
        replyId = note.replyID
        renoteId = note.renoteID
        poll = note.poll
    }
}

private struct DriveFileResponse: Decodable {
    let id: String
}

private struct NoteCreateResponse: Decodable {
    struct CreatedNote: Decodable {
        let id: String
    }

    let createdNote: CreatedNote
}

private struct ErrorEnvelope: Decodable {
    struct Detail: Decodable {
        let message: String?
        let code: String?
        let id: String?
    }

    let error: Detail
}

private struct MultipartBody {
    private let boundary: String
    private var data = Data()

    init(boundary: String) {
        self.boundary = boundary
    }

    func addingField(name: String, value: String) -> MultipartBody {
        var copy = self
        copy.append("--\(boundary)\r\n")
        copy.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        copy.append(value)
        copy.append("\r\n")
        return copy
    }

    func addingOptionalField(name: String, value: String?) -> MultipartBody {
        guard let value, !value.isEmpty else { return self }
        return addingField(name: name, value: value)
    }

    func addingFile(
        name: String,
        filename: String,
        mimeType: String,
        data fileData: Data
    ) -> MultipartBody {
        var copy = self
        let unsafeFilenameCharacters = CharacterSet.controlCharacters
            .union(CharacterSet(charactersIn: "\"\\"))
        let safeFilename = filename.unicodeScalars.map { scalar in
            unsafeFilenameCharacters.contains(scalar) ? "_" : String(scalar)
        }.joined()
        copy.append("--\(boundary)\r\n")
        copy.append(
            "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(safeFilename)\"\r\n"
        )
        copy.append("Content-Type: \(mimeType)\r\n\r\n")
        copy.data.append(fileData)
        copy.append("\r\n")
        return copy
    }

    func finalized() -> Data {
        var copy = self
        copy.append("--\(boundary)--\r\n")
        return copy.data
    }

    private mutating func append(_ value: String) {
        data.append(Data(value.utf8))
    }
}
