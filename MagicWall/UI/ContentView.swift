import MagicWallCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var viewModel: LibraryViewModel
    @EnvironmentObject private var engine: WallpaperEngine

    @State private var sidebarSelection: String = "all"
    @State private var isDropTargeted = false
    @State private var showingNewCategory = false
    @State private var newCategoryName = ""

    private let columns = [GridItem(.adaptive(minimum: 240, maximum: 340), spacing: 18)]

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .overlay(alignment: .top) { banner }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted) { providers in
            Task { await handleDrop(providers) }
            return true
        }
        .alert("New VideoCategory", isPresented: $showingNewCategory) {
            TextField("Name", text: $newCategoryName)
            Button("Create") {
                viewModel.createCategory(named: newCategoryName)
                newCategoryName = ""
            }
            Button("Cancel", role: .cancel) { newCategoryName = "" }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $sidebarSelection) {
            Section("Library") {
                Label("All Videos", systemImage: "square.grid.2x2")
                    .tag("all")
                Label("Favorites", systemImage: "heart.fill")
                    .tag("favorites")
            }
            Section("Categories") {
                ForEach(viewModel.categories) { category in
                    Label(category.name, systemImage: "tag")
                        .tag(category.slug)
                        .contextMenu {
                            Button("Delete VideoCategory", role: .destructive) {
                                viewModel.deleteCategory(category)
                            }
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button {
                    showingNewCategory = true
                } label: {
                    Label("New VideoCategory", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(12)
        }
        .onChange(of: sidebarSelection) { _, newValue in
            sidebarSelectionChanged(to: newValue)
        }
        .frame(minWidth: 200)
    }

    private func sidebarSelectionChanged(to newValue: String) {
        switch newValue {
        case "all":
            viewModel.showsFavoritesOnly = false
            viewModel.selectedCategorySlug = nil
            viewModel.refresh()
        case "favorites":
            viewModel.showsFavoritesOnly = true
            viewModel.selectedCategorySlug = nil
            viewModel.refresh()
        default:
            viewModel.showsFavoritesOnly = false
            viewModel.selectedCategorySlug = newValue
            viewModel.refresh()
        }
    }

    // MARK: - Detail

    private var detail: some View {
        ScrollView {
            if viewModel.displayVideos.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                    ForEach(viewModel.displayVideos) { video in
                        card(for: video)
                    }
                }
                .padding(24)
            }
        }
        .searchable(text: $viewModel.searchText, placement: .toolbar, prompt: "Search videos")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.presentImportPanel()
                } label: {
                    Label("Import", systemImage: "plus")
                }
                .disabled(viewModel.isImporting)
                .help("Import videos (or drop files anywhere in the window)")
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    viewModel.applyRandomToAllScreens()
                } label: {
                    Label("Random Wallpaper", systemImage: "shuffle")
                }
                .disabled(viewModel.videos.isEmpty)
            }
        }
        .navigationTitle(navigationTitle)
    }

    private var navigationTitle: String {
        if viewModel.showsFavoritesOnly { return "Favorites" }
        if let slug = viewModel.selectedCategorySlug,
           let category = viewModel.categories.first(where: { $0.slug == slug }) {
            return category.name
        }
        return "All Videos"
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "film.stack")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text("No videos yet")
                .font(.title3.weight(.semibold))
            Text("Drop MP4/MOV files here or click + to import them.\nThen press play on a video to set it as your wallpaper.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 120)
    }

    private func card(for video: Video) -> some View {
        VideoCard(
            video: video,
            isFavorite: viewModel.favoriteIDs.contains(video.id),
            isApplied: engine.statuses.contains { $0.videoID == video.id },
            onApply: { viewModel.applyToAllScreens(video) },
            onToggleFavorite: { viewModel.toggleFavorite(video) }
        )
        .contextMenu {
            Button("Set as Wallpaper (All Screens)") {
                viewModel.applyToAllScreens(video)
            }
            if engine.statuses.count > 1 {
                Menu("Set on Screen") {
                    ForEach(engine.statuses) { status in
                        Button(status.name) {
                            apply(video: video, toScreenKey: status.id)
                        }
                    }
                }
            }
            Divider()
            Menu("Categories") {
                ForEach(viewModel.categories) { category in
                    let assigned = viewModel.categories(for: video).contains { $0.id == category.id }
                    Toggle(category.name, isOn: Binding(
                        get: { assigned },
                        set: { _ in viewModel.toggleCategory(category, for: video) }
                    ))
                }
            }
            Divider()
            Button(viewModel.favoriteIDs.contains(video.id) ? "Remove from Favorites" : "Add to Favorites") {
                viewModel.toggleFavorite(video)
            }
            Button("Delete", role: .destructive) {
                viewModel.delete(video)
            }
        }
    }

    private func apply(video: Video, toScreenKey screenKey: String) {
        guard let screen = NSScreen.screens.first(where: { $0.magicWallKey == screenKey }) else { return }
        engine.apply(video, to: screen)
        viewModel.statusMessage = "“\(video.title)” applied to \(screen.magicWallName)."
    }

    // MARK: - Banner

    @ViewBuilder
    private var banner: some View {
        if isDropTargeted {
            bannerLabel("Drop videos to import", icon: "arrow.down.circle.fill", color: .accentColor)
        } else if let error = viewModel.lastError {
            bannerLabel(error, icon: "exclamationmark.triangle.fill", color: .red)
        } else if let message = viewModel.statusMessage {
            bannerLabel(message, icon: "checkmark.circle.fill", color: .green)
                .task(id: message) {
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    if viewModel.statusMessage == message {
                        viewModel.statusMessage = nil
                    }
                }
        }
    }

    private func bannerLabel(_ text: String, icon: String, color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.callout)
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.4), lineWidth: 1))
            .padding(.top, 12)
            .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Drag & drop

    private func handleDrop(_ providers: [NSItemProvider]) async {
        var urls: [URL] = []
        for provider in providers {
            let item = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil)
            guard let data = item as? Data,
                  let string = String(data: data, encoding: .utf8),
                  let url = URL(string: string) else { continue }
            urls.append(url)
        }
        await viewModel.importVideos(urls)
    }
}
