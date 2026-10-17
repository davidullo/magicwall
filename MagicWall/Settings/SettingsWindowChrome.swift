import AppKit
import SwiftUI

/// Themes the standard Settings window: transparent titlebar, no title text,
/// and a window background that matches the active theme instead of the system
/// default (which is what made Settings look white on a dark app).
struct SettingsWindowConfigurator: NSViewRepresentable {
    let theme: ThemeConfiguration

    func makeNSView(context: Context) -> NSView {
        let view = PassthroughView(frame: .zero)
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView.window) }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }

        let background = NSColor(themeHex: theme.windowBackground) ?? .black
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isOpaque = true
        window.backgroundColor = background
        window.appearance = NSAppearance(named: theme.isDarkAppearance ? .darkAqua : .aqua)
    }
}
