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
    @EnvironmentObject private var updater: UpdaterController

    var body: some View {
        Button(L("menubar.open")) {
            openMainWindow()
        }

        Divider()

        screenStatusSection

        Divider()

        playbackToggles

        Divider()

        favoritesMenu
        rotationMenu

        Button(L("menubar.nextRandom")) {
            viewModel.applyRandomToAllScreens()
        }
        .disabled(viewModel.videos.isEmpty)

        Button(L("common.importVideosEllipsis")) {
            viewModel.presentImportPanel()
        }
        .disabled(viewModel.isImporting)

        if engine.hasActiveWallpaper {
            Button(L("menubar.stop")) {
                engine.clearAll()
            }
        }

        Divider()

        if updater.isActive {
            Button(L("update.check")) {
                updater.checkForUpdates()
            }
            .disabled(!updater.canCheckForUpdates)
        }

        Button(L("menubar.quit")) {
            NSApp.terminate(nil)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var screenStatusSection: some View {
        if engine.statuses.isEmpty {
            Text(L("menubar.noDisplay"))
        } else {
            ForEach(engine.statuses) { status in
                Text(statusLine(status))
            }
        }
    }

    @ViewBuilder
    private var playbackToggles: some View {
        Toggle(L("playback.pause.wallpapers"), isOn: $engine.isPaused)
        Toggle(L("playback.pause.battery"), isOn: $engine.pauseOnBattery)
        Toggle(L("playback.pause.occluded"), isOn: $engine.pauseWhenOccluded)
    }

    @ViewBuilder
    private var favoritesMenu: some View {
        let favorites = favoriteVideos
        Menu(L("menubar.favorites.apply")) {
            if favorites.isEmpty {
                Text(L("menubar.favorites.empty"))
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

    /// Rotation over the favorites: on/off, how often and "next now", so the
    /// wallpaper can be controlled with the window closed.
    @ViewBuilder
    private var rotationMenu: some View {
        Menu(L("menubar.rotation")) {
            Toggle(L("menubar.rotation.enabled"), isOn: Binding(
                get: { engine.rotationEnabled },
                set: { engine.setRotationEnabled($0) }
            ))

            Divider()

            ForEach(RotationInterval.allCases, id: \.self) { interval in
                Button {
                    engine.setRotationInterval(interval)
                } label: {
                    if interval == engine.rotationInterval {
                        Label(rotationIntervalLabel(interval), systemImage: "checkmark")
                    } else {
                        Text(rotationIntervalLabel(interval))
                    }
                }
            }

            Divider()

            Button(L("menubar.rotation.next")) {
                engine.advanceRotationNow()
            }
            .disabled(viewModel.favoriteIDs.isEmpty)
        }
    }

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
        return L("menubar.status.none", status.name)
    }

    /// Brings the library window to the front, recreating it when the user
    /// closed it (the app keeps running so the wallpaper never stops).
    private func openMainWindow() {
        MainWindow.present()
    }
}
