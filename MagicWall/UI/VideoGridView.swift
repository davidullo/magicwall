import MagicWallCore
import SwiftUI

/// Reusable adaptive grid of `VideoCard`s with the shared context menu.
struct VideoGridView: View {
    let videos: [Video]
    let membership: [String: Set<Int64>]
    let onOpen: (Video) -> Void
    let onNewCategory: () -> Void
    var minimumWidth: CGFloat = 232
    var maximumWidth: CGFloat = 300

    @EnvironmentObject private var viewModel: LibraryViewModel
    @EnvironmentObject private var engine: WallpaperEngine
    @Environment(\.libraryDidMutate) private var libraryDidMutate

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: minimumWidth, maximum: maximumWidth), spacing: 18)]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
            ForEach(videos) { video in
                VideoCard(
                    video: video,
                    isFavorite: viewModel.favoriteIDs.contains(video.id),
                    isLive: isLive(video),
                    onOpen: { onOpen(video) }
                )
                .contextMenu { contextMenu(for: video) }
            }
        }
    }

    private func isLive(_ video: Video) -> Bool {
        engine.statuses.contains { $0.videoID == video.id }
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
