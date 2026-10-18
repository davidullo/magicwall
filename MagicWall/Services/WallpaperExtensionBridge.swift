import CryptoKit
import Foundation
import MagicWallCore

/// Mirrors the MagicWall library into the wallpaper extension's sandbox
/// container.
///
/// The extension (target `MagicWallWallpaperExtension`) is one of the system's
/// `com.apple.wallpaper` providers: macOS paints the desktop and the lock screen
/// from it. ExtensionKit sandboxes it, so it can only read inside its own
/// container — MagicWall is not sandboxed and is therefore the only side that
/// can write there. That is this type's whole job.
///
/// Mirroring is hard-link first and copy only as a fallback, so a full library
/// costs a handful of directory entries instead of a second copy of every
/// video. The extension re-scans on the Darwin notification posted at the end
/// of a sync (`MagicWallWallpaperExtension.observeLibraryChanges`).
final class WallpaperExtensionBridge: @unchecked Sendable {
    /// Bundle identifier of the wallpaper extension embedded in the app.
    static let extensionBundleID = "app.magicwall.wallpaper-extension"

    /// Name of the embedded appex inside `Contents/Extensions`.
    static let extensionBundleName = "MagicWallWallpaperExtension.appex"

    /// Darwin notification the extension observes to re-scan the library.
    static let libraryChangedNotification = "app.magicwall.libraryChanged"

    /// Environment flag that suppresses mirroring: isolated data directories
    /// (UI tests, development tooling) must never touch the real container.
    static var isDisabledByEnvironment: Bool {
        ProcessInfo.processInfo.environment[AppPaths.dataDirectoryEnvironmentKey] != nil
    }

    private let fileManager = FileManager.default
    private let homeDirectory: URL

