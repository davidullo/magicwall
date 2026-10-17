import MagicWallCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var viewModel: LibraryViewModel
    @EnvironmentObject private var engine: WallpaperEngine
    @EnvironmentObject private var loginItemService: LoginItemService

    var body: some View {
        TabView {
            engineTab
                .tabItem { Label("Wallpaper", systemImage: "display") }
            libraryTab
                .tabItem { Label("Library", systemImage: "folder") }
            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 340)
    }

    // MARK: - Tabs

    private var engineTab: some View {
        Form {
            Section("Playback") {
                Toggle("Pause wallpaper", isOn: Binding(
                    get: { engine.isPaused },
                    set: { engine.isPaused = $0 }
                ))
                Toggle("Pause when on battery", isOn: $engine.pauseOnBattery)
                Toggle("Pause when desktop is hidden", isOn: $engine.pauseWhenOccluded)
            }
            Section("Startup") {
                Toggle("Launch MagicWall at login", isOn: Binding(
                    get: { loginItemService.isEnabled },
                    set: { loginItemService.setEnabled($0) }
                ))
                if let error = loginItemService.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var libraryTab: some View {
        Form {
            Section("Storage") {
                LabeledContent("Videos", value: "\(viewModel.videos.count)")
                LabeledContent("Library size", value: viewModel.librarySizeLabel)
                LabeledContent("Location") {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([AppPaths.libraryRoot])
                    }
                }
            }
            Section("Maintenance") {
                Button("Refresh Library") {
                    viewModel.refresh()
                }
            }
        }
        .formStyle(.grouped)
    }

    private var aboutTab: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles.tv")
                .font(.system(size: 42))
                .foregroundStyle(.tint)
            Text("MagicWall")
                .font(.title2.weight(.semibold))
            Text("Version \(Bundle.main.shortVersion) (\(Bundle.main.buildNumber))")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Local video wallpapers for macOS.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension Bundle {
    var shortVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0"
    }
    var buildNumber: String {
        (infoDictionary?["CFBundleVersion"] as? String) ?? "0"
    }
}
