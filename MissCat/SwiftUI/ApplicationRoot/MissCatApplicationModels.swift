import Foundation

/// Instance-scoped, non-secret account identity used by application routing.
/// Misskey user IDs are not globally unique, so routing must never compare a
/// bare user ID when deciding whether a push belongs to the active account.
public struct MissCatApplicationAccountID: Hashable, Codable, RawRepresentable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(instance: String, userID: String) {
        rawValue = MissCatAccountIdentity.storageKey(instance: instance, userId: userID)
    }
}

public struct MissCatApplicationAccount: Hashable, Identifiable, Sendable {
    public let id: MissCatApplicationAccountID
    public let instance: String
    public let userID: String
    public let username: String
    public let displayName: String
    public let avatarURL: URL?

    public init(
        instance: String,
        userID: String,
        username: String,
        displayName: String? = nil,
        avatarURL: URL? = nil
    ) {
        id = MissCatApplicationAccountID(instance: instance, userID: userID)
        self.instance = MissCatAccountIdentity.normalizedInstance(instance)
        self.userID = userID
        self.username = username
        if let displayName, !displayName.isEmpty {
            self.displayName = displayName
        } else {
            self.displayName = "@\(username)"
        }
        self.avatarURL = avatarURL
    }
}

/// Everything the authenticated application root needs to render without
/// reaching into Cache, Theme, or a UIKit controller.
public struct MissCatApplicationSession: Equatable, Sendable {
    public let currentAccount: MissCatApplicationAccount
    public let accounts: [MissCatApplicationAccount]
    public let timelineTabs: [MissCatTimelineTab]
    public let selectedTimelineID: String

    public init(
        currentAccount: MissCatApplicationAccount,
        accounts: [MissCatApplicationAccount],
        timelineTabs: [MissCatTimelineTab],
        selectedTimelineID: String
    ) {
        var seenAccounts = Set<MissCatApplicationAccountID>()
        var normalizedAccounts = accounts.filter { seenAccounts.insert($0.id).inserted }
        if !seenAccounts.contains(currentAccount.id) {
            normalizedAccounts.insert(currentAccount, at: 0)
        }

        let selection = MissCatApplicationTabSelection(
            tabs: timelineTabs,
            selectedID: selectedTimelineID
        )
        self.currentAccount = currentAccount
        self.accounts = normalizedAccounts
        self.timelineTabs = selection.tabs
        self.selectedTimelineID = selection.selectedID
    }
}

public enum MissCatApplicationRootPhase: Equatable, Sendable {
    case launching
    case signedOut
    case switching(current: MissCatApplicationSession, target: MissCatApplicationAccountID)
    case signingOut(current: MissCatApplicationSession)
    case authenticated(MissCatApplicationSession)
    case failed(message: String)

    public var authenticatedSession: MissCatApplicationSession? {
        switch self {
        case let .authenticated(session),
             let .switching(current: session, target: _),
             let .signingOut(current: session):
            session
        case .launching, .signedOut, .failed:
            nil
        }
    }
}

public enum MissCatApplicationRoute: Hashable, Sendable {
    case discovery
    case note(id: String)
    case notification(id: String)
    case profile(userID: String)
    case profileUserList(MissCatUserListKind)
    case profileEditor(MissCatProfileUser)
    case userTimeline(userID: String, includesReplies: Bool, onlyFiles: Bool)
    case conversation(userID: String)
    case search(query: String)
    case hashtag(String)
    case settings
    case accounts
    case externalURL(URL)
}

public enum MissCatApplicationSheetDestination: Hashable, Identifiable, Sendable {
    case accountSwitcher
    case settings
    case reactionPicker(noteID: String)
    case share(noteID: String)

    public var id: String {
        switch self {
        case .accountSwitcher: "account-switcher"
        case .settings: "settings"
        case let .reactionPicker(noteID): "reaction:\(noteID)"
        case let .share(noteID): "share:\(noteID)"
        }
    }
}

public enum MissCatApplicationComposeIntent: Hashable, Sendable {
    case new
    case reply(noteID: String)
    case quote(noteID: String)
}

public enum MissCatApplicationFullScreenDestination: Hashable, Identifiable, Sendable {
    case compose(MissCatApplicationComposeIntent)
    case media(attachmentID: String)

