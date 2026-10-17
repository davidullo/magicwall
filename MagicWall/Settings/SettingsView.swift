import AppKit
import MagicWallCore
import SwiftUI

/// The app's Settings window, split into three tabs:
///
/// - **General** — playback policy, launch at login, library stats, language
///   and maintenance.
/// - **Theme** — the live theme editor (see ``ThemeEditorView``).
/// - **About** — version and a one-liner about the app.
///
/// Every user-facing string goes through the `L(...)` lookup so the whole
/// window re-localizes when the interface language changes.
struct SettingsView: View {
    @EnvironmentObject private var themeStore: ThemeStore

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label(L("settings.tab.general"), systemImage: "gearshape") }

            ThemeEditorView()
                .tabItem { Label(L("settings.tab.theme"), systemImage: "paintpalette") }

            AboutSettingsView()
                .tabItem { Label(L("settings.tab.about"), systemImage: "info.circle") }
        }
        .frame(width: 720, height: 560)
        .tint(themeStore.active.accentColor)
    }
}

// MARK: - General

/// Everything that used to live in the single-sheet settings, now grouped in a
/// scrollable, grouped form.
struct GeneralSettingsView: View {
    @EnvironmentObject private var viewModel: LibraryViewModel
    @EnvironmentObject private var engine: WallpaperEngine
    @EnvironmentObject private var loginItemService: LoginItemService
    @EnvironmentObject private var localization: LocalizationManager

    var body: some View {
        Form {
            playbackSection
            startupSection
            librarySection
            languageSection
            maintenanceSection
        }
        .formStyle(.grouped)
    }

    // MARK: Playback

    private var playbackSection: some View {
        Section {
            Toggle(L("settings.playback.pauseWallpaper"), isOn: Binding(
                get: { engine.isPaused },
                set: { engine.isPaused = $0 }
            ))
            Toggle(L("settings.playback.pauseOnBattery"), isOn: $engine.pauseOnBattery)
            Toggle(L("settings.playback.pauseOccluded"), isOn: $engine.pauseWhenOccluded)
            Toggle(L("settings.playback.pauseLowPower"), isOn: $engine.pauseOnLowPower)
            Toggle(L("settings.playback.pauseLocked"), isOn: $engine.pauseWhenLocked)
            Toggle(L("settings.playback.pauseThermal"), isOn: $engine.pauseOnThermalPressure)

            if !engine.pauseReasons.isEmpty {
                Text(L("settings.playback.paused", engine.pauseReasons.map { L("engine.reason.\($0.rawValue)") }.joined(separator: ", ")))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text(L("settings.playback.title"))
        }
    }

    // MARK: Startup

    private var startupSection: some View {
        Section {
            Toggle(L("settings.startup.launchAtLogin"), isOn: Binding(
                get: { loginItemService.isEnabled },
                set: { loginItemService.setEnabled($0) }
            ))

            if loginItemService.requiresApproval {
                Text(L("settings.startup.requiresApproval"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let error = loginItemService.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(L("settings.startup.openSystemSettings")) {
                loginItemService.openSystemSettingsLoginItems()
            }
        } header: {
            Text(L("settings.startup.title"))
        }
    }

    // MARK: Library

    private var librarySection: some View {
        Section {
            LabeledContent {
                Text("\(viewModel.videos.count)")
            } label: {
                Text(L("settings.library.videos"))
            }

            LabeledContent {
                Text(viewModel.librarySizeLabel)
            } label: {
                Text(L("settings.library.size"))
            }

            LabeledContent {
                Button(L("settings.library.reveal")) {
                    NSWorkspace.shared.activateFileViewerSelecting([AppPaths.libraryRoot])
                }
            } label: {
                Text(L("settings.library.location"))
            }

            Text(AppPaths.libraryRoot.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        } header: {
            Text(L("settings.library.title"))
        }
    }

    // MARK: Language

    private var languageSection: some View {
        Section {
            Picker(selection: Binding(
                get: { localization.language },
                set: { localization.setLanguage($0) }
            )) {
                ForEach(AppLanguage.allCases) { language in
                    Text(L("settings.language.option.\(language.rawValue)")).tag(language)
                }
            } label: {
                Text(L("settings.language.picker"))
            }
            .pickerStyle(.menu)

            Text(L("settings.language.hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text(L("settings.language"))
        }
    }

    // MARK: Maintenance

    private var maintenanceSection: some View {
        Section {
            Button(L("common.stopAllWallpapers")) {
                engine.clearAll()
            }
            .disabled(!engine.hasActiveWallpaper)
        } header: {
            Text(L("settings.maintenance.title"))
        }
    }
}

// MARK: - About

struct AboutSettingsView: View {
    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Text("\(Bundle.main.shortVersion) (\(Bundle.main.buildNumber))")
                } label: {
                    Text(L("settings.about.version"))
                }
                Text(L("settings.about.blurb"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("MagicWall")
            }
        }
        .formStyle(.grouped)
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
