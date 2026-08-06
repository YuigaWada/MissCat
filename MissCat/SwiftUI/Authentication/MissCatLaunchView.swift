import SwiftUI

/// SwiftUI equivalent of `LaunchScreen.storyboard` for transitions and screenshot tests.
/// The static launch storyboard must remain for the OS-owned launch phase.
public struct MissCatLaunchView: View {
    public init() {}

    public var body: some View {
        GeometryReader { proxy in
            ZStack {
                Image("SprashBack")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()

                Image("MissCat")
                    .resizable()
                    .scaledToFit()
                    .frame(
                        width: proxy.size.height * 0.196429,
                        height: proxy.size.height * 0.196429
                    )
                    .accessibilityHidden(true)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("launch.screen")
        .preferredColorScheme(.light)
    }
}
