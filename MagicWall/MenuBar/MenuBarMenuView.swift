import SwiftUI

struct MenuBarMenuView: View {
    @EnvironmentObject private var viewModel: LibraryViewModel
    @EnvironmentObject private var engine: WallpaperEngine

    var body: some View {
        Button("Open MagicWall") {
            NSApp.activate(ignoringOtherApps: true)
        }

        Divider()

        if engine.statuses.isEmpty {
            Text("No displays detected")
        } else {
            ForEach(engine.statuses) { status in
                Text(statusLine(status))
            }
        }

        Divider()

        Toggle("Pause Wallpaper", isOn: Binding(
            get: { engine.isPaused },
            set: { engine.isPaused = $0 }
        ))

        Button("Next Random Wallpaper") {
            viewModel.applyRandomToAllScreens()
        }
        .disabled(viewModel.videos.isEmpty)

        Button("Stop Wallpaper") {
            engine.clearAll()
        }
        .disabled(!engine.hasActiveWallpaper)

        Divider()

        Button("Quit MagicWall") {
            NSApp.terminate(nil)
        }
    }

    private func statusLine(_ status: WallpaperEngine.ScreenStatus) -> String {
        if let title = status.videoTitle {
            return "\(status.name): \(title)"
        }
        return "\(status.name): no wallpaper"
    }
}
