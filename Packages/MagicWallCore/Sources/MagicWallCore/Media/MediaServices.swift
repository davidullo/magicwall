import AVFoundation
import CoreMedia
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import os

private let mediaLog = Logger(subsystem: "app.magicwall", category: "media")

// MARK: - Probing

public struct AVMediaProbe: MediaProbing {
    public init() {}

    public func probe(url: URL) async throws -> MediaMetadata {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else {
            throw MediaError.noVideoTrack(url)
        }

        let duration = try await asset.load(.duration)
        let naturalSize = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let nominalFPS = Double(try await track.load(.nominalFrameRate))
        let estimatedDataRate = Double(try await track.load(.estimatedDataRate))
        let formatDescriptions = try await track.load(.formatDescriptions)

        var width = Int(abs(naturalSize.width))
        var height = Int(abs(naturalSize.height))
        // Portrait videos store landscape dimensions plus a rotation transform.
        let rotation = atan2(transform.b, transform.a)
        if abs(rotation) == .pi / 2 {
            swap(&width, &height)
        }

        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (attributes?[.size] as? NSNumber)?.int64Value ?? 0

        return MediaMetadata(
            duration: duration.seconds.isFinite ? duration.seconds : 0,
            width: width,
            height: height,
            fps: nominalFPS,
            codec: Self.codecName(for: formatDescriptions.first),
            bitrate: Int(estimatedDataRate),
            fileSize: fileSize
        )
    }

    static func codecName(for format: CMFormatDescription?) -> String? {
        guard let format else { return nil }
        let subType = CMFormatDescriptionGetMediaSubType(format)
        switch subType {
        case kCMVideoCodecType_H264: return "H.264"
        case kCMVideoCodecType_HEVC: return "HEVC"
        case kCMVideoCodecType_AppleProRes422: return "ProRes 422"
        case kCMVideoCodecType_AppleProRes4444: return "ProRes 4444"
        default: return fourCCString(subType)
        }
    }

    static func fourCCString(_ code: FourCharCode) -> String {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF),
            UInt8(code & 0xFF)
        ]
        return String(bytes: bytes, encoding: .ascii) ?? "????"
    }
}

// MARK: - Hashing

public struct SHA256Hasher: FileHashing {
    public init() {}

    public func sha256(of url: URL) async throws -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw MediaError.notReadable(url)
        }
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 4 * 1024 * 1024) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Posters

public struct AVPosterGenerator: ThumbnailGenerating {
    public init() {}

    public func makePoster(
        for videoURL: URL,
        to destination: URL,
        maxWidth: Int = 1280,
        at time: Double? = nil
    ) async throws {
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        guard duration.seconds.isFinite, duration.seconds > 0 else {
            throw MediaError.posterGenerationFailed(videoURL)
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxWidth, height: 0)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

        // A frame at ~10% of the video is usually more representative than frame 0.
        let fallbackTime = min(max(duration.seconds * 0.10, 0), max(duration.seconds - 0.1, 0))
        let requested = time ?? fallbackTime
        let cmTime = CMTime(seconds: requested, preferredTimescale: 600)

        let cgImage: CGImage
        do {
            cgImage = try await generator.image(at: cmTime).image
        } catch {
            mediaLog.error("Poster generation failed for \(videoURL.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
            throw MediaError.posterGenerationFailed(videoURL)
        }

        try AppPaths.ensureDirectories()
        guard let imageDestination = CGImageDestinationCreateWithURL(
            destination as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw MediaError.posterGenerationFailed(videoURL)
        }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.85]
        CGImageDestinationAddImage(imageDestination, cgImage, options as CFDictionary)
        guard CGImageDestinationFinalize(imageDestination) else {
            throw MediaError.posterGenerationFailed(videoURL)
        }
    }
}

// MARK: - Import pipeline

public struct VideoImportService: VideoImporting {
    private let repository: LibraryRepository
    private let prober: MediaProbing
    private let hasher: FileHashing
    private let posters: ThumbnailGenerating

    public init(
        repository: LibraryRepository,
        prober: MediaProbing = AVMediaProbe(),
        hasher: FileHashing = SHA256Hasher(),
        posters: ThumbnailGenerating = AVPosterGenerator()
    ) {
        self.repository = repository
        self.prober = prober
        self.hasher = hasher
        self.posters = posters
    }

    public func importVideos(from urls: [URL]) async throws -> [Video] {
        var results: [Video] = []
        var firstError: Error?

        for fileURL in expand(urls) {
            do {
                if let video = try await importOne(fileURL) {
                    results.append(video)
                }
            } catch {
                mediaLog.error("Import failed for \(fileURL.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
                if firstError == nil { firstError = error }
            }
        }

        if results.isEmpty, let firstError {
            throw firstError
        }
        return results
    }

    /// Expands directories into a flat list of importable video files.
    private func expand(_ urls: [URL]) -> [URL] {
        let fm = FileManager.default
        var files: [URL] = []
        for url in urls {
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                let enumerator = fm.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                )
                while let candidate = enumerator?.nextObject() as? URL {
                    let ext = candidate.pathExtension.lowercased()
                    if AppPaths.supportedVideoExtensions.contains(ext) {
                        files.append(candidate)
                    }
                }
            } else if AppPaths.supportedVideoExtensions.contains(url.pathExtension.lowercased()) {
                files.append(url)
            }
        }
        return files
    }

    private func importOne(_ url: URL) async throws -> Video? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let ext = url.pathExtension.lowercased()
        guard AppPaths.supportedVideoExtensions.contains(ext) else { return nil }

        let metadata = try await prober.probe(url: url)
        let hash = try await hasher.sha256(of: url)

        // Already in the library? Return the existing record.
        if let existing = try repository.video(contentHash: hash) {
            return existing
        }

        let id = UUID().uuidString
        try AppPaths.ensureDirectories()
        let destination = AppPaths.managedVideoDestination(id: id, fileExtension: ext)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: url, to: destination)

        var posterPath: String?
        let posterDestination = AppPaths.posterDestination(for: id)
        do {
            try await posters.makePoster(for: destination, to: posterDestination, maxWidth: 1280, at: nil)
            posterPath = posterDestination.path
        } catch {
            mediaLog.warning("Poster generation skipped for \(url.lastPathComponent, privacy: .public)")
        }

        var video = Video(
            id: id,
            title: url.deletingPathExtension().lastPathComponent,
            filePath: destination.path,
            duration: metadata.duration,
            width: metadata.width,
            height: metadata.height,
            fps: metadata.fps,
            codec: metadata.codec,
            bitrate: metadata.bitrate,
            fileSize: metadata.fileSize,
            contentHash: hash,
            posterPath: posterPath
        )
        video.createdAt = Date()
        video.importedAt = Date()
        try repository.save(video)
        return video
    }
}
