import Foundation
import GRDB

// MARK: - GRDB conformances

extension Video: FetchableRecord, PersistableRecord {}
extension VideoCategory: FetchableRecord, PersistableRecord {}
extension Playlist: FetchableRecord, PersistableRecord {}
extension ScreenAssignment: FetchableRecord, PersistableRecord {}

// MARK: - Repository protocol

/// Read/write access to the local library. Implemented by `GRDBLibraryRepository`.
public protocol LibraryRepository: AnyObject, Sendable {
    // Videos
    func allVideos() throws -> [Video]
    func video(id: String) throws -> Video?
    func video(contentHash: String) throws -> Video?
    func videos(inCategorySlug slug: String?) throws -> [Video]
    func searchVideos(matching query: String) throws -> [Video]
    func save(_ video: Video) throws
    func renameVideo(id: String, title: String) throws
    func deleteVideo(id: String) throws
    func markPlayed(id: String) throws

    // Categories
    func categories() throws -> [VideoCategory]
    func addCategory(name: String) throws -> VideoCategory
    func deleteCategory(id: Int64) throws
    func setCategories(_ categoryIDs: [Int64], forVideo videoID: String) throws
    func categories(forVideo videoID: String) throws -> [VideoCategory]

    // Favorites
    func isFavorite(videoID: String) throws -> Bool
    func setFavorite(_ flag: Bool, videoID: String) throws
    func favoriteVideos() throws -> [Video]
    func favoriteIDs() throws -> Set<String>

    // Playlists
    func playlists() throws -> [Playlist]
    func createPlaylist(name: String) throws -> Playlist
    func deletePlaylist(id: Int64) throws
    func addToPlaylist(_ playlistID: Int64, videoID: String) throws
    func removeFromPlaylist(_ playlistID: Int64, videoID: String) throws
    func videos(inPlaylist playlistID: Int64) throws -> [Video]

    // Screen assignments
    func assignments() throws -> [ScreenAssignment]
    func assignment(screenKey: String) throws -> ScreenAssignment?
    func setAssignment(_ assignment: ScreenAssignment) throws
    func clearAssignment(screenKey: String) throws

    // Stats
    func videoCount() throws -> Int
    func totalLibraryBytes() throws -> Int64
}

// MARK: - GRDB implementation

public final class GRDBLibraryRepository: LibraryRepository, @unchecked Sendable {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    // MARK: Videos

    public func allVideos() throws -> [Video] {
        try database.dbQueue.read { db in
            try Video.order(Column("importedAt").desc).fetchAll(db)
        }
    }

    public func video(id: String) throws -> Video? {
        try database.dbQueue.read { db in
            try Video.filter(Column("id") == id).fetchOne(db)
        }
    }

    public func video(contentHash: String) throws -> Video? {
        try database.dbQueue.read { db in
            try Video.filter(Column("contentHash") == contentHash).fetchOne(db)
        }
    }

    public func videos(inCategorySlug slug: String?) throws -> [Video] {
        guard let slug, !slug.isEmpty else { return try allVideos() }
        return try database.dbQueue.read { db in
            try Video.fetchAll(db, sql: """
                SELECT v.* FROM videos v
                JOIN video_categories vc ON vc.videoId = v.id
                JOIN categories c ON c.id = vc.categoryId
                WHERE c.slug = ?
                ORDER BY v.importedAt DESC
                """, arguments: [slug])
        }
    }

