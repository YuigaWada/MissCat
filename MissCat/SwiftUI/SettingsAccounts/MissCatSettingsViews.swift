import SwiftUI

public enum MissCatSettingsLegacyMetrics {
    public static let settingsHeaderHeight: CGFloat = 60
    public static let settingsRowHeight: CGFloat = 43.5
    public static let accountToolbarHeight: CGFloat = 50
    public static let accountCardHeight: CGFloat = 120
    public static let accountHorizontalInset: CGFloat = 10
    public static let accountSpacing: CGFloat = 10
    public static let accountCornerRadius: CGFloat = 8
    public static let accountAvatarDiameter: CGFloat = 50
    public static let reactionGridColumns = 8
    public static let reactionHorizontalInset: CGFloat = 10
    public static let reactionToolbarTop: CGFloat = 40
    public static let emptyImageSize: CGFloat = 170
    public static let emptyImageTop: CGFloat = 180
    public static let aboutLogoHeight: CGFloat = 112
    public static let aboutLogoTop: CGFloat = 170
    public static let aboutDeveloperRowHeight: CGFloat = 70
}

private struct MissCatSettingsVisualReadyMarker: View {
    let ready: Bool
    let identifier: String

    var body: some View {
        Text(ready ? "ready" : "waiting")
            .font(.system(size: 1))
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .accessibilityLabel("visualReady")
            .accessibilityValue(ready ? "true" : "false")
            .accessibilityIdentifier(identifier)
    }
}

@MainActor
final class MissCatReactionMediaReadiness: ObservableObject {
    @Published private(set) var isReady = false
    @Published private(set) var failureMessage: String?

    private var pending: Set<String> = []
    private var completed: Set<String> = []
    private var failed: Set<String> = []
    private var registrationPassCompleted = false

    func register(_ id: String) {
        guard !completed.contains(id), !failed.contains(id) else { return }
        pending.insert(id)
        isReady = false
    }

    func complete(_ id: String, succeeded: Bool) {
        pending.remove(id)
        if succeeded {
            completed.insert(id)
            failed.remove(id)
        } else {
            failed.insert(id)
            failureMessage = "リアクション画像を読み込めませんでした"
        }
        updateReadiness()
    }

    func finishInitialRegistrationPass() {
        registrationPassCompleted = true
        updateReadiness()
    }

    private func updateReadiness() {
        isReady = registrationPassCompleted && pending.isEmpty && failed.isEmpty
    }
}

public struct MissCatSettingsEmptyState: View {
    public let title: String
    public let message: String
    public let palette: MissCatVisualPalette

    public init(title: String = "No Data", message: String, palette: MissCatVisualPalette) {
        self.title = title
        self.message = message
        self.palette = palette
    }

    public var body: some View {
        VStack(spacing: 8) {
            Image("Sad_Ai")
                .resizable()
                .scaledToFit()
                .frame(
                    width: MissCatSettingsLegacyMetrics.emptyImageSize,
                    height: MissCatSettingsLegacyMetrics.emptyImageSize
                )
                .accessibilityHidden(true)

            Text(title)
                .font(.system(size: 17))

            Text(message)
                .font(.system(size: 17))
        }
        .foregroundStyle(palette.muted)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, MissCatSettingsLegacyMetrics.emptyImageTop)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settings.empty")
    }
}

public struct MissCatSettingsErrorState: View {
    public let message: String
    public let palette: MissCatVisualPalette
    public let retry: () -> Void

    public init(message: String, palette: MissCatVisualPalette, retry: @escaping () -> Void) {
        self.message = message
        self.palette = palette
        self.retry = retry
    }

    public var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "xmark.circle")
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(.red)
            Text("エラー")
                .font(.headline)
            Text(message)
                .font(.system(size: 15))
                .multilineTextAlignment(.center)
            Button("再試行", action: retry)
                .buttonStyle(.borderedProminent)
                .tint(palette.accent)
        }
        .foregroundStyle(palette.text)
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.error")
    }
}

public struct MissCatSettingsBanner: View {
    public let message: String
    public let palette: MissCatVisualPalette
    public let dismiss: () -> Void

    public init(message: String, palette: MissCatVisualPalette, dismiss: @escaping () -> Void) {
        self.message = message
        self.palette = palette
        self.dismiss = dismiss
    }

    public var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
            Text(message)
                .font(.system(size: 14, weight: .medium))
            Spacer(minLength: 0)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("閉じる")
        }
        .foregroundStyle(palette.text)
        .padding(.leading, 14)
        .padding(.trailing, 7)
        .frame(minHeight: 50)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(palette.border, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
        .accessibilityIdentifier("settings.banner")
    }
}

public struct MissCatAccountsScreen: View {
    @ObservedObject private var store: MissCatAccountStore
    private let palette: MissCatVisualPalette
    private let onAddAccount: () -> Void
    private let onOpenProfile: (MissCatAccountSummary) -> Void
    private let onAccountSwitched: () -> Void
    private let onConfiguredTabsChanged: () -> Void

