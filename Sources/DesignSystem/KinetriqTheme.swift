import SwiftUI

// MARK: - Kinetriq Design System (v2 — "Premium" redesign)
//
// This file defines the visual language for the redesigned Kinetriq UI:
// color, typography, spacing, radius, and elevation tokens. Everything is
// adaptive (light + dark) so the app stays legible in both appearances while
// leaning into the high-contrast, data-forward feel of premium fitness apps
// (Whoop / Oura / Apple Fitness / Levels).
//
// The original UI is preserved on the `fix/saved-video-loading` branch and can
// be restored at any time — nothing here mutates the analysis pipeline.

// MARK: - Color utilities

extension Color {
    /// Hex initializer, e.g. `Color(hex: 0x3B82F6)`.
    init(hex: UInt, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }

    /// Appearance-adaptive color built from two hex values.
    init(lightHex: UInt, darkHex: UInt) {
        let light = UIColor(Color(hex: lightHex))
        let dark = UIColor(Color(hex: darkHex))
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

// MARK: - Brand palette

enum KColor {
    // Signature brand — an electric "kinetic" blue with a teal/violet support.
    static let accent       = Color(hex: 0x3D7BFF)   // primary action / brand
    static let accentDeep   = Color(hex: 0x2A5BE0)
    static let teal         = Color(hex: 0x21D0B2)   // positive movement / mint
    static let violet       = Color(hex: 0x8B5CF6)   // secondary accent / assessments
    static let amber        = Color(hex: 0xF6B73C)

    // Semantic feedback
    static let success      = Color(hex: 0x2FCB6E)
    static let warning      = Color(hex: 0xF6B73C)
    static let danger       = Color(hex: 0xFB4D63)

    // Surfaces (adaptive)
    static let background     = Color(lightHex: 0xF4F6FB, darkHex: 0x0B0E14)
    static let surface        = Color(lightHex: 0xFFFFFF, darkHex: 0x161A23)
    static let surfaceElevated = Color(lightHex: 0xFFFFFF, darkHex: 0x1E2430)
    static let surfaceSunken  = Color(lightHex: 0xEDF0F7, darkHex: 0x10131A)
    static let separator      = Color(lightHex: 0xE2E6F0, darkHex: 0x2A313F)

    // Text (adaptive)
    static let textPrimary   = Color(lightHex: 0x0B0E14, darkHex: 0xF4F6FB)
    static let textSecondary = Color(lightHex: 0x5A6478, darkHex: 0x9AA4B8)
    static let textTertiary  = Color(lightHex: 0x8A93A6, darkHex: 0x6A7283)

    /// Signature hero gradient used on scores, CTAs, and brand moments.
    static let brandGradient = LinearGradient(
        colors: [Color(hex: 0x3D7BFF), Color(hex: 0x6E5CFF)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let tealGradient = LinearGradient(
        colors: [Color(hex: 0x21D0B2), Color(hex: 0x16A4D8)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Letter-grade color, shared by exercise scores and assessments.
    static func grade(_ grade: LetterGrade) -> Color {
        switch grade {
        case .A: return success
        case .B: return teal
        case .C: return warning
        case .D: return amber
        case .F: return danger
        }
    }

    /// 0–100 score color ramp.
    static func score(_ value: Int) -> Color {
        switch value {
        case 80...: return success
        case 60..<80: return warning
        default: return danger
        }
    }
}

// MARK: - Spacing scale (8pt-based)

enum KSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 28
    static let xxl: CGFloat = 40
    static let screenH: CGFloat = 20   // standard horizontal screen inset
}

// MARK: - Corner radius

enum KRadius {
    static let sm: CGFloat = 12
    static let md: CGFloat = 18
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let pill: CGFloat = 999
}

// MARK: - Typography
//
// A clear, restrained type ramp using SF Rounded for a friendly-premium feel.
// Numbers (scores, reps, angles) use rounded + monospaced digits for stability.

enum KFont {
    static func display(_ size: CGFloat = 40) -> Font { .system(size: size, weight: .bold, design: .rounded) }
    static let title = Font.system(size: 26, weight: .bold, design: .rounded)
    static let title2 = Font.system(size: 20, weight: .semibold, design: .rounded)
    static let headline = Font.system(size: 17, weight: .semibold, design: .rounded)
    static let body = Font.system(size: 16, weight: .regular)
    static let subheadline = Font.system(size: 15, weight: .regular)
    static let callout = Font.system(size: 15, weight: .semibold, design: .rounded)
    static let caption = Font.system(size: 13, weight: .regular)
    static let micro = Font.system(size: 11, weight: .semibold, design: .rounded)

    /// Big stat numerals (scores, reps).
    static func numeral(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }

    /// All-caps section/eyebrow label style.
    static let eyebrow = Font.system(size: 12, weight: .bold, design: .rounded)
}

// MARK: - Elevation

extension View {
    /// Soft, premium card shadow that reads in both light and dark.
    func kCardShadow() -> some View {
        shadow(color: Color.black.opacity(0.10), radius: 18, x: 0, y: 10)
    }

    func kSoftShadow() -> some View {
        shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 4)
    }
}
