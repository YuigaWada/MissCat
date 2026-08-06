import SwiftUI
import UIKit

/// UIKit ownership boundary used only until the authenticated root shell is
/// retired. The ordinary Notifications and Chat tabs render SwiftUI content.
@MainActor
enum MissCatNotificationMessageBridge {
    static func makeNotificationsController(
        owner: SecureUser,
        home: HomeViewController
    ) -> MissCatNotificationsHostingController? {
        guard let scope = accountScope(from: owner) else { return nil }
        return MissCatNotificationsHostingController(
            owner: owner,
            repository: MissCatNativeNotificationMessagingRepository(accountScope: scope),
            home: home,
            palette: currentPalette
        )
    }

    static func makeMessagesController(
        owner: SecureUser,
        home: HomeViewController
    ) -> MissCatMessageHistoryHostingController? {
        guard let scope = accountScope(from: owner) else { return nil }
        return MissCatMessageHistoryHostingController(
            owner: owner,
            repository: MissCatNativeNotificationMessagingRepository(accountScope: scope),
            home: home,
            palette: currentPalette
        )
    }

    static func accountScope(from owner: SecureUser) -> MissCatAccountScope? {
        guard !owner.userId.isEmpty,
              !owner.username.isEmpty,
              !owner.instance.isEmpty,
              let token = owner.apiKey,
              !token.isEmpty else { return nil }
        return MissCatAccountScope(
            accountID: owner.userId,
            username: owner.username,
            host: owner.instance,
            accessToken: token
        )
    }

    static func openNotificationRoute(
        _ route: MissCatNotificationRoute,
        owner: SecureUser,
        home: HomeViewController
    ) {
        switch route {
        case let .user(userID):
            home.move2Profile(userId: userID, owner: owner)
        case let .note(noteID):
            guard let repository = MissCatMisskeyFeedRepository(user: owner) else { return }
            let view = MissCatNoteDetailView(
                noteID: noteID,
                repository: repository,
                palette: currentPalette,
                navigationActions: feedNavigationActions(owner: owner, home: home)
            )
            let controller = MissCatRoutedHostingController(rootView: AnyView(view))
            controller.title = "Thread"
            controller.view.backgroundColor = UIColor(currentPalette.base)
            home.navigationController?.pushViewController(controller, animated: true)
        }
    }

    static func makeConversationController(
        peer: MissCatPerson,
        owner: SecureUser,
        home: HomeViewController
    ) -> UIViewController? {
        guard let scope = accountScope(from: owner) else { return nil }
        let repository = MissCatNativeNotificationMessagingRepository(accountScope: scope)
        let view = MissCatConversationView(
            peer: peer,
            repository: repository,
            palette: currentPalette,
            navigationActions: .init(
                openRoute: { [weak home] route in
                    guard let home else { return }
                    openMessageRoute(route, repository: repository, owner: owner, home: home)
                }
            )
        )
        let controller = MissCatRoutedHostingController(rootView: AnyView(view))
        controller.title = peer.displayName
        controller.view.backgroundColor = UIColor(currentPalette.base)
        return controller
    }

    private static func openMessageRoute(
        _ route: MissCatMessageRoute,
        repository: MissCatNativeNotificationMessagingRepository,
        owner: SecureUser,
        home: HomeViewController
    ) {
        switch route {
        case let .externalURL(url):
            home.openLink(url: url.absoluteString)
        case let .hashtag(tag):
            home.searchHashtag(tag: tag)
        case let .mention(acct):
            Task { @MainActor [weak home] in
                guard let home else { return }
                do {
                    let person = try await repository.resolvePerson(acct: acct)
                    home.move2Profile(userId: person.id, owner: owner)
                } catch {
                    let normalized = acct.trimmingCharacters(in: CharacterSet(charactersIn: "@"))
                    let components = normalized.split(separator: "@", maxSplits: 1).map(String.init)
                    let host = components.count == 2 ? components[1] : owner.instance
                    if let username = components.first, !username.isEmpty {
                        home.openLink(url: "https://\(host)/@\(username)")
                    }
                }
            }
        }
    }

    private static func feedNavigationActions(
        owner: SecureUser,
        home: HomeViewController
    ) -> MissCatFeedNavigationActions {
        MissCatFeedNavigationActions(
            openUser: { [weak home] userID in
                home?.move2Profile(userId: userID, owner: owner)
            },
            openNote: { [weak home] noteID in
                guard let home else { return }
                openNotificationRoute(.note(noteID), owner: owner, home: home)
            },
            openAttachment: { [weak home] attachment in
                guard let url = attachment.url else { return }
                home?.showImage([url], start: 0)
            },
            openHashtag: { [weak home] tag in home?.searchHashtag(tag: tag) }
        )
    }

