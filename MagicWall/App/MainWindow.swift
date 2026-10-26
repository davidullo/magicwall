import AppKit

/// Single source of truth for the library window.
///
/// The app deliberately keeps running after the last window is closed so the
/// wallpaper engine never stops, which also means SwiftUI destroys the
/// `WindowGroup` window. A login-item launch is even more extreme: SwiftUI does
/// not create the window scene at all. Activating the app again (Dock icon,
/// Finder, menu bar item) has to recreate it: `applicationShouldHandleReopen`
/// cannot do that on its own, so the scenes store their `openWindow` action
/// here.
@MainActor
enum MainWindow {
    /// Identifier of the library window scene in `MagicWallApp`.
    static let sceneID = "main"

    /// The live window, registered by `WindowChromeConfigurator`.
    private(set) static weak var window: NSWindow?

    /// Recreates the window after SwiftUI tore it down on close.
    static var openAction: (() -> Void)?

    /// A presentation requested before SwiftUI handed over its `openWindow`
    /// action. A login-item launch starts without a `WindowGroup` scene, so the
    /// action can arrive a moment after the first click on the Dock icon.
    private static var pendingPresentation = false

    /// The deferred reopen request currently in flight, if any.
    private static var reopenTask: Task<Void, Never>?

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

    /// Installs the action that asks SwiftUI to create the library window.
    ///
    /// The `WindowGroup` content only appears once a window exists, so it
    /// cannot install this action on its own: a login-item launch starts with
    /// no window at all. The menu bar label (always present) installs it
    /// instead; this method is idempotent, so the window content can refresh it
    /// later.
    static func installOpenAction(_ action: @escaping () -> Void) {
        openAction = action

        guard pendingPresentation else { return }
        pendingPresentation = false
        action()
    }

    /// Handles an explicit "open MagicWall" request. Used by the menu bar item,
    /// where no system reopen event is involved.
    static func present() {
        NSApp.activate(ignoringOtherApps: true)
        reopenTask?.cancel()

        if let window {
            reveal(window)
        } else if let openAction {
            openAction()
        } else {
            // The menu bar label has not installed the action yet. Keep the
            // request so the click is not lost during a slow login launch.
            pendingPresentation = true
        }
    }

    /// Handles the system reopen event (Dock icon, Finder, `open`).
    ///
    /// SwiftUI occasionally restores a window by itself in response to the same
    /// event. Opening our own one immediately would leave the user with two
    /// identical library windows, so give SwiftUI a moment to do its thing and
    /// only create a window when none appeared. This is also the path that
    /// recovers a login-item launch, where SwiftUI never created a window.
    static func handleReopen() {
        NSApp.activate(ignoringOtherApps: true)

        if let window {
            reopenTask?.cancel()
            reveal(window)
            return
        }

        reopenTask?.cancel()
        reopenTask = Task { @MainActor in
            // One run loop is not enough for SwiftUI's window restoration on a
            // cold start; this is short enough to feel immediate to the user.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }

            if let window {
                reveal(window)
            } else if let openAction {
                openAction()
            } else {
                pendingPresentation = true
            }
        }
    }

    private static func reveal(_ window: NSWindow) {
        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
    }
}
