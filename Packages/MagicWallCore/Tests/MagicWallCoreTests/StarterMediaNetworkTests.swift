import AVFoundation
import XCTest

@testable import MagicWallCore

/// Opt-in end-to-end check of the hosted starter media: downloads one asset
/// from the `starter-v1` release, verifies the manifest checksum/size and makes
/// sure AVFoundation can actually probe it and generate a poster — the same
/// building blocks `StarterWallpaperService` uses inside the app.
///
/// Network tests are excluded from the default suite (they need the release to
/// be reachable); run them explicitly with:
///
///     MW_NETWORK_TESTS=1 swift test --filter StarterMediaNetworkTests
final class StarterMediaNetworkTests: XCTestCase {
    private var networkTestsEnabled: Bool {
        ProcessInfo.processInfo.environment["MW_NETWORK_TESTS"] == "1"
    }

    func testHostedAssetDownloadsMatchesTheManifestAndProbes() async throws {
        try XCTSkipUnless(networkTestsEnabled, "set MW_NETWORK_TESTS=1 to run network tests")

        let catalog = StarterWallpaperCatalog.current
        let wallpaper = try XCTUnwrap(
            catalog.wallpaper(id: "dreamscape"),
            "the catalog must carry the dreamscape entry"
        )

        let (temporaryURL, response) = try await URLSession.shared.download(
            from: catalog.remoteURL(for: wallpaper)
        )
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 200, "the release asset must be publicly downloadable")

        let attributes = try FileManager.default.attributesOfItem(atPath: temporaryURL.path)
        let size = (attributes[.size] as? NSNumber)?.int64Value
        XCTAssertEqual(size, wallpaper.bytes, "downloaded size must match the manifest")

        let digest = try await SHA256Hasher().sha256(of: temporaryURL)
        XCTAssertEqual(
            digest.lowercased(),
            wallpaper.sha256.lowercased(),
            "downloaded file must match the manifest checksum"
        )

        // AVFoundation inspects the file name too: the service moves the asset
        // to "<id>.mp4" before probing, so mirror that step here.
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("mw-starter-net-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        let assetURL = scratch.appendingPathComponent("\(wallpaper.id).mp4")
        try FileManager.default.copyItem(at: temporaryURL, to: assetURL)

        let metadata = try await AVMediaProbe().probe(url: assetURL)
        XCTAssertEqual(metadata.width, wallpaper.width)
        XCTAssertEqual(metadata.height, wallpaper.height)
        XCTAssertEqual(metadata.codec, "HEVC", "the starter encodes must stay hvc1 HEVC")
        XCTAssertGreaterThan(metadata.duration, 0)

        let poster = scratch.appendingPathComponent("poster.jpg")

        try await AVPosterGenerator().makePoster(
            for: assetURL,
            to: poster,
            maxWidth: 1280,
            at: nil
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: poster.path),
            "a poster must be generated from the downloaded asset"
        )
    }
}
