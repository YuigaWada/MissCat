import SwiftUI

public struct MissCatMessageNavigationActions {
    public var openConversation: (MissCatPerson) -> Void
    public var openRoute: (MissCatMessageRoute) -> Void

    public init(
        openConversation: @escaping (MissCatPerson) -> Void = { _ in },
        openRoute: @escaping (MissCatMessageRoute) -> Void = { _ in }
    ) {
        self.openConversation = openConversation
        self.openRoute = openRoute
    }
}

public struct MissCatMessageHistoryView: View {
    @StateObject private var store: MissCatMessageHistoryStore

    private let palette: MissCatVisualPalette
    private let navigationActions: MissCatMessageNavigationActions

    public init(
        repository: MissCatMessagingRepository,
        palette: MissCatVisualPalette = .legacyLight,
        navigationActions: MissCatMessageNavigationActions = .init()
    ) {
        _store = StateObject(wrappedValue: MissCatMessageHistoryStore(repository: repository))
        self.palette = palette
        self.navigationActions = navigationActions
    }

    public var body: some View {
        ZStack {
            palette.base.ignoresSafeArea()
            content
        }
        .task { await store.load() }
        .accessibilityIdentifier("messages.history.screen")
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .idle, .loading:
            VStack(spacing: 10) {
                ProgressView().tint(palette.accent)
                Text("メッセージを読み込み中…")
                    .font(.system(size: 14))
                    .foregroundStyle(palette.strong)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("messages.history.loading")
        case .empty:
            ContentUnavailableView {
                Label("メッセージはありません", systemImage: "message")
            } description: {
                Text("会話を始めるとここに表示されます")
            }
            .foregroundStyle(palette.strong)
            .accessibilityIdentifier("messages.history.empty")
        case let .failed(message):
            ContentUnavailableView {
                Label("メッセージを読み込めませんでした", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("再試行") { Task { await store.retry() } }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.accent)
                    .accessibilityIdentifier("messages.history.retry")
            }
            .foregroundStyle(palette.strong)
            .accessibilityIdentifier("messages.history.failure")
        case .loaded:
            List(store.conversations) { conversation in
                Button {
                    navigationActions.openConversation(conversation.peer)
                } label: {
                    MissCatConversationRow(conversation: conversation, palette: palette)
                }
                .buttonStyle(.plain)
                .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowSeparator(.hidden)
                .listRowBackground(palette.base)
                .accessibilityIdentifier("messages.history.row.\(conversation.peer.id)")
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(palette.base)
            .refreshable { await store.refresh() }
            .accessibilityIdentifier("messages.history.list")
        }
    }
}

public struct MissCatConversationRow: View {
    public let conversation: MissCatConversation
    public let palette: MissCatVisualPalette

    public init(conversation: MissCatConversation, palette: MissCatVisualPalette = .legacyLight) {
        self.conversation = conversation
        self.palette = palette
    }

    public var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: conversation.peer.avatarURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(palette.muted)
            }
            .frame(width: 48, height: 48)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(conversation.peer.displayName)
                        .font(.system(size: 15, weight: conversation.isRead ? .regular : .semibold))
                        .foregroundStyle(palette.text)
                        .lineLimit(1)
                    Spacer()
                    Text(conversation.latestDate, style: .relative)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.strong)
                }
                Text(conversation.latestText.isEmpty ? "添付ファイル" : conversation.latestText)
                    .font(.system(size: 13))
                    .foregroundStyle(palette.strong)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.base)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(palette.border)
                .frame(height: MissCatLegacyMetrics.hairlineWidth)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

public struct MissCatConversationView: View {
    @StateObject private var store: MissCatConversationStore
    @FocusState private var composerFocused: Bool

    private let palette: MissCatVisualPalette
    private let navigationActions: MissCatMessageNavigationActions

    public init(
        peer: MissCatPerson,
        repository: MissCatMessagingRepository,
        palette: MissCatVisualPalette = .legacyLight,
        navigationActions: MissCatMessageNavigationActions = .init()
    ) {
        _store = StateObject(
            wrappedValue: MissCatConversationStore(peer: peer, repository: repository)
        )
        self.palette = palette
        self.navigationActions = navigationActions
    }

