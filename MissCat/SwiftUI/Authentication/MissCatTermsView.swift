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
                    .font(MissCatTypography.termsText)
                    .foregroundStyle(Color.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, MissCatLegacyMetrics.termsTextHorizontalInset)
                    .padding(.vertical, MissCatLegacyMetrics.termsTextVerticalInset)
                    .textSelection(.enabled)
            }
            .accessibilityIdentifier("terms.text")

            HStack {
                Spacer()
                Button("同意する", action: onAgree)
                    .font(MissCatTypography.termsAgreement)
                    .frame(height: MissCatLegacyMetrics.termsAgreementHeight)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityIdentifier("terms.agree")
            }
            .padding(.top, MissCatLegacyMetrics.termsAgreementTopGap)
            .padding(.trailing, MissCatLegacyMetrics.termsAgreementTrailingInset)
        }
        .navigationTitle("利用規約")
        .navigationBarTitleDisplayMode(.inline)
        .missCatLegacyOnboardingNavigationBar()
        .background(Color(uiColor: .systemBackground))
        .overlay(alignment: .topLeading) {
            MissCatAuthenticationMarker(identifier: "terms.screen")
        }
    }
}
