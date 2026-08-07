import PhotosUI
import SwiftUI

public struct MissCatProfileScreen: View {
    @State private var store: MissCatProfileStore
    @State private var presentedList: MissCatUserListKind?
    @State private var confirmsUnfollow = false

    private let palette: MissCatVisualPalette
    private let repositoryFactory: (MissCatProfileAccount) -> MissCatProfileRepository
    private let showsBack: Bool
    private let onBack: () -> Void
    private let onOpenURL: (URL) -> Void
    private let onOpenImage: (URL) -> Void
    private let onSelectUser: (String) -> Void
    private let onOpenUserList: ((MissCatUserListKind) -> Void)?
    private let onEditProfile: (MissCatProfileUser) -> Void
    private let onOpenSettings: () -> Void
    private let onSelectRoot: (MissCatRootSection) -> Void
    private let onCompose: () -> Void
    private let showsBottomBar: Bool

    public init(
        store: MissCatProfileStore,
        palette: MissCatVisualPalette = .legacyLight,
        repositoryFactory: @escaping (MissCatProfileAccount) -> MissCatProfileRepository = { MissCatRESTProfileRepository(account: $0) },
        showsBack: Bool = true,
        onBack: @escaping () -> Void = {},
        onOpenURL: @escaping (URL) -> Void = { _ in },
        onOpenImage: @escaping (URL) -> Void = { _ in },
        onSelectUser: @escaping (String) -> Void = { _ in },
        onOpenUserList: ((MissCatUserListKind) -> Void)? = nil,
        onEditProfile: @escaping (MissCatProfileUser) -> Void = { _ in },
        onOpenSettings: @escaping () -> Void = {},
        onSelectRoot: @escaping (MissCatRootSection) -> Void = { _ in },
        onCompose: @escaping () -> Void = {},
        showsBottomBar: Bool = true
    ) {
        _store = State(initialValue: store)
        self.palette = palette
        self.repositoryFactory = repositoryFactory
        self.showsBack = showsBack
        self.onBack = onBack
        self.onOpenURL = onOpenURL
        self.onOpenImage = onOpenImage
        self.onSelectUser = onSelectUser
        self.onOpenUserList = onOpenUserList
        self.onEditProfile = onEditProfile
        self.onOpenSettings = onOpenSettings
        self.onSelectRoot = onSelectRoot
        self.onCompose = onCompose
        self.showsBottomBar = showsBottomBar
    }

    public var body: some View {
        profileContent
    }

