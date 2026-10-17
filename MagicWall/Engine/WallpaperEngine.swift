import AppKit
import AVFoundation
import Combine
import Foundation
import IOKit.ps
import MagicWallCore

/// Renders looping videos behind the desktop icons — one window per screen.
///
/// Window management, gapless looping and per-screen persistence are the M2
/// baseline; on top of that this class owns the *playback policy*: it samples
/// the system (power source, Low Power Mode, thermal state, screen lock, sleep
/// and session state, desktop occlusion), feeds everything into the pure
/// ``PlaybackPolicy`` and applies the result to the per-screen players.
///
/// All sampling is callback driven; the only polling is a 3 s occlusion
/// fallback timer that exists only while at least one screen has a video.
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
        didSet { reapplyPlaybackPolicy() }
    }
    @Published var pauseOnBattery = true {
        didSet { reapplyPlaybackPolicy() }
    }
    @Published var pauseWhenOccluded = true {
        didSet { reapplyPlaybackPolicy() }
    }
    @Published var pauseOnLowPower = true {
        didSet { reapplyPlaybackPolicy() }
    }
    @Published var pauseWhenLocked = true {
        didSet { reapplyPlaybackPolicy() }
    }
    @Published var pauseOnThermalPressure = true {
        didSet { reapplyPlaybackPolicy() }
    }

    /// Why playback is currently suspended (diagnostics / settings copy).
    @Published private(set) var pauseReasons: [PlaybackPolicy.Reason] = []

    /// Fallback occlusion poll interval. Occlusion is normally event driven; the
    /// timer only covers the cases where the window server swallows the change.
    private static let occlusionPollInterval: TimeInterval = 3

    private let repository: LibraryRepository
    private var windowsByKey: [String: WallpaperDesktopWindow] = [:]

    private var notificationObservers: [NSObjectProtocol] = []
    private var occlusionTimer: Timer?
    private var powerSourceBox: PowerSourceCallbackBox?
    private var powerSourceRunLoopSource: CFRunLoopSource?

    // Sampled system state, kept up to date by the observers below.
    private var screenIsLocked = false
    private var displaysAreAsleep = false
    private var systemIsAsleep = false
    private var sessionIsActive = true

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
        reapplyPlaybackPolicy()
    }

    func stop() {
        for window in windowsByKey.values {
            window.clear()
        }
        windowsByKey.removeAll()
        teardownObservers()
        invalidateOcclusionTimer()
        isRunning = false
        statuses = []
        pauseReasons = []
    }

    /// Tears everything down for app termination: players stopped, windows
    /// closed, observers and timers removed. Safe to call more than once.
    func prepareForTermination() {
        invalidateOcclusionTimer()
        for window in windowsByKey.values {
            window.prepareForTermination()
            window.close()
        }
        windowsByKey.removeAll()
        teardownObservers()
        isRunning = false
        statuses = []
        pauseReasons = []
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
        reapplyPlaybackPolicy()
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
        reapplyPlaybackPolicy()
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
        reapplyPlaybackPolicy()
    }

    /// Stops every window currently displaying the given video (used before deletion).
    func stopDisplaying(videoID: String) {
        for (key, window) in windowsByKey where window.videoID == videoID {
            window.clear()
            try? repository.clearAssignment(screenKey: key)
        }
        refreshStatuses()
        reapplyPlaybackPolicy()
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
        reapplyPlaybackPolicy()
    }

    // MARK: - Observations

    private func observeSystemEvents() {
        guard notificationObservers.isEmpty else { return }

        let notifications = NotificationCenter.default

        // Display arrangement / resolution changes.
        notificationObservers.append(observe(notifications, NSApplication.didChangeScreenParametersNotification) { engine in
            engine.refreshScreens()
        })

        // Low Power Mode.
        notificationObservers.append(observe(notifications, NSNotification.Name.NSProcessInfoPowerStateDidChange) { engine in
            engine.reapplyPlaybackPolicy()
        })

        // Thermal pressure.
        notificationObservers.append(observe(notifications, ProcessInfo.thermalStateDidChangeNotification) { engine in
            engine.reapplyPlaybackPolicy()
        })

        // Power source (IOKit run loop source → private notification).
        notificationObservers.append(observe(notifications, SystemNotification.powerSourceChanged) { engine in
            engine.reapplyPlaybackPolicy()
        })

        // Screen lock / unlock (distributed, posted by loginwindow).
        let distributed = DistributedNotificationCenter.default()
        notificationObservers.append(observe(distributed, SystemNotification.screenLocked) { engine in
            engine.screenIsLocked = true
            engine.reapplyPlaybackPolicy()
        })
        notificationObservers.append(observe(distributed, SystemNotification.screenUnlocked) { engine in
            engine.screenIsLocked = false
            engine.reapplyPlaybackPolicy()
        })

        // Display + system sleep/wake and fast user switching.
        let workspace = NSWorkspace.shared.notificationCenter
        notificationObservers.append(observe(workspace, NSWorkspace.screensDidSleepNotification) { engine in
            engine.displaysAreAsleep = true
            engine.reapplyPlaybackPolicy()
        })
        notificationObservers.append(observe(workspace, NSWorkspace.screensDidWakeNotification) { engine in
            engine.displaysAreAsleep = false
            engine.recoverAfterWake()
        })
        notificationObservers.append(observe(workspace, NSWorkspace.willSleepNotification) { engine in
            engine.systemIsAsleep = true
            engine.reapplyPlaybackPolicy()
        })
        notificationObservers.append(observe(workspace, NSWorkspace.didWakeNotification) { engine in
            engine.systemIsAsleep = false
            engine.recoverAfterWake()
        })
        notificationObservers.append(observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { engine in
            engine.sessionIsActive = false
            engine.reapplyPlaybackPolicy()
        })
        notificationObservers.append(observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { engine in
            engine.sessionIsActive = true
            engine.recoverAfterWake()
        })

        installPowerSourceRunLoopSource()
    }

    private func teardownObservers() {
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
            DistributedNotificationCenter.default().removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        notificationObservers.removeAll()
        removePowerSourceRunLoopSource()
    }

    /// Registers a main-queue observer that runs `action` on the main actor.
    private func observe(
        _ center: NotificationCenter,
        _ name: Notification.Name,
        _ action: @escaping @MainActor (WallpaperEngine) -> Void
    ) -> NSObjectProtocol {
        center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                action(self)
            }
        }
    }

    // MARK: - Power source (IOKit.ps)

    private func installPowerSourceRunLoopSource() {
        guard powerSourceRunLoopSource == nil else { return }

        let box = PowerSourceCallbackBox {
            NotificationCenter.default.post(name: SystemNotification.powerSourceChanged, object: nil)
        }
        let context = Unmanaged.passRetained(box).toOpaque()

        guard let source = IOPSNotificationCreateRunLoopSource(
            magicWallPowerSourceChangedCallback,
            context
        )?.takeRetainedValue() else {
            Unmanaged<PowerSourceCallbackBox>.fromOpaque(context).release()
            return
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        powerSourceBox = box
        powerSourceRunLoopSource = source
    }

    private func removePowerSourceRunLoopSource() {
        if let source = powerSourceRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
            CFRunLoopSourceInvalidate(source)
        }
        powerSourceRunLoopSource = nil
        if let box = powerSourceBox {
            Unmanaged.passUnretained(box).release()
            powerSourceBox = nil
        }
    }

    private nonisolated static func isRunningOnBattery() -> Bool {
        guard let type = IOPSGetProvidingPowerSourceType(nil)?.takeUnretainedValue() else {
            return false
        }
        return (type as String) == (kIOPSBatteryPowerValue as String)
    }

    // MARK: - Playback policy

    /// Samples the system, asks ``PlaybackPolicy`` and applies the result to
    /// every live window. Cheap: no media work unless the answer changed.
    private func reapplyPlaybackPolicy() {
        guard isRunning else {
            if !pauseReasons.isEmpty { pauseReasons = [] }
            return
        }

        let globalReasons = PlaybackPolicy.pauseReasons(for: currentPolicyInputs())
        let globalShouldPlay = globalReasons.isEmpty

        var hasActiveWindow = false
        var hasPlayingWindow = false

        for window in windowsByKey.values where window.videoID != nil {
            hasActiveWindow = true
            let occluded = pauseWhenOccluded && window.isDesktopOccluded
            let shouldPlay = globalShouldPlay && !occluded
            if shouldPlay { hasPlayingWindow = true }
            window.setPlaying(shouldPlay)
        }

        var published = globalReasons
        if hasActiveWindow, !hasPlayingWindow, globalShouldPlay {
            // Every screen is covered: report it as a pause reason even though
            // the decision is made per window.
            published.append(.desktopOccluded)
        }
        if published != pauseReasons { pauseReasons = published }

        updateOcclusionTimer(hasActiveWindow: hasActiveWindow)
    }

    private func currentPolicyInputs() -> PlaybackPolicy.Inputs {
        var inputs = PlaybackPolicy.Inputs()
        inputs.userPaused = isPaused
        inputs.pauseOnBattery = pauseOnBattery
        inputs.pauseOnLowPower = pauseOnLowPower
        inputs.pauseOnThermalPressure = pauseOnThermalPressure
        inputs.pauseWhenLocked = pauseWhenLocked
        inputs.pauseWhenOccluded = pauseWhenOccluded

        inputs.powerSourceIsBattery = Self.isRunningOnBattery()
        inputs.lowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
        inputs.thermalState = ProcessInfo.processInfo.thermalState
        inputs.screenIsLocked = screenIsLocked
        inputs.displaysAreAsleep = displaysAreAsleep
        inputs.systemIsAsleep = systemIsAsleep
        inputs.sessionIsActive = sessionIsActive
        inputs.desktopIsOccluded = false // decided per window

        return inputs
    }

    /// After a wake (display or system) the window server may have dropped our
    /// desktop-level windows: re-cycle their frames, re-assert level/stacking
    /// and re-evaluate the policy.
    private func recoverAfterWake() {
        refreshScreens()
        for window in windowsByKey.values {
            window.reassertOnWake()
        }
        reapplyPlaybackPolicy()
    }

    // MARK: - Occlusion fallback timer

    private func updateOcclusionTimer(hasActiveWindow: Bool) {
        let needed = isRunning && pauseWhenOccluded && hasActiveWindow
        if needed {
            guard occlusionTimer == nil else { return }
            let timer = Timer(timeInterval: Self.occlusionPollInterval, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.reapplyPlaybackPolicy()
                }
            }
            timer.tolerance = 1
            RunLoop.main.add(timer, forMode: .common)
            occlusionTimer = timer
        } else {
            invalidateOcclusionTimer()
        }
    }

    private func invalidateOcclusionTimer() {
        occlusionTimer?.invalidate()
        occlusionTimer = nil
    }

    // MARK: - Private

    private func createWindow(for screen: NSScreen) -> WallpaperDesktopWindow {
        let window = WallpaperDesktopWindow(screen: screen)
        window.onOcclusionStateChanged = { [weak self] in
            MainActor.assumeIsolated {
                self?.reapplyPlaybackPolicy()
            }
        }
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
        }

        refreshStatuses()
    }

    private func persistAssignment(screenKey: String, videoID: String) {
        let assignment = ScreenAssignment(screenKey: screenKey, videoId: videoID)
        try? repository.setAssignment(assignment)
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

// MARK: - Power source observation support

/// Notification names used by the engine's own wiring.
private enum SystemNotification {
    static let screenLocked = Notification.Name("com.apple.screenIsLocked")
    static let screenUnlocked = Notification.Name("com.apple.screenIsUnlocked")
    /// Posted from the IOKit run loop source callback below.
    static let powerSourceChanged = Notification.Name("app.magicwall.powerSourceChanged")
}

/// Retains the handler invoked by the C callback of the power-source run loop
/// source (the callback itself cannot capture Swift context).
private final class PowerSourceCallbackBox {
    let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }
}

/// C-compatible trampoline required by `IOPSNotificationCreateRunLoopSource`.
private func magicWallPowerSourceChangedCallback(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let box = Unmanaged<PowerSourceCallbackBox>.fromOpaque(context).takeUnretainedValue()
    box.handler()
}
