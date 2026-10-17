import XCTest

@testable import MagicWallCore

/// Smoke test: an empty database can be created and seeded with default categories.
final class DatabaseSmokeTests: XCTestCase {
    func testDefaultCategoriesAreSeeded() throws {
        let database = try AppDatabase.inMemory()
        let repository = GRDBLibraryRepository(database: database)
        let categories = try repository.categories()
        XCTAssertFalse(categories.isEmpty)
        XCTAssertTrue(categories.contains { $0.slug == "nature" })
    }

    func testVideoRoundTrip() throws {
        let database = try AppDatabase.inMemory()
        let repository = GRDBLibraryRepository(database: database)

        let video = Video(title: "Test", filePath: "/tmp/test.mp4", duration: 12.5)
        try repository.save(video)

        let loaded = try repository.video(id: video.id)
        XCTAssertEqual(loaded?.title, "Test")
        XCTAssertEqual(try repository.videoCount(), 1)
    }

    func testRenameVideoPersistsTrimmedTitle() throws {
        let database = try AppDatabase.inMemory()
        let repository = GRDBLibraryRepository(database: database)

        let video = Video(title: "Original", filePath: "/tmp/test.mp4")
        try repository.save(video)

        try repository.renameVideo(id: video.id, title: "  New title  ")

        let loaded = try repository.video(id: video.id)
        XCTAssertEqual(loaded?.title, "New title")
    }

    func testRenameVideoRejectsEmptyTitle() throws {
        let database = try AppDatabase.inMemory()
        let repository = GRDBLibraryRepository(database: database)

        let video = Video(title: "Original", filePath: "/tmp/test.mp4")
        try repository.save(video)

        XCTAssertThrowsError(try repository.renameVideo(id: video.id, title: "   ")) { error in
            guard case LibraryError.invalidInput = error else {
                return XCTFail("Expected invalidInput, got \(error)")
            }
        }
        XCTAssertEqual(try repository.video(id: video.id)?.title, "Original")
    }
}
