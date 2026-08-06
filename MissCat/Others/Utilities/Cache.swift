//
//  Cache.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/23.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import Foundation
import KeychainAccess
import MisskeyKit
import SwiftLinkPreview
import UIKit

typealias Attachments = [NSTextAttachment: YanagiText.Attachment]

protocol AccountAPIKeyStoring {
    func apiKey(for accountID: String) throws -> String?
    func setAPIKey(_ apiKey: String, for accountID: String) throws
    func removeAPIKey(for accountID: String) throws
    func allAccountIDs() throws -> [String]
}

private struct KeychainAccountAPIKeyStore: AccountAPIKeyStoring {
    private let keychain: Keychain

    init(keychain: Keychain) {
        self.keychain = keychain
    }

    func apiKey(for accountID: String) throws -> String? {
        return try keychain.get(accountID)
    }

    func setAPIKey(_ apiKey: String, for accountID: String) throws {
        try keychain.set(apiKey, key: accountID)
    }

    func removeAPIKey(for accountID: String) throws {
        try keychain.remove(accountID)
    }

    func allAccountIDs() throws -> [String] {
        keychain.allKeys()
    }
}

/// Copies the legacy, app-only Keychain into the shared access group. Every
/// entry is read, copied, and read back independently. A failed or corrupt
/// entry leaves the completion marker absent, so the next launch resumes and
/// verifies already copied entries instead of silently declaring success.
struct AccountKeychainMigrator {
    static let completionMarker = "DidMigrateToAppGroups-v2"

    @discardableResult
    func migrate(from oldStore: AccountAPIKeyStoring, to newStore: AccountAPIKeyStoring) -> Bool {
        do {
            if try newStore.apiKey(for: Self.completionMarker) == "true" {
                return true
            }

            let accountIDs = try oldStore.allAccountIDs()
                .filter { $0 != Self.completionMarker && $0 != "DidMigrateToAppGroups" }
                .sorted()
            for accountID in accountIDs {
                guard let value = try oldStore.apiKey(for: accountID) else {
                    throw MigrationError.missingSourceEntry
                }
                if try newStore.apiKey(for: accountID) != value {
                    try newStore.setAPIKey(value, for: accountID)
                }
                guard try newStore.apiKey(for: accountID) == value else {
                    throw MigrationError.verificationFailed
                }
            }

            // Re-verify all copied entries before writing the marker. This also
            // protects a resumed migration whose earlier destination data was
            // changed between launches.
            for accountID in accountIDs {
                guard let source = try oldStore.apiKey(for: accountID),
                      try newStore.apiKey(for: accountID) == source
                else { throw MigrationError.verificationFailed }
            }

            try newStore.setAPIKey("true", for: Self.completionMarker)
            guard try newStore.apiKey(for: Self.completionMarker) == "true" else {
                throw MigrationError.verificationFailed
            }
            return true
        } catch {
            return false
        }
    }

    private enum MigrationError: Error {
        case missingSourceEntry
        case verificationFailed
    }
}

class Cache {
    struct UserInfo {
        let user: SecureUser
        let name: String
        let username: String
        let host: String
        let image: UIImage
    }
    
    // MARK: Singleton
    
    static var shared: Cache = .init()
    
    // MARK: Var
    
    private let iconCache = NSCache<NSString, UIImage>()
    private let imageCache = NSCache<NSString, UIImage>()
    private let dataCache = NSCache<NSString, NSData>()
    private let urlPreviewCache = NSCache<NSString, UrlSummalyEntity>()

    private var userInfo: [UserInfo] = []
    
    private var me: UserEntity?
    
    private lazy var applicationSupportDir = CreateApplicationSupportDir()
    
    // MARK: Reset
    
    func resetMyCache() {
        me = nil
    }
    
    // MARK: Save
    
    func saveIcon(username: String, image: UIImage) {
        iconCache.setObject(image, forKey: NSString(string: username))
    }
    
    func saveUiImage(_ image: UIImage, url: String) {
        imageCache.setObject(image, forKey: NSString(string: url))
    }
    
