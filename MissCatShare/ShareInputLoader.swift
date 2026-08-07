import Foundation
import UniformTypeIdentifiers

@MainActor
protocol ShareInputLoading {
    func load(inputItems: [Any]) async throws -> ShareDraft
}

final class ShareInputLoader: ShareInputLoading {
    private enum LoadedItem: Sendable {
        case text(String)
        case url(URL)
        case data(Data)
    }

    enum LoadingError: LocalizedError {
        case noSupportedContent
        case unreadableAttachment

        var errorDescription: String? {
            switch self {
            case .noSupportedContent:
                "共有されたテキスト、URL、画像を取得できませんでした"
            case .unreadableAttachment:
                "共有されたデータを読み込めませんでした"
            }
        }
    }

    func load(inputItems: [Any]) async throws -> ShareDraft {
        let extensionItems = inputItems.compactMap { $0 as? NSExtensionItem }
        let initialTexts = extensionItems.compactMap { $0.attributedContentText?.string }
        let providers = extensionItems.flatMap { $0.attachments ?? [] }

        var fragments: [ShareInputFragment] = []
        var firstLoadingError: Error?

        for provider in providers {
            do {
                if let fragment = try await load(provider: provider) {
                    fragments.append(fragment)
                }
            } catch {
                firstLoadingError = firstLoadingError ?? error
            }
        }

        let draft = ShareContentNormalizer.normalize(
            initialTexts: initialTexts,
            fragments: fragments
        )
        if draft.hasContent {
            return draft
        }
        if let firstLoadingError {
            throw firstLoadingError
        }
        throw LoadingError.noSupportedContent
    }

    private func load(provider: NSItemProvider) async throws -> ShareInputFragment? {
        if let typeIdentifier = Self.registeredTypeIdentifier(in: provider, conformingTo: .image) {
            return .imageData(
                try await loadImageData(provider: provider, typeIdentifier: typeIdentifier)
            )
        }
        if let typeIdentifier = Self.registeredTypeIdentifier(in: provider, conformingTo: .url) {
            let item = try await loadItem(provider: provider, typeIdentifier: typeIdentifier)
            guard let url = Self.url(from: item) else { throw LoadingError.unreadableAttachment }
            return .url(url)
        }
        if let typeIdentifier = Self.registeredTypeIdentifier(in: provider, conformingTo: .text) {
            let item = try await loadItem(provider: provider, typeIdentifier: typeIdentifier)
            guard let text = Self.text(from: item) else { throw LoadingError.unreadableAttachment }
            return .text(text)
        }
        return nil
    }

    private func loadImageData(
        provider: NSItemProvider,
        typeIdentifier: String
    ) async throws -> Data {
        do {
            return try await withCheckedThrowingContinuation { continuation in
                provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let data, !data.isEmpty {
                        continuation.resume(returning: data)
                    } else {
                        continuation.resume(throwing: LoadingError.unreadableAttachment)
                    }
                }
            }
        } catch {
            if let data = try? await loadFileData(
                provider: provider,
                typeIdentifier: typeIdentifier
            ), !data.isEmpty {
                return data
            }
            let item = try await loadItem(provider: provider, typeIdentifier: typeIdentifier)
            if let url = Self.url(from: item), url.isFileURL {
                return try Self.readFile(at: url)
            }
            if case let .data(data) = item, !data.isEmpty {
                return data
            }
            throw error
        }
    }

    private func loadFileData(
        provider: NSItemProvider,
        typeIdentifier: String
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let url {
                    do {
                        continuation.resume(returning: try Self.readFile(at: url))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                } else {
                    continuation.resume(throwing: LoadingError.unreadableAttachment)
                }
            }
        }
    }

    private static func registeredTypeIdentifier(
        in provider: NSItemProvider,
        conformingTo expectedType: UTType
    ) -> String? {
        provider.registeredTypeIdentifiers.first { identifier in
            UTType(identifier)?.conforms(to: expectedType) == true
        }
    }

    private func loadItem(
        provider: NSItemProvider,
        typeIdentifier: String
    ) async throws -> LoadedItem {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let item, let loadedItem = Self.loadedItem(from: item) {
                    continuation.resume(returning: loadedItem)
                } else {
                    continuation.resume(throwing: LoadingError.unreadableAttachment)
                }
            }
        }
    }

    nonisolated private static func loadedItem(from item: NSSecureCoding) -> LoadedItem? {
        if let url = item as? URL {
            return .url(url)
        }
        if let string = item as? String {
            return .text(string)
        }
        if let attributedString = item as? NSAttributedString {
            return .text(attributedString.string)
        }
        if let data = item as? Data {
            return .data(data)
        }
        return nil
    }

    private static func text(from item: LoadedItem) -> String? {
        switch item {
        case let .text(string):
            return string
        case let .data(data):
            return String(data: data, encoding: .utf8)
        case .url:
            return nil
        }
    }

    private static func url(from item: LoadedItem) -> URL? {
        switch item {
        case let .url(url):
            return url
        case let .text(string):
            return URL(string: string)
        case .data:
            return nil
        }
    }

    nonisolated private static func readFile(at url: URL) throws -> Data {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try Data(contentsOf: url)
    }
}
