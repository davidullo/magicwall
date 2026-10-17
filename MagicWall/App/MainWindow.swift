import AppKit

/// Single source of truth for the library window.
///
/// The app deliberately keeps running after the last window is closed so the
/// wallpaper engine never stops, which also means SwiftUI destroys the
/// `WindowGroup` window. Activating the app again (Dock icon, Finder, menu bar
/// item) has to recreate it: `applicationShouldHandleReopen` cannot do that on
/// its own, so the main scene stores its `openWindow` action here.
@MainActor
enum MainWindow {
    /// Identifier of the library window scene in `MagicWallApp`.
    static let sceneID = "main"

    /// The live window, registered by `WindowChromeConfigurator`.
    private(set) static weak var window: NSWindow?

    /// Recreates the window after SwiftUI tore it down on close.
    static var openAction: (() -> Void)?

    private static var closeObserver: NSObjectProtocol?

    /// Called whenever the main window's chrome is configured.
    static func register(_ window: NSWindow) {
        guard self.window !== window else { return }

        if let closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
        }

        self.window = window
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { _ in
            Task { @MainActor in
                if MainWindow.window === window {
                    MainWindow.window = nil
                }
            }
        }
    }

    /// Brings the library window back: fronts it when it still exists, asks
    /// SwiftUI to build a fresh one when it was closed.
    static func present() {
        NSApp.activate(ignoringOtherApps: true)

        if let window {
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
        } else {
            openAction?()
        }
    }
}