    private var profileContent: some View {
        @Bindable var store = store
        return VStack(spacing: 0) {
            profileHeader
                .frame(height: MissCatProfileMetrics.headerHeight)

            MissCatProfileTabBar(selectedTab: $store.selectedTab, palette: palette) { tab in
                store.selectTab(tab)
            }

            TabView(selection: Binding(
                get: { store.selectedTab },
                set: { store.selectTab($0) }
            )) {
                ForEach(MissCatProfileTimelineTab.allCases) { tab in
                    MissCatProfileTimelinePage(store: store, tab: tab, palette: palette)
                        .tag(tab)
                        .accessibilityIdentifier("profile.timeline.\(tab.rawValue)")
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .accessibilityIdentifier("profile.timeline.pager")

            if showsBottomBar {
                MissCatBottomBar(
                    selectedSection: Binding(
                        get: { .profile },
                        set: { onSelectRoot($0) }
                    ),
                    palette: palette,
                    onCompose: onCompose,
                    onReselect: onSelectRoot
                )
            }
        }
        .background(palette.base.ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
        .tint(palette.accent)
        .task { store.load() }
        .sheet(item: $presentedList) { kind in
            userListDestination(kind)
        }
        .confirmationDialog("フォロー解除", isPresented: $confirmsUnfollow) {
            Button("Unfollow", role: .destructive) { store.setFollowing(false) }
            Button("いいえ", role: .cancel) {}
        } message: {
            Text("本当にフォロー解除しますか？")
        }
        .alert(
            "フォロー操作に失敗しました",
            isPresented: Binding(
                get: { store.followErrorMessage != nil },
                set: { if !$0 { store.dismissFollowError() } }
            )
        ) {
            Button("再試行") { store.retryFollowing() }
            Button("閉じる", role: .cancel) { store.dismissFollowError() }
        } message: {
            Text(store.followErrorMessage ?? "")
        }
        .overlay(alignment: .topLeading) {
            VStack(spacing: 0) {
                MissCatVisualReadyMarker(
                    ready: store.profilePhase == .loaded && store.timelines[store.selectedTab]?.phase.isTerminal == true,
                    identifier: "profile.visualReady"
                )
                MissCatVisualReadyMarker(
                    ready: true,
                    identifier: store.isCurrentUser ? "profile.self.screen" : "profile.other.screen"
                )
            }
        }
    }

    @ViewBuilder
    private var profileHeader: some View {
        switch store.profilePhase {
        case .idle, .loading:
            MissCatProfileHeaderPlaceholder(palette: palette)
                .accessibilityIdentifier("profile.loading")
        case let .failed(message):
            MissCatStateView(
                symbol: "exclamationmark.triangle",
                title: "プロフィールを読み込めませんでした",
                message: message,
                buttonTitle: "再試行",
                palette: palette,
                action: store.reloadProfile
            )
            .accessibilityIdentifier("profile.error")
        case .empty:
            MissCatStateView(symbol: "person.crop.circle.badge.questionmark", title: "ユーザーが見つかりません", palette: palette)
        case .loaded:
            if let profile = store.profile {
                MissCatProfileHeader(
                    profile: profile,
                    isCurrentUser: store.isCurrentUser,
                    isFollowing: store.isFollowing,
                    followPhase: store.followPhase,
                    palette: palette,
                    showsBack: showsBack,
                    onBack: onBack,
                    onSettings: onOpenSettings,
                    onOpenImage: onOpenImage,
                    onNotes: { store.selectTab(.notes) },
                    onFollowing: { openUserList(.following(userID: profile.id)) },
                    onFollowers: { openUserList(.followers(userID: profile.id)) },
                    onAction: {
                        if store.isCurrentUser {
                            onEditProfile(profile)
                        } else if store.isFollowing {
                            confirmsUnfollow = true
                        } else {
                            store.setFollowing(true)
                        }
                    }
                )
                .environment(\.openURL, OpenURLAction { url in
                    onOpenURL(url)
                    return .handled
                })
            }
        }
    }

    private func openUserList(_ kind: MissCatUserListKind) {
        if let onOpenUserList {
            onOpenUserList(kind)
        } else {
            presentedList = kind
        }
    }

    @ViewBuilder
    private func userListDestination(_ kind: MissCatUserListKind) -> some View {
        let listStore = MissCatUserListStore(
            account: store.account,
            kind: kind,
            repositoryFactory: repositoryFactory
        )
        NavigationStack {
            switch kind {
            case .followers:
                MissCatFollowersScreen(store: listStore, palette: palette, onSelectUser: onSelectUser)
            case .following:
                MissCatFollowingScreen(store: listStore, palette: palette, onSelectUser: onSelectUser)
            case .search:
                MissCatUserSearchScreen(store: listStore, palette: palette, onSelectUser: onSelectUser)
            }
        }
    }
}

enum MissCatProfileHeaderLayout {
    static let identityReservedWidth: CGFloat = 126

    static func identityMaxWidth(containerWidth: CGFloat) -> CGFloat {
        guard containerWidth.isFinite else { return 0 }
        return max(0, containerWidth - identityReservedWidth)
    }
}

public struct MissCatProfileHeader: View {
    public let profile: MissCatProfileUser
    public let isCurrentUser: Bool
    public let isFollowing: Bool
    public let followPhase: MissCatLoadPhase
    public let palette: MissCatVisualPalette
    public let showsBack: Bool
    public let onBack: () -> Void
    public let onSettings: () -> Void
    public let onOpenImage: (URL) -> Void
    public let onNotes: () -> Void
    public let onFollowing: () -> Void
    public let onFollowers: () -> Void
    public let onAction: () -> Void

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                palette.base

                Button {
                    if let url = profile.bannerURL { onOpenImage(url) }
                } label: {
                    banner(width: proxy.size.width)
                }
                .frame(width: proxy.size.width, height: MissCatProfileMetrics.bannerHeight)
                .contentShape(Rectangle())
                .buttonStyle(.plain)
                .disabled(profile.bannerURL == nil)
                .accessibilityLabel("バナー画像を表示")

                Button {
                    if let url = profile.avatarURL { onOpenImage(url) }
                } label: {
                    CircleImage(url: profile.avatarURL, diameter: MissCatProfileMetrics.avatarDiameter)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .disabled(profile.avatarURL == nil)
                .position(
                    x: MissCatProfileMetrics.avatarLeading + MissCatProfileMetrics.avatarDiameter / 2,
                    y: MissCatProfileMetrics.avatarTop + MissCatProfileMetrics.avatarDiameter / 2
                )
                .accessibilityLabel("\(profile.displayName)のアバターを表示")
                .accessibilityIdentifier("profile.avatar")

                if profile.isCat {
                    Image("Cat")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 66, height: 35)
                        .position(x: 59, y: 134)
                        .accessibilityLabel("猫")
                        .accessibilityIdentifier("profile.cat")
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(profile.acct)
                        .font(.system(size: 12))
                        .opacity(0.92)
                        .lineLimit(1)
                }
                .foregroundStyle(.white)
                .frame(
                    maxWidth: MissCatProfileHeaderLayout.identityMaxWidth(
                        containerWidth: proxy.size.width
                    ),
                    alignment: .leading
                )
                .position(x: (proxy.size.width + 106) / 2 - 10, y: 131)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("profile.identity")

                Text((profile.description?.isEmpty == false ? profile.description! : "自己紹介はありません").missCatLinkified)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.text)
                    .frame(maxWidth: .infinity, maxHeight: MissCatProfileMetrics.biographyHeight, alignment: .topLeading)
                    .padding(.top, 8)
                    .padding(.horizontal, 0)
                    .position(
                        x: proxy.size.width / 2,
                        y: MissCatProfileMetrics.biographyTop + MissCatProfileMetrics.biographyHeight / 2
                    )
                    .accessibilityIdentifier("profile.biography")

                HStack(spacing: 0) {
                    countButton(value: profile.notesCount, label: "投稿", identifier: "profile.count.notes", action: onNotes)
                    countButton(value: profile.followingCount, label: "フォロー", identifier: "profile.count.following", action: onFollowing)
                    countButton(value: profile.followersCount, label: "フォロワー", identifier: "profile.count.followers", action: onFollowers)
                }
                .frame(width: 226, height: 51)
                .position(x: 123, y: 400.5)

                Button(action: onAction) {
                    Group {
                        if followPhase == .loading {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(isCurrentUser ? "編集" : (isFollowing ? "フォロー解除" : "フォロー"))
                        }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 103, height: 25)
                    .foregroundStyle(isFollowing && !isCurrentUser ? palette.accent : (isCurrentUser ? palette.accent : .white))
                    .background(isFollowing || isCurrentUser ? Color.clear : palette.accent)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(palette.accent, lineWidth: 1))
                }
                .disabled(followPhase == .loading)
                .position(x: proxy.size.width - 72.5, y: 412.5)
                .buttonStyle(.plain)
                .zIndex(1)
                .accessibilityIdentifier(isCurrentUser ? "profile.action.edit" : "profile.action.follow")

                if showsBack {
                    circularToolbarButton(symbol: "chevron.left", label: "戻る", identifier: "profile.action.back", action: onBack)
                        .position(x: 35, y: 59)
                }
                circularToolbarButton(symbol: "gearshape.fill", label: "設定", identifier: "profile.action.settings", action: onSettings)
                    .position(x: proxy.size.width - 35, y: 59)
            }
        }
        .clipped()
        .overlay(alignment: .topLeading) {
            MissCatVisualReadyMarker(ready: true, identifier: "profile.header")
        }
    }

    private func banner(width: CGFloat) -> some View {
        Group {
#if DEBUG
            if profile.bannerURL?.scheme == "misscat-fixture" {
                Image("SprashBack").resizable().scaledToFill()
            } else {
                remoteBanner
            }
#else
            remoteBanner
#endif
        }
        .frame(width: width, height: MissCatProfileMetrics.bannerHeight)
        .clipped()
        .overlay(alignment: .bottom) {
            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                .frame(height: MissCatProfileMetrics.bannerHeight / 2)
        }
        .accessibilityIdentifier("profile.banner")
    }

    private var remoteBanner: some View {
        AsyncImage(url: profile.bannerURL) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                palette.muted
            }
        }
    }

    private func countButton(value: Int, label: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: -1) {
                Text(value.formatted())
                    .font(.system(size: 16, weight: .semibold))
                Text(label)
                    .font(.system(size: 12))
            }
            .foregroundStyle(palette.text)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) \(value)")
        .accessibilityIdentifier(identifier)
    }

    private func circularToolbarButton(symbol: String, label: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(.black.opacity(0.8), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}

public struct MissCatProfileTabBar: View {
    @Binding public var selectedTab: MissCatProfileTimelineTab
    public let palette: MissCatVisualPalette
    public let onSelect: (MissCatProfileTimelineTab) -> Void

    public var body: some View {
        HStack(spacing: 15) {
            ForEach(MissCatProfileTimelineTab.allCases) { tab in
                Button {
                    selectedTab = tab
                    onSelect(tab)
                } label: {
                    VStack(spacing: 0) {
                        Text(tab.title)
                            .font(.system(size: 15))
                            .foregroundStyle(palette.text)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        Rectangle()
                            .fill(selectedTab == tab ? palette.accent : .clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                .accessibilityIdentifier("profile.tab.\(tab.rawValue)")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: MissCatProfileMetrics.tabHeight)
        .background(palette.base)
        .overlay(alignment: .bottom) { Rectangle().fill(palette.border).frame(height: 0.5) }
        .overlay(alignment: .topLeading) {
            MissCatVisualReadyMarker(ready: true, identifier: "profile.tabs")
        }
    }
}

public struct MissCatProfileTimelinePage: View {
    public let store: MissCatProfileStore
    public let tab: MissCatProfileTimelineTab
    public let palette: MissCatVisualPalette

    public var body: some View {
        let state = store.timelines[tab, default: .init()]
        Group {
            switch state.phase {
            case .idle where state.notes.isEmpty, .loading where state.notes.isEmpty:
                ProgressView().accessibilityLabel("読み込み中")
            case .empty:
                MissCatStateView(
                    symbol: tab == .media ? "photo.on.rectangle.angled" : "text.bubble",
                    title: tab == .media ? "メディア付きの投稿はありません" : "投稿はありません",
                    palette: palette
                )
            case let .failed(message) where state.notes.isEmpty:
                MissCatStateView(
                    symbol: "arrow.clockwise",
                    title: "投稿を読み込めませんでした",
                    message: message,
                    buttonTitle: "再試行",
                    palette: palette,
                    action: { store.retryTimeline(tab) }
                )
            default:
                timeline(state)
            }
        }
        .background(palette.base)
    }

    private func timeline(_ state: MissCatProfileStore.TimelineState) -> some View {
        let scrollBinding = Binding<String?>(
            get: { store.timelines[tab]?.topVisibleNoteID },
            set: { store.setTopVisibleNoteID($0, for: tab) }
        )
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(state.notes) { note in
                    MissCatProfileNoteRow(note: note, palette: palette)
                        .id(note.id)
                        .onAppear { store.loadMoreIfNeeded(tab: tab, currentNoteID: note.id) }
                }

                if state.phase == .loading {
                    ProgressView().padding(16)
                } else if case let .failed(message) = state.phase {
                    MissCatInlineRetry(message: message, palette: palette) { store.retryTimeline(tab) }
                }
            }
            .scrollTargetLayout()
        }
        .scrollPosition(id: scrollBinding, anchor: .top)
        .refreshable { store.loadTimeline(tab, reload: true) }
        .accessibilityIdentifier("profile.timeline.scroll.\(tab.rawValue)")
    }
}

public struct MissCatProfileNoteRow: View {
    public let note: MissCatProfileNote
    public let palette: MissCatVisualPalette
    @State private var showsCWContent = false

    public var body: some View {
        HStack(alignment: .top, spacing: 10) {
            CircleImage(url: note.user.avatarURL, diameter: 42)

            VStack(alignment: .leading, spacing: 7) {
                if let renotedBy = note.renotedBy {
                    Label("\(renotedBy.displayName)がRenote", systemImage: "arrow.2.squarepath")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.strong)
                        .accessibilityIdentifier("profile.note.\(note.id).renoted-by")
                }

                HStack(spacing: 5) {
                    Text(note.user.displayName).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text(note.user.acct).font(.system(size: 11)).foregroundStyle(palette.strong).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(note.createdAt.legacyRelativeDateLabel).font(.system(size: 10)).foregroundStyle(palette.strong)
                }

                if let cw = note.cw, !cw.isEmpty {
                    Button {
                        showsCWContent.toggle()
                    } label: {
                        HStack {
                            Text(cw).font(.system(size: 13, weight: .semibold))
                            Spacer()
                            Text(showsCWContent ? "隠す" : "もっと見る")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(palette.accent)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("profile.note.\(note.id).cw")
                }
                if note.cw == nil || showsCWContent,
                   let text = note.text,
                   !text.isEmpty {
                    Text(text.missCatLinkified).font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
                }
                if (note.cw == nil || showsCWContent), !note.files.isEmpty {
                    MissCatProfileMediaGrid(files: note.files)
                }

                if !note.reactions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 5) {
                            ForEach(note.reactions.keys.sorted(), id: \.self) { reaction in
                                Text("\(reaction) \(note.reactions[reaction] ?? 0)")
                                    .font(.system(size: 12))
                                    .padding(.horizontal, 8)
                                    .frame(height: 30)
                                    .background(palette.muted.opacity(0.8), in: RoundedRectangle(cornerRadius: 5))
                            }
                        }
                    }
                    .accessibilityIdentifier("profile.note.\(note.id).reactions")
                }

                HStack {
                    metric("bubble.left", value: note.repliesCount)
                    metric("arrow.2.squarepath", value: note.renoteCount)
                    metric("plus.circle", value: note.reactionCount)
                }
                .foregroundStyle(palette.strong)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .foregroundStyle(palette.text)
        .background(palette.base)
        .overlay(alignment: .bottom) { Rectangle().fill(palette.border.opacity(0.7)).frame(height: 0.5) }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("profile.note.\(note.id)")
    }

    private func metric(_ symbol: String, value: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            if value > 0 { Text(value.formatted()) }
        }
        .font(.system(size: 11))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

public struct MissCatProfileMediaGrid: View {
    public let files: [MissCatProfileNoteFile]

    public var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)], spacing: 2) {
            ForEach(files.prefix(4)) { file in
                AsyncImage(url: file.thumbnailURL ?? file.url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Color.gray.opacity(0.22).overlay { ProgressView().controlSize(.small) }
                    }
                }
                .frame(minHeight: files.count == 1 ? 180 : 100)
                .clipped()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .accessibilityIdentifier("profile.note.media")
    }
}

// MARK: - Followers, following, generic lists, and search

public struct MissCatFollowersScreen: View {
    @State private var store: MissCatUserListStore
    private let palette: MissCatVisualPalette
    private let onSelectUser: (String) -> Void

    public init(store: MissCatUserListStore, palette: MissCatVisualPalette = .legacyLight, onSelectUser: @escaping (String) -> Void = { _ in }) {
        _store = State(initialValue: store)
        self.palette = palette
        self.onSelectUser = onSelectUser
    }

    public var body: some View {
        MissCatUserListScreen(store: store, palette: palette, onSelectUser: onSelectUser)
            .navigationTitle("Followers")
            .overlay(alignment: .topLeading) {
                MissCatVisualReadyMarker(ready: true, identifier: "profile.followers.screen")
            }
    }
}

public struct MissCatFollowingScreen: View {
    @State private var store: MissCatUserListStore
    private let palette: MissCatVisualPalette
    private let onSelectUser: (String) -> Void

    public init(store: MissCatUserListStore, palette: MissCatVisualPalette = .legacyLight, onSelectUser: @escaping (String) -> Void = { _ in }) {
        _store = State(initialValue: store)
        self.palette = palette
        self.onSelectUser = onSelectUser
    }

    public var body: some View {
        MissCatUserListScreen(store: store, palette: palette, onSelectUser: onSelectUser)
            .navigationTitle("Following")
            .overlay(alignment: .topLeading) {
                MissCatVisualReadyMarker(ready: true, identifier: "profile.following.screen")
            }
    }
}

public struct MissCatUserListScreen: View {
    public let store: MissCatUserListStore
    public let palette: MissCatVisualPalette
    public let onSelectUser: (String) -> Void

    public init(store: MissCatUserListStore, palette: MissCatVisualPalette = .legacyLight, onSelectUser: @escaping (String) -> Void = { _ in }) {
        self.store = store
        self.palette = palette
        self.onSelectUser = onSelectUser
    }

    public var body: some View {
        Group {
            switch store.phase {
            case .idle where store.users.isEmpty, .loading where store.users.isEmpty:
                ProgressView().accessibilityLabel("ユーザーを読み込み中")
            case .empty:
                MissCatStateView(symbol: "person.2.slash", title: "ユーザーはいません", palette: palette)
            case let .failed(message) where store.users.isEmpty:
                MissCatStateView(
                    symbol: "arrow.clockwise",
                    title: "ユーザーを読み込めませんでした",
                    message: message,
                    buttonTitle: "再試行",
                    palette: palette,
                    action: store.retry
                )
            default:
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.users) { user in
                            Button { onSelectUser(user.id) } label: {
                                MissCatUserRow(user: user, palette: palette)
                            }
                            .buttonStyle(.plain)
                            .onAppear { store.loadMoreIfNeeded(currentUserID: user.id) }
                        }
                        if store.phase == .loading { ProgressView().padding(16) }
                    }
                }
                .refreshable { store.load(reload: true) }
            }
        }
        .background(palette.base)
        .task { store.load() }
        .overlay(alignment: .topLeading) {
            VStack(spacing: 0) {
                MissCatVisualReadyMarker(ready: store.phase.isTerminal, identifier: "profile.userList.visualReady")
                MissCatVisualReadyMarker(ready: true, identifier: "profile.userList.screen")
            }
        }
    }
}

