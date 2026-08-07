//
//  UserModel.swift
//  MissCatShare
//
//  Created by Yuiga Wada on 2020/08/07.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import Foundation
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

extension SecureUser {
    var accountIdentifier: String {
        MissCatAccountIdentity.storageKey(instance: instance, userId: userId)
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
              let decodedUsers = try? JSONDecoder().decode([SecureUser].self, from: data),
              !decodedUsers.isEmpty else { return [] }
        let users = deduplicatedMetadata(decodedUsers)

        var availableUsers: [SecureUser] = []
        var availableMetadata: [SecureUser] = []
        let legacyUserIDCounts = Dictionary(grouping: users, by: \.userId).mapValues(\.count)

        do {
            for user in users {
                let accountID = user.accountIdentifier
                var apiKey = try keychain.get(accountID)
                if apiKey == nil,
                   legacyUserIDCounts[user.userId] == 1,
                   let legacyAPIKey = try keychain.get(user.userId)
                {
                    try keychain.set(legacyAPIKey, key: accountID)
                    guard try keychain.get(accountID) == legacyAPIKey else {
                        throw AccountPersistenceError.keychainVerificationFailed
                    }
                    apiKey = legacyAPIKey
                }
                if apiKey == nil, let legacyAPIKey = user.apiKey {
                    try keychain.set(legacyAPIKey, key: accountID)
                    guard try keychain.get(accountID) == legacyAPIKey else {
                        throw AccountPersistenceError.keychainVerificationFailed
                    }
                    apiKey = legacyAPIKey
                }

                guard let resolvedAPIKey = apiKey else { continue }
                availableUsers.append(SecureUser(userId: user.userId,
                                                 username: user.username,
                                                 instance: MissCatAccountIdentity.normalizedInstance(user.instance),
                                                 apiKey: resolvedAPIKey))
                availableMetadata.append(SecureUser(
                    userId: user.userId,
                    username: user.username,
                    instance: MissCatAccountIdentity.normalizedInstance(user.instance),
                    apiKey: nil
                ))
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
        return resolveUser(identifier: currentUserId, in: savedUsers)
    }
    
    /// 複合アカウントIDに一致するユーザーを取得する
    func getUser(accountIdentifier: String) -> SecureUser? {
        getUsers().first { $0.accountIdentifier == accountIdentifier }
    }

    /// A credential-free hook for signed-extension verification. Callers can
    /// prove that the extension read the exact composite account's Keychain
    /// entry without receiving, logging, or serializing the token.
    func credentialReadProof(accountIdentifier: String) -> ShareCredentialReadProof {
        let exactUser = getUsers().first { $0.accountIdentifier == accountIdentifier }
        return ShareCredentialReadProof(
            accountIdentifierHash: ShareCredentialReadProof.accountHash(accountIdentifier),
            credentialAvailable: exactUser?.apiKey?.isEmpty == false
        )
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
                       instance: MissCatAccountIdentity.normalizedInstance($0.instance),
                       apiKey: nil)
        }
        return try? JSONEncoder().encode(metadata)
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

    private func deduplicatedMetadata(_ users: [SecureUser]) -> [SecureUser] {
        var seen = Set<String>()
        let deduplicated: [SecureUser] = users.reversed().compactMap { user -> SecureUser? in
            guard seen.insert(user.accountIdentifier).inserted else { return nil }
            return user
        }
        return Array(deduplicated.reversed())
    }

    private func resolveUser(identifier: String, in users: [SecureUser]) -> SecureUser? {
        if let exact = users.first(where: { $0.accountIdentifier == identifier }) { return exact }
        let legacyMatches = users.filter { $0.userId == identifier }
        guard legacyMatches.count > 1 else { return legacyMatches.first }
        if let current = getCurrentUserId(),
           let selected = legacyMatches.first(where: { $0.accountIdentifier == current })
        {
            return selected
        }
        return legacyMatches.first
    }
    
    // MARK: Visiblity
    
    func getCurrentVisibility() -> Visibility? {
        guard let raw = userDefaults.string(forKey: currentVisibilityKey) else { return nil }
        return Visibility(rawValue: raw)
    }
}
