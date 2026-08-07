import CoreGraphics
import SwiftUI

private extension ColorScheme {
    var missCatComposePalette: MissCatVisualPalette {
        self == .dark ? .legacyDark : .legacyLight
    }
}

struct MissCatComposeTargetPreview: View {
    let mode: MissCatComposeMode
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let target = mode.target {
            HStack(spacing: 8) {
                Image(systemName: modeIcon)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 24)

                AsyncImage(url: target.avatarURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Circle().fill(colorScheme.missCatComposePalette.surface)
                        .overlay(Image(systemName: "person.fill").font(.caption))
                }
                .frame(width: 32, height: 32)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(target.mention)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(target.text.isEmpty ? "（本文なし）" : target.text)
                        .font(.system(size: 12))
                        .foregroundStyle(colorScheme.missCatComposePalette.strong)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("compose.target")
        }
    }

    private var modeIcon: String {
        switch mode {
        case .reply: "chevron.right"
        case .quote, .renote: "repeat"
        case .note: "square.and.pencil"
        }
    }
}

struct MissCatComposeAccountPicker: View {
    let accounts: [MissCatComposeAccount]
    let selectedAccountID: String?
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(accounts) { account in
                Button {
                    onSelect(account.id)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        AsyncImage(url: account.avatarURL) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Circle().fill(.quaternary)
                                .overlay(Image(systemName: "person.fill"))
                        }
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())

                        Text(account.displayName)
                        Spacer()
                        if selectedAccountID == account.id {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                }
                .foregroundStyle(.primary)
                .accessibilityIdentifier("compose.account.\(account.id)")
            }
            .navigationTitle("アカウント")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                        .accessibilityIdentifier("compose.account.close")
                }
            }
        }
        .accessibilityIdentifier("compose.account.screen")
    }
}

struct MissCatVisibilitySelectorView: View {
    @Binding var visibility: MissCatComposeVisibility
    @Binding var visibleUserIDs: [String]
    @State private var recipient = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                visibilityOptions
                directRecipients
            }
            .navigationTitle("公開範囲")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                        .accessibilityIdentifier("compose.visibility.done")
                }
            }
        }
        .accessibilityIdentifier("compose.visibility.screen")
    }

    private var visibilityOptions: some View {
        Section("公開範囲") {
            ForEach(MissCatComposeVisibility.allCases) { option in
                visibilityButton(option)
            }
        }
    }

    @ViewBuilder
    private var directRecipients: some View {
        if visibility == .specified {
            Section {
                HStack {
                    TextField("ユーザーID", text: $recipient)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("compose.visibility.recipient")
                    Button("追加") { addRecipient() }
                        .disabled(recipient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("compose.visibility.add-recipient")
                }

                ForEach(visibleUserIDs, id: \.self) { id in
                    recipientRow(id)
                }
            } header: {
                Text("宛先ユーザーID")
            } footer: {
                Text("ダイレクト投稿には少なくとも1人の宛先が必要です")
            }
        }
    }

    private func visibilityButton(_ option: MissCatComposeVisibility) -> some View {
        Button {
            visibility = option
            if option != .specified { visibleUserIDs = [] }
        } label: {
            HStack {
                Image(systemName: option.systemImage).frame(width: 24)
                Text(option.label)
                Spacer()
                if visibility == option {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
        }
        .foregroundStyle(.primary)
        .accessibilityIdentifier("compose.visibility.\(option.rawValue)")
    }

    private func recipientRow(_ id: String) -> some View {
        HStack {
            Text(id).textSelection(.enabled)
            Spacer()
            Button(role: .destructive) {
                visibleUserIDs.removeAll { $0 == id }
            } label: {
                Image(systemName: "trash")
            }
            .accessibilityLabel("\(id)を削除")
        }
    }

    private func addRecipient() {
        let value = recipient.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !visibleUserIDs.contains(value) else { return }
        visibleUserIDs.append(value)
        recipient = ""
    }
}

struct MissCatContentWarningEditorView: View {
    @Binding var isEnabled: Bool
    @Binding var text: String
    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Toggle("投稿に注釈をつける", isOn: $isEnabled)
                    .accessibilityIdentifier("compose.cw.enabled")
                if isEnabled {
                    Section("注釈") {
                        TextEditor(text: $text)
                            .frame(minHeight: 110)
                            .focused($isFocused)
                            .accessibilityLabel("投稿の注釈")
                            .accessibilityIdentifier("compose.cw.text")
                        Text("\(text.count) / \(MissCatComposeSubmissionBuilder.maximumContentWarningLength)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(
                                text.count > MissCatComposeSubmissionBuilder.maximumContentWarningLength
                                    ? .red : .secondary
                            )
                    }
                }
            }
            .navigationTitle("内容を隠す")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                        .accessibilityIdentifier("compose.cw.done")
                }
            }
            .onAppear { isFocused = isEnabled }
        }
        .accessibilityIdentifier("compose.cw.screen")
    }
}

