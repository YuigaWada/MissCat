import Foundation

/// Instance-scoped emoji catalog used by the native reaction settings screen.
/// It preserves the eager post-login fetch while keeping rendering independent
/// from the retired MFM/UIKit implementation.
@MainActor
final class MissCatEmojiCatalog {
    typealias CategorizedEmojis = [String: [MissCatEmojiArchive.EmojiModel]]

    private static var catalogs: [MissCatEmojiCatalog] = []

    static func prepare(for owner: SecureUser) {
        guard catalog(for: owner) == nil,
              let client = try? MissCatNativeAPIClient(owner: owner)
        else { return }
        catalogs.append(MissCatEmojiCatalog(client: client, owner: owner))
    }

    static func catalog(for owner: SecureUser) -> MissCatEmojiCatalog? {
        catalogs.first { $0.owner.normalizedInstance == owner.normalizedInstance }
    }

    private(set) var categorizedDefaultEmojis: CategorizedEmojis = [:]
    private(set) var categorizedCustomEmojis: CategorizedEmojis = [:]

    private let owner: SecureUser

    private init(client: MissCatNativeAPIClient, owner: SecureUser) {
        self.owner = owner
        categorizedDefaultEmojis = Self.categorizeDefaults(
            MissCatReactionSettingsStore.legacyDefaults
        )
        Task { [weak self] in
            guard let emojis = try? await client.customEmojis() else { return }
            self?.categorizedCustomEmojis = Self.categorizeCustom(emojis)
        }
    }

    private static func categorizeDefaults(
        _ emojis: [String]
    ) -> CategorizedEmojis {
        emojis.reduce(into: CategorizedEmojis()) { result, emoji in
            result["Standard", default: []].append(
                MissCatEmojiArchive.EmojiModel(
                    rawEmoji: emoji,
                    isDefault: true,
                    defaultEmoji: emoji,
                    customEmojiUrl: nil
                )
            )
        }
    }

    private static func categorizeCustom(
        _ emojis: [MissCatNativeEmoji]
    ) -> CategorizedEmojis {
        emojis.reduce(into: CategorizedEmojis()) { result, emoji in
            let category = emoji.category?.nonEmpty ?? "Others"
            result[category, default: []].append(
                MissCatEmojiArchive.EmojiModel(
                    rawEmoji: emoji.name,
                    isDefault: false,
                    defaultEmoji: nil,
                    customEmojiUrl: emoji.url
                )
            )
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