    public var id: String {
        switch self {
        case .compose(.new): "compose:new"
        case let .compose(.reply(noteID)): "compose:reply:\(noteID)"
        case let .compose(.quote(noteID)): "compose:quote:\(noteID)"
        case let .media(attachmentID): "media:\(attachmentID)"
        }
    }
}

public enum MissCatApplicationTabSelectionOrigin: Equatable, Sendable {
    case initial
    case tap
    case swipeLeft
    case swipeRight
    case tabsChanged
}

public enum MissCatApplicationTabBoundary: Equatable, Sendable {
    case first
    case last
}

public enum MissCatApplicationTabSelectionResult: Equatable, Sendable {
    case changed(id: String, origin: MissCatApplicationTabSelectionOrigin)
    case unchanged(id: String)
    case boundary(MissCatApplicationTabBoundary, id: String)
    case rejected(candidate: String)
}

/// Pure selection state shared by header taps and page swipes. Boundary results
/// are explicit so a container never wraps from the first page to the last.
public struct MissCatApplicationTabSelection: Equatable, Sendable {
    public private(set) var tabs: [MissCatTimelineTab]
    public private(set) var selectedID: String
    public private(set) var lastOrigin: MissCatApplicationTabSelectionOrigin

    public init(tabs: [MissCatTimelineTab], selectedID: String) {
        self.tabs = Self.unique(tabs)
        self.selectedID = Self.normalized(selectedID, in: self.tabs)
        lastOrigin = .initial
    }

    @discardableResult
    public mutating func select(_ candidate: String) -> MissCatApplicationTabSelectionResult {
        guard tabs.contains(where: { $0.id == candidate }) else {
            return .rejected(candidate: candidate)
        }
        guard candidate != selectedID else { return .unchanged(id: selectedID) }
        selectedID = candidate
        lastOrigin = .tap
        return .changed(id: selectedID, origin: lastOrigin)
    }

    @discardableResult
    public mutating func swipeLeft() -> MissCatApplicationTabSelectionResult {
        move(offset: 1, origin: .swipeLeft, boundary: .last)
    }

    @discardableResult
    public mutating func swipeRight() -> MissCatApplicationTabSelectionResult {
        move(offset: -1, origin: .swipeRight, boundary: .first)
    }

    @discardableResult
    public mutating func updateTabs(
        _ tabs: [MissCatTimelineTab],
        preferredID: String? = nil
    ) -> MissCatApplicationTabSelectionResult {
        let previous = selectedID
        self.tabs = Self.unique(tabs)
        selectedID = Self.normalized(preferredID ?? previous, in: self.tabs)
        lastOrigin = .tabsChanged
        if selectedID == previous { return .unchanged(id: selectedID) }
        return .changed(id: selectedID, origin: lastOrigin)
    }

    private mutating func move(
        offset: Int,
        origin: MissCatApplicationTabSelectionOrigin,
        boundary: MissCatApplicationTabBoundary
    ) -> MissCatApplicationTabSelectionResult {
        guard let index = tabs.firstIndex(where: { $0.id == selectedID }) else {
            return .rejected(candidate: selectedID)
        }
        let target = index + offset
        guard tabs.indices.contains(target) else { return .boundary(boundary, id: selectedID) }
        selectedID = tabs[target].id
        lastOrigin = origin
        return .changed(id: selectedID, origin: origin)
    }

    private static func unique(_ tabs: [MissCatTimelineTab]) -> [MissCatTimelineTab] {
        var seen = Set<String>()
        return tabs.filter { !$0.id.isEmpty && seen.insert($0.id).inserted }
    }

    private static func normalized(_ candidate: String, in tabs: [MissCatTimelineTab]) -> String {
        tabs.contains(where: { $0.id == candidate }) ? candidate : (tabs.first?.id ?? "")
    }
}

public struct MissCatApplicationPush: Hashable, Identifiable, Sendable {
    public enum Action: Hashable, Sendable {
        case refreshNotifications(notificationID: String)
        case openNotification(notificationID: String)
    }

    public let id: String
    public let accountID: MissCatApplicationAccountID
    public let action: Action

    public init(id: String, accountID: MissCatApplicationAccountID, action: Action) {
        self.id = id
        self.accountID = accountID
        self.action = action
    }
}
