import SwiftUI
import UIKit

public struct MissCatDiscoveryNavigationActions {
    public var openUser: (String) -> Void
    public var openNote: (String) -> Void
    public var openAttachment: (MissCatNoteAttachment) -> Void
    public var openHashtag: (String) -> Void

    public init(
        openUser: @escaping (String) -> Void = { _ in },
        openNote: @escaping (String) -> Void = { _ in },
        openAttachment: @escaping (MissCatNoteAttachment) -> Void = { _ in },
        openHashtag: @escaping (String) -> Void = { _ in }
    ) {
        self.openUser = openUser
        self.openNote = openNote
        self.openAttachment = openAttachment
        self.openHashtag = openHashtag
    }
}

/// Native discovery surface. Tap and horizontal swipe both drive the same tab
/// selection, so there is one state owner for the result pages.
public struct MissCatDiscoveryScreen: View {
    @StateObject private var store: MissCatDiscoveryStore
    @FocusState private var searchIsFocused: Bool

    private let instanceDisplayName: String
    private let palette: MissCatVisualPalette
    private let navigationActions: MissCatDiscoveryNavigationActions

    public init(
        store: MissCatDiscoveryStore,
        instanceDisplayName: String,
        palette: MissCatVisualPalette = .legacyLight,
        navigationActions: MissCatDiscoveryNavigationActions = .init()
    ) {
        _store = StateObject(wrappedValue: store)
        self.instanceDisplayName = instanceDisplayName
        self.palette = palette
        self.navigationActions = navigationActions
    }

