import Combine
import Foundation
import MagicWallCore

/// Downloads the bundled "starter" wallpapers on demand.
///
/// The service owns no authoritative state of its own: what is installed is
/// always derived from the library database (a `starter-<id>` record — or any
/// record whose `contentHash` matches the catalog — with a file on disk). The
/// only thing persisted is whether the first-launch offer was dismissed.
@MainActor
final class StarterWallpaperService: ObservableObject {
    enum Status: Equatable {
        /// Nothing installed, never dismissed-or-downloaded.
        case available
        /// A batch download is in flight.
        case downloading(completed: Int, total: Int, bytesDownloaded: Int64, bytesTotal: Int64)
        /// Every catalog wallpaper is present in the library.
        case installed
        /// Some, but not all, catalog wallpapers are present.
        case partial(installed: Int)
        /// The last download attempt failed.
        case failed(String)
    }

    enum DownloadError: LocalizedError {
        case badResponse
        case httpStatus(Int)
        case sizeMismatch(expected: Int64, actual: Int64)
        case checksumMismatch

        var errorDescription: String? {
            switch self {
            case .badResponse:
                return "The download server returned an invalid response."
            case .httpStatus(let code):
                return "The download server returned HTTP \(code)."
            case .sizeMismatch(let expected, let actual):
                return "Downloaded file size mismatch (expected \(expected) bytes, got \(actual))."
            case .checksumMismatch:
                return "The downloaded file failed its integrity check."
            }
        }
    }

    /// Settings key holding the persisted `{"dismissed": Bool}` JSON blob.
    static let settingsKey = "starterWallpapers.v1"
    /// Prefix used for library records created by this service.
    static let videoIDPrefix = "starter-"
    /// Environment flag that suppresses the automatic first-launch offer.
    static let offerDisabledEnvironmentKey = "MW_DISABLE_STARTER_OFFER"

    @Published private(set) var status: Status = .available
    /// Whether the first-launch offer was already shown and skipped.
    @Published private(set) var hasBeenOffered: Bool = false

    private let repository: LibraryRepository
    private var downloadTask: Task<Void, Never>?

    private struct PersistedState: Codable {
        var dismissed: Bool
    }

    init(repository: LibraryRepository) {
        self.repository = repository
        self.hasBeenOffered = Self.persistedDismissed(in: repository)
        refreshStatus()
    }

    // MARK: - Environment

    /// The automatic offer is suppressed for isolated data directories (UI
    /// tests, development tooling) and when explicitly disabled. The manual
    /// download from Settings stays available in both cases.
    static var isOfferDisabledByEnvironment: Bool {
        let environment = ProcessInfo.processInfo.environment
        if environment[AppPaths.dataDirectoryEnvironmentKey] != nil { return true }
        if environment[Self.offerDisabledEnvironmentKey] == "1" { return true }
        return false
    }

    // MARK: - Status

    /// Recomputes the status from the database. Call after an external mutation
    /// (deletion, import) rather than during a download.
    func refreshStatus() {
        let total = StarterWallpaperCatalog.current.wallpapers.count
        let installed = installedCount()

        if total > 0, installed >= total {
            status = .installed
        } else if installed > 0 {
            status = .partial(installed: installed)
        } else {
            status = .available
        }
    }

    /// Number of catalog wallpapers currently present in the library.
    func installedCount() -> Int {
        StarterWallpaperCatalog.current.wallpapers.reduce(into: 0) { count, wallpaper in
            if existingVideo(for: wallpaper) != nil { count += 1 }
        }
    }

    /// Library record IDs of every installed catalog wallpaper, in catalog
    /// order. Uses the deduplicated record when the file was already imported.
    func installedVideoIDs() -> [String] {
        StarterWallpaperCatalog.current.wallpapers.compactMap { wallpaper in
            existingVideo(for: wallpaper)?.id
        }
    }

    // MARK: - Offer

    /// Persists the "user skipped the offer" flag so it is not shown again.
    func dismissOffer() {
        hasBeenOffered = true
        persistDismissed(true)
    }

    // MARK: - Download

