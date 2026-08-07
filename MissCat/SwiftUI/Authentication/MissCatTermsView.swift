import SwiftUI

enum MissCatTermsVisibleEdge: Hashable {
    case top
    case bottom
}

enum MissCatTermsScrollReadiness {
    static func visibleEdges(
        contentMinY: CGFloat,
        contentMaxY: CGFloat,
        viewportHeight: CGFloat,
        tolerance: CGFloat = 1
    ) -> Set<MissCatTermsVisibleEdge> {
        guard contentMinY.isFinite,
              contentMaxY.isFinite,
              viewportHeight.isFinite,
              viewportHeight > 0,
              contentMaxY >= contentMinY
        else { return [] }

        var result: Set<MissCatTermsVisibleEdge> = []
        if contentMinY >= -tolerance, contentMinY <= viewportHeight + tolerance {
            result.insert(.top)
        }
        if contentMaxY >= -tolerance, contentMaxY <= viewportHeight + tolerance {
            result.insert(.bottom)
        }
        return result
    }
}

private struct MissCatTermsContentFramePreferenceKey: PreferenceKey {
    static let defaultValue = CGRect.null

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

public struct MissCatTermsView: View {
    public let text: String
    public let onAgree: () -> Void

    @State private var visibleEdges: Set<MissCatTermsVisibleEdge> = []

    public init(
        text: String = MissCatTermsContent.japanese,
        onAgree: @escaping () -> Void
    ) {
        self.text = text
        self.onAgree = onAgree
    }

    public var body: some View {
        VStack(spacing: 0) {
            GeometryReader { viewport in
                ScrollView {
                    Text(text)
                        .font(MissCatTypography.termsText)
                        .foregroundStyle(Color.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, MissCatLegacyMetrics.termsTextHorizontalInset)
                        .padding(.vertical, MissCatLegacyMetrics.termsTextVerticalInset)
                        .textSelection(.enabled)
                        .background {
                            GeometryReader { content in
                                Color.clear.preference(
                                    key: MissCatTermsContentFramePreferenceKey.self,
                                    value: content.frame(in: .named("terms-scroll-viewport"))
                                )
                            }
                        }
                }
                .coordinateSpace(name: "terms-scroll-viewport")
                .onPreferenceChange(MissCatTermsContentFramePreferenceKey.self) { frame in
                    visibleEdges = MissCatTermsScrollReadiness.visibleEdges(
                        contentMinY: frame.minY,
                        contentMaxY: frame.maxY,
                        viewportHeight: viewport.size.height
                    )
                }
                .overlay(alignment: .topLeading) {
                    VStack(spacing: 0) {
                        if visibleEdges.contains(.top) {
                            MissCatAuthenticationMarker(
                                identifier: "visual-ready.login-terms.top"
                            )
                        }
                        if visibleEdges.contains(.bottom) {
                            MissCatAuthenticationMarker(
                                identifier: "visual-ready.login-terms.bottom"
                            )
                        }
                    }
                }
                .accessibilityIdentifier("terms.text")
            }

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
