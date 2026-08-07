import Combine
import SwiftUI


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
            Text(allowsCancel ? "ready" : "required")
                .font(.system(size: 1))
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .accessibilityIdentifier(allowsCancel ? "accounts.add.flow" : "accounts.add.required")
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
        case accountsLastRecovery = "accounts-last-recovery"
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
    private let repository: MissCatSettingsFixtureRepository
    private let licenses: [MissCatLicenseEntry]

    init() {
        let screen = MissCatAccountsSettingsAcceptanceLaunch.screen
        let accountMode: MissCatSettingsFixtureRepository.AccountMode
        switch screen {
        case .accountsEmpty: accountMode = .empty
        case .accountsError: accountMode = .failOnce
        case .accountsLastRecovery: accountMode = .single
        default: accountMode = .populated
        }
        let repository = MissCatSettingsFixtureRepository(accountMode: accountMode)
        self.screen = screen
        self.repository = repository
        licenses = MissCatLicenseCatalog.entries()
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
                },
                automaticallyPresentsRequiredAccountRecovery: screen != .accountsEmpty
            )
        case .accountsLastRecovery:
            MissCatAccountsProductionLifecycleFixture(repository: repository)
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
                    entry: rxSwiftVisualReferenceEntry,
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

    /// The frozen visual contract captures this legacy RxSwift viewport. Ordinary
    /// settings navigation continues to pass the canonical, unabridged catalog
    /// entry to `MissCatLicenseDetailScreen`.
    private var rxSwiftVisualReferenceEntry: MissCatLicenseEntry? {
        MissCatLicenseEntry(
            name: "RxSwift",
            text: """
            The MIT License (MIT)

            Copyright (c) 2015 Krunoslav Zaher

            Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files, to deal in the Software without restriction.
            """
        )
    }
}

private struct MissCatAccountsProductionLifecycleFixture: View {
    @StateObject private var store: MissCatAccountStore

    init(repository: MissCatSettingsFixtureRepository) {
        _store = StateObject(wrappedValue: MissCatAccountStore(repository: repository))
    }

    var body: some View {
        MissCatAccountsRootView(
            store: store,
            profileDestination: { account, dismiss in
                AnyView(MissCatAcceptanceAccountProfile(account: account, dismiss: dismiss))
            }
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
