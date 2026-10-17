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
final class WallpaperDesktopWindow: NSWindow {
    private let playerLayer = AVPlayerLayer()
    private var queuePlayer: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private(set) var videoID: String?

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
    }

    func show(video: Video) {
        loadPlayer(for: video.fileURL)
        videoID = video.id
        alphaValue = 1
        orderFrontRegardless()
    }

    func setPaused(_ paused: Bool) {
        guard let queuePlayer else { return }
        if paused {
            if queuePlayer.rate != 0 { queuePlayer.pause() }
        } else {
            if queuePlayer.rate == 0 { queuePlayer.play() }
        }
    }

    func clear() {
        queuePlayer?.pause()
        looper?.disableLooping()
        looper = nil
        queuePlayer = nil
        playerLayer.player = nil
        videoID = nil
        alphaValue = 0
        orderOut(nil)
    }

    func updateFrame(for screen: NSScreen) {
        setFrame(screen.frame, display: false)
        contentView?.frame = NSRect(origin: .zero, size: screen.frame.size)
        playerLayer.frame = contentView?.bounds ?? .zero
    }

    // MARK: - Private

    private func loadPlayer(for url: URL) {
        queuePlayer?.pause()
        looper?.disableLooping()

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
        player.play()
    }
}
