import AppKit
import Combine
import Foundation
import MagicWallCore

/// Single source of truth for the library UI. Views own no state beyond presentation.
@MainActor
final class LibraryViewModel: ObservableObject {
    @Published private(set) var videos: [Video] = []
    @Published private(set) var categories: [VideoCategory] = []
    @Published private(set) var favoriteIDs: Set<String> = []
    @Published private(set) var libraryBytes: Int64 = 0
    @Published private(set) var isImporting = false
    @Published var searchText = ""
    @Published var selectedCategorySlug: String?
    @Published var showsFavoritesOnly = false
    @Published var lastError: String?
    @Published var statusMessage: String?

    let repository: LibraryRepository
    let importService: VideoImporting
    let engine: WallpaperEngine
    let startupWarnings: [String]

    init(
        repository: LibraryRepository,
        importService: VideoImporting,
        engine: WallpaperEngine,
        startupWarnings: [String] = []
    ) {
        self.repository = repository
        self.importService = importService
        self.engine = engine
        self.startupWarnings = startupWarnings
    }

    // MARK: - Derived state

    var displayVideos: [Video] {
        var list = videos
        if showsFavoritesOnly {
            list = list.filter { favoriteIDs.contains($0.id) }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            list = list.filter { $0.title.localizedCaseInsensitiveContains(query) }
        }
        return list
    }

    var librarySizeLabel: String {
        ByteCountFormatter.string(fromByteCount: libraryBytes, countStyle: .file)
    }

    // MARK: - Data loading

    func refresh() {
        do {
            categories = try repository.categories()
            videos = try repository.videos(inCategorySlug: selectedCategorySlug)
            favoriteIDs = try repository.favoriteIDs()
            libraryBytes = try repository.totalLibraryBytes()
            lastError = nil
        } catch {
            lastError = "Library error: \(error.localizedDescription)"
        }
    }

    // MARK: - Import

    func presentImportPanel() {
        let panel = NSOpenPanel()
        panel.title = "Import Wallpaper Videos"
        panel.message = "Choose MP4/MOV videos or a folder containing them."
        panel.prompt = "Import"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.movie, .video]

        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        Task { await importVideos(urls) }
    }

    func importVideos(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }
        isImporting = true
        defer { isImporting = false }

        do {
            let imported = try await importService.importVideos(from: urls)
            refresh()
            if imported.isEmpty {
                statusMessage = "No importable videos found in the selection."
            } else {
                let duplicates = imported.count != urls.count
                statusMessage = "Imported \(imported.count) video\(imported.count == 1 ? "" : "s")\(duplicates ? " (duplicates reused)" : "")."
            }
        } catch {
            lastError = "Import failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Applying wallpapers

    func applyToAllScreens(_ video: Video) {
        engine.applyToAllScreens(video)
        try? repository.markPlayed(id: video.id)
        statusMessage = "“\(video.title)” is now playing on all screens."
    }

    func applyRandomToAllScreens() {
        guard let video = videos.randomElement() else { return }
        applyToAllScreens(video)
    }

    // MARK: - Mutations

    func toggleFavorite(_ video: Video) {
        let newValue = !favoriteIDs.contains(video.id)
        do {
            try repository.setFavorite(newValue, videoID: video.id)
            if newValue { favoriteIDs.insert(video.id) } else { favoriteIDs.remove(video.id) }
        } catch {
            lastError = "Could not update favorite: \(error.localizedDescription)"
        }
    }

    func delete(_ video: Video) {
        engine.stopDisplaying(videoID: video.id)
        do {
            let fileManager = FileManager.default
            if video.filePath.hasPrefix(AppPaths.libraryRoot.path) {
                try? fileManager.removeItem(at: video.fileURL)
            }
            if let posterURL = video.posterURL, video.posterPath?.hasPrefix(AppPaths.postersDirectory.path) == true {
                try? fileManager.removeItem(at: posterURL)
            }
            try repository.deleteVideo(id: video.id)
            refresh()
            statusMessage = "Deleted “\(video.title)”."
        } catch {
            lastError = "Could not delete video: \(error.localizedDescription)"
        }
    }

    func createCategory(named name: String) {
        do {
            _ = try repository.addCategory(name: name)
            categories = try repository.categories()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func deleteCategory(_ category: VideoCategory) {
        guard let id = category.id else { return }
        do {
            try repository.deleteCategory(id: id)
            if selectedCategorySlug == category.slug {
                selectedCategorySlug = nil
            }
            refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func categories(for video: Video) -> [VideoCategory] {
        (try? repository.categories(forVideo: video.id)) ?? []
    }

    func toggleCategory(_ category: VideoCategory, for video: Video) {
        guard let categoryID = category.id else { return }
        var current = categories(for: video).compactMap(\.id)
        if let index = current.firstIndex(of: categoryID) {
            current.remove(at: index)
        } else {
            current.append(categoryID)
        }
        do {
            try repository.setCategories(current, forVideo: video.id)
        } catch {
            lastError = error.localizedDescription
        }
    }
}
