import Combine
import SwiftUI

@MainActor
final class MissCatProductionAccountCoordinator: ObservableObject {
    enum Phase {
        case loading
        case ready(MissCatShellConfiguration)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var homeScrollToTopGeneration = 0

    let session: MissCatApplicationSession
    private let shellProvider = MissCatLegacyShellConfigurationProvider()
    private var feedRepositories: [MissCatShellAccountScope: any MissCatFeedRepository] = [:]
    private(set) var notificationRepository: (any MissCatNotificationsRepository)?
    private(set) var messagingRepository: (any MissCatMessagingRepository)?
    private(set) var notificationStore: MissCatNotificationsStore?
    let notificationScrollCoordinator = MissCatNotificationScrollCoordinator()
    private(set) var discoveryGeneration: MissCatDiscoveryAccountGeneration?
    private(set) var profileAccount: MissCatProfileAccount?
    private(set) var profileRepositoryFactory: ((MissCatProfileAccount) -> MissCatProfileRepository)?
    private(set) var composeSession: MissCatComposeProductionSession?
    private var people: [String: MissCatPerson] = [:]
    private var attachments: [String: MissCatNoteAttachment] = [:]
    private var reactionRequests: [String: MissCatFeedReactionRequest] = [:]

    init(session: MissCatApplicationSession) {
        self.session = session
    }

