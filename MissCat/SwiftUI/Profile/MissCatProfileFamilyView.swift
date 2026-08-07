import SwiftUI

/// A typed SwiftUI navigation owner for every profile and user-list route.
///
/// The legacy home controller still supplies the outer compatibility host while
/// the authenticated root is being migrated atomically. Once this family is
/// entered, result rows, relationship lists, and nested profiles remain inside
/// one SwiftUI `NavigationStack`; they never round-trip through storyboard
/// controllers.
public struct MissCatProfileFamilyView: View {
    public enum Root: Hashable, Sendable {
        case profile(userID: String)
        case searchResults(query: String)
    }

    public enum Destination: Hashable, Sendable {
        case profile(userID: String)
        case userList(MissCatUserListKind)
        case editProfile(MissCatProfileUser)
    }

    @State private var path: [Destination] = []
    @State private var editRequestCount = 0
    @State private var profileRevision: [String: Int] = [:]

    private let root: Root
    private let account: MissCatProfileAccount
    private let palette: MissCatVisualPalette
    private let repositoryFactory: (MissCatProfileAccount) -> MissCatProfileRepository
    private let onExit: () -> Void
    private let onOpenURL: (URL) -> Void
    private let onOpenImage: (URL) -> Void
    private let onOpenSettings: () -> Void
    private let onSelectRoot: (MissCatRootSection) -> Void
    private let onCompose: () -> Void

    public init(
        root: Root,
        account: MissCatProfileAccount,
        palette: MissCatVisualPalette = .legacyLight,
        repositoryFactory: @escaping (MissCatProfileAccount) -> MissCatProfileRepository = {
            MissCatRESTProfileRepository(account: $0)
        },
        onExit: @escaping () -> Void = {},
        onOpenURL: @escaping (URL) -> Void = { _ in },
        onOpenImage: @escaping (URL) -> Void = { _ in },
        onOpenSettings: @escaping () -> Void = {},
        onSelectRoot: @escaping (MissCatRootSection) -> Void = { _ in },
        onCompose: @escaping () -> Void = {}
    ) {
        self.root = root
        self.account = account
        self.palette = palette
        self.repositoryFactory = repositoryFactory
        self.onExit = onExit
        self.onOpenURL = onOpenURL
        self.onOpenImage = onOpenImage
        self.onOpenSettings = onOpenSettings
        self.onSelectRoot = onSelectRoot
        self.onCompose = onCompose
    }

    public var body: some View {
        NavigationStack(path: $path) {
            rootView
                .navigationDestination(for: Destination.self, destination: destination)
        }
        .overlay(alignment: .topLeading) {
            VStack(spacing: 0) {
                MissCatProfileAccessibilityMarker(identifier: "profile.family")
#if DEBUG
                MissCatProfileValueMarker(
                    identifier: "profile.edit.requestCount",
                    value: String(editRequestCount)
                )
#endif
            }
        }
    }

    @ViewBuilder
    private var rootView: some View {
        switch root {
        case let .profile(userID):
            profile(userID: userID, isRoot: true)
        case let .searchResults(query):
            userList(kind: .search(query: query), title: nil)
                .toolbar(.hidden, for: .navigationBar)
                .overlay(alignment: .topLeading) {
                    MissCatProfileAccessibilityMarker(identifier: "profile.searchResults.root")
                }
        }
    }

    @ViewBuilder
    private func destination(_ destination: Destination) -> some View {
        switch destination {
        case let .profile(userID):
            profile(userID: userID, isRoot: false)
        case let .userList(kind):
            userList(kind: kind, title: kind.title)
        case let .editProfile(profile):
            editor(profile: profile)
        }
    }

    private func profile(userID: String, isRoot: Bool) -> some View {
        MissCatProfileScreen(
            store: MissCatProfileStore(
                account: account,
                userID: userID,
                repositoryFactory: repositoryFactory
            ),
            palette: palette,
            repositoryFactory: repositoryFactory,
            onBack: {
                if isRoot || path.isEmpty {
                    onExit()
                } else {
                    path.removeLast()
                }
            },
            onOpenURL: onOpenURL,
            onOpenImage: onOpenImage,
            onSelectUser: { path.append(.profile(userID: $0)) },
            onOpenUserList: { path.append(.userList($0)) },
            onEditProfile: { profile in
                editRequestCount += 1
                path.append(.editProfile(profile))
            },
            onOpenSettings: onOpenSettings,
            onSelectRoot: onSelectRoot,
            onCompose: onCompose
        )
        .id("profile-\(userID)-\(profileRevision[userID, default: 0])")
        .toolbar(.hidden, for: .navigationBar)
    }

    private func editor(profile: MissCatProfileUser) -> some View {
        MissCatProfileEditorScreen(
            store: MissCatProfileEditorStore(
                account: account,
                profile: profile,
                repositoryFactory: repositoryFactory
            ),
            palette: palette,
            onCancel: popEditor
        ) { updated in
            profileRevision[updated.id, default: 0] += 1
            popEditor()
        }
        .background(palette.base)
    }

    private func popEditor() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    @ViewBuilder
    private func userList(kind: MissCatUserListKind, title: String?) -> some View {
        let store = MissCatUserListStore(
            account: account,
            kind: kind,
            repositoryFactory: repositoryFactory
        )
        MissCatUserListScreen(
            store: store,
            palette: palette,
            onSelectUser: { path.append(.profile(userID: $0)) }
        )
        .navigationTitle(title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .topLeading) {
            MissCatProfileAccessibilityMarker(identifier: "profile.family.userList")
        }
    }
}

private struct MissCatProfileAccessibilityMarker: View {
    let identifier: String

    var body: some View {
        Text("marker")
            .font(.system(size: 1))
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .accessibilityLabel(identifier)
            .accessibilityIdentifier(identifier)
    }
}

#if DEBUG
private struct MissCatProfileValueMarker: View {
    let identifier: String
    let value: String

    var body: some View {
        Text(value)
            .font(.system(size: 1))
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .accessibilityLabel(identifier)
            .accessibilityValue(value)
            .accessibilityIdentifier(identifier)
    }
}
#endif

/// Pure route state used by unit tests and by future deep-link restoration.
public struct MissCatProfileNavigationState: Equatable, Sendable {
    public private(set) var path: [MissCatProfileFamilyView.Destination] = []

    public init() {}

    public mutating func openProfile(_ userID: String) {
        guard !userID.isEmpty else { return }
        path.append(.profile(userID: userID))
    }

    public mutating func openUserList(_ kind: MissCatUserListKind) {
        path.append(.userList(kind))
    }

    public mutating func editProfile(_ profile: MissCatProfileUser) {
        path.append(.editProfile(profile))
    }

    @discardableResult
    public mutating func goBack() -> Bool {
        guard !path.isEmpty else { return false }
        path.removeLast()
        return true
    }
}