    public func searchVideos(matching query: String) throws -> [Video] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return try allVideos() }
        let pattern = "%\(trimmed)%"
        return try database.dbQueue.read { db in
            try Video.fetchAll(db, sql: """
                SELECT DISTINCT v.* FROM videos v
                LEFT JOIN video_tags vt ON vt.videoId = v.id
                LEFT JOIN tags t ON t.id = vt.tagId
                WHERE v.title LIKE ? COLLATE NOCASE
                   OR t.name LIKE ? COLLATE NOCASE
                ORDER BY v.importedAt DESC
                """, arguments: [pattern, pattern])
        }
    }

    public func save(_ video: Video) throws {
        try database.dbQueue.write { db in
            try video.save(db)
        }
    }

    public func renameVideo(id: String, title: String) throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw LibraryError.invalidInput("Video title must not be empty.")
        }
        try database.dbQueue.write { db in
            guard try Video.filter(Column("id") == id).fetchOne(db) != nil else {
                throw LibraryError.invalidInput("No video with id \(id).")
            }
            try db.execute(
                sql: "UPDATE videos SET title = ? WHERE id = ?",
                arguments: [trimmed, id]
            )
        }
    }

    public func deleteVideo(id: String) throws {
        _ = try database.dbQueue.write { db in
            try Video.deleteOne(db, key: id)
        }
    }

    public func markPlayed(id: String) throws {
        try database.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE videos SET lastPlayedAt = ? WHERE id = ?",
                arguments: [Date(), id]
            )
        }
    }

    // MARK: Categories

    public func categories() throws -> [VideoCategory] {
        try database.dbQueue.read { db in
            try VideoCategory.order(Column("sortOrder")).fetchAll(db)
        }
    }

    @discardableResult
    public func addCategory(name: String) throws -> VideoCategory {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw LibraryError.invalidInput("VideoCategory name must not be empty.")
        }
        return try database.dbQueue.write { db in
            if let existing = try VideoCategory.filter(Column("name") == trimmed).fetchOne(db) {
                return existing
            }
            var category = VideoCategory(
                name: trimmed,
                slug: VideoCategory.makeSlug(from: trimmed),
                sortOrder: try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(sortOrder), 0) + 1 FROM categories") ?? 0
            )
            try category.insert(db)
            category.id = db.lastInsertedRowID
            return category
        }
    }

    public func deleteCategory(id: Int64) throws {
        _ = try database.dbQueue.write { db in
            try VideoCategory.deleteOne(db, key: id)
        }
    }

    public func setCategories(_ categoryIDs: [Int64], forVideo videoID: String) throws {
        try database.dbQueue.write { db in
            try db.execute(sql: "DELETE FROM video_categories WHERE videoId = ?", arguments: [videoID])
            for categoryID in categoryIDs {
                try db.execute(
                    sql: "INSERT OR IGNORE INTO video_categories (videoId, categoryId) VALUES (?, ?)",
                    arguments: [videoID, categoryID]
                )
            }
        }
    }

    public func categories(forVideo videoID: String) throws -> [VideoCategory] {
        try database.dbQueue.read { db in
            try VideoCategory.fetchAll(db, sql: """
                SELECT c.* FROM categories c
                JOIN video_categories vc ON vc.categoryId = c.id
                WHERE vc.videoId = ?
                ORDER BY c.sortOrder
                """, arguments: [videoID])
        }
    }

    // MARK: Favorites

    public func isFavorite(videoID: String) throws -> Bool {
        try database.dbQueue.read { db in
            try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM favorites WHERE videoId = ?)", arguments: [videoID]) ?? false
        }
    }

    public func setFavorite(_ flag: Bool, videoID: String) throws {
        try database.dbQueue.write { db in
            if flag {
                try db.execute(
                    sql: "INSERT OR REPLACE INTO favorites (videoId, addedAt) VALUES (?, ?)",
                    arguments: [videoID, Date()]
                )
            } else {
                try db.execute(sql: "DELETE FROM favorites WHERE videoId = ?", arguments: [videoID])
            }
        }
    }

    public func favoriteVideos() throws -> [Video] {
        try database.dbQueue.read { db in
            try Video.fetchAll(db, sql: """
                SELECT v.* FROM videos v
                JOIN favorites f ON f.videoId = v.id
                ORDER BY f.addedAt DESC
                """)
        }
    }

    public func favoriteIDs() throws -> Set<String> {
        try database.dbQueue.read { db in
            Set(try String.fetchAll(db, sql: "SELECT videoId FROM favorites"))
        }
    }

    // MARK: Playlists

    public func playlists() throws -> [Playlist] {
        try database.dbQueue.read { db in
            try Playlist.order(Column("createdAt").desc).fetchAll(db)
        }
    }

    @discardableResult
    public func createPlaylist(name: String) throws -> Playlist {
        try database.dbQueue.write { db in
            var playlist = Playlist(name: name)
            try playlist.insert(db)
            playlist.id = db.lastInsertedRowID
            return playlist
        }
    }

    public func deletePlaylist(id: Int64) throws {
        _ = try database.dbQueue.write { db in
            try Playlist.deleteOne(db, key: id)
        }
    }

    public func addToPlaylist(_ playlistID: Int64, videoID: String) throws {
        try database.dbQueue.write { db in
            let next = try Int.fetchOne(
                db,
                sql: "SELECT COALESCE(MAX(position), -1) + 1 FROM playlist_items WHERE playlistId = ?",
                arguments: [playlistID]
            ) ?? 0
            try db.execute(
                sql: "INSERT OR IGNORE INTO playlist_items (playlistId, videoId, position) VALUES (?, ?, ?)",
                arguments: [playlistID, videoID, next]
            )
        }
    }

    public func removeFromPlaylist(_ playlistID: Int64, videoID: String) throws {
        try database.dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM playlist_items WHERE playlistId = ? AND videoId = ?",
                arguments: [playlistID, videoID]
            )
        }
    }

    public func videos(inPlaylist playlistID: Int64) throws -> [Video] {
        try database.dbQueue.read { db in
            try Video.fetchAll(db, sql: """
                SELECT v.* FROM videos v
                JOIN playlist_items pi ON pi.videoId = v.id
                WHERE pi.playlistId = ?
                ORDER BY pi.position
                """, arguments: [playlistID])
        }
    }

    // MARK: Screen assignments

    public func assignments() throws -> [ScreenAssignment] {
        try database.dbQueue.read { db in
            try ScreenAssignment.fetchAll(db)
        }
    }

    public func assignment(screenKey: String) throws -> ScreenAssignment? {
        try database.dbQueue.read { db in
            try ScreenAssignment.filter(Column("screenKey") == screenKey).fetchOne(db)
        }
    }

    public func setAssignment(_ assignment: ScreenAssignment) throws {
        try database.dbQueue.write { db in
            var incoming = assignment
            incoming.updatedAt = Date()
            if var existing = try ScreenAssignment
                .filter(Column("screenKey") == incoming.screenKey)
                .fetchOne(db)
            {
                existing.videoId = incoming.videoId
                existing.playlistId = incoming.playlistId
                existing.updatedAt = incoming.updatedAt
                try existing.update(db)
            } else {
                try incoming.insert(db)
            }
        }
    }

    public func clearAssignment(screenKey: String) throws {
        try database.dbQueue.write { db in
            try db.execute(sql: "DELETE FROM screen_assignments WHERE screenKey = ?", arguments: [screenKey])
        }
    }

    // MARK: Stats

    public func videoCount() throws -> Int {
        try database.dbQueue.read { db in
            try Video.fetchCount(db)
        }
    }

    public func totalLibraryBytes() throws -> Int64 {
        try database.dbQueue.read { db in
            try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(fileSize), 0) FROM videos") ?? 0
        }
    }
}
