import XCTest
@testable import MagicWallCore

final class StarterWallpapersTests: XCTestCase {

    // MARK: - 1. Shape and order of the bundled catalog

    func testCatalogHasFourWallpapersInExpectedOrder() {
        let catalog = StarterWallpaperCatalog.current
        XCTAssertEqual(catalog.wallpapers.count, 4)
        XCTAssertEqual(
            catalog.wallpapers.map(\.id),
            ["dreamscape", "clover-rainbow", "aurora-forest", "cherry-blossom-spring"]
        )
    }

    func testCatalogVersionIsPositive() {
        XCTAssertGreaterThan(StarterWallpaperCatalog.current.version, 0)
    }

    // MARK: - 2. Structural invariants (the manifest ships real sha256/bytes)

    func testIdentifiersAndFileNamesAreUnique() {
        let wallpapers = StarterWallpaperCatalog.current.wallpapers

        let ids = wallpapers.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "wallpaper ids must be unique")

        let fileNames = wallpapers.map(\.fileName)
        XCTAssertEqual(Set(fileNames).count, fileNames.count, "fileNames must be unique")
    }

    func testEveryWallpaperHasUsableMetadata() {
        for wallpaper in StarterWallpaperCatalog.current.wallpapers {
            XCTAssertFalse(wallpaper.title.isEmpty, "\(wallpaper.id): title must not be empty")
            XCTAssertTrue(
                wallpaper.fileName.hasSuffix(".mp4"),
                "\(wallpaper.id): fileName must be an .mp4, got \(wallpaper.fileName)"
            )
            XCTAssertGreaterThan(wallpaper.width, 0, "\(wallpaper.id): width")
            XCTAssertGreaterThan(wallpaper.height, 0, "\(wallpaper.id): height")
            XCTAssertGreaterThan(wallpaper.duration, 0, "\(wallpaper.id): duration")
            XCTAssertGreaterThanOrEqual(wallpaper.bytes, 0, "\(wallpaper.id): bytes")
        }
    }

    func testBaseURLIsHTTPS() {
        let baseURL = StarterWallpaperCatalog.current.baseURL
        XCTAssertEqual(baseURL.scheme, "https")
        XCTAssertNotNil(baseURL.host)
    }

    /// The manifest that ships in the repository must carry the real checksums
    /// and sizes: the download service refuses anything that does not match.
    func testEveryWallpaperCarriesAChecksumAndSize() {
        for wallpaper in StarterWallpaperCatalog.current.wallpapers {
            XCTAssertEqual(
                wallpaper.sha256.count, 64,
                "\(wallpaper.id): sha256 must be a 64-char hex digest"
            )
            XCTAssertTrue(
                wallpaper.sha256.allSatisfy { $0.isHexDigit },
                "\(wallpaper.id): sha256 must be hexadecimal"
            )
            XCTAssertGreaterThan(wallpaper.bytes, 0, "\(wallpaper.id): bytes must be known")
        }
    }

    func testRemoteURLAppendsFileNameToBaseURL() {
        let catalog = StarterWallpaperCatalog.current
        for wallpaper in catalog.wallpapers {
            XCTAssertEqual(catalog.remoteURL(for: wallpaper), catalog.baseURL.appendingPathComponent(wallpaper.fileName))
            XCTAssertEqual(catalog.remoteURL(for: wallpaper).lastPathComponent, wallpaper.fileName)
        }
    }

    // MARK: - 3. totalBytes

    func testTotalBytesIsSumOfIndividualSizes() {
        let catalog = StarterWallpaperCatalog.current
        XCTAssertEqual(catalog.totalBytes, catalog.wallpapers.map(\.bytes).reduce(0, +))
    }

    // MARK: - 4. Lookup

    func testWallpaperLookupFindsAndMisses() {
        let catalog = StarterWallpaperCatalog.current
        XCTAssertEqual(catalog.wallpaper(id: "dreamscape")?.fileName, "dreamscape.mp4")
        XCTAssertNotNil(catalog.wallpaper(id: "cherry-blossom-spring"))
        XCTAssertNil(catalog.wallpaper(id: "does-not-exist"))
        XCTAssertNil(catalog.wallpaper(id: ""))
    }

    // MARK: - 5. VideoSource

    func testStarterVideoSourceRawValueRoundTrips() {
        XCTAssertEqual(VideoSource.starter.rawValue, "starter")
        XCTAssertEqual(VideoSource(rawValue: "starter"), .starter)
        XCTAssertEqual(VideoSource(rawValue: VideoSource.starter.rawValue), .starter)
        XCTAssertEqual(VideoSource(rawValue: VideoSource.imported.rawValue), .imported)
        XCTAssertEqual(VideoSource(rawValue: VideoSource.community.rawValue), .community)
    }

    func testVideoSourceEncodesRawValue() throws {
        let data = try JSONEncoder().encode(VideoSource.starter)
        XCTAssertEqual(String(data: data, encoding: .utf8), "\"starter\"")
    }

    func testUnknownVideoSourceDecodesAsImported() throws {
        let json = Data(#"{"source":"qualcosa-di-ignoto"}"#.utf8)
        let decoded = try JSONDecoder().decode(SourceEnvelope.self, from: json)
        XCTAssertEqual(decoded.source, .imported)
    }

    func testKnownAndUnknownSourcesDecodeTolerantly() throws {
        for (raw, expected) in [("imported", VideoSource.imported),
                                ("community", .community),
                                ("starter", .starter),
                                ("legacy-value", .imported)] {
            let json = Data(#"{"source":"\#(raw)"}"#.utf8)
            let decoded = try JSONDecoder().decode(SourceEnvelope.self, from: json)
            XCTAssertEqual(decoded.source, expected, "source \(raw)")
        }
    }

    /// Minimal shape that exercises `VideoSource` through a real `Codable` record.
    private struct SourceEnvelope: Codable {
        var source: VideoSource
    }
}
