import Combine
import Foundation
import Security
import Sparkle
import SwiftUI

/// Owns Sparkle's standard updater and exposes it to the SwiftUI scenes.
///
/// Sparkle installs updates by validating the running app's code signature
/// against the update's: an ad-hoc or unsigned build can never install an
/// update, so the updater stays off for development builds and local releases
/// (see `isSupported`). `MW_ENABLE_UPDATES=1` / `MW_DISABLE_UPDATES=1` force
/// the two states for the release smoke test.
///
/// The default behaviour is: silent daily check for a new version, then an
/// explicit user confirmation before downloading and installing. MagicWall
/// stays in the menu bar for weeks, and an unsolicited relaunch would stop the
/// wallpaper, so silent installation is intentionally not enabled
/// (`SUAutomaticallyUpdate` is `NO` in Info.plist).
@MainActor
final class UpdaterController: NSObject, ObservableObject {
    /// Mirrors Sparkle's `canCheckForUpdates`: false while a check or an
    /// installation is already in progress.
    @Published private(set) var canCheckForUpdates = false

    /// Mirrors Sparkle's `automaticallyChecksForUpdates`. The Info.plist
    /// default is on; the user can switch it off in Settings → About.
    @Published private(set) var automaticallyChecksForUpdates = false

    /// False when the running build cannot use Sparkle (Debug builds, unsigned
    /// or ad-hoc releases, or the environment overrides). The UI hides the
    /// update controls in that case.
    private(set) var isActive = false

    private var controller: SPUStandardUpdaterController?
    private var cancellables: Set<AnyCancellable> = []

    override init() {
        super.init()

        guard Self.isSupported else { return }

        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        self.controller = controller
        isActive = true
        automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates

        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.canCheckForUpdates = value
            }
            .store(in: &cancellables)
    }

    // MARK: - API

    /// A user-initiated check (app menu, menu bar extra or Settings).
    func checkForUpdates() {
        controller?.updater.checkForUpdates()
    }

    /// Persists the "check automatically" choice through Sparkle.
    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        controller?.updater.automaticallyChecksForUpdates = enabled
        automaticallyChecksForUpdates = enabled
    }

    // MARK: - Availability

    /// Whether the running build can be updated: a Developer ID signature is
    /// what Sparkle compares when it installs, and it is also what the
    /// notarized release uses.
    private static var isSupported: Bool {
        let environment = ProcessInfo.processInfo.environment
        if environment["MW_DISABLE_UPDATES"] == "1" { return false }
        if environment["MW_ENABLE_UPDATES"] == "1" { return true }

        #if DEBUG
        return false
        #else
        return isDeveloperIDSigned
        #endif
    }

    private static var isDeveloperIDSigned: Bool {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode
        else { return false }

        var information: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &information
        ) == errSecSuccess,
            let info = information as? [String: Any],
            let certificates = info[kSecCodeInfoCertificates as String] as? [SecCertificate]
        else { return false }

        return certificates.contains { certificate in
            guard let summary = SecCertificateCopySubjectSummary(certificate) as String? else {
                return false
            }
            return summary.hasPrefix("Developer ID Application")
        }
    }
}

// MARK: - Feed override (development)

extension UpdaterController: SPUUpdaterDelegate {
    /// Lets the release smoke test point the app at a locally served appcast
    /// without rebuilding it.
    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        ProcessInfo.processInfo.environment["MW_UPDATE_FEED_URL"]
    }
}

// MARK: - App menu item

/// "Check for Updates…" for the application menu. A dedicated view is needed
/// because the disabled state follows Sparkle's `canCheckForUpdates`.
struct CheckForUpdatesMenuItem: View {
    @ObservedObject var updater: UpdaterController

    var body: some View {
        Button(L("update.check")) {
            updater.checkForUpdates()
        }
        .disabled(!updater.canCheckForUpdates)
    }
}