    public init(
        store: MissCatAccountStore,
        palette: MissCatVisualPalette = .legacyLight,
        onAddAccount: @escaping () -> Void,
        onOpenProfile: @escaping (MissCatAccountSummary) -> Void,
        onAccountSwitched: @escaping () -> Void,
        onConfiguredTabsChanged: @escaping () -> Void
    ) {
        self.store = store
        self.palette = palette
        self.onAddAccount = onAddAccount
        self.onOpenProfile = onOpenProfile
        self.onAccountSwitched = onAccountSwitched
        self.onConfiguredTabsChanged = onConfiguredTabsChanged
    }

    public var body: some View {
        ZStack(alignment: .top) {
            palette.base.ignoresSafeArea()
            VStack(spacing: 0) {
                accountToolbar
                accountContent
            }

            if case let .banner(message) = store.presentation {
                MissCatSettingsBanner(message: message, palette: palette) {
                    store.dismissPresentation()
                }
                .padding(.horizontal, 12)
                .padding(.top, MissCatSettingsLegacyMetrics.accountToolbarHeight + 4)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .foregroundStyle(palette.text)
        .tint(palette.accent)
        .task { store.load() }
        .alert(
            "本当に削除しますか？",
            isPresented: Binding(
                get: { store.accountPendingDeletion != nil },
                set: { if !$0 { store.cancelDeletion() } }
            )
        ) {
            Button("閉じる", role: .cancel) { store.cancelDeletion() }
            Button("はい", role: .destructive) {
                store.confirmDeletion(onConfiguredTabsChanged: onConfiguredTabsChanged)
            }
        }
        .alert(
            "エラー",
            isPresented: Binding(
                get: {
                    if case .error = store.presentation { return true }
                    return false
                },
                set: { if !$0 { store.dismissPresentation() } }
            )
        ) {
            Button("閉じる", role: .cancel) { store.dismissPresentation() }
        } message: {
            if case let .error(_, message) = store.presentation { Text(message) }
        }
        .overlay(alignment: .bottomTrailing) {
            MissCatSettingsVisualReadyMarker(
                ready: store.phase != .idle && store.phase != .loading,
                identifier: "accounts.visualReady"
            )
        }
    }

    private var accountToolbar: some View {
        HStack(spacing: 10) {
            Spacer()
            Button("アカウントを追加", action: onAddAccount)
                .accessibilityIdentifier("accounts.add")
            Button(store.isEditing ? "完了" : "編集") {
                withAnimation(.easeInOut(duration: 0.2)) { store.isEditing.toggle() }
            }
            .accessibilityIdentifier("accounts.edit")
        }
        .font(.system(size: 17))
        .padding(.trailing, 25)
        .frame(height: MissCatSettingsLegacyMetrics.accountToolbarHeight)
    }

    @ViewBuilder
    private var accountContent: some View {
        switch store.phase {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("読み込み中")
                .accessibilityIdentifier("accounts.loading")
        case let .failed(message):
            MissCatSettingsErrorState(message: message, palette: palette, retry: store.retry)
        case .loaded:
            if store.accounts.isEmpty {
                MissCatSettingsEmptyState(message: "アカウントがありません", palette: palette)
            } else {
                ScrollView {
                    LazyVStack(spacing: MissCatSettingsLegacyMetrics.accountSpacing) {
                        ForEach(store.accounts) { account in
                            accountCard(account)
                        }
                    }
                    .padding(.horizontal, MissCatSettingsLegacyMetrics.accountHorizontalInset)
                    .padding(.bottom, 10)
                }
                .refreshable { store.load() }
                .accessibilityIdentifier("accounts.list")
            }
        }
    }

    private func accountCard(_ account: MissCatAccountSummary) -> some View {
        let isCurrent = store.currentAccountID == account.id
        return HStack(spacing: 13) {
            Button { onOpenProfile(account) } label: {
                HStack(spacing: 13) {
                    avatar(account)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(account.displayName)
                            .font(.custom("Helvetica", size: 15))
                            .lineLimit(1)
                        Text("@\(account.username)")
                            .font(.custom("Helvetica", size: 10))
                            .lineLimit(1)
                        Text(account.instance)
                            .font(.custom("Helvetica", size: 13))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("@\(account.username)、\(account.instance)のプロフィール")
            .accessibilityIdentifier("accounts.profile.\(account.id)")

            if store.isEditing {
                Button(role: .destructive) { store.requestDeletion(account) } label: {
                    Image(systemName: "trash.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .disabled(store.busyAccountID != nil)
                .accessibilityLabel("アカウントを削除")
                .accessibilityIdentifier("accounts.delete.\(account.id)")
            } else {
                Button {
                    store.switchAccount(id: account.id, onSwitched: onAccountSwitched)
                } label: {
                    Group {
                        if store.busyAccountID == account.id {
                            ProgressView()
                        } else {
                            Image(systemName: isCurrent ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 25))
                        }
                    }
                    .frame(width: 34, height: 44)
                }
                .buttonStyle(.plain)
                .disabled(isCurrent || store.busyAccountID != nil)
                .accessibilityLabel(isCurrent ? "現在のアカウント" : "このアカウントに切り替える")
                .accessibilityIdentifier("accounts.switch.\(account.id)")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: MissCatSettingsLegacyMetrics.accountCardHeight - 10)
        .background(palette.base)
        .overlay {
            RoundedRectangle(cornerRadius: MissCatSettingsLegacyMetrics.accountCornerRadius)
                .stroke(palette.accent, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: MissCatSettingsLegacyMetrics.accountCornerRadius))
        .overlay(alignment: .bottomTrailing) {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityIdentifier("accounts.card.\(account.id)")
        }
    }

    @ViewBuilder
    private func avatar(_ account: MissCatAccountSummary) -> some View {
        AsyncImage(url: account.avatarURL) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .foregroundStyle(palette.muted)
        }
        .frame(
            width: MissCatSettingsLegacyMetrics.accountAvatarDiameter,
            height: MissCatSettingsLegacyMetrics.accountAvatarDiameter
        )
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

/// SwiftUI-owned Accounts navigation. UIKit may host this view while the
/// application shell is retired, but add-account and profile destinations stay
/// inside this typed SwiftUI navigation tree.
public struct MissCatAccountsRootView: View {
    @State private var path: [MissCatAccountsRoute] = []
    @State private var addAccountPresentation: AddAccountPresentation?

    @StateObject private var store: MissCatAccountStore
    private let palette: MissCatVisualPalette
    private let profileDestination: (MissCatAccountSummary, @escaping () -> Void) -> AnyView
    private let onAccountSwitched: () -> Void
    private let onConfiguredTabsChanged: () -> Void
    private let automaticallyPresentsRequiredAccountRecovery: Bool

    public init(
        store: MissCatAccountStore,
        palette: MissCatVisualPalette = .legacyLight,
        profileDestination: @escaping (MissCatAccountSummary, @escaping () -> Void) -> AnyView,
        onAccountSwitched: @escaping () -> Void = {},
        onConfiguredTabsChanged: @escaping () -> Void = {},
        automaticallyPresentsRequiredAccountRecovery: Bool = true
    ) {
        _store = StateObject(wrappedValue: store)
        self.palette = palette
        self.profileDestination = profileDestination
        self.onAccountSwitched = onAccountSwitched
        self.onConfiguredTabsChanged = onConfiguredTabsChanged
        self.automaticallyPresentsRequiredAccountRecovery = automaticallyPresentsRequiredAccountRecovery
    }

    public var body: some View {
        NavigationStack(path: $path) {
            MissCatAccountsScreen(
                store: store,
                palette: palette,
                onAddAccount: { addAccountPresentation = .cancelable },
                onOpenProfile: { path.append(.profile(accountID: $0.id)) },
                onAccountSwitched: onAccountSwitched,
                onConfiguredTabsChanged: onConfiguredTabsChanged
            )
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: MissCatAccountsRoute.self) { route in
                switch route {
                case let .profile(accountID):
                    if let account = store.accounts.first(where: { $0.id == accountID }) {
                        profileDestination(account) {
                            if !path.isEmpty { path.removeLast() }
                        }
                    } else {
                        MissCatSettingsErrorState(
                            message: MissCatAccountManagementError.accountNotFound.localizedDescription,
                            palette: palette,
                            retry: {
                                if !path.isEmpty { path.removeLast() }
                            }
                        )
                    }
                }
            }
        }
        .tint(palette.accent)
        .onChange(of: store.requiresAccountRecovery, initial: true) { _, requiresRecovery in
            guard automaticallyPresentsRequiredAccountRecovery, requiresRecovery else { return }
            addAccountPresentation = .required
        }
        .fullScreenCover(item: $addAccountPresentation) { presentation in
            MissCatAddAccountSheet(
                allowsCancel: presentation == .cancelable,
                onSuccess: {
                    addAccountPresentation = nil
                    store.load()
                    onAccountSwitched()
                },
                onCancel: { addAccountPresentation = nil }
            )
            .interactiveDismissDisabled(presentation == .required)
        }
    }

    private enum AddAccountPresentation: String, Identifiable {
        case cancelable
        case required

        var id: String { rawValue }
    }
}

public struct MissCatSettingsRootView: View {
    @State private var path: [MissCatSettingsRoute] = []
    @StateObject private var designStore: MissCatDesignSettingsStore
    @StateObject private var reactionStore: MissCatReactionSettingsStore

    private let palette: MissCatVisualPalette
    private let licenses: [MissCatLicenseEntry]
    private let appVersion: String
    private let onRootRelaunchRequired: () -> Void
    private let onClose: () -> Void

    public init(
        designStore: MissCatDesignSettingsStore,
        reactionStore: MissCatReactionSettingsStore,
        palette: MissCatVisualPalette = .legacyLight,
        licenses: [MissCatLicenseEntry],
        appVersion: String,
        onRootRelaunchRequired: @escaping () -> Void,
        onClose: @escaping () -> Void = {}
    ) {
        _designStore = StateObject(wrappedValue: designStore)
        _reactionStore = StateObject(wrappedValue: reactionStore)
        self.palette = palette
        self.licenses = licenses.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        self.appVersion = appVersion
        self.onRootRelaunchRequired = onRootRelaunchRequired
        self.onClose = onClose
    }

    public var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                HStack {
                    Text("MissCat")
                        .font(.system(size: 17))
                    Spacer()
                }
                .padding(.horizontal, 20)
                .frame(height: MissCatSettingsLegacyMetrics.settingsHeaderHeight)

                VStack(spacing: 0) {
                    settingsRow(title: "デザイン", symbol: "drafting-compass", route: .design, id: "settings.design")
                    settingsRow(title: "リアクション", symbol: "flame.fill", route: .reactionInstances, id: "settings.reactions")
                    settingsRow(title: "LICENSE", symbol: "person.text.rectangle", route: .licenses, id: "settings.licenses")
                    settingsRow(title: "MissCatについて", symbol: "cat.fill", route: .about, id: "settings.about")
                }
                Spacer()
            }
            .background(palette.base.ignoresSafeArea())
            .foregroundStyle(palette.text)
            .navigationDestination(for: MissCatSettingsRoute.self) { route in
                destination(route)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onClose) {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("戻る")
                    .accessibilityIdentifier("settings.close")
                }
            }
            .overlay(alignment: .bottomTrailing) {
                MissCatSettingsVisualReadyMarker(ready: true, identifier: "settings.root.visualReady")
            }
        }
        .tint(palette.accent)
    }

    private func settingsRow(
        title: String,
        symbol: String,
        route: MissCatSettingsRoute,
        id: String
    ) -> some View {
        Button { path.append(route) } label: {
            HStack(spacing: 20) {
                Image(systemName: symbol)
                    .font(.system(size: 23))
                    .frame(width: 32)
                Text(title)
                    .font(.system(size: 17))
                Spacer()
            }
            .padding(.horizontal, 20)
            .frame(height: MissCatSettingsLegacyMetrics.settingsRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    @ViewBuilder
    private func destination(_ route: MissCatSettingsRoute) -> some View {
        switch route {
        case .design:
            MissCatDesignSettingsScreen(
                store: designStore,
                palette: palette,
                onRootRelaunchRequired: onRootRelaunchRequired
            )
        case .reactionInstances:
            MissCatReactionInstanceScreen(store: reactionStore, palette: palette)
        case let .reactions(accountID):
            MissCatReactionSettingsScreen(store: reactionStore, accountID: accountID, palette: palette)
        case .licenses:
            MissCatLicensesScreen(entries: licenses, palette: palette)
        case let .license(name):
            MissCatLicenseDetailScreen(
                entry: licenses.first(where: { $0.name == name }),
                palette: palette
            )
        case .about:
            MissCatAboutScreen(appVersion: appVersion)
        }
    }
}

public struct MissCatDesignSettingsScreen: View {
    @ObservedObject private var store: MissCatDesignSettingsStore
    @Environment(\.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var editMode: EditMode = .inactive
    @State private var showsAccentPicker = false
    private let palette: MissCatVisualPalette
    private let onRootRelaunchRequired: () -> Void

    public init(
        store: MissCatDesignSettingsStore,
        palette: MissCatVisualPalette,
        onRootRelaunchRequired: @escaping () -> Void
    ) {
        self.store = store
        self.palette = palette
        self.onRootRelaunchRequired = onRootRelaunchRequired
    }

    public var body: some View {
        designList
        .listStyle(.insetGrouped)
        .contentMargins(.top, 17, for: .scrollContent)
        .foregroundStyle(palette.text)
        .navigationTitle("デザイン")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.white, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .environment(\.editMode, $editMode)
        .toolbar {
            if editMode.isEditing {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完了") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            editMode = .inactive
                        }
                    }
                    .accessibilityIdentifier("settings.design.edit")
                }
            }
        }
        .task { store.load() }
        .onDisappear { store.save(onRootRelaunchRequired: onRootRelaunchRequired) }
        .overlay { progressOverlay }
        .alert(
            "エラー",
            isPresented: errorIsPresented
        ) {
            Button("再試行") { store.retrySave() }
            Button("閉じる", role: .cancel) { store.dismissPresentation() }
        } message: {
            errorMessage
        }
        .overlay(alignment: .bottomTrailing) {
            MissCatSettingsVisualReadyMarker(
                ready: store.isReady && !store.isSaving,
                identifier: "settings.design.visualReady"
            )
        }
        .sheet(isPresented: $showsAccentPicker) {
            NavigationStack {
                SwiftUI.ColorPicker("メインカラー", selection: accentBinding, supportsOpacity: false)
                    .padding(20)
                    .navigationTitle("メインカラー")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完了") { showsAccentPicker = false }
                        }
                    }
            }
            .presentationDetents([.medium])
        }
    }

    private var designList: some View {
        List {
            tabSettingsSection
            Section(header: Text("テーマ設定"), footer: EmptyView()) {
                HStack {
                    Text("カラーモード")
                    Spacer()
                    ForEach(MissCatThemeMode.allCases) { mode in
                        Button(mode.rawValue) { store.updateMode(mode) }
                            .foregroundStyle(palette.muted)
                            .frame(width: 55)
                            .accessibilityIdentifier("settings.design.color-mode.\(mode.rawValue.lowercased())")
                    }
                }

                Button { showsAccentPicker = true } label: {
                    HStack {
                        Text("メインカラー")
                            .foregroundStyle(palette.text)
                        Spacer()
                        Circle()
                            .fill(Color(hex: store.accentHex))
                            .frame(width: 28, height: 28)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.design.color-picker")

                HStack {
                    Text("HEX")
                    TextField("2F7CF6", text: accentHexBinding)
                        .foregroundStyle(palette.muted)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                        .submitLabel(.done)
                        .onSubmit { _ = store.commitAccentHexDraft() }
                        .accessibilityIdentifier("settings.design.color-hex")
                }
            }
        }
    }

    private var tabSettingsSection: some View {
        Section {
            ForEach(store.tabs) { tab in
                tabRow(tab)
                    .listRowBackground(cellBackground)
            }
            .onMove(perform: store.moveTabs)
            .onDelete(perform: store.removeTabs)

            Menu("タブを追加") {
                ForEach(addableTabKinds) { kind in
                    Button(kind.legacyTitle) {
                        store.addTab(kind: kind, accountID: store.accounts.first?.id)
                    }
                }
            }
            .tint(palette.accent)
            .accessibilityIdentifier("settings.design.add-tab")
        } header: {
            Text("上タブ設定")
        } footer: {
            Text("タップで表示名を変更することができます")
        }
    }

    private func tabRow(_ tab: MissCatSettingsTab) -> some View {
        Group {
            if editMode.isEditing {
                editableTabRow(tab)
            } else {
                HStack(spacing: 10) {
                    Text(tab.kind.legacyTitle)
                        .frame(width: 70, alignment: .leading)
                    Text(tab.name)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .onTapGesture { editMode = .active }
            }
        }
    }

    private func editableTabRow(_ tab: MissCatSettingsTab) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                Text(tab.kind.legacyTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 70, alignment: .leading)
                TextField(tab.kind.defaultName, text: tabNameBinding(for: tab))
                    .accessibilityIdentifier("settings.design.tab-name.\(tab.id)")
            }

            if store.accounts.count > 1 {
                Picker("アカウント", selection: tabOwnerBinding(for: tab)) {
                    ForEach(store.accounts) { account in
                        Text("@\(account.username)@\(account.instance)").tag(account.id)
                    }
                }
                .font(.system(size: 12))
            }
        }
    }

    @ViewBuilder private var progressOverlay: some View {
        if store.isLoading || store.isSaving {
            ProgressView()
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("settings.design.progress")
        }
    }

    @ViewBuilder private var errorMessage: some View {
        if case let .error(_, message) = store.presentation {
            Text(message)
        }
    }

    private var addableTabKinds: [MissCatSettingsTabKind] {
        MissCatSettingsTabKind.allCases
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { if case .error = store.presentation { return true }; return false },
            set: { if !$0 { store.dismissPresentation() } }
        )
    }