public struct MissCatUserSearchScreen: View {
    @State private var store: MissCatUserListStore
    private let palette: MissCatVisualPalette
    private let onSelectUser: (String) -> Void

    public init(store: MissCatUserListStore, palette: MissCatVisualPalette = .legacyLight, onSelectUser: @escaping (String) -> Void = { _ in }) {
        _store = State(initialValue: store)
        self.palette = palette
        self.onSelectUser = onSelectUser
    }

    public var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(palette.strong)
                TextField("ユーザーを検索", text: $store.query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit(store.submitSearch)
                    .accessibilityIdentifier("profile.search.query")
                if !store.query.isEmpty {
                    Button { store.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .accessibilityLabel("検索語を消去")
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .padding(10)

            if store.query.isEmpty && store.users.isEmpty {
                MissCatStateView(symbol: "person.crop.circle.badge.magnifyingglass", title: "ユーザー名を入力してください", palette: palette)
            } else {
                MissCatUserListScreen(store: store, palette: palette, onSelectUser: onSelectUser)
            }
        }
        .navigationTitle("ユーザー検索")
        .background(palette.base)
        .overlay(alignment: .topLeading) {
            MissCatVisualReadyMarker(ready: true, identifier: "profile.search.screen")
        }
    }
}

public struct MissCatUserRow: View {
    public let user: MissCatProfileUser
    public let palette: MissCatVisualPalette

