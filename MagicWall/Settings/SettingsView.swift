import AppKit
import MagicWallCore
import SwiftUI

/// The app's Settings window, grouped into playback, startup, library,
/// maintenance and about sections. Intentionally capped at 540×420.
struct SettingsView: View {
    @EnvironmentObject private var viewModel: LibraryViewModel
    @EnvironmentObject private var engine: WallpaperEngine
    @EnvironmentObject private var loginItemService: LoginItemService

    var body: some View {
        Form {
            playbackSection
            startupSection
            librarySection
            maintenanceSection
            aboutSection
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 420)
    }

    // MARK: - Playback

    private var playbackSection: some View {
        Section("Riproduzione") {
            Toggle("Pausa wallpaper", isOn: Binding(
                get: { engine.isPaused },
                set: { engine.isPaused = $0 }
            ))
            Toggle("Pausa su batteria", isOn: $engine.pauseOnBattery)
            Toggle("Pausa con desktop nascosto", isOn: $engine.pauseWhenOccluded)
            Toggle("Pausa in risparmio energetico", isOn: $engine.pauseOnLowPower)
            Toggle("Pausa a schermo bloccato", isOn: $engine.pauseWhenLocked)
            Toggle("Pausa con pressione termica", isOn: $engine.pauseOnThermalPressure)

            if !engine.pauseReasons.isEmpty {
                Text("In pausa: \(engine.pauseReasons.map(Self.italianLabel(for:)).joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private static func italianLabel(for reason: PlaybackPolicy.Reason) -> String {
        switch reason {
        case .userPaused: return "pausa manuale"
        case .onBattery: return "alimentazione a batteria"
        case .lowPowerMode: return "risparmio energetico"
        case .thermalPressure: return "pressione termica"
        case .screenLocked: return "schermo bloccato"
        case .displaysAsleep: return "display spenti"
        case .systemAsleep: return "sistema in stop"
        case .sessionInactive: return "sessione inattiva"
        case .desktopOccluded: return "desktop nascosto"
        }
    }

    // MARK: - Startup

    private var startupSection: some View {
        Section("Avvio") {
            Toggle("Avvia MagicWall al login", isOn: Binding(
                get: { loginItemService.isEnabled },
                set: { loginItemService.setEnabled($0) }
            ))

            if loginItemService.requiresApproval {
                Text("Elemento di login registrato: richiede l’approvazione in Impostazioni di Sistema.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = loginItemService.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("Apri Impostazioni di Sistema → Login Items") {
                loginItemService.openSystemSettingsLoginItems()
            }
        }
    }

    // MARK: - Library

    private var librarySection: some View {
        Section("Libreria") {
            LabeledContent("Video", value: "\(viewModel.videos.count)")
            LabeledContent("Dimensione", value: viewModel.librarySizeLabel)

            LabeledContent("Percorso") {
                Button("Mostra nel Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([AppPaths.libraryRoot])
                }
            }
            Text(AppPaths.libraryRoot.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    // MARK: - Maintenance

    private var maintenanceSection: some View {
        Section("Manutenzione") {
            Button("Ferma tutti i wallpaper") {
                engine.clearAll()
            }
            .disabled(!engine.hasActiveWallpaper)
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section("Informazioni") {
            LabeledContent("Versione", value: "\(Bundle.main.shortVersion) (\(Bundle.main.buildNumber))")
            Text("MagicWall — wallpaper video locali per macOS. Nessun servizio cloud: i tuoi video restano sul Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private extension Bundle {
    var shortVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0"
    }
    var buildNumber: String {
        (infoDictionary?["CFBundleVersion"] as? String) ?? "0"
    }
}
