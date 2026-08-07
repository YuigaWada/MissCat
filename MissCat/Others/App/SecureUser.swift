//
//  SecureUser.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/06/11.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import Foundation

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

/// Stable, non-secret identity used by account metadata, Keychain entries, and
/// the persisted current-account selection. Misskey user IDs are only unique
/// within an instance, so using `userId` alone can silently replace credentials
/// for an account on another server.
enum MissCatAccountIdentity {
    private static let prefix = "misscat-account-v2"

    static func normalizedInstance(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"

        if let components = URLComponents(string: candidate),
           let host = components.host?.lowercased(),
           !host.isEmpty
        {
            if let port = components.port, port != 443 {
                return "\(host):\(port)"
            }
            return host
        }

        return trimmed
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    static func storageKey(instance: String, userId: String) -> String {
        let normalized = normalizedInstance(instance)
        let encodedInstance = Data(normalized.utf8).base64EncodedString()
        let encodedUserID = Data(userId.utf8).base64EncodedString()
        return "\(prefix):\(encodedInstance):\(encodedUserID)"
    }
}

extension SecureUser {
    var accountIdentifier: String {
        MissCatAccountIdentity.storageKey(instance: instance, userId: userId)
    }

    var normalizedInstance: String {
        MissCatAccountIdentity.normalizedInstance(instance)
    }
}
