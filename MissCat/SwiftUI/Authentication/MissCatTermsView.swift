import SwiftUI

public struct MissCatTermsView: View {
    public let text: String
    public let onAgree: () -> Void

    public init(
        text: String = MissCatTermsContent.japanese,
        onAgree: @escaping () -> Void
    ) {
        self.text = text
        self.onAgree = onAgree
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 8)
                    .textSelection(.enabled)
            }
            .accessibilityIdentifier("terms.text")

            HStack {
                Spacer()
                Button("同意する", action: onAgree)
                    .font(.system(size: 17))
                    .frame(height: 30)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityIdentifier("terms.agree")
            }
            .padding(.top, 15)
            .padding(.trailing, 20)
        }
        .navigationTitle("利用規約")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(uiColor: .systemBackground))
        .accessibilityIdentifier("terms.screen")
    }
}
