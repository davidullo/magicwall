import Foundation

/// A downloadable "starter" wallpaper described by the bundled catalog.
public struct StarterWallpaper: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var fileName: String
    public var sha256: String
    public var bytes: Int64
    public var width: Int
    public var height: Int
    public var duration: Double

    public init(
        id: String,
        title: String,
        fileName: String,
        sha256: String,
        bytes: Int64,
        width: Int,
        height: Int,
        duration: Double
    ) {
        self.id = id
        self.title = title
        self.fileName = fileName
        self.sha256 = sha256
        self.bytes = bytes
        self.width = width
        self.height = height
        self.duration = duration
    }
}

/// The bundled catalog of starter wallpapers (`starter-wallpapers.json`).
public struct StarterWallpaperCatalog: Sendable {
    /// Resource file name inside the package bundle.
    public static let resourceName = "starter-wallpapers"
    public static let resourceExtension = "json"

    public let version: Int
    public let baseURL: URL
    public let wallpapers: [StarterWallpaper]

    public init(version: Int, baseURL: URL, wallpapers: [StarterWallpaper]) {
        self.version = version
        self.baseURL = baseURL
        self.wallpapers = wallpapers
    }

    /// Total on-disk size of every wallpaper in the catalog.
    public var totalBytes: Int64 {
        wallpapers.reduce(0) { $0 + $1.bytes }
    }

    /// Look up a wallpaper by its stable identifier.
    public func wallpaper(id: String) -> StarterWallpaper? {
        wallpapers.first { $0.id == id }
    }

    /// Absolute remote location of a wallpaper's video file.
    public func remoteURL(for wallpaper: StarterWallpaper) -> URL {
        baseURL.appendingPathComponent(wallpaper.fileName)
    }

    /// Catalog loaded once from the package bundle (`Bundle.module`).
    ///
    /// Fails loudly if the resource is missing or malformed: the catalog is a
    /// build-time invariant, not user data, so a silent empty catalog would
    /// hide packaging regressions.
    public static let current: StarterWallpaperCatalog = loadCurrent()

    private static func loadCurrent() -> StarterWallpaperCatalog {
        guard let url = Bundle.module.url(
            forResource: resourceName,
            withExtension: resourceExtension
        ) else {
            fatalError("""
            MagicWallCore: missing bundled resource "\(resourceName).\(resourceExtension)". \
            The package target must process Sources/MagicWallCore/Resources (see Package.swift).
            """)
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            fatalError("""
            MagicWallCore: could not read "\(resourceName).\(resourceExtension)" at \(url.path): \(error)
            """)
        }

        do {
            return try JSONDecoder().decode(StarterWallpaperCatalog.self, from: data)
        } catch {
            fatalError("""
            MagicWallCore: failed to decode "\(resourceName).\(resourceExtension)" at \(url.path): \(error)
            """)
        }
    }
}

extension StarterWallpaperCatalog: Codable {
    private enum CodingKeys: String, CodingKey {
        case version
        case baseURL
        case wallpapers
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .version)
        let baseURL = try container.decode(URL.self, forKey: .baseURL)
        let wallpapers = try container.decode([StarterWallpaper].self, forKey: .wallpapers)
        self.init(version: version, baseURL: baseURL, wallpapers: wallpapers)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(baseURL, forKey: .baseURL)
        try container.encode(wallpapers, forKey: .wallpapers)
    }
}
