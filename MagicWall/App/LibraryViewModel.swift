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
            lastError = L("library.error", error.localizedDescription)
        }
    }

    // MARK: - Import

    func presentImportPanel() {
        let panel = NSOpenPanel()
        panel.title = L("import.panel.title")
        panel.message = L("import.panel.message")
        panel.prompt = L("common.import")
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
                statusMessage = L("import.none")
            } else {
                let count = imported.count
                let duplicates = count != urls.count
                statusMessage = Self.importSummary(count: count, duplicates: duplicates)
            }
        } catch {
            lastError = L("import.error", error.localizedDescription)
        }
    }

    private static func importSummary(count: Int, duplicates: Bool) -> String {
        switch (count == 1, duplicates) {
        case (true, true): return L("import.summary.one.duplicates", count)
        case (true, false): return L("import.summary.one", count)
        case (false, true): return L("import.summary.other.duplicates", count)
        case (false, false): return L("import.summary.other", count)
        }
    }

    // MARK: - Applying wallpapers

    func applyToAllScreens(_ video: Video) {
        engine.applyToAllScreens(video)
        try? repository.markPlayed(id: video.id)
        statusMessage = L("video.status.playingAll", video.title)
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
            lastError = L("video.error.favorite", error.localizedDescription)
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
            statusMessage = L("video.status.deleted", video.title)
        } catch {
            lastError = L("video.error.delete", error.localizedDescription)
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
