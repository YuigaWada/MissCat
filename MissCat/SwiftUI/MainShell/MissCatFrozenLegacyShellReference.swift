#if DEBUG
import SwiftUI

/// Frozen, self-contained rendering contract used only to construct migration
/// reference images. This source intentionally has no dependency on the
/// candidate shell, pager, feed, row, or visual-token implementations.
enum MissCatFrozenLegacyShellReferenceLaunch {
    enum State {
        case populated
        case empty
        case loading
        case error
        case offline
    }

    static let argument = "--frozen-legacy-shell-reference"
    static var isRequested: Bool { CommandLine.arguments.contains(argument) }

    static var state: State {
        if CommandLine.arguments.contains("--frozen-legacy-shell-reference-empty") { return .empty }
        if CommandLine.arguments.contains("--frozen-legacy-shell-reference-loading") { return .loading }
        if CommandLine.arguments.contains("--frozen-legacy-shell-reference-error") { return .error }
        if CommandLine.arguments.contains("--frozen-legacy-shell-reference-offline") { return .offline }
        return .populated
    }
}

struct MissCatFrozenLegacyShellReferenceView: View {
    private let state = MissCatFrozenLegacyShellReferenceLaunch.state
    private let accent = Color(red: 47 / 255, green: 124 / 255, blue: 246 / 255)
    private let strong = Color(red: 85 / 255, green: 85 / 255, blue: 85 / 255)
    private let border = Color(red: 198 / 255, green: 198 / 255, blue: 198 / 255)

    var body: some View {
        VStack(spacing: 0) {
            frozenHeader

            frozenContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white)

            frozenFooter
        }
        .background(Color.white.ignoresSafeArea())
        .tint(accent)
        .overlay(alignment: .bottomTrailing) {
            Text("reference-ready")
                .font(.system(size: 1))
                .opacity(0.01)
                .frame(width: 1, height: 1)
                .accessibilityIdentifier("frozen.legacy.shell.visual-ready")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("frozen.legacy.shell.reference")
    }

    private var frozenHeader: some View {
        GeometryReader { proxy in
            let searchWidth: CGFloat = 44
            let tabWidth = max(110, (proxy.size.width - searchWidth) / 3)

            HStack(spacing: 0) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Color.black)
                    .frame(width: searchWidth, height: 43)

                ForEach(Array(["Home", "Local", "Global"].enumerated()), id: \.offset) { index, title in
                    VStack(spacing: 0) {
                        Text(title)
                            .font(.system(size: 17))
                            .foregroundStyle(Color.black)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        Rectangle()
                            .fill(index == 0 ? accent : Color.clear)
                            .frame(height: 2)
                            .padding(.horizontal, 4)
                    }
                    .frame(width: tabWidth, height: 43)
                }
            }
        }
        .frame(height: 43)
        .background(Color.white)
        .overlay(alignment: .bottom) {
            Rectangle().fill(border).frame(height: 0.5)
        }
    }

    @ViewBuilder
    private var frozenContent: some View {
        switch state {
        case .populated, .offline:
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(0 ..< 30, id: \.self) { index in
                        frozenNoteRow(index)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .overlay(alignment: .top) {
                if state == .offline {
                    frozenOfflineBanner
                        .padding(.horizontal, 10)
                        .padding(.top, 8)
                }
            }
        case .empty:
            ScrollView {
                ContentUnavailableView {
                    Label("ノートがありません", systemImage: "text.bubble")
                } description: {
                    Text("下に引っ張ると更新できます")
                }
                .foregroundStyle(strong)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 360)
                .accessibilityIdentifier("feed.empty")
            }
            .scrollIndicators(.hidden)
        case .loading:
            VStack(spacing: 12) {
                ProgressView().tint(accent)
                Text("読み込み中…")
                    .font(.system(size: 14))
                    .foregroundStyle(strong)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("feed.loading")
        case .error:
            ContentUnavailableView {
                Label("読み込めませんでした", systemImage: "exclamationmark.triangle")
            } description: {
                Text("Fixture network error")
            } actions: {
                Button("再試行") {}
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
            }
            .foregroundStyle(strong)
            .accessibilityIdentifier("feed.failure")
        }
    }

    private func frozenNoteRow(_ index: Int) -> some View {
        let names = ["Miss Cat", "Yuigawada", "Neko"]
        let usernames = ["misscat", "developer", "neko"]

        return HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color(red: 211 / 255, green: 211 / 255, blue: 211 / 255))
                .overlay {
                    Image(systemName: "person.fill")
                        .foregroundStyle(Color.white)
                }
                .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(names[index % 3])
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.black)
                        .lineLimit(1)

                    if index % 2 == 0 {
                        Image(systemName: "cat.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(accent)
                    }

                    Text("@\(usernames[index % 3])")
                        .font(.system(size: 11))
                        .foregroundStyle(strong)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Text("\(10 + index * 3)m ago")
                        .font(.system(size: 13))
                        .foregroundStyle(strong)
                        .lineLimit(1)
                }
                .frame(height: 27)

                Text(index == 0 ? "SwiftUI native timeline fixture 🐈" : "Deterministic note \(index + 1)")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.black)
                    .fixedSize(horizontal: false, vertical: true)

                if index == 0 {
                    HStack(spacing: 4) {
                        Text("👍")
                        Text("3")
                    }
                    .font(.system(size: 13))
                    .padding(.horizontal, 7)
                    .frame(minHeight: 28)
                    .foregroundStyle(Color.black)
                    .background(Color(red: 240 / 255, green: 240 / 255, blue: 240 / 255))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                frozenActionBar(index)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 20)
        .padding(.trailing, 20)
        .padding(.top, 13)
        .padding(.bottom, 1)
        .background(Color.white)
        .overlay(alignment: .bottom) {
            Rectangle().fill(border).frame(height: 0.5)
        }
    }

    private func frozenActionBar(_ index: Int) -> some View {
        HStack(spacing: 0) {
            frozenAction("arrowshape.turn.up.left", count: index % 2)
            frozenAction("arrow.2.squarepath", count: index % 3)
            frozenAction("face.smiling", count: 0)
            frozenAction("ellipsis", count: 0)
        }
        .frame(height: 40)
        .foregroundStyle(strong)
    }

    private func frozenAction(_ symbol: String, count: Int) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
            if count > 0 {
                Text("\(count)").font(.system(size: 12))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var frozenFooter: some View {
        HStack(spacing: 10) {
            frozenFooterItem("house.fill", color: accent)
            frozenFooterItem("bell.fill", color: Color(white: 0.67))

            Circle()
                .fill(accent)
                .frame(width: 48, height: 48)
                .overlay {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 23, weight: .regular))
                        .foregroundStyle(Color.white)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            frozenFooterItem("star.fill", color: Color(white: 0.67))
            frozenFooterItem("person.fill", color: Color(white: 0.67))
        }
        .frame(height: 55)
        .background(Color.white)
        .overlay(alignment: .top) {
            Rectangle().fill(border).frame(height: 0.5)
        }
    }

    private func frozenFooterItem(_ symbol: String, color: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 21, weight: .semibold))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var frozenOfflineBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.white)
            Text("Fixture offline")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 30, height: 30)
        }
        .padding(.leading, 12)
        .padding(.trailing, 5)
        .padding(.vertical, 6)
        .background(strong.opacity(0.96), in: RoundedRectangle(cornerRadius: 8))
        .shadow(color: Color.black.opacity(0.18), radius: 4, y: 2)
        .accessibilityIdentifier("feed.banner.error")
    }
}
#endif