    func saveUrlData(_ data: Data, on rawUrl: String, toStorage: Bool = false) {
        dataCache.setObject(NSData(data: data), forKey: NSString(string: rawUrl))
        if toStorage {
            saveToStorage(data: data, url: rawUrl)
        }
    }
    
    func saveUrlPreview(_ response: UrlSummalyEntity, on rawUrl: String) {
        urlPreviewCache.setObject(response, forKey: NSString(string: rawUrl))
    }
    
    func saveUserInfo(info: UserInfo) {
        userInfo.append(info)
    }
    
    // MARK: Get
    
    func getIcon(username: String) -> UIImage? {
        return iconCache.object(forKey: NSString(string: username))
    }
    
    func getUiImage(url: String) -> UIImage? {
        return imageCache.object(forKey: NSString(string: url))
    }
    
    func getUrlData(on rawUrl: String) -> Data? {
        if let data = dataCache.object(forKey: NSString(string: rawUrl)) {
            return Data(referencing: data)
        }
        if let savedOnStorage = getFromStorage(url: rawUrl) {
            saveUrlData(savedOnStorage, on: rawUrl) // RAM上に載せる
            return savedOnStorage
        }
        return nil
    }
    
    func getUrlPreview(on rawUrl: String) -> UrlSummalyEntity? {
        return urlPreviewCache.object(forKey: NSString(string: rawUrl))
    }
    
    func getUserInfo(user: SecureUser) -> UserInfo? {
        let info = userInfo.filter { $0.user.accountIdentifier == user.accountIdentifier }
        return info.count > 0 ? info[0] : nil
    }
    
    /// データをハッシュを利用して保存する
    /// - Parameters:
    ///   - data: Data
    ///   - url: Url
    private func saveToStorage(data: Data, url: String) {
        let filename = url.sha256() ?? url
        
        let path = applicationSupportDir.appendingPathComponent(filename)
        do {
            try data.write(to: path)
        } catch {
            /* Ignore */
            print(error)
        }
    }
    
    /// データをハッシュを利用して保存する
    /// - Parameter url: url
    private func getFromStorage(url: String) -> Data? {
        let filename = url.sha256() ?? url
        
        let path = applicationSupportDir.appendingPathComponent(filename)
        do {
            return try Data(contentsOf: path)
        } catch {
            return nil
        }
    }
    
    private func CreateApplicationSupportDir() -> URL {
        let manager = FileManager.default
        let applicationSupportDir = manager.urls(for: .applicationSupportDirectory,
                                                 in: .userDomainMask)[0]
        
        // デフォルトではsandbox内にApplication Supportが存在しないので、ディレクトリを作る必要がある
        if !manager.fileExists(atPath: applicationSupportDir.absoluteString) {
            do {
                try manager.createDirectory(at: applicationSupportDir,
                                            withIntermediateDirectories: false,
                                            attributes: nil)
            } catch {
                /* Ignore */
            }
        }
        
        return applicationSupportDir
    }
}

extension Cache {
    class UserDefaults {
        static var shared: Cache.UserDefaults = .init()

        private static let appGroup = "group.yuwd.MissCat"
        private static let keychainService = "yuwd.MissCat"
        private static var keychainAccessGroup: String {
            guard let accessGroup = Bundle.main.object(forInfoDictionaryKey: "MissCatKeychainAccessGroup") as? String,
                  !accessGroup.isEmpty else { fatalError("Missing shared Keychain access group") }
            return accessGroup
        }

        private let injectedUserDefaults: Foundation.UserDefaults?
        private let injectedAPIKeyStore: AccountAPIKeyStoring?

        init(userDefaults: Foundation.UserDefaults? = nil,
             apiKeyStore: AccountAPIKeyStoring? = nil) {
            injectedUserDefaults = userDefaults
            injectedAPIKeyStore = apiKeyStore
        }
        
        // MARK: Stores
        
