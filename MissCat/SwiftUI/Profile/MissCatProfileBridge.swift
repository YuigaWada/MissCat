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
        let view = MissCatProfileFamilyView(
            root: .profile(userID: userID),
            account: account,
            palette: palette,
            onExit: { [weak home] in home?.navigationController?.popViewController(animated: true) },
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
        let view = MissCatProfileFamilyView(
            root: .searchResults(query: query),
            account: account,
            palette: currentPalette,
            onExit: { [weak home] in home?.navigationController?.popViewController(animated: true) }
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