    /// Serialises syncs so a burst of library changes cannot interleave and
    /// unlink a file another pass is about to write.
    private let queue = DispatchQueue(
        label: "app.magicwall.wallpaper-extension-bridge",
        qos: .utility
    )

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory
    }

    // MARK: - Locations

    /// The `Documents` folder the extension sees inside its container. The
    /// system creates the container the first time the extension runs; the
    /// intermediate directories are created here so a library can be deployed
    /// before that ever happens.
    var containerDocumentsURL: URL {
        homeDirectory.appendingPathComponent(
            "Library/Containers/\(Self.extensionBundleID)/Data/Documents",
            isDirectory: true
        )
    }

    /// One `<extension id>/` directory per video, as the extension expects.
    var videosDirectoryURL: URL {
        containerDocumentsURL.appendingPathComponent("videos", isDirectory: true)
    }

    /// True when the extension is embedded in the running bundle. A build
    /// without the appex can never animate the lock screen, and mirroring a
    /// library for it would only litter the disk.
    static var isExtensionBundled: Bool {
        let appex = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Extensions", isDirectory: true)
            .appendingPathComponent(extensionBundleName, isDirectory: true)
        guard FileManager.default.fileExists(atPath: appex.path) else { return false }
        return Bundle(url: appex)?.bundleIdentifier == extensionBundleID
    }

    // MARK: - Sync

    /// Converges the extension's copy of the library on `videos`: adds what is
    /// new, refreshes what changed, removes what is gone. Runs off the main
    /// thread — the Darwin notification is posted only when something moved, so
    /// an unchanged library never wakes the extension.
    func sync(_ videos: [Video]) {
        guard !Self.isDisabledByEnvironment else { return }

        queue.async { [self] in
            if converge(videos) {
                Self.notifyLibraryChanged()
            }
        }
    }

    /// The mapped directory name a video gets inside the container: UUID ids
    /// (imported videos) are used verbatim, anything else (starter videos are
    /// `starter-…`) is hashed into a stable UUID so the extension's UUID-only
    /// directory rule keeps holding without a lookup table.
    static func extensionVideoID(for video: Video) -> String {
        extensionVideoID(for: video.id)
    }

    static func extensionVideoID(for videoID: String) -> String {
        UUID(uuidString: videoID) != nil ? videoID : stableUUIDString(from: videoID)
    }

    // MARK: - Private

    /// Returns true when the container changed and the extension must re-scan.
    private func converge(_ videos: [Video]) -> Bool {
        do {
            try fileManager.createDirectory(at: videosDirectoryURL, withIntermediateDirectories: true)
        } catch {
            return false
        }

        var desired: [String: Video] = [:]
        for video in videos {
            desired[Self.extensionVideoID(for: video)] = video
        }

        var changed = false
        for (id, video) in desired where deploy(video, extensionID: id) {
            changed = true
        }

        // Entries the library no longer has. Only UUID directories are ever
        // touched: anything else in the container is not ours to delete.
        let existing = (try? fileManager.contentsOfDirectory(
            at: videosDirectoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        for url in existing where url.hasDirectoryPath {
            let id = url.lastPathComponent
            guard desired[id] == nil, UUID(uuidString: id) != nil else { continue }
            do {
                try fileManager.removeItem(at: url)
                changed = true
            } catch {
                continue
            }
        }

        return changed
    }

    /// Mirrors one video: directory, hard link and metadata. Returns true when
    /// anything on disk changed.
    private func deploy(_ video: Video, extensionID: String) -> Bool {
        let source = URL(fileURLWithPath: video.filePath)
        let directory = videosDirectoryURL.appendingPathComponent(extensionID, isDirectory: true)

        guard fileManager.fileExists(atPath: source.path) else {
            // The record outlived its file (deleted outside the app): mirror the
            // absence instead of leaving a dead entry on the lock screen.
            guard fileManager.fileExists(atPath: directory.path) else { return false }
            return (try? fileManager.removeItem(at: directory)) != nil
        }

        let destination = directory.appendingPathComponent(source.lastPathComponent)

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return false
        }

        var changed = false
        if !linksToSameFile(destination, source) {
            try? fileManager.removeItem(at: destination)
            do {
                try fileManager.linkItem(at: source, to: destination)
                changed = true
            } catch {
                // Containers on another volume, or filesystems without hard
                // links: a copy is slower and bigger, never wrong.
                if (try? fileManager.copyItem(at: source, to: destination)) != nil {
                    changed = true
                }
            }
        }

        if writeMetadata(for: video, in: directory, extensionID: extensionID, fileName: source.lastPathComponent) {
            changed = true
        }

        return changed
    }

    /// True when `destination` is already the very same file as `source`.
    /// Identity — not the path — is what matters: when the starter service
    /// replaces a video with a different quality tier the path stays the same
    /// and this link would otherwise keep serving the old file.
    private func linksToSameFile(_ destination: URL, _ source: URL) -> Bool {
        let keys: Set<URLResourceKey> = [.fileResourceIdentifierKey]
        guard let destinationID = (try? destination.resourceValues(forKeys: keys))?.fileResourceIdentifier,
              let sourceID = (try? source.resourceValues(forKeys: keys))?.fileResourceIdentifier
        else { return false }
        return (destinationID as? NSObject)?.isEqual(sourceID) ?? false
    }

    /// Writes the `metadata.json` the extension decodes into its `VideoEntry`.
    /// The shape is a wire contract with `VideoLibrary`: same keys, `resolution`
    /// as a two-element array and dates as JSONEncoder's default (seconds since
    /// 2001). Unchanged content is not rewritten.
    @discardableResult
    private func writeMetadata(
        for video: Video,
        in directory: URL,
        extensionID: String,
        fileName: String
    ) -> Bool {
        let entry = ExtensionVideoEntry(
            id: extensionID,
            name: video.title,
            filename: fileName,
            duration: video.duration,
            fps: video.fps,
            resolution: [Double(video.width), Double(video.height)],
            dateAdded: video.importedAt
        )

        guard let data = try? JSONEncoder().encode(entry) else { return false }
        let url = directory.appendingPathComponent("metadata.json")

        if let existing = try? Data(contentsOf: url), existing == data { return false }

        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// SHA-256 of the library id folded into an RFC 4122 v4-shaped UUID string:
    /// stable across launches, so a starter video keeps the same directory (and
    /// therefore the same system wallpaper selection) forever.
    private static func stableUUIDString(from string: String) -> String {
        var bytes = Array(SHA256.hash(data: Data(string.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80

        let hex = bytes.map { String(format: "%02X", $0) }.joined()
        let groups = [
            hex.prefix(8),
            hex.dropFirst(8).prefix(4),
            hex.dropFirst(12).prefix(4),
            hex.dropFirst(16).prefix(4),
            hex.dropFirst(20),
        ]
        return groups.map(String.init).joined(separator: "-")
    }

    private static func notifyLibraryChanged() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(libraryChangedNotification as CFString),
            nil,
            nil,
            true
        )
    }
}

/// Wire format of `metadata.json` inside the container. Mirrors the extension's
/// `VideoEntry`, minus `variants` (MagicWall has one file per video).
private struct ExtensionVideoEntry: Codable {
    var id: String
    var name: String
    var filename: String
    var duration: Double
    var fps: Double
    var resolution: [Double]
    var dateAdded: Date
}