        // ShareExtensionとUserDefaults情報を共有するためappGroupsのUserDefaultsを用いる
        private lazy var userDefaults: Foundation.UserDefaults = {
            if let injectedUserDefaults = injectedUserDefaults {
                return injectedUserDefaults
            }
            guard let userDefaults = Foundation.UserDefaults(suiteName: Self.appGroup) else { fatalError() }
            migrateUserDefaultsToAppGroups(userDefaults)
            return userDefaults
        }()
        
        private lazy var apiKeyStore: AccountAPIKeyStoring = { // indexをuseridとして、valueをapiKeyとする
            if let injectedAPIKeyStore = injectedAPIKeyStore {
                return injectedAPIKeyStore
            }
            let keychain = Keychain(service: Self.keychainService,
                                    accessGroup: Self.keychainAccessGroup)
            let sharedStore = KeychainAccountAPIKeyStore(keychain: keychain)
            migrateKeyChainToAppGroups(sharedStore)
            return sharedStore
        }()
        
        // MARK: Keys
        
        private let latestNotificationKey = "latest-notification"
        
        private let savedUserKey = "saved-user"
        private let currentUserIdKey = "current-user-id"
        private let currentVisibilityKey = "current-visibility"
        
        // MARK: Notification
        
        func getLatestNotificationId() -> String? {
            return userDefaults.string(forKey: latestNotificationKey)
        }
        
        func setLatestNotificationId(_ id: String) {
            userDefaults.set(id, forKey: latestNotificationKey)
        }
        
        // MARK: User
        
        @discardableResult
        func removeUser(userId identifier: String) -> Bool {
            do {
                let users = try getUsersThrowing()
                guard let target = resolveUser(identifier: identifier, in: users) else { return false }
                let savedUsers = users.filter { $0.accountIdentifier != target.accountIdentifier }
                let usersData = try encodeMetadata(savedUsers)
                try apiKeyStore.removeAPIKey(for: target.accountIdentifier)
                userDefaults.set(usersData, forKey: savedUserKey)
                repairCurrentUserId(availableUsers: savedUsers)
                return true
            } catch {
                return false
            }
        }
        
        /// ユーザーを保存する
        func saveUser(_ user: SecureUser) -> Bool {
            if persist(user, makeCurrent: false) != nil {
                user.apiKey = nil // Preserve the existing caller contract after secure persistence succeeds.
                return true
            }
            return false
        }

        /// Atomically installs a freshly authenticated account and selects it.
        /// The Keychain value, metadata, and current selection are restored to
        /// their exact pre-call values if any final read-back check fails.
        func installAuthenticatedUser(_ user: SecureUser) -> SecureUser? {
            persist(user, makeCurrent: true)
        }
        
        /// 保存されている全てのユーザー情報を取得する
        func getUsers() -> [SecureUser] {
            return (try? getUsersThrowing()) ?? []
        }

