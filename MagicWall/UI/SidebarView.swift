import MagicWallCore
import SwiftUI

/// Left sidebar: brand, navigation, search, quick actions and screen status.
///
/// Semi-transparent Apple-style material (see `SidebarMaterialView`), tinted
/// with the theme's `sidebarBackground` token and driven entirely by
/// `theme.active`.
struct SidebarView: View {
    @Binding var tab: AppTab
    let onImport: () -> Void
    let onShuffle: () -> Void

    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var viewModel: LibraryViewModel
    @EnvironmentObject private var engine: WallpaperEngine

    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
            searchField.padding(.top, 20)
            navigationList.padding(.top, 16)
            Spacer(minLength: 12)
            actionsSection
            screensSection.padding(.top, 16)
            settingsLink.padding(.top, 14)
        }
        .padding(.horizontal, 14)
        .padding(.top, 46)
        .padding(.bottom, 16)
        .frame(width: MagicWallLayout.sidebarWidth, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background {
            ZStack {
                SidebarMaterialView()
                theme.active.sidebarBackgroundColor
            }
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(theme.active.dividerColor)
                .frame(width: 1)
        }
    }

    // MARK: - Brand

    private var brand: some View {
        Button {
            select(.home)
        } label: {
            Text("MagicWall")
                .font(.system(size: 24, weight: .black, design: .rounded))
                .kerning(-0.6)
                .foregroundStyle(theme.active.textPrimaryColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L("sidebar.home.help"))
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSearchFocused ? theme.active.accentColor : theme.active.textTertiaryColor)

            TextField(L("sidebar.search.placeholder"), text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundStyle(theme.active.textPrimaryColor)
                .focused($isSearchFocused)

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.active.textTertiaryColor)
                }
                .buttonStyle(.plain)
                .help(L("sidebar.search.clear"))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            theme.active.surfaceColor,
            in: RoundedRectangle(cornerRadius: theme.active.controlRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: theme.active.controlRadius, style: .continuous)
                .strokeBorder(
                    isSearchFocused ? theme.active.accentColor.opacity(0.7) : theme.active.dividerColor,
                    lineWidth: 1
                )
        )
        .animation(.easeOut(duration: 0.12), value: isSearchFocused)
    }

    // MARK: - Navigation

    private var navigationList: some View {
        VStack(spacing: 2) {
            ForEach(AppTab.allCases) { item in
                SidebarNavRow(tab: item, isSelected: tab == item) {
                    select(item)
                }
            }
        }
    }

    private func select(_ item: AppTab) {
        viewModel.searchText = ""
        withAnimation(.easeOut(duration: 0.15)) { tab = item }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(spacing: 10) {
            Button(action: onImport) {
                HStack(spacing: 7) {
                    if viewModel.isImporting {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.7)
                            .frame(width: 12, height: 12)
                    } else {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                    }
                    Text(viewModel.isImporting ? L("common.importing") : L("common.import"))
                        .font(.system(size: 12.5, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .foregroundStyle(theme.active.accentTextColor)
                .background(theme.active.accentShapeStyle, in: Capsule())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityIdentifier("sidebar.import")
            .disabled(viewModel.isImporting)
            .keyboardShortcut("i", modifiers: .command)
            .help(L("sidebar.import.help"))

            HStack(spacing: 8) {
                SidebarIconButton(
                    systemImage: engine.isPaused ? "play.fill" : "pause.fill",
                    help: engine.isPaused ? L("sidebar.resume") : L("sidebar.pause")
                ) {
                    engine.isPaused.toggle()
                }

                SidebarIconButton(systemImage: "shuffle", help: L("sidebar.shuffle.help")) {
                    onShuffle()
                }
                .disabled(viewModel.videos.isEmpty)
                .opacity(viewModel.videos.isEmpty ? 0.4 : 1)

                moreMenu
                Spacer(minLength: 0)
            }
        }
    }

    private var moreMenu: some View {
        Menu {
            Toggle(L("playback.pause.wallpapers"), isOn: $engine.isPaused)
            Toggle(L("playback.pause.battery"), isOn: $engine.pauseOnBattery)
            Toggle(L("playback.pause.occluded"), isOn: $engine.pauseWhenOccluded)
            Divider()
            Button(L("common.importVideosEllipsis")) { onImport() }
            Button(L("common.randomWallpaper")) { onShuffle() }
            Button(L("sidebar.rebuildLibrary")) { viewModel.refresh() }
            if engine.hasActiveWallpaper {
                Divider()
                Button(L("common.stopAllWallpapers")) { engine.clearAll() }
            }
        } label: {
            SidebarIconChip(systemImage: "ellipsis")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L("sidebar.more.help"))
    }

    // MARK: - Settings

    private var settingsLink: some View {
        SettingsLink {
            HStack(spacing: 8) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12.5, weight: .semibold))
                Text(L("sidebar.settings"))
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(theme.active.textSecondaryColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                theme.active.buttonSecondaryBackgroundColor,
                in: RoundedRectangle(cornerRadius: theme.active.controlRadius, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: theme.active.controlRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("sidebar.settings")
        .help(L("sidebar.settings.help"))
    }

    // MARK: - Screens

    @ViewBuilder
    private var screensSection: some View {
        if !engine.statuses.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("sidebar.screens"))
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.2)
                    .foregroundStyle(theme.active.textTertiaryColor)

                ForEach(engine.statuses) { status in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(status.videoTitle == nil ? theme.active.textTertiaryColor : theme.active.liveBadgeBackgroundColor)
                            .frame(width: 6, height: 6)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(status.name)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(theme.active.textPrimaryColor)
                                .lineLimit(1)
                            Text(status.videoTitle ?? L("sidebar.noWallpaper"))
                                .font(.system(size: 10.5))
                                .foregroundStyle(theme.active.textTertiaryColor)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                }

                if engine.hasActiveWallpaper {
                    Button {
                        engine.clearAll()
                    } label: {
                        Text(L("common.stopAllWallpapers"))
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(theme.active.textSecondaryColor)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

// MARK: - Rows & small controls

/// One sidebar destination. Selected state is a soft rounded fill — never an
/// underline or gradient.
private struct SidebarNavRow: View {
    let tab: AppTab
    let isSelected: Bool
    let action: () -> Void

    @EnvironmentObject private var theme: ThemeStore
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? tab.selectedSymbol : tab.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 18, alignment: .center)
                    .foregroundStyle(isSelected ? theme.active.accentColor : theme.active.textSecondaryColor)

                Text(tab.title)
                    .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? theme.active.textPrimaryColor : theme.active.textSecondaryColor)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                isSelected
                    ? theme.active.accentColor.opacity(0.16)
                    : (isHovering ? theme.active.surfaceHoverColor : Color.clear),
                in: RoundedRectangle(cornerRadius: theme.active.controlRadius, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: theme.active.controlRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("sidebar.item.\(tab.rawValue)")
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }
}

/// Borderless circular icon chip used for the sidebar quick actions.
private struct SidebarIconChip: View {
    let systemImage: String

    @EnvironmentObject private var theme: ThemeStore
    @State private var isHovering = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(theme.active.textPrimaryColor)
            .frame(width: 32, height: 32)
            .background(
                isHovering ? theme.active.surfaceHoverColor : theme.active.buttonSecondaryBackgroundColor,
                in: Circle()
            )
            .contentShape(Circle())
            .onHover { isHovering = $0 }
    }
}

private struct SidebarIconButton: View {
    let systemImage: String
    var help: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SidebarIconChip(systemImage: systemImage)
        }
        .buttonStyle(PressableButtonStyle())
        .help(help ?? "")
    }
}