    public var body: some View {
        VStack(spacing: 0) {
            searchBar

            if store.showsTrends {
                trendContent
            } else {
                resultTabs
                resultPager
            }
        }
        .background(palette.base.ignoresSafeArea())
        .tint(palette.accent)
        .task { store.loadTrends() }
        .overlay(alignment: .topLeading) {
            if store.visualReady {
                Text("ready")
                    .font(.system(size: 1))
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .accessibilityLabel("visualReady")
                    .accessibilityValue("true")
                    .accessibilityIdentifier("discovery.visualReady")
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(palette.strong)

            TextField("検索", text: $store.query)
                .focused($searchIsFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit {
                    searchIsFocused = false
                    store.submitSearch()
                }
                .accessibilityIdentifier("discovery.query")

            if !store.query.isEmpty {
                Button {
                    store.cancelSearch()
                    searchIsFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(palette.strong)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("検索をキャンセル")
                .accessibilityIdentifier("discovery.cancel")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.border.opacity(0.65)).frame(height: 0.5)
        }
    }

    @ViewBuilder
    private var trendContent: some View {
        switch store.trendPhase {
        case .idle, .loading:
            stateView(symbol: nil, title: "トレンドを読み込み中…")
                .accessibilityIdentifier("discovery.trends.loading")
        case .empty:
            stateView(symbol: "number", title: "トレンドはありません")
                .accessibilityIdentifier("discovery.trends.empty")
        case .offline:
            stateView(
                symbol: "wifi.slash",
                title: "オフラインです",
                message: "インターネット接続を確認してください",
                retry: store.retryTrends
            )
            .accessibilityIdentifier("discovery.trends.offline")
        case let .failed(message):
            stateView(
                symbol: "exclamationmark.triangle",
                title: "トレンドを読み込めませんでした",
                message: message,
                retry: store.retryTrends
            )
            .accessibilityIdentifier("discovery.trends.error")
        case .loaded:
            ScrollView {
                LazyVStack(spacing: 0) {
                    Text("\(capitalizedInstance)でのトレンド")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(palette.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .frame(height: 54)
                        .accessibilityIdentifier("discovery.trends.title")

                    ForEach(store.trends) { trend in
                        Button {
                            searchIsFocused = false
                            store.activateTrend(trend)
                        } label: {
                            Text("#\(trend.tag)")
                                .font(.system(size: 17))
                                .foregroundStyle(palette.text)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .frame(height: 60)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("discovery.trend.\(trend.tag)")
                    }
                }
            }
            .scrollIndicators(.hidden)
            .accessibilityIdentifier("discovery.trends.list")
        }
    }

    private var resultTabs: some View {
        HStack(spacing: 0) {
            Text("検索")
                .font(.system(size: 14))
                .foregroundStyle(palette.text)
                .fixedSize()

            Spacer().frame(width: 16)

            ForEach(MissCatDiscoveryTab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { store.select(tab) }
                } label: {
                    Text(tab.legacyTitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(store.selectedTab == tab ? Color.white : palette.strong)
                        .frame(width: tab == .notes ? 45 : 66, height: 30)
                        .background(
                            store.selectedTab == tab ? palette.accent : Color.clear,
                            in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("discovery.tab.\(tab.rawValue)")
                .accessibilityAddTraits(store.selectedTab == tab ? .isSelected : [])

                if tab == .notes { Spacer().frame(width: 17) }
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, 20)
        .frame(height: 50)
        .background(palette.base)
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.border.opacity(0.65)).frame(height: 0.5)
        }
        .simultaneousGesture(resultSwipeGesture)
    }

    private var resultPager: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                noteResults
                    .frame(width: proxy.size.width)
                    .padding(.top, 8)
                userResults
                    .frame(width: proxy.size.width)
                    .padding(.top, 7)
            }
            .frame(width: proxy.size.width * 2, alignment: .leading)
            .offset(x: store.selectedTab == .notes ? 0 : -proxy.size.width)
            .animation(.easeInOut(duration: 0.2), value: store.selectedTab)
            .contentShape(Rectangle())
        }
        .clipped()
        .highPriorityGesture(resultSwipeGesture)
    }

    private var resultSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 18)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height),
                      abs(value.translation.width) >= 44
                else { return }
                store.select(value.translation.width < 0 ? .users : .notes)
            }
    }

    @ViewBuilder
    private var noteResults: some View {
        switch store.noteResults.phase {
        case .idle where store.noteResults.items.isEmpty,
             .loading where store.noteResults.items.isEmpty:
            stateView(symbol: nil, title: "投稿を検索中…")
                .accessibilityIdentifier("discovery.notes.loading")
        case .empty:
            stateView(symbol: "text.bubble", title: "検索結果はありません")
                .accessibilityIdentifier("discovery.notes.empty")
        case .offline:
            stateView(symbol: "wifi.slash", title: "オフラインです", retry: { store.retry(.notes) })
                .accessibilityIdentifier("discovery.notes.offline")
        case let .failed(message):
            stateView(
                symbol: "exclamationmark.triangle",
                title: "投稿を検索できませんでした",
                message: message,
                retry: { store.retry(.notes) }
            )
            .accessibilityIdentifier("discovery.notes.error")
        default:
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.noteResults.items) { note in
                        MissCatDiscoveryLegacyNoteRow(
                            note: note,
                            palette: palette,
                            onOpenUser: navigationActions.openUser,
                            onOpenNote: navigationActions.openNote
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { navigationActions.openNote(note.noteID) }
                        .onAppear { store.loadMoreNotesIfNeeded(currentNoteID: note.id) }
                        .accessibilityIdentifier("discovery.note.\(note.id)")
                    }
                    paginationFooter(
                        isLoading: store.noteResults.isLoadingMore,
                        error: store.noteResults.paginationError,
                        retry: store.retryNotePagination
                    )
                }
            }
            .scrollIndicators(.hidden)
            .accessibilityIdentifier("discovery.notes.list")
        }
    }

    @ViewBuilder
    private var userResults: some View {
        switch store.userResults.phase {
        case .idle where store.userResults.items.isEmpty,
             .loading where store.userResults.items.isEmpty:
            stateView(symbol: nil, title: "ユーザーを検索中…")
                .accessibilityIdentifier("discovery.users.loading")
        case .empty:
            stateView(symbol: "person.2.slash", title: "ユーザーは見つかりませんでした")
                .accessibilityIdentifier("discovery.users.empty")
        case .offline:
            stateView(symbol: "wifi.slash", title: "オフラインです", retry: { store.retry(.users) })
                .accessibilityIdentifier("discovery.users.offline")
        case let .failed(message):
            stateView(
                symbol: "exclamationmark.triangle",
                title: "ユーザーを検索できませんでした",
                message: message,
                retry: { store.retry(.users) }
            )
            .accessibilityIdentifier("discovery.users.error")
        default:
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.userResults.items) { user in
                        Button { navigationActions.openUser(user.id) } label: {
                            MissCatDiscoveryLegacyUserRow(user: user, palette: palette)
                        }
                        .buttonStyle(.plain)
                        .onAppear { store.loadMoreUsersIfNeeded(currentUserID: user.id) }
                        .accessibilityIdentifier("discovery.user.\(user.id)")
                    }
                    paginationFooter(
                        isLoading: store.userResults.isLoadingMore,
                        error: store.userResults.paginationError,
                        retry: store.retryUserPagination
                    )
                }
            }
            .scrollIndicators(.hidden)
            .accessibilityIdentifier("discovery.users.list")
        }
    }

    @ViewBuilder
    private func paginationFooter(
        isLoading: Bool,
        error: String?,
        retry: @escaping () -> Void
    ) -> some View {
        if isLoading {
            ProgressView()
                .tint(palette.accent)
                .frame(height: 52)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("discovery.pagination.loading")
        } else if let error {
            VStack(spacing: 8) {
                Text(error).font(.system(size: 12)).foregroundStyle(palette.strong)
                Button("再試行", action: retry)
                    .buttonStyle(.borderedProminent)
                    .tint(palette.accent)
                    .accessibilityIdentifier("discovery.pagination.retry")
            }
            .padding(12)
            .frame(maxWidth: .infinity)
        }
    }

    private func stateView(
        symbol: String?,
        title: String,
        message: String? = nil,
        retry: (() -> Void)? = nil
    ) -> some View {
        VStack(spacing: 12) {
            Spacer()
            if let symbol {
                Image(systemName: symbol).font(.system(size: 31)).foregroundStyle(palette.strong)
            } else {
                ProgressView().tint(palette.accent)
            }
            Text(title).font(.system(size: 16, weight: .medium)).foregroundStyle(palette.text)
            if let message { Text(message).font(.system(size: 13)).foregroundStyle(palette.strong) }
            if let retry {
                Button("再試行", action: retry)
                    .buttonStyle(.borderedProminent)
                    .tint(palette.accent)
            }
            Spacer()
        }
        .multilineTextAlignment(.center)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.base)
    }

    private var capitalizedInstance: String {
        guard let first = instanceDisplayName.first else { return "このインスタンス" }
        return first.uppercased() + instanceDisplayName.dropFirst()
    }
}

