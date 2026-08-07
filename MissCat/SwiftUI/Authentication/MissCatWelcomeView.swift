import SwiftUI

struct MissCatWelcomeFrameGeometry {
    let contentSize: CGSize
    let safeTop: CGFloat
    let safeBottom: CGFloat

    init(proposedSize: CGSize, proposedSafeTop: CGFloat, proposedSafeBottom: CGFloat) {
        contentSize = CGSize(
            width: Self.validFrameDimension(proposedSize.width),
            height: Self.validFrameDimension(proposedSize.height)
        )
        safeTop = Self.validFrameDimension(proposedSafeTop)
        safeBottom = Self.validFrameDimension(proposedSafeBottom)
    }

    var canvasHeight: CGFloat {
        Self.validFrameDimension(contentSize.height + safeTop + safeBottom)
    }

    var logoWidth: CGFloat {
        Self.validFrameDimension(
            contentSize.width - (MissCatLegacyMetrics.welcomeLogoHorizontalInset * 2)
        )
    }

    var buttonWidth: CGFloat {
        Self.validFrameDimension(
            MissCatLegacyMetrics.welcomeButtonWidth(canvasWidth: contentSize.width)
        )
    }

    var buttonHeight: CGFloat {
        Self.validFrameDimension(
            MissCatLegacyMetrics.welcomeButtonHeight(canvasHeight: canvasHeight)
        )
    }

    private static func validFrameDimension(_ proposed: CGFloat) -> CGFloat {
        guard proposed.isFinite else { return 0 }
        return max(0, proposed)
    }
}

public struct MissCatWelcomeView: View {
    public let instance: String
    public let onSignUp: () -> Void
    public let onLogIn: () -> Void
    public let onChangeInstance: () -> Void

    @State private var controlsAreVisible = false

    public init(
        instance: String = "misskey.io",
        onSignUp: @escaping () -> Void,
        onLogIn: @escaping () -> Void,
        onChangeInstance: @escaping () -> Void
    ) {
        self.instance = instance
        self.onSignUp = onSignUp
        self.onLogIn = onLogIn
        self.onChangeInstance = onChangeInstance
    }

    public var body: some View {
        GeometryReader { proxy in
            let frameGeometry = MissCatWelcomeFrameGeometry(
                proposedSize: proxy.size,
                proposedSafeTop: proxy.safeAreaInsets.top,
                proposedSafeBottom: proxy.safeAreaInsets.bottom
            )
            let size = frameGeometry.contentSize
            let safeTop = frameGeometry.safeTop
            let safeBottom = frameGeometry.safeBottom
            let layout = MissCatWelcomeLayout(
                contentSize: size,
                safeTop: safeTop,
                safeBottom: safeBottom
            )
            let buttonHeight = frameGeometry.buttonHeight
            let buttonWidth = frameGeometry.buttonWidth
            let buttonGap = max(
                0,
                size.width
                    - (MissCatLegacyMetrics.welcomeHorizontalInset * 2)
                    - (buttonWidth * 2)
            )
            let changeButtonHeight = MissCatLegacyMetrics.welcomeChangeInstanceHeight

            ZStack(alignment: .topLeading) {
                LinearGradient(
                    stops: [
                        .init(color: Color(hex: MissCatLegacyColorHex.welcomeGradientBottomLeading), location: 0),
                        .init(color: Color(hex: MissCatLegacyColorHex.welcomeGradientMiddle), location: 0.5),
                        .init(color: Color(hex: MissCatLegacyColorHex.welcomeGradientTopTrailing), location: 1)
                    ],
                    startPoint: layout.gradientStartPoint,
                    endPoint: layout.gradientEndPoint
                )
                .frame(width: size.width, height: layout.canvasHeight)
                .offset(y: layout.backgroundOffsetY)
                .ignoresSafeArea()

                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(
                        width: frameGeometry.logoWidth,
                        height: MissCatLegacyMetrics.welcomeLogoHeight
                    )
                    .position(
                        x: size.width / 2,
                        y: layout.logoCenterY + safeTop
                    )
                    .accessibilityHidden(true)

                Text("新しい世界を探検しよう")
                    .font(MissCatTypography.welcomeTagline)
                    .foregroundStyle(.white)
                    .fixedSize()
                    .position(
                        x: size.width / 2,
                        y: layout.taglineCenterY + safeTop
                    )
                    .modifier(WelcomeControlEntrance(isVisible: controlsAreVisible))
                    .accessibilityIdentifier("welcome.tagline")

                HStack(spacing: buttonGap) {
                    welcomeButton(title: "新規登録", identifier: "welcome.signup", action: onSignUp)
                        .frame(width: buttonWidth)
                    welcomeButton(title: "ログイン", identifier: "welcome.login", action: onLogIn)
                        .frame(width: buttonWidth)
                }
                .padding(.horizontal, MissCatLegacyMetrics.welcomeHorizontalInset)
                .frame(width: size.width, height: buttonHeight)
                .position(x: size.width / 2, y: layout.buttonsTopY + safeTop + buttonHeight / 2)
                .modifier(WelcomeControlEntrance(isVisible: controlsAreVisible))

                Button(action: onChangeInstance) {
                    Text("> インスタンスを変更する")
                        .font(.system(size: MissCatLegacyMetrics.welcomeChangeInstanceFontSize))
                        .foregroundStyle(Color.white.opacity(0.925))
                        .frame(height: changeButtonHeight)
                }
                .buttonStyle(.plain)
                .fixedSize(horizontal: true, vertical: false)
                .position(x: size.width / 2, y: layout.changeInstanceCenterY + safeTop)
                .modifier(WelcomeControlEntrance(isVisible: controlsAreVisible))
                .accessibilityIdentifier("welcome.change-instance")

                Text(instance)
                    .font(MissCatTypography.welcomeInstance)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, MissCatLegacyMetrics.welcomeHorizontalInset)
                    .frame(width: size.width, height: MissCatLegacyMetrics.welcomeInstanceHeight)
                    .position(
                        x: size.width / 2,
                        y: layout.instanceCenterY + safeTop
                    )
                    .modifier(WelcomeControlEntrance(isVisible: controlsAreVisible))
                    .accessibilityLabel("現在のインスタンス、\(instance)")
                    .accessibilityIdentifier("welcome.instance")
            }
            .frame(width: size.width, height: size.height)
        }
        .onAppear {
            controlsAreVisible = false
            withAnimation(.easeInOut(duration: 0.7)) {
                controlsAreVisible = true
            }
        }
        .overlay(alignment: .topLeading) {
            MissCatAuthenticationMarker(identifier: "welcome.screen")
        }
        .preferredColorScheme(.light)
    }

    private func welcomeButton(
        title: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(MissCatTypography.welcomeButton)
                .foregroundStyle(Color(hex: "2BA3BC"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: MissCatLegacyMetrics.welcomeButtonCornerRadius))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

private struct WelcomeControlEntrance: ViewModifier {
    let isVisible: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : -30)
    }
}
