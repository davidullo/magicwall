import AppKit
import SwiftUI

@main
struct MagicWallApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel: LibraryViewModel
    @StateObject private var engine: WallpaperEngine
    @StateObject private var loginItemService = LoginItemService()
    @StateObject private var themeStore = ThemeStore()
    @StateObject private var localization = LocalizationManager.shared

    init() {
        let environment = AppEnvironment.bootstrap()
        _viewModel = StateObject(wrappedValue: environment.viewModel)
        _engine = StateObject(wrappedValue: environment.engine)
        AppDelegate.engine = environment.engine
    }

    var body: some Scene {
        WindowGroup("MagicWall", id: MainWindow.sceneID) {
            MainWindowRoot {
                ContentView()
                    .environmentObject(viewModel)
                    .environmentObject(engine)
                    .environmentObject(themeStore)
                    .environmentObject(localization)
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

        MenuBarExtra {
            MenuBarMenuView()
                .environmentObject(viewModel)
                .environmentObject(engine)
                .environmentObject(themeStore)
                .environmentObject(localization)
                .id(localization.language)
        } label: {
            Label("MagicWall", systemImage: "sparkles.tv")
        }

        Settings {
            SettingsView()
                .environmentObject(viewModel)
                .environmentObject(engine)
                .environmentObject(loginItemService)
                .environmentObject(themeStore)
                .environmentObject(localization)
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

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
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
