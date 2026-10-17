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

        let seconds = duration.seconds
        var bitrate = Int(estimatedDataRate)
        // Some containers don't carry a data rate: estimate it from size/duration.
        if bitrate <= 0, seconds.isFinite, seconds > 0, fileSize > 0 {
            bitrate = Int((Double(fileSize) * 8 / seconds).rounded())
        }

        return MediaMetadata(
            duration: seconds.isFinite ? seconds : 0,
            width: width,
            height: height,
            fps: nominalFPS,
            codec: Self.codecName(for: formatDescriptions.first),
            bitrate: bitrate,
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

    /// Streams the file in 4 MB chunks so large videos never get loaded in memory.
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
        let seconds = duration.seconds
        guard seconds.isFinite, seconds > 0 else {
            throw MediaError.posterGenerationFailed(videoURL)
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxWidth, height: 0)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

        // Primary request: an explicit time, or ~10% into the video (more
        // representative than frame 0). Very short clips just use 0s.
        let requested: Double
        if let time {
            requested = time
        } else if seconds < 1.0 {
            requested = 0
        } else {
            requested = min(max(seconds * 0.10, 0), max(seconds - 0.1, 0))
        }

        // Fallbacks: 0s then 1s (for clips long enough to have a frame there).
        var candidates: [Double] = [requested, 0]
        if seconds >= 1.0 { candidates.append(1) }

        var cgImage: CGImage?
        var seen = Set<Int64>()
        var lastError: Error?
        for candidate in candidates {
            let clamped = min(max(candidate, 0), max(seconds - 0.001, 0))
            let key = Int64((clamped * 1000).rounded())
            guard seen.insert(key).inserted else { continue }

            let cmTime = CMTime(seconds: clamped, preferredTimescale: 600)
            do {
                cgImage = try await generator.image(at: cmTime).image
                break
            } catch {
                lastError = error
                mediaLog.warning(
                    "Poster frame at \(clamped, privacy: .public)s failed for \(videoURL.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)"
                )
            }
        }

        guard let cgImage else {
            mediaLog.error(
                "Poster generation failed for \(videoURL.lastPathComponent, privacy: .public): \(String(describing: lastError), privacy: .public)"
            )
            throw MediaError.posterGenerationFailed(videoURL)
        }

        let data = try Self.encodeJPEG(cgImage, sourceURL: videoURL)

        // Create the destination directory if needed, then write atomically.
        let directory = destination.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try data.write(to: destination, options: .atomic)
    }

    /// Encodes a frame to JPEG bytes in memory so the file can be written atomically.
    private static func encodeJPEG(_ image: CGImage, sourceURL: URL) throws -> Data {
        guard let mutableData = CFDataCreateMutable(nil, 0),
              let imageDestination = CGImageDestinationCreateWithData(
                  mutableData,
                  UTType.jpeg.identifier as CFString,
                  1,
                  nil
              )
        else {
            throw MediaError.posterGenerationFailed(sourceURL)
        }

        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.85]
        CGImageDestinationAddImage(imageDestination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(imageDestination) else {
            throw MediaError.posterGenerationFailed(sourceURL)
        }
        return mutableData as Data
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
        // Unsupported files are skipped silently.
        guard AppPaths.supportedVideoExtensions.contains(ext) else { return nil }

        // Hash off the cooperative pool: reads the whole file, possibly from a
        // network volume.
        let hasher = self.hasher
        let hash = try await Task.detached(priority: .utility) {
            try await hasher.sha256(of: url)
        }.value

        // Dedup: the file is already in the library, return the existing record
        // without copying it again.
        if let existing = try repository.video(contentHash: hash) {
            return existing
        }

        let id = UUID().uuidString
        try AppPaths.ensureDirectories()
        let destination = AppPaths.managedVideoDestination(id: id, fileExtension: ext)
        let posterDestination = AppPaths.posterDestination(for: id)
        let originalCreationDate = Self.creationDate(of: url)

        // Copy off the cooperative pool, preserving the original creation date.
        try await Task.detached(priority: .utility) {
            let fm = FileManager.default
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.copyItem(at: url, to: destination)
            if let originalCreationDate {
                try? fm.setAttributes([.creationDate: originalCreationDate], ofItemAtPath: destination.path)
            }
        }.value

        // Anything after the copy is transactional: on failure remove the copied
        // file and any partial poster, then rethrow.
        do {
            // Probe the *copy*: the original may live on an unreachable/network volume.
            let metadata = try await prober.probe(url: destination)

            var posterPath: String?
            do {
                try await posters.makePoster(for: destination, to: posterDestination, maxWidth: 1280, at: nil)
                posterPath = posterDestination.path
            } catch {
                // A missing poster is not fatal; keep the video.
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
        } catch {
            Self.rollback(video: destination, poster: posterDestination)
            throw error
        }
    }

    /// Removes artifacts of a failed import. Best-effort: never throws.
    private static func rollback(video: URL, poster: URL) {
        let fm = FileManager.default
        if fm.fileExists(atPath: video.path) {
            try? fm.removeItem(at: video)
        }
        if fm.fileExists(atPath: poster.path) {
            try? fm.removeItem(at: poster)
        }
    }

    private static func creationDate(of url: URL) -> Date? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.creationDate] as? Date
    }
}
