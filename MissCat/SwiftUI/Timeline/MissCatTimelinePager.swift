import SwiftUI

public struct MissCatTimelinePage: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let source: MissCatFeedSource
    public let accountScope: MissCatShellAccountScope?
    public let accessibilityID: String

    public init(
        id: String,
        title: String,
        source: MissCatFeedSource,
        accountScope: MissCatShellAccountScope? = nil,
        accessibilityID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.source = source
        self.accountScope = accountScope
        self.accessibilityID = accessibilityID ?? id
    }

    public static let networkDefaults: [MissCatTimelinePage] = [
        .init(id: "home", title: "Home", source: .home),
        .init(id: "local", title: "Local", source: .local),
        .init(id: "social", title: "Social", source: .social),
        .init(id: "global", title: "Global", source: .global)
    ]
}

public enum MissCatTimelineSelectionOrigin: Equatable, Sendable {
    case initial
    case tap
    case swipe
    case pagesChanged
}

public struct MissCatTimelineScrollKey: Hashable, Sendable {
    public let accountScope: MissCatShellAccountScope
    public let pageID: String

    public init(accountScope: MissCatShellAccountScope, pageID: String) {
        self.accountScope = accountScope
        self.pageID = pageID
    }
}

public struct MissCatTimelineScrollPositionState: Equatable, Sendable {
    private var positions: [MissCatTimelineScrollKey: String] = [:]

    public init() {}

    public func position(for key: MissCatTimelineScrollKey) -> String? {
        positions[key]
    }

    public mutating func setPosition(_ noteID: String?, for key: MissCatTimelineScrollKey) {
        if let noteID, !noteID.isEmpty {
            positions[key] = noteID
        } else {
            positions.removeValue(forKey: key)
        }
    }
}

/// Pure state shared by tap and swipe selection. Keeping this independent of SwiftUI
/// makes edge clamping, reverse swipes and rapid selection changes deterministic in tests.
public struct MissCatTimelineSelectionState: Equatable, Sendable {
    public private(set) var pageIDs: [String]
    public private(set) var selectedID: String
    public private(set) var lastOrigin: MissCatTimelineSelectionOrigin

    public init(pageIDs: [String], selectedID: String) {
        self.pageIDs = Self.unique(pageIDs)
        self.selectedID = Self.normalized(selectedID, in: self.pageIDs)
        lastOrigin = .initial
    }

    @discardableResult
    public mutating func select(
        _ candidate: String,
        origin: MissCatTimelineSelectionOrigin
    ) -> Bool {
        guard pageIDs.contains(candidate) else { return false }
        selectedID = candidate
        lastOrigin = origin
        return true
    }

    @discardableResult
    public mutating func move(by offset: Int) -> Bool {
        guard !pageIDs.isEmpty,
              let currentIndex = pageIDs.firstIndex(of: selectedID) else { return false }
        let targetIndex = min(max(currentIndex + offset, 0), pageIDs.count - 1)
        guard targetIndex != currentIndex else { return false }
        selectedID = pageIDs[targetIndex]
        lastOrigin = .swipe
        return true
    }

    public mutating func updatePages(_ pageIDs: [String]) {
        self.pageIDs = Self.unique(pageIDs)
        selectedID = Self.normalized(selectedID, in: self.pageIDs)
        lastOrigin = .pagesChanged
    }

    private static func unique(_ pageIDs: [String]) -> [String] {
        var seen = Set<String>()
        return pageIDs.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private static func normalized(_ selectedID: String, in pageIDs: [String]) -> String {
        pageIDs.contains(selectedID) ? selectedID : (pageIDs.first ?? "")
    }
}

/// Native SwiftUI page container. `selectedID` is the same binding consumed by
/// `MissCatTimelineTabs`, so header taps and page swipes always update one source of truth.
public struct MissCatTimelinePager: View {
    @Binding private var selectedID: String
    @State private var scrollPositions = MissCatTimelineScrollPositionState()

    private let accountScope: MissCatShellAccountScope
    private let pages: [MissCatTimelinePage]
    private let repositoryProvider: (MissCatShellAccountScope) -> (any MissCatFeedRepository)?
    private let palette: MissCatVisualPalette
    private let navigationActions: MissCatFeedNavigationActions
    private let scrollToTopTrigger: Int
    private let relativeDateReference: Date
    private let visualReadyPrefix: String?
    private let allowsLoadingVisualReady: Bool
    private let externalScrollPosition: ((MissCatTimelineScrollKey) -> Binding<String?>)?
    private let onSelection: (String, MissCatTimelineSelectionOrigin) -> Void

