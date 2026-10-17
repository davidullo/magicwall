import AppKit
import SwiftUI

/// Loads a poster JPEG from disk off the main thread and caches it in memory.
struct PosterImageView: View {
    let url: URL?
    var fallbackTitle: String = ""

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.18), Color(white: 0.10)],
                startPoint: .top,
                endPoint: .bottom
            )
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if !fallbackTitle.isEmpty {
                Text(fallbackTitle)
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
        .clipped()
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else {
            image = nil
            return
        }
        if let cached = PosterImageCache.shared.image(for: url) {
            image = cached
            return
        }
        let loaded = await Task.detached(priority: .userInitiated) {
            NSImage(contentsOf: url)
        }.value
        if let loaded {
            PosterImageCache.shared.set(loaded, for: url)
        }
        image = loaded
    }
}

/// Simple in-memory LRU-ish cache for poster images.
final class PosterImageCache {
    static let shared = PosterImageCache()

    private let cache = NSCache<NSURL, NSImage>()

    private init() {
        cache.countLimit = 400
    }

    func image(for url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }

    func set(_ image: NSImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }
}
