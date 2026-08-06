import SwiftUI
import UIKit

/// Temporary UIKit ownership boundary while the authenticated app root remains
/// storyboard-based. The complete Accounts principal content is native SwiftUI.
final class AccountsListViewController: UIViewController {
    var homeViewController: HomeViewController?
    private var hostingController: UIHostingController<AnyView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        guard hostingController == nil else { return }
        hostingController = MissCatSettingsBridge.installAccountsScreen(
            in: self,
            home: homeViewController
        )
    }
}