    private var accentHexBinding: Binding<String> {
        Binding(
            get: { store.accentHexDraft },
            set: { store.updateAccentHexDraft($0) }
        )
    }

    private func tabNameBinding(for tab: MissCatSettingsTab) -> Binding<String> {
        Binding(
            get: { tab.name },
            set: { store.updateName(id: tab.id, name: $0) }
        )
    }

    private func tabOwnerBinding(for tab: MissCatSettingsTab) -> Binding<String> {
        Binding(
            get: { tab.accountID ?? store.accounts.first?.id ?? "" },
            set: { updateOwner(tabID: tab.id, ownerID: $0) }
        )
    }

    private var cellBackground: Color {
        store.mode == .light ? palette.base : palette.surface
    }

    private var accentBinding: Binding<Color> {
        Binding(
            get: { Color(hex: store.accentHex) },
            set: { color in
                let resolved = color.resolve(in: environment)
                let red = Int((resolved.red * 255).rounded())
                let green = Int((resolved.green * 255).rounded())
                let blue = Int((resolved.blue * 255).rounded())
                store.setAccentHex(String(format: "%02X%02X%02X", red, green, blue))
            }
        )
    }

    private func updateOwner(tabID: UUID, ownerID: String) {
        store.updateOwner(tabID: tabID, accountID: ownerID)
    }
}

