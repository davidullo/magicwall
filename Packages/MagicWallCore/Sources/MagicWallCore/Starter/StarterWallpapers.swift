import Foundation

/// Quality tier of a downloadable starter wallpaper.
public enum StarterWallpaperQuality: String, Codable, CaseIterable, Sendable {
    /// Smallest files (the original 6 Mbps pack): for slow connections.
    case compact
    /// Full-quality encode from the 4K masters: the recommended tier.
    case high

    /// Tier used when the user never picked one.
    public static let `default`: StarterWallpaperQuality = .high

    /// Every tier a catalog may ship, from most to least compressed. Used by
    /// the UI to offer the choice in a stable order.
    public static let allCasesInOrder: [StarterWallpaperQuality] = [.high, .compact]
}

/// One downloadable file of a starter wallpaper.
public struct StarterWallpaperVariant: Codable, Hashable, Sendable {
    public var quality: StarterWallpaperQuality
    public var fileName: String
    public var sha256: String
    public var bytes: Int64

    public init(quality: StarterWallpaperQuality, fileName: String, sha256: String, bytes: Int64) {
        self.quality = quality
        self.fileName = fileName
        self.sha256 = sha256
        self.bytes = bytes
    }
}

/// A downloadable "starter" wallpaper described by the bundled catalog.
public struct StarterWallpaper: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var width: Int
    public var height: Int
    public var duration: Double
    /// One file per quality tier, at least one.
    public var variants: [StarterWallpaperVariant]

    public init(
        id: String,
        title: String,
        width: Int,
        height: Int,
        duration: Double,
        variants: [StarterWallpaperVariant]
    ) {
        self.id = id
        self.title = title
        self.width = width
        self.height = height
        self.duration = duration
        self.variants = variants
    }

    /// First variant carrying `quality`, when the catalog ships it.
    public func variant(_ quality: StarterWallpaperQuality) -> StarterWallpaperVariant? {
        variants.first { $0.quality == quality }
    }

    /// Variant to download for a tier: the requested one when available, the
    /// only one otherwise — so a single-variant catalog keeps working.
    public func installableVariant(_ quality: StarterWallpaperQuality) -> StarterWallpaperVariant? {
        variant(quality) ?? variants.first
    }

    /// Qualities actually shipped for this wallpaper, in catalog order.
    public var availableQualities: [StarterWallpaperQuality] {
        variants.map(\.quality)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case width
        case height
        case duration
        case variants
        // Flat fields of the v1 manifest (single file per wallpaper).
        case fileName
        case sha256
        case bytes
    }

    /// Decoding survives both manifest shapes: v2 (`variants`) and v1 (flat
    /// `fileName`/`sha256`/`bytes`, which decode as a single compact variant).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.width = try container.decode(Int.self, forKey: .width)
        self.height = try container.decode(Int.self, forKey: .height)
        self.duration = try container.decode(Double.self, forKey: .duration)

        if let variants = try container.decodeIfPresent([StarterWallpaperVariant].self, forKey: .variants),
           !variants.isEmpty {
            self.variants = variants
        } else {
            let fileName = try container.decode(String.self, forKey: .fileName)
            let sha256 = try container.decode(String.self, forKey: .sha256)
            let bytes = try container.decode(Int64.self, forKey: .bytes)
            self.variants = [
                StarterWallpaperVariant(
                    quality: .compact,
                    fileName: fileName,
                    sha256: sha256,
                    bytes: bytes
                )
            ]
        }
    }

    /// Encodes the v2 shape; the flat v1 fields are decode-only.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(duration, forKey: .duration)
        try container.encode(variants, forKey: .variants)
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

    /// Total on-disk size of the recommended tier of every wallpaper.
    public var totalBytes: Int64 {
        totalBytes(for: .default)
    }

    /// Total on-disk size of one quality tier across every wallpaper.
    public func totalBytes(for quality: StarterWallpaperQuality) -> Int64 {
        wallpapers.reduce(0) { total, wallpaper in
            total + (wallpaper.installableVariant(quality)?.bytes ?? 0)
        }
    }

    /// Look up a wallpaper by its stable identifier.
    public func wallpaper(id: String) -> StarterWallpaper? {
        wallpapers.first { $0.id == id }
    }

    /// Absolute remote location of a wallpaper's recommended-tier file.
    public func remoteURL(for wallpaper: StarterWallpaper) -> URL {
        remoteURL(for: wallpaper, quality: .default)
    }

    /// Absolute remote location of a wallpaper's file for a quality tier. Falls
    /// back to whichever variant the catalog does ship.
    public func remoteURL(for wallpaper: StarterWallpaper, quality: StarterWallpaperQuality) -> URL {
        let variant = wallpaper.installableVariant(quality)
        return baseURL.appendingPathComponent(variant?.fileName ?? "")
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
            MagicWallCore: failed to decode "\(resourceName).\(resourceExtension)": \(error)
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