/// Search results preserve the compact geometry of the retired UIKit cells
/// while retaining native SwiftUI routing at the row and avatar boundaries.
private struct MissCatDiscoveryLegacyNoteRow: View {
    let note: MissCatNote
    let palette: MissCatVisualPalette
    let onOpenUser: (String) -> Void
    let onOpenNote: (String) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button { onOpenUser(note.author.id) } label: {
                legacyAvatar(url: note.author.avatarURL)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(note.author.name)のプロフィール")

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(note.author.name)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text(note.author.acct)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.strong)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .frame(height: 27)

                Text(MissCatNativeMFMRenderer.render(note.text))
                    .font(.system(size: 14))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 3)

                Spacer(minLength: 0)

                Text("↩  \(note.repliesCount)          ⇄  \(note.renoteCount)          ♡  \(note.reactions.reduce(0) { $0 + $1.count })          ···")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.strong)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(palette.text)
        .padding(.leading, 20)
        .padding(.trailing, 20)
        .padding(.top, 9)
        .padding(.bottom, 11)
        .frame(height: 148)
        .background(palette.base)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(red: 226 / 255, green: 229 / 255, blue: 234 / 255))
                .frame(height: MissCatLegacyMetrics.hairlineWidth)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
    }

    private func legacyAvatar(url: URL?) -> some View {
        AsyncImage(url: url) { phase in
            if case let .success(image) = phase {
                image.resizable().scaledToFill()
            } else {
                Circle().fill(Color(white: 0.92))
            }
        }
        .frame(width: 50, height: 50)
        .clipShape(Circle())
    }
}

