import Combine
import SwiftUI
import UIKit

@MainActor
enum MissCatSettingsBridge {
    static func makeSettingsController(home: HomeViewController) -> UIViewController {
        let repository = MissCatLegacySettingsRepository()
        let designStore = MissCatDesignSettingsStore(repository: repository)
        let reactionStore = MissCatReactionSettingsStore(repository: repository)
        let licenses = LicenseTableViewController.getOssDescription().map {
            MissCatLicenseEntry(name: $0.key, text: $0.value)
        }
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "1.0"
        let palette = currentPalette
        let view = MissCatSettingsRootView(
            designStore: designStore,
            reactionStore: reactionStore,
            palette: palette,
            licenses: licenses,
            appVersion: version,
            onRootRelaunchRequired: { [weak home] in
                home?.relaunchView(start: .main)
            },
            onClose: { [weak home] in
                home?.navigationController?.popViewController(animated: true)
            }
        )
        let controller = MissCatSettingsHostingController(rootView: AnyView(view))
        controller.view.backgroundColor = UIColor(palette.base)
        return controller
    }

    static func installAccountsScreen(
        in container: UIViewController,
        home: HomeViewController?
    ) -> UIHostingController<AnyView> {
        let repository = MissCatLegacySettingsRepository()
        let store = MissCatAccountStore(repository: repository)
        let palette = currentPalette
        let view = MissCatAccountsScreen(
            store: store,
            palette: palette,
            onAddAccount: { [weak home] in
                guard let home else { return }
                presentAddAccount(from: home, allowsCancel: true) {
                    store.load()
                    home.relaunchView(start: .profile)
                }
            },
            onOpenProfile: { [weak home] userID in
                guard let home,
                      let owner = Cache.UserDefaults.shared.getUser(userId: userID)
                else { return }
                home.move2Profile(userId: userID, owner: owner)
            },
            onAccountSwitched: { [weak home] in
                home?.relaunchView(start: .profile)
            },
            onConfiguredTabsChanged: { [weak home] in
                home?.relaunchView(start: .profile)
            },
            onAllAccountsDeleted: { [weak home] in
                guard let home else { return }
                presentAddAccount(from: home, allowsCancel: false) {
                    home.relaunchView(start: .profile)
                }
            }
        )
        let host = UIHostingController(rootView: AnyView(view))
        host.view.backgroundColor = UIColor(palette.base)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        container.addChild(host)
        container.view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: container.view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: container.view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: container.view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: container.view.bottomAnchor)
        ])
        host.didMove(toParent: container)
        return host
    }

    private static func presentAddAccount(
        from source: UIViewController,
        allowsCancel: Bool,
        onSuccess: @escaping () -> Void
    ) {
        let model = MissCatAddAccountModel()
        let view = MissCatAddAccountView(
            model: model,
            allowsCancel: allowsCancel,
            onSuccess: { [weak source] in
                source?.dismiss(animated: true, completion: onSuccess)
            },
            onCancel: { [weak source] in
                source?.dismiss(animated: true)
            }
        )
        let controller = UIHostingController(rootView: view)
        controller.modalPresentationStyle = .fullScreen
        controller.isModalInPresentation = !allowsCancel
        source.present(controller, animated: true)
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

private final class MissCatSettingsHostingController: UIHostingController<AnyView> {
    private var previousNavigationBarHidden = false

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        previousNavigationBarHidden = navigationController?.isNavigationBarHidden ?? false
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        navigationController?.setNavigationBarHidden(previousNavigationBarHidden, animated: animated)
        super.viewWillDisappear(animated)
    }
}

@MainActor
final class MissCatAddAccountModel: ObservableObject {
    @Published private(set) var isCompleting = false
    @Published private(set) var generation = 0
    @Published var errorMessage: String?

    private let service: MissCatAuthenticationService

    init() {
        self.service = MissCatAuthenticationService()
    }

    init(service: MissCatAuthenticationService) {
        self.service = service
    }

    func makeAuthorizationRequest(
        intent: MissCatAuthenticationIntent,
        instance: String
    ) async throws -> URLRequest {
        try await service.makeAuthorizationRequest(intent: intent, instance: instance)
    }

    func makeLoginRequestAfterSignUp(instance: String) async throws -> URLRequest {
        try await service.makeLoginRequestAfterSignUp(instance: instance)
    }

    func callbackMatches(_ url: URL) -> Bool {
        service.callbackMatches(url)
    }

    func complete(callbackURL: URL, onSuccess: @escaping () -> Void) {
        guard !isCompleting else { return }
        isCompleting = true
        Task { @MainActor in
            defer { isCompleting = false }
            do {
                _ = try await service.completeAuthentication(callbackURL: callbackURL)
                onSuccess()
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? "データ処理に失敗しました"
            }
        }
    }

    func present(_ error: Error) {
        errorMessage = (error as? LocalizedError)?.errorDescription
            ?? "インスタンスに接続できません"
    }

    func retry() {
        service.invalidatePendingAuthentication()
        errorMessage = nil
        generation += 1
    }

    func cancel() {
        service.invalidatePendingAuthentication()
    }
}

struct MissCatAddAccountView: View {
    @ObservedObject var model: MissCatAddAccountModel
    let allowsCancel: Bool
    let onSuccess: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            MissCatAuthenticationFlowView(
                makeAuthorizationRequest: model.makeAuthorizationRequest,
                makeLoginRequestAfterSignUp: model.makeLoginRequestAfterSignUp,
                callbackMatches: model.callbackMatches,
                onCallback: { model.complete(callbackURL: $0, onSuccess: onSuccess) },
                onFailure: model.present
            )
            .id(model.generation)

            if allowsCancel {
                Button {
                    model.cancel()
                    onCancel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 27))
                        .foregroundStyle(.white, .black.opacity(0.35))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
                .padding(.trailing, 8)
                .accessibilityLabel("閉じる")
                .accessibilityIdentifier("accounts.add.close")
            }

            if model.isCompleting {
                MissCatAuthenticationLoadingOverlay(accessibilityLabel: "認証情報を保存中")
                    .accessibilityIdentifier("accounts.add.completing")
            }
        }
        .alert(
            "エラー",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("再試行") { model.retry() }
            if allowsCancel {
                Button("閉じる", role: .cancel) {
                    model.cancel()
                    onCancel()
                }
            }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .accessibilityIdentifier("accounts.add.flow")
    }
}
