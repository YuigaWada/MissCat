import SwiftUI

public enum MissCatRootSection: String, CaseIterable, Identifiable, Sendable {
    case home
    case notifications
    case messages
    case profile

    public var id: String { rawValue }

    public var legacyTitle: String {
        switch self {
        case .home: "Home"
        case .notifications: "Notifications"
        case .messages: "Chat"
        case .profile: "Accounts"
        }
    }
}

public struct MissCatTimelineTab: Identifiable, Equatable, Sendable {
    public let id: String
    public var title: String
    public var accessibilityID: String

    public init(id: String, title: String, accessibilityID: String? = nil) {
        self.id = id
        self.title = title
        self.accessibilityID = accessibilityID ?? id
    }

    public static let legacyDefaults = [
        MissCatTimelineTab(id: "home", title: "Home"),
        MissCatTimelineTab(id: "local", title: "Local"),
        MissCatTimelineTab(id: "global", title: "Global")
    ]
}

/// The visual shell shared by the timeline, notifications, chat and account screens.
/// Feature views are injected so this layer has no dependency on the legacy UIKit models.
public struct MissCatMainShellView<Content: View>: View {
    @Binding private var selectedTimelineID: String
    @Binding private var selectedSection: MissCatRootSection

    private let timelineTabs: [MissCatTimelineTab]
    private let palette: MissCatVisualPalette
    private let avatar: Image?
    private let accounts: [MissCatShellAccount]
    private let currentAccountID: String?
    private let bannerMessage: String?
    private let onSearch: () -> Void
    private let onCompose: () -> Void
    private let onSettings: () -> Void
    private let onAccountSelected: (MissCatShellAccountScope) -> Void
    private let onTimelineSelection: (String, MissCatTimelineSelectionOrigin) -> Void
    private let onReselect: (MissCatRootSection) -> Void
    private let onDismissBanner: () -> Void
    private let content: (MissCatRootSection) -> Content

    public init(
        timelineTabs: [MissCatTimelineTab] = MissCatTimelineTab.legacyDefaults,
        selectedTimelineID: Binding<String>,
        selectedSection: Binding<MissCatRootSection>,
        palette: MissCatVisualPalette = .legacyLight,
        avatar: Image? = nil,
        accounts: [MissCatShellAccount] = [],
        currentAccountID: String? = nil,
        bannerMessage: String? = nil,
        onSearch: @escaping () -> Void,
        onCompose: @escaping () -> Void,
        onSettings: @escaping () -> Void = {},
        onAccountSelected: @escaping (MissCatShellAccountScope) -> Void = { _ in },
        onTimelineSelection: @escaping (String, MissCatTimelineSelectionOrigin) -> Void = { _, _ in },
        onReselect: @escaping (MissCatRootSection) -> Void = { _ in },
        onDismissBanner: @escaping () -> Void = {},
        @ViewBuilder content: @escaping (MissCatRootSection) -> Content
    ) {
        self.timelineTabs = timelineTabs
        _selectedTimelineID = selectedTimelineID
        _selectedSection = selectedSection
        self.palette = palette
        self.avatar = avatar
        self.accounts = accounts
        self.currentAccountID = currentAccountID
        self.bannerMessage = bannerMessage
        self.onSearch = onSearch
        self.onCompose = onCompose
        self.onSettings = onSettings
        self.onAccountSelected = onAccountSelected
        self.onTimelineSelection = onTimelineSelection
        self.onReselect = onReselect
        self.onDismissBanner = onDismissBanner
        self.content = content
    }

    public var body: some View {
        VStack(spacing: 0) {
            shellHeader

            content(selectedSection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(palette.base)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("main.content.\(selectedSection.rawValue)")

            MissCatBottomBar(
                selectedSection: $selectedSection,
                palette: palette,
                onCompose: onCompose,
                onReselect: onReselect
            )
        }
        .background(palette.base.ignoresSafeArea())
        .tint(palette.accent)
        .overlay(alignment: .top) {
            if let bannerMessage {
                MissCatFeedStatusBanner(
                    message: bannerMessage,
                    palette: palette,
                    onDismiss: onDismissBanner
                )
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .accessibilityIdentifier("main.banner.error")
            }
        }
        .animation(.easeInOut(duration: 0.2), value: bannerMessage)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("main.shell")
    }

    @ViewBuilder
    private var shellHeader: some View {
        if selectedSection == .home {
            MissCatTimelineTabs(
                tabs: timelineTabs,
                selectedID: $selectedTimelineID,
                palette: palette,
                onSearch: onSearch,
                onSelection: onTimelineSelection
            )
        } else {
            MissCatNavigationHeader(
                title: selectedSection.legacyTitle,
                palette: palette,
                leadingImage: selectedSection == .profile ? nil : avatar,
                accounts: selectedSection == .profile ? [] : accounts,
                currentAccountID: currentAccountID,
                showsSettings: selectedSection == .profile,
                onSettings: onSettings,
                onAccountSelected: onAccountSelected
            )
        }
    }
}

public struct MissCatTimelineTabs: View {
    public let tabs: [MissCatTimelineTab]
    @Binding public var selectedID: String
    public let palette: MissCatVisualPalette
    public let onSearch: () -> Void
    public let onSelection: (String, MissCatTimelineSelectionOrigin) -> Void

