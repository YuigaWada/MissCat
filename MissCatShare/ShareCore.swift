import Combine
import Foundation

enum MissCatAccountIdentity {
    private static let prefix = "misscat-account-v2"

    static func normalizedInstance(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        if let components = URLComponents(string: candidate),
           let host = components.host?.lowercased(),
           !host.isEmpty
        {
            if let port = components.port, port != 443 { return "\(host):\(port)" }
            return host
        }
        return trimmed.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    static func storageKey(instance: String, userId: String) -> String {
        let instanceValue = Data(normalizedInstance(instance).utf8).base64EncodedString()
        let userValue = Data(userId.utf8).base64EncodedString()
        return "\(prefix):\(instanceValue):\(userValue)"
    }
}

struct ShareAccount: Identifiable, Equatable, Sendable {
    let id: String
    let username: String
    let instance: String

    init(id: String, username: String, instance: String) {
        self.id = id
        self.username = username
        self.instance = instance
    }

    init(userID: String, username: String, instance: String) {
        id = MissCatAccountIdentity.storageKey(instance: instance, userId: userID)
        self.username = username
        self.instance = MissCatAccountIdentity.normalizedInstance(instance)
    }

    var displayName: String {
        "\(username)@\(instance)"
    }
}

/// Safe result for a signed-extension credential-read check. It intentionally
/// cannot carry or describe the credential itself.
struct ShareCredentialReadProof: Equatable, Sendable, CustomStringConvertible {
    let accountIdentifierHash: String
    let credentialAvailable: Bool

    var description: String {
        "ShareCredentialReadProof(accountIdentifierHash: \(accountIdentifierHash), credentialAvailable: \(credentialAvailable))"
    }
}

enum ShareCredentialReadProbe {
    static let launchArgument = "--misscat-share-credential-proof"
    static let resultKey = "share-credential-proof.available"
    static let accountHashKey = "share-credential-proof.account-hash"

    @discardableResult
    static func invokeIfRequested(
        arguments: [String],
        accountIdentifier: String?,
        read: (String) -> ShareCredentialReadProof,
        store: (ShareCredentialReadProof) -> Void
    ) -> Bool {
        guard arguments.contains(launchArgument), let accountIdentifier else { return false }
        store(read(accountIdentifier))
        return true
    }
}

@MainActor
final class ShareRequestTerminalArbiter {
    enum Terminal: Equatable { case completed, cancelled }
    private(set) var terminal: Terminal?

    func resolve(_ candidate: Terminal) -> Bool {
        guard terminal == nil else { return false }
        terminal = candidate
        return true
    }
}

enum ShareVisibility: String, CaseIterable, Identifiable, Sendable {
    case `public`
    case home
    case followers

    var id: String { rawValue }
    var apiValue: String { rawValue }
}

enum ShareInputFragment: Equatable, Sendable {
    case text(String)
    case url(URL)
    case imageData(Data)
}

struct ShareDraft: Equatable, Sendable {
    var text: String
    var imageData: [Data]

    static let empty = ShareDraft(text: "", imageData: [])

    var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !imageData.isEmpty
    }
}

enum ShareContentNormalizer {
    static func normalize(
        initialTexts: [String],
        fragments: [ShareInputFragment]
    ) -> ShareDraft {
        var textParts: [String] = []
        var seenTextParts: Set<String> = []
        var images: [Data] = []
        var seenImages: Set<Data> = []

        func appendText(_ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seenTextParts.insert(trimmed).inserted else { return }
            textParts.append(trimmed)
        }

        initialTexts.forEach(appendText)

        for fragment in fragments {
            switch fragment {
            case let .text(value):
                appendText(value)
            case let .url(url):
                let value = url.absoluteString
                guard !textParts.contains(where: { $0.contains(value) }) else { continue }
                appendText(value)
            case let .imageData(data):
                guard !data.isEmpty, seenImages.insert(data).inserted else { continue }
                images.append(data)
            }
        }

        return ShareDraft(text: textParts.joined(separator: "\n"), imageData: images)
    }
}

@MainActor
protocol SharePosting: AnyObject {
    func submit(
        draft: ShareDraft,
        accountID: String,
        visibility: ShareVisibility
    ) async throws
    func cancelActiveSubmission()
}

extension SharePosting {
    func cancelActiveSubmission() {}
}