    public init(
        accountID: String,
        pages: [MissCatTimelinePage] = MissCatTimelinePage.networkDefaults,
        selectedID: Binding<String>,
        repository: MissCatFeedRepository,
        palette: MissCatVisualPalette = .legacyLight,
        navigationActions: MissCatFeedNavigationActions = .init()
    ) {
        let scope = MissCatShellAccountScope(instance: "legacy.invalid", userID: accountID, username: "")
        accountScope = scope
        self.pages = pages
        _selectedID = selectedID
        repositoryProvider = { _ in repository }
        self.palette = palette
        self.navigationActions = navigationActions
        scrollToTopTrigger = 0
        relativeDateReference = Date()
        visualReadyPrefix = nil
        allowsLoadingVisualReady = false
        externalScrollPosition = nil
        onSelection = { _, _ in }
    }

    public init(
        accountScope: MissCatShellAccountScope,
        pages: [MissCatTimelinePage],
        selectedID: Binding<String>,
        repositoryProvider: @escaping (MissCatShellAccountScope) -> (any MissCatFeedRepository)?,
        palette: MissCatVisualPalette = .legacyLight,
        scrollToTopTrigger: Int = 0,
        relativeDateReference: Date = Date(),
        visualReadyPrefix: String? = nil,
        allowsLoadingVisualReady: Bool = false,
        scrollPosition: ((MissCatTimelineScrollKey) -> Binding<String?>)? = nil,
        navigationActions: MissCatFeedNavigationActions = .init(),
        onSelection: @escaping (String, MissCatTimelineSelectionOrigin) -> Void = { _, _ in }
    ) {
        self.accountScope = accountScope
        self.pages = pages
        _selectedID = selectedID
        self.repositoryProvider = repositoryProvider
        self.palette = palette
        self.scrollToTopTrigger = scrollToTopTrigger
        self.relativeDateReference = relativeDateReference
        self.visualReadyPrefix = visualReadyPrefix
        self.allowsLoadingVisualReady = allowsLoadingVisualReady
        externalScrollPosition = scrollPosition
        self.navigationActions = navigationActions
        self.onSelection = onSelection
    }

    public var body: some View {
        TabView(selection: selection) {
            ForEach(pages) { page in
                timelinePage(page)
                .id("\(accountScope.id):\(page.id)")
                .tag(page.id)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("timeline.page.\(page.accessibilityID)")
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(palette.base)
        .onAppear(perform: normalizeSelection)
        .onChange(of: pageIDs) { _, _ in normalizeSelection() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("timeline.pager")
        .accessibilityValue(selectedID)
    }

    private var pageIDs: [String] { pages.map(\.id) }

    private var selection: Binding<String> {
        return Binding(
            get: { selectedID },
            set: { candidate in
                var state = MissCatTimelineSelectionState(
                    pageIDs: pageIDs,
                    selectedID: selectedID
                )
                guard state.select(candidate, origin: .swipe) else { return }
                guard state.selectedID != selectedID else { return }
                onSelection(state.selectedID, .swipe)
                if selectedID != state.selectedID { selectedID = state.selectedID }
            }
        )
    }

    private func scrollPosition(for page: MissCatTimelinePage) -> Binding<String?> {
        let key = MissCatTimelineScrollKey(
            accountScope: page.accountScope ?? accountScope,
            pageID: page.id
        )
        if let externalScrollPosition {
            return externalScrollPosition(key)
        }
        return Binding(
            get: { scrollPositions.position(for: key) },
            set: { scrollPositions.setPosition($0, for: key) }
        )
    }

    private func normalizeSelection() {
        let state = MissCatTimelineSelectionState(pageIDs: pageIDs, selectedID: selectedID)
        if state.selectedID != selectedID {
            selectedID = state.selectedID
        }
    }

    @ViewBuilder
    private func timelinePage(_ page: MissCatTimelinePage) -> some View {
        let scope = page.accountScope ?? accountScope
        if let repository = repositoryProvider(scope) {
            MissCatFeedView(
                source: page.source,
                repository: repository,
                accountScope: scope,
                palette: palette,
                scrollPositionID: scrollPosition(for: page),
                scrollToTopTrigger: selectedID == page.id ? scrollToTopTrigger : 0,
                relativeDateReference: relativeDateReference,
                visualReadyIdentifier: visualReadyPrefix.map { "\($0).\(page.accessibilityID)" },
                allowsLoadingVisualReady: allowsLoadingVisualReady,
                navigationActions: navigationActions
            )
        } else {
            ContentUnavailableView {
                Label("アカウントを読み込めません", systemImage: "person.crop.circle.badge.exclamationmark")
            } description: {
                Text("アカウント設定を確認してください")
            }
            .foregroundStyle(palette.strong)
            .accessibilityIdentifier("feed.account-unavailable")
        }
    }
}