public struct MissCatReactionInstanceScreen: View {
    @ObservedObject private var store: MissCatReactionSettingsStore
    private let palette: MissCatVisualPalette

    public init(
        store: MissCatReactionSettingsStore,
        palette: MissCatVisualPalette
    ) {
        self.store = store
        self.palette = palette
    }

    public var body: some View {
        Group {
            if store.isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.accounts.isEmpty {
                MissCatSettingsEmptyState(message: "インスタンスがありません", palette: palette)
            } else {
                List(store.accounts) { account in
                    NavigationLink(value: MissCatSettingsRoute.reactions(accountID: account.id)) {
                        Text(account.instance)
                            .font(.system(size: 17, weight: .bold))
                        .frame(minHeight: 44)
                    }
                    .listRowBackground(palette.base)
                    .accessibilityIdentifier("settings.reactions.instance.\(account.id)")
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(palette.base)
        .foregroundStyle(palette.text)
        .navigationTitle("お気に入りの絵文字")
        .navigationBarTitleDisplayMode(.inline)
        .task { store.loadAccounts() }
        .overlay(alignment: .bottomTrailing) {
            MissCatSettingsVisualReadyMarker(
                ready: !store.isLoading,
                identifier: "settings.reactions.instances.visualReady"
            )
        }
    }
}

public struct MissCatReactionSettingsScreen: View {
    @ObservedObject private var store: MissCatReactionSettingsStore
    private let accountID: String
    private let palette: MissCatVisualPalette

    public init(store: MissCatReactionSettingsStore, accountID: String, palette: MissCatVisualPalette) {
        self.store = store
        self.accountID = accountID
        self.palette = palette
    }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: 0),
            count: MissCatSettingsLegacyMetrics.reactionGridColumns
        )
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 13) {
                Button { store.showsPicker = true } label: {
                    Image(systemName: "plus")
                        .frame(width: 30, height: 30)
                }
                .accessibilityLabel("リアクションを追加")
                .accessibilityIdentifier("settings.reactions.add")

                Button { store.isEditing.toggle() } label: {
                    Image(systemName: "minus")
                        .frame(width: 30, height: 30)
                }
                .accessibilityLabel("リアクションを削除")
                .accessibilityIdentifier("settings.reactions.remove-mode")

                Spacer()
                Text("長押しで順序を変更できます")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.muted)
            }
            .padding(.horizontal, 20)
            .padding(.top, MissCatSettingsLegacyMetrics.reactionToolbarTop)
            .padding(.bottom, 15)

            if store.isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.favorites.isEmpty {
                MissCatSettingsEmptyState(message: "お気に入りがありません", palette: palette)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 0) {
                        ForEach(store.favorites) { item in
                            reactionCell(item)
                                .onDrag { NSItemProvider(object: item.id as NSString) }
                                .onDrop(of: [.text], delegate: MissCatReactionDropDelegate(
                                    item: item,
                                    items: store.favorites,
                                    move: store.move
                                ))
                        }
                    }
                    .padding(.horizontal, MissCatSettingsLegacyMetrics.reactionHorizontalInset)
                }
            }
        }
        .background(palette.base)
        .foregroundStyle(palette.text)
        .tint(palette.accent)
        .navigationTitle(store.snapshot?.account.instance ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task { store.load(accountID: accountID) }
        .onDisappear { store.saveIfNeeded() }
        .sheet(isPresented: $store.showsPicker) {
            MissCatReactionPicker(
                sections: store.pickerSections,
                searchQuery: $store.searchQuery,
                palette: palette,
                onSelect: store.add
            )
        }
        .alert(
            "エラー",
            isPresented: Binding(
                get: { if case .error = store.presentation { return true }; return false },
                set: { if !$0 { store.dismissPresentation() } }
            )
        ) {
            Button("再試行") { store.retrySave() }
            Button("閉じる", role: .cancel) { store.dismissPresentation() }
        } message: {
            if case let .error(_, message) = store.presentation { Text(message) }
        }
        .overlay(alignment: .bottomTrailing) {
            MissCatSettingsVisualReadyMarker(
                ready: !store.isLoading && store.snapshot != nil && !store.isSaving,
                identifier: "settings.reactions.visualReady"
            )
        }
    }

    private func reactionCell(_ item: MissCatReactionItem) -> some View {
        Button {
            if store.isEditing { store.remove(item) }
        } label: {
            Group {
                if let url = item.imageURL {
                    MissCatReactionImage(url: url)
                } else {
                    Text(item.displayValue ?? item.rawValue)
                        .font(.system(size: 30))
                        .minimumScaleFactor(0.4)
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .overlay(alignment: .topTrailing) {
                if store.isEditing {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.rawValue)
        .accessibilityIdentifier("settings.reactions.item.\(item.id)")
    }
}

private struct MissCatReactionDropDelegate: DropDelegate {
    let item: MissCatReactionItem
    let items: [MissCatReactionItem]
    let move: (IndexSet, Int) -> Void

    func dropEntered(info: DropInfo) {
        guard let sourceID = info.itemProviders(for: [.text]).first,
              sourceID.canLoadObject(ofClass: NSString.self)
        else { return }
        sourceID.loadObject(ofClass: NSString.self) { object, _ in
            guard let id = object as? String,
                  let source = items.firstIndex(where: { $0.id == id }),
                  let target = items.firstIndex(of: item),
                  source != target
            else { return }
            Task { @MainActor in
                move(IndexSet(integer: source), target > source ? target + 1 : target)
            }
        }
    }

    func performDrop(info: DropInfo) -> Bool { true }
}

public struct MissCatReactionPicker: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var mediaReadiness = MissCatReactionMediaReadiness()
    public let sections: [MissCatReactionSection]
    @Binding public var searchQuery: String
    public let palette: MissCatVisualPalette
    public let onSelect: (MissCatReactionItem) -> Void

    public init(
        sections: [MissCatReactionSection],
        searchQuery: Binding<String>,
        palette: MissCatVisualPalette,
        onSelect: @escaping (MissCatReactionItem) -> Void
    ) {
        self.sections = sections
        _searchQuery = searchQuery
        self.palette = palette
        self.onSelect = onSelect
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(section.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(palette.muted)
                                .accessibilityIdentifier("settings.reactions.section.\(section.id)")
                            LazyVGrid(
                                columns: Array(repeating: GridItem(.flexible()), count: 7),
                                spacing: 8
                            ) {
                                ForEach(section.items) { item in
                                    let renderedMediaID = "\(section.id)|\(item.id)"
                                    Button {
                                        onSelect(item)
                                        dismiss()
                                    } label: {
                                        Group {
                                            if let url = item.imageURL {
                                                MissCatReactionImage(url: url) { succeeded in
                                                    mediaReadiness.complete(
                                                        renderedMediaID,
                                                        succeeded: succeeded
                                                    )
                                                }
                                                .onAppear { mediaReadiness.register(renderedMediaID) }
                                            } else {
                                                Text(item.displayValue ?? item.rawValue).font(.system(size: 28))
                                            }
                                        }
                                        .frame(maxWidth: .infinity)
                                        .aspectRatio(1, contentMode: .fit)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(item.rawValue)
                                    .accessibilityIdentifier("settings.reactions.picker.item.\(item.id)")
                                }
                            }
                        }
                    }
                }
                .padding(10)
            }
            .background(palette.base)
            .navigationTitle("リアクションを追加")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchQuery, prompt: "絵文字を検索")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .task {
            // Allow the first lazy layout pass to register every custom-media cell
            // that SwiftUI actually rendered before exposing screenshot readiness.
            await Task.yield()
            await Task.yield()
            mediaReadiness.finishInitialRegistrationPass()
        }
        .overlay(alignment: .bottomTrailing) {
            MissCatSettingsVisualReadyMarker(
                ready: mediaReadiness.isReady,
                identifier: "settings.reactions.picker.visualReady"
            )
        }
        .overlay(alignment: .bottom) {
            if let failureMessage = mediaReadiness.failureMessage {
                Text(failureMessage)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.92), in: Capsule())
                    .padding(.bottom, 8)
                    .accessibilityIdentifier("settings.reactions.picker.mediaError")
            }
        }
    }
}