@MainActor
final class ShareComposerViewModel: ObservableObject {
    static let maximumTextLength = 1_500

    enum Phase: Equatable {
        case loading
        case ready
        case posting
        case failed
        case outcomeUnknown
        case completed
        case cancelled
    }

    @Published var text = ""
    @Published var selectedAccountID: String?
    @Published var visibility: ShareVisibility
    @Published private(set) var imageData: [Data] = []
    @Published private(set) var phase: Phase = .loading
    @Published private(set) var errorMessage: String?

    let accounts: [ShareAccount]
    private let posting: SharePosting
    private var submissionTask: Task<Bool, Never>?
    private var submissionID: UUID?

    init(
        accounts: [ShareAccount],
        selectedAccountID: String?,
        visibility: ShareVisibility,
        posting: SharePosting
    ) {
        self.accounts = accounts
        self.selectedAccountID = selectedAccountID
        self.visibility = visibility
        self.posting = posting
    }

    var selectedAccount: ShareAccount? {
        guard let selectedAccountID else { return nil }
        return accounts.first { $0.id == selectedAccountID }
    }

    var canPost: Bool {
        (phase == .ready || phase == .failed)
            && selectedAccount != nil
            && text.count <= Self.maximumTextLength
            && ShareDraft(text: text, imageData: imageData).hasContent
    }

    func beginLoading() {
        guard phase != .posting, phase != .completed else { return }
        errorMessage = nil
        phase = .loading
    }

    func load(_ draft: ShareDraft) {
        guard phase == .loading else { return }
        text = draft.text
        imageData = draft.imageData
        errorMessage = accounts.isEmpty ? "MissCatでログインしてから、もう一度お試しください" : nil
        phase = accounts.isEmpty ? .failed : .ready
    }

    func failLoading(_ error: Error) {
        guard phase == .loading else { return }
        errorMessage = error.localizedDescription
        phase = .failed
    }

    func clearError() {
        errorMessage = nil
        if phase == .failed, !accounts.isEmpty {
            phase = .ready
        }
    }

    func submit() async -> Bool {
        guard phase == .ready || phase == .failed else { return false }
        guard let selectedAccountID, selectedAccount != nil else {
            errorMessage = "投稿に使うアカウントを選択してください"
            phase = .failed
            return false
        }

        let draft = ShareDraft(text: text, imageData: imageData)
        guard draft.hasContent else {
            errorMessage = "投稿するテキストまたは画像を追加してください"
            phase = .failed
            return false
        }
        guard text.count <= Self.maximumTextLength else {
            errorMessage = "投稿内容は\(Self.maximumTextLength)文字以内にしてください"
            phase = .failed
            return false
        }

        phase = .posting
        errorMessage = nil

        let operationID = UUID()
        submissionID = operationID
        let task = Task { @MainActor [weak self] in
            guard let self else { return false }
            do {
                try await posting.submit(
                    draft: draft,
                    accountID: selectedAccountID,
                    visibility: visibility
                )
                return resolveTerminal(.completed, operationID: operationID)
            } catch let error as MissCatNativeComposeAPIError {
                if case .outcomeUnknown = error {
                    errorMessage = error.localizedDescription
                    _ = resolveTerminal(.outcomeUnknown, operationID: operationID)
                } else if !isTerminal {
                    errorMessage = error.localizedDescription
                    phase = .failed
                }
                return false
            } catch is CancellationError {
                _ = resolveTerminal(.cancelled, operationID: operationID)
                return false
            } catch {
                guard !isTerminal else { return false }
                errorMessage = error.localizedDescription
                phase = .failed
                return false
            }
        }
        submissionTask = task
        let result = await task.value
        if submissionID == operationID {
            submissionTask = nil
            submissionID = nil
        }
        return result
    }

    func cancel() {
        guard !isTerminal else { return }
        phase = .cancelled
        posting.cancelActiveSubmission()
        submissionTask?.cancel()
    }

    private var isTerminal: Bool {
        phase == .completed || phase == .cancelled || phase == .outcomeUnknown
    }

    @discardableResult
    private func resolveTerminal(_ terminal: Phase, operationID: UUID) -> Bool {
        guard submissionID == operationID, !isTerminal else { return false }
        phase = terminal
        return true
    }
}