    public var body: some View {
        HStack(alignment: .top, spacing: 10) {
            CircleImage(url: user.avatarURL, diameter: 50)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(user.displayName).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    if user.isCat { Image(systemName: "cat.fill").font(.system(size: 11)).foregroundStyle(palette.accent) }
                }
                Text(user.acct).font(.system(size: 12)).foregroundStyle(palette.strong).lineLimit(1)
                Text(user.description?.isEmpty == false ? user.description! : "自己紹介文はありません")
                    .font(.system(size: 12))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(palette.text)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.base)
        .overlay(alignment: .bottom) { Rectangle().fill(palette.border.opacity(0.7)).frame(height: 0.5) }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("profile.user.\(user.id)")
    }
}

// MARK: - Profile editing

public struct MissCatProfileEditorScreen: View {
    @State private var store: MissCatProfileEditorStore
    @State private var avatarItem: PhotosPickerItem?
    @State private var bannerItem: PhotosPickerItem?
    @State private var cameraTarget: CameraTarget?
    @Environment(\.dismiss) private var dismiss

    private let palette: MissCatVisualPalette
    private let onCancel: (() -> Void)?
    private let onSaved: (MissCatProfileUser) -> Void

    public init(
        store: MissCatProfileEditorStore,
        palette: MissCatVisualPalette = .legacyLight,
        onCancel: (() -> Void)? = nil,
        onSaved: @escaping (MissCatProfileUser) -> Void = { _ in }
    ) {
        _store = State(initialValue: store)
        self.palette = palette
        self.onCancel = onCancel
        self.onSaved = onSaved
    }