private struct MissCatReactionImage: View {
    let url: URL
    var onLoad: ((Bool) -> Void)?
    @State private var reportedURL: URL?

    init(url: URL, onLoad: ((Bool) -> Void)? = nil) {
        self.url = url
        self.onLoad = onLoad
    }

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case let .success(image):
                image
                    .resizable()
                    .scaledToFit()
                    .onAppear { report(success: true) }
            case .failure:
                Image(systemName: "exclamationmark.triangle")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .onAppear { report(success: false) }
            case .empty:
                ProgressView()
            @unknown default:
                EmptyView()
            }
        }
    }

    private func report(success: Bool) {
        guard reportedURL != url else { return }
        reportedURL = url
        onLoad?(success)
    }
}

public struct MissCatLicensesScreen: View {
    public let entries: [MissCatLicenseEntry]
    public let palette: MissCatVisualPalette

    public init(
        entries: [MissCatLicenseEntry],
        palette: MissCatVisualPalette
    ) {
        self.entries = entries
        self.palette = palette
    }

    public var body: some View {
        List {
            Section("License") {
                ForEach(entries) { entry in
                    NavigationLink(value: MissCatSettingsRoute.license(name: entry.name)) {
                        Text(entry.name)
                            .font(.system(size: 17, weight: .bold))
                        .frame(height: 60)
                    }
                    .listRowBackground(palette.base)
                    .accessibilityIdentifier("settings.license.\(entry.id)")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(palette.base)
        .foregroundStyle(palette.text)
        .navigationTitle("LICENSE")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottomTrailing) {
            MissCatSettingsVisualReadyMarker(ready: true, identifier: "settings.licenses.visualReady")
        }
    }
}

public struct MissCatLicenseDetailScreen: View {
    @State private var isVisuallyReady = false
    public let entry: MissCatLicenseEntry?
    public let palette: MissCatVisualPalette

    public init(entry: MissCatLicenseEntry?, palette: MissCatVisualPalette) {
        self.entry = entry
        self.palette = palette
    }

    public var body: some View {
        ScrollView {
            Text(entry?.text ?? "")
                .font(.custom("Helvetica", size: 14))
                .foregroundStyle(palette.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .textSelection(.enabled)
        }
        .background(palette.base.ignoresSafeArea())
        .navigationTitle(entry?.name ?? "LICENSE")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: entry?.id) {
            isVisuallyReady = false
            // Let the navigation bar and the text viewport finish their first
            // layout pass before a screenshot consumer observes readiness.
            try? await Task.sleep(nanoseconds: 200_000_000)
            isVisuallyReady = true
        }
        .overlay(alignment: .bottomTrailing) {
            MissCatSettingsVisualReadyMarker(
                ready: isVisuallyReady,
                identifier: "settings.license.detail.visualReady"
            )
        }
    }
}

public struct MissCatAboutScreen: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var appeared = false
    @State private var animationCompleted = false
    public let appVersion: String

    public init(appVersion: String) {
        self.appVersion = appVersion
    }

    public var body: some View {
        VStack(spacing: 0) {
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color(hex: "ECECEC"))
                                .frame(width: 40, height: 40)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("戻る")
                        Spacer()
                    }
                    .padding(.leading, 7)

                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: MissCatSettingsLegacyMetrics.aboutLogoHeight)
                        .padding(.horizontal, 40)
                        .padding(.top, max(0, MissCatSettingsLegacyMetrics.aboutLogoTop - 40))

