import Combine
import Foundation

struct ShareAccount: Identifiable, Equatable, Sendable {
    let id: String
    let username: String
    let instance: String

    var displayName: String {
        "\(username)@\(instance)"
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
}

@MainActor
final class ShareComposerViewModel: ObservableObject {
    static let maximumTextLength = 1_500

    enum Phase: Equatable {
        case loading
        case ready
        case posting
        case failed
        case completed
    }

    @Published var text = ""
    @Published var selectedAccountID: String?
    @Published var visibility: ShareVisibility
    @Published private(set) var imageData: [Data] = []
    @Published private(set) var phase: Phase = .loading
    @Published private(set) var errorMessage: String?

    let accounts: [ShareAccount]
    private let posting: SharePosting

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
        phase != .loading
            && phase != .posting
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

        do {
            try await posting.submit(
                draft: draft,
                accountID: selectedAccountID,
                visibility: visibility
            )
            phase = .completed
            return true
        } catch {
            errorMessage = error.localizedDescription
            phase = .failed
            return false
        }
    }
}
