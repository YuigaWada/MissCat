import Combine
import SwiftUI
import UIKit

@MainActor
enum MissCatSettingsBridge {
    static func makeSettingsController(home: HomeViewController) -> UIViewController {
        let repository: any MissCatDesignSettingsManaging & MissCatReactionSettingsManaging
        if MissCatSettingsFixtureRepository.isEnabled {
            repository = MissCatSettingsFixtureRepository()
        } else {
            repository = MissCatLegacySettingsRepository()
        }
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
        let repository: any MissCatAccountManaging
        if MissCatSettingsFixtureRepository.isEnabled {
            repository = MissCatSettingsFixtureRepository()
        } else {
            repository = MissCatLegacySettingsRepository()
        }
        let store = MissCatAccountStore(repository: repository)
        let palette = currentPalette
        let view = MissCatAccountsRootView(
            store: store,
            palette: palette,
            profileDestination: { [weak home] account, dismiss in
                makeProfileDestination(account: account, home: home, dismiss: dismiss)
            },
            onAccountSwitched: { [weak home] in
                home?.relaunchView(start: .profile)
            },
            onConfiguredTabsChanged: { [weak home] in
                home?.relaunchView(start: .profile)
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

    static func makeReactionSettingsController(
        accountID: String,
        onClose: @escaping () -> Void
    ) -> UIViewController {
        let repository: any MissCatReactionSettingsManaging
        if MissCatSettingsFixtureRepository.isEnabled {
            repository = MissCatSettingsFixtureRepository()
        } else {
            repository = MissCatLegacySettingsRepository()
        }
        let store = MissCatReactionSettingsStore(repository: repository)
        let palette = currentPalette
        let view = NavigationStack {
            MissCatReactionSettingsScreen(
                store: store,
                accountID: accountID,
                palette: palette
            )
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onClose) {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("戻る")
                    .accessibilityIdentifier("settings.reactions.close")
                }
            }
        }
        let controller = MissCatSettingsHostingController(rootView: AnyView(view))
        controller.view.backgroundColor = UIColor(palette.base)
        return controller
    }

    static func profileUserID(
        for account: MissCatAccountSummary,
        owner: SecureUser
    ) -> String? {
        guard account.id == owner.accountIdentifier,
              account.userID == owner.userId else { return nil }
        return owner.userId
    }

    private static func makeProfileDestination(
        account: MissCatAccountSummary,
        home: HomeViewController?,
        dismiss: @escaping () -> Void
    ) -> AnyView {
        guard let owner = Cache.UserDefaults.shared.getUser(userId: account.id),
              let userID = profileUserID(for: account, owner: owner),
              let token = owner.apiKey,
              !token.isEmpty
        else {
            return AnyView(MissCatSettingsErrorState(
                message: MissCatAccountManagementError.accountNotFound.localizedDescription,
                palette: currentPalette,
                retry: dismiss
            ))
        }
        let profileAccount = MissCatProfileAccount(
            userID: owner.userId,
            instance: owner.instance,
            token: token
        )
        let store = MissCatProfileStore(account: profileAccount, userID: userID)
        return AnyView(MissCatProfileScreen(
            store: store,
            palette: currentPalette,
            onBack: dismiss,
            onOpenURL: { [weak home] url in home?.openLink(url: url.absoluteString) },
            onOpenImage: { [weak home] url in home?.showImage([url], start: 0) },
            onSelectUser: { [weak home] selectedUserID in
                home?.move2Profile(userId: selectedUserID, owner: owner)
            },
            onOpenSettings: { [weak home] in home?.openSettings() },
            onSelectRoot: { [weak home] section in
                switch section {
                case .home: home?.emulateFooterTabTap(tab: .home)
                case .notifications: home?.emulateFooterTabTap(tab: .notifications)
                case .messages: home?.emulateFooterTabTap(tab: .messages)
                case .profile: dismiss()
                }
            },
            onCompose: { [weak home] in home?.tappedPost() }
        ))
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
        .overlay(alignment: .bottomTrailing) {
            Text("ready")
                .font(.system(size: 1))
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .accessibilityIdentifier("accounts.add.flow")
        }
    }
}

struct MissCatAddAccountSheet: View {
    @StateObject private var model = MissCatAddAccountModel()
    let allowsCancel: Bool
    let onSuccess: () -> Void
    let onCancel: () -> Void

