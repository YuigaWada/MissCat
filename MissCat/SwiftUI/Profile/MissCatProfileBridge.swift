import SwiftUI
import UIKit

@MainActor
protocol MissCatProfileHomeRouting: AnyObject {
    func missCatProfileExit()
    func missCatProfileOpenUser(username: String, owner: SecureUser)
    func missCatProfileOpenHashtag(_ hashtag: String)
    func missCatProfileOpenExternalURL(_ url: String)
    func missCatProfileOpenImage(_ url: URL)
    func missCatProfileOpenSettings()
    func missCatProfileSelectRoot(_ section: MissCatRootSection)
    func missCatProfileCompose()
}

extension HomeViewController: MissCatProfileHomeRouting {
    func missCatProfileExit() {
#if DEBUG
        if MissCatProfileOrdinaryRouteConfiguration.isEnabled {
            MissCatProfileOrdinaryRouteConfiguration.record("exit")
            return
        }
#endif
        navigationController?.popViewController(animated: true)
    }

    func missCatProfileOpenUser(username: String, owner: SecureUser) {
#if DEBUG
        if MissCatProfileOrdinaryRouteConfiguration.isEnabled {
            MissCatProfileOrdinaryRouteConfiguration.record("user")
            return
        }
#endif
        openUserPage(username: username, owner: owner)
    }

    func missCatProfileOpenHashtag(_ hashtag: String) {
#if DEBUG
        if MissCatProfileOrdinaryRouteConfiguration.isEnabled {
            MissCatProfileOrdinaryRouteConfiguration.record("hashtag")
            return
        }
#endif
        searchHashtag(tag: hashtag)
    }

    func missCatProfileOpenExternalURL(_ url: String) {
#if DEBUG
        if MissCatProfileOrdinaryRouteConfiguration.isEnabled {
            MissCatProfileOrdinaryRouteConfiguration.record("url")
            return
        }
#endif
        openLink(url: url)
    }

    func missCatProfileOpenImage(_ url: URL) {
#if DEBUG
        if MissCatProfileOrdinaryRouteConfiguration.isEnabled {
            MissCatProfileOrdinaryRouteConfiguration.record("image")
            return
        }
#endif
        showImage([url], start: 0)
    }

    func missCatProfileOpenSettings() {
#if DEBUG
        if MissCatProfileOrdinaryRouteConfiguration.isEnabled {
            MissCatProfileOrdinaryRouteConfiguration.record("settings")
            return
        }
#endif
        openSettings()
    }

    func missCatProfileSelectRoot(_ section: MissCatRootSection) {
#if DEBUG
        if MissCatProfileOrdinaryRouteConfiguration.isEnabled {
            MissCatProfileOrdinaryRouteConfiguration.record("root.\(section.rawValue)")
            return
        }
#endif
        navigationController?.popToViewController(self, animated: false)
        switch section {
        case .home: emulateFooterTabTap(tab: .home)
        case .notifications: emulateFooterTabTap(tab: .notifications)
        case .messages: emulateFooterTabTap(tab: .messages)
        case .profile: emulateFooterTabTap(tab: .profile)
        }
    }

    func missCatProfileCompose() {
#if DEBUG
        if MissCatProfileOrdinaryRouteConfiguration.isEnabled {
            MissCatProfileOrdinaryRouteConfiguration.record("compose")
            return
        }
#endif
        tappedPost()
    }
}

/// The only UIKit boundary for the profile family while the legacy root
/// controller is being retired. All screen content below this host is SwiftUI.
@MainActor
enum MissCatProfileBridge {
    static func makeProfileController(
        userID: String,
        owner: SecureUser,
        home: HomeViewController
    ) -> UIViewController? {
        guard let account = account(from: owner) else { return nil }
        let palette = currentPalette
        return makeFamilyController(
            root: .profile(userID: userID),
            account: account,
            palette: palette,
            shellOwnership: .profileFamily,
            actions: productionActions(owner: owner, router: home)
        )
    }

    static func makeSearchResultsController(
        query: String,
        owner: SecureUser,
        home: HomeViewController?
    ) -> UIViewController? {
        guard let account = account(from: owner) else { return nil }
#if DEBUG
        let repositoryFactory: (MissCatProfileAccount) -> MissCatProfileRepository =
            MissCatProfileOrdinaryRouteConfiguration.isEnabled
                ? { _ in MissCatProfileOrdinaryRouteConfiguration.repository }
                : { MissCatRESTProfileRepository(account: $0) }
#else
        let repositoryFactory: (MissCatProfileAccount) -> MissCatProfileRepository = {
            MissCatRESTProfileRepository(account: $0)
        }
#endif
        return makeFamilyController(
            root: .searchResults(query: query),
            account: account,
            palette: currentPalette,
            shellOwnership: .outerShell,
            repositoryFactory: repositoryFactory,
            actions: productionActions(owner: owner, router: home)
        )
    }

    static func makeFamilyController(
        root: MissCatProfileFamilyView.Root,
        account: MissCatProfileAccount,
        palette: MissCatVisualPalette,
        shellOwnership: MissCatProfileShellOwnership,
        repositoryFactory: @escaping (MissCatProfileAccount) -> MissCatProfileRepository = {
            MissCatRESTProfileRepository(account: $0)
        },
        actions: MissCatProfileFamilyActions
    ) -> UIHostingController<MissCatProfileFamilyView> {
        let view = MissCatProfileFamilyView(
            root: root,
            account: account,
            palette: palette,
            shellOwnership: shellOwnership,
            repositoryFactory: repositoryFactory,
            actions: actions
        )
        let controller = UIHostingController(rootView: view)
        controller.view.backgroundColor = UIColor(palette.base)
        controller.navigationItem.hidesBackButton = true
        return controller
    }

    static func productionActions(
        owner: SecureUser,
        router: MissCatProfileHomeRouting?
    ) -> MissCatProfileFamilyActions {
        MissCatProfileFamilyActions(
            onExit: { [weak router] in router?.missCatProfileExit() },
            onOpenURL: { [weak router] url in
                switch (url.scheme, url.host) {
                case ("misscat", "user"):
                    router?.missCatProfileOpenUser(
                        username: url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
                        owner: owner
                    )
                case ("misscat", "hashtag"):
                    router?.missCatProfileOpenHashtag(
                        url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    )
                default:
                    router?.missCatProfileOpenExternalURL(url.absoluteString)
                }
            },
            onOpenImage: { [weak router] in router?.missCatProfileOpenImage($0) },
            onOpenSettings: { [weak router] in router?.missCatProfileOpenSettings() },
            onSelectRoot: { [weak router] in router?.missCatProfileSelectRoot($0) },
            onCompose: { [weak router] in router?.missCatProfileCompose() }
        )
    }

    private static func account(from owner: SecureUser) -> MissCatProfileAccount? {
        guard let token = owner.apiKey, !token.isEmpty else { return nil }
        return MissCatProfileAccount(userID: owner.userId, instance: owner.instance, token: token)
    }

    private static var currentPalette: MissCatVisualPalette {
        Theme.shared.currentModel?.colorMode == .dark ? .legacyDark : .legacyLight
    }
}
