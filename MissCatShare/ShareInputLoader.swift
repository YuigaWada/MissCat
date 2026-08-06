import Foundation
import UniformTypeIdentifiers
import UIKit

protocol ShareInputLoading {
    func load(inputItems: [Any]) async throws -> ShareDraft
}

final class ShareInputLoader: ShareInputLoading {
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
            let item = try await loadItem(provider: provider, typeIdentifier: typeIdentifier)
            if let image = item as? UIImage,
               let data = image.pngData()
            {
                return data
            }
            if let url = Self.url(from: item), url.isFileURL {
                return try Self.readFile(at: url)
            }
            if let data = item as? Data, !data.isEmpty {
                return data
            }
            throw error
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
    ) async throws -> NSSecureCoding {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let item {
                    continuation.resume(returning: item)
                } else {
                    continuation.resume(throwing: LoadingError.unreadableAttachment)
                }
            }
        }
    }

    private static func text(from item: NSSecureCoding) -> String? {
        if let string = item as? String {
            return string
        }
        if let attributedString = item as? NSAttributedString {
            return attributedString.string
        }
        if let data = item as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }

    private static func url(from item: NSSecureCoding) -> URL? {
        if let url = item as? URL {
            return url
        }
        if let string = item as? String {
            return URL(string: string)
        }
        return nil
    }

    private static func readFile(at url: URL) throws -> Data {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try Data(contentsOf: url)
    }
}