    public var body: some View {
        @Bindable var store = store
        Form {
            Section {
                bannerEditor
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(palette.base)
            }

            Section("プロフィール") {
                TextField("名前", text: $store.name)
                    .accessibilityIdentifier("profile.edit.name")
                TextField("自己紹介", text: $store.biography, axis: .vertical)
                    .lineLimit(4 ... 10)
                    .accessibilityIdentifier("profile.edit.biography")
                Toggle("猫です", isOn: $store.isCat)
                    .accessibilityIdentifier("profile.edit.isCat")
            }

            if store.phase == .loading {
                Section("アップロード") {
                    ProgressView(value: store.uploadProgress)
                        .accessibilityValue("\(Int(store.uploadProgress * 100))パーセント")
                        .accessibilityIdentifier("profile.edit.uploadProgress")
                    Button("キャンセル", action: store.cancelSave)
                        .accessibilityIdentifier("profile.edit.cancelUpload")
                }
            }

            if case let .failed(message) = store.phase {
                Section {
                    Text(message).foregroundStyle(.red)
                    Button("再試行", action: store.retry)
                        .accessibilityIdentifier("profile.edit.retry")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(palette.surface)
        .navigationTitle("プロフィール編集")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("閉じる") {
                    store.discardPendingChanges()
                    if let onCancel {
                        onCancel()
                    } else {
                        dismiss()
                    }
                }
                .accessibilityIdentifier("profile.edit.close")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: store.save)
                    .disabled(store.phase == .loading)
                    .accessibilityIdentifier("profile.edit.save")
            }
        }
        .onChange(of: avatarItem) { _, item in load(item, target: .avatar) }
        .onChange(of: bannerItem) { _, item in load(item, target: .banner) }
        .onChange(of: store.savedProfile) { _, profile in
            if let profile { onSaved(profile) }
        }
        .onDisappear {
            if store.phase == .loading { store.cancelSave() }
        }
        .sheet(item: $cameraTarget) { target in
            MissCatCameraCaptureView(configuration: .profile) { capture in
                apply(capture.data, target: target)
                cameraTarget = nil
            } onCancel: {
                cameraTarget = nil
            }
            .ignoresSafeArea()
        }
        .overlay(alignment: .topLeading) {
            VStack(spacing: 0) {
                MissCatVisualReadyMarker(ready: store.phase != .loading, identifier: "profile.edit.visualReady")
                MissCatVisualReadyMarker(ready: true, identifier: "profile.edit.screen")
            }
        }
    }

