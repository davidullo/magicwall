import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import MagicWallCore

/// Media pipeline tests: probe, hashing, poster generation and the import
/// service (copy/rollback/dedup).
final class MediaTests: XCTestCase {
    private var tempDirectory: URL!
    /// Artifacts written into the real managed library, removed on tearDown.
    private var libraryArtifacts: [URL] = []

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MagicWallMediaTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        libraryArtifacts = []
    }

    override func tearDownWithError() throws {
        let fm = FileManager.default
        for url in libraryArtifacts where fm.fileExists(atPath: url.path) {
            try? fm.removeItem(at: url)
        }
        if let tempDirectory, fm.fileExists(atPath: tempDirectory.path) {
            try? fm.removeItem(at: tempDirectory)
        }
    }

    // MARK: - Probe

    func testProbeReadsDimensionsDurationAndCodec() async throws {
        let url = tempDirectory.appendingPathComponent("probe.mp4")
        try await makeTestVideo(at: url, width: 320, height: 240, fps: 30, seconds: 1.5)

        let metadata = try await AVMediaProbe().probe(url: url)

        XCTAssertEqual(metadata.width, 320)
        XCTAssertEqual(metadata.height, 240)
        XCTAssertEqual(metadata.duration, 1.5, accuracy: 0.3)
        XCTAssertEqual(metadata.fps, 30, accuracy: 1.0)
        XCTAssertEqual(metadata.codec, "H.264")
        XCTAssertGreaterThan(metadata.fileSize, 0)
        XCTAssertGreaterThan(metadata.bitrate, 0)
    }

    // MARK: - Hashing

    func testSHA256IsStableForLargeFile() async throws {
        let url = tempDirectory.appendingPathComponent("random-8mb.bin")
        var data = Data(count: 8 * 1024 * 1024)
        data.withUnsafeMutableBytes { buffer in
            if let base = buffer.baseAddress {
                arc4random_buf(base, buffer.count)
            }
        }
        try data.write(to: url)

        let hasher = SHA256Hasher()
        let first = try await hasher.sha256(of: url)
        let second = try await hasher.sha256(of: url)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.count, 64)
        XCTAssertTrue(first.allSatisfy { $0.isHexDigit })
    }

    // MARK: - Poster

    func testPosterIsValidJPEGAndCreatesDirectory() async throws {
        let videoURL = tempDirectory.appendingPathComponent("poster.mp4")
        try await makeTestVideo(at: videoURL)

        // Nested, non-existent directory: the generator must create it.
        let posterURL = tempDirectory
            .appendingPathComponent("nested", isDirectory: true)
            .appendingPathComponent("deeper", isDirectory: true)
            .appendingPathComponent("poster.jpg")

        try await AVPosterGenerator().makePoster(for: videoURL, to: posterURL, maxWidth: 320, at: nil)

        XCTAssertTrue(FileManager.default.fileExists(atPath: posterURL.path))

        guard let source = CGImageSourceCreateWithURL(posterURL as CFURL, nil) else {
            XCTFail("Poster is not a readable image")
            return
        }
        XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.jpeg.identifier)
        XCTAssertNotNil(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    // MARK: - Import

    func testImportCreatesRecordManagedFilesAndSkipsNonVideo() async throws {
        let source = tempDirectory.appendingPathComponent("clip.mp4")
        try await makeTestVideo(at: source)

        let ignored = tempDirectory.appendingPathComponent("notes.txt")
        try "not a video".write(to: ignored, atomically: true, encoding: .utf8)

        let repository = GRDBLibraryRepository(database: try AppDatabase.inMemory())
        let service = VideoImportService(repository: repository)

        let imported = try await service.importVideos(from: [source, ignored])
        XCTAssertEqual(imported.count, 1)

        let video = try XCTUnwrap(imported.first)
        trackLibraryArtifacts(for: video)

        let managedURL = URL(fileURLWithPath: video.filePath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: managedURL.path))
        XCTAssertTrue(video.filePath.hasPrefix(AppPaths.libraryRoot.path))

        XCTAssertEqual(video.width, 320)
        XCTAssertEqual(video.height, 240)
        XCTAssertEqual(video.duration, 1.5, accuracy: 0.3)
        XCTAssertEqual(video.codec, "H.264")
        XCTAssertNotNil(video.contentHash)

        let posterPath = try XCTUnwrap(video.posterPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: posterPath))

        XCTAssertEqual(try repository.videoCount(), 1)
    }

    func testSecondImportReturnsExistingRecordWithoutCopyingAgain() async throws {
        let source = tempDirectory.appendingPathComponent("dupe.mp4")
        try await makeTestVideo(at: source)

        let repository = GRDBLibraryRepository(database: try AppDatabase.inMemory())
        let service = VideoImportService(repository: repository)

        let first = try await service.importVideos(from: [source])
        let firstVideo = try XCTUnwrap(first.first)
        trackLibraryArtifacts(for: firstVideo)

        let managedURL = URL(fileURLWithPath: firstVideo.filePath)
        let modificationDate = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: managedURL.path)[.modificationDate] as? Date
        )

        let second = try await service.importVideos(from: [source])
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(second.first?.id, firstVideo.id)
        XCTAssertEqual(try repository.videoCount(), 1)

        // The managed file was not rewritten.
        let modificationDateAfter = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: managedURL.path)[.modificationDate] as? Date
        )
        XCTAssertEqual(modificationDate, modificationDateAfter)
    }

    func testImportPreservesOriginalCreationDate() async throws {
        let source = tempDirectory.appendingPathComponent("dated.mp4")
        try await makeTestVideo(at: source)

        let originalDate = Date(timeIntervalSince1970: 1_600_000_000)
        try FileManager.default.setAttributes([.creationDate: originalDate], ofItemAtPath: source.path)

        let repository = GRDBLibraryRepository(database: try AppDatabase.inMemory())
        let service = VideoImportService(repository: repository)

        let imported = try await service.importVideos(from: [source])
        let video = try XCTUnwrap(imported.first)
        trackLibraryArtifacts(for: video)

        let copiedDate = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: video.filePath)[.creationDate] as? Date
        )
        XCTAssertEqual(copiedDate.timeIntervalSince1970, originalDate.timeIntervalSince1970, accuracy: 1)
    }

    func testCorruptVideoFailsAloneButIsSkippedWhenMixed() async throws {
        let valid = tempDirectory.appendingPathComponent("valid.mp4")
        try await makeTestVideo(at: valid)

        let corrupt = tempDirectory.appendingPathComponent("corrupt.mp4")
        var garbage = Data(count: 4096)
        garbage.withUnsafeMutableBytes { buffer in
            if let base = buffer.baseAddress { arc4random_buf(base, buffer.count) }
        }
        try garbage.write(to: corrupt)

        let repository = GRDBLibraryRepository(database: try AppDatabase.inMemory())
        let service = VideoImportService(repository: repository)

        // Alone: the corrupt file is the only element, so the error surfaces.
        do {
            _ = try await service.importVideos(from: [corrupt])
            XCTFail("Expected importVideos to throw for a single corrupt file")
        } catch {
            // expected
        }
        XCTAssertEqual(try repository.videoCount(), 0)

        // Mixed with a valid file: the corrupt one is skipped without failing.
        let imported = try await service.importVideos(from: [corrupt, valid])
        XCTAssertEqual(imported.count, 1)
        let video = try XCTUnwrap(imported.first)
        trackLibraryArtifacts(for: video)
        XCTAssertTrue(FileManager.default.fileExists(atPath: video.filePath))
        XCTAssertEqual(try repository.videoCount(), 1)
    }

    // MARK: - Helpers

    /// Remembers files written into the real managed library so tearDown can
    /// remove them and keep the user's library clean.
    private func trackLibraryArtifacts(for video: Video) {
        libraryArtifacts.append(URL(fileURLWithPath: video.filePath))
        if let posterPath = video.posterPath {
            libraryArtifacts.append(URL(fileURLWithPath: posterPath))
        }
    }

    private enum TestMediaError: Error {
        case writerCannotAddInput
        case writerDidNotStart
        case pixelBufferPoolUnavailable
        case pixelBufferCreationFailed
        case appendFailed
        case writingFailed
    }

    /// Writes a short H.264, audio-less test clip with AVAssetWriter.
    private func makeTestVideo(
        at url: URL,
        width: Int = 320,
        height: Int = 240,
        fps: Int = 30,
        seconds: Double = 1.5
    ) async throws {
        try? FileManager.default.removeItem(at: url)

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false

        let sourceAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: sourceAttributes
        )

        guard writer.canAdd(input) else { throw TestMediaError.writerCannotAddInput }
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? TestMediaError.writerDidNotStart
        }
        writer.startSession(atSourceTime: .zero)

        let frameCount = max(1, Int((Double(fps) * seconds).rounded()))
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))

        for frame in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            guard let pool = adaptor.pixelBufferPool else {
                throw TestMediaError.pixelBufferPoolUnavailable
            }
            var pixelBuffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer) == kCVReturnSuccess,
                  let buffer = pixelBuffer
            else {
                throw TestMediaError.pixelBufferCreationFailed
            }
            Self.fill(buffer, frame: frame)

            let time = CMTimeMultiply(frameDuration, multiplier: Int32(frame))
            guard adaptor.append(buffer, withPresentationTime: time) else {
                throw writer.error ?? TestMediaError.appendFailed
            }
        }

        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw writer.error ?? TestMediaError.writingFailed
        }
    }

    /// Fills a BGRA pixel buffer with a moving pattern.
    private static func fill(_ buffer: CVPixelBuffer, frame: Int) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }

        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let pixels = base.assumingMemoryBound(to: UInt8.self)

        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                pixels[offset] = UInt8((x + frame * 5) % 256)
                pixels[offset + 1] = UInt8((y + frame * 3) % 256)
                pixels[offset + 2] = UInt8((frame * 7) % 256)
                pixels[offset + 3] = 255
            }
        }
    }
}