    func load() async {
        guard case .loading = phase else { return }
        do {
#if DEBUG
            if MissCatProductionRootE2ELaunch.isRequested {
                let configuration = makeFixtureConfiguration()
                let repository = MissCatProductionRootE2ERepository(
                    account: configuration.currentScope
                )
                for account in configuration.accounts {
                    feedRepositories[account.scope] = repository
                }
                notificationRepository = repository
                messagingRepository = repository
                notificationStore = MissCatNotificationsStore(repository: repository)
                let feedSession = MissCatFeedSession(
                    accountID: configuration.currentScope.userID,
                    username: configuration.currentScope.username,
                    instance: configuration.currentScope.instance,
                    apiKey: "fixture-token"
                )
                discoveryGeneration = MissCatDiscoveryAccountGeneration(
                    session: feedSession,
                    discoveryRepository: repository,
                    feedRepository: repository,
                    previewProfile: repository.profileUser,
                    pageSize: 8
                )
                let fixtureProfileAccount = MissCatProfileAccount(
                    userID: configuration.currentScope.userID,
                    instance: configuration.currentScope.instance,
                    token: "fixture-token"
                )
                let profileRepository = MissCatProductionRootE2EProfileRepository(
                    account: fixtureProfileAccount
                )
                profileAccount = fixtureProfileAccount
                profileRepositoryFactory = { _ in profileRepository }
                composeSession = try MissCatProductionRootE2ELaunch.composeSession(
                    for: session.currentAccount.id
                )
                phase = .ready(configuration)
                return
            }
#endif
            let configuration = try await shellProvider.loadConfiguration()
            let savedUsers = Cache.UserDefaults.shared.getUsers()
            guard configuration.currentScope.userID == session.currentAccount.userID,
                  MissCatApplicationAccountID(
                    instance: configuration.currentScope.instance,
                    userID: configuration.currentScope.userID
                  ) == session.currentAccount.id,
                  let user = savedUsers.first(where: {
                    $0.accountIdentifier == session.currentAccount.id.rawValue
                  }),
                  let apiKey = user.apiKey,
                  !apiKey.isEmpty
            else { throw MissCatShellConfigurationError.accountIdentityMismatch }

            for page in configuration.timelinePages {
                let scope = page.accountScope ?? configuration.currentScope
                if feedRepositories[scope] == nil {
                    feedRepositories[scope] = try shellProvider.repository(for: scope)
                }
            }
            let accountScope = MissCatAccountScope(
                accountID: user.userId,
                username: user.username,
                host: user.normalizedInstance,
                accessToken: apiKey
            )
            let notificationMessaging = MissCatNativeNotificationMessagingRepository(
                accountScope: accountScope
            )
            notificationRepository = notificationMessaging
            messagingRepository = notificationMessaging
            notificationStore = MissCatNotificationsStore(repository: notificationMessaging)
            let feedSession = MissCatFeedSession(
                accountID: user.userId,
                username: user.username,
                instance: user.instance,
                apiKey: apiKey
            )
            let currentFeed = repository(for: configuration.currentScope)
            discoveryGeneration = MissCatDiscoveryAccountGeneration(
                session: feedSession,
                feedRepository: currentFeed
            )
            profileAccount = MissCatProfileAccount(
                userID: user.userId,
                instance: user.instance,
                token: apiKey
            )
            profileRepositoryFactory = { MissCatRESTProfileRepository(account: $0) }
            let savedUsersByAccountID = Dictionary(
                uniqueKeysWithValues: savedUsers.map { ($0.accountIdentifier, $0) }
            )
            let composeAuthorizations: [MissCatComposeProductionSession.Authorization] = session.accounts.compactMap {
                applicationAccount -> MissCatComposeProductionSession.Authorization? in
                guard let savedUser = savedUsersByAccountID[applicationAccount.id.rawValue],
                      let accessToken = savedUser.apiKey,
                      !accessToken.isEmpty
                else { return nil }
                return try? MissCatComposeProductionSession.Authorization(
                    accountID: savedUser.accountIdentifier,
                    username: savedUser.username,
                    instance: savedUser.instance,
                    avatarURL: applicationAccount.avatarURL,
                    accessToken: accessToken
                )
            }
            composeSession = try MissCatComposeProductionSession(
                authorizations: composeAuthorizations,
                selectedAccountID: session.currentAccount.id.rawValue,
                visibility: Cache.UserDefaults.shared.getCurrentVisibility()
                    .flatMap { MissCatComposeVisibility(rawValue: $0.rawValue) }
                    ?? .public
            )
            phase = .ready(configuration)
        } catch is CancellationError {
            phase = .loading
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func repository(for scope: MissCatShellAccountScope) -> (any MissCatFeedRepository)? {
        if let repository = feedRepositories[scope] { return repository }
        guard let repository = try? shellProvider.repository(for: scope) else { return nil }
        feedRepositories[scope] = repository
        return repository
    }

    func persistTimelineSelection(_ id: String, scope: MissCatShellAccountScope) {
        Task {
            try? await shellProvider.saveSelectedTimelineID(id, for: scope)
        }
    }

    func scrollHomeToTop() {
        homeScrollToTopGeneration &+= 1
    }

    func persistComposeVisibility(
        accountID: String,
        visibility: MissCatComposeVisibility
    ) {
#if DEBUG
        if MissCatProductionRootE2ELaunch.isRequested { return }
#endif
        guard accountID == session.currentAccount.id.rawValue,
              Cache.UserDefaults.shared.getCurrentUserId() == session.currentAccount.id.rawValue,
              let legacyVisibility = MissCatComposeLegacyVisibilityAdapter.value(visibility)
        else { return }
        Cache.UserDefaults.shared.setCurrentVisibility(legacyVisibility)
    }

    func remember(_ person: MissCatPerson) {
        people[person.id] = person
    }

    func person(id: String) -> MissCatPerson? { people[id] }

    func remember(_ attachment: MissCatNoteAttachment) {
        attachments[attachment.id] = attachment
    }

    func attachment(id: String) -> MissCatNoteAttachment? { attachments[id] }

    func prepareReaction(_ request: MissCatFeedReactionRequest) {
        reactionRequests[request.noteID] = request
    }

    func reactionRequest(noteID: String) -> MissCatFeedReactionRequest? {
        reactionRequests[noteID]
    }

    func clearReactionRequest(noteID: String? = nil) {
        if let noteID {
            reactionRequests[noteID] = nil
        } else {
            reactionRequests.removeAll()
        }
    }

    private func makeFixtureConfiguration() -> MissCatShellConfiguration {
        let accounts = session.accounts.map { account in
            MissCatShellAccount(
                scope: MissCatShellAccountScope(
                    instance: account.instance,
                    userID: account.userID,
                    username: account.username
                ),
                displayName: account.displayName,
                avatarURL: account.avatarURL
            )
        }
        let currentScope = accounts.first(where: {
            MissCatApplicationAccountID(
                instance: $0.scope.instance,
                userID: $0.scope.userID
            ) == session.currentAccount.id
        })?.scope ?? accounts[0].scope
        let sources: [MissCatFeedSource] = [.home, .local, .global]
        let pages = zip(session.timelineTabs, sources).map { tab, source in
            MissCatTimelinePage(
                id: tab.id,
                title: tab.title,
                source: source,
                accountScope: currentScope,
                accessibilityID: tab.accessibilityID
            )
        }
        return MissCatShellConfiguration(
            currentScope: currentScope,
            accounts: accounts,
            timelinePages: pages,
            selectedTimelineID: session.selectedTimelineID,
            appearance: MissCatShellAppearance(
                isDark: false,
                accentHex: MissCatLegacyColorHex.accent
            )
        )
    }
}

/// The authenticated application root. It owns the application `NavigationStack`,
/// shell, feature factories, account generation and modal presentation state.
struct MissCatProductionApplicationRootView: View {
    @Bindable private var rootStore: MissCatApplicationRootStore
    @StateObject private var coordinator: MissCatProductionAccountCoordinator
    @Environment(\.openURL) private var openURL

    private let session: MissCatApplicationSession

    init(rootStore: MissCatApplicationRootStore, session: MissCatApplicationSession) {
        self.rootStore = rootStore
        self.session = session
        _coordinator = StateObject(
            wrappedValue: MissCatProductionAccountCoordinator(session: session)
        )
    }

    var body: some View {
        Group {
            switch coordinator.phase {
            case .loading:
                ProgressView("タイムラインを準備中…")
                    .accessibilityIdentifier("production.root.loading")
            case let .failed(message):
                ContentUnavailableView(
                    "アプリを開けません",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
                .accessibilityIdentifier("production.root.failure")
            case let .ready(configuration):
                navigationRoot(configuration)
            }
        }
        .task { await coordinator.load() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("production.root")
        .overlay(alignment: .topLeading) { productionRootE2EStateMarkers }
    }

    private func navigationRoot(_ configuration: MissCatShellConfiguration) -> some View {
        NavigationStack(path: navigationPathBinding) {
            shell(configuration)
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: MissCatApplicationRoute.self) { route in
                    routeDestination(route, configuration: configuration)
                }
        }
        .sheet(item: sheetBinding) { destination in
            sheetDestination(destination, configuration: configuration)
        }
        .fullScreenCover(item: fullScreenBinding) { destination in
            fullScreenDestination(destination)
        }
    }

    private func shell(_ configuration: MissCatShellConfiguration) -> some View {
        MissCatMainShellView(
            timelineTabs: rootStore.router.timelineSelection.tabs,
            selectedTimelineID: timelineBinding(configuration),
            selectedSection: sectionBinding,
            palette: configuration.appearance.palette,
            avatar: Image(systemName: "person.crop.circle.fill"),
            accounts: configuration.accounts,
            currentAccountID: configuration.currentScope.id,
            bannerMessage: rootStore.lastErrorMessage,
            onSearch: { rootStore.router.open(.discovery) },
            onCompose: { rootStore.router.presentFullScreen(.compose(.new)) },
            onSettings: { rootStore.router.presentSheet(.settings) },
            onAccountSelected: switchAccount,
            onTimelineSelection: { id, origin in
                selectTimeline(id, origin: origin, configuration: configuration)
            },
            onReselect: { section in reselect(section) },
            onDismissBanner: rootStore.dismissError
        ) { section in
            sectionContent(section, configuration: configuration)
        }
    }

    @ViewBuilder
    private func sectionContent(
        _ section: MissCatRootSection,
        configuration: MissCatShellConfiguration
    ) -> some View {
        switch section {
        case .home:
            MissCatTimelinePager(
                accountScope: configuration.currentScope,
                pages: configuration.timelinePages,
                selectedID: timelineBinding(configuration),
                repositoryProvider: coordinator.repository,
                palette: configuration.appearance.palette,
                scrollToTopTrigger: coordinator.homeScrollToTopGeneration,
                visualReadyPrefix: fixtureVisualReadyPrefix,
                navigationActions: feedNavigationActions,
                onSelection: { id, origin in
                    selectTimeline(id, origin: origin, configuration: configuration)
                }
            )
            .overlay(alignment: .topTrailing) {
                Text("timeline-selection")
                    .font(.system(size: 1))
                    .opacity(0.01)
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier("production.timeline.selection")
                    .accessibilityValue(selectedTimelineAccessibilityID(configuration))
            }
        case .notifications:
            if let notificationStore = coordinator.notificationStore {
                MissCatNotificationsView(
                    store: notificationStore,
                    palette: configuration.appearance.palette,
                    navigationActions: notificationNavigationActions,
                    scrollCoordinator: coordinator.notificationScrollCoordinator
                )
            } else {
                unavailable("通知")
            }
        case .messages:
            if let repository = coordinator.messagingRepository {
                MissCatMessageHistoryView(
                    repository: repository,
                    palette: configuration.appearance.palette,
                    navigationActions: messageNavigationActions
                )
            } else {
                unavailable("メッセージ")
            }
        case .profile:
            profileView(
                root: .profile(userID: session.currentAccount.userID),
                palette: configuration.appearance.palette,
                showsBack: false
            )
        }
    }

    @ViewBuilder
    private func routeDestination(
        _ route: MissCatApplicationRoute,
        configuration: MissCatShellConfiguration
    ) -> some View {
        let palette = configuration.appearance.palette
        switch route {
        case .discovery:
            if let generation = coordinator.discoveryGeneration {
                MissCatDiscoveryRoot(
                    generation: generation,
                    applicationNavigationActions: discoveryNavigationActions
                )
                .navigationBarBackButtonHidden(true)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        productionRouteBackButton
                    }
                }
            } else {
                unavailable("検索")
            }
        case let .note(id):
            if let repository = coordinator.repository(for: configuration.currentScope) {
                MissCatNoteDetailView(
                    noteID: id,
                    repository: repository,
                    palette: palette,
                    navigationActions: feedNavigationActions
                )
                .navigationBarBackButtonHidden(true)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        productionRouteBackButton
                    }
                }
            } else { unavailable("ノート") }
        case .notification:
            if let notificationStore = coordinator.notificationStore {
                MissCatNotificationsView(
                    store: notificationStore,
                    palette: palette,
                    navigationActions: notificationNavigationActions,
                    scrollCoordinator: coordinator.notificationScrollCoordinator
                )
            } else { unavailable("通知") }
        case let .profile(userID):
            profileView(root: .profile(userID: userID), palette: palette, showsBack: true)
        case let .profileUserList(kind):
            profileView(root: .userList(kind), palette: palette, showsBack: true)
                .navigationBarBackButtonHidden(true)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        productionRouteBackButton
                    }
                }
        case let .profileEditor(profile):
            profileView(root: .editProfile(profile), palette: palette, showsBack: true)
        case let .userTimeline(userID, includesReplies, onlyFiles):
            if let repository = coordinator.repository(for: configuration.currentScope) {
                MissCatUserTimelineView(
                    userID: userID,
                    includesReplies: includesReplies,
                    onlyFiles: onlyFiles,
                    repository: repository,
                    palette: palette,
                    navigationActions: feedNavigationActions
                )
            } else { unavailable("タイムライン") }
        case let .conversation(userID):
            if let person = coordinator.person(id: userID),
               let repository = coordinator.messagingRepository {
                MissCatConversationView(
                    peer: person,
                    repository: repository,
                    palette: palette,
                    navigationActions: messageNavigationActions
                )
            } else { unavailable("会話") }
        case let .search(query):
            if let repository = coordinator.repository(for: configuration.currentScope) {
                MissCatSearchResultsView(
                    query: query,
                    repository: repository,
                    palette: palette,
                    navigationActions: feedNavigationActions
                )
                .navigationBarBackButtonHidden(true)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        productionRouteBackButton
                    }
                }
            } else { unavailable("検索") }
        case let .hashtag(tag):
            if let repository = coordinator.repository(for: configuration.currentScope) {
                MissCatHashtagResultsView(
                    tag: tag,
                    repository: repository,
                    palette: palette,
                    navigationActions: feedNavigationActions
                )
            } else { unavailable("ハッシュタグ") }
        case .settings:
            settingsView(palette: palette, close: rootStore.router.pop)
        case .accounts:
            accountsView(palette: palette, close: rootStore.router.pop)
        case let .externalURL(url):
            MissCatExternalURLDestination(url: url)
        }
    }

    @ViewBuilder
    private func sheetDestination(
        _ destination: MissCatApplicationSheetDestination,
        configuration: MissCatShellConfiguration
    ) -> some View {
        switch destination {
        case .accountSwitcher:
            accountsView(
                palette: configuration.appearance.palette,
                close: rootStore.router.dismissSheet
            )
        case .settings:
            settingsView(
                palette: configuration.appearance.palette,
                close: rootStore.router.dismissSheet
            )
        case let .reactionPicker(noteID):
            if let repository = coordinator.repository(for: configuration.currentScope)
                as? any MissCatNoteContextRepository,
               let request = coordinator.reactionRequest(noteID: noteID) {
                MissCatReactionPickerView(
                    noteID: noteID,
                    existingReactions: request.existingReactions,
                    noteAuthorHost: request.noteAuthorHost,
                    reactionAcceptance: request.reactionAcceptance,
                    repository: repository,
                    palette: configuration.appearance.palette
                ) { _, reaction in
                    request.selectReaction(reaction)
                }
                .overlay(alignment: .topLeading) {
                    productionSheetE2EMarker("reaction:\(noteID)")
                }
            } else {
                unavailable("リアクション")
            }
        case let .share(noteID):
            if let repository = coordinator.repository(for: configuration.currentScope)
                as? any MissCatNoteContextRepository,
               let url = repository.notePermalink(noteID: noteID) {
                MissCatApplicationShareSheet(url: url)
                    .overlay(alignment: .topLeading) {
                        MissCatProductionAccessibilityMarker(identifier: "share.sheet")
                    }
                    .overlay(alignment: .topLeading) {
                        productionSheetE2EMarker("share:\(noteID)")
                    }
            } else {
                unavailable("共有")
            }
        }
    }

    @ViewBuilder
    private func fullScreenDestination(
        _ destination: MissCatApplicationFullScreenDestination
    ) -> some View {
        switch destination {
        case let .compose(intent):
            if let viewModel = composeViewModel(intent) {
                MissCatComposeScreen(
                    viewModel: viewModel,
                    onComplete: rootStore.router.dismissFullScreen,
                    onCancel: rootStore.router.dismissFullScreen
                )
            } else {
                unavailable("投稿")
            }
        case let .media(attachmentID):
            if let attachment = coordinator.attachment(id: attachmentID) {
                MissCatMediaViewer(attachments: [attachment], selectedID: attachment.id)
            } else { unavailable("メディア") }
        }
    }

    private func profileView(
        root: MissCatProfileFamilyView.Root,
        palette: MissCatVisualPalette,
        showsBack: Bool
    ) -> AnyView {
        guard let account = coordinator.profileAccount else {
            return AnyView(unavailable("プロフィール"))
        }
        guard let repositoryFactory = coordinator.profileRepositoryFactory else {
            return AnyView(unavailable("プロフィール"))
        }
        return AnyView(
            MissCatProfileFamilyView(
                root: root,
                account: account,
                palette: palette,
                shellOwnership: .outerShell,
                rootProfileShowsBack: showsBack,
                repositoryFactory: repositoryFactory,
                onExit: rootStore.router.pop,
                onOpenURL: { rootStore.router.open(.externalURL($0)) },
                onOpenImage: { openURL($0) },
                onOpenSettings: { rootStore.router.presentSheet(.settings) },
                onSelectRoot: { section in selectRoot(section) },
                onCompose: { rootStore.router.presentFullScreen(.compose(.new)) },
                onOpenDestination: openProfileDestination
            )
        )
    }

    private func openProfileDestination(_ destination: MissCatProfileFamilyDestination) {
        switch destination {
        case let .profile(userID):
            rootStore.router.open(.profile(userID: userID))
        case let .userList(kind):
            rootStore.router.open(.profileUserList(kind))
        case let .editProfile(profile):
            rootStore.router.open(.profileEditor(profile))
        }
    }

    private func settingsView(
        palette: MissCatVisualPalette,
        close: @escaping () -> Void
    ) -> some View {
        let repository = MissCatLegacySettingsRepository()
        return MissCatSettingsRootView(
            designStore: MissCatDesignSettingsStore(repository: repository),
            reactionStore: MissCatReactionSettingsStore(repository: repository),
            palette: palette,
            licenses: MissCatLicenseCatalog.entries(),
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0",
            onRootRelaunchRequired: { Task { await rootStore.restore() } },
            onClose: close
        )
    }

    private func accountsView(
        palette: MissCatVisualPalette,
        close: @escaping () -> Void
    ) -> some View {
        let repository = MissCatLegacySettingsRepository()
        return MissCatAccountsRootView(
            store: MissCatAccountStore(repository: repository),
            palette: palette,
            profileDestination: { account, dismiss in
                guard let user = Cache.UserDefaults.shared.getUser(userId: account.id),
                      let token = user.apiKey else {
                    return AnyView(unavailable("プロフィール"))
                }
                return AnyView(
                    MissCatProfileFamilyView(
                        root: .profile(userID: account.userID),
                        account: MissCatProfileAccount(
                            userID: user.userId,
                            instance: user.instance,
                            token: token
                        ),
                        palette: palette,
                        onExit: dismiss
                    )
                )
            },
            onAccountSwitched: {
                close()
                Task { await rootStore.restore() }
            },
            onConfiguredTabsChanged: { Task { await rootStore.restore() } }
        )
    }

    private var feedNavigationActions: MissCatFeedNavigationActions {
        MissCatFeedNavigationActions(
            openUser: { rootStore.router.open(.profile(userID: $0)) },
            openNote: { rootStore.router.open(.note(id: $0)) },
            openAttachment: {
                coordinator.remember($0)
                rootStore.router.presentFullScreen(.media(attachmentID: $0.id))
            },
            openHashtag: { rootStore.router.open(.hashtag($0)) },
            reply: { rootStore.router.presentFullScreen(.compose(.reply(noteID: $0))) },
            chooseReaction: { request in
                coordinator.prepareReaction(request)
                rootStore.router.presentSheet(.reactionPicker(noteID: request.noteID))
            },
            share: { rootStore.router.presentSheet(.share(noteID: $0)) }
        )
    }

    private var discoveryNavigationActions: MissCatDiscoveryNavigationActions {
        MissCatDiscoveryNavigationActions(
            openUser: { rootStore.router.open(.profile(userID: $0)) },
            openNote: { rootStore.router.open(.note(id: $0)) },
            openAttachment: {
                coordinator.remember($0)
                rootStore.router.presentFullScreen(.media(attachmentID: $0.id))
            },
            openHashtag: { rootStore.router.open(.hashtag($0)) },
            openSearch: { rootStore.router.open(.search(query: $0)) }
        )
    }

    private var notificationNavigationActions: MissCatNotificationNavigationActions {
        MissCatNotificationNavigationActions { route in
            switch route {
            case let .user(id): rootStore.router.open(.profile(userID: id))
            case let .note(id): rootStore.router.open(.note(id: id))
            }
        }
    }

    private var messageNavigationActions: MissCatMessageNavigationActions {
        MissCatMessageNavigationActions(
            openConversation: {
                coordinator.remember($0)
                rootStore.router.open(.conversation(userID: $0.id))
            },
            openRoute: { route in
                switch route {
                case let .externalURL(url): rootStore.router.open(.externalURL(url))
                case let .hashtag(tag): rootStore.router.open(.hashtag(tag))
                case let .mention(acct):
                    if let repository = coordinator.messagingRepository
                        as? MissCatNativeNotificationMessagingRepository {
                        Task {
                            if let person = try? await repository.resolvePerson(acct: acct) {
                                coordinator.remember(person)
                                rootStore.router.open(.profile(userID: person.id))
                            }
                        }
                    }
                }
            }
        )
    }

    private var navigationPathBinding: Binding<[MissCatApplicationRoute]> {
        Binding(
            get: { rootStore.router.path },
            set: { rootStore.router.replacePath($0) }
        )
    }

    private var sectionBinding: Binding<MissCatRootSection> {
        Binding(
            get: { rootStore.router.selectedSection },
            set: { section in selectRoot(section) }
        )
    }

    private func timelineBinding(
        _ configuration: MissCatShellConfiguration
    ) -> Binding<String> {
        Binding(
            get: { rootStore.router.timelineSelection.selectedID },
            set: { id in
                if case .changed = rootStore.router.selectTimeline(id) {
                    coordinator.persistTimelineSelection(id, scope: configuration.currentScope)
                }
            }
        )
    }

    private var sheetBinding: Binding<MissCatApplicationSheetDestination?> {
        Binding(
            get: { rootStore.router.sheetDestination },
            set: {
                if $0 == nil {
                    coordinator.clearReactionRequest()
                    rootStore.router.dismissSheet()
                }
            }
        )
    }

    private var productionRouteBackButton: some View {
        Button(action: rootStore.router.pop) {
            Image(systemName: "chevron.left")
        }
        .accessibilityLabel("戻る")
        .accessibilityIdentifier("production.route.back")
    }

    private var fullScreenBinding: Binding<MissCatApplicationFullScreenDestination?> {
        Binding(
            get: { rootStore.router.fullScreenDestination },
            set: { if $0 == nil { rootStore.router.dismissFullScreen() } }
        )
    }

    private func selectTimeline(
        _ id: String,
        origin: MissCatTimelineSelectionOrigin,
        configuration: MissCatShellConfiguration
    ) {
        let previous = rootStore.router.timelineSelection.selectedID
        let result: MissCatApplicationTabSelectionResult
        if origin == .swipe,
           let previousIndex = configuration.timelinePages.firstIndex(where: { $0.id == previous }),
           let targetIndex = configuration.timelinePages.firstIndex(where: { $0.id == id }) {
            result = targetIndex > previousIndex
                ? rootStore.router.swipeTimelineLeft()
                : rootStore.router.swipeTimelineRight()
        } else {
            result = rootStore.router.selectTimeline(id)
        }
        if case let .changed(selected, _) = result {
            coordinator.persistTimelineSelection(selected, scope: configuration.currentScope)
        }
    }

    private func selectedTimelineAccessibilityID(
        _ configuration: MissCatShellConfiguration
    ) -> String {
        let selectedID = rootStore.router.timelineSelection.selectedID
        return configuration.timelinePages.first(where: { $0.id == selectedID })?.accessibilityID
            ?? selectedID
    }

    private func selectRoot(_ section: MissCatRootSection) {
        _ = rootStore.router.selectRoot(section)
    }

    private func reselect(_ section: MissCatRootSection) {
        rootStore.router.popToRoot(in: section)
        if section == .home { coordinator.scrollHomeToTop() }
        if section == .notifications { coordinator.notificationScrollCoordinator.scrollToTop() }
    }

    private func switchAccount(_ scope: MissCatShellAccountScope) {
        let accountID = MissCatApplicationAccountID(instance: scope.instance, userID: scope.userID)
        Task {
            await rootStore.switchAccount(to: accountID)
        }
    }

    private func composeMode(_ intent: MissCatApplicationComposeIntent) -> MissCatComposeMode {
        switch intent {
        case .new: .note
        case let .reply(noteID): .reply(composeTarget(noteID))
        case let .quote(noteID): .quote(composeTarget(noteID))
        }
    }

    private func composeViewModel(
        _ intent: MissCatApplicationComposeIntent
    ) -> MissCatComposeViewModel? {
        let mode = composeMode(intent)
        guard let composeSession = coordinator.composeSession else { return nil }
#if DEBUG
        if MissCatProductionRootE2ELaunch.isRequested {
            return MissCatComposeFactory.makeViewModel(
                mode: mode,
                session: composeSession,
                accountSelectionObserver: {
                    MissCatProductionRootE2EState.shared.recordComposeSelection($0)
                },
                transport: MissCatProductionRootE2EComposeTransport(),
                scopeSelectionObserver: {
                    MissCatProductionRootE2EState.shared.recordComposeSubmissionScope($0)
                }
            )
        }
#endif
        return MissCatComposeFactory.makeViewModel(
            mode: mode,
            session: composeSession,
            visibilityPersistence: coordinator.persistComposeVisibility
        )
    }

    private func composeTarget(_ noteID: String) -> MissCatComposeTarget {
        MissCatComposeTarget(
            id: noteID,
            username: session.currentAccount.username,
            instance: session.currentAccount.instance,
            text: ""
        )
    }

    private func unavailable(_ title: String) -> some View {
        ContentUnavailableView(
            "\(title)を利用できません",
            systemImage: "exclamationmark.triangle"
        )
    }

    private var fixtureVisualReadyPrefix: String? {
#if DEBUG
        MissCatProductionRootE2ELaunch.isRequested ? "production.root.visual-ready" : nil
#else
        nil
#endif
    }

    @ViewBuilder
    private func productionSheetE2EMarker(_ destination: String) -> some View {
#if DEBUG
        if MissCatProductionRootE2ELaunch.isRequested {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityIdentifier("production.sheet.destination")
                .accessibilityValue(destination)
        }
#endif
    }

    @ViewBuilder
    private var productionRootE2EStateMarkers: some View {
#if DEBUG
        if MissCatProductionRootE2ELaunch.isRequested {
            VStack(spacing: 0) {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityElement()
                    .accessibilityIdentifier("production.root.persisted-account")
                    .accessibilityValue(
                        MissCatProductionRootE2EState.shared.persistedAccountID.rawValue
                    )
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityElement()
                    .accessibilityIdentifier("production.root.compose-selection-request")
                    .accessibilityValue(
                        MissCatProductionRootE2EState.shared.lastComposeSelectionRequest ?? ""
                    )
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityElement()
                    .accessibilityIdentifier("production.root.compose-submission-account")
                    .accessibilityValue(
                        MissCatProductionRootE2EState.shared.composeSubmissionAccountID ?? ""
                    )
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityElement()
                    .accessibilityIdentifier("production.root.route")
                    .accessibilityValue(productionRouteE2EValue)
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityElement()
                    .accessibilityIdentifier("production.root.sheet")
                    .accessibilityValue(rootStore.router.sheetDestination?.id ?? "none")
            }
        }
#endif
    }

    private var productionRouteE2EValue: String {
        guard let route = rootStore.router.path.last else {
            return "root:\(rootStore.router.selectedSection.rawValue)"
        }
        switch route {
        case .discovery: return "discovery"
        case let .note(id): return "note:\(id)"
        case let .notification(id): return "notification:\(id)"
        case let .profile(userID): return "profile:\(userID)"
        case let .profileUserList(kind): return "profile-list:\(kind.id)"
        case let .profileEditor(profile): return "profile-editor:\(profile.id)"
        case let .userTimeline(userID, includesReplies, onlyFiles):
            return "user-timeline:\(userID):\(includesReplies):\(onlyFiles)"
        case let .conversation(userID): return "conversation:\(userID)"
        case let .search(query): return "search:\(query)"
        case let .hashtag(tag): return "hashtag:\(tag)"
        case .settings: return "settings"
        case .accounts: return "accounts"
        case let .externalURL(url): return "external:\(url.absoluteString)"
        }
    }
}

