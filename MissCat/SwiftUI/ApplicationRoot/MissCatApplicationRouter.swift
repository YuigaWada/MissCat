import Observation

public enum MissCatApplicationRootSelectionResult: Equatable, Sendable {
    case selected(MissCatRootSection)
    case reselected(MissCatRootSection)
}

/// Observation-native routing state for the production SwiftUI root. Feature
/// views consume typed destinations and never need a UIKit navigation owner.
@MainActor
@Observable
public final class MissCatApplicationRouter {
    public private(set) var activeAccountID: MissCatApplicationAccountID?
    public private(set) var selectedSection: MissCatRootSection
    public private(set) var timelineSelection: MissCatApplicationTabSelection
    public private(set) var sheetDestination: MissCatApplicationSheetDestination?
    public private(set) var fullScreenDestination: MissCatApplicationFullScreenDestination?

    private var navigationPaths: [MissCatRootSection: [MissCatApplicationRoute]] = [:]

    public init(
        selectedSection: MissCatRootSection = .home,
        timelineTabs: [MissCatTimelineTab] = MissCatTimelineTab.legacyDefaults,
        selectedTimelineID: String = MissCatTimelineTab.legacyDefaults.first?.id ?? ""
    ) {
        self.selectedSection = selectedSection
        timelineSelection = MissCatApplicationTabSelection(
            tabs: timelineTabs,
            selectedID: selectedTimelineID
        )
    }

    public var path: [MissCatApplicationRoute] {
        navigationPaths[selectedSection] ?? []
    }

    public func path(for section: MissCatRootSection) -> [MissCatApplicationRoute] {
        navigationPaths[section] ?? []
    }

    public func replacePath(
        _ path: [MissCatApplicationRoute],
        for section: MissCatRootSection? = nil
    ) {
        navigationPaths[section ?? selectedSection] = path
    }

    public func open(_ route: MissCatApplicationRoute) {
        navigationPaths[selectedSection, default: []].append(route)
    }

    public func pop() {
        guard navigationPaths[selectedSection]?.isEmpty == false else { return }
        navigationPaths[selectedSection]?.removeLast()
    }

    public func popToRoot(in section: MissCatRootSection? = nil) {
        navigationPaths[section ?? selectedSection] = []
    }

    @discardableResult
    public func selectRoot(_ section: MissCatRootSection) -> MissCatApplicationRootSelectionResult {
        guard section != selectedSection else { return .reselected(section) }
        selectedSection = section
        return .selected(section)
    }

    @discardableResult
    public func selectTimeline(_ id: String) -> MissCatApplicationTabSelectionResult {
        timelineSelection.select(id)
    }

    @discardableResult
    public func swipeTimelineLeft() -> MissCatApplicationTabSelectionResult {
        timelineSelection.swipeLeft()
    }

    @discardableResult
    public func swipeTimelineRight() -> MissCatApplicationTabSelectionResult {
        timelineSelection.swipeRight()
    }

    public func presentSheet(_ destination: MissCatApplicationSheetDestination) {
        fullScreenDestination = nil
        sheetDestination = destination
    }

    public func dismissSheet() {
        sheetDestination = nil
    }

    public func presentFullScreen(_ destination: MissCatApplicationFullScreenDestination) {
        sheetDestination = nil
        fullScreenDestination = destination
    }

    public func dismissFullScreen() {
        fullScreenDestination = nil
    }

    public func activate(_ session: MissCatApplicationSession) {
        activeAccountID = session.currentAccount.id
        selectedSection = .home
        navigationPaths.removeAll(keepingCapacity: true)
        sheetDestination = nil
        fullScreenDestination = nil
        timelineSelection = MissCatApplicationTabSelection(
            tabs: session.timelineTabs,
            selectedID: session.selectedTimelineID
        )
    }

    public func clearForSignOut() {
        activeAccountID = nil
        selectedSection = .home
        navigationPaths.removeAll()
        sheetDestination = nil
        fullScreenDestination = nil
        timelineSelection = MissCatApplicationTabSelection(tabs: [], selectedID: "")
    }

}
