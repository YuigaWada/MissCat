import MisskeyKit

/// Instance-scoped emoji catalog used by the native reaction settings screen.
/// It preserves the eager post-login fetch while keeping rendering independent
/// from the retired MFM/UIKit implementation.
final class MissCatEmojiCatalog {
    typealias CategorizedEmojis = [String: [MissCatEmojiArchive.EmojiModel]]

    private static var catalogs: [MissCatEmojiCatalog] = []

    static func prepare(for owner: SecureUser) {
        guard catalog(for: owner) == nil,
              let misskey = MisskeyKit(from: owner)
        else { return }
        catalogs.append(MissCatEmojiCatalog(misskey: misskey, owner: owner))
    }

    static func catalog(for owner: SecureUser) -> MissCatEmojiCatalog? {
        catalogs.first { $0.owner.normalizedInstance == owner.normalizedInstance }
    }

    private(set) var categorizedDefaultEmojis: CategorizedEmojis = [:]
    private(set) var categorizedCustomEmojis: CategorizedEmojis = [:]

    private let owner: SecureUser

    private init(misskey: MisskeyKit, owner: SecureUser) {
        self.owner = owner
        misskey.emojis.getDefault { [weak self] emojis in
            self?.categorizedDefaultEmojis = Self.categorizeDefaults(emojis ?? [])
        }
        misskey.emojis.getCustom { [weak self] emojis in
            self?.categorizedCustomEmojis = Self.categorizeCustom(emojis ?? [])
        }
    }

    private static func categorizeDefaults(
        _ emojis: [DefaultEmojiModel]
    ) -> CategorizedEmojis {
        emojis.reduce(into: CategorizedEmojis()) { result, emoji in
            guard let raw = emoji.name, let character = emoji.char else { return }
            let category = emoji.category?.rawValue.nonEmpty ?? "Others"
            result[category, default: []].append(
                MissCatEmojiArchive.EmojiModel(
                    rawEmoji: raw,
                    isDefault: true,
                    defaultEmoji: character,
                    customEmojiUrl: nil
                )
            )
        }
    }

    private static func categorizeCustom(
        _ emojis: [EmojiModel]
    ) -> CategorizedEmojis {
        emojis.reduce(into: CategorizedEmojis()) { result, emoji in
            guard let raw = emoji.name, let url = emoji.url else { return }
            let category = emoji.category?.nonEmpty ?? "Others"
            result[category, default: []].append(
                MissCatEmojiArchive.EmojiModel(
                    rawEmoji: raw,
                    isDefault: false,
                    defaultEmoji: nil,
                    customEmojiUrl: url
                )
            )
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
