import AppKit
import MagicWallCore
import SwiftUI

/// Content of the existing `MenuBarExtra`.
///
/// Kept deliberately light: no view state beyond presentation, every action
/// delegates to `LibraryViewModel` or `WallpaperEngine`. Items whose action
/// cannot apply right now are hidden rather than shown disabled.
struct MenuBarMenuView: View {
    @EnvironmentObject private var viewModel: LibraryViewModel
    @EnvironmentObject private var engine: WallpaperEngine

    var body: some View {
        Button("Apri MagicWall") {
            openMainWindow()
        }

        Divider()

        screenStatusSection

        Divider()

        playbackToggles

        Divider()

        favoritesMenu

        Button("Prossimo casuale") {
            viewModel.applyRandomToAllScreens()
        }
        .disabled(viewModel.videos.isEmpty)

        Button("Importa video…") {
            viewModel.presentImportPanel()
        }
        .disabled(viewModel.isImporting)

        if engine.hasActiveWallpaper {
            Button("Ferma wallpaper") {
                engine.clearAll()
            }
        }

        Divider()

        Button("Esci") {
            NSApp.terminate(nil)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var screenStatusSection: some View {
        if engine.statuses.isEmpty {
            Text("Nessun display rilevato")
        } else {
            ForEach(engine.statuses) { status in
                Text(statusLine(status))
            }
        }
    }

    @ViewBuilder
    private var playbackToggles: some View {
        Toggle("Pausa wallpaper", isOn: $engine.isPaused)
        Toggle("Pausa su batteria", isOn: $engine.pauseOnBattery)
        Toggle("Pausa con desktop nascosto", isOn: $engine.pauseWhenOccluded)
    }

    @ViewBuilder
    private var favoritesMenu: some View {
        let favorites = favoriteVideos
        Menu("Applica preferito") {
            if favorites.isEmpty {
                Text("Nessun preferito")
            } else {
                ForEach(favorites) { video in
                    Button(video.title) {
                        viewModel.applyToAllScreens(video)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    /// Up to ten favorite videos, alphabetically sorted, ready for the submenu.
    private var favoriteVideos: [Video] {
        Array(
            viewModel.videos
                .filter { viewModel.favoriteIDs.contains($0.id) }
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
                .prefix(10)
        )
    }

    private func statusLine(_ status: WallpaperEngine.ScreenStatus) -> String {
        if let title = status.videoTitle {
            return "\(status.name): \(title)"
        }
        return "\(status.name): nessun wallpaper"
    }

    /// Brings the library window to the front, activating the app first.
    ///
    /// Prefers the main window (the one with a toolbar) over auxiliary windows
    /// such as the Settings panel, then falls back to the first titled window.
    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)

        let titled = NSApp.windows.filter { $0.styleMask.contains(.titled) }
        let target = titled.first(where: { $0.toolbar != nil }) ?? titled.first
        target?.deminiaturize(nil)
        target?.makeKeyAndOrderFront(nil)
    }
}
