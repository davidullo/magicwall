import AppKit
import SwiftUI

@main
struct MagicWallApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel: LibraryViewModel
    @StateObject private var engine: WallpaperEngine
    @StateObject private var starterService: StarterWallpaperService
    @StateObject private var loginItemService = LoginItemService()
    @StateObject private var themeStore = ThemeStore()
    @StateObject private var localization = LocalizationManager.shared
    @StateObject private var updater = UpdaterController()
    @StateObject private var wallpaperExtensionService: WallpaperExtensionService

    init() {
        let environment = AppEnvironment.bootstrap()
        _viewModel = StateObject(wrappedValue: environment.viewModel)
        _engine = StateObject(wrappedValue: environment.engine)

        // A starter wallpaper replaced by an upgrade (quality tier) has to be
        // re-read by the engine when it is currently on screen.
        let starterService = StarterWallpaperService(repository: environment.repository)
        let engine = environment.engine
        starterService.onVideoReplaced = { [weak engine] videoID in
            engine?.reloadDisplayedVideo(id: videoID)
        }
        _starterService = StateObject(wrappedValue: starterService)

        // Lock screen: the same library, mirrored into the wallpaper
        // extension's sandbox container and watched back from the system store.
        let wallpaperExtensionService = WallpaperExtensionService(repository: environment.repository)
        wallpaperExtensionService.track(environment.viewModel.$videos)
        _wallpaperExtensionService = StateObject(wrappedValue: wallpaperExtensionService)

        AppDelegate.engine = environment.engine
        AppDelegate.wallpaperExtension = wallpaperExtensionService
    }

    var body: some Scene {
        WindowGroup("MagicWall", id: MainWindow.sceneID) {
            MainWindowRoot {
                ContentView()
                    .environmentObject(viewModel)
                    .environmentObject(engine)
                    .environmentObject(starterService)
                    .environmentObject(themeStore)
                    .environmentObject(localization)
                    .environmentObject(updater)
                    .id(localization.language)
                    .task {
                        engine.start()
                        viewModel.refresh()
                        if let warning = viewModel.startupWarnings.first {
                            viewModel.statusMessage = warning
                        }
                    }
            }
        }
        .defaultSize(width: 1180, height: 780)
        .commands {
            CommandGroup(after: .appInfo) {
                if updater.isActive {
                    CheckForUpdatesMenuItem(updater: updater)
                }
            }
        }

        MenuBarExtra {
            MenuBarMenuView()
                .environmentObject(viewModel)
                .environmentObject(engine)
                .environmentObject(themeStore)
                .environmentObject(localization)
                .environmentObject(updater)
                .id(localization.language)
        } label: {
            MenuBarLabel()
                .environmentObject(engine)
        }

        Settings {
            SettingsView()
                .environmentObject(viewModel)
                .environmentObject(engine)
                .environmentObject(starterService)
                .environmentObject(loginItemService)
                .environmentObject(wallpaperExtensionService)
                .environmentObject(themeStore)
                .environmentObject(localization)
                .environmentObject(updater)
                .id(localization.language)
        }
    }
}

/// Captures the scene's `openWindow` action for `MainWindow`, so the window can
/// be recreated after the user closes it with the red button (the app keeps
/// running for the wallpaper engine).
private struct MainWindowRoot<Content: View>: View {
    @Environment(\.openWindow) private var openWindow

    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .onAppear {
                MainWindow.openAction = { openWindow(id: MainWindow.sceneID) }
            }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set at launch so termination can shut the engine down cleanly.
    static weak var engine: WallpaperEngine?

    /// Set at launch so the lock screen mirror is refreshed even when the
    /// library window never appears (login item, menu-bar only launch).
    static weak var wallpaperExtension: WallpaperExtensionService?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// The engine must run even when the library window never appears — a login
    /// item launch or a restored session must still bring back the assigned
    /// wallpapers and the saved playback rules. `start()` is idempotent, so the
    /// main window's `.task` keeps calling it harmlessly.
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.engine?.start()
        AppDelegate.wallpaperExtension?.startLibrarySync()
    }

    /// macOS calls this when the app is activated while running — typically a
    /// click on the Dock icon after the library window was closed. Without a
    /// handler SwiftUI does not recreate the window and the app looks stuck.
    ///
    /// `hasVisibleWindows` is ignored on purpose: the wallpaper desktop windows
    /// count as visible, so the flag is true even when the library window is
    /// gone. `MainWindow.present()` decides what to do.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainWindow.present()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppDelegate.engine?.prepareForTermination()
    }
}
