import SwiftUI
import UIKit

final class ShareViewController: UIViewController {
    private let userModel = UserModel()

    private var hostingController: UIHostingController<AnyView>?
    private let terminalArbiter = ShareRequestTerminalArbiter()

    override func viewDidLoad() {
        super.viewDidLoad()
        installSwiftUIComposer()
    }

    private func installSwiftUIComposer() {
        let rootView = ShareExtensionRootView(
            userModel: userModel,
            inputItems: extensionContext?.inputItems ?? [],
            onComplete: { [weak self] in self?.completeRequest() },
            onCancel: { [weak self] in self?.cancelRequest() }
        )
        installSwiftUIRoot(rootView)
    }

    private func installSwiftUIRoot<Content: View>(_ rootView: Content) {
        let hostingController = UIHostingController(rootView: AnyView(rootView))
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

    private func completeRequest() {
        guard terminalArbiter.resolve(.completed) else { return }
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }

    private func cancelRequest() {
        guard terminalArbiter.resolve(.cancelled) else { return }
        let error = NSError(
            domain: NSCocoaErrorDomain,
            code: NSUserCancelledError,
            userInfo: [NSLocalizedDescriptionKey: "共有をキャンセルしました"]
        )
        extensionContext?.cancelRequest(withError: error)
    }
}
