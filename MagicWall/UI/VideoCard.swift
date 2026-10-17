import MagicWallCore
import SwiftUI

/// Library thumbnail: poster, metadata, hover affordances (play + favorite)
/// and a LIVE badge when the video is currently used as wallpaper.
struct VideoCard: View {
    let video: Video
    var isFavorite: Bool = false
    var isLive: Bool = false
    let onOpen: () -> Void

    @EnvironmentObject private var viewModel: LibraryViewModel
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            thumbnail
            details
        }
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
        }
        .help("Apri l’anteprima di “\(video.title)”")
    }

    // MARK: - Poster

    private var thumbnail: some View {
        PosterThumbnail(video: video)
            .clipShape(RoundedRectangle(cornerRadius: MagicWallTheme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MagicWallTheme.cardRadius, style: .continuous)
                    .strokeBorder(
                        isHovering ? Color.white.opacity(0.35) : MagicWallTheme.stroke,
                        lineWidth: 1
                    )
            )
            .overlay(alignment: .topLeading) {
                if isLive {
                    LiveBadge(compact: true).padding(8)
                }
            }
            .overlay(alignment: .topTrailing) {
                favoriteButton
                    .padding(8)
                    .opacity(isHovering || isFavorite ? 1 : 0)
            }
            .overlay(alignment: .bottomTrailing) {
                Text(video.durationLabel)
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .foregroundStyle(.white)
                    .background(.black.opacity(0.6), in: Capsule())
                    .padding(8)
                    .opacity(video.durationLabel == "—" ? 0 : 1)
            }
            .overlay { playOverlay }
            .scaleEffect(isHovering ? 1.03 : 1)
            .shadow(color: .black.opacity(isHovering ? 0.55 : 0), radius: 14, y: 8)
    }

    @ViewBuilder
    private var playOverlay: some View {
        if isHovering {
            ZStack {
                Color.black.opacity(0.32)
                Circle()
                    .fill(.white)
                    .frame(width: 46, height: 46)
                    .overlay {
                        Image(systemName: "play.fill")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.black)
                            .offset(x: 1.5)
                    }
                    .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
            }
            .clipShape(RoundedRectangle(cornerRadius: MagicWallTheme.cardRadius, style: .continuous))
            .transition(.opacity)
            .allowsHitTesting(false)
        }
    }

    private var favoriteButton: some View {
        Button {
            viewModel.toggleFavorite(video)
        } label: {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isFavorite ? Color(red: 1, green: 0.28, blue: 0.42) : .white)
                .frame(width: 26, height: 26)
                .background(.black.opacity(0.5), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.14), lineWidth: 1))
        }
        .buttonStyle(PressableButtonStyle())
        .help(isFavorite ? "Rimuovi dai preferiti" : "Aggiungi ai preferiti")
        .animation(.easeOut(duration: 0.12), value: isFavorite)
    }

    // MARK: - Text

    private var details: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(video.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
                .lineLimit(1)

            Text(metadataLine)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var metadataLine: String {
        var parts: [String] = []
        if video.resolutionLabel != "—" { parts.append(video.resolutionLabel) }
        if video.durationLabel != "—" { parts.append(video.durationLabel) }
        if let codec = video.codec, !codec.isEmpty { parts.append(codec) }
        if video.fileSizeLabel != "—" { parts.append(video.fileSizeLabel) }
        return parts.joined(separator: " · ")
    }
}
