import AppKit
import MagicWallCore
import SwiftUI
import UniformTypeIdentifiers

/// Root view of the library window.
///
/// Owns nothing but presentation state: the current tab, the previewed video,
/// drag & drop targeting and a cached map of video → category IDs (rebuilt only
/// when the library actually changes, never while scrolling).
struct ContentView: View {
    @EnvironmentObject private var viewModel: LibraryViewModel
    @EnvironmentObject private var engine: WallpaperEngine

    @State private var tab: AppTab = .home
    @State private var previewVideo: Video?
    @State private var isDropTargeted = false
    @State private var membership: [String: Set<Int64>] = [:]

    @State private var isNamingCategory = false
    @State private var newCategoryName = ""

    var body: some View {
        ZStack(alignment: .top) {
            MagicWallTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                MagicWallTopBar(
                    tab: $tab,
                    onImport: { viewModel.presentImportPanel() },
                    onShuffle: { viewModel.applyRandomToAllScreens() }
                )
                Divider().overlay(MagicWallTheme.stroke)
                content
            }

            overlays
        }
        .environment(\.libraryDidMutate, { rebuildMembership() })
        .frame(minWidth: 980, minHeight: 620)
        .preferredColorScheme(.dark)
        .toolbar { overflowToolbar }
        .task { rebuildMembership() }
        .onChange(of: viewModel.videos) { _, _ in rebuildMembership() }
        .onChange(of: viewModel.categories) { _, _ in rebuildMembership() }
        .onChange(of: tab) { _, newTab in
            if newTab == .library {
                viewModel.refresh()
            }
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted) { providers in
            Task { await handleDrop(providers) }
            return true
        }
        .alert("Nuova categoria", isPresented: $isNamingCategory) {
            TextField("Nome", text: $newCategoryName)
            Button("Crea") { createCategory() }
            Button("Annulla", role: .cancel) { newCategoryName = "" }
        } message: {
            Text("Raggruppa i tuoi wallpaper per tema, stile o luminosità.")
        }
    }

    // MARK: - Tab content

    @ViewBuilder
    private var content: some View {
        let query = viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        if !query.isEmpty {
            searchResults(query: query)
        } else {
            switch tab {
            case .home:
                HomeView(
                    videos: viewModel.videos,
                    membership: membership,
                    onOpen: open,
                    onNewCategory: beginCategoryCreation
                )
            case .explore:
                ExploreView(
                    videos: viewModel.videos,
                    membership: membership,
                    onOpen: open,
                    onNewCategory: beginCategoryCreation
                )
            case .library:
                LibraryView(
                    videos: viewModel.videos,
                    membership: membership,
                    onOpen: open,
                    onNewCategory: beginCategoryCreation
                )
            case .favorites:
                FavoritesView(
                    videos: viewModel.videos.filter { viewModel.favoriteIDs.contains($0.id) },
                    membership: membership,
                    onOpen: open,
                    onNewCategory: beginCategoryCreation
                )
            }
        }
    }

    private func searchResults(query: String) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                SectionHeader(
                    title: "Risultati per “\(query)”",
                    subtitle: "\(viewModel.displayVideos.count) video"
                )
                .padding(.horizontal, MagicWallTheme.gutter)

                if viewModel.displayVideos.isEmpty {
                    MessageState(
                        icon: "magnifyingglass",
                        title: "Nessun risultato",
                        message: "Prova con un altro titolo oppure importa nuovi video."
                    )
                } else {
                    VideoGridView(
                        videos: viewModel.displayVideos,
                        membership: membership,
                        onOpen: open,
                        onNewCategory: beginCategoryCreation
                    )
                    .padding(.horizontal, MagicWallTheme.gutter)
                }
            }
            .padding(.top, 26)
            .padding(.bottom, 48)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Overlays

    @ViewBuilder
    private var overlays: some View {
        VStack(spacing: 10) {
            if isDropTargeted {
                banner(
                    text: "Rilascia i video per importarli",
                    icon: "arrow.down.circle.fill",
                    tint: MagicWallTheme.accent,
                    dismiss: nil
                )
            } else if let error = viewModel.lastError {
                banner(
                    text: error,
                    icon: "exclamationmark.triangle.fill",
                    tint: Color(red: 1, green: 0.35, blue: 0.35),
                    dismiss: { viewModel.lastError = nil }
                )
            } else if let message = viewModel.statusMessage {
                banner(text: message, icon: "checkmark.circle.fill", tint: MagicWallTheme.live, dismiss: nil)
                    .task(id: message) {
                        try? await Task.sleep(nanoseconds: 4_000_000_000)
                        if viewModel.statusMessage == message {
                            withAnimation(.easeOut(duration: 0.15)) { viewModel.statusMessage = nil }
                        }
                    }
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 66)
        .animation(.easeOut(duration: 0.15), value: viewModel.statusMessage)
        .animation(.easeOut(duration: 0.15), value: isDropTargeted)

        dropHighlight

        if let video = previewVideo {
            VideoPreviewView(
                video: video,
                onNewCategory: beginCategoryCreation,
                onClose: { previewVideo = nil }
            )
            .transition(.opacity)
            .zIndex(2)
        }
    }

    private var dropHighlight: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(
                MagicWallTheme.accent,
                style: StrokeStyle(lineWidth: 3, dash: [10, 7])
            )
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(MagicWallTheme.accent.opacity(0.10))
            )
            .padding(10)
            .opacity(isDropTargeted ? 1 : 0)
            .allowsHitTesting(false)
    }

    private func banner(text: String, icon: String, tint: Color, dismiss: (() -> Void)?) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)

            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(.white.opacity(0.95))
                .lineLimit(2)

            if let dismiss {
                Button {
                    withAnimation(.easeOut(duration: 0.12)) { dismiss() }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Chiudi")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(MagicWallTheme.surfaceHigh, in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var overflowToolbar: some ToolbarContent {
        // Keeps an (invisible) NSToolbar on the window and groups secondary
        // actions that would crowd the custom top bar.
        ToolbarItem(placement: .automatic) {
            Menu {
                Toggle("Pausa wallpaper", isOn: $engine.isPaused)
                Toggle("Pausa su batteria", isOn: $engine.pauseOnBattery)
                Toggle("Pausa con desktop nascosto", isOn: $engine.pauseWhenOccluded)
                Divider()
                Button("Importa video…") { viewModel.presentImportPanel() }
                Button("Wallpaper casuale") { viewModel.applyRandomToAllScreens() }
                Button("Nuova categoria…") { beginCategoryCreation() }
                Button("Ricostruisci libreria") { viewModel.refresh() }
                if engine.hasActiveWallpaper {
                    Divider()
                    Button("Ferma tutti i wallpaper") { engine.clearAll() }
                }
                Divider()
                ForEach(engine.statuses) { status in
                    Text(status.videoTitle.map { "\(status.name): \($0)" } ?? "\(status.name): nessun wallpaper")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Altre azioni")
        }
    }

    // MARK: - Actions

    private func open(_ video: Video) {
        withAnimation(.easeOut(duration: 0.15)) { previewVideo = video }
    }

    private func beginCategoryCreation() {
        newCategoryName = ""
        isNamingCategory = true
    }

    private func createCategory() {
        let name = newCategoryName
        newCategoryName = ""
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        viewModel.createCategory(named: name)
        rebuildMembership()
    }

    /// One pass over the library keeps category lookups O(1) everywhere else.
    private func rebuildMembership() {
        var map: [String: Set<Int64>] = [:]
        for video in viewModel.videos {
            let ids = Set(viewModel.categories(for: video).compactMap(\.id))
            if !ids.isEmpty {
                map[video.id] = ids
            }
        }
        membership = map
    }

    // MARK: - Drag & drop

    private func handleDrop(_ providers: [NSItemProvider]) async {
        var urls: [URL] = []
        for provider in providers {
            if let url = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) as? URL {
                urls.append(url)
                continue
            }
            if let data = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) as? Data,
               let string = String(data: data, encoding: .utf8),
               let url = URL(string: string) {
                urls.append(url)
            }
        }
        guard !urls.isEmpty else { return }
        await viewModel.importVideos(urls)
    }
}