    var body: some View {
        MissCatAddAccountView(
            model: model,
            allowsCancel: allowsCancel,
            onSuccess: onSuccess,
            onCancel: onCancel
        )
    }
}

#if DEBUG
enum MissCatAccountsSettingsAcceptanceLaunch {
    enum Screen: String {
        case accounts
        case accountsEmpty = "accounts-empty"
        case accountsError = "accounts-error"
        case settingsRoot = "settings-root"
        case design
        case reactionInstances = "reaction-instances"
        case reactions
        case licenses
        case licenseDetail = "license-detail"
        case about
    }

    static let launchArgument = "--swiftui-accounts-settings-acceptance"
    static var isRequested: Bool { CommandLine.arguments.contains(launchArgument) }

    static var screen: Screen {
        guard let index = CommandLine.arguments.firstIndex(of: "--swiftui-accounts-settings-screen"),
              CommandLine.arguments.indices.contains(index + 1),
              let value = Screen(rawValue: CommandLine.arguments[index + 1])
        else { return .accounts }
        return value
    }
}

@MainActor
struct MissCatAccountsSettingsAcceptanceView: View {
    @StateObject private var accountStore: MissCatAccountStore
    @StateObject private var designStore: MissCatDesignSettingsStore
    @StateObject private var reactionStore: MissCatReactionSettingsStore

    private let screen: MissCatAccountsSettingsAcceptanceLaunch.Screen
    private let palette = MissCatVisualPalette.legacyLight
    private let licenses = [
        MissCatLicenseEntry(name: "Alamofire", text: "Copyright (c) Alamofire Software Foundation\n\nPermission is hereby granted, free of charge, to any person obtaining a copy."),
        MissCatLicenseEntry(name: "MisskeyKit", text: "MIT License\n\nCopyright (c) MisskeyKit contributors\n\nPermission is hereby granted, free of charge."),
        MissCatLicenseEntry(name: "RxSwift", text: "Copyright (c) ReactiveX\n\nLicensed under the MIT License.")
    ]

    init() {
        let screen = MissCatAccountsSettingsAcceptanceLaunch.screen
        let accountMode: MissCatSettingsFixtureRepository.AccountMode
        switch screen {
        case .accountsEmpty: accountMode = .empty
        case .accountsError: accountMode = .failOnce
        default: accountMode = .populated
        }
        let repository = MissCatSettingsFixtureRepository(accountMode: accountMode)
        self.screen = screen
        _accountStore = StateObject(wrappedValue: MissCatAccountStore(repository: repository))
        _designStore = StateObject(wrappedValue: MissCatDesignSettingsStore(repository: repository))
        _reactionStore = StateObject(wrappedValue: MissCatReactionSettingsStore(repository: repository))
    }

    @ViewBuilder
    var body: some View {
        switch screen {
        case .accounts, .accountsEmpty, .accountsError:
            MissCatAccountsRootView(
                store: accountStore,
                palette: palette,
                profileDestination: { account, dismiss in
                    AnyView(MissCatAcceptanceAccountProfile(account: account, dismiss: dismiss))
                }
            )
        case .settingsRoot:
            settingsRoot
        case .design:
            NavigationStack {
                MissCatDesignSettingsScreen(store: designStore, palette: palette) {}
            }
        case .reactionInstances:
            NavigationStack {
                MissCatReactionInstanceScreen(store: reactionStore, palette: palette)
            }
        case .reactions:
            NavigationStack {
                MissCatReactionSettingsScreen(
                    store: reactionStore,
                    accountID: "fixture-wada",
                    palette: palette
                )
            }
        case .licenses:
            NavigationStack {
                MissCatLicensesScreen(entries: licenses, palette: palette)
            }
        case .licenseDetail:
            NavigationStack {
                MissCatLicenseDetailScreen(
                    entry: licenses.first(where: { $0.name == "MisskeyKit" }),
                    palette: palette
                )
            }
        case .about:
            NavigationStack { MissCatAboutScreen(appVersion: "1.0.2") }
        }
    }

    private var settingsRoot: some View {
        MissCatSettingsRootView(
            designStore: designStore,
            reactionStore: reactionStore,
            palette: palette,
            licenses: licenses,
            appVersion: "1.0.2",
            onRootRelaunchRequired: {}
        )
    }
}

private struct MissCatAcceptanceAccountProfile: View {
    let account: MissCatAccountSummary
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 88))
            Text(account.displayName).font(.title2)
            Text("@\(account.username)@\(account.instance)")
            Button("戻る", action: dismiss)
                .accessibilityIdentifier("accounts.profile.back")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        .overlay(alignment: .bottomTrailing) {
            Text("ready")
                .font(.system(size: 1))
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .accessibilityIdentifier("accounts.profile.screen")
        }
    }
}
#endif
