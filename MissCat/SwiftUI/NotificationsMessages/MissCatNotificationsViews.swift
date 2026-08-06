import SwiftUI

public struct MissCatNotificationNavigationActions {
    public var open: (MissCatNotificationRoute) -> Void

    public init(open: @escaping (MissCatNotificationRoute) -> Void = { _ in }) {
        self.open = open
    }
}

public struct MissCatNotificationsView: View {
    @StateObject private var store: MissCatNotificationsStore

    private let palette: MissCatVisualPalette
    private let navigationActions: MissCatNotificationNavigationActions

    public init(
        repository: MissCatNotificationsRepository,
        palette: MissCatVisualPalette = .legacyLight,
        navigationActions: MissCatNotificationNavigationActions = .init()
    ) {
        _store = StateObject(wrappedValue: MissCatNotificationsStore(repository: repository))
        self.palette = palette
        self.navigationActions = navigationActions
    }

    public var body: some View {
        ZStack(alignment: .top) {
            palette.base.ignoresSafeArea()
            content

            if let banner = store.banner {
                MissCatInAppNotificationBannerView(
                    banner: banner,
                    palette: palette,
                    onTap: {
                        if let route = store.takeBannerRoute() {
                            navigationActions.open(route)
                        }
                    },
                    onDismiss: store.dismissBanner
                )
                .padding(.horizontal, 10)
                .padding(.top, 6)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(2)
            }
        }
        .animation(.snappy, value: store.banner?.id)
        .task { await store.loadInitial() }
        .onDisappear { store.stopRealtime() }
        .alert(
            "エラー",
            isPresented: Binding(
                get: { store.actionErrorMessage != nil },
                set: { if !$0 { store.dismissActionError() } }
            )
        ) {
            Button("閉じる") { store.dismissActionError() }
        } message: {
            Text(store.actionErrorMessage ?? "")
        }
        .accessibilityIdentifier("notifications.screen")
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .idle, .loading:
            loading
        case .empty:
            ContentUnavailableView {
                Label("通知はありません", systemImage: "bell")
            } description: {
                Text("新しい通知が届くとここに表示されます")
            }
            .foregroundStyle(palette.strong)
            .accessibilityIdentifier("notifications.empty")
        case let .failed(message):
            ContentUnavailableView {
                Label("通知を読み込めませんでした", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("再試行") { Task { await store.retry() } }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.accent)
                    .accessibilityIdentifier("notifications.retry")
            }
            .foregroundStyle(palette.strong)
            .accessibilityIdentifier("notifications.failure")
        case .loaded:
            list
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(store.notifications) { notification in
                    Button {
                        navigationActions.open(notification.preferredRoute)
                    } label: {
                        MissCatNotificationRow(notification: notification, palette: palette)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("notification.row.\(notification.id)")
                    .task {
                        await store.loadNextPageIfNeeded(currentID: notification.id)
                    }
                }

                if store.isLoadingMore {
                    ProgressView()
                        .tint(palette.accent)
                        .frame(height: 48)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("notifications.pagination.loading")
                }
            }
        }
        .refreshable { await store.refresh() }
        .scrollIndicators(.hidden)
        .background(palette.base)
        .accessibilityIdentifier("notifications.list")
    }

    private var loading: some View {
        VStack(spacing: 10) {
            ProgressView().tint(palette.accent)
            Text("通知を読み込み中…")
                .font(.system(size: 14))
                .foregroundStyle(palette.strong)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("notifications.loading")
    }
}

public struct MissCatNotificationRow: View {
    public let notification: MissCatNotification
    public let palette: MissCatVisualPalette

    public init(notification: MissCatNotification, palette: MissCatVisualPalette = .legacyLight) {
        self.notification = notification
        self.palette = palette
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: notification.actor.avatarURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(palette.muted)
            }
            .frame(width: 42, height: 42)
            .clipShape(Circle())
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: notification.kind.symbolName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(kindColor)
                        .accessibilityHidden(true)
                    Text(notification.actor.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.text)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(notification.createdAt, style: .relative)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.strong)
                }

                Text(actionText)
                    .font(.system(size: 13))
                    .foregroundStyle(palette.strong)

                if let note = notification.noteText?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !note.isEmpty {
                    Text(note)
                        .font(.system(size: 14))
                        .foregroundStyle(palette.text)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.base)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(palette.border)
                .frame(height: MissCatLegacyMetrics.hairlineWidth)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(notification.actor.displayName)が\(notification.kind.localizedAction)")
    }

    private var actionText: String {
        if notification.kind == .reaction, let reaction = notification.reaction {
            return "\(reaction) でリアクションしました"
        }
        return notification.kind.localizedAction
    }

    private var kindColor: Color {
        switch notification.kind {
        case .reaction: .orange
        case .renote, .quote: .green
        case .follow: palette.accent
        case .reply, .mention: .cyan
        }
    }
}

public struct MissCatInAppNotificationBannerView: View {
    public let banner: MissCatInAppNotificationBanner
    public let palette: MissCatVisualPalette
    public let onTap: () -> Void
    public let onDismiss: () -> Void

    public init(
        banner: MissCatInAppNotificationBanner,
        palette: MissCatVisualPalette = .legacyLight,
        onTap: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.banner = banner
        self.palette = palette
        self.onTap = onTap
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(spacing: 8) {
            Button(action: onTap) {
                MissCatNotificationRow(notification: banner.notification, palette: palette)
                    .background(palette.surface)
            }
            .buttonStyle(.plain)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(palette.strong)
                    .frame(width: 30, height: 30)
            }
            .accessibilityLabel("通知を閉じる")
            .accessibilityIdentifier("notification.banner.dismiss")
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        .accessibilityIdentifier("notification.banner")
    }
}
