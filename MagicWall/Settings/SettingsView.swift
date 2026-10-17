import AppKit
import MagicWallCore
import SwiftUI

/// The app's Settings window.
///
/// A two-pane layout replaces the old system `TabView` + `Form(.grouped)`
/// combination: the sidebar mirrors the app's navigation, while the content is
/// built from cards that read every colour from the active theme. The standard
/// grouped form is intentionally avoided because it ignores custom themes and
/// falls back to a white system background.
struct SettingsView: View {
    @EnvironmentObject private var themeStore: ThemeStore

    @State private var destination: SettingsDestination = .general

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Rectangle()
                .fill(themeStore.active.dividerColor)
                .frame(width: 1)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 820, height: 620)
        .background(themeStore.active.windowBackgroundColor)
        .tint(themeStore.active.accentColor)
        .preferredColorScheme(themeStore.active.preferredColorScheme)
        .background(SettingsWindowConfigurator(theme: themeStore.active))
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(themeStore.active.accentColor.opacity(0.16))

                    Image(systemName: "sparkles.tv")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(themeStore.active.accentColor)
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 1) {
                    Text("MagicWall")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(themeStore.active.textPrimaryColor)

                    Text(L("settings.title"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(themeStore.active.textTertiaryColor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 22)

            VStack(spacing: 4) {
                ForEach(SettingsDestination.allCases) { item in
                    SettingsNavItem(
                        identifier: "settings.nav.\(item.rawValue)",
                        title: item.title,
                        systemImage: item.symbol,
                        isSelected: destination == item
                    ) {
                        destination = item
                    }
                }
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 0)

            Text("v\(Bundle.main.shortVersion)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(themeStore.active.textTertiaryColor)
                .padding(.horizontal, 18)
                .padding(.bottom, 16)
        }
        .frame(width: 205)
        .frame(maxHeight: .infinity)
        .background(themeStore.active.sidebarBackgroundColor)
    }

    @ViewBuilder
    private var content: some View {
        switch destination {
        case .general:
            GeneralSettingsView()
        case .theme:
            ThemeEditorView()
        case .about:
            AboutSettingsView()
        }
    }
}

private enum SettingsDestination: String, CaseIterable, Identifiable {
    case general
    case theme
    case about

    var id: String { rawValue }

    @MainActor
    var title: String {
        switch self {
        case .general: return L("settings.tab.general")
        case .theme: return L("settings.tab.theme")
        case .about: return L("settings.tab.about")
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .theme: return "paintpalette"
        case .about: return "info.circle"
        }
    }
}

// MARK: - General

/// Playback, login item, library and maintenance in four themed cards. The
/// automatic pause conditions live behind a disclosure so the page opens with
/// one clear primary setting instead of six equal toggles.
struct GeneralSettingsView: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var viewModel: LibraryViewModel
    @EnvironmentObject private var engine: WallpaperEngine
    @EnvironmentObject private var loginItemService: LoginItemService
    @EnvironmentObject private var localization: LocalizationManager
    @EnvironmentObject private var starterService: StarterWallpaperService

    @State private var showsAutomaticPause = false

    var body: some View {
        SettingsPage(
            title: L("settings.tab.general"),
            subtitle: L("settings.general.subtitle")
        ) {
            playbackCard
            applicationCard
            libraryCard
            starterCard
            maintenanceCard
        }
    }

    // MARK: Playback

    private var playbackCard: some View {
        SettingsCard(title: L("settings.playback.title"), systemImage: "play.circle") {
            SettingsToggleRow(
                title: L("settings.playback.pauseWallpaper"),
                isOn: Binding(
                    get: { engine.isPaused },
                    set: { engine.isPaused = $0 }
                )
            )

            if !engine.pauseReasons.isEmpty {
                SettingsDivider()

                HStack(spacing: 7) {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.active.textTertiaryColor)

                    Text(L(
                        "settings.playback.paused",
                        engine.pauseReasons.map { L("engine.reason.\($0.rawValue)") }.joined(separator: ", ")
                    ))
                    .font(.system(size: 11))
                    .foregroundStyle(theme.active.textSecondaryColor)
                    .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 9)
            }

            SettingsDivider()

            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    showsAutomaticPause.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11.5, weight: .semibold))

                    Text(L("settings.playback.automatic"))
                        .font(.system(size: 12.5, weight: .medium))

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(showsAutomaticPause ? 0 : -90))
                }
                .foregroundStyle(theme.active.textPrimaryColor)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings.playback.automatic")

            if showsAutomaticPause {
                SettingsDivider()

                VStack(spacing: 0) {
                    SettingsToggleRow(
                        title: L("settings.playback.pauseOnBattery"),
                        isOn: $engine.pauseOnBattery
                    )
                    SettingsDivider()
                    SettingsToggleRow(
                        title: L("settings.playback.pauseOccluded"),
                        isOn: $engine.pauseWhenOccluded
                    )
                    SettingsDivider()
                    SettingsToggleRow(
                        title: L("settings.playback.pauseLowPower"),
                        isOn: $engine.pauseOnLowPower
                    )
                    SettingsDivider()
                    SettingsToggleRow(
                        title: L("settings.playback.pauseLocked"),
                        isOn: $engine.pauseWhenLocked
                    )
                    SettingsDivider()
                    SettingsToggleRow(
                        title: L("settings.playback.pauseThermal"),
                        isOn: $engine.pauseOnThermalPressure
                    )
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: Application

    private var applicationCard: some View {
        SettingsCard(title: L("settings.application.title"), systemImage: "macwindow") {
            SettingsToggleRow(
                title: L("settings.startup.launchAtLogin"),
                subtitle: loginItemService.requiresApproval ? L("settings.startup.requiresApproval") : nil,
                isOn: Binding(
                    get: { loginItemService.isEnabled },
                    set: { loginItemService.setEnabled($0) }
                )
            )

            if loginItemService.requiresApproval {
                SettingsDivider()

                HStack {
                    Spacer(minLength: 0)

                    SettingsActionButton(
                        title: L("settings.startup.openSystemSettings"),
                        systemImage: "arrow.up.right.square"
                    ) {
                        loginItemService.openSystemSettingsLoginItems()
                    }
                }
                .padding(.vertical, 7)
            }

            if let error = loginItemService.lastError {
                SettingsDivider()

                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10.5, weight: .semibold))

                    Text(error)
                        .font(.system(size: 11))
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }
                .foregroundStyle(theme.active.dangerColor)
                .padding(.vertical, 8)
            }

            SettingsDivider()

            SettingsRow(
                L("settings.language.picker"),
                subtitle: L("settings.language.hint")
            ) {
                Picker(
                    selection: Binding(
                        get: { localization.language },
                        set: { localization.setLanguage($0) }
                    )
                ) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(L("settings.language.option.\(language.rawValue)")).tag(language)
                    }
                } label: {
                    Text(L("settings.language.picker"))
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 145)
            }
        }
    }

    // MARK: Library

    private var libraryCard: some View {
        SettingsCard(title: L("settings.library.title"), systemImage: "internaldrive") {
            SettingsValueRow(
                title: L("settings.library.videos"),
                value: "\(viewModel.videos.count)"
            )

            SettingsDivider()

            SettingsValueRow(
                title: L("settings.library.size"),
                value: viewModel.librarySizeLabel
            )

            SettingsDivider()

            SettingsRow(
                L("settings.library.location"),
                subtitle: AppPaths.libraryRoot.path
            ) {
                SettingsActionButton(
                    title: L("settings.library.reveal"),
                    systemImage: "folder"
                ) {
                    NSWorkspace.shared.activateFileViewerSelecting([AppPaths.libraryRoot])
                }
            }
        }
    }

    // MARK: Starter wallpapers

    private var starterCard: some View {
        SettingsCard(title: L("starter.section.title"), systemImage: "sparkles.tv") {
            SettingsRow(starterStatusTitle, subtitle: L("starter.settings.hint")) {
                starterAction
            }

            if case .downloading(let completed, let total, let downloaded, let totalBytes) = starterService.status {
                SettingsDivider()

                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: Double(completed), total: Double(max(total, 1)))
                        .tint(theme.active.accentColor)

                    Text(L(
                        "starter.download.progress",
                        completed,
                        total,
                        byteLabel(downloaded),
                        byteLabel(totalBytes)
                    ))
                    .font(.system(size: 11))
                    .foregroundStyle(theme.active.textSecondaryColor)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 9)
            }

            if case .failed(let message) = starterService.status {
                SettingsDivider()

                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10.5, weight: .semibold))

                    Text(L("starter.download.failed", message))
                        .font(.system(size: 11))
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }
                .foregroundStyle(theme.active.dangerColor)
                .padding(.vertical, 8)
            }
        }
    }

    private var starterStatusTitle: String {
        switch starterService.status {
        case .available:
            return starterService.hasBeenOffered
                ? L("starter.state.dismissed")
                : L("starter.state.available")
        case .downloading:
            return L("starter.state.downloading")
        case .installed:
            return L("starter.state.installed")
        case .partial:
            return L("starter.state.partial")
        case .failed:
            return L("starter.state.failed")
        }
    }

    @ViewBuilder
    private var starterAction: some View {
        switch starterService.status {
        case .available, .failed:
            SettingsActionButton(
                title: L("starter.action.download"),
                systemImage: "arrow.down.circle",
                kind: .primary
            ) {
                Task { await starterService.downloadAll() }
            }
            .accessibilityIdentifier("settings.starter.action")

        case .downloading:
            SettingsActionButton(
                title: L("starter.download.cancel"),
                systemImage: "xmark"
            ) {
                starterService.cancel()
            }
            .accessibilityIdentifier("settings.starter.action")

        case .installed:
            removeStarterButton(identifier: "settings.starter.action")

        case .partial:
            HStack(spacing: 8) {
                SettingsActionButton(
                    title: L("starter.action.download"),
                    systemImage: "arrow.down.circle"
                ) {
                    Task { await starterService.downloadAll() }
                }
                .accessibilityIdentifier("settings.starter.action")

                removeStarterButton(identifier: "settings.starter.remove")
            }
        }
    }

    private func removeStarterButton(identifier: String) -> some View {
        SettingsActionButton(
            title: L("starter.action.remove"),
            systemImage: "trash",
            kind: .destructive
        ) {
            for id in starterService.installedVideoIDs() {
                guard let video = try? viewModel.repository.video(id: id) else { continue }
                viewModel.delete(video)
            }
            starterService.refreshStatus()
        }
        .accessibilityIdentifier(identifier)
    }

    private func byteLabel(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // MARK: Maintenance

    private var maintenanceCard: some View {
        SettingsCard(title: L("settings.maintenance.title"), systemImage: "wrench.and.screwdriver") {
            SettingsRow(
                L("settings.maintenance.activeWallpapers"),
                subtitle: L("settings.maintenance.hint")
            ) {
                SettingsActionButton(
                    title: L("common.stopAllWallpapers"),
                    systemImage: "stop.fill",
                    kind: .destructive,
                    isEnabled: engine.hasActiveWallpaper
                ) {
                    engine.clearAll()
                }
            }
        }
    }
}

