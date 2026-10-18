import AppKit
import Combine
import Foundation
import MagicWallCore

/// Status of the video lock screen, plus the app-side plumbing that feeds it.
///
/// The lock screen is painted by macOS's own wallpaper pipeline, so the only
/// way to influence it is to be one of its providers — and the only way to pick
/// a provider is System Settings. This service therefore does two things:
/// it mirrors the library into the extension's container (see
/// `WallpaperExtensionBridge`) and it reads the system store to report what the
/// user actually has, instead of nagging blindly.
@MainActor
final class WallpaperExtensionService: ObservableObject {
    /// Why the lock screen feature is, or is not, available in this build.
    enum Availability: Equatable {
        /// macOS older than the wallpaper pipeline the extension plugs into.
        case unsupportedSystem
        /// No appex in the bundle: a build without the extension target.
        case missingExtension
        case ready
    }

    /// What the system store says about the lock screen slot (`Idle`).
    enum LockScreenState: Equatable {
        /// Not one of our wallpapers: the lock screen is still, or an Apple choice.
        case notSet
        /// Ours on some displays only.
        case partial(active: Int, total: Int)
        /// Ours wherever the store keeps an idle slot.
        case active
    }

    @Published private(set) var availability: Availability
    @Published private(set) var lockScreenState: LockScreenState = .notSet

    /// Title of the library video the lock screen is set to, when it is ours.
    @Published private(set) var lockScreenVideoTitle: String?

    private let repository: LibraryRepository
    private let bridge = WallpaperExtensionBridge()

    private var library: [Video] = []
    private var libraryCancellable: AnyCancellable?
    private var activationObserver: NSObjectProtocol?
    private var storeMonitor: DispatchSourceFileSystemObject?

