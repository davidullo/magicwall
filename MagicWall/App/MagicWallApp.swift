import SwiftUI

@main
struct MagicWallApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel: LibraryViewModel
    @StateObject private var engine: WallpaperEngine
    @StateObject private var loginItemService = LoginItemService()

    init() {
        let environment = AppEnvironment.bootstrap()
        _viewModel = StateObject(wrappedValue: environment.viewModel)
        _engine = StateObject(wrappedValue: environment.engine)
    }

    var body: some Scene {
        WindowGroup("MagicWall") {
            ContentView()
                .environmentObject(viewModel)
                .environmentObject(engine)
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
        } label: {
            Label("MagicWall", systemImage: "sparkles.tv")
        }

        Settings {
            SettingsView()
                .environmentObject(viewModel)
                .environmentObject(engine)
                .environmentObject(loginItemService)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