private struct MissCatDiscoveryLegacyUserRow: View {
    let user: MissCatProfileUser
    let palette: MissCatVisualPalette

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AsyncImage(url: user.avatarURL) { phase in
                if case let .success(image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    Circle().fill(Color(white: 0.92))
                }
            }
            .frame(width: 50, height: 50)
            .clipShape(Circle())
            .padding(.top, 11)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(user.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    Text(user.acct)
                        .font(.system(size: 12))
                        .foregroundStyle(palette.strong)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                Text(user.description?.isEmpty == false ? user.description! : "自己紹介文はありません")
                    .font(.system(size: 13))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(palette.text)
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .frame(height: 100, alignment: .top)
        .background(palette.base)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(red: 226 / 255, green: 229 / 255, blue: 234 / 255))
                .frame(height: MissCatLegacyMetrics.hairlineWidth)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Account-scoped production boundary and typed navigation

public enum MissCatDiscoveryRoute: Hashable, Sendable {
    case note(String)
    case profile(String)
    case userTimeline(userID: String, includesReplies: Bool, onlyFiles: Bool)
    case userList(String)
    case search(query: String, tab: MissCatDiscoveryTab)
    case media(String)
    case hashtag(String)
}

@MainActor
final class MissCatDiscoveryRouter: ObservableObject {
    @Published var path: [MissCatDiscoveryRoute] = []
    private var attachments: [String: MissCatNoteAttachment] = [:]

    func open(_ route: MissCatDiscoveryRoute) {
        path.append(route)
    }

    func open(_ attachment: MissCatNoteAttachment) {
        attachments[attachment.id] = attachment
        path.append(.media(attachment.id))
    }

    func attachment(id: String) -> MissCatNoteAttachment? {
        attachments[id]
    }

    func pop() {
        if !path.isEmpty { path.removeLast() }
    }

    func reset() {
        path.removeAll()
        attachments.removeAll()
    }
}

/// All repositories in this object are constructed from one immutable session
/// snapshot. No request path can observe a later global-current-account value.
@MainActor
final class MissCatDiscoveryAccountGeneration {
    let id = UUID()
    let session: MissCatFeedSession
    let discoveryRepository: MissCatDiscoveryRepository
    let feedRepository: MissCatFeedRepository
    let profileAccount: MissCatProfileAccount
    let store: MissCatDiscoveryStore
    let previewProfile: ((String) -> MissCatProfileUser)?

    init(
        session: MissCatFeedSession,
        discoveryRepository: MissCatDiscoveryRepository? = nil,
        feedRepository: MissCatFeedRepository? = nil,
        previewProfile: ((String) -> MissCatProfileUser)? = nil,
        pageSize: Int = 20
    ) {
        self.session = session
        let discovery = discoveryRepository
            ?? MissCatMisskeyDiscoveryRepository(session: session)
        let feed = feedRepository
            ?? MissCatMisskeyFeedRepository(session: session)
        self.discoveryRepository = discovery
        self.feedRepository = feed
        self.previewProfile = previewProfile
        profileAccount = MissCatProfileAccount(
            userID: session.accountID,
            instance: session.instance,
            token: session.apiKey
        )
        store = MissCatDiscoveryStore(repository: discovery, pageSize: pageSize)
    }

    var accountIdentifier: String { session.compositeAccountID }

    func cancel() {
        store.cancelForAccountSwitch()
    }
}

@MainActor
final class MissCatDiscoveryAccountCoordinator {
    private(set) var generation: MissCatDiscoveryAccountGeneration

    init(generation: MissCatDiscoveryAccountGeneration) {
        self.generation = generation
    }

    @discardableResult
    func replace(with next: MissCatDiscoveryAccountGeneration) -> Bool {
        guard generation.accountIdentifier != next.accountIdentifier else {
            next.cancel()
            return false
        }
        generation.cancel()
        generation = next
        return true
    }