// MARK: - About

struct AboutSettingsView: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var updater: UpdaterController

    var body: some View {
        SettingsPage(title: L("settings.tab.about")) {
            SettingsCard {
                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(theme.active.accentColor.opacity(0.14))
                            .frame(width: 72, height: 72)

                        Image(systemName: "sparkles.tv")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(theme.active.accentColor)
                    }

                    VStack(spacing: 4) {
                        Text("MagicWall")
                            .font(.system(size: 20, weight: theme.active.titleFontWeight, design: .rounded))
                            .foregroundStyle(theme.active.textPrimaryColor)

                        Text("\(Bundle.main.shortVersion) (\(Bundle.main.buildNumber))")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(theme.active.textTertiaryColor)
                    }

                    Text(L("settings.about.blurb"))
                        .font(.system(size: 12.5))
                        .foregroundStyle(theme.active.textSecondaryColor)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 440)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .padding(.horizontal, 20)
            }

            updatesCard
        }
    }

    /// Sparkle controls. Hidden for development builds: the updater is only
    /// started for Developer ID-signed releases (see `UpdaterController`).
    @ViewBuilder
    private var updatesCard: some View {
        if updater.isActive {
            SettingsCard(title: L("settings.updates.title"), systemImage: "arrow.triangle.2.circlepath") {
                SettingsToggleRow(
                    title: L("settings.updates.automatic"),
                    subtitle: L("settings.updates.hint"),
                    isOn: Binding(
                        get: { updater.automaticallyChecksForUpdates },
                        set: { updater.setAutomaticallyChecksForUpdates($0) }
                    )
                )

                SettingsDivider()

                HStack {
                    Spacer(minLength: 0)

                    SettingsActionButton(
                        title: L("update.check"),
                        systemImage: "arrow.triangle.2.circlepath",
                        isEnabled: updater.canCheckForUpdates
                    ) {
                        updater.checkForUpdates()
                    }
                    .accessibilityIdentifier("settings.about.checkUpdates")
                }
                .padding(.vertical, 7)
            }
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
