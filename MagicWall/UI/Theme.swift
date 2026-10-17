import AppKit
import SwiftUI

/// Destinations of the main window sidebar.
enum AppTab: String, CaseIterable, Identifiable {
    case home
    case explore
    case library
    case favorites

    var id: String { rawValue }

    @MainActor var title: String {
        switch self {
        case .home: return L("tab.home")
        case .explore: return L("tab.explore")
        case .library: return L("tab.library")
        case .favorites: return L("tab.favorites")
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house"
        case .explore: return "safari"
        case .library: return "square.grid.2x2"
        case .favorites: return "heart"
        }
    }

    var selectedSymbol: String { symbol + ".fill" }
}

/// Layout constants only: every *color*, corner radius and font weight comes
/// from the active `ThemeConfiguration`. These values are geometry that does
/// not vary per theme.
enum MagicWallLayout {
    static let gutter: CGFloat = 32
    static let heroHeight: CGFloat = 430
    static let shelfHeight: CGFloat = 222
    static let sidebarWidth: CGFloat = 240
    static let contentTopInset: CGFloat = 32
}

// MARK: - ThemeConfiguration → SwiftUI adapter

/// Bridges the portable, hex-based `ThemeConfiguration` tokens to ready-to-use
/// SwiftUI values. Views never read hardcoded palette constants: they read
/// `theme.active.*` (the raw tokens) or these derived helpers.
extension ThemeConfiguration {
    /// Second stop of the accent gradient. Only used when the theme opts into
    /// gradients (`useGradients == true`); otherwise the accent stays flat.
    var accentSecondaryColor: Color {
        guard let base = NSColor(accentColor).usingColorSpace(.sRGB) else { return accentColor }
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        base.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let shifted = NSColor(
            hue: (hue + 0.08).truncatingRemainder(dividingBy: 1),
            saturation: min(1, saturation * 0.95),
            brightness: min(1, brightness * 1.05 + 0.05),
            alpha: alpha
        )
        return Color(nsColor: shifted)
    }

    var accentGradient: LinearGradient {
        LinearGradient(
            colors: [accentSecondaryColor, accentColor],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Flat accent by default, gradient only when the theme asks for it.
    var accentShapeStyle: AnyShapeStyle {
        useGradients ? AnyShapeStyle(accentGradient) : AnyShapeStyle(accentColor)
    }

    /// Small corner radius for rows, fields and compact buttons. Keeps small
    /// controls coherent with the (often larger) card radius.
    var controlRadius: CGFloat { max(6, cornerRadiusValue - 3) }

    /// Semantic error tint. No theme token models "error", so the adapter keeps
    /// a single UI-layer value instead of scattering literals in the views.
    var dangerColor: Color { Color(themeHex: "#FF6B6B") }

    // MARK: Scrims (derived from the window background token)

    /// Vertical fade used by the hero banner so text stays readable on any poster.
    var heroScrim: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.08), location: 0.0),
                .init(color: .black.opacity(0.30), location: 0.42),
                .init(color: windowBackgroundColor.opacity(0.90), location: 0.84),
                .init(color: windowBackgroundColor, location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var heroHorizontalScrim: LinearGradient {
        LinearGradient(
            colors: [windowBackgroundColor.opacity(0.92), windowBackgroundColor.opacity(0.0)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    /// Bottom-heavy scrim used by the fullscreen preview.
    var previewBottomScrim: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.0), location: 0.0),
                .init(color: .black.opacity(0.55), location: 0.62),
                .init(color: .black.opacity(0.92), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var previewTopScrim: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.65), location: 0.0),
                .init(color: .black.opacity(0.0), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
