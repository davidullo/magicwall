import AppKit
import SwiftUI

/// An `NSView` that never intercepts mouse events, so hosting it behind
/// SwiftUI content cannot swallow clicks or drag & drop.
final class PassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Semi-transparent, Apple-style sidebar material (Finder / Music).
///
/// `NSVisualEffectView` with `.sidebar` + `.behindWindow` gives the real
/// desktop blur; `WindowChromeConfigurator` below makes the hosting window
/// non-opaque so the blur has something to show through.
struct SidebarMaterialView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = SidebarMaterialNSView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

final class SidebarMaterialNSView: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Blends the window chrome with the content: transparent titlebar, no title
/// text, and an extended content view so the sidebar material can bleed under
/// the traffic lights. Also keeps the top-right corner clean (no toolbar pill).
struct WindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = PassthroughView(frame: .zero)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView.window) }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isOpaque = false
        window.backgroundColor = .clear
    }
}
