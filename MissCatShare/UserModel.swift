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

    private static let appGroup = "group.yuwd.MissCat"
    private static let keychainService = "yuwd.MissCat"
    private static var keychainAccessGroup: String {
        guard let accessGroup = Bundle.main.object(forInfoDictionaryKey: "MissCatKeychainAccessGroup") as? String,
              !accessGroup.isEmpty else { fatalError("Missing shared Keychain access group") }
        return accessGroup
    }
    
    private lazy var userDefaults = Foundation.UserDefaults(suiteName: Self.appGroup)!
    private lazy var keychain = Keychain(service: Self.keychainService,
                                         accessGroup: Self.keychainAccessGroup)
    
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

        var availableUsers: [SecureUser] = []
        var availableMetadata: [SecureUser] = []

        do {
            for user in users {
                var apiKey = try keychain.get(user.userId)
                if apiKey == nil, let legacyAPIKey = user.apiKey {
                    try keychain.set(legacyAPIKey, key: user.userId)
                    guard try keychain.get(user.userId) == legacyAPIKey else {
                        throw AccountPersistenceError.keychainVerificationFailed
                    }
                    apiKey = legacyAPIKey
                }

                guard let resolvedAPIKey = apiKey else { continue }
                availableUsers.append(SecureUser(userId: user.userId,
                                                 username: user.username,
                                                 instance: user.instance,
                                                 apiKey: resolvedAPIKey))
                availableMetadata.append(user)
            }
        } catch {
            if let metadata = encodeMetadata(users) {
                userDefaults.set(metadata, forKey: savedUserKey)
            }
            return []
        }

        if let metadata = encodeMetadata(availableMetadata) {
            userDefaults.set(metadata, forKey: savedUserKey)
        }
        repairCurrentUserId(availableUsers: availableUsers)
        return availableUsers
    }
    
    /// 現在ログイン中のユーザーデータを取得する
    func getCurrentUser() -> SecureUser? {
        let savedUsers = getUsers()
        repairCurrentUserId(availableUsers: savedUsers)
        guard let currentUserId = getCurrentUserId() else { return nil }
        return savedUsers.first(where: { $0.userId == currentUserId })
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

    private enum AccountPersistenceError: Error {
        case keychainVerificationFailed
    }

    private func encodeMetadata(_ users: [SecureUser]) -> Data? {
        let metadata = users.map {
            SecureUser(userId: $0.userId,
                       username: $0.username,
                       instance: $0.instance,
                       apiKey: nil)
        }
        return try? JSONEncoder().encode(metadata)
    }

    private func repairCurrentUserId(availableUsers: [SecureUser]) {
        let availableUserIds = availableUsers.map { $0.userId }
        if let currentUserId = getCurrentUserId(), availableUserIds.contains(currentUserId) {
            return
        }

        if let replacementUserId = availableUserIds.first {
            userDefaults.set(replacementUserId, forKey: currentUserIdKey)
        } else {
            userDefaults.removeObject(forKey: currentUserIdKey)
        }
    }
    
    // MARK: Visiblity
    
    func getCurrentVisibility() -> Visibility? {
        guard let raw = userDefaults.string(forKey: currentVisibilityKey) else { return nil }
        return Visibility(rawValue: raw)
    }
}