struct MissCatPollEditorView: View {
    @Binding var poll: MissCatPollDraft
    @State private var expirySelection = ExpirySelection.never
    @State private var customDate = Date().addingTimeInterval(3_600)
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("選択肢") {
                    ForEach($poll.choices) { $choice in
                        HStack {
                            TextField("選択肢", text: $choice.text)
                                .accessibilityIdentifier("compose.poll.choice.\(choice.id.uuidString)")
                            if poll.choices.count > 2 {
                                Button(role: .destructive) {
                                    poll.choices.removeAll { $0.id == choice.id }
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .accessibilityLabel("選択肢を削除")
                            }
                        }
                    }
                    Button("追加") {
                        guard poll.choices.count < 10 else { return }
                        poll.choices.append(MissCatPollChoice())
                    }
                    .disabled(poll.choices.count >= 10)
                    .accessibilityIdentifier("compose.poll.add-choice")
                }

                Section {
                    Toggle("複数回答を許可", isOn: $poll.allowsMultiple)
                        .accessibilityIdentifier("compose.poll.multiple")
                }

                Section("終了日時") {
                    Picker("期間", selection: $expirySelection) {
                        ForEach(ExpirySelection.allCases) { value in
                            Text(value.label).tag(value)
                        }
                    }
                    .accessibilityIdentifier("compose.poll.expiry")

                    if expirySelection == .custom {
                        DatePicker(
                            "終了",
                            selection: $customDate,
                            in: Date().addingTimeInterval(60)...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .accessibilityIdentifier("compose.poll.custom-expiry")
                    }
                }
            }
            .navigationTitle("アンケート")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
                        updateExpiry()
                        dismiss()
                    }
                    .accessibilityIdentifier("compose.poll.done")
                }
            }
            .onAppear { loadExpiry() }
            .onChange(of: expirySelection) { _, _ in updateExpiry() }
            .onChange(of: customDate) { _, _ in updateExpiry() }
        }
        .accessibilityIdentifier("compose.poll.screen")
    }

    private func loadExpiry() {
        switch poll.expiry {
        case .never:
            expirySelection = .never
        case let .duration(value):
            expirySelection = ExpirySelection(rawValue: Int(value)) ?? .custom
        case let .at(value):
            expirySelection = .custom
            customDate = value
        }
    }

    private func updateExpiry() {
        poll.expiry = expirySelection == .custom
            ? .at(customDate)
            : expirySelection.expiry
    }

    private enum ExpirySelection: Int, CaseIterable, Identifiable {
        case never = 0
        case fiveMinutes = 300
        case thirtyMinutes = 1_800
        case oneHour = 3_600
        case sixHours = 21_600
        case oneDay = 86_400
        case custom = -1

        var id: Int { rawValue }
        var label: String {
            switch self {
            case .never: "なし"
            case .fiveMinutes: "5分"
            case .thirtyMinutes: "30分"
            case .oneHour: "1時間"
            case .sixHours: "6時間"
            case .oneDay: "1日"
            case .custom: "日時を指定"
            }
        }
        var expiry: MissCatPollExpiry {
            self == .never ? .never : .duration(TimeInterval(rawValue))
        }
    }
}