    public init(
        tabs: [MissCatTimelineTab],
        selectedID: Binding<String>,
        palette: MissCatVisualPalette = .legacyLight,
        onSearch: @escaping () -> Void,
        onSelection: @escaping (String, MissCatTimelineSelectionOrigin) -> Void = { _, _ in }
    ) {
        self.tabs = tabs
        _selectedID = selectedID
        self.palette = palette
        self.onSearch = onSearch
        self.onSelection = onSelection
    }

    public var body: some View {
        GeometryReader { proxy in
            let searchWidth: CGFloat = 44
            let availableTabWidth = max(0, proxy.size.width - searchWidth)
            let tabWidth = max(110, availableTabWidth / CGFloat(max(1, tabs.count)))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    Button(action: onSearch) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(palette.text)
                            .frame(width: searchWidth, height: MissCatLegacyMetrics.timelineTabsHeight)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("検索")
                    .accessibilityIdentifier("main.timeline.search")

                    ForEach(tabs) { tab in
                        Button {
                            guard selectedID != tab.id else { return }
                            onSelection(tab.id, .tap)
                            if selectedID != tab.id { selectedID = tab.id }
                        } label: {
                            VStack(spacing: 0) {
                                Text(tab.title)
                                    .font(MissCatTypography.timelineTab)
                                    .foregroundStyle(palette.text)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                                Rectangle()
                                    .fill(selectedID == tab.id ? palette.accent : .clear)
                                    .frame(height: MissCatLegacyMetrics.timelineSelectionHeight)
                                    .padding(.horizontal, 4)
                            }
                            .frame(width: tabWidth, height: MissCatLegacyMetrics.timelineTabsHeight)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selectedID == tab.id ? .isSelected : [])
                        .accessibilityIdentifier("main.timeline.\(tab.accessibilityID)")
                    }
                }
            }
        }
        .frame(height: MissCatLegacyMetrics.timelineTabsHeight)
        .background(palette.base)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(palette.border)
                .frame(height: MissCatLegacyMetrics.hairlineWidth)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("main.timeline-tabs")
        .accessibilityValue(selectedID)
    }
}

public struct MissCatNavigationHeader: View {
    public let title: String
    public let palette: MissCatVisualPalette
    public let leadingImage: Image?
    public let accounts: [MissCatShellAccount]
    public let currentAccountID: String?
    public let showsSettings: Bool
    public let onSettings: () -> Void
    public let onAccountSelected: (MissCatShellAccountScope) -> Void

    @State private var showsAccountSwitcher = false

    public init(
        title: String,
        palette: MissCatVisualPalette = .legacyLight,
        leadingImage: Image? = nil,
        accounts: [MissCatShellAccount] = [],
        currentAccountID: String? = nil,
        showsSettings: Bool = false,
        onSettings: @escaping () -> Void = {},
        onAccountSelected: @escaping (MissCatShellAccountScope) -> Void = { _ in }
    ) {
        self.title = title
        self.palette = palette
        self.leadingImage = leadingImage
        self.accounts = accounts
        self.currentAccountID = currentAccountID
        self.showsSettings = showsSettings
        self.onSettings = onSettings
        self.onAccountSelected = onAccountSelected
    }

    public var body: some View {
        ZStack {
            Text(title)
                .font(MissCatTypography.navigationTitle)
                .foregroundStyle(palette.text)

            HStack {
                if leadingImage != nil || !accounts.isEmpty {
                    Button {
                        showsAccountSwitcher = true
                    } label: {
                        accountImage
                            .frame(width: 30, height: 30)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("アカウントを切り替える")
                    .accessibilityIdentifier("main.header.account")
                    .accessibilityValue(currentAccountID ?? "")
                    .popover(isPresented: $showsAccountSwitcher, arrowEdge: .top) {
                        MissCatAccountDropdownView(
                            accounts: accounts,
                            currentAccountID: currentAccountID,
                            palette: palette
                        ) { scope in
                            showsAccountSwitcher = false
                            onAccountSelected(scope)
                        }
                        .presentationCompactAdaptation(.popover)
                    }
                }

                Spacer()

                if showsSettings {
                    Button(action: onSettings) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("設定")
                    .accessibilityIdentifier("main.header.settings")
                }
            }
            .padding(.leading, 14)
        }
        .frame(height: MissCatLegacyMetrics.navigationHeaderHeight)
        .background(palette.base)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(palette.border)
                .frame(height: MissCatLegacyMetrics.hairlineWidth)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("main.header")
    }

    @ViewBuilder
    private var accountImage: some View {
        if let leadingImage {
            leadingImage
                .resizable()
                .scaledToFill()
        } else if let account = accounts.first(where: { $0.id == currentAccountID }),
                  let avatarURL = account.avatarURL {
            AsyncImage(url: avatarURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    accountPlaceholder
                }
            }
        } else {
            accountPlaceholder
        }
    }

