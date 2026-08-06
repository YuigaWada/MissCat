import SwiftUI

public struct MissCatTimelinePage: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let source: MissCatFeedSource

    public init(id: String, title: String, source: MissCatFeedSource) {
        self.id = id
        self.title = title
        self.source = source
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
    @State private var scrollPositions: [String: String] = [:]

    private let accountID: String
    private let pages: [MissCatTimelinePage]
    private let repository: MissCatFeedRepository
    private let palette: MissCatVisualPalette
    private let navigationActions: MissCatFeedNavigationActions

    public init(
        accountID: String,
        pages: [MissCatTimelinePage] = MissCatTimelinePage.networkDefaults,
        selectedID: Binding<String>,
        repository: MissCatFeedRepository,
        palette: MissCatVisualPalette = .legacyLight,
        navigationActions: MissCatFeedNavigationActions = .init()
    ) {
        self.accountID = accountID
        self.pages = pages
        _selectedID = selectedID
        self.repository = repository
        self.palette = palette
        self.navigationActions = navigationActions
    }

    public var body: some View {
        TabView(selection: selection) {
            ForEach(pages) { page in
                MissCatFeedView(
                    source: page.source,
                    repository: repository,
                    palette: palette,
                    scrollPositionID: scrollPosition(for: page.id),
                    navigationActions: navigationActions
                )
                .id("\(accountID):\(page.id)")
                .tag(page.id)
                .accessibilityIdentifier("timeline.page.\(page.id)")
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(palette.base)
        .onAppear(perform: normalizeSelection)
        .onChange(of: pageIDs) { _, _ in normalizeSelection() }
        .onChange(of: accountID) { _, _ in scrollPositions.removeAll() }
        .accessibilityIdentifier("timeline.pager.\(accountID)")
    }

    private var pageIDs: [String] { pages.map(\.id) }

    private var selection: Binding<String> {
        Binding(
            get: { selectedID },
            set: { candidate in
                var state = MissCatTimelineSelectionState(
                    pageIDs: pageIDs,
                    selectedID: selectedID
                )
                guard state.select(candidate, origin: .swipe) else { return }
                selectedID = state.selectedID
            }
        )
    }

    private func scrollPosition(for pageID: String) -> Binding<String?> {
        Binding(
            get: { scrollPositions[pageID] },
            set: { scrollPositions[pageID] = $0 }
        )
    }

    private func normalizeSelection() {
        let state = MissCatTimelineSelectionState(pageIDs: pageIDs, selectedID: selectedID)
        if state.selectedID != selectedID {
            selectedID = state.selectedID
        }
    }
}
