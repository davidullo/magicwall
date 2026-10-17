import AppKit
import AVFoundation
import SwiftUI

/// Muted, gapless looping local video used by the fullscreen preview.
///
/// `AVPlayerLayer` + `AVPlayerLooper` keep the exact behaviour of the wallpaper
/// engine (hardware decoding, no gap between loops) while `resizeAspectFill`
/// makes the preview cover the window.
struct PreviewVideoPlayerView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PreviewPlayerHostView {
        PreviewPlayerHostView()
    }

    func updateNSView(_ nsView: PreviewPlayerHostView, context: Context) {
        nsView.play(url: url)
    }

    static func dismantleNSView(_ nsView: PreviewPlayerHostView, coordinator: ()) {
        nsView.stop()
    }
}

final class PreviewPlayerHostView: NSView {
    private let playerLayer = AVPlayerLayer()
    private var queuePlayer: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var loadedURL: URL?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.backgroundColor = NSColor.black.cgColor
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }

    /// Starts (or restarts) playback of `url`, muted and looped forever.
    func play(url: URL) {
        if loadedURL != url {
            teardown()
            loadedURL = url

            let item = AVPlayerItem(url: url)
            let player = AVQueuePlayer()
            player.isMuted = true
            player.volume = 0
            player.actionAtItemEnd = .advance

            looper = AVPlayerLooper(player: player, templateItem: item)
            queuePlayer = player
            playerLayer.player = player
        }
        queuePlayer?.play()
    }

    func stop() {
        teardown()
    }

    private func teardown() {
        queuePlayer?.pause()
        looper?.disableLooping()
        looper = nil
        queuePlayer = nil
        playerLayer.player = nil
        loadedURL = nil
    }
}
