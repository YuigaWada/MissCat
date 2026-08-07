//
//  MissCatEmojiArchive.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/18.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import Foundation

struct EmojiArchiveStorage {
    let data: (_ key: String) -> Data?
    let version: (_ key: String) -> Int?
    let setData: (_ data: Data?, _ key: String) -> Void
    let setVersion: (_ version: Int?, _ key: String) -> Void
    let keys: () -> [String]

    static var standard: EmojiArchiveStorage {
        EmojiArchiveStorage(
            data: { UserDefaults.standard.data(forKey: $0) },
            version: { UserDefaults.standard.object(forKey: $0) as? Int },
            setData: { data, key in
                if let data {
                    UserDefaults.standard.set(data, forKey: key)
                } else {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            },
            setVersion: { version, key in
                if let version {
                    UserDefaults.standard.set(version, forKey: key)
                } else {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            },
            keys: { Array(UserDefaults.standard.dictionaryRepresentation().keys) }
        )
    }
}

/// Foundation-only persistence for reaction favorites/history. The Objective-C
/// archive class name remains `EmojiModel`, preserving previously saved data.
enum MissCatEmojiArchive {
    enum EmojiType: String {
        case favs
        case history
    }

    @objc(EmojiModel) class EmojiModel: NSObject, NSSecureCoding {
        class var supportsSecureCoding: Bool { true }

        enum PersistenceError: Error {
            case writeOrReadbackFailed
            case rollbackFailed
        }

        let rawEmoji: String
        let isDefault: Bool
        let defaultEmoji: String?
        let customEmojiUrl: String?

        var isFake: Bool = false

        init(rawEmoji: String, isDefault: Bool, defaultEmoji: String?, customEmojiUrl: String?, isFake: Bool = false) {
            self.rawEmoji = rawEmoji
            self.isDefault = isDefault
            self.defaultEmoji = defaultEmoji
            self.customEmojiUrl = customEmojiUrl
            self.isFake = isFake
        }

        // MARK: UserDefaults Init

        required init?(coder aDecoder: NSCoder) {
            rawEmoji = aDecoder.decodeObject(of: NSString.self, forKey: "rawEmoji") as String? ?? ""
            isDefault = aDecoder.decodeBool(forKey: "isDefault")
            defaultEmoji = aDecoder.decodeObject(of: NSString.self, forKey: "defaultEmoji") as String?
            customEmojiUrl = aDecoder.decodeObject(of: NSString.self, forKey: "customEmojiUrl") as String?
        }

        func encode(with aCoder: NSCoder) {
            aCoder.encode(rawEmoji, forKey: "rawEmoji")
            aCoder.encode(isDefault, forKey: "isDefault")
            aCoder.encode(defaultEmoji, forKey: "defaultEmoji")
            aCoder.encode(customEmojiUrl, forKey: "customEmojiUrl")
        }

        // MARK: GET/SET

        static func getEmojis(type: EmojiType, owner: SecureUser) -> [EmojiModel]? {
            getEmojis(type: type, owner: owner, storage: .standard)
        }

        static func getEmojis(
            type: EmojiType,
            owner: SecureUser,
            storage: EmojiArchiveStorage
        ) -> [EmojiModel]? {
            migrateLegacyKeyIfNeeded(type: type, owner: owner, storage: storage)
            let key = getKey(type: type, owner: owner)
            guard let array = storage.data(key) else { return nil }
            guard let decoded = decodeStoredEmojis(array) else {
                // Corrupt archives must not crash every subsequent picker launch.
                storage.setData(nil, key)
                storage.setVersion(nil, storageVersionKey(key))
                return nil
            }
            let sanitized = sanitize(decoded, type: type)
            if storage.version(storageVersionKey(key)) != 2 || !archiveFieldsEqual(sanitized, decoded) {
                guard let migrated = try? saveEmojisChecked(
                    with: sanitized,
                    type: type,
                    owner: owner,
                    storage: storage
                ) else { return nil }
                return migrated
            }
            return sanitized
        }

        static func saveEmojis(with target: [EmojiModel], type: EmojiType, owner: SecureUser) {
            _ = try? saveEmojisChecked(with: target, type: type, owner: owner, storage: .standard)
        }

        @discardableResult
        static func saveEmojisChecked(
            with target: [EmojiModel],
            type: EmojiType,
            owner: SecureUser,
            storage: EmojiArchiveStorage = .standard
        ) throws -> [EmojiModel] {
            let key = getKey(type: type, owner: owner)
            let sanitized = sanitize(target, type: type)
            guard archiveFieldsEqual(sanitized, target) else {
                throw PersistenceError.writeOrReadbackFailed
            }
            let targetRawData = try archiveEmojis(sanitized)
            let versionKey = storageVersionKey(key)
            let oldData = storage.data(key)
            let oldVersion = storage.version(versionKey)

            storage.setData(targetRawData, key)
            storage.setVersion(2, versionKey)
            if let readbackData = storage.data(key),
               storage.version(versionKey) == 2,
               let readback = decodeStoredEmojis(readbackData),
               archiveFieldsEqual(readback, sanitized)
            {
                return readback
            }

            storage.setData(oldData, key)
            storage.setVersion(oldVersion, versionKey)
            guard storage.data(key) == oldData,
                  storage.version(versionKey) == oldVersion
            else {
                throw PersistenceError.rollbackFailed
            }
            throw PersistenceError.writeOrReadbackFailed
        }

        static func checkHavingEmojis(type: EmojiType, owner: SecureUser) -> Bool {
            migrateLegacyKeyIfNeeded(type: type, owner: owner, storage: .standard)
            let key = getKey(type: type, owner: owner)
            return UserDefaults.standard.object(forKey: key) != nil
        }

        static func getKey(type: EmojiType, owner: SecureUser) -> String {
            let instance = canonicalInstanceIdentifier(owner.instance) ?? owner.instance
            return "\(type.rawValue)-\(instance)" // 絵文字情報はインスタンスごとに管理する
        }

        static func archiveEmojis(_ target: [EmojiModel]) throws -> Data {
            try NSKeyedArchiver.archivedData(withRootObject: target, requiringSecureCoding: true)
        }

        static func decodeStoredEmojis(_ data: Data) -> [EmojiModel]? {
            guard hasExactArchiveClassGraph(data) else { return nil }
            let allowed: [AnyClass] = [NSArray.self, EmojiModel.self, NSString.self, NSNumber.self]
            if let secure = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: allowed, from: data) as? [EmojiModel] {
                return secure
            }

            // One read of the pre-2026 non-secure archive is supported so existing
            // favorites/history can be migrated immediately to the secure v2 archive.
            guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
            unarchiver.requiresSecureCoding = false
            unarchiver.decodingFailurePolicy = .setErrorAndReturn
            defer { unarchiver.finishDecoding() }
            return unarchiver.decodeObject(
                of: allowed,
                forKey: NSKeyedArchiveRootObjectKey
            ) as? [EmojiModel]
        }

        /// Foundation's allowed-class APIs accept subclasses of an allowed base
        /// class. Validate the keyed-archive class table before instantiation so
        /// only the exact archive graph emitted for `[EmojiModel]` is accepted.
        static func hasExactArchiveClassGraph(_ data: Data) -> Bool {
            guard let propertyList = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ),
            let archive = propertyList as? [String: Any],
            archive["$archiver"] as? String == "NSKeyedArchiver",
            (archive["$version"] as? NSNumber)?.intValue == 100_000,
            archive["$top"] as? [String: Any] != nil,
            let objects = archive["$objects"] as? [Any]
            else { return false }

            let exactClasses: [String: [String]] = [
                "NSArray": ["NSArray", "NSObject"],
                "EmojiModel": ["EmojiModel", "NSObject"]
            ]
            var sawArrayClass = false

            for case let record as [String: Any] in objects {
                let className = record["$classname"] as? String
                let classes = record["$classes"] as? [String]
                guard className != nil || classes != nil else { continue }
                guard let className,
                      let classes,
                      exactClasses[className] == classes
                else { return false }
                sawArrayClass = sawArrayClass || className == "NSArray"
            }

            return sawArrayClass
        }

        static func archiveFieldsEqual(_ lhs: [EmojiModel], _ rhs: [EmojiModel]) -> Bool {
            guard lhs.count == rhs.count else { return false }
            return zip(lhs, rhs).allSatisfy { left, right in
                left.rawEmoji == right.rawEmoji
                    && left.isDefault == right.isDefault
                    && left.defaultEmoji == right.defaultEmoji
                    && left.customEmojiUrl == right.customEmojiUrl
            }
        }

        private static func sanitize(_ target: [EmojiModel], type: EmojiType) -> [EmojiModel] {
            var seen: Set<String> = []
            let valid = target.filter { model in
                guard !model.isFake, !model.rawEmoji.isEmpty else { return false }
                if !model.isDefault {
                    guard let rawURL = model.customEmojiUrl,
                          let url = URL(string: rawURL),
                          ["http", "https"].contains(url.scheme?.lowercased() ?? "")
                    else { return false }
                }
                return seen.insert("\(model.rawEmoji)|\(model.customEmojiUrl ?? "")").inserted
            }
            return type == .history ? Array(valid.prefix(14)) : valid
        }

        private static func storageVersionKey(_ key: String) -> String {
            "\(key).secure-archive-version"
        }

        private static func canonicalInstanceIdentifier(_ rawValue: String) -> String? {
            let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let httpsValue: String
            if trimmed.lowercased().hasPrefix("http://") {
                httpsValue = "https://" + trimmed.dropFirst("http://".count)
            } else {
                httpsValue = trimmed
            }
            return try? MissCatInstance.normalize(httpsValue).identifier
        }

        /// Older releases keyed archives with the instance string exactly as entered.
        /// Scan only the fav/history key namespaces, normalize the suffix, and move one
        /// matching archive to the canonical instance key. Account identifiers and API
        /// keys are deliberately not included in either the lookup or destination key.
        private static func migrateLegacyKeyIfNeeded(
            type: EmojiType,
            owner: SecureUser,
            storage: EmojiArchiveStorage
        ) {
            let canonicalKey = getKey(type: type, owner: owner)
            guard storage.data(canonicalKey) == nil,
                  let canonicalInstance = canonicalInstanceIdentifier(owner.instance)
            else { return }

            let prefix = "\(type.rawValue)-"
            let versionSuffix = ".secure-archive-version"
            let exactLegacyKey = prefix + owner.instance
            let candidates = storage.keys().filter { key in
                guard key.hasPrefix(prefix),
                      !key.hasSuffix(versionSuffix),
                      key != canonicalKey,
                      storage.data(key) != nil
                else { return false }
                let instance = String(key.dropFirst(prefix.count))
                return canonicalInstanceIdentifier(instance) == canonicalInstance
            }.sorted { left, right in
                if left == exactLegacyKey { return true }
                if right == exactLegacyKey { return false }
                return left < right
            }

            for legacyKey in candidates {
                guard let data = storage.data(legacyKey),
                      let decoded = decodeStoredEmojis(data)
                else { continue }
                let sanitized = sanitize(decoded, type: type)
                guard let migrated = try? saveEmojisChecked(
                    with: sanitized,
                    type: type,
                    owner: owner,
                    storage: storage
                ), archiveFieldsEqual(migrated, sanitized)
                else { return }
                storage.setData(nil, legacyKey)
                storage.setVersion(nil, storageVersionKey(legacyKey))
                return
            }
        }
    }
}