    func cancel() {
        generation.cancel()
    }
}

/// Temporary UIKit containment boundary used by the ordinary Home pager. The
/// complete discovery hierarchy below this controller is native SwiftUI.
@MainActor
final class MissCatDiscoveryHostingController: UIHostingController<AnyView> {
    private let accountCoordinator: MissCatDiscoveryAccountCoordinator

    var accountIdentifier: String {
        accountCoordinator.generation.accountIdentifier
    }

    init(generation: MissCatDiscoveryAccountGeneration) {
        accountCoordinator = MissCatDiscoveryAccountCoordinator(generation: generation)
        super.init(rootView: AnyView(EmptyView()))
        rebuildRoot()
        view.backgroundColor = UIColor(MissCatDiscoveryPageFactory.currentPalette.base)
    }

    @available(*, unavailable)
    required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func handleHashtag(_ tag: String) {
        accountCoordinator.generation.store.search(hashtag: tag)
    }

    func replaceAccountGeneration(_ generation: MissCatDiscoveryAccountGeneration) {
        guard accountCoordinator.replace(with: generation) else { return }
        rebuildRoot()
    }

    func retire() {
        accountCoordinator.cancel()
    }

    private func rebuildRoot() {
        rootView = AnyView(
            MissCatDiscoveryRoot(generation: accountCoordinator.generation)
        )
    }
}

@MainActor
enum MissCatDiscoveryPageFactory {
    static func makeController(owner: SecureUser?) -> UIViewController {
#if DEBUG
        if MissCatDiscoveryOrdinaryRouteConfiguration.isEnabled {
            let session = MissCatDiscoveryOrdinaryRouteConfiguration.session
            let repository = MissCatDiscoveryOrdinaryRouteRepository()
            return MissCatDiscoveryHostingController(
                generation: MissCatDiscoveryAccountGeneration(
                    session: session,
                    discoveryRepository: repository,
                    feedRepository: repository,
                    previewProfile: repository.user
                )
            )
        }
#endif
        guard let owner,
              let apiKey = owner.apiKey,
              !apiKey.isEmpty
        else {
            return UIHostingController(rootView: AnyView(MissCatDiscoveryUnavailableView()))
        }
        let session = MissCatFeedSession(
            accountID: owner.userId,
            username: owner.username,
            instance: owner.instance,
            apiKey: apiKey
        )
        return MissCatDiscoveryHostingController(
            generation: MissCatDiscoveryAccountGeneration(session: session)
        )
    }

    static var currentPalette: MissCatVisualPalette {
        var palette = Theme.shared.currentModel?.colorMode == .dark
            ? MissCatVisualPalette.legacyDark
            : MissCatVisualPalette.legacyLight
        if let accent = Theme.shared.currentModel?.mainColorHex {
            palette.accent = Color(hex: accent)
        }
        return palette
    }
}

private struct MissCatDiscoveryUnavailableView: View {
    var body: some View {
        ContentUnavailableView(
            "検索を利用できません",
            systemImage: "person.crop.circle.badge.exclamationmark",
            description: Text("アカウントを選択してください")
        )
        .accessibilityIdentifier("discovery.account-unavailable")
    }
}

struct MissCatDiscoveryRoot: View {
    @Environment(\.openURL) private var openURL
    @StateObject private var router = MissCatDiscoveryRouter()

    let generation: MissCatDiscoveryAccountGeneration

    var body: some View {
        NavigationStack(path: $router.path) {
            MissCatDiscoveryScreen(
                store: generation.store,
                instanceDisplayName: generation.session.instance,
                palette: MissCatDiscoveryPageFactory.currentPalette,
                navigationActions: discoveryNavigationActions
            )
            .navigationTitle("検索")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: MissCatDiscoveryRoute.self) { route in
                destination(for: route)
            }
        }
        .id(generation.id)
        .accessibilityIdentifier("home.discovery.native-page")
    }

    private var discoveryNavigationActions: MissCatDiscoveryNavigationActions {
        MissCatDiscoveryNavigationActions(
            openUser: { router.open(.profile($0)) },
            openNote: { router.open(.note($0)) },
            openAttachment: router.open,
            openHashtag: { router.open(.hashtag($0)) }
        )
    }

