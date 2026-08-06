import SwiftUI
import UIKit

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
        let store = MissCatProfileStore(account: account, userID: userID)
        let view = MissCatProfileScreen(
            store: store,
            palette: palette,
            onBack: { [weak home] in home?.navigationController?.popViewController(animated: true) },
            onOpenURL: { [weak home] url in
                switch (url.scheme, url.host) {
                case ("misscat", "user"):
                    home?.openUserPage(username: url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")), owner: owner)
                case ("misscat", "hashtag"):
                    home?.searchHashtag(tag: url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
                default:
                    home?.openLink(url: url.absoluteString)
                }
            },
            onOpenImage: { [weak home] url in home?.showImage([url], start: 0) },
            onSelectUser: { [weak home] selectedUserID in
                home?.move2Profile(userId: selectedUserID, owner: owner)
            },
            onOpenSettings: { [weak home] in home?.openSettings() },
            onSelectRoot: { [weak home] section in
                guard let home else { return }
                home.navigationController?.popToViewController(home, animated: false)
                switch section {
                case .home: home.emulateFooterTabTap(tab: .home)
                case .notifications: home.emulateFooterTabTap(tab: .notifications)
                case .messages: home.emulateFooterTabTap(tab: .messages)
                case .profile: home.emulateFooterTabTap(tab: .profile)
                }
            },
            onCompose: { [weak home] in home?.tappedPost() }
        )
        let controller = UIHostingController(rootView: view)
        controller.view.backgroundColor = UIColor(currentPalette.base)
        controller.navigationItem.hidesBackButton = true
        return controller
    }

    static func makeSearchResultsController(
        query: String,
        owner: SecureUser,
        home: HomeViewController?
    ) -> UIViewController? {
        guard let account = account(from: owner) else { return nil }
        let store = MissCatUserListStore(account: account, kind: .search(query: query))
        let view = MissCatUserListScreen(
            store: store,
            palette: currentPalette,
            onSelectUser: { [weak home] userID in
                home?.move2Profile(userId: userID, owner: owner)
            }
        )
        let controller = UIHostingController(rootView: view)
        controller.view.backgroundColor = UIColor(currentPalette.base)
        return controller
    }

    private static func account(from owner: SecureUser) -> MissCatProfileAccount? {
        guard let token = owner.apiKey, !token.isEmpty else { return nil }
        return MissCatProfileAccount(userID: owner.userId, instance: owner.instance, token: token)
    }

    private static var currentPalette: MissCatVisualPalette {
        Theme.shared.currentModel?.colorMode == .dark ? .legacyDark : .legacyLight
    }
}