struct MissCatTokenInsertionView: View {
    let onMention: (String, String?) -> Void
    let onHashtag: (String) -> Void
    @State private var username = ""
    @State private var instance = ""
    @State private var hashtag = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("メンション") {
                    TextField("ユーザー名", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("compose.token.username")
                    TextField("インスタンス（省略可）", text: $instance)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("compose.token.instance")
                    Button("メンションを追加") {
                        onMention(username, instance.isEmpty ? nil : instance)
                        dismiss()
                    }
                    .disabled(username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("compose.token.add-mention")
                }

                Section("ハッシュタグ") {
                    TextField("タグ", text: $hashtag)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("compose.token.hashtag")
                    Button("ハッシュタグを追加") {
                        onHashtag(hashtag)
                        dismiss()
                    }
                    .disabled(hashtag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("compose.token.add-hashtag")
                }
            }
            .navigationTitle("文字を挿入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("compose.token.screen")
    }
}

struct MissCatMediaPreviewStrip: View {
    @Binding var media: [MissCatComposeMedia]
    let onEdit: (MissCatComposeMedia) -> Void
    @State private var metadataID: UUID?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(media) { item in
                    ZStack(alignment: .topTrailing) {
                        Button { onEdit(item) } label: {
                            preview(for: item)
                                .frame(width: 118, height: 118)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                                .overlay(alignment: .bottomLeading) {
                                    if item.isSensitive {
                                        Text("NSFW")
                                            .font(.caption2.bold())
                                            .padding(5)
                                            .foregroundStyle(.white)
                                            .background(.black.opacity(0.72), in: Capsule())
                                            .padding(5)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("添付を編集")
                        .accessibilityIdentifier("compose.media.edit.\(item.id.uuidString)")

                        Button(role: .destructive) {
                            media.removeAll { $0.id == item.id }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption.bold())
                                .frame(width: 28, height: 28)
                                .foregroundStyle(.white)
                                .background(.black.opacity(0.72), in: Circle())
                        }
                        .offset(x: 4, y: -4)
                        .accessibilityLabel("添付を削除")

                        Button {
                            metadataID = item.id
                        } label: {
                            Image(systemName: "text.bubble")
                                .font(.caption.bold())
                                .frame(width: 28, height: 28)
                                .foregroundStyle(.white)
                                .background(.black.opacity(0.72), in: Circle())
                        }
                        .offset(x: 4, y: 84)
                        .accessibilityLabel("代替テキストと閲覧注意を設定")
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 1)
        }
        .frame(height: 128)
        .sheet(item: metadataBinding) { item in
            MissCatMediaMetadataEditor(media: binding(for: item.id))
        }
        .accessibilityIdentifier("compose.media.strip")
    }

    @ViewBuilder
    private func preview(for item: MissCatComposeMedia) -> some View {
        if let image = MissCatComposeImageCodec.decode(item.previewData) {
            Image(decorative: image, scale: 1).resizable().scaledToFill()
                .overlay {
                    if item.kind == .video {
                        Image(systemName: "play.circle.fill")
                            .font(.largeTitle).foregroundStyle(.white)
                    }
                }
        } else {
            Rectangle().fill(.quaternary)
                .overlay(Image(systemName: item.kind == .video ? "video" : "photo"))
        }
    }

    private var metadataBinding: Binding<MissCatComposeMedia?> {
        Binding(
            get: { metadataID.flatMap { id in media.first { $0.id == id } } },
            set: { metadataID = $0?.id }
        )
    }

    private func binding(for id: UUID) -> Binding<MissCatComposeMedia> {
        Binding(
            get: { media.first { $0.id == id } ?? media[0] },
            set: { updated in
                guard let index = media.firstIndex(where: { $0.id == id }) else { return }
                media[index] = updated
            }
        )
    }
}

struct MissCatMediaMetadataEditor: View {
    @Binding var media: MissCatComposeMedia
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Toggle("画像を閲覧注意にする", isOn: $media.isSensitive)
                    .accessibilityIdentifier("compose.media.sensitive")
                Section("代替テキスト") {
                    TextEditor(text: $media.altText)
                        .frame(minHeight: 120)
                        .accessibilityIdentifier("compose.media.alt-text")
                    Text("\(media.altText.count) / \(MissCatComposeSubmissionBuilder.maximumAltTextLength)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(
                            media.altText.count > MissCatComposeSubmissionBuilder.maximumAltTextLength
                                ? .red : .secondary
                        )
                }
            }
            .navigationTitle("添付ファイル")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                        .disabled(media.altText.count > MissCatComposeSubmissionBuilder.maximumAltTextLength)
                }
            }
        }
        .accessibilityIdentifier("compose.media.metadata")
    }
}
