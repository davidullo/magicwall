import MagicWallCore
import SwiftUI

struct VideoCard: View {
    let video: Video
    let isFavorite: Bool
    let isApplied: Bool
    let onApply: () -> Void
    let onToggleFavorite: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PosterImageView(url: video.posterURL, fallbackTitle: video.title)
                .frame(height: 156)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    Text(video.durationLabel)
                        .font(.caption2.monospacedDigit())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.65), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(8)
                }
                .overlay(alignment: .topTrailing) {
                    Button(action: onToggleFavorite) {
                        Image(systemName: isFavorite ? "heart.fill" : "heart")
                            .font(.caption)
                            .foregroundStyle(isFavorite ? Color.red : Color.white)
                            .padding(6)
                            .background(.black.opacity(0.45), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                    .opacity(isHovering || isFavorite ? 1 : 0)
                }
                .overlay(alignment: .topLeading) {
                    if isApplied {
                        Label("Live", systemImage: "desktopcomputer")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.green.opacity(0.85), in: Capsule())
                            .foregroundStyle(.white)
                            .padding(8)
                    }
                }
                .overlay {
                    if isHovering {
                        Button(action: onApply) {
                            Image(systemName: "play.fill")
                                .font(.title3)
                                .foregroundStyle(.white)
                                .padding(14)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Set as wallpaper on all screens")
                    }
                }
                .onHover { isHovering = $0 }
                .animation(.easeOut(duration: 0.12), value: isHovering)

            VStack(alignment: .leading, spacing: 2) {
                Text(video.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var subtitle: String {
        [video.resolutionLabel, video.durationLabel, video.fileSizeLabel, video.codec ?? ""]
            .filter { !$0.isEmpty && $0 != "—" }
            .joined(separator: " · ")
    }
}
