import AppKit
import ServiceManagement
import SwiftUI

/// Manages "launch at login" through `SMAppService.mainApp`.
///
/// The service keeps a human-readable `lastError` and never crashes or shows
/// blocking dialogs: registering a login item can legitimately fail when the
/// app is not signed with a Developer ID, and that failure is surfaced as
/// inline text so the user can fall back to System Settings.
@MainActor
final class LoginItemService: ObservableObject {
    /// Whether the login item is currently registered and enabled.
    @Published private(set) var isEnabled: Bool = false
    /// The login item is registered but waiting for the user to approve it in
    /// System Settings (macOS 13+ behaviour for some signing states).
    @Published private(set) var requiresApproval: Bool = false
    /// Last user-facing error, or `nil` when everything is fine.
    @Published private(set) var lastError: String?

    private var activationObserver: NSObjectProtocol?

    init() {
        refresh()
        observeActivation()
    }

    deinit {
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
    }

    // MARK: - API

    /// Re-reads the current status. Cheap and safe to call often.
    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        requiresApproval = status == .requiresApproval

        // `.notFound` means the bundle is not a valid login-item host
        // (e.g. launched from a location macOS does not persist). Everything
        // else is a normal state and does not need an error message.
        if status == .notFound, lastError == nil {
            lastError = L("login.error.notFound")
        }
    }

    /// Enables or disables the login item. Errors are captured in `lastError`.
    func setEnabled(_ enabled: Bool) {
        lastError = nil
        let service = SMAppService.mainApp

        do {
            if enabled {
                if service.status != .enabled {
                    try service.register()
                }
            } else if service.status == .enabled || service.status == .requiresApproval {
                try service.unregister()
            }
        } catch {
            lastError = failureMessage(for: error, enabling: enabled)
        }

        refresh()
    }

    /// Opens System Settings → General → Login Items so the user can fix or
    /// approve the login item manually.
    func openSystemSettingsLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }

    // MARK: - Private

    private func observeActivation() {
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    private func failureMessage(for error: Error, enabling: Bool) -> String {
        // A local, ad-hoc signed build cannot register a login item, and the
        // error domain/code is not stable enough to special-case. Instead we
        // always point at the manual fallback, which works in every case.
        let key = enabling ? "login.error.enable" : "login.error.disable"
        return L(key, error.localizedDescription)
    }
}
