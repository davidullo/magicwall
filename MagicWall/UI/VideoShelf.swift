import MagicWallCore
import SwiftUI

/// Horizontal, lazily loaded carousel used by the Home shelves.
struct VideoShelf: View {
    let title: String
    var subtitle: String?
    let videos: [Video]
    let membership: [String: Set<Int64>]
    let onOpen: (Video) -> Void
    let onNewCategory: () -> Void

    @EnvironmentObject private var viewModel: LibraryViewModel
    @EnvironmentObject private var engine: WallpaperEngine
    @Environment(\.libraryDidMutate) private var libraryDidMutate

    private let cardWidth: CGFloat = 264

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: title, subtitle: subtitle)
                .padding(.horizontal, MagicWallTheme.gutter)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(videos) { video in
                        VideoCard(
                            video: video,
                            isFavorite: viewModel.favoriteIDs.contains(video.id),
                            isLive: engine.statuses.contains { $0.videoID == video.id },
                            onOpen: { onOpen(video) }
                        )
                        .frame(width: cardWidth)
                        .contextMenu { contextMenu(for: video) }
                    }
                }
                .padding(.horizontal, MagicWallTheme.gutter)
                .padding(.vertical, 10)
            }
            .scrollClipDisabled()
            .frame(height: MagicWallTheme.shelfHeight)
        }
    }

    @ViewBuilder
    private func contextMenu(for video: Video) -> some View {
        VideoContextMenu(
            video: video,
            isFavorite: viewModel.favoriteIDs.contains(video.id),
            statuses: engine.statuses,
            categoryItems: VideoMenuFactory.categoryItems(
                for: video,
                categories: viewModel.categories,
                membership: membership
            ),
            actions: VideoMenuFactory.actions(
                for: video,
                viewModel: viewModel,
                engine: engine,
                onNewCategory: onNewCategory,
                didMutate: libraryDidMutate
            )
        )
    }
}
