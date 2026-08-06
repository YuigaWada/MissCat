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
    func apiKey(for userId: String) throws -> String?
    func setAPIKey(_ apiKey: String, for userId: String) throws
    func removeAPIKey(for userId: String) throws
}

private struct KeychainAccountAPIKeyStore: AccountAPIKeyStoring {
    private let keychain: Keychain

    init(keychain: Keychain) {
        self.keychain = keychain
    }

    func apiKey(for userId: String) throws -> String? {
        return try keychain.get(userId)
    }

    func setAPIKey(_ apiKey: String, for userId: String) throws {
        try keychain.set(apiKey, key: userId)
    }

    func removeAPIKey(for userId: String) throws {
        try keychain.remove(userId)
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
        let info = userInfo.filter { $0.user.userId == user.userId }
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
        private static let keychainAccessGroup = "4LMTSU8RLS.yuwd.MissCat"

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
            migrateKeyChainToAppGroups(keychain)
            return KeychainAccountAPIKeyStore(keychain: keychain)
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
        func removeUser(userId: String) -> Bool {
            do {
                let savedUsers = try getUsersThrowing().filter { $0.userId != userId }
                let usersData = try encodeMetadata(savedUsers)
                try apiKeyStore.removeAPIKey(for: userId)
                userDefaults.set(usersData, forKey: savedUserKey)
                repairCurrentUserId(availableUsers: savedUsers)
                return true
            } catch {
                return false
            }
        }
        
        /// ユーザーを保存する
        func saveUser(_ user: SecureUser) -> Bool {
            guard let apiKey = user.apiKey else { return false }

            do {
                let savedUsers = try getUsersThrowing()
                let newUsers: [SecureUser]
                if savedUsers.contains(where: { $0.userId == user.userId }) {
                    newUsers = savedUsers.map { $0.userId == user.userId ? user : $0 }
                } else {
                    newUsers = savedUsers + [user]
                }

                // Encode only sanitized metadata before touching the Keychain. This also
                // guarantees that another account's hydrated key cannot enter UserDefaults.
                let usersData = try encodeMetadata(newUsers)
                try apiKeyStore.setAPIKey(apiKey, for: user.userId)
                guard try apiKeyStore.apiKey(for: user.userId) == apiKey else { return false }

                userDefaults.set(usersData, forKey: savedUserKey)
                user.apiKey = nil // Preserve the existing caller contract after secure persistence succeeds.
                return true
            } catch {
                return false
            }
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

            let storedUsers = try JSONDecoder().decode([SecureUser].self, from: data)
            var availableUsers: [SecureUser] = []
            var availableMetadata: [SecureUser] = []

            do {
                for storedUser in storedUsers {
                    var apiKey = try apiKeyStore.apiKey(for: storedUser.userId)

                    // Older builds accidentally wrote the API key into the shared JSON.
                    // Move it into the shared Keychain before the JSON is scrubbed.
                    if apiKey == nil, let legacyAPIKey = storedUser.apiKey {
                        try apiKeyStore.setAPIKey(legacyAPIKey, for: storedUser.userId)
                        guard try apiKeyStore.apiKey(for: storedUser.userId) == legacyAPIKey else {
                            throw AccountPersistenceError.keychainVerificationFailed
                        }
                        apiKey = legacyAPIKey
                    }

                    guard let resolvedAPIKey = apiKey else { continue }
                    availableUsers.append(SecureUser(userId: storedUser.userId,
                                                     username: storedUser.username,
                                                     instance: storedUser.instance,
                                                     apiKey: resolvedAPIKey))
                    availableMetadata.append(storedUser)
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
        func getUser(userId: String) -> SecureUser? {
            var user: SecureUser?
            let savedUser = getUsers()
            savedUser.forEach {
                if userId == $0.userId { user = $0; return }
            }
            
            return user
        }
        
        /// 現在ログイン中のユーザー情報を変更する
        func changeCurrentUser(userId id: String) {
            userDefaults.set(id, forKey: currentUserIdKey)
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
                  let currentUser = savedUsers.first(where: { $0.userId == currentUserId }) else { return nil }
            
            usernameRefill(with: currentUser)
            return currentUser
        }

        private enum AccountPersistenceError: Error {
            case keychainVerificationFailed
        }

        private func encodeMetadata(_ users: [SecureUser]) throws -> Data {
            let metadata = users.map {
                SecureUser(userId: $0.userId,
                           username: $0.username,
                           instance: $0.instance,
                           apiKey: nil)
            }
            return try JSONEncoder().encode(metadata)
        }

        private func repairCurrentUserId(availableUsers: [SecureUser]) {
            let availableUserIds = availableUsers.map { $0.userId }
            if let currentUserId = getCurrentUserId(), availableUserIds.contains(currentUserId) {
                return
            }

            if let replacementUserId = availableUserIds.first {
                changeCurrentUser(userId: replacementUserId)
            } else {
                userDefaults.removeObject(forKey: currentUserIdKey)
            }
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
            changeCurrentUser(userId: userId)
            
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
        
        func migrateKeyChainToAppGroups(_ new: Keychain) {
            let old = Keychain(service: Self.keychainService)
            
            // Key to track if we migrated
            let didMigrateToAppGroups = "DidMigrateToAppGroups"
            
            if !new.allKeys().contains(didMigrateToAppGroups) {
                for key in old.allKeys() {
                    guard let value = try? old.get(key) else { continue }
                    try? new.set(value, key: key)
                }
                try? new.set("true", key: didMigrateToAppGroups)
                print("Successfully migrated defaults")
            } else {
                print("No need to migrate defaults")
            }
        }
    }
}