    private var bannerEditor: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let data = store.bannerData,
                   let image = MissCatCameraImageProcessor.decode(data)
                {
                    Image(decorative: image, scale: 1, orientation: .up)
                        .resizable()
                        .scaledToFill()
                } else if let url = store.existingBannerURL {
#if DEBUG
                    if url.scheme == "misscat-fixture" {
                        Image("SprashBack").resizable().scaledToFill()
                    } else {
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            palette.muted
                        }
                    }
#else
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        palette.muted
                    }
#endif
                } else {
                    palette.muted
                }
            }
            .frame(height: 154)
            .frame(maxWidth: .infinity)
            .clipped()

            HStack(alignment: .bottom) {
                Group {
                    if let data = store.avatarData,
                       let image = MissCatCameraImageProcessor.decode(data)
                    {
                        Image(decorative: image, scale: 1, orientation: .up)
                            .resizable()
                            .scaledToFill()
                    } else if let url = store.existingAvatarURL {
#if DEBUG
                        if url.scheme == "misscat-fixture" {
                            Image("MissCat").resizable().scaledToFill()
                        } else {
                            AsyncImage(url: url) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Image(systemName: "person.crop.circle.fill")
                                    .resizable()
                                    .foregroundStyle(.white, palette.strong)
                            }
                        }
#else
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Image(systemName: "person.crop.circle.fill")
                                .resizable()
                                .foregroundStyle(.white, palette.strong)
                        }
#endif
                    } else {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .foregroundStyle(.white, palette.strong)
                    }
                }
                .frame(width: 78, height: 78)
                .clipShape(Circle())
                .overlay(Circle().stroke(.white, lineWidth: 2))

                Spacer()
                imageMenu(title: "バナー", pickerItem: $bannerItem, target: .banner)
                imageMenu(title: "アイコン", pickerItem: $avatarItem, target: .avatar)
            }
            .padding(16)
        }
        .overlay(alignment: .topLeading) {
            MissCatValueMarker(
                identifier: "profile.edit.images",
                value: "avatar=\(imageState(.avatar));banner=\(imageState(.banner))"
            )
        }
    }

    private func imageMenu(title: String, pickerItem: Binding<PhotosPickerItem?>, target: CameraTarget) -> some View {
        Menu {
            PhotosPicker(selection: pickerItem, matching: .images) {
                Label("写真を選択", systemImage: "photo")
            }
            if MissCatCameraAccessPolicy.hasVideoDevice {
                Button { cameraTarget = target } label: { Label("カメラ", systemImage: "camera") }
            }
            if hasImage(target) {
                Button(role: .destructive) {
                    removeImage(target)
                } label: {
                    Label("画像を削除", systemImage: "trash")
                }
                .accessibilityIdentifier("profile.edit.\(target.rawValue).remove")
            }
            if hasImageChange(target) {
                Button {
                    resetImage(target)
                } label: {
                    Label("変更を元に戻す", systemImage: "arrow.uturn.backward")
                }
                .accessibilityIdentifier("profile.edit.\(target.rawValue).reset")
            }
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(.black.opacity(0.65), in: Capsule())
        }
        .disabled(store.phase == .loading)
        .accessibilityIdentifier("profile.edit.\(target.rawValue)")
    }

    private func hasImage(_ target: CameraTarget) -> Bool {
        switch target {
        case .avatar: return store.hasAvatar
        case .banner: return store.hasBanner
        }
    }

    private func hasImageChange(_ target: CameraTarget) -> Bool {
        switch target {
        case .avatar: return store.hasAvatarChange
        case .banner: return store.hasBannerChange
        }
    }

    private func imageState(_ target: CameraTarget) -> String {
        switch target {
        case .avatar:
            if store.avatarRemoved { return "removed" }
            if store.avatarData != nil { return "replacement" }
            return store.existingAvatarURL == nil ? "empty" : "existing"
        case .banner:
            if store.bannerRemoved { return "removed" }
            if store.bannerData != nil { return "replacement" }
            return store.existingBannerURL == nil ? "empty" : "existing"
        }
    }

    private func removeImage(_ target: CameraTarget) {
        switch target {
        case .avatar: store.removeAvatar()
        case .banner: store.removeBanner()
        }
    }

    private func resetImage(_ target: CameraTarget) {
        switch target {
        case .avatar: store.resetAvatar()
        case .banner: store.resetBanner()
        }
    }

    private func load(_ item: PhotosPickerItem?, target: CameraTarget) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                await MainActor.run { apply(data, target: target) }
            }
        }
    }

    private func apply(_ data: Data?, target: CameraTarget) {
        let processed = data.flatMap {
            MissCatCameraImageProcessor.profileJPEG(
                from: $0,
                target: target == .avatar ? .avatar : .banner
            )
        } ?? data
        switch target {
        case .avatar: store.setAvatarData(processed)
        case .banner: store.setBannerData(processed)
        }
    }

    private enum CameraTarget: String, Identifiable {
        case avatar, banner
        var id: String { rawValue }
    }
}

