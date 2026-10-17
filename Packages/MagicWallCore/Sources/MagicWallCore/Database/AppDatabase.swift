import Foundation
import GRDB

/// Owns the SQLite database and its schema migrations.
public final class AppDatabase: @unchecked Sendable {
    public let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) throws {
        self.dbQueue = dbQueue
        try Self.migrator.migrate(dbQueue)
    }

    /// Opens (creating if needed) the on-disk database in Application Support.
    public static func makeShared() throws -> AppDatabase {
        try AppPaths.ensureDirectories()
        var config = Configuration()
        config.foreignKeysEnabled = true
        let dbQueue = try DatabaseQueue(path: AppPaths.databaseURL.path, configuration: config)
        return try AppDatabase(dbQueue: dbQueue)
    }

    /// In-memory database for tests and fallback startup.
    public static func inMemory() throws -> AppDatabase {
        var config = Configuration()
        config.foreignKeysEnabled = true
        return try AppDatabase(dbQueue: try DatabaseQueue(configuration: config))
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial_schema") { db in
            try db.create(table: "videos") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
                t.column("filePath", .text).notNull().unique()
                t.column("duration", .double).notNull().defaults(to: 0)
                t.column("width", .integer).notNull().defaults(to: 0)
                t.column("height", .integer).notNull().defaults(to: 0)
                t.column("fps", .double).notNull().defaults(to: 0)
                t.column("codec", .text)
                t.column("bitrate", .integer).notNull().defaults(to: 0)
                t.column("fileSize", .integer).notNull().defaults(to: 0)
                t.column("contentHash", .text)
                t.column("posterPath", .text)
                t.column("source", .text).notNull().defaults(to: "imported")
                t.column("createdAt", .datetime).notNull()
                t.column("importedAt", .datetime).notNull()
                t.column("lastPlayedAt", .datetime)
            }
            try db.create(index: "videos_on_contentHash", on: "videos", columns: ["contentHash"])

            try db.create(table: "categories") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull().unique()
                t.column("slug", .text).notNull().unique()
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
            }

            try db.create(table: "video_categories") { t in
                t.column("videoId", .text).notNull()
                    .references("videos", onDelete: .cascade)
                t.column("categoryId", .integer).notNull()
                    .references("categories", onDelete: .cascade)
                t.primaryKey(["videoId", "categoryId"])
            }

            try db.create(table: "tags") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull().unique()
            }

            try db.create(table: "video_tags") { t in
                t.column("videoId", .text).notNull()
                    .references("videos", onDelete: .cascade)
                t.column("tagId", .integer).notNull()
                    .references("tags", onDelete: .cascade)
                t.primaryKey(["videoId", "tagId"])
            }

            try db.create(table: "favorites") { t in
                t.column("videoId", .text).primaryKey()
                    .references("videos", onDelete: .cascade)
                t.column("addedAt", .datetime).notNull()
            }

            try db.create(table: "playlists") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(table: "playlist_items") { t in
                t.column("playlistId", .integer).notNull()
                    .references("playlists", onDelete: .cascade)
                t.column("videoId", .text).notNull()
                    .references("videos", onDelete: .cascade)
                t.column("position", .integer).notNull().defaults(to: 0)
                t.primaryKey(["playlistId", "videoId"])
            }

            try db.create(table: "screen_assignments") { t in
                t.primaryKey("id", .text)
                t.column("screenKey", .text).notNull().unique()
                t.column("videoId", .text)
                    .references("videos", onDelete: .setNull)
                t.column("playlistId", .integer)
                    .references("playlists", onDelete: .setNull)
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "app_settings") { t in
                t.primaryKey("key", .text)
                t.column("value", .text)
            }

            // Seed default categories. Users can add more; slugs stay stable.
            let seeded: [(String, String)] = [
                ("Nature", "nature"),
                ("Urban", "urban"),
                ("Abstract", "abstract"),
                ("Anime", "anime"),
                ("Minimal", "minimal"),
                ("Space", "space"),
                ("Gaming", "gaming"),
                ("Movies & Shows", "movies")
            ]
            for (index, entry) in seeded.enumerated() {
                try db.execute(
                    sql: "INSERT INTO categories (name, slug, sortOrder) VALUES (?, ?, ?)",
                    arguments: [entry.0, entry.1, index]
                )
            }
        }

        return migrator
    }
}