    private var feedNavigationActions: MissCatFeedNavigationActions {
        MissCatFeedNavigationActions(
            openUser: { router.open(.profile($0)) },
            openNote: { router.open(.note($0)) },
            openAttachment: router.open,
            openHashtag: { router.open(.hashtag($0)) }
        )
    }

    @ViewBuilder
    private func destination(for route: MissCatDiscoveryRoute) -> some View {
        switch route {
        case let .note(noteID):
            MissCatNoteDetailView(
                noteID: noteID,
                repository: generation.feedRepository,
                palette: MissCatDiscoveryPageFactory.currentPalette,
                navigationActions: feedNavigationActions
            )

        case let .profile(userID):
            if let previewProfile = generation.previewProfile {
                MissCatDiscoveryPreviewProfile(user: previewProfile(userID))
            } else {
                MissCatProfileScreen(
                    store: MissCatProfileStore(account: generation.profileAccount, userID: userID),
                    palette: MissCatDiscoveryPageFactory.currentPalette,
                    onBack: router.pop,
                    onOpenURL: routeProfileURL,
                    onOpenImage: { url in
                        router.open(MissCatNoteAttachment(
                            id: "profile-image:\(url.absoluteString)",
                            name: "プロフィール画像",
                            kind: .image,
                            url: url
                        ))
                    },
                    onSelectUser: { router.open(.profile($0)) },
                    onSelectRoot: { _ in router.reset() }
                )
            }

        case let .userTimeline(userID, includesReplies, onlyFiles):
            MissCatUserTimelineView(
                userID: userID,
                includesReplies: includesReplies,
                onlyFiles: onlyFiles,
                repository: generation.feedRepository,
                palette: MissCatDiscoveryPageFactory.currentPalette,
                navigationActions: feedNavigationActions
            )
            .navigationTitle("投稿")
            .navigationBarTitleDisplayMode(.inline)

        case let .userList(listID):
            MissCatUserListTimelineView(
                listID: listID,
                repository: generation.feedRepository,
                palette: MissCatDiscoveryPageFactory.currentPalette,
                navigationActions: feedNavigationActions
            )
            .navigationTitle("リスト")
            .navigationBarTitleDisplayMode(.inline)

        case let .search(query, tab):
            if tab == .notes {
                MissCatSearchResultsView(
                    query: query,
                    repository: generation.feedRepository,
                    palette: MissCatDiscoveryPageFactory.currentPalette,
                    navigationActions: feedNavigationActions
                )
            } else {
                MissCatUserSearchScreen(
                    store: MissCatUserListStore(
                        account: generation.profileAccount,
                        kind: .search(query: query)
                    ),
                    palette: MissCatDiscoveryPageFactory.currentPalette,
                    onSelectUser: { router.open(.profile($0)) }
                )
            }

        case let .media(attachmentID):
            if let attachment = router.attachment(id: attachmentID) {
                MissCatMediaViewer(attachments: [attachment], selectedID: attachment.id)
            } else {
                ContentUnavailableView("メディアがありません", systemImage: "photo")
            }

        case let .hashtag(tag):
            MissCatHashtagResultsView(
                tag: tag,
                repository: generation.feedRepository,
                palette: MissCatDiscoveryPageFactory.currentPalette,
                navigationActions: feedNavigationActions
            )
        }
    }

    private func routeProfileURL(_ url: URL) {
        switch (url.scheme, url.host) {
        case ("misscat", "user"):
            router.open(.profile(url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))))
        case ("misscat", "hashtag"):
            router.open(.hashtag(url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))))
        default:
            openURL(url)
        }
    }
}

private struct MissCatDiscoveryPreviewProfile: View {
    let user: MissCatProfileUser

    var body: some View {
        VStack(spacing: 0) {
            MissCatUserRow(user: user, palette: .legacyLight)
            VStack(spacing: 8) {
                Text(user.displayName).font(.title2.weight(.semibold))
                Text(user.acct).foregroundStyle(.secondary)
                Text(user.description ?? "")
            }
            .padding(24)
            Spacer()
        }
        .navigationTitle(user.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("discovery.profile.destination")
    }
}
