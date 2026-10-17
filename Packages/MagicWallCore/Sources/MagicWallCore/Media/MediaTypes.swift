import Foundation

/// Video metadata extracted with AVFoundation.
public struct MediaMetadata: Sendable, Equatable {
    public var duration: Double
    public var width: Int
    public var height: Int
    public var fps: Double
    public var codec: String?
    public var bitrate: Int
    public var fileSize: Int64

    public init(
        duration: Double,
        width: Int,
        height: Int,
        fps: Double,
        codec: String?,
        bitrate: Int,
        fileSize: Int64
    ) {
        self.duration = duration
        self.width = width
        self.height = height
        self.fps = fps
        self.codec = codec
        self.bitrate = bitrate
        self.fileSize = fileSize
    }
}

public enum MediaError: Error, LocalizedError, Sendable {
    case notReadable(URL)
    case noVideoTrack(URL)
    case posterGenerationFailed(URL)
    case loadFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notReadable(let url):
            return "Cannot read \(url.lastPathComponent)."
        case .noVideoTrack(let url):
            return "\(url.lastPathComponent) has no video track."
        case .posterGenerationFailed(let url):
            return "Could not generate a poster for \(url.lastPathComponent)."
        case .loadFailed(let message):
            return message
        }
    }
}

public enum LibraryError: Error, LocalizedError, Sendable {
    case invalidInput(String)

    public var errorDescription: String? {
        switch self {
        case .invalidInput(let message):
            return message
        }
    }
}

/// Reads duration/resolution/codec metadata from a video file.
public protocol MediaProbing: Sendable {
    func probe(url: URL) async throws -> MediaMetadata
}

/// Streams a SHA-256 digest of a file (used for duplicate detection).
public protocol FileHashing: Sendable {
    func sha256(of url: URL) async throws -> String
}

/// Extracts a poster frame (JPEG) from a video.
public protocol ThumbnailGenerating: Sendable {
    func makePoster(for videoURL: URL, to destination: URL, maxWidth: Int, at time: Double?) async throws
}

/// Full import pipeline: copy into the managed library, probe, hash, poster, persist.
public protocol VideoImporting: Sendable {
    /// Imports files and/or directories of videos. Returns the created (or already-known) records.
    func importVideos(from urls: [URL]) async throws -> [Video]
}
