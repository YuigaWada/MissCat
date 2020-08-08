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
    
    private var icon: [String: UIImage] = [:] // key: username
    private var uiImage: [String: UIImage] = [:] // key: url
    private var dataOnUrl: [String: Data] = [:] // key: url
    private var urlPreview: [String: UrlSummalyEntity] = [:] // key: url
    
    private var userInfo: [UserInfo] = []
    
    private var me: UserEntity?
    
    private lazy var applicationSupportDir = CreateApplicationSupportDir()
    
    // MARK: Reset
    
    func resetMyCache() {
        me = nil
    }
    
    // MARK: Save
    
    func saveIcon(username: String, image: UIImage) {
        icon[username] = image
    }
    
    func saveUiImage(_ image: UIImage, url: String) {
        uiImage[url] = image
    }
    
    func saveUrlData(_ data: Data, on rawUrl: String, toStorage: Bool = false) {
        dataOnUrl[rawUrl] = data
        if toStorage {
            saveToStorage(data: data, url: rawUrl)
        }
    }
    
    func saveUrlPreview(_ response: UrlSummalyEntity, on rawUrl: String) {
        urlPreview[rawUrl] = response
    }
    
    func saveUserInfo(info: UserInfo) {
        userInfo.append(info)
    }
    
    // MARK: Get
    
    func getIcon(username: String) -> UIImage? {
        return icon[username]
    }
    
    func getUiImage(url: String) -> UIImage? {
        return uiImage[url]
    }
    
    func getUrlData(on rawUrl: String) -> Data? {
        if !dataOnUrl.keys.contains(rawUrl), let savedOnStorage = getFromStorage(url: rawUrl) {
            saveUrlData(savedOnStorage, on: rawUrl) // RAM上に載せる
            return savedOnStorage
        }
        
        return dataOnUrl[rawUrl]
    }
    
    func getUrlPreview(on rawUrl: String) -> UrlSummalyEntity? {
        guard urlPreview.keys.contains(rawUrl) else { return nil }
        return urlPreview[rawUrl]
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
        
        // MARK: Stores
        
        // ShareExtensionとUserDefaults情報を共有するためappGroupsのUserDefaultsを用いる
        private lazy var userDefaults: Foundation.UserDefaults = {
            guard let userDefaults = Foundation.UserDefaults(suiteName: "group.yuwd.MissCat") else { fatalError() }
            migrateUserDefaultsToAppGroups(userDefaults)
            return userDefaults
        }()
        
        private lazy var keychain: Keychain = { // indexをuseridとして、valueをapiKeyとする
            let keychain = Keychain(service: "yuwd.MissCat", accessGroup: "group.yuwd.MissCat")
            migrateKeyChainToAppGroups(keychain)
            return keychain
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
        
        func removeUser(userId: String) {
            let savedUser = getUsers().filter { $0.userId != userId } // 保存済みのユーザー情報からターゲットのみ除外する
            guard let usersData = try? JSONEncoder().encode(savedUser) else { return }
            
            userDefaults.set(usersData, forKey: savedUserKey)
            do { try keychain.remove(userId) }
            catch {}
            
            if let currentUser = getCurrentUser(), userId == currentUser.userId { // メインとしてログインしている場合
                guard savedUser.count > 0 else { return }
                
                let newMainUserId = savedUser[0].userId
                changeCurrentUser(userId: newMainUserId) // メインアカウントを移し替える
            }
        }
        
        /// ユーザーを保存する
        func saveUser(_ user: SecureUser) -> Bool {
            let savedUsers = getUsers()
            var newUsers: [SecureUser]
            if savedUsers.filter({ $0.userId == user.userId }).count > 0 { // アカウントがすでにログインされてたら
                newUsers = savedUsers.map { // アカウント情報をアップデートする
                    guard $0.userId == user.userId else { return $0 }
                    return user
                }
            } else { // 新規のアカウントだったら
                newUsers = savedUsers + [user]
            }
            
            guard let usersData = try? JSONEncoder().encode(newUsers) else { return false }
            
            keychain[user.userId] = user.apiKey // apiKeyはキーチェーンに保存
            user.apiKey = nil // apikeyは隠蔽する
            userDefaults.set(usersData, forKey: savedUserKey) // instance情報とuserIdはそのままUserDefaultsへ
            return true
        }
        
        /// 保存されている全てのユーザー情報を取得する
        func getUsers() -> [SecureUser] {
            guard let data = userDefaults.data(forKey: savedUserKey),
                let users = try? JSONDecoder().decode([SecureUser].self, from: data),
                users.count > 0 else { return [] }
            
            var noApiKeyUserIds: [String] = []
            
            // apikeyをキーチェーンから取り出して詰め替えていく
            let _users: [SecureUser] = users.compactMap {
                guard let apiKey = self.keychain[$0.userId] else { noApiKeyUserIds.append($0.userId); return nil }
                return SecureUser(userId: $0.userId, username: $0.username, instance: $0.instance, apiKey: apiKey)
            }
            
            if noApiKeyUserIds.count > 0 { // apiKeyを持っていないユーザーは削除する
                guard let usersData = try? JSONEncoder().encode(users.filter { !noApiKeyUserIds.contains($0.userId) }) else { return _users }
                userDefaults.set(usersData, forKey: savedUserKey)
            }
            
            return _users
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
            
            // currentUserIdを持つアカウントを探す
            guard let currentUserId = getCurrentUserId(), let currentUser = getUser(userId: currentUserId) else {
                let savedUser = getUsers()
                return savedUser.count > 0 ? savedUser[0] : nil
            }
            
            usernameRefill(with: currentUser)
            return currentUser
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
            _ = saveUser(.init(userId: userId, username: "", instance: instance, apiKey: apiKey))
            changeCurrentUser(userId: userId)
            
            // UserDefaultsに保存されているデータを削除
            Foundation.UserDefaults.standard.removeObject(forKey: currentLoginedApiKey)
            Foundation.UserDefaults.standard.removeObject(forKey: currentLoginedUserId)
            Foundation.UserDefaults.standard.removeObject(forKey: currentLoginedInstance)
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
                    groupDefaults.set(userDefaults.dictionaryRepresentation()[key], forKey: key)
                }
                groupDefaults.set(true, forKey: didMigrateToAppGroups)
                groupDefaults.synchronize()
                print("Successfully migrated defaults")
            } else {
                print("No need to migrate defaults")
            }
        }
        
        func migrateKeyChainToAppGroups(_ new: Keychain) {
            let old = Keychain(service: "yuwd.MissCat")
            
            // Key to track if we migrated
            let didMigrateToAppGroups = "DidMigrateToAppGroups"
            
            if !new.allKeys().contains(didMigrateToAppGroups) {
                for key in old.allKeys() {
                    new[key] = old[key]
                }
                new[didMigrateToAppGroups] = "true"
                print("Successfully migrated defaults")
            } else {
                print("No need to migrate defaults")
            }
        }
    }
}
