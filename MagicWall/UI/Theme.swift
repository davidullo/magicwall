import SwiftUI

/// Destinations of the main window. The chrome is a custom top bar (no sidebar),
/// so the current tab is plain view state.
enum AppTab: String, CaseIterable, Identifiable {
    case home
    case explore
    case library
    case favorites

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .explore: return "Explore"
        case .library: return "Libreria"
        case .favorites: return "Preferiti"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .explore: return "safari.fill"
        case .library: return "square.grid.2x2.fill"
        case .favorites: return "heart.fill"
        }
    }
}

/// Dark-only palette and shared metrics (Netflix/Disney+ flavoured).
enum MagicWallTheme {
    static let background = Color(red: 0.043, green: 0.047, blue: 0.055)
    static let surface = Color(red: 0.078, green: 0.086, blue: 0.102)
    static let surfaceHigh = Color(red: 0.125, green: 0.133, blue: 0.153)
    static let stroke = Color.white.opacity(0.08)
    static let accent = Color(red: 0.58, green: 0.36, blue: 0.98)
    static let accentAlt = Color(red: 0.96, green: 0.31, blue: 0.62)
    static let live = Color(red: 0.19, green: 0.82, blue: 0.48)

    static let cardRadius: CGFloat = 12
    static let heroHeight: CGFloat = 430
    static let gutter: CGFloat = 32
    static let shelfHeight: CGFloat = 222

    static let accentGradient = LinearGradient(
        colors: [accentAlt, accent],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Vertical fade used by the hero banner so text stays readable on any poster.
    static let heroScrim = LinearGradient(
        stops: [
            .init(color: .black.opacity(0.08), location: 0.0),
            .init(color: .black.opacity(0.28), location: 0.42),
            .init(color: background.opacity(0.90), location: 0.84),
            .init(color: background, location: 1.0)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Bottom-heavy scrim used by the fullscreen preview.
    static let bottomScrim = LinearGradient(
        stops: [
            .init(color: .black.opacity(0.0), location: 0.0),
            .init(color: .black.opacity(0.55), location: 0.62),
            .init(color: .black.opacity(0.92), location: 1.0)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    static let topScrim = LinearGradient(
        stops: [
            .init(color: .black.opacity(0.65), location: 0.0),
            .init(color: .black.opacity(0.0), location: 1.0)
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}
