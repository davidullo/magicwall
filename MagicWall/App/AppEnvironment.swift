import Foundation
import MagicWallCore

/// Wires the object graph: database → repository → services → view model → engine.
@MainActor
final class AppEnvironment {
    let repository: LibraryRepository
    let importService: VideoImporting
    let viewModel: LibraryViewModel
    let engine: WallpaperEngine

    init(
        repository: LibraryRepository,
        importService: VideoImporting,
        viewModel: LibraryViewModel,
        engine: WallpaperEngine
    ) {
        self.repository = repository
        self.importService = importService
        self.viewModel = viewModel
        self.engine = engine
    }

    static func bootstrap() -> AppEnvironment {
        var warnings: [String] = []

        let database: AppDatabase
        do {
            database = try AppDatabase.makeShared()
        } catch {
            warnings.append("Could not open the library database. Using temporary in-memory storage — changes will not persist.")
            // If even the in-memory database fails there is nothing sensible left to do.
            database = try! AppDatabase.inMemory()
        }

        let repository = GRDBLibraryRepository(database: database)
        let importService = VideoImportService(repository: repository)
        let engine = WallpaperEngine(repository: repository)
        let viewModel = LibraryViewModel(
            repository: repository,
            importService: importService,
            engine: engine,
            startupWarnings: warnings
        )

        return AppEnvironment(
            repository: repository,
            importService: importService,
            viewModel: viewModel,
            engine: engine
        )
    }
}
