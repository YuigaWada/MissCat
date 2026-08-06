import SwiftUI

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
            let size = proxy.size
            let safeTop = proxy.safeAreaInsets.top
            let safeBottom = proxy.safeAreaInsets.bottom
            let layout = MissCatWelcomeLayout(
                contentSize: size,
                safeTop: safeTop,
                safeBottom: safeBottom
            )
            let buttonHeight = layout.buttonHeight
            let buttonWidth = MissCatLegacyMetrics.welcomeButtonWidth(canvasWidth: size.width)
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
                    startPoint: .bottomLeading,
                    endPoint: .topTrailing
                )
                .frame(width: size.width, height: layout.canvasHeight)
                .offset(y: layout.backgroundOffsetY)
                .ignoresSafeArea()

                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(
                        width: size.width - (MissCatLegacyMetrics.welcomeLogoHorizontalInset * 2),
                        height: MissCatLegacyMetrics.welcomeLogoHeight
                    )
                    .position(
                        x: size.width / 2,
                        y: layout.logoCenterY
                    )
                    .accessibilityHidden(true)

                Text("新しい世界を探検しよう")
                    .font(MissCatTypography.welcomeTagline)
                    .foregroundStyle(.white)
                    .fixedSize()
                    .position(
                        x: size.width / 2,
                        y: layout.taglineCenterY
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
                .position(x: size.width / 2, y: layout.buttonsTopY + buttonHeight / 2)
                .modifier(WelcomeControlEntrance(isVisible: controlsAreVisible))

                Button(action: onChangeInstance) {
                    Text("> インスタンスを変更する")
                        .font(.system(size: MissCatLegacyMetrics.welcomeChangeInstanceFontSize))
                        .foregroundStyle(Color.white.opacity(0.925))
                        .frame(height: changeButtonHeight)
                }
                .buttonStyle(.plain)
                .fixedSize(horizontal: true, vertical: false)
                .position(x: size.width / 2, y: layout.changeInstanceCenterY)
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
                        y: layout.instanceCenterY
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
        .accessibilityIdentifier("welcome.screen")
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