private struct MissCatExternalURLDestination: View {
    @Environment(\.openURL) private var openURL
    let url: URL

    var body: some View {
        ContentUnavailableView {
            Label("外部リンク", systemImage: "safari")
        } description: {
            Text(url.absoluteString)
        } actions: {
            Button("Safariで開く") { openURL(url) }
        }
        .navigationTitle("リンク")
    }
}

private struct MissCatProductionAccessibilityMarker: View {
    let identifier: String

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(identifier)
            .accessibilityIdentifier(identifier)
            .allowsHitTesting(false)
    }
}

private struct MissCatApplicationShareSheet: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL

    var body: some View {
        VStack(spacing: 20) {
            Label("ノートを共有", systemImage: "square.and.arrow.up")
                .font(.headline)

            ShareLink(item: url) {
                Label("共有先を選ぶ", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("share.link")

            Button("閉じる", action: dismiss.callAsFunction)
                .buttonStyle(.bordered)
        }
        .padding(24)
        .presentationDetents([.medium])
    }
}

#if DEBUG
/// The sole mutable fixture flag is serialized by `reactionLock`.
private final class MissCatProductionRootE2ERepository:
    MissCatNoteContextRepository,
    MissCatDiscoveryRepository,
    MissCatNotificationsRepository,
    MissCatMessagingRepository,
    @unchecked Sendable
{
    let accountScope: MissCatAccountScope
    let accountIdentifier: String
    let currentServerUserID: String
    private let reactionLock = NSLock()
    private var shouldFailFirstReaction = true

    init(account: MissCatShellAccountScope) {
        accountScope = MissCatAccountScope(
            accountID: account.userID,
            username: account.username,
            host: account.displayInstance,
            accessToken: "fixture-token"
        )
        accountIdentifier = MissCatAccountIdentity.storageKey(
            instance: account.instance,
            userId: account.userID
        )
        currentServerUserID = account.userID
    }

    func fetchPage(
        source: MissCatFeedSource,
        cursor: String?,
        limit: Int
    ) async throws -> MissCatFeedPage {
        guard cursor == nil else { return MissCatFeedPage(notes: [], hasMore: false) }
        let prefix = source.accessibilityName
        return MissCatFeedPage(
            notes: (0 ..< min(limit, 12)).map { index in
                MissCatNote(
                    id: "\(prefix)-\(index)",
                    author: MissCatNoteAuthor(
                        id: "fixture-author-\(index)",
                        name: "Miss Cat",
                        username: "misscat",
                        isCat: true
                    ),
                    createdAt: Date(timeIntervalSince1970: 1_596_288_600 - Double(index * 60)),
                    text: index == 0 ? "Production SwiftUI root fixture 🐈" : "Fixture note \(index + 1)"
                )
            },
            hasMore: false
        )
    }

    func fetchThread(noteID: String, replyLimit: Int) async throws -> MissCatNoteThread {
        let note = MissCatNote(
            id: noteID,
            author: MissCatNoteAuthor(
                id: "fixture-author",
                name: "Miss Cat",
                username: "misscat"
            ),
            createdAt: Date(timeIntervalSince1970: 1_596_288_600),
            text: "Production note detail"
        )
        return MissCatNoteThread(ancestors: [], note: note, replies: [])
    }

    func realtimeEvents(
        source: MissCatFeedSource,
        capturing noteIDs: [String]
    ) -> AsyncStream<MissCatRealtimeEvent> {
        AsyncStream { $0.yield(.connected(true)) }
    }

    func perform(_ action: MissCatFeedAction) async throws {
        guard case .addReaction = action else { return }
        let shouldFail = reactionLock.withLock {
            defer { shouldFailFirstReaction = false }
            return shouldFailFirstReaction
        }
        if shouldFail { throw MissCatFeedRepositoryError.rejectedAction }
    }

    func notePermalink(noteID: String) -> URL? {
        URL(string: "https://\(accountScope.host)/notes/\(noteID)")
    }

    func fetchURLPreview(for url: URL) async throws -> MissCatURLPreview {
        MissCatURLPreview(sourceURL: url, title: "Production root fixture")
    }

    func fetchTrends() async throws -> [MissCatTrend] {
        [
            MissCatTrend(tag: "SwiftUI", chart: [2, 3, 5], usersCount: 42),
            MissCatTrend(tag: "MissCat", chart: [1, 4, 6], usersCount: 21),
        ]
    }

    func searchNotes(
        query: String,
        cursor: String?,
        limit: Int
    ) async throws -> MissCatDiscoveryPage<MissCatNote> {
        let page = try await fetchPage(
            source: .search(query: query),
            cursor: cursor,
            limit: limit
        )
        return MissCatDiscoveryPage(
            items: page.notes,
            nextCursor: page.hasMore ? page.notes.last?.id : nil
        )
    }

    func searchUsers(
        query: String,
        offset: Int,
        limit: Int
    ) async throws -> MissCatDiscoveryPage<MissCatProfileUser> {
        guard offset == 0 else { return MissCatDiscoveryPage(items: [], nextCursor: nil) }
        let users = [
            profileUser("fixture-author-0"),
            profileUser(currentServerUserID),
        ]
        return MissCatDiscoveryPage(items: Array(users.prefix(limit)), nextCursor: nil)
    }

    func profileUser(_ userID: String) -> MissCatProfileUser {
        MissCatProfileUser(
            id: userID,
            name: userID == currentServerUserID ? "Miss Cat" : "Route Author",
            username: userID == currentServerUserID ? accountScope.username : "route-author",
            host: accountScope.host,
            description: "Production root typed-route fixture",
            isCat: true,
            followersCount: 42,
            followingCount: 21,
            notesCount: 12
        )
    }

    func fetchNotifications(cursor: String?, limit: Int) async throws -> MissCatNotificationPage {
        MissCatNotificationPage(notifications: [], hasMore: false)
    }

    func realtimeNotifications() -> AsyncStream<MissCatNotificationRealtimeEvent> {
        AsyncStream { $0.yield(.connected(true)) }
    }

    func fetchConversations(limit: Int) async throws -> [MissCatConversation] { [] }

    func fetchMessages(
        peer: MissCatPerson,
        cursor: String?,
        limit: Int
    ) async throws -> MissCatMessagePage {
        MissCatMessagePage(messages: [], hasMore: false)
    }

    func sendText(
        _ text: String,
        to peer: MissCatPerson,
        requestID: UUID
    ) async throws -> MissCatDirectMessage {
        MissCatDirectMessage(
            id: requestID.uuidString,
            senderID: accountScope.accountID,
            recipientID: peer.id,
            text: text,
            createdAt: Date(),
            isRead: true
        )
    }
}

private final class MissCatProductionRootE2EProfileRepository: MissCatProfileRepository {
    let account: MissCatProfileAccount

    init(account: MissCatProfileAccount) {
        self.account = account
    }

    func profile(userID: String) async throws -> MissCatProfileUser {
        fixtureUser(userID)
    }

    func relationship(userID: String) async throws -> Bool { false }

    func notes(
        userID: String,
        tab: MissCatProfileTimelineTab,
        cursor: String?,
        limit: Int
    ) async throws -> MissCatProfilePage<MissCatProfileNote> {
        guard cursor == nil, tab != .media else {
            return MissCatProfilePage(items: [], nextCursor: nil)
        }
        let user = fixtureUser(userID)
        return MissCatProfilePage(
            items: [
                MissCatProfileNote(
                    id: "profile-route-note",
                    createdAt: "2026-08-07T00:00:00.000Z",
                    text: "Production root profile route",
                    user: user,
                    reactions: ["👍": 1]
                ),
            ],
            nextCursor: nil
        )
    }

    func users(
        kind: MissCatUserListKind,
        cursor: String?,
        limit: Int
    ) async throws -> MissCatProfilePage<MissCatProfileUser> {
        guard cursor == nil else { return MissCatProfilePage(items: [], nextCursor: nil) }
        return MissCatProfilePage(
            items: [fixtureUser("fixture-author-0"), fixtureUser(account.userID)],
            nextCursor: nil
        )
    }

    func setFollowing(_ following: Bool, userID: String) async throws {}

    func uploadProfileImage(
        data: Data,
        filename: String,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> String {
        progress(1)
        return "fixture-profile-upload"
    }

    func deleteProfileImage(fileID: String) async throws {}

    func updateProfile(patch: MissCatProfileUpdatePatch) async throws -> MissCatProfileUser {
        fixtureUser(account.userID)
    }

    private func fixtureUser(_ userID: String) -> MissCatProfileUser {
        MissCatProfileUser(
            id: userID,
            name: userID == account.userID ? "Miss Cat" : "Route Author",
            username: userID == account.userID ? "misscat" : "route-author",
            host: MissCatAccountIdentity.normalizedInstance(account.instance),
            description: "Production root typed-route fixture",
            isCat: true,
            followersCount: 42,
            followingCount: 21,
            notesCount: 12
        )
    }
}
#endif
