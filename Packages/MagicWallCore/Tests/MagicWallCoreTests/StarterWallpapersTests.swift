import XCTest
@testable import MagicWallCore

final class StarterWallpapersTests: XCTestCase {

    // MARK: - 1. Shape and order of the bundled catalog

    func testCatalogHasFiveWallpapersInExpectedOrder() {
        let catalog = StarterWallpaperCatalog.current
        XCTAssertEqual(catalog.wallpapers.count, 5)
        XCTAssertEqual(
            catalog.wallpapers.map(\.id),
            [
                "dreamscape",
                "clover-rainbow",
                "aurora-forest",
                "cherry-blossom-spring",
                "colorful-underwater-scene"
            ]
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

        let fileNames = wallpapers.flatMap { $0.variants.map(\.fileName) }
        XCTAssertEqual(Set(fileNames).count, fileNames.count, "variant file names must be unique")
    }

    func testEveryWallpaperHasUsableMetadataAndVariants() {
        for wallpaper in StarterWallpaperCatalog.current.wallpapers {
            XCTAssertFalse(wallpaper.title.isEmpty, "\(wallpaper.id): title must not be empty")
            XCTAssertGreaterThan(wallpaper.width, 0, "\(wallpaper.id): width")
            XCTAssertGreaterThan(wallpaper.height, 0, "\(wallpaper.id): height")
            XCTAssertGreaterThan(wallpaper.duration, 0, "\(wallpaper.id): duration")
            XCTAssertFalse(wallpaper.variants.isEmpty, "\(wallpaper.id): at least one variant")

            for variant in wallpaper.variants {
                XCTAssertTrue(
                    variant.fileName.hasSuffix(".mp4"),
                    "\(wallpaper.id)/\(variant.quality): fileName must be an .mp4, got \(variant.fileName)"
                )
            }
        }
    }

    func testEveryWallpaperShipsHighAndCompactTiers() {
        for wallpaper in StarterWallpaperCatalog.current.wallpapers {
            XCTAssertNotNil(wallpaper.variant(.high), "\(wallpaper.id): high tier")
            XCTAssertNotNil(wallpaper.variant(.compact), "\(wallpaper.id): compact tier")

            let high = wallpaper.variant(.high)?.bytes ?? 0
            let compact = wallpaper.variant(.compact)?.bytes ?? 0
            XCTAssertGreaterThan(high, compact, "\(wallpaper.id): the high tier must be the bigger file")
        }
    }

    func testBaseURLIsHTTPS() {
        let baseURL = StarterWallpaperCatalog.current.baseURL
        XCTAssertEqual(baseURL.scheme, "https")
        XCTAssertNotNil(baseURL.host)
    }

    /// The manifest that ships in the repository must carry the real checksums
    /// and sizes: the download service refuses anything that does not match.
    func testEveryVariantCarriesAChecksumAndSize() {
        for wallpaper in StarterWallpaperCatalog.current.wallpapers {
            for variant in wallpaper.variants {
                XCTAssertEqual(
                    variant.sha256.count, 64,
                    "\(wallpaper.id)/\(variant.quality): sha256 must be a 64-char hex digest"
                )
                XCTAssertTrue(
                    variant.sha256.allSatisfy { $0.isHexDigit },
                    "\(wallpaper.id)/\(variant.quality): sha256 must be hexadecimal"
                )
                XCTAssertGreaterThan(variant.bytes, 0, "\(wallpaper.id)/\(variant.quality): bytes must be known")
            }
        }
    }

    func testRemoteURLAppendsFileNameToBaseURL() {
        let catalog = StarterWallpaperCatalog.current
        for wallpaper in catalog.wallpapers {
            for variant in wallpaper.variants {
                let url = catalog.remoteURL(for: wallpaper, quality: variant.quality)
                XCTAssertEqual(url, catalog.baseURL.appendingPathComponent(variant.fileName))
                XCTAssertEqual(url.lastPathComponent, variant.fileName)
            }
            XCTAssertEqual(
                catalog.remoteURL(for: wallpaper),
                catalog.remoteURL(for: wallpaper, quality: .high),
                "the plain remoteURL is the recommended-tier file"
            )
        }
    }

    // MARK: - 3. totalBytes

    func testTotalBytesIsSumOfIndividualSizesPerTier() {
        let catalog = StarterWallpaperCatalog.current

        for quality in StarterWallpaperQuality.allCases {
            let expected = catalog.wallpapers
                .compactMap { $0.variant(quality)?.bytes }
                .reduce(Int64(0), +)
            XCTAssertEqual(catalog.totalBytes(for: quality), expected, "tier \(quality)")
        }

        XCTAssertEqual(catalog.totalBytes, catalog.totalBytes(for: .default))
    }

    // MARK: - 4. Lookup and variants

    func testWallpaperLookupFindsAndMisses() {
        let catalog = StarterWallpaperCatalog.current
        XCTAssertEqual(catalog.wallpaper(id: "dreamscape")?.variant(.high)?.fileName, "dreamscape-high.mp4")
        XCTAssertEqual(
            catalog.wallpaper(id: "colorful-underwater-scene")?.variant(.compact)?.fileName,
            "colorful-underwater-scene-compact.mp4"
        )
        XCTAssertNotNil(catalog.wallpaper(id: "cherry-blossom-spring"))
        XCTAssertNil(catalog.wallpaper(id: "does-not-exist"))
        XCTAssertNil(catalog.wallpaper(id: ""))
    }

    func testInstallableVariantFallsBackWhenATierIsMissing() {
        let single = StarterWallpaper(
            id: "solo",
            title: "Solo",
            width: 3840,
            height: 2160,
            duration: 10,
            variants: [
                StarterWallpaperVariant(quality: .compact, fileName: "solo.mp4", sha256: "ab", bytes: 1)
            ]
        )
        XCTAssertEqual(single.installableVariant(.high)?.quality, .compact)
        XCTAssertEqual(single.installableVariant(.compact)?.quality, .compact)
    }

    // MARK: - 5. Manifest decoding (v2 variants and v1 flat shape)

    func testV2ManifestDecodesVariants() throws {
        let json = Data("""
        {
          "version": 2,
          "baseURL": "https://example.com/",
          "wallpapers": [
            {
              "id": "demo",
              "title": "Demo",
              "width": 3840,
              "height": 2160,
              "duration": 12.5,
              "variants": [
                { "quality": "high", "fileName": "demo-high.mp4", "sha256": "aa", "bytes": 200 },
                { "quality": "compact", "fileName": "demo-compact.mp4", "sha256": "bb", "bytes": 100 }
              ]
            }
          ]
        }
        """.utf8)

        let catalog = try JSONDecoder().decode(StarterWallpaperCatalog.self, from: json)
        XCTAssertEqual(catalog.version, 2)
        let wallpaper = try XCTUnwrap(catalog.wallpaper(id: "demo"))
        XCTAssertEqual(wallpaper.variant(.high)?.bytes, 200)
        XCTAssertEqual(wallpaper.variant(.compact)?.fileName, "demo-compact.mp4")
    }

    /// The old, flat v1 manifest keeps loading: its single file becomes the
    /// compact tier, and the high tier falls back to it.
    func testV1ManifestDecodesAsASingleCompactVariant() throws {
        let json = Data("""
        {
          "version": 1,
          "baseURL": "https://example.com/starter-v1/",
          "wallpapers": [
            {
              "id": "legacy",
              "title": "Legacy",
              "fileName": "legacy.mp4",
              "sha256": "cc",
              "bytes": 42,
              "width": 3840,
              "height": 2160,
              "duration": 9
            }
          ]
        }
        """.utf8)

        let catalog = try JSONDecoder().decode(StarterWallpaperCatalog.self, from: json)
        let wallpaper = try XCTUnwrap(catalog.wallpaper(id: "legacy"))
        XCTAssertEqual(wallpaper.availableQualities, [.compact])
        XCTAssertEqual(wallpaper.variant(.compact)?.fileName, "legacy.mp4")
        XCTAssertEqual(wallpaper.installableVariant(.high)?.fileName, "legacy.mp4")
    }

    func testEncodingUsesTheV2ShapeWithVariantsOnly() throws {
        let wallpaper = StarterWallpaper(
            id: "demo",
            title: "Demo",
            width: 3840,
            height: 2160,
            duration: 12.5,
            variants: [
                StarterWallpaperVariant(quality: .high, fileName: "demo-high.mp4", sha256: "aa", bytes: 200)
            ]
        )

        let data = try JSONEncoder().encode(wallpaper)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(object["variants"])
        XCTAssertNil(object["fileName"], "the v1 flat fields must not be written anymore")
    }

    // MARK: - 6. VideoSource

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