    public var body: some View {
        ZStack {
            palette.base.ignoresSafeArea()
            content
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            composer
        }
        .navigationTitle(store.peer.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.loadInitial() }
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
        .accessibilityIdentifier("messages.conversation.screen")
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .idle, .loading:
            ProgressView()
                .tint(palette.accent)
                .accessibilityLabel("会話を読み込み中")
                .accessibilityIdentifier("messages.conversation.loading")
        case let .failed(message):
            ContentUnavailableView {
                Label("会話を読み込めませんでした", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("再試行") { Task { await store.retryLoad() } }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.accent)
                    .accessibilityIdentifier("messages.conversation.retry")
            }
            .foregroundStyle(palette.strong)
            .accessibilityIdentifier("messages.conversation.failure")
        case .empty, .loaded:
            transcript
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 5) {
                    if store.canLoadOlder {
                        Button {
                            Task { await store.loadOlder() }
                        } label: {
                            if store.isLoadingOlder {
                                ProgressView().tint(palette.accent)
                            } else {
                                Label("以前のメッセージを読み込む", systemImage: "arrow.up")
                            }
                        }
                        .font(.system(size: 13))
                        .foregroundStyle(palette.accent)
                        .frame(height: 44)
                        .disabled(store.isLoadingOlder)
                        .accessibilityIdentifier("messages.conversation.load-older")
                    }

                    if store.messages.isEmpty {
                        Text("メッセージを送って会話を始めましょう")
                            .font(.system(size: 14))
                            .foregroundStyle(palette.strong)
                            .padding(.top, 24)
                            .accessibilityIdentifier("messages.conversation.empty")
                    }

                    ForEach(Array(store.messages.enumerated()), id: \.element.id) { index, message in
                        if store.showsDateSeparator(at: index) {
                            Text(message.createdAt.formatted(date: .abbreviated, time: .omitted))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(palette.strong)
                                .padding(.vertical, 8)
                                .accessibilityIdentifier("message.date.\(message.id)")
                        }

                        MissCatMessageBubble(
                            message: message,
                            ownerAccountID: store.accountScope.accountID,
                            palette: palette,
                            onRoute: navigationActions.openRoute
                        )
                        .id(message.id)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .onChange(of: store.messages.count) {
                if let last = store.messages.last?.id {
                    withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
            .accessibilityIdentifier("messages.conversation.transcript")
        }
    }

    private var composer: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(palette.border)
                .frame(height: MissCatLegacyMetrics.hairlineWidth)

            if case let .failed(_, _, message) = store.sendState {
                HStack(spacing: 8) {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                    Spacer()
                    Button("再試行", action: store.retrySend)
                        .font(.system(size: 12, weight: .semibold))
                        .accessibilityIdentifier("messages.send.retry")
                }
                .padding(.horizontal, 12)
                .padding(.top, 7)
                .accessibilityIdentifier("messages.send.error")
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField("メッセージ", text: $store.draft, axis: .vertical)
                    .lineLimit(1 ... 5)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .focused($composerFocused)
                    .accessibilityIdentifier("messages.composer.text")

                switch store.sendState {
                case .sending:
                    Button(action: store.cancelSend) {
                        ZStack {
                            ProgressView().tint(.white)
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 36, height: 36)
                        .background(palette.accent, in: Circle())
                    }
                    .accessibilityLabel("送信をキャンセル")
                    .accessibilityIdentifier("messages.send.cancel")
                case .idle, .failed:
                    Button(action: store.sendDraft) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(palette.accent, in: Circle())
                    }
                    .disabled(store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
                    .accessibilityLabel("送信")
                    .accessibilityIdentifier("messages.send.button")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(.regularMaterial)
        .accessibilityIdentifier("messages.composer")
    }
}

public struct MissCatMessageBubble: View {
    public let message: MissCatDirectMessage
    public let ownerAccountID: String
    public let palette: MissCatVisualPalette
    public let onRoute: (MissCatMessageRoute) -> Void

    public init(
        message: MissCatDirectMessage,
        ownerAccountID: String,
        palette: MissCatVisualPalette = .legacyLight,
        onRoute: @escaping (MissCatMessageRoute) -> Void = { _ in }
    ) {
        self.message = message
        self.ownerAccountID = ownerAccountID
        self.palette = palette
        self.onRoute = onRoute
    }

    public var body: some View {
        let mine = message.isMine(ownerAccountID: ownerAccountID)
        HStack(alignment: .bottom, spacing: 5) {
            if mine { Spacer(minLength: 48) }

            if mine {
                VStack(alignment: .trailing, spacing: 2) {
                    if message.isRead {
                        Text("既読")
                            .font(.system(size: 9))
                            .foregroundStyle(palette.strong)
                    }
                    Text(message.createdAt, style: .time)
                        .font(.system(size: 9))
                        .foregroundStyle(palette.strong)
                }
            }

            Text(MissCatMessageLinkParser.attributedString(message.text))
                .font(.system(size: 15))
                .foregroundStyle(mine ? Color.white : palette.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    mine ? palette.accent : palette.surface,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .environment(\.openURL, OpenURLAction { url in
                    guard let route = MissCatMessageLinkParser.route(for: url) else { return .systemAction }
                    onRoute(route)
                    return .handled
                })

            if !mine {
                Text(message.createdAt, style: .time)
                    .font(.system(size: 9))
                    .foregroundStyle(palette.strong)
                Spacer(minLength: 48)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(mine ? "自分" : "相手")のメッセージ、\(message.text)")
        .accessibilityIdentifier("message.bubble.\(message.id)")
    }
}