    private var accountPlaceholder: some View {
        Circle()
            .fill(palette.surface)
            .overlay {
                Image(systemName: "person.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.strong)
            }
    }
}

public struct MissCatAccountDropdownView: View {
    public let accounts: [MissCatShellAccount]
    public let currentAccountID: String?
    public let palette: MissCatVisualPalette
    public let onSelect: (MissCatShellAccountScope) -> Void

    public init(
        accounts: [MissCatShellAccount],
        currentAccountID: String?,
        palette: MissCatVisualPalette = .legacyLight,
        onSelect: @escaping (MissCatShellAccountScope) -> Void
    ) {
        self.accounts = accounts
        self.currentAccountID = currentAccountID
        self.palette = palette
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(spacing: 0) {
            Text("アカウントを選択")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.text)
                .frame(maxWidth: .infinity, minHeight: 36)

            Rectangle().fill(palette.border).frame(height: MissCatLegacyMetrics.hairlineWidth)

            ForEach(accounts) { account in
                Button {
                    onSelect(account.scope)
                } label: {
                    HStack(spacing: 10) {
                        AsyncImage(url: account.avatarURL) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                            } else {
                                Circle()
                                    .fill(palette.surface)
                                    .overlay {
                                        Image(systemName: "person.fill")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(palette.strong)
                                    }
                            }
                        }
                        .frame(width: 30, height: 30)
                        .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 1) {
                            Text(account.displayName)
                                .font(.system(size: 14))
                            Text("@\(account.scope.username)@\(account.scope.displayInstance)")
                                .font(.system(size: 11))
                                .foregroundStyle(palette.strong)
                        }
                        .lineLimit(1)

                        Spacer(minLength: 6)
                        if account.id == currentAccountID {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(palette.accent)
                        }
                    }
                    .foregroundStyle(palette.text)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(account.id == currentAccountID ? .isSelected : [])
                .accessibilityIdentifier("main.account.\(account.id)")
            }
        }
        .frame(width: 280)
        .background(palette.base)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("main.account.dropdown")
    }
}

public struct MissCatBottomBar: View {
    @Binding public var selectedSection: MissCatRootSection
    public let palette: MissCatVisualPalette
    public let onCompose: () -> Void
    public let onReselect: (MissCatRootSection) -> Void

    public init(
        selectedSection: Binding<MissCatRootSection>,
        palette: MissCatVisualPalette = .legacyLight,
        onCompose: @escaping () -> Void,
        onReselect: @escaping (MissCatRootSection) -> Void = { _ in }
    ) {
        _selectedSection = selectedSection
        self.palette = palette
        self.onCompose = onCompose
        self.onReselect = onReselect
    }

    public var body: some View {
        HStack(spacing: MissCatLegacyMetrics.bottomBarItemSpacing) {
            rootButton(.home, symbol: "house.fill", label: "ホーム")
            rootButton(.notifications, symbol: "bell.fill", label: "通知")

            Button {
                var state = MissCatFooterSelectionState(selectedSection: selectedSection)
                guard state.activate(.compose) == .composeRequested else { return }
                onCompose()
            } label: {
                Circle()
                    .fill(palette.accent)
                    .frame(
                        width: MissCatLegacyMetrics.composeButtonDiameter,
                        height: MissCatLegacyMetrics.composeButtonDiameter
                    )
                    .overlay {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 23, weight: .regular))
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("投稿")
            .accessibilityIdentifier("main.action.compose")

            rootButton(.messages, symbol: "star.fill", label: "ダイレクトメッセージ")
            rootButton(.profile, symbol: "person.fill", label: "プロフィール")
        }
        .padding(.horizontal, 0)
        .frame(height: MissCatLegacyMetrics.bottomBarHeight)
        .background(palette.base)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(palette.border)
                .frame(height: MissCatLegacyMetrics.hairlineWidth)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("main.bottom-bar")
    }

    private func rootButton(
        _ destination: MissCatFooterDestination,
        symbol: String,
        label: String
    ) -> some View {
        let section = destination.rootSection ?? .home
        return Button {
            var state = MissCatFooterSelectionState(selectedSection: selectedSection)
            switch state.activate(destination) {
            case let .selected(section):
                selectedSection = section
            case let .reselected(section):
                onReselect(section)
            case .composeRequested:
                onCompose()
            }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(selectedSection == section ? palette.accent : Color(white: 0.67))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selectedSection == section ? .isSelected : [])
        .accessibilityIdentifier("main.tab.\(section.rawValue)")
    }
}
