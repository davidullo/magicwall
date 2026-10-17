import Combine
import Foundation
import MagicWallCore

/// Downloads the bundled "starter" wallpapers on demand.
///
/// Every wallpaper ships in two quality tiers (`high` and `compact`). The
/// preferred tier is persisted in `app_settings`; switching tier replaces the
/// file of the same `starter-<id>` record, so favorites, categories and
/// per-screen assignments survive an upgrade.
///
/// The service owns no authoritative state of its own: what is installed is
/// always derived from the library database (a `starter-<id>` record — or any
/// record whose `contentHash` matches a catalog variant — with a file on disk).
/// The only things persisted are whether the first-launch offer was dismissed
/// and the preferred quality tier.
@MainActor
final class StarterWallpaperService: ObservableObject {
    enum Status: Equatable {
        /// Nothing installed at the selected tier, never dismissed-or-downloaded.
        case available
        /// A batch download is in flight.
        case downloading(completed: Int, total: Int, bytesDownloaded: Int64, bytesTotal: Int64)
        /// Every catalog wallpaper is present at the selected tier.
        case installed
        /// Some, but not all, catalog wallpapers are present at the selected tier.
        case partial(installed: Int)
        /// The last download attempt failed.
        case failed(String)
    }

    enum DownloadError: LocalizedError {
        case badResponse
        case httpStatus(Int)
        case sizeMismatch(expected: Int64, actual: Int64)
        case checksumMismatch
        case missingVariant

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
            case .missingVariant:
                return "The catalog does not list a file for this wallpaper."
            }
        }
    }

    /// Settings key holding the persisted `{"dismissed": Bool}` JSON blob.
    static let settingsKey = "starterWallpapers.v1"
    /// Settings key holding the preferred quality tier.
    static let qualitySettingsKey = "starterWallpapers.quality"
    /// Prefix used for library records created by this service.
    static let videoIDPrefix = "starter-"
    /// Environment flag that suppresses the automatic first-launch offer.
    static let offerDisabledEnvironmentKey = "MW_DISABLE_STARTER_OFFER"

    @Published private(set) var status: Status = .available
    /// Whether the first-launch offer was already shown and skipped.
    @Published private(set) var hasBeenOffered: Bool = false
    /// Quality tier the user wants in the library.
    @Published private(set) var quality: StarterWallpaperQuality

    /// Invoked with the video id whenever a file on disk was replaced by a
    /// different tier, so the engine can reload it if it is on screen.
    var onVideoReplaced: (@MainActor (String) -> Void)?

    private let repository: LibraryRepository
    private var downloadTask: Task<Void, Never>?

    private struct PersistedState: Codable {
        var dismissed: Bool
    }

    init(repository: LibraryRepository) {
        self.repository = repository
        let stored = (try? repository.setting(Self.qualitySettingsKey)) ?? nil
        self.quality = stored.flatMap(StarterWallpaperQuality.init(rawValue:)) ?? .default
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

    /// Number of catalog wallpapers installed at the selected tier.
    func installedCount() -> Int {
        installedCount(in: quality)
    }

    /// Number of catalog wallpapers installed at a specific tier.
    func installedCount(in quality: StarterWallpaperQuality) -> Int {
        StarterWallpaperCatalog.current.wallpapers.reduce(into: 0) { count, wallpaper in
            if installedQuality(for: wallpaper) == quality { count += 1 }
        }
    }

    /// Tier currently on disk for a wallpaper: a variant whose checksum matches
    /// the record's content hash, or `compact` for a copy left by an older pack
    /// whose bytes are no longer in the catalog. `nil` when absent.
    func installedQuality(for wallpaper: StarterWallpaper) -> StarterWallpaperQuality? {
        guard let video = existingVideo(for: wallpaper) else { return nil }

        if let match = wallpaper.variants.first(where: {
            !$0.sha256.isEmpty
                && $0.sha256.caseInsensitiveCompare(video.contentHash ?? "") == .orderedSame
        }) {
            return match.quality
        }

        return .compact
    }

    /// Tier shared by every installed wallpaper, or `nil` when nothing is
    /// installed or the library mixes tiers.
    func installedQuality() -> StarterWallpaperQuality? {
        let tiers = StarterWallpaperCatalog.current.wallpapers.compactMap { installedQuality(for: $0) }
        guard let first = tiers.first else { return nil }
        return tiers.allSatisfy { $0 == first } ? first : nil
    }

    /// Library record IDs of every installed catalog wallpaper, in catalog
    /// order. Uses the deduplicated record when the file was already imported.
    func installedVideoIDs() -> [String] {
        StarterWallpaperCatalog.current.wallpapers.compactMap { wallpaper in
            existingVideo(for: wallpaper)?.id
        }
    }

    // MARK: - Quality

    /// Switches tier: the next download replaces the files of the existing
    /// `starter-<id>` records, so favorites, categories and assignments stay.
    func setQuality(_ newQuality: StarterWallpaperQuality) {
        guard newQuality != quality else { return }
        quality = newQuality
        try? repository.setSetting(Self.qualitySettingsKey, value: newQuality.rawValue)
        refreshStatus()
    }

    // MARK: - Offer

    /// Persists the "user skipped the offer" flag so it is not shown again.
    func dismissOffer() {
        hasBeenOffered = true
        persistDismissed(true)
    }

    // MARK: - Download

    /// Downloads every catalog wallpaper that is missing at the selected tier,
    /// one at a time. Idempotent: returns immediately when a download is
    /// already running or everything is installed at that tier, and reuses
    /// (without copying) any record whose content hash already matches.
    func downloadAll() async {
        if case .downloading = status { return }

        let catalog = StarterWallpaperCatalog.current
        let target = quality
        var missing: [StarterWallpaper] = []
        var completed = 0
        var bytesDownloaded: Int64 = 0

        for wallpaper in catalog.wallpapers {
            if installedQuality(for: wallpaper) == target {
                completed += 1
                bytesDownloaded += variantBytes(of: wallpaper, quality: target)
            } else {
                missing.append(wallpaper)
            }
        }

        guard !missing.isEmpty else {
            refreshStatus()
            return
        }

        let total = catalog.wallpapers.count
        let bytesTotal = catalog.totalBytes(for: target)
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
                quality: target,
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
        quality: StarterWallpaperQuality,
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
                try await download(wallpaper, quality: quality)
                completed += 1
                bytesDownloaded += variantBytes(of: wallpaper, quality: quality)
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

    /// Size of the file that will be installed for a tier, when the manifest
    /// knows it (0 otherwise).
    private func variantBytes(of wallpaper: StarterWallpaper, quality: StarterWallpaperQuality) -> Int64 {
        max(wallpaper.installableVariant(quality)?.bytes ?? 0, 0)
    }

    private func download(_ wallpaper: StarterWallpaper, quality: StarterWallpaperQuality) async throws {
        guard let variant = wallpaper.installableVariant(quality) else {
            throw DownloadError.missingVariant
        }

        let remoteURL = StarterWallpaperCatalog.current.remoteURL(for: wallpaper, quality: variant.quality)

        let (temporaryURL, response) = try await URLSession.shared.download(from: remoteURL)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        guard let http = response as? HTTPURLResponse else { throw DownloadError.badResponse }
        guard http.statusCode == 200 else { throw DownloadError.httpStatus(http.statusCode) }

        if variant.bytes > 0 {
            let actual = Self.fileSize(at: temporaryURL)
            guard actual == variant.bytes else {
                throw DownloadError.sizeMismatch(expected: variant.bytes, actual: actual)
            }
        }

        if !variant.sha256.isEmpty {
            let digest = try await SHA256Hasher().sha256(of: temporaryURL)
            guard digest.caseInsensitiveCompare(variant.sha256) == .orderedSame else {
                throw DownloadError.checksumMismatch
            }
        }

        try Task.checkCancellation()

        try AppPaths.ensureDirectories()
        let videoID = "\(Self.videoIDPrefix)\(wallpaper.id)"
        let destination = AppPaths.managedVideoDestination(id: videoID, fileExtension: "mp4")
        let posterDestination = AppPaths.posterDestination(for: videoID)
        let fileManager = FileManager.default

        // Stage the verified download next to its destination and swap it in
        // only now: a failed upgrade must leave the installed quality intact.
        let staged = Self.stagedURL(for: destination)
        if fileManager.fileExists(atPath: staged.path) {
            try fileManager.removeItem(at: staged)
        }
        try fileManager.moveItem(at: temporaryURL, to: staged)

        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: staged)
        } else {
            try fileManager.moveItem(at: staged, to: destination)
        }

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
            fileSize: variant.bytes > 0 ? variant.bytes : (metadata?.fileSize ?? 0),
            contentHash: variant.sha256.isEmpty ? nil : variant.sha256,
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

        // The bytes behind an existing record were replaced: the engine has to
        // re-read the file when that wallpaper is currently on screen.
        onVideoReplaced?(videoID)
    }

    // MARK: - Installed detection

    /// Returns the library record for a wallpaper: either the managed
    /// `starter-<id>` record, or a pre-existing record whose content hash
    /// matches one of the catalog variants (dedup). Requires the backing file
    /// to actually exist.
    private func existingVideo(for wallpaper: StarterWallpaper) -> Video? {
        if let video = try? repository.video(id: "\(Self.videoIDPrefix)\(wallpaper.id)"),
           FileManager.default.fileExists(atPath: video.filePath) {
            return video
        }

        for variant in wallpaper.variants where !variant.sha256.isEmpty {
            if let video = try? repository.video(contentHash: variant.sha256),
               FileManager.default.fileExists(atPath: video.filePath) {
                return video
            }
        }

        return nil
    }

    /// Removes the artifacts of a single failed or cancelled wallpaper
    /// download. A wallpaper that is already installed is left alone: only a
    /// staged file is dropped, so a failed quality upgrade keeps the previous
    /// tier playable.
    private func cleanupPartial(_ wallpaper: StarterWallpaper) {
        let videoID = "\(Self.videoIDPrefix)\(wallpaper.id)"
        let fileManager = FileManager.default

        let destination = AppPaths.managedVideoDestination(id: videoID, fileExtension: "mp4")
        let staged = Self.stagedURL(for: destination)
        if fileManager.fileExists(atPath: staged.path) {
            try? fileManager.removeItem(at: staged)
        }

        guard !fileManager.fileExists(atPath: destination.path) else { return }

        let poster = AppPaths.posterDestination(for: videoID)
        if fileManager.fileExists(atPath: poster.path) {
            try? fileManager.removeItem(at: poster)
        }

        try? repository.deleteVideo(id: videoID)
    }

    /// Temporary name used while a download is being verified, next to the
    /// final file so the swap stays on the same volume.
    private static func stagedURL(for destination: URL) -> URL {
        destination
            .deletingLastPathComponent()
            .appendingPathComponent(destination.lastPathComponent + ".incoming")
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
