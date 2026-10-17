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
        WindowGroup("MagicWall") {
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

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set at launch so termination can shut the engine down cleanly.
    static weak var engine: WallpaperEngine?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppDelegate.engine?.prepareForTermination()
    }
}
