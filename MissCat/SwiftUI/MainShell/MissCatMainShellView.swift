import SwiftUI

public enum MissCatRootSection: String, CaseIterable, Identifiable {
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

    public init(id: String, title: String) {
        self.id = id
        self.title = title
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
    private let onSearch: () -> Void
    private let onCompose: () -> Void
    private let onSettings: () -> Void
    private let onReselect: (MissCatRootSection) -> Void
    private let content: (MissCatRootSection) -> Content

    public init(
        timelineTabs: [MissCatTimelineTab] = MissCatTimelineTab.legacyDefaults,
        selectedTimelineID: Binding<String>,
        selectedSection: Binding<MissCatRootSection>,
        palette: MissCatVisualPalette = .legacyLight,
        avatar: Image? = nil,
        onSearch: @escaping () -> Void,
        onCompose: @escaping () -> Void,
        onSettings: @escaping () -> Void = {},
        onReselect: @escaping (MissCatRootSection) -> Void = { _ in },
        @ViewBuilder content: @escaping (MissCatRootSection) -> Content
    ) {
        self.timelineTabs = timelineTabs
        _selectedTimelineID = selectedTimelineID
        _selectedSection = selectedSection
        self.palette = palette
        self.avatar = avatar
        self.onSearch = onSearch
        self.onCompose = onCompose
        self.onSettings = onSettings
        self.onReselect = onReselect
        self.content = content
    }

    public var body: some View {
        VStack(spacing: 0) {
            shellHeader

            content(selectedSection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(palette.base)
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
        .accessibilityIdentifier("main.shell")
    }

    @ViewBuilder
    private var shellHeader: some View {
        if selectedSection == .home {
            MissCatTimelineTabs(
                tabs: timelineTabs,
                selectedID: $selectedTimelineID,
                palette: palette,
                onSearch: onSearch
            )
        } else {
            MissCatNavigationHeader(
                title: selectedSection.legacyTitle,
                palette: palette,
                leadingImage: selectedSection == .profile ? nil : avatar,
                showsSettings: selectedSection == .profile,
                onSettings: onSettings
            )
        }
    }
}

public struct MissCatTimelineTabs: View {
    public let tabs: [MissCatTimelineTab]
    @Binding public var selectedID: String
    public let palette: MissCatVisualPalette
    public let onSearch: () -> Void

    public init(
        tabs: [MissCatTimelineTab],
        selectedID: Binding<String>,
        palette: MissCatVisualPalette = .legacyLight,
        onSearch: @escaping () -> Void
    ) {
        self.tabs = tabs
        _selectedID = selectedID
        self.palette = palette
        self.onSearch = onSearch
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
                            selectedID = tab.id
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
                        .accessibilityIdentifier("main.timeline.\(tab.id)")
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
        .accessibilityIdentifier("main.timeline-tabs")
    }
}

public struct MissCatNavigationHeader: View {
    public let title: String
    public let palette: MissCatVisualPalette
    public let leadingImage: Image?
    public let showsSettings: Bool
    public let onSettings: () -> Void

    public init(
        title: String,
        palette: MissCatVisualPalette = .legacyLight,
        leadingImage: Image? = nil,
        showsSettings: Bool = false,
        onSettings: @escaping () -> Void = {}
    ) {
        self.title = title
        self.palette = palette
        self.leadingImage = leadingImage
        self.showsSettings = showsSettings
        self.onSettings = onSettings
    }

    public var body: some View {
        ZStack {
            Text(title)
                .font(MissCatTypography.navigationTitle)
                .foregroundStyle(palette.text)

            HStack {
                if let leadingImage {
                    leadingImage
                        .resizable()
                        .scaledToFill()
                        .frame(width: 30, height: 30)
                        .clipShape(Circle())
                        .accessibilityLabel("アカウントを切り替える")
                        .accessibilityIdentifier("main.header.account")
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
        .accessibilityIdentifier("main.header")
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

            Button(action: onCompose) {
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
        .accessibilityIdentifier("main.bottom-bar")
    }

    private func rootButton(
        _ section: MissCatRootSection,
        symbol: String,
        label: String
    ) -> some View {
        Button {
            if selectedSection == section {
                onReselect(section)
            } else {
                selectedSection = section
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
