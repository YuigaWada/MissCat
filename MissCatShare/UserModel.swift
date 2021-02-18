//
//  UserModel.swift
//  MissCatShare
//
//  Created by Yuiga Wada on 2020/08/07.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import KeychainAccess
import MisskeyKit

class SecureUser: Codable {
    let userId: String
    let instance: String
    let username: String
    var apiKey: String?
    
    init(userId: String, username: String, instance: String, apiKey: String?) {
        self.userId = userId
        self.username = username
        self.instance = instance
        self.apiKey = apiKey
    }
}

class UserModel {
    // MARK: Stores
    
    private lazy var userDefaults = Foundation.UserDefaults(suiteName: "group.yuwd.MissCat")!
    private lazy var keychain = Keychain(service: "yuwd.MissCat", accessGroup: "group.yuwd.MissCat")
    
    // MARK: Keys
    
    private let savedUserKey = "saved-user"
    private let currentUserIdKey = "current-user-id"
    private let currentVisibilityKey = "current-visibility"
    
    // MARK: User Itself
    
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
    
    /// 現在ログイン中のユーザーデータを取得する
    func getCurrentUser() -> SecureUser? {
        // currentUserIdを持つアカウントを探す
        guard let currentUserId = getCurrentUserId(), let currentUser = getUser(userId: currentUserId) else {
            let savedUser = getUsers()
            return savedUser.count > 0 ? savedUser[0] : nil
        }
        
        return currentUser
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
    
    /// 現在ログイン中のユーザーのuserIdを取得する
    func getCurrentUserId() -> String? {
        return userDefaults.string(forKey: currentUserIdKey)
    }
    
    // MARK: Visiblity
    
    func getCurrentVisibility() -> Visibility? {
        guard let raw = userDefaults.string(forKey: currentVisibilityKey) else { return nil }
        return Visibility(rawValue: raw)
    }
}