                    Text("新しい世界を探検しよう")
                        .font(.system(size: 17))
                        .padding(.top, 3)

                    Spacer()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("開発者")
                            .font(.system(size: 17))
                            .padding(.horizontal, 20)
                        developerRow(
                            title: "YuigaWada",
                            account: "@YuigaWada",
                            url: URL(string: "https://twitter.com/yuigawada")!
                        )
                        developerRow(
                            title: "wada",
                            account: "@wada",
                            url: URL(string: "https://misskey.io/@wada")!
                        )
                    }

                    HStack {
                        Spacer()
                        Text("v\(appVersion)")
                            .font(.system(size: 15))
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 20)
        }
        .foregroundStyle(.white)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : -30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            GeometryReader { proxy in
                legacyGradient(size: proxy.size)
            }
            .ignoresSafeArea()
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            animationCompleted = false
            withAnimation(.easeInOut(duration: 0.7), completionCriteria: .logicallyComplete) {
                appeared = true
            } completion: {
                animationCompleted = true
            }
        }
        .overlay(alignment: .bottomTrailing) {
            MissCatSettingsVisualReadyMarker(
                ready: animationCompleted,
                identifier: "settings.about.visualReady"
            )
        }
    }

    private func legacyGradient(size: CGSize) -> LinearGradient {
        let widthSquared = size.width * size.width
        let heightSquared = size.height * size.height
        let denominator = max(widthSquared + heightSquared, 1)
        let deltaX = 2 * heightSquared / denominator
        let deltaY = -2 * widthSquared / denominator

        return LinearGradient(
            colors: [Color(hex: "4691A3"), Color(hex: "5AB0C5"), Color(hex: "89D5E8")],
            startPoint: UnitPoint(x: 0.5 - deltaX / 2, y: 0.5 - deltaY / 2),
            endPoint: UnitPoint(x: 0.5 + deltaX / 2, y: 0.5 + deltaY / 2)
        )
    }

    private func developerRow(
        title: String,
        account: String,
        url: URL
    ) -> some View {
        Button { openURL(url) } label: {
            HStack(spacing: 13) {
                Image(systemName: "circle")
                    .font(.system(size: 15, weight: .regular))
                    .frame(width: 20, height: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 17))
                    Text(account).font(.system(size: 15))
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .frame(height: MissCatSettingsLegacyMetrics.aboutDeveloperRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)のプロフィールを開く")
        .accessibilityIdentifier("settings.about.\(title.lowercased())")
    }
}