        func getUsersThrowing() throws -> [SecureUser] {
            guard let data = userDefaults.data(forKey: savedUserKey),
                  !data.isEmpty else {
                repairCurrentUserId(availableUsers: [])
                return []
            }

            let decodedUsers = try JSONDecoder().decode([SecureUser].self, from: data)
            let storedUsers = deduplicatedMetadata(decodedUsers)
            let legacyUserIDCounts = Dictionary(grouping: storedUsers, by: \.userId)
                .mapValues(\.count)
            var availableUsers: [SecureUser] = []
            var availableMetadata: [SecureUser] = []

            do {
                for storedUser in storedUsers {
                    let accountID = storedUser.accountIdentifier
                    var apiKey = try apiKeyStore.apiKey(for: accountID)

                    // v1 keyed credentials by userId only. That key is safe to
                    // adopt only when metadata has one account with that userId;
                    // otherwise it cannot be attributed to an instance without
                    // risking credential crossover.
                    if apiKey == nil,
                       legacyUserIDCounts[storedUser.userId] == 1,
                       let legacyAPIKey = try apiKeyStore.apiKey(for: storedUser.userId)
                    {
                        try apiKeyStore.setAPIKey(legacyAPIKey, for: accountID)
                        guard try apiKeyStore.apiKey(for: accountID) == legacyAPIKey else {
                            throw AccountPersistenceError.keychainVerificationFailed
                        }
                        apiKey = legacyAPIKey
                    }

                    // Older builds accidentally wrote the API key into the shared JSON.
                    // Move it into the shared Keychain before the JSON is scrubbed.
                    if apiKey == nil, let legacyAPIKey = storedUser.apiKey {
                        try apiKeyStore.setAPIKey(legacyAPIKey, for: accountID)
                        guard try apiKeyStore.apiKey(for: accountID) == legacyAPIKey else {
                            throw AccountPersistenceError.keychainVerificationFailed
                        }
                        apiKey = legacyAPIKey
                    }

                    guard let resolvedAPIKey = apiKey else { continue }
                    availableUsers.append(SecureUser(userId: storedUser.userId,
                                                     username: storedUser.username,
                                                     instance: storedUser.normalizedInstance,
                                                     apiKey: resolvedAPIKey))
                    availableMetadata.append(SecureUser(userId: storedUser.userId,
                                                        username: storedUser.username,
                                                        instance: storedUser.normalizedInstance,
                                                        apiKey: nil))
                }
            } catch {
                // Even when Keychain access fails, remove any legacy plaintext key.
                userDefaults.set(try encodeMetadata(storedUsers), forKey: savedUserKey)
                throw error
            }

            userDefaults.set(try encodeMetadata(availableMetadata), forKey: savedUserKey)
            repairCurrentUserId(availableUsers: availableUsers)
            return availableUsers
        }
        
        /// 指定されたuserIdのユーザーを取得する
        func getUser(userId identifier: String) -> SecureUser? {
            resolveUser(identifier: identifier, in: getUsers())
        }
        
        /// 現在ログイン中のユーザー情報を変更する
        @discardableResult
        func changeCurrentUser(userId id: String) -> Bool {
            guard let user = resolveUser(identifier: id, in: getUsers()) else { return false }
            return persistCurrentSelection(user.accountIdentifier)
        }

        @discardableResult
        func changeCurrentUser(_ user: SecureUser) -> Bool {
            guard getUsers().contains(where: { $0.accountIdentifier == user.accountIdentifier }) else {
                return false
            }
            return persistCurrentSelection(user.accountIdentifier)
        }
        
        /// 現在ログイン中のユーザーのuserIdを取得する
        func getCurrentUserId() -> String? {
            return userDefaults.string(forKey: currentUserIdKey)
        }
        
        /// 現在ログイン中のユーザーデータを取得する
        func getCurrentUser() -> SecureUser? {
            userRefill()

            guard let savedUsers = try? getUsersThrowing() else { return nil }
            guard let currentUserId = getCurrentUserId(),
                  let currentUser = resolveUser(identifier: currentUserId, in: savedUsers) else { return nil }
            
            usernameRefill(with: currentUser)
            return currentUser
        }

        private enum AccountPersistenceError: Error {
            case keychainVerificationFailed
            case finalVerificationFailed
        }

        private func encodeMetadata(_ users: [SecureUser]) throws -> Data {
            let metadata = users.map {
                SecureUser(userId: $0.userId,
                           username: $0.username,
                           instance: $0.normalizedInstance,
                           apiKey: nil)
            }
            return try JSONEncoder().encode(metadata)
        }

        private func repairCurrentUserId(availableUsers: [SecureUser]) {
            if let currentUserId = getCurrentUserId(),
               let resolved = resolveUser(identifier: currentUserId, in: availableUsers)
            {
                if currentUserId != resolved.accountIdentifier {
                    userDefaults.set(resolved.accountIdentifier, forKey: currentUserIdKey)
                }
                return
            }

            if let replacement = availableUsers.first {
                userDefaults.set(replacement.accountIdentifier, forKey: currentUserIdKey)
            } else {
                userDefaults.removeObject(forKey: currentUserIdKey)
            }
        }

