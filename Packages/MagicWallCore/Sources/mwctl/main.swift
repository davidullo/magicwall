// mwctl — small automation CLI for MagicWall's local library.
//
// Usage:
//   mwctl import <file-or-folder>...     Import videos into the library
//   mwctl list                           List library videos
//   mwctl assign <screenKey|main> <id>   Assign a video to a display
//   mwctl assign-latest main             Assign the most recent video to a display
//   mwctl favorite <id>                  Mark a video as favorite
//   mwctl favorite-latest                Mark the most recent video as favorite
//   mwctl clear-assignments              Remove all screen assignments
//   mwctl delete <videoID>               Delete a video (files + record)
//   mwctl prune-missing                  Delete records whose files are gone
import CoreGraphics
import Foundation
import MagicWallCore

func usage() {
    print("""
    mwctl — MagicWall library control

      mwctl import <file-or-folder>...     Import videos into the managed library
      mwctl list                           List library videos
      mwctl assign <screenKey|main> <id>   Assign a video to a display
      mwctl assign-latest main             Assign the most recent video to a display
      mwctl favorite <id>                  Mark a video as favorite
      mwctl favorite-latest                Mark the most recent video as favorite
      mwctl clear-assignments              Remove all screen assignments
      mwctl delete <videoID>               Delete a video (files + record)
      mwctl prune-missing                  Delete records whose files are gone
    """)
}

func resolveScreenKey(_ raw: String) -> String {
    raw == "main" ? "display:\(CGMainDisplayID())" : raw
}

func printVideo(_ video: Video) {
    let size = ByteCountFormatter.string(fromByteCount: video.fileSize, countStyle: .file)
    print("\(video.id)  \(video.resolutionLabel)  \(video.durationLabel)  \(size)  \(video.title)")
}

@MainActor
func run(_ args: [String]) async throws -> Int32 {    guard let command = args.first else {
        usage()
        return 1
    }
    let rest = Array(args.dropFirst())

    let database = try AppDatabase.makeShared()
    let repository = GRDBLibraryRepository(database: database)

    switch command {
    case "import":
        guard !rest.isEmpty else {
            usage()
            return 1
        }
        let service = VideoImportService(repository: repository)
        let urls = rest.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
        let imported = try await service.importVideos(from: urls)
        print("Imported \(imported.count) video(s):")
        for video in imported { printVideo(video) }
        return 0

    case "list":
        let videos = try repository.allVideos()
        print("\(videos.count) video(s) in library:")
        for video in videos { printVideo(video) }
        return 0

    case "assign":
        guard rest.count == 2 else {
            usage()
            return 1
        }
        let key = resolveScreenKey(rest[0])
        guard let video = try repository.video(id: rest[1]) else {
            FileHandle.standardError.write("error: no video with id \(rest[1])\n".data(using: .utf8)!)
            return 1
        }
        try repository.setAssignment(ScreenAssignment(screenKey: key, videoId: video.id))
        print("Assigned \(video.title) to \(key)")
        return 0

    case "assign-latest":
        guard rest.count == 1 else {
            usage()
            return 1
        }
        guard let video = try repository.allVideos().first else {
            FileHandle.standardError.write("error: library is empty\n".data(using: .utf8)!)
            return 1
        }
        try repository.setAssignment(ScreenAssignment(screenKey: resolveScreenKey(rest[0]), videoId: video.id))
        print("Assigned \(video.title) to \(resolveScreenKey(rest[0]))")
        return 0

    case "favorite":
        guard rest.count == 1 else {
            usage()
            return 1
        }
        guard let video = try repository.video(id: rest[0]) else {
            FileHandle.standardError.write("error: no video with id \(rest[0])\n".data(using: .utf8)!)
            return 1
        }
        try repository.setFavorite(true, videoID: video.id)
        print("Favorited \(video.title)")
        return 0

    case "favorite-latest":
        guard let video = try repository.allVideos().first else {
            FileHandle.standardError.write("error: library is empty\n".data(using: .utf8)!)
            return 1
        }
        try repository.setFavorite(true, videoID: video.id)
        print("Favorited \(video.title)")
        return 0

    case "clear-assignments":
        for assignment in try repository.assignments() {
            try repository.clearAssignment(screenKey: assignment.screenKey)
        }
        print("Cleared all assignments")
        return 0

    case "delete":
        guard rest.count == 1 else {
            usage()
            return 1
        }
        guard let video = try repository.video(id: rest[0]) else {
            FileHandle.standardError.write("error: no video with id \(rest[0])\n".data(using: .utf8)!)
            return 1
        }
        let fm = FileManager.default
        if video.filePath.hasPrefix(AppPaths.libraryRoot.path) {
            try? fm.removeItem(at: video.fileURL)
        }
        if let posterURL = video.posterURL, video.posterPath?.hasPrefix(AppPaths.postersDirectory.path) == true {
            try? fm.removeItem(at: posterURL)
        }
        try repository.deleteVideo(id: video.id)
        print("Deleted \(video.title)")
        return 0

    case "prune-missing":
        var pruned = 0
        for video in try repository.allVideos() where !FileManager.default.fileExists(atPath: video.filePath) {
            try repository.deleteVideo(id: video.id)
            pruned += 1
        }
        print("Pruned \(pruned) record(s)")
        return 0

    default:
        usage()
        return 1
    }
}

let semaphore = DispatchSemaphore(value: 0)
var exitCode: Int32 = 0
Task { @MainActor in
    do {
        exitCode = try await run(Array(CommandLine.arguments.dropFirst()))
    } catch {
        FileHandle.standardError.write("error: \(error.localizedDescription)\n".data(using: .utf8)!)
        exitCode = 1
    }
    exit(exitCode)
}
dispatchMain()
