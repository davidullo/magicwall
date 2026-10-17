import AppKit
import AVFoundation
import Combine
import Foundation
import MagicWallCore

/// Stable identity and metadata for a display.
extension NSScreen {
    var magicWallDisplayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    /// Stable key used to persist per-screen assignments.
    var magicWallKey: String { "display:\(magicWallDisplayID)" }

    var magicWallName: String { localizedName }
}

/// Fullscreen, borderless, non-interactive window that plays a looping video
/// at the desktop level (above the wallpaper, below desktop icons).
///
/// One window — and therefore at most one `AVQueuePlayer` — exists per screen.
/// An emptied window holds no player at all, and re-showing the same video is
/// a no-op on the media pipeline so the decoder keeps its buffers.
final class WallpaperDesktopWindow: NSWindow {
    private let playerLayer = AVPlayerLayer()
    private var queuePlayer: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private(set) var videoID: String?
    /// File currently loaded, kept so the pipeline can be rebuilt after the
    /// bytes on disk were replaced (starter wallpaper quality upgrade).
    private var loadedURL: URL?

    /// Invoked on the main thread when the desktop window's occlusion state
    /// changes. Owned by ``WallpaperEngine``; the callback only reads live
    /// state, so a spurious call is harmless.
    var onOcclusionStateChanged: (() -> Void)?

    /// `true` when the window has a video but is not visible on screen, i.e.
    /// something (a fullscreen app, another space, a maximised window) covers
    /// the desktop. Reads live state so it is correct even if the delegate
    /// callback never fires.
    var isDesktopOccluded: Bool {
        videoID != nil && !occlusionState.contains(.visible)
    }

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        ignoresMouseEvents = true
        isMovable = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        alphaValue = 0

        let host = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.black.cgColor
        host.autoresizingMask = [.width, .height]

        playerLayer.frame = host.bounds
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        playerLayer.backgroundColor = NSColor.black.cgColor
        host.layer?.addSublayer(playerLayer)

        contentView = host
        setFrame(screen.frame, display: false)
        delegate = self
    }

    /// Displays `video`, reusing the running player when it already plays the
    /// very same item (cheap re-apply from the UI, wake recovery, …).
    func show(video: Video) {
        if videoID != video.id || queuePlayer == nil {
            loadPlayer(for: video.fileURL)
            videoID = video.id
        }
        alphaValue = 1
        orderFrontRegardless()
    }

    /// Rebuilds the media pipeline from the file on disk. Used when the file
    /// behind the current wallpaper was replaced (starter quality upgrade) —
    /// `show(video:)` would keep running the old bytes because the id matches.
    func reloadPlayer() {
        guard let loadedURL else { return }
        loadPlayer(for: loadedURL)
    }

    /// Starts or suspends decoding. Never allocates or tears down the player.
    func setPlaying(_ playing: Bool) {
        guard let queuePlayer else { return }
        if playing {
            if queuePlayer.rate == 0 { queuePlayer.play() }
        } else {
            if queuePlayer.rate != 0 { queuePlayer.pause() }
        }
    }

    /// Backwards-compatible shim for the older pause-only entry point.
    func setPaused(_ paused: Bool) {
        setPlaying(!paused)
    }

    /// Stops playback, releases the player and hides the window. The window
    /// itself is kept alive by the engine so it can be reused later.
    func clear() {
        teardownPlayer()
        videoID = nil
        alphaValue = 0
        orderOut(nil)
    }

    /// Re-asserts level and stacking after a display/system wake and after the
    /// window server rebuilt the desktop layers. No-op while empty.
    func reassertOnWake() {
        guard videoID != nil else { return }
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        orderFrontRegardless()
    }

    /// Final teardown before the app quits. Idempotent.
    func prepareForTermination() {
        teardownPlayer()
        videoID = nil
        onOcclusionStateChanged = nil
        delegate = nil
        alphaValue = 0
    }

    func updateFrame(for screen: NSScreen) {
        setFrame(screen.frame, display: false)
        contentView?.frame = NSRect(origin: .zero, size: screen.frame.size)
        playerLayer.frame = contentView?.bounds ?? .zero
    }

    // MARK: - Private

    private func teardownPlayer() {
        if let queuePlayer {
            queuePlayer.rate = 0
            queuePlayer.pause()
        }
        looper?.disableLooping()
        looper = nil
        queuePlayer = nil
        playerLayer.player = nil
        loadedURL = nil
    }

    private func loadPlayer(for url: URL) {
        if let queuePlayer {
            queuePlayer.rate = 0
            queuePlayer.pause()
        }
        looper?.disableLooping()
        looper = nil
        queuePlayer = nil
        playerLayer.player = nil

        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer()
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.allowsExternalPlayback = false
        player.automaticallyWaitsToMinimizeStalling = true

        let newLooper = AVPlayerLooper(player: player, templateItem: item)

        playerLayer.player = player
        queuePlayer = player
        looper = newLooper
        loadedURL = url
        player.play()
    }
}

// MARK: - NSWindowDelegate

extension WallpaperDesktopWindow: NSWindowDelegate {
    func windowDidChangeOcclusionState(_ notification: Notification) {
        onOcclusionStateChanged?()
    }
}