// MARK: - Reusable visual states

private enum MissCatProfileMetrics {
    static let headerHeight = MissCatLegacyMetrics.profileHeaderHeight
    static let bannerHeight = MissCatLegacyMetrics.profileBannerHeight
    static let avatarDiameter = MissCatLegacyMetrics.profileAvatarDiameter
    static let avatarLeading = MissCatLegacyMetrics.profileAvatarLeading
    static let avatarTop = MissCatLegacyMetrics.profileAvatarTop
    static let biographyTop = MissCatLegacyMetrics.profileBiographyTop
    static let biographyHeight = MissCatLegacyMetrics.profileBiographyHeight
    static let tabHeight = MissCatLegacyMetrics.profileTabsHeight
}

private struct CircleImage: View {
    let url: URL?
    let diameter: CGFloat

    var body: some View {
        Group {
#if DEBUG
            if url?.scheme == "misscat-fixture" {
                Image("MissCat").resizable().scaledToFill()
            } else {
                remoteImage
            }
#else
            remoteImage
#endif
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
    }

    private var remoteImage: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.white, Color.gray)
            }
        }
    }
}

private struct MissCatProfileHeaderPlaceholder: View {
    let palette: MissCatVisualPalette

    var body: some View {
        ZStack(alignment: .topLeading) {
            palette.base
            palette.muted.frame(height: MissCatProfileMetrics.bannerHeight)
            Circle().fill(palette.surface).frame(width: 78, height: 78).offset(x: 20, y: 95)
            VStack(alignment: .leading, spacing: 12) {
                RoundedRectangle(cornerRadius: 4).fill(palette.surface).frame(height: 14)
                RoundedRectangle(cornerRadius: 4).fill(palette.surface).frame(width: 230, height: 12)
                RoundedRectangle(cornerRadius: 4).fill(palette.surface).frame(height: 12)
            }
            .padding(.horizontal, 20)
            .offset(y: 190)
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct MissCatStateView: View {
    let symbol: String
    let title: String
    var message: String? = nil
    var buttonTitle: String? = nil
    let palette: MissCatVisualPalette
    var action: () -> Void = {}

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 30)).foregroundStyle(palette.strong)
            Text(title).font(.system(size: 15, weight: .semibold)).multilineTextAlignment(.center)
            if let message { Text(message).font(.system(size: 12)).foregroundStyle(palette.strong).multilineTextAlignment(.center) }
            if let buttonTitle { Button(buttonTitle, action: action).buttonStyle(.bordered) }
        }
        .foregroundStyle(palette.text)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MissCatInlineRetry: View {
    let message: String
    let palette: MissCatVisualPalette
    let action: () -> Void

    var body: some View {
        VStack(spacing: 5) {
            Text(message).font(.system(size: 11)).foregroundStyle(palette.strong)
            Button("再試行", action: action).font(.system(size: 12, weight: .semibold))
        }
        .padding(12)
    }
}

private struct MissCatVisualReadyMarker: View {
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

private struct MissCatValueMarker: View {
    let identifier: String
    let value: String