    /// Downloads every missing catalog wallpaper, one at a time. Idempotent:
    /// returns immediately when a download is already running or everything is
    /// installed, and reuses (without copying) any record whose content hash
    /// already matches.
    func downloadAll() async {
        if case .downloading = status { return }

        let catalog = StarterWallpaperCatalog.current
        var missing: [StarterWallpaper] = []
        var completed = 0
        var bytesDownloaded: Int64 = 0

        for wallpaper in catalog.wallpapers {
            if existingVideo(for: wallpaper) != nil {
                completed += 1
                bytesDownloaded += max(wallpaper.bytes, 0)
            } else {
                missing.append(wallpaper)
            }
        }

        guard !missing.isEmpty else {
            refreshStatus()
            return
        }

        let total = catalog.wallpapers.count
        let bytesTotal = catalog.totalBytes
        status = .downloading(
            completed: completed,
            total: total,
            bytesDownloaded: bytesDownloaded,
            bytesTotal: bytesTotal
        )

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runDownload(
                missing,
                completed: completed,
                bytesDownloaded: bytesDownloaded,
                total: total,
                bytesTotal: bytesTotal
            )
        }
        downloadTask = task

        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }

        downloadTask = nil
    }

    /// Cancels the in-flight download, if any. Partial files are cleaned up and
    /// the status falls back to `.available` / `.partial`.
    func cancel() {
        downloadTask?.cancel()
    }

    private func runDownload(
        _ missing: [StarterWallpaper],
        completed initialCompleted: Int,
        bytesDownloaded initialBytes: Int64,
        total: Int,
        bytesTotal: Int64
    ) async {
        var completed = initialCompleted
        var bytesDownloaded = initialBytes

        for wallpaper in missing {
            if Task.isCancelled {
                refreshStatus()
                return
            }

            do {
                try await download(wallpaper)
                completed += 1
                bytesDownloaded += max(wallpaper.bytes, 0)
                status = .downloading(
                    completed: min(completed, total),
                    total: total,
                    bytesDownloaded: min(bytesDownloaded, bytesTotal),
                    bytesTotal: bytesTotal
                )
            } catch {
                cleanupPartial(wallpaper)
                if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                    refreshStatus()
                    return
                }
                status = .failed(error.localizedDescription)
                return
            }
        }

        refreshStatus()
    }

    private func download(_ wallpaper: StarterWallpaper) async throws {
        let remoteURL = StarterWallpaperCatalog.current.remoteURL(for: wallpaper)

        let (temporaryURL, response) = try await URLSession.shared.download(from: remoteURL)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        guard let http = response as? HTTPURLResponse else { throw DownloadError.badResponse }
        guard http.statusCode == 200 else { throw DownloadError.httpStatus(http.statusCode) }

        if wallpaper.bytes > 0 {
            let actual = Self.fileSize(at: temporaryURL)
            guard actual == wallpaper.bytes else {
                throw DownloadError.sizeMismatch(expected: wallpaper.bytes, actual: actual)
            }
        }

        if !wallpaper.sha256.isEmpty {
            let digest = try await SHA256Hasher().sha256(of: temporaryURL)
            guard digest.caseInsensitiveCompare(wallpaper.sha256) == .orderedSame else {
                throw DownloadError.checksumMismatch
            }
        }

        try Task.checkCancellation()

        try AppPaths.ensureDirectories()
        let videoID = "\(Self.videoIDPrefix)\(wallpaper.id)"
        let destination = AppPaths.managedVideoDestination(id: videoID, fileExtension: "mp4")
        let posterDestination = AppPaths.posterDestination(for: videoID)
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: temporaryURL, to: destination)

        var posterPath: String?
        do {
            try await AVPosterGenerator().makePoster(
                for: destination,
                to: posterDestination,
                maxWidth: 1280,
                at: nil
            )
            posterPath = posterDestination.path
        } catch {
            // A missing poster is not fatal; keep the video.
            posterPath = nil
        }

        try Task.checkCancellation()

        // Probe the copy, falling back to the manifest values when AVFoundation
        // cannot read it.
        let metadata = try? await AVMediaProbe().probe(url: destination)

        var video = Video(
            id: videoID,
            title: wallpaper.title,
            filePath: destination.path,
            duration: metadata?.duration ?? wallpaper.duration,
            width: metadata?.width ?? wallpaper.width,
            height: metadata?.height ?? wallpaper.height,
            fps: metadata?.fps ?? 0,
            codec: metadata?.codec,
            bitrate: metadata?.bitrate ?? 0,
            fileSize: wallpaper.bytes > 0 ? wallpaper.bytes : (metadata?.fileSize ?? 0),
            contentHash: wallpaper.sha256.isEmpty ? nil : wallpaper.sha256,
            posterPath: posterPath,
            source: .starter
        )
        video.createdAt = Date()
        video.importedAt = Date()

        try repository.save(video)
        try? repository.setFavorite(true, videoID: videoID)

        // Best effort: file it under the built-in "Nature" category.
        if let nature = (try? repository.categories())?.first(where: { $0.slug == "nature" }),
           let categoryID = nature.id {
            try? repository.setCategories([categoryID], forVideo: videoID)
        }
    }

    // MARK: - Installed detection

    /// Returns the library record for a wallpaper: either the managed
    /// `starter-<id>` record, or a pre-existing record with the same content
    /// hash (dedup). Requires the backing file to actually exist.
    private func existingVideo(for wallpaper: StarterWallpaper) -> Video? {
        if let video = try? repository.video(id: "\(Self.videoIDPrefix)\(wallpaper.id)"),
           FileManager.default.fileExists(atPath: video.filePath) {
            return video
        }

        if !wallpaper.sha256.isEmpty,
           let video = try? repository.video(contentHash: wallpaper.sha256),
           FileManager.default.fileExists(atPath: video.filePath) {
            return video
        }

        return nil
    }

    /// Removes the artifacts of a single failed or cancelled wallpaper
    /// download, leaving already-installed ones untouched.
    private func cleanupPartial(_ wallpaper: StarterWallpaper) {
        let videoID = "\(Self.videoIDPrefix)\(wallpaper.id)"
        let fileManager = FileManager.default

        let destination = AppPaths.managedVideoDestination(id: videoID, fileExtension: "mp4")
        if fileManager.fileExists(atPath: destination.path) {
            try? fileManager.removeItem(at: destination)
        }

        let poster = AppPaths.posterDestination(for: videoID)
        if fileManager.fileExists(atPath: poster.path) {
            try? fileManager.removeItem(at: poster)
        }

        try? repository.deleteVideo(id: videoID)
    }

    private static func fileSize(at url: URL) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }

    // MARK: - Persistence

    private static func persistedDismissed(in repository: LibraryRepository) -> Bool {
        guard let raw = try? repository.setting(settingsKey),
              let data = raw.data(using: .utf8) else {
            return false
        }
        return (try? JSONDecoder().decode(PersistedState.self, from: data))?.dismissed ?? false
    }

    private func persistDismissed(_ dismissed: Bool) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(PersistedState(dismissed: dismissed)),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        try? repository.setSetting(Self.settingsKey, value: json)
    }
}