    private static var currentPalette: MissCatVisualPalette {
        var palette = Theme.shared.currentModel?.colorMode == .dark
            ? MissCatVisualPalette.legacyDark
            : MissCatVisualPalette.legacyLight
        if let accent = Theme.shared.currentModel?.mainColorHex {
            palette.accent = Color(hex: accent)
        }
        return palette
    }
}

@MainActor
final class MissCatNotificationsHostingController: UIHostingController<AnyView> {
    private weak var home: HomeViewController?
    private var owner: SecureUser
    private var repository: MissCatNativeNotificationMessagingRepository
    private var store: MissCatNotificationsStore
    private let palette: MissCatVisualPalette
    private let scrollCoordinator = MissCatNotificationScrollCoordinator()

    var ownerID: String { owner.userId }

    init(
        owner: SecureUser,
        repository: MissCatNativeNotificationMessagingRepository,
        home: HomeViewController,
        palette: MissCatVisualPalette
    ) {
        self.owner = owner
        self.repository = repository
        self.home = home
        self.palette = palette
        store = MissCatNotificationsStore(repository: repository)
        super.init(rootView: AnyView(EmptyView()))
        rebuildRoot()
        view.backgroundColor = UIColor(palette.base)
    }

    @available(*, unavailable)
    required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func changeUser(_ user: SecureUser) {
        guard user.userId != owner.userId,
              let scope = MissCatNotificationMessageBridge.accountScope(from: user) else { return }
        owner = user
        repository = MissCatNativeNotificationMessagingRepository(accountScope: scope)
        store.stopRealtime()
        store = MissCatNotificationsStore(repository: repository)
        rebuildRoot()
    }

    func handlePush(_ envelope: MissCatPushEnvelope, opensRoute: Bool) async {
        await store.handleForegroundPush(envelope)
        guard opensRoute,
              let route = store.takeBannerRoute(),
              let home else { return }
        MissCatNotificationMessageBridge.openNotificationRoute(route, owner: owner, home: home)
    }

    func tappedNotifications() {
        scrollCoordinator.scrollToTop()
    }

    private func rebuildRoot() {
        let view = MissCatNotificationsView(
            store: store,
            palette: palette,
            navigationActions: .init(open: { [weak self] route in
                guard let self, let home = self.home else { return }
                MissCatNotificationMessageBridge.openNotificationRoute(
                    route,
                    owner: self.owner,
                    home: home
                )
            }),
            scrollCoordinator: scrollCoordinator
        )
        rootView = AnyView(view)
    }
}

@MainActor
final class MissCatMessageHistoryHostingController: UIHostingController<AnyView> {
    private weak var home: HomeViewController?
    private var owner: SecureUser
    private var repository: MissCatNativeNotificationMessagingRepository
    private let palette: MissCatVisualPalette

    var ownerID: String { owner.userId }

    init(
        owner: SecureUser,
        repository: MissCatNativeNotificationMessagingRepository,
        home: HomeViewController,
        palette: MissCatVisualPalette
    ) {
        self.owner = owner
        self.repository = repository
        self.home = home
        self.palette = palette
        super.init(rootView: AnyView(EmptyView()))
        rebuildRoot()
        view.backgroundColor = UIColor(palette.base)
    }

    @available(*, unavailable)
    required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func changeUser(_ user: SecureUser) {
        guard user.userId != owner.userId,
              let scope = MissCatNotificationMessageBridge.accountScope(from: user) else { return }
        owner = user
        repository = MissCatNativeNotificationMessagingRepository(accountScope: scope)
        rebuildRoot()
    }

    private func rebuildRoot() {
        let view = MissCatMessageHistoryView(
            repository: repository,
            palette: palette,
            navigationActions: .init(
                openConversation: { [weak self] peer in
                    guard let self,
                          let home = self.home,
                          let controller = MissCatNotificationMessageBridge.makeConversationController(
                              peer: peer,
                              owner: self.owner,
                              home: home
                          ) else { return }
                    home.navigationController?.pushViewController(controller, animated: true)
                }
            )
        )
        rootView = AnyView(view)
    }
}

private final class MissCatRoutedHostingController: UIHostingController<AnyView> {
    private var previouslyHidden = true

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        previouslyHidden = navigationController?.isNavigationBarHidden ?? true
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        navigationController?.setNavigationBarHidden(previouslyHidden, animated: animated)
        super.viewWillDisappear(animated)
    }
}
