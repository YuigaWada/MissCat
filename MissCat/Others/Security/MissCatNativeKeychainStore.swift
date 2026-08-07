import Foundation
import Security

/// The only adapter around the Security framework used by both the app and
/// Share extension. Its generic-password schema deliberately matches the
/// former generic-password wrapper defaults so existing credentials remain readable:
/// service + account + access group, UTF-8 data, non-synchronizable, and
/// accessible after the first device unlock.
struct MissCatNativeKeychainStore {
    enum StoreError: Error, Equatable {
        case invalidUTF8
        case unexpectedResult
        case security(OSStatus)
    }

    struct SecurityClient {
        var copyMatching: ([String: Any]) -> (OSStatus, Any?)
        var add: ([String: Any]) -> OSStatus
        var update: ([String: Any], [String: Any]) -> OSStatus
        var delete: ([String: Any]) -> OSStatus

        static var live: SecurityClient {
            SecurityClient(
                copyMatching: { query in
                    var result: CFTypeRef?
                    let status = SecItemCopyMatching(query as CFDictionary, &result)
                    return (status, result)
                },
                add: { attributes in
                    SecItemAdd(attributes as CFDictionary, nil)
                },
                update: { query, attributes in
                    SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
                },
                delete: { query in
                    SecItemDelete(query as CFDictionary)
                }
            )
        }
    }

    private let service: String
    private let accessGroup: String?
    private let client: SecurityClient

    init(
        service: String,
        accessGroup: String? = nil,
        client: SecurityClient = .live
    ) {
        self.service = service
        self.accessGroup = accessGroup
        self.client = client
    }

    func string(forKey key: String) throws -> String? {
        var query = matchingQuery(account: key)
        query[String(kSecMatchLimit)] = kSecMatchLimitOne
        query[String(kSecReturnData)] = kCFBooleanTrue

        let (status, result) = client.copyMatching(query)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw StoreError.unexpectedResult
            }
            guard let value = String(data: data, encoding: .utf8) else {
                throw StoreError.invalidUTF8
            }
            return value
        case errSecItemNotFound:
            return nil
        default:
            throw StoreError.security(status)
        }
    }

    func set(_ value: String, forKey key: String) throws {
        let valueData = Data(value.utf8)
        let updateAttributes: [String: Any] = [
            String(kSecValueData): valueData,
            String(kSecAttrAccessible): kSecAttrAccessibleAfterFirstUnlock,
            String(kSecAttrSynchronizable): kCFBooleanFalse as Any,
        ]

        let updateStatus = client.update(matchingQuery(account: key), updateAttributes)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var attributes = itemIdentity(account: key)
            updateAttributes.forEach { attributes[$0.key] = $0.value }
            let addStatus = client.add(attributes)
            if addStatus == errSecSuccess {
                return
            }
            // Another process can add the same app/extension item between the
            // update and add. Resolve that harmless race with one verified
            // update path instead of surfacing a spurious login failure.
            if addStatus == errSecDuplicateItem {
                let retryStatus = client.update(matchingQuery(account: key), updateAttributes)
                guard retryStatus == errSecSuccess else {
                    throw StoreError.security(retryStatus)
                }
                return
            }
            throw StoreError.security(addStatus)
        default:
            throw StoreError.security(updateStatus)
        }
    }

    func removeValue(forKey key: String) throws {
        let status = client.delete(matchingQuery(account: key))
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StoreError.security(status)
        }
    }

    func allKeys() throws -> [String] {
        var query = matchingQuery(account: nil)
        query[String(kSecMatchLimit)] = kSecMatchLimitAll
        query[String(kSecReturnAttributes)] = kCFBooleanTrue

        let (status, result) = client.copyMatching(query)
        switch status {
        case errSecSuccess:
            let items: [[String: Any]]
            if let multiple = result as? [[String: Any]] {
                items = multiple
            } else if let single = result as? [String: Any] {
                items = [single]
            } else {
                throw StoreError.unexpectedResult
            }
            return items.compactMap { $0[String(kSecAttrAccount)] as? String }.sorted()
        case errSecItemNotFound:
            return []
        default:
            throw StoreError.security(status)
        }
    }

    private func itemIdentity(account: String?) -> [String: Any] {
        var query: [String: Any] = [
            String(kSecClass): kSecClassGenericPassword,
            String(kSecAttrService): service,
        ]
        if let accessGroup {
            query[String(kSecAttrAccessGroup)] = accessGroup
        }
        if let account {
            query[String(kSecAttrAccount)] = account
        }
        return query
    }

    private func matchingQuery(account: String?) -> [String: Any] {
        var query = itemIdentity(account: account)
        // The former wrapper ignored the synchronizable attribute for reads,
        // updates, removals, and enumeration. Keep that migration contract.
        query[String(kSecAttrSynchronizable)] = kSecAttrSynchronizableAny
        return query
    }
}
