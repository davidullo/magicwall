import Foundation

/// Where a video came from. `community` is reserved for the future online catalog,
/// `starter` marks videos downloaded from the bundled starter catalog.
public enum VideoSource: String, Codable, Sendable, CaseIterable {
    case imported
    case community
    case starter

    /// Tolerant decoding: any value the schema does not know about (a source
    /// written by a newer version, or corrupted data) degrades to `.imported`
    /// instead of failing the whole `Video` record.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = VideoSource(rawValue: raw) ?? .imported
    }
}

/// A wallpaper video in the local library.
public struct Video: Codable, Identifiable, Hashable, Sendable {
    public static let databaseTableName = "videos"

    public var id: String
    public var title: String
    public var filePath: String
    public var duration: Double
    public var width: Int
    public var height: Int
    public var fps: Double
    public var codec: String?
    public var bitrate: Int
    public var fileSize: Int64
    public var contentHash: String?
    public var posterPath: String?
    public var source: VideoSource
    public var createdAt: Date
    public var importedAt: Date
    public var lastPlayedAt: Date?

    public init(
        id: String = UUID().uuidString,
        title: String,
        filePath: String,
        duration: Double = 0,
        width: Int = 0,
        height: Int = 0,
        fps: Double = 0,
        codec: String? = nil,
        bitrate: Int = 0,
        fileSize: Int64 = 0,
        contentHash: String? = nil,
        posterPath: String? = nil,
        source: VideoSource = .imported,
        createdAt: Date = Date(),
        importedAt: Date = Date(),
        lastPlayedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.filePath = filePath
        self.duration = duration
        self.width = width
        self.height = height
        self.fps = fps
        self.codec = codec
        self.bitrate = bitrate
        self.fileSize = fileSize
        self.contentHash = contentHash
        self.posterPath = posterPath
        self.source = source
        self.createdAt = createdAt
        self.importedAt = importedAt
        self.lastPlayedAt = lastPlayedAt
    }
}

extension Video {
    public var fileURL: URL { URL(fileURLWithPath: filePath) }
    public var posterURL: URL? { posterPath.map { URL(fileURLWithPath: $0) } }

    public var resolutionLabel: String {
        guard width > 0, height > 0 else { return "—" }
        return "\(width)×\(height)"
    }

    public var durationLabel: String {
        guard duration.isFinite, duration > 0 else { return "—" }
        let total = Int(duration.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    public var fileSizeLabel: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    public var isPortrait: Bool { height > width }
}

/// A user-defined category for grouping videos.
public struct VideoCategory: Codable, Identifiable, Hashable, Sendable {
    public static let databaseTableName = "categories"

    public var id: Int64?
    public var name: String
    public var slug: String
    public var sortOrder: Int

    public init(id: Int64? = nil, name: String, slug: String, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.slug = slug
        self.sortOrder = sortOrder
    }

    public static func makeSlug(from name: String) -> String {
        let lowered = name.lowercased()
        let allowed = lowered.map { ch -> Character in
            if ch.isLetter || ch.isNumber { return ch }
            return "-"
        }
        let slug = String(allowed)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return slug.isEmpty ? UUID().uuidString.lowercased() : slug
    }
}

/// A named, ordered collection of videos.
public struct Playlist: Codable, Identifiable, Hashable, Sendable {
    public static let databaseTableName = "playlists"

    public var id: Int64?
    public var name: String
    public var createdAt: Date

    public init(id: Int64? = nil, name: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}

/// Which video (or playlist) is assigned to a given display.
public struct ScreenAssignment: Codable, Identifiable, Hashable, Sendable {
    public static let databaseTableName = "screen_assignments"

    public var id: String
    public var screenKey: String
    public var videoId: String?
    public var playlistId: Int64?
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        screenKey: String,
        videoId: String? = nil,
        playlistId: Int64? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.screenKey = screenKey
        self.videoId = videoId
        self.playlistId = playlistId
        self.updatedAt = updatedAt
    }
}
