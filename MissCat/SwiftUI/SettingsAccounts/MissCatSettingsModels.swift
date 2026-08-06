import Foundation

public struct MissCatAccountSummary: Identifiable, Equatable, Sendable {
    public let id: String
    public let username: String
    public let displayName: String
    public let instance: String
    public let avatarURL: URL?

    public init(
        id: String,
        username: String,
        displayName: String? = nil,
        instance: String,
        avatarURL: URL? = nil
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName?.isEmpty == false ? displayName! : "@\(username)"
        self.instance = instance
        self.avatarURL = avatarURL
    }
}

public struct MissCatAccountSnapshot: Equatable, Sendable {
    public var accounts: [MissCatAccountSummary]
    public var currentAccountID: String?

    public init(accounts: [MissCatAccountSummary], currentAccountID: String?) {
        self.accounts = accounts
        self.currentAccountID = currentAccountID
    }
}

public struct MissCatAccountDeletionResult: Equatable, Sendable {
    public var snapshot: MissCatAccountSnapshot
    public var removedConfiguredTabs: Bool

    public init(snapshot: MissCatAccountSnapshot, removedConfiguredTabs: Bool) {
        self.snapshot = snapshot
        self.removedConfiguredTabs = removedConfiguredTabs
    }
}

public enum MissCatAccountManagementError: LocalizedError, Equatable {
    case accountNotFound
    case accountPersistenceFailed
    case currentAccountVerificationFailed

    public var errorDescription: String? {
        switch self {
        case .accountNotFound:
            "アカウントが見つかりません"
        case .accountPersistenceFailed:
            "アカウント情報を安全に更新できませんでした"
        case .currentAccountVerificationFailed:
            "アカウントの切り替えを確認できませんでした"
        }
    }
}

@MainActor
public protocol MissCatAccountManaging: AnyObject {
    func loadAccounts() async throws -> MissCatAccountSnapshot
    func switchAccount(id: String) async throws -> MissCatAccountSnapshot
    func deleteAccount(id: String) async throws -> MissCatAccountDeletionResult
}

public enum MissCatThemeMode: String, CaseIterable, Identifiable, Sendable {
    case light = "Light"
    case dark = "Dark"

    public var id: String { rawValue }
}

public enum MissCatSettingsTabKind: String, CaseIterable, Identifiable, Sendable {
    case home
    case local
    case social
    case global
    case user
    case list

    public var id: String { rawValue }

    public var legacyTitle: String {
        switch self {
        case .home: "ホーム"
        case .local: "ローカル"
        case .social: "ソーシャル"
        case .global: "グローバル"
        case .user: "ユーザー"
        case .list: "リスト"
        }
    }

    public var defaultName: String {
        switch self {
        case .home: "Home"
        case .local: "Local"
        case .social: "Social"
        case .global: "Global"
        case .user: "User"
        case .list: "List"
        }
    }
}

public struct MissCatSettingsTab: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var kind: MissCatSettingsTabKind
    public var accountID: String?
    public var listID: String?

    public init(
        id: UUID = UUID(),
        name: String,
        kind: MissCatSettingsTabKind,
        accountID: String? = nil,
        listID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.accountID = accountID
        self.listID = listID
    }
}

public struct MissCatDesignSettingsSnapshot: Equatable, Sendable {
    public var tabs: [MissCatSettingsTab]
    public var mode: MissCatThemeMode
    public var accentHex: String
    public var accounts: [MissCatAccountSummary]

    public init(
        tabs: [MissCatSettingsTab],
        mode: MissCatThemeMode,
        accentHex: String,
        accounts: [MissCatAccountSummary]
    ) {
        self.tabs = tabs
        self.mode = mode
        self.accentHex = accentHex
        self.accounts = accounts
    }
}

public struct MissCatDesignSaveResult: Equatable, Sendable {
    public var snapshot: MissCatDesignSettingsSnapshot
    public var requiresRootRelaunch: Bool

    public init(snapshot: MissCatDesignSettingsSnapshot, requiresRootRelaunch: Bool) {
        self.snapshot = snapshot
        self.requiresRootRelaunch = requiresRootRelaunch
    }
}

@MainActor
public protocol MissCatDesignSettingsManaging: AnyObject {
    func loadDesignSettings() async throws -> MissCatDesignSettingsSnapshot
    func saveDesignSettings(_ snapshot: MissCatDesignSettingsSnapshot) async throws -> MissCatDesignSaveResult
}

public struct MissCatReactionItem: Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let rawValue: String
    public let displayValue: String?
    public let imageURL: URL?

    public init(rawValue: String, displayValue: String? = nil, imageURL: URL? = nil) {
        self.id = "\(rawValue)|\(imageURL?.absoluteString ?? "")"
        self.rawValue = rawValue
        self.displayValue = displayValue
        self.imageURL = imageURL
    }
}

public struct MissCatReactionAccount: Identifiable, Equatable, Sendable {
    public let id: String
    public let instance: String

    public init(id: String, instance: String) {
        self.id = id
        self.instance = instance
    }
}

public struct MissCatReactionSettingsSnapshot: Equatable, Sendable {
    public var account: MissCatReactionAccount
    public var favorites: [MissCatReactionItem]
    public var available: [MissCatReactionItem]

    public init(
        account: MissCatReactionAccount,
        favorites: [MissCatReactionItem],
        available: [MissCatReactionItem]
    ) {
        self.account = account
        self.favorites = favorites
        self.available = available
    }
}

@MainActor
public protocol MissCatReactionSettingsManaging: AnyObject {
    func loadReactionAccounts() async throws -> [MissCatReactionAccount]
    func loadReactions(accountID: String) async throws -> MissCatReactionSettingsSnapshot
    func saveReactions(_ snapshot: MissCatReactionSettingsSnapshot) async throws
}

public struct MissCatLicenseEntry: Identifiable, Equatable, Sendable {
    public let name: String
    public let text: String
    public var id: String { name }

    public init(name: String, text: String) {
        self.name = name
        self.text = text
    }
}

public enum MissCatSettingsRoute: Hashable {
    case design
    case reactionInstances
    case reactions(accountID: String)
    case licenses
    case license(name: String)
    case about
}

public enum MissCatSettingsPresentation: Equatable, Sendable {
    case empty(title: String, message: String)
    case error(title: String, message: String)
    case banner(message: String)
}

