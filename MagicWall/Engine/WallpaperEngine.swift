import AppKit
import AVFoundation
import Combine
import Foundation
import MagicWallCore

/// Renders looping videos behind the desktop icons — one window per screen.
///
/// Baseline implementation (milestone M2 start): window management, gapless
/// looping, persistence of per-screen assignments and restore at launch.
/// Advanced pause policies (battery, lock, occlusion, thermal, fullscreen) are
/// layered on top by the engine hardening pass.
@MainActor
final class WallpaperEngine: ObservableObject {
    struct ScreenStatus: Identifiable, Equatable {
        let id: String
        var name: String
        var videoID: String?
        var videoTitle: String?
    }

    @Published private(set) var statuses: [ScreenStatus] = []
    @Published private(set) var isRunning = false
    @Published var isPaused = false {
        didSet { applyPauseState() }
    }
    @Published var pauseOnBattery = true
    @Published var pauseWhenOccluded = true

    private let repository: LibraryRepository
    private var windowsByKey: [String: WallpaperDesktopWindow] = [:]
    private var screenObserver: NSObjectProtocol?

    init(repository: LibraryRepository) {
        self.repository = repository
    }

    var hasActiveWallpaper: Bool {
        !windowsByKey.isEmpty && windowsByKey.values.contains { $0.videoID != nil }
    }

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else {
            refreshScreens()
            return
        }
        isRunning = true
        observeSystemEvents()
        refreshScreens()
        restoreAssignments()
    }

    func stop() {
        for window in windowsByKey.values {
            window.clear()
        }
        windowsByKey.removeAll()
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        isRunning = false
        statuses = []
    }

    // MARK: - Applying

    func apply(_ video: Video, to screen: NSScreen) {
        guard FileManager.default.fileExists(atPath: video.filePath) else {
            return
        }
        let key = screen.magicWallKey
        let window = windowsByKey[key] ?? createWindow(for: screen)
        window.show(video: video)

        persistAssignment(screenKey: key, videoID: video.id)
        refreshStatuses()
    }

    func applyToAllScreens(_ video: Video) {
        for screen in NSScreen.screens {
            apply(video, to: screen)
        }
    }

    func clear(screen: NSScreen) {
        let key = screen.magicWallKey
        windowsByKey[key]?.clear()
        try? repository.clearAssignment(screenKey: key)
        refreshStatuses()
    }

    func clearAll() {
        for window in windowsByKey.values {
            window.clear()
        }
        if let assignments = try? repository.assignments() {
            for assignment in assignments {
                try? repository.clearAssignment(screenKey: assignment.screenKey)
            }
        }
        refreshStatuses()
    }

    /// Stops every window currently displaying the given video (used before deletion).
    func stopDisplaying(videoID: String) {
        for (key, window) in windowsByKey where window.videoID == videoID {
            window.clear()
            try? repository.clearAssignment(screenKey: key)
        }
        refreshStatuses()
    }

    func refreshScreens() {
        let screens = NSScreen.screens
        let currentKeys = Set(screens.map { $0.magicWallKey })

        // Prune windows for disconnected screens.
        for (key, window) in windowsByKey where !currentKeys.contains(key) {
            window.clear()
            windowsByKey.removeValue(forKey: key)
        }

        // Update frames for connected screens (resolution changes, arrangement).
        for screen in screens {
            windowsByKey[screen.magicWallKey]?.updateFrame(for: screen)
        }

        refreshStatuses()
    }

    // MARK: - Private

    private func observeSystemEvents() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshScreens()
            }
        }
    }

    private func createWindow(for screen: NSScreen) -> WallpaperDesktopWindow {
        let window = WallpaperDesktopWindow(screen: screen)
        windowsByKey[screen.magicWallKey] = window
        return window
    }

    private func restoreAssignments() {
        guard let assignments = try? repository.assignments() else { return }
        let screens = NSScreen.screens

        for assignment in assignments {
            guard
                let videoID = assignment.videoId,
                let video = try? repository.video(id: videoID),
                FileManager.default.fileExists(atPath: video.filePath),
                let screen = screens.first(where: { $0.magicWallKey == assignment.screenKey })
            else { continue }

            let window = windowsByKey[screen.magicWallKey] ?? createWindow(for: screen)
            window.show(video: video)
            if isPaused { window.setPaused(true) }
        }

        refreshStatuses()
    }

    private func persistAssignment(screenKey: String, videoID: String) {
        let assignment = ScreenAssignment(screenKey: screenKey, videoId: videoID)
        try? repository.setAssignment(assignment)
    }

    private func applyPauseState() {
        for window in windowsByKey.values {
            window.setPaused(isPaused)
        }
    }

    private func refreshStatuses() {
        statuses = NSScreen.screens.map { screen in
            let key = screen.magicWallKey
            let videoID = windowsByKey[key]?.videoID
            let title = videoID.flatMap { id in
                (try? repository.video(id: id))??.title
            }
            return ScreenStatus(id: key, name: screen.magicWallName, videoID: videoID, videoTitle: title)
        }
    }
}
