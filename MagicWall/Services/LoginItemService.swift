import ServiceManagement
import SwiftUI

/// Manages "launch at login" through SMAppService.
@MainActor
final class LoginItemService: ObservableObject {
    @Published private(set) var isEnabled: Bool = false
    @Published var lastError: String?

    init() {
        refresh()
    }

    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        lastError = nil
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            lastError = "Could not update the login item: \(error.localizedDescription)"
        }
        refresh()
    }
}