    /// Index of the system wallpaper store. Owned by a daemon that reverts any
    /// write from outside within a second — the reason the picker stays manual —
    /// but perfectly readable, and reading it is what lets the app tell the
    /// truth about the current screensaver.
    private static var storeIndexURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
    }

    /// The Wallpaper pane in System Settings: the only place the screensaver
    /// (and through it the lock screen) can be chosen. The ExtensionKit pane
    /// first, the legacy preference id as a fallback.
    private static let wallpaperSettingsURLs = [
        "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension",
        "x-apple.systempreferences:com.apple.preference.desktopscreeneffect",
    ].compactMap(URL.init(string:))

    init(repository: LibraryRepository) {
        self.repository = repository
        self.availability = Self.currentAvailability()

        observeActivation()
        watchStore()
        refreshLockScreen()
    }

    deinit {
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
        storeMonitor?.cancel()
    }

    // MARK: - Library

    /// Follows the published library: every import, rename, deletion and starter
    /// download lands in the container, and the row keeps its video title.
    func track(_ videos: Published<[Video]>.Publisher) {
        libraryCancellable = videos
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] videos in
                Task { @MainActor in self?.libraryDidChange(videos) }
            }
    }

    /// Sync entry point for launches where the window never appears (login item,
    /// menu-bar only): the publisher above only emits after the first refresh.
    func startLibrarySync() {
        libraryDidChange((try? repository.allVideos()) ?? [])
    }

    func libraryDidChange(_ videos: [Video]) {
        library = videos
        refreshLockScreen()

        guard availability == .ready, !WallpaperExtensionBridge.isDisabledByEnvironment else { return }

        // An empty list is mirrored only when the database agrees the library is
        // genuinely empty: the published list starts empty, and treating that as
        // the truth would wipe the extension's copy of a full library at launch.
        let isGenuinelyEmpty = videos.isEmpty && (try? repository.videoCount()) == 0
        guard !videos.isEmpty || isGenuinelyEmpty else { return }

        bridge.sync(videos)
    }

    // MARK: - System Settings

    func openWallpaperSettings() {
        for url in Self.wallpaperSettingsURLs {
            if NSWorkspace.shared.open(url) { return }
        }
    }

    // MARK: - Store

    /// Reads the system store and updates the published state. A few KB of
    /// binary plist: cheap enough to run on every activation and every store
    /// write, and it keeps the row honest without polling.
    func refreshLockScreen() {
        lockScreenVideoTitle = nil

        guard availability == .ready,
              let data = try? Data(contentsOf: Self.storeIndexURL),
              let root = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil))
                  as? [String: Any]
        else {
            lockScreenState = .notSet
            return
        }

        let slots = Self.idleSlots(in: root)
        guard !slots.isEmpty else {
            lockScreenState = .notSet
            return
        }

        let ours = slots.filter { $0.value.provider == WallpaperExtensionBridge.extensionBundleID }

        if ours.isEmpty {
            lockScreenState = .notSet
        } else if ours.count == slots.count {
            lockScreenState = .active
        } else {
            lockScreenState = .partial(active: ours.count, total: slots.count)
        }

        lockScreenVideoTitle = ours.values
            .compactMap(\.videoID)
            .compactMap(libraryTitle(forExtensionID:))
            .first
    }

    private func libraryTitle(forExtensionID id: String) -> String? {
        library.first { WallpaperExtensionBridge.extensionVideoID(for: $0) == id }?.title
    }

    // MARK: - Private

    /// The extension target and the wallpaper pipeline it talks to both start at
    /// macOS 26. Checked at runtime rather than with `#available` so the app
    /// still builds against SDKs that predate it.
    private static func currentAvailability() -> Availability {
        let macOS26 = OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)
        guard ProcessInfo.processInfo.isOperatingSystemAtLeast(macOS26) else {
            return .unsupportedSystem
        }
        return WallpaperExtensionBridge.isExtensionBundled ? .ready : .missingExtension
    }

    private func observeActivation() {
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshLockScreen() }
        }
    }

    /// Watches the store's *directory*: the daemon replaces `Index.plist` rather
    /// than editing it in place, so a file watcher would go deaf after the first
    /// change. This is what turns the row green the moment the user comes back
    /// from System Settings.
    private func watchStore() {
        guard availability == .ready else { return }

        let directory = Self.storeIndexURL.deletingLastPathComponent()
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.refreshLockScreen() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()

        storeMonitor = source
    }

    // MARK: - Store parsing

    private struct SlotSelection {
        var provider: String?
        var videoID: String?
    }

    /// Every `Idle` record in the store, keyed by the slot it belongs to. The
    /// same display is stored both at top level and under each space; the
    /// top-level record is the authoritative one and wins here.
    private static func idleSlots(in root: [String: Any]) -> [String: SlotSelection] {
        var slots: [String: (isNested: Bool, selection: SlotSelection)] = [:]

        func walk(_ node: Any, path: [String]) {
            guard let dictionary = node as? [String: Any] else { return }

            if let idle = dictionary["Idle"] as? [String: Any],
               let key = slotKey(for: path),
               let selection = selection(from: idle) {
                let isNested = path.first == "Spaces"
                if slots[key] == nil || (isNested == false && slots[key]?.isNested == true) {
                    slots[key] = (isNested, selection)
                }
            }

            for (name, value) in dictionary where name != "Idle" {
                walk(value, path: path + [name])
            }
        }

        walk(root, path: [])
        return slots.mapValues(\.selection)
    }

    /// Canonical slot name for a store path: `all`, `system`, `space` or
    /// `display:<uuid>`. Paths under `Spaces/<uuid>/` collapse onto their
    /// top-level equivalent so one display is counted once.
    private static func slotKey(for path: [String]) -> String? {
        var path = path
        if path.first == "Spaces" {
            path.removeFirst()
            guard !path.isEmpty else { return nil }
            path.removeFirst()
        }

        switch path.first {
        case "AllSpacesAndDisplays": return "all"
        case "SystemDefault": return "system"
        case "Default": return "space"
        case "Displays": return path.dropFirst().first.map { "display:\($0)" }
        default: return nil
        }
    }

    /// What a slot resolves to. A slot with no choice at all ("None" in the
    /// picker) still counts as a slot — one that is not ours.
    private static func selection(from idle: [String: Any]) -> SlotSelection? {
        guard let content = idle["Content"] as? [String: Any] else { return nil }
        let choices = content["Choices"] as? [[String: Any]] ?? []
        guard let first = choices.first else { return SlotSelection(provider: nil, videoID: nil) }

        return SlotSelection(
            provider: first["Provider"] as? String,
            videoID: (first["Configuration"] as? Data).flatMap { String(data: $0, encoding: .utf8) }
        )
    }
}
