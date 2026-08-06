import SwiftUI

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

/// Native replacement for the legacy SearchViewController and
/// TrendViewController pair. Tap and horizontal swipe both drive the same tab
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
                    .simultaneousGesture(resultSwipeGesture)
                userResults
                    .frame(width: proxy.size.width)
                    .simultaneousGesture(resultSwipeGesture)
            }
            .frame(width: proxy.size.width * 2, alignment: .leading)
            .offset(x: store.selectedTab == .notes ? 0 : -proxy.size.width)
            .animation(.easeInOut(duration: 0.2), value: store.selectedTab)
            .contentShape(Rectangle())
        }
        .clipped()
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
                        MissCatNoteRow(
                            note: note,
                            palette: palette,
                            onOpenUser: navigationActions.openUser,
                            onOpenNote: navigationActions.openNote,
                            onOpenAttachment: navigationActions.openAttachment,
                            onOpenHashtag: navigationActions.openHashtag
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
                            MissCatUserRow(user: user, palette: palette)
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
