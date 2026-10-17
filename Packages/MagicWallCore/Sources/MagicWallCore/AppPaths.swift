import Foundation

/// Canonical locations of MagicWall's on-disk data.
///
/// ~/Library/Application Support/MagicWall/
///   ├── magicwall.sqlite          (library database)
///   └── Library/
///       ├── Videos/<uuid>.<ext>   (managed video files)
///       └── Posters/<uuid>.jpg    (generated poster frames)
public enum AppPaths {
    public static let appSupportFolderName = "MagicWall"

    /// Overrides the on-disk data root (database, managed videos, posters,
    /// themes). Used by UI tests and development tooling to keep a real user
    /// library untouched. Empty values fall back to Application Support.
    public static let dataDirectoryEnvironmentKey = "MAGICWALL_DATA_DIR"

    public static var appSupportDirectory: URL {
        if let override = ProcessInfo.processInfo.environment[dataDirectoryEnvironmentKey],
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let expanded = (override as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expanded, isDirectory: true)
        }
        return FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(appSupportFolderName, isDirectory: true)
    }

    public static var libraryRoot: URL {
        appSupportDirectory.appendingPathComponent("Library/Videos", isDirectory: true)
    }

    public static var postersDirectory: URL {
        appSupportDirectory.appendingPathComponent("Library/Posters", isDirectory: true)
    }

    public static var databaseURL: URL {
        appSupportDirectory.appendingPathComponent("magicwall.sqlite")
    }

    /// Creates the directory tree if needed. Safe to call multiple times.
    public static func ensureDirectories() throws {
        let fm = FileManager.default
        for dir in [appSupportDirectory, libraryRoot, postersDirectory] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// Destination inside the managed library for a video being imported.
    public static func managedVideoDestination(id: String, fileExtension: String) -> URL {
        let ext = fileExtension.isEmpty ? "mp4" : fileExtension.lowercased()
        return libraryRoot.appendingPathComponent("\(id).\(ext)")
    }

    public static func posterDestination(for videoID: String) -> URL {
        postersDirectory.appendingPathComponent("\(videoID).jpg")
    }

    /// File extensions we can import with AVFoundation.
    public static let supportedVideoExtensions: Set<String> = ["mp4", "mov", "m4v"]
}
