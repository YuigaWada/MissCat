import SwiftUI
import UIKit

final class ShareViewController: UIViewController {
    private let userModel = UserModel()
    private let inputLoader: ShareInputLoading = ShareInputLoader()

    private var hostingController: UIHostingController<ShareComposerView>?
    private var viewModel: ShareComposerViewModel?
    private var hasFinishedRequest = false

    override func viewDidLoad() {
        super.viewDidLoad()
        installSwiftUIComposer()
        loadSharedContent()
    }

    private func installSwiftUIComposer() {
        let users = userModel.getUsers()
        let accounts = users.map {
            ShareAccount(id: $0.userId, username: $0.username, instance: $0.instance)
        }
        let currentUserID = userModel.getCurrentUser()?.userId
        let selectedAccountID = accounts.contains(where: { $0.id == currentUserID })
            ? currentUserID
            : accounts.first?.id
        let visibility = userModel.getCurrentVisibility()
            .flatMap { ShareVisibility(rawValue: $0.rawValue) }
            ?? .public

        let viewModel = ShareComposerViewModel(
            accounts: accounts,
            selectedAccountID: selectedAccountID,
            visibility: visibility,
            posting: SharePostService(userModel: userModel)
        )
        self.viewModel = viewModel

        let rootView = ShareComposerView(
            viewModel: viewModel,
            onComplete: { [weak self] in self?.completeRequest() },
            onCancel: { [weak self] in self?.cancelRequest() },
            onReloadInput: { [weak self] in self?.loadSharedContent() }
        )
        let hostingController = UIHostingController(rootView: rootView)
        self.hostingController = hostingController

        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hostingController.didMove(toParent: self)
    }

    private func loadSharedContent() {
        guard !hasFinishedRequest, let viewModel else { return }
        viewModel.beginLoading()
        let inputItems = extensionContext?.inputItems ?? []

        Task { @MainActor in
            do {
                let draft = try await inputLoader.load(inputItems: inputItems)
                guard !hasFinishedRequest else { return }
                viewModel.load(draft)
            } catch {
                guard !hasFinishedRequest else { return }
                viewModel.failLoading(error)
            }
        }
    }

    private func completeRequest() {
        guard !hasFinishedRequest else { return }
        hasFinishedRequest = true
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }

    private func cancelRequest() {
        guard !hasFinishedRequest else { return }
        hasFinishedRequest = true
        let error = NSError(
            domain: NSCocoaErrorDomain,
            code: NSUserCancelledError,
            userInfo: [NSLocalizedDescriptionKey: "共有をキャンセルしました"]
        )
        extensionContext?.cancelRequest(withError: error)
    }
}
