import SwiftUI
import UIKit

final class ShareViewController: UIViewController {
    private let userModel = UserModel()
    private let inputLoader: ShareInputLoading = ShareInputLoader()

    private var hostingController: UIHostingController<ShareComposerView>?
    private var viewModel: ShareComposerViewModel?
    private let terminalArbiter = ShareRequestTerminalArbiter()

    override func viewDidLoad() {
        super.viewDidLoad()
        installSwiftUIComposer()
        loadSharedContent()
    }

    private func installSwiftUIComposer() {
        let users = userModel.getUsers()
        let accounts = users.map {
            ShareAccount(userID: $0.userId, username: $0.username, instance: $0.instance)
        }
        let currentAccountID = userModel.getCurrentUser()?.accountIdentifier
        let selectedAccountID = accounts.contains(where: { $0.id == currentAccountID })
            ? currentAccountID
            : accounts.first?.id
        let visibility = userModel.getCurrentVisibility()
            .flatMap { ShareVisibility(rawValue: $0.rawValue) }
            ?? .public

#if DEBUG
        ShareCredentialReadProbe.invokeIfRequested(
            arguments: ProcessInfo.processInfo.arguments,
            accountIdentifier: selectedAccountID,
            read: userModel.credentialReadProof(accountIdentifier:),
            store: { proof in
                let defaults = UserDefaults(suiteName: MissCatComposeOperationJournal.appGroup) ?? .standard
                defaults.set(proof.credentialAvailable, forKey: ShareCredentialReadProbe.resultKey)
                defaults.set(proof.accountIdentifierHash, forKey: ShareCredentialReadProbe.accountHashKey)
            }
        )
#endif

        let viewModel = ShareComposerViewModel(
            accounts: accounts,
            selectedAccountID: selectedAccountID,
            visibility: visibility,
            posting: SharePostService(userProvider: userModel.getUser(accountIdentifier:))
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
        guard terminalArbiter.terminal == nil, let viewModel else { return }
        viewModel.beginLoading()
        let inputItems = extensionContext?.inputItems ?? []

        Task { @MainActor in
            do {
                let draft = try await inputLoader.load(inputItems: inputItems)
                guard terminalArbiter.terminal == nil else { return }
                viewModel.load(draft)
            } catch {
                guard terminalArbiter.terminal == nil else { return }
                viewModel.failLoading(error)
            }
        }
    }

    private func completeRequest() {
        guard terminalArbiter.resolve(.completed) else { return }
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }

    private func cancelRequest() {
        viewModel?.cancel()
        guard terminalArbiter.resolve(.cancelled) else { return }
        let error = NSError(
            domain: NSCocoaErrorDomain,
            code: NSUserCancelledError,
            userInfo: [NSLocalizedDescriptionKey: "共有をキャンセルしました"]
        )
        extensionContext?.cancelRequest(withError: error)
    }
}
