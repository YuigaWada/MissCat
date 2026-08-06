import Foundation
import SwiftUI

/// Values recovered from the legacy storyboard, XIBs and the 2020 reference screenshots.
/// Keep the numeric values in this type so screenshot tests can assert the visual contract.
public enum MissCatLegacyMetrics {
    public static let referenceCanvas = CGSize(width: 414, height: 896)

    public static let welcomeHorizontalInset: CGFloat = 20
    public static let welcomeReferenceButtonGap: CGFloat = 44
    public static let welcomeButtonCornerRadius: CGFloat = 10
    public static let welcomeLogoHorizontalInset: CGFloat = 40
    public static let welcomeLogoHeight: CGFloat = 112
    public static let welcomeLogoTopFromSafeArea: CGFloat = 236
    public static let welcomeTaglineGap: CGFloat = 3
    public static let welcomeChangeInstanceGap: CGFloat = 20
    public static let welcomeChangeInstanceBottomFromSafeArea: CGFloat = 50
    public static let welcomeInstanceBottomFromSafeArea: CGFloat = 10

    public static let timelineTabsHeight: CGFloat = 43
    public static let timelineSelectionHeight: CGFloat = 2
    public static let bottomBarHeight: CGFloat = 55
    public static let bottomBarItemSpacing: CGFloat = 10
    public static let composeButtonDiameter: CGFloat = 48
    public static let navigationHeaderHeight: CGFloat = 44
    public static let hairlineWidth: CGFloat = 0.5

    /// Storyboard ratio: button height = canvas height × 0.0569196.
    public static func welcomeButtonHeight(canvasHeight: CGFloat) -> CGFloat {
        canvasHeight * 0.0569196
    }

    /// Mirrors the two 39.8551%-wide buttons and their flexible middle gap.
    public static func welcomeButtonWidth(canvasWidth: CGFloat) -> CGFloat {
        canvasWidth * 0.398551
    }
}

public enum MissCatLegacyColorHex {
    public static let accent = "2F7CF6"
    public static let welcomeGradientBottomLeading = "4691A3"
    public static let welcomeGradientMiddle = "5AB0C5"
    public static let welcomeGradientTopTrailing = "89D5E8"

    public static let lightBase = "FFFFFF"
    public static let lightStrong = "555555"
    public static let lightBorder = "C6C6C6"
    public static let lightMuted = "D3D3D3"
    public static let lightSurface = "F0F0F0"
    public static let lightText = "000000"

    public static let darkBase = "1F1F1F"
    public static let darkStrong = "C5C5C5"
    public static let darkBorder = "555555"
    public static let darkSurface = "303030"
    public static let darkText = "FFFFFF"
}

public struct MissCatVisualPalette: Sendable {
    public var accent: Color
    public var base: Color
    public var strong: Color
    public var border: Color
    public var muted: Color
    public var surface: Color
    public var text: Color

    public init(
        accent: Color,
        base: Color,
        strong: Color,
        border: Color,
        muted: Color,
        surface: Color,
        text: Color
    ) {
        self.accent = accent
        self.base = base
        self.strong = strong
        self.border = border
        self.muted = muted
        self.surface = surface
        self.text = text
    }

    public static let legacyLight = MissCatVisualPalette(
        accent: Color(hex: MissCatLegacyColorHex.accent),
        base: Color(hex: MissCatLegacyColorHex.lightBase),
        strong: Color(hex: MissCatLegacyColorHex.lightStrong),
        border: Color(hex: MissCatLegacyColorHex.lightBorder),
        muted: Color(hex: MissCatLegacyColorHex.lightMuted),
        surface: Color(hex: MissCatLegacyColorHex.lightSurface),
        text: Color(hex: MissCatLegacyColorHex.lightText)
    )

    public static let legacyDark = MissCatVisualPalette(
        accent: Color(hex: MissCatLegacyColorHex.accent),
        base: Color(hex: MissCatLegacyColorHex.darkBase),
        strong: Color(hex: MissCatLegacyColorHex.darkStrong),
        border: Color(hex: MissCatLegacyColorHex.darkBorder),
        muted: Color(hex: "ADADAD"),
        surface: Color(hex: MissCatLegacyColorHex.darkSurface),
        text: Color(hex: MissCatLegacyColorHex.darkText)
    )
}

public enum MissCatTypography {
    public static let welcomeTagline = Font.system(size: 17)
    public static let welcomeButton = Font.system(size: 17)
    public static let welcomeInstance = Font.system(size: 15)
    public static let timelineTab = Font.system(size: 17)
    public static let navigationTitle = Font.system(size: 17, weight: .medium)
}

public extension Color {
    init(hex: String, opacity: Double = 1) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)

        let red: UInt64
        let green: UInt64
        let blue: UInt64

        switch cleaned.count {
        case 3:
            red = ((value >> 8) & 0xF) * 17
            green = ((value >> 4) & 0xF) * 17
            blue = (value & 0xF) * 17
        default:
            red = (value >> 16) & 0xFF
            green = (value >> 8) & 0xFF
            blue = value & 0xFF
        }

        self.init(
            .sRGB,
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255,
            opacity: opacity
        )
    }
}
