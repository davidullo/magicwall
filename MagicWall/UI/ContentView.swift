import AppKit
import MagicWallCore
import SwiftUI
import UniformTypeIdentifiers

/// Root view of the library window: a translucent sidebar plus the detail area.
///
/// Owns nothing but presentation state: the current tab, the previewed video,
/// drag & drop targeting and a cached map of video → category IDs (rebuilt only
/// when the library actually changes, never while scrolling).
struct ContentView: View {
    @EnvironmentObject private var viewModel: LibraryViewModel
    @EnvironmentObject private var engine: WallpaperEngine
    @EnvironmentObject private var theme: ThemeStore

    @State private var tab: AppTab = .home
    @State private var previewVideo: Video?
    @State private var isDropTargeted = false
    @State private var membership: [String: Set<Int64>] = [:]

    @State private var isNamingCategory = false
    @State private var newCategoryName = ""

    @State private var renamingVideo: Video?
    @State private var renameText = ""

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                SidebarView(
                    tab: $tab,
                    onImport: { viewModel.presentImportPanel() },
                    onShuffle: { viewModel.applyRandomToAllScreens() }
                )

                detail
            }
            .frame(minWidth: 980, minHeight: 620)
            .background(theme.active.windowBackgroundColor)
            .background(WindowChromeConfigurator())
            .ignoresSafeArea()

            // The preview floats above the whole window — sidebar included — so
            // it can never linger behind the user while they navigate beneath it.
            if let video = previewVideo {
                VideoPreviewView(
                    video: video,
                    onNewCategory: beginCategoryCreation,
                    onRename: beginRenaming,
                    onClose: {
                        withAnimation(.easeOut(duration: 0.15)) { previewVideo = nil }
                    }
                )
                .ignoresSafeArea()
                .transition(.opacity)
                .zIndex(3)
            }
        }
        .environment(\.libraryDidMutate, { rebuildMembership() })
        .preferredColorScheme(theme.active.preferredColorScheme)
        .task { rebuildMembership() }
        .onChange(of: viewModel.videos) { _, _ in rebuildMembership() }
        .onChange(of: viewModel.categories) { _, _ in rebuildMembership() }
        .onChange(of: tab) { _, newTab in
            if previewVideo != nil {
                withAnimation(.easeOut(duration: 0.15)) { previewVideo = nil }
            }
            if newTab == .library {
                viewModel.refresh()
            }
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted) { providers in
            Task { await handleDrop(providers) }
            return true
        }
        .alert(L("category.new"), isPresented: $isNamingCategory) {
            TextField(L("category.nameField"), text: $newCategoryName)
            Button(L("category.create")) { createCategory() }
            Button(L("common.cancel"), role: .cancel) { newCategoryName = "" }
        } message: {
            Text(L("category.new.message"))
        }
        .alert(L("video.rename.title"), isPresented: isRenamingVideoPresented) {
            TextField(L("video.rename.field"), text: $renameText)
                .accessibilityIdentifier("rename.field")
            Button(L("common.save")) { commitRename() }
                .accessibilityIdentifier("rename.save")
            Button(L("common.cancel"), role: .cancel) {
                renamingVideo = nil
                renameText = ""
            }
            .accessibilityIdentifier("rename.cancel")
        } message: {
            Text(L("video.rename.message"))
        }
    }

    // MARK: - Detail

    private var detail: some View {
        ZStack(alignment: .top) {
            content
            overlays
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.active.windowBackgroundColor)
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
                    onNewCategory: beginCategoryCreation,
                    onRename: beginRenaming
                )
            case .explore:
                ExploreView(
                    videos: viewModel.videos,
                    membership: membership,
                    onOpen: open,
                    onNewCategory: beginCategoryCreation,
                    onRename: beginRenaming
                )
            case .library:
                LibraryView(
                    videos: viewModel.videos,
                    membership: membership,
                    onOpen: open,
                    onNewCategory: beginCategoryCreation,
                    onRename: beginRenaming
                )
            case .favorites:
                FavoritesView(
                    videos: viewModel.videos.filter { viewModel.favoriteIDs.contains($0.id) },
                    membership: membership,
                    onOpen: open,
                    onNewCategory: beginCategoryCreation,
                    onRename: beginRenaming
                )
            }
        }
    }

    private func searchResults(query: String) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                SectionHeader(
                    title: L("search.results", query),
                    subtitle: videoCountLabel(viewModel.displayVideos.count)
                )
                .padding(.horizontal, MagicWallLayout.gutter)

                if viewModel.displayVideos.isEmpty {
                    MessageState(
                        icon: "magnifyingglass",
                        title: L("search.empty.title"),
                        message: L("search.empty.message")
                    )
                } else {
                    VideoGridView(
                        videos: viewModel.displayVideos,
                        membership: membership,
                        onOpen: open,
                        onNewCategory: beginCategoryCreation,
                        onRename: beginRenaming
                    )
                    .padding(.horizontal, MagicWallLayout.gutter)
                }
            }
            .padding(.top, MagicWallLayout.contentTopInset)
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
                    text: L("drop.hint"),
                    icon: "arrow.down.circle.fill",
                    tint: theme.active.accentColor,
                    dismiss: nil
                )
            } else if let error = viewModel.lastError {
                banner(
                    text: error,
                    icon: "exclamationmark.triangle.fill",
                    tint: theme.active.dangerColor,
                    dismiss: { viewModel.lastError = nil }
                )
            } else if let message = viewModel.statusMessage {
                banner(
                    text: message,
                    icon: "checkmark.circle.fill",
                    tint: theme.active.liveBadgeBackgroundColor,
                    dismiss: nil
                )
                .task(id: message) {
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    if viewModel.statusMessage == message {
                        withAnimation(.easeOut(duration: 0.15)) { viewModel.statusMessage = nil }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 22)
        .animation(.easeOut(duration: 0.15), value: viewModel.statusMessage)
        .animation(.easeOut(duration: 0.15), value: isDropTargeted)

        dropHighlight
    }

    private var dropHighlight: some View {
        RoundedRectangle(cornerRadius: theme.active.cornerRadiusValue + 6, style: .continuous)
            .strokeBorder(
                theme.active.accentColor,
                style: StrokeStyle(lineWidth: 3, dash: [10, 7])
            )
            .background(
                RoundedRectangle(cornerRadius: theme.active.cornerRadiusValue + 6, style: .continuous)
                    .fill(theme.active.accentColor.opacity(0.10))
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
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(theme.active.textPrimaryColor)
                .lineLimit(2)

            if let dismiss {
                Button {
                    withAnimation(.easeOut(duration: 0.12)) { dismiss() }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(theme.active.textTertiaryColor)
                }
                .buttonStyle(.plain)
                .help(L("common.dismiss"))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(theme.active.surfaceHoverColor, in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Actions

    private func open(_ video: Video) {
        withAnimation(.easeOut(duration: 0.15)) { previewVideo = video }
    }

    private func beginCategoryCreation() {
        newCategoryName = ""
        isNamingCategory = true
    }

    private var isRenamingVideoPresented: Binding<Bool> {
        Binding(
            get: { renamingVideo != nil },
            set: { isPresented in
                if !isPresented {
                    renamingVideo = nil
                    renameText = ""
                }
            }
        )
    }

    private func beginRenaming(_ video: Video) {
        renameText = video.title
        renamingVideo = video
    }

    private func commitRename() {
        guard let video = renamingVideo else { return }
        renamingVideo = nil
        guard let updated = viewModel.rename(video, to: renameText) else { return }
        if previewVideo?.id == updated.id {
            previewVideo = updated
        }
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