        private func persist(_ user: SecureUser, makeCurrent: Bool) -> SecureUser? {
            guard let apiKey = user.apiKey, !apiKey.isEmpty else { return nil }

            let normalizedUser = SecureUser(userId: user.userId,
                                            username: user.username,
                                            instance: user.normalizedInstance,
                                            apiKey: apiKey)
            let accountID = normalizedUser.accountIdentifier
            let previousMetadata = userDefaults.object(forKey: savedUserKey)
            let previousCurrent = userDefaults.object(forKey: currentUserIdKey)
            var previousAPIKey: String?
            var didReadPreviousAPIKey = false

            do {
                previousAPIKey = try apiKeyStore.apiKey(for: accountID)
                didReadPreviousAPIKey = true
                let savedUsers = try getUsersThrowing()
                let newUsers: [SecureUser]
                if savedUsers.contains(where: { $0.accountIdentifier == accountID }) {
                    newUsers = savedUsers.map { $0.accountIdentifier == accountID ? normalizedUser : $0 }
                } else {
                    newUsers = savedUsers + [normalizedUser]
                }

                let usersData = try encodeMetadata(newUsers)
                try apiKeyStore.setAPIKey(apiKey, for: accountID)
                guard try apiKeyStore.apiKey(for: accountID) == apiKey else {
                    throw AccountPersistenceError.keychainVerificationFailed
                }

                userDefaults.set(usersData, forKey: savedUserKey)
                if makeCurrent {
                    userDefaults.set(accountID, forKey: currentUserIdKey)
                }

                guard metadataContains(accountID: accountID, in: userDefaults.data(forKey: savedUserKey)),
                      try apiKeyStore.apiKey(for: accountID) == apiKey,
                      !makeCurrent || userDefaults.string(forKey: currentUserIdKey) == accountID
                else { throw AccountPersistenceError.finalVerificationFailed }

                return SecureUser(userId: normalizedUser.userId,
                                  username: normalizedUser.username,
                                  instance: normalizedUser.instance,
                                  apiKey: apiKey)
            } catch {
                restore(previousMetadata, forKey: savedUserKey)
                restore(previousCurrent, forKey: currentUserIdKey)
                do {
                    guard didReadPreviousAPIKey else { return nil }
                    if let previousAPIKey {
                        try apiKeyStore.setAPIKey(previousAPIKey, for: accountID)
                    } else {
                        try apiKeyStore.removeAPIKey(for: accountID)
                    }
                } catch {
                    // Metadata/current selection have still been rolled back.
                    // A verified orphan Keychain item is never enumerated as an
                    // account and will be overwritten by a later retry.
                }
                return nil
            }
        }

        private func metadataContains(accountID: String, in data: Data?) -> Bool {
            guard let data,
                  let users = try? JSONDecoder().decode([SecureUser].self, from: data)
            else { return false }
            return users.contains { $0.accountIdentifier == accountID && $0.apiKey == nil }
        }

        private func restore(_ value: Any?, forKey key: String) {
            if let value {
                userDefaults.set(value, forKey: key)
            } else {
                userDefaults.removeObject(forKey: key)
            }
        }

        private func deduplicatedMetadata(_ users: [SecureUser]) -> [SecureUser] {
            var seen = Set<String>()
            let deduplicated: [SecureUser] = users.reversed().compactMap { user -> SecureUser? in
                guard seen.insert(user.accountIdentifier).inserted else { return nil }
                return user
            }
            return Array(deduplicated.reversed())
        }

        private func resolveUser(identifier: String, in users: [SecureUser]) -> SecureUser? {
            if let exact = users.first(where: { $0.accountIdentifier == identifier }) {
                return exact
            }

            let matchingLegacyUsers = users.filter { $0.userId == identifier }
            guard matchingLegacyUsers.count > 1 else { return matchingLegacyUsers.first }

            if let current = userDefaults.string(forKey: currentUserIdKey),
               let selected = matchingLegacyUsers.first(where: { $0.accountIdentifier == current })
            {
                return selected
            }
            return matchingLegacyUsers.first
        }

