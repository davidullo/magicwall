import MagicWallCore
import SwiftUI

/// Full library grid: every imported video, with category management and
/// deletion available from each card's context menu.
struct LibraryView: View {
    let videos: [Video]
    let membership: [String: Set<Int64>]
    let onOpen: (Video) -> Void
    let onNewCategory: () -> Void

    @EnvironmentObject private var viewModel: LibraryViewModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                header
                    .accessibilityIdentifier("library.header")

                if viewModel.videos.isEmpty {
                    EmptyLibraryState(onImport: { viewModel.presentImportPanel() })
                } else {
                    VideoGridView(
                        videos: videos,
                        membership: membership,
                        onOpen: onOpen,
                        onNewCategory: onNewCategory
                    )
                    .padding(.horizontal, MagicWallLayout.gutter)
                }
            }
            .padding(.top, MagicWallLayout.contentTopInset)
            .padding(.bottom, 48)
        }
        .scrollIndicators(.hidden)
    }

    private var header: some View {
        SectionHeader(
            title: L("tab.library"),
            subtitle: viewModel.videos.isEmpty
                ? nil
                : "\(videoCountLabel(viewModel.videos.count)) · \(viewModel.librarySizeLabel)",
            trailing: AnyView(
                HStack(spacing: 8) {
                    HeaderActionButton(title: L("category.new"), systemImage: "folder.badge.plus") {
                        onNewCategory()
                    }

                    HeaderActionButton(
                        title: L("library.shuffle"),
                        systemImage: "shuffle",
                        isEnabled: !viewModel.videos.isEmpty
                    ) {
                        viewModel.applyRandomToAllScreens()
                    }
                }
            )
        )
        .padding(.horizontal, MagicWallLayout.gutter)
    }
}

/// Same grid, restricted to favorites.
struct FavoritesView: View {
    let videos: [Video]
    let membership: [String: Set<Int64>]
    let onOpen: (Video) -> Void
    let onNewCategory: () -> Void

    @EnvironmentObject private var viewModel: LibraryViewModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                SectionHeader(
                    title: L("tab.favorites"),
                    subtitle: videos.isEmpty ? nil : videoCountLabel(videos.count)
                )
                .padding(.horizontal, MagicWallLayout.gutter)

                if viewModel.videos.isEmpty {
                    EmptyLibraryState(onImport: { viewModel.presentImportPanel() })
                } else if videos.isEmpty {
                    MessageState(
                        icon: "heart",
                        title: L("favorites.empty.title"),
                        message: L("favorites.empty.message")
                    )
                } else {
                    VideoGridView(
                        videos: videos,
                        membership: membership,
                        onOpen: onOpen,
                        onNewCategory: onNewCategory
                    )
                    .padding(.horizontal, MagicWallLayout.gutter)
                }
            }
            .padding(.top, MagicWallLayout.contentTopInset)
            .padding(.bottom, 48)
        }
        .scrollIndicators(.hidden)
    }
}
