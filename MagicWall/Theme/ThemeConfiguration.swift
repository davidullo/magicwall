import AppKit
import SwiftUI

/// Every visual token of the app. Stored as hex strings so a theme is portable
/// JSON, editable from the Settings theme editor, and easy to persist/share.
struct ThemeConfiguration: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var isBuiltIn: Bool

    // MARK: Brand

    var accent: String
    var accentText: String

    // MARK: Backgrounds

    var windowBackground: String
    var sidebarBackground: String
    var surface: String
    var surfaceHover: String
    var surfaceSelected: String

    // MARK: Text

    var textPrimary: String
    var textSecondary: String
    var textTertiary: String

    // MARK: Badges & pills

    var badgeBackground: String
    var badgeText: String
    var liveBadgeBackground: String
    var liveBadgeText: String

    // MARK: Buttons & chrome

    var buttonSecondaryBackground: String
    var buttonSecondaryText: String
    var divider: String

    // MARK: Shape & typography

    var cornerRadius: Double
    var titleWeight: String
    var useGradients: Bool

    static let titleWeightOptions = ["regular", "medium", "semibold", "bold", "heavy"]

    /// Built-in default theme: minimal dark UI with the MagicWall pink accent.
    static let midnight = ThemeConfiguration(
        id: "builtin.midnight",
        name: "Midnight",
        isBuiltIn: true,
        accent: "#FF5EDA",
        accentText: "#FFFFFF",
        windowBackground: "#0B0B0F",
        sidebarBackground: "#141419CC",
        surface: "#17171D",
        surfaceHover: "#202028",
        surfaceSelected: "#2A2A35",
        textPrimary: "#F5F5F7",
        textSecondary: "#9B9BA4",
        textTertiary: "#6E6E78",
        badgeBackground: "#FFFFFF14",
        badgeText: "#D7D7DE",
        liveBadgeBackground: "#34C759",
        liveBadgeText: "#FFFFFF",
        buttonSecondaryBackground: "#FFFFFF14",
        buttonSecondaryText: "#F5F5F7",
        divider: "#FFFFFF14",
        cornerRadius: 12,
        titleWeight: "bold",
        useGradients: false
    )

    static func makeNew(named name: String, basedOn base: ThemeConfiguration) -> ThemeConfiguration {
        var copy = base
        copy.id = UUID().uuidString
        copy.name = name
        copy.isBuiltIn = false
        return copy
    }
}

// MARK: - Typed accessors

extension ThemeConfiguration {
    var accentColor: Color { Color(themeHex: accent) }
    var accentTextColor: Color { Color(themeHex: accentText) }
    var windowBackgroundColor: Color { Color(themeHex: windowBackground) }
    var sidebarBackgroundColor: Color { Color(themeHex: sidebarBackground) }
    var surfaceColor: Color { Color(themeHex: surface) }
    var surfaceHoverColor: Color { Color(themeHex: surfaceHover) }
    var surfaceSelectedColor: Color { Color(themeHex: surfaceSelected) }
    var textPrimaryColor: Color { Color(themeHex: textPrimary) }
    var textSecondaryColor: Color { Color(themeHex: textSecondary) }
    var textTertiaryColor: Color { Color(themeHex: textTertiary) }
    var badgeBackgroundColor: Color { Color(themeHex: badgeBackground) }
    var badgeTextColor: Color { Color(themeHex: badgeText) }
    var liveBadgeBackgroundColor: Color { Color(themeHex: liveBadgeBackground) }
    var liveBadgeTextColor: Color { Color(themeHex: liveBadgeText) }
    var buttonSecondaryBackgroundColor: Color { Color(themeHex: buttonSecondaryBackground) }
    var buttonSecondaryTextColor: Color { Color(themeHex: buttonSecondaryText) }
    var dividerColor: Color { Color(themeHex: divider) }

    var cornerRadiusValue: CGFloat { CGFloat(cornerRadius) }

    var titleFontWeight: Font.Weight {
        switch titleWeight {
        case "regular": return .regular
        case "medium": return .medium
        case "semibold": return .semibold
        case "heavy": return .heavy
        default: return .bold
        }
    }
}

// MARK: - Hex <-> Color

extension Color {
    /// Parses `#RRGGBB`, `RRGGBB`, `#RRGGBBAA` or `RRGGBBAA`.
    init(themeHex hex: String) {
        self = Color(nsColor: NSColor(themeHex: hex) ?? .magenta)
    }

    /// Serializes to `#RRGGBBAA` in the sRGB space (used by the theme editor).
    var themeHexString: String {
        guard let rgb = NSColor(self).usingColorSpace(.sRGB) else { return "#FF5EDAFF" }
        let r = Int((rgb.redComponent * 255).rounded())
        let g = Int((rgb.greenComponent * 255).rounded())
        let b = Int((rgb.blueComponent * 255).rounded())
        let a = Int((rgb.alphaComponent * 255).rounded())
        return String(format: "#%02X%02X%02X%02X", r, g, b, a)
    }
}

extension NSColor {
    convenience init?(themeHex hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6 || value.count == 8,
              let number = UInt64(value, radix: 16) else { return nil }
        let hasAlpha = value.count == 8
        let r = CGFloat((number >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let g = CGFloat((number >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let b = CGFloat((number >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let a = hasAlpha ? CGFloat(number & 0xFF) / 255 : 1
        self.init(srgbRed: r, green: g, blue: b, alpha: a)
    }
}