        private func persistCurrentSelection(_ accountID: String) -> Bool {
            let previous = userDefaults.object(forKey: currentUserIdKey)
            userDefaults.set(accountID, forKey: currentUserIdKey)
            guard userDefaults.string(forKey: currentUserIdKey) == accountID else {
                restore(previous, forKey: currentUserIdKey)
                return false
            }
            return true
        }
        
        // MARK: Visibility
        
        func getCurrentVisibility() -> Visibility? {
            guard let raw = userDefaults.string(forKey: currentVisibilityKey) else { return nil }
            return Visibility(rawValue: raw)
        }
        
        func setCurrentVisibility(_ visibility: Visibility) {
            userDefaults.set(visibility.rawValue, forKey: currentVisibilityKey)
        }
        
        // MARK: Migrates
        
        /// ユーザーデータの保持構造が変わったので、v1.1.0以前のバージョンから乗り換えた場合、ユーザーデータを詰め替える
        func userRefill() {
            let currentLoginedApiKey = "current-logined-ApiKey"
            let currentLoginedUserId = "current-logined-UserId"
            let currentLoginedInstance = "current-logined-instance"
            
            guard let apiKey = Foundation.UserDefaults.standard.string(forKey: currentLoginedApiKey),
                  let userId = Foundation.UserDefaults.standard.string(forKey: currentLoginedUserId),
                  let instance = Foundation.UserDefaults.standard.string(forKey: currentLoginedInstance) else { return }
            
            // 詰め替える
            guard saveUser(.init(userId: userId, username: "", instance: instance, apiKey: apiKey)) else { return }
            changeCurrentUser(.init(userId: userId, username: "", instance: instance, apiKey: apiKey))
            
            // UserDefaultsに保存されているデータを削除
            Foundation.UserDefaults.standard.removeObject(forKey: currentLoginedApiKey)
            Foundation.UserDefaults.standard.removeObject(forKey: currentLoginedUserId)
            Foundation.UserDefaults.standard.removeObject(forKey: currentLoginedInstance)
            userDefaults.removeObject(forKey: currentLoginedApiKey)
        }
        
        /// userRefill()で詰めきれなかったusernameを非同期で詰める
        func usernameRefill(with user: SecureUser) {
            guard user.username.isEmpty,
                  let apiKey = user.apiKey else { return }
            let misskey = MisskeyKit(from: user)
            misskey?.users.i { info, _ in
                guard let info = info else { return }
                let secureUser = SecureUser(userId: user.userId, username: info.username ?? "", instance: user.instance, apiKey: apiKey)
                _ = Cache.UserDefaults.shared.saveUser(secureUser)
            }
        }
        
        // Thanks. https://gist.github.com/dougdiego/945fd2e33769cf5f1338
        func migrateUserDefaultsToAppGroups(_ newUserDefaults: Foundation.UserDefaults) {
            // User Defaults - Old
            let userDefaults = Foundation.UserDefaults.standard
            
            // App Groups Default - New
            let groupDefaults = newUserDefaults
            
            // Key to track if we migrated
            let didMigrateToAppGroups = "DidMigrateToAppGroups"
            
            if !groupDefaults.bool(forKey: didMigrateToAppGroups) {
                for key in userDefaults.dictionaryRepresentation().keys {
                    guard key != "current-logined-ApiKey" else { continue }
                    groupDefaults.set(userDefaults.dictionaryRepresentation()[key], forKey: key)
                }
                groupDefaults.removeObject(forKey: "current-logined-ApiKey")
                groupDefaults.set(true, forKey: didMigrateToAppGroups)
                groupDefaults.synchronize()
                print("Successfully migrated defaults")
            } else {
                print("No need to migrate defaults")
            }
        }
        
        func migrateKeyChainToAppGroups(_ newStore: AccountAPIKeyStoring) {
            let oldStore = KeychainAccountAPIKeyStore(
                keychain: Keychain(service: Self.keychainService)
            )
            if !AccountKeychainMigrator().migrate(from: oldStore, to: newStore) {
                // No account IDs or values are logged. The absent marker makes
                // the next initialization retry every unverified entry.
                print("Shared Keychain migration is incomplete and will be retried")
            }
        }
    }
}