    var body: some View {
        Text("state")
            .font(.system(size: 1))
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .accessibilityLabel(identifier)
            .accessibilityValue(value)
            .accessibilityIdentifier(identifier)
    }
}

private extension MissCatLoadPhase {
    var isTerminal: Bool {
        switch self {
        case .loaded, .empty, .failed: return true
        case .idle, .loading: return false
        }
    }
}

private extension String {
    var missCatLinkified: AttributedString {
        let result = NSMutableAttributedString(string: self)
        let fullRange = NSRange(location: 0, length: (self as NSString).length)
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            detector.enumerateMatches(in: self, range: fullRange) { match, _, _ in
                guard let match, let url = match.url else { return }
                result.addAttribute(.link, value: url, range: match.range)
            }
        }
        let expression = try? NSRegularExpression(pattern: "(?<![\\w])([@#][\\p{L}\\p{N}_@.\\-]+)")
        expression?.enumerateMatches(in: self, range: fullRange) { match, _, _ in
            guard let range = match?.range(at: 1), range.location != NSNotFound else { return }
            let value = (self as NSString).substring(with: range)
            let kind = value.hasPrefix("@") ? "user" : "hashtag"
            let payload = String(value.dropFirst()).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
            if let url = URL(string: "misscat://\(kind)/\(payload)") {
                result.addAttribute(.link, value: url, range: range)
            }
        }
        return AttributedString(result)
    }

    var legacyRelativeDateLabel: String {
        guard let date = MissCatProfileAPIDateParser.date(from: self) else { return self }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

extension MissCatUserListKind: Identifiable {
    public var id: String {
        switch self {
        case let .followers(userID): return "followers-\(userID)"
        case let .following(userID): return "following-\(userID)"
        case let .search(query): return "search-\(query)"
        }
    }
}
