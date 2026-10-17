import MagicWallCore
import SwiftUI

/// Icon of the menu bar item.
///
/// The menu bar is the only surface that is always visible while the wallpaper
/// plays (the library window is often closed), so a wallpaper that stopped
/// because of a power rule has to be visible here: the glyph flips to a pause
/// symbol and the menu spells the reason out.
struct MenuBarLabel: View {
    @EnvironmentObject private var engine: WallpaperEngine

    var body: some View {
        Label("MagicWall", systemImage: engine.menuBarSymbol)
            .accessibilityLabel(menuBarAccessibilityLabel)
    }

    private var menuBarAccessibilityLabel: String {
        guard !engine.pauseReasons.isEmpty else { return "MagicWall" }
        return L("settings.playback.paused", playbackPauseSummary(engine.pauseReasons))
    }
}
