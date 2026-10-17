import MagicWallCore
import SwiftUI

/// Custom dark chrome: brand, four sections, search field and quick actions.
struct MagicWallTopBar: View {
    @Binding var tab: AppTab
    let onImport: () -> Void
    let onShuffle: () -> Void

    @EnvironmentObject private var viewModel: LibraryViewModel
    @EnvironmentObject private var engine: WallpaperEngine

    @FocusState private var isSearchFocused: Bool

    var body: some View {
        HStack(spacing: 20) {
            brand
            navigation
            Spacer(minLength: 16)
            searchField
            actions
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 11)
        .background(MagicWallTheme.background)
    }

    // MARK: - Brand

    private var brand: some View {
        Button {
            tab = .home
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "sparkles.tv")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(MagicWallTheme.accentGradient)
                Text("MagicWall")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .help("Torna alla Home")
    }

    // MARK: - Tabs

    private var navigation: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases) { item in
                NavTabButton(tab: item, isSelected: tab == item) {
                    withAnimation(.easeOut(duration: 0.15)) { tab = item }
                }
            }
        }
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSearchFocused ? .white : .secondary)

            TextField("Cerca nella libreria", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($isSearchFocused)
                .frame(width: 168)

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Cancella ricerca")
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(MagicWallTheme.surfaceHigh, in: Capsule())
        .overlay(
            Capsule().strokeBorder(
                isSearchFocused ? MagicWallTheme.accent.opacity(0.75) : MagicWallTheme.stroke,
                lineWidth: 1
            )
        )
        .animation(.easeOut(duration: 0.12), value: isSearchFocused)
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: 8) {
            screensIndicator

            CircleIconButton(
                systemImage: engine.isPaused ? "play.fill" : "pause.fill",
                size: 32,
                help: engine.isPaused ? "Riprendi i wallpaper" : "Metti in pausa i wallpaper"
            ) {
                engine.isPaused.toggle()
            }

            CircleIconButton(
                systemImage: "shuffle",
                size: 32,
                help: "Wallpaper casuale su tutti gli schermi"
            ) {
                onShuffle()
            }
            .disabled(viewModel.videos.isEmpty)
            .opacity(viewModel.videos.isEmpty ? 0.4 : 1)

            importButton
        }
    }

    private var importButton: some View {
        Button(action: onImport) {
            HStack(spacing: 6) {
                if viewModel.isImporting {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                        .frame(width: 12, height: 12)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                }
                Text(viewModel.isImporting ? "Importazione…" : "Importa")
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(.white)
            .background(MagicWallTheme.accentGradient, in: Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(viewModel.isImporting)
        .help("Importa video MP4/MOV (oppure trascinali nella finestra)")
    }

    /// Compact monitor chip: how many screens are covered and which video is live.
    @ViewBuilder
    private var screensIndicator: some View {
        if !engine.statuses.isEmpty {
            Menu {
                ForEach(engine.statuses) { status in
                    Text(status.videoTitle.map { "\(status.name) — \($0)" } ?? "\(status.name) — nessun wallpaper")
                }
                Divider()
                if engine.hasActiveWallpaper {
                    Button("Ferma tutti i wallpaper") { engine.clearAll() }
                }
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(engine.hasActiveWallpaper ? MagicWallTheme.live : Color.white.opacity(0.35))
                        .frame(width: 7, height: 7)
                    Text("\(engine.statuses.count) scherm\(engine.statuses.count == 1 ? "o" : "i")")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(MagicWallTheme.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(MagicWallTheme.stroke, lineWidth: 1))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }
}

/// One tab of the custom navigation bar.
private struct NavTabButton: View {
    let tab: AppTab
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: tab.symbol)
                        .font(.system(size: 11, weight: .semibold))
                    Text(tab.title)
                        .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                }
                .foregroundStyle(isSelected ? Color.white : Color.white.opacity(isHovering ? 0.85 : 0.6))

                Capsule()
                    .fill(MagicWallTheme.accentGradient)
                    .frame(height: 2)
                    .opacity(isSelected ? 1 : 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }
}
