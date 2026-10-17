import MagicWallCore
import SwiftUI

/// Full library grid: every imported video, with category management and
/// deletion available from each card's context menu.
struct LibraryView: View {
    let videos: [Video]
    let membership: [String: Set<Int64>]
    let onOpen: (Video) -> Void
    let onNewCategory: () -> Void
    let onRename: (Video) -> Void

    @EnvironmentObject private var viewModel: LibraryViewModel

    var body: some View {
        Group {
            if viewModel.videos.isEmpty {
                VStack(alignment: .leading, spacing: 22) {
                    header
                        .accessibilityIdentifier("library.header")

                    EmptyLibraryState(onImport: { viewModel.presentImportPanel() })
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.top, MagicWallLayout.contentTopInset)
                .padding(.bottom, 48)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        header
                            .accessibilityIdentifier("library.header")

                        VideoGridView(
                            videos: videos,
                            membership: membership,
                            onOpen: onOpen,
                            onNewCategory: onNewCategory,
                            onRename: onRename
                        )
                        .padding(.horizontal, MagicWallLayout.gutter)
                    }
                    .padding(.top, MagicWallLayout.contentTopInset)
                    .padding(.bottom, 48)
                }
                .scrollIndicators(.hidden)
            }
        }
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
    let onRename: (Video) -> Void

    @EnvironmentObject private var viewModel: LibraryViewModel

    var body: some View {
        Group {
            if viewModel.videos.isEmpty {
                VStack(alignment: .leading, spacing: 22) {
                    favoritesHeader

                    EmptyLibraryState(onImport: { viewModel.presentImportPanel() })
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.top, MagicWallLayout.contentTopInset)
                .padding(.bottom, 48)
            } else if videos.isEmpty {
                VStack(alignment: .leading, spacing: 22) {
                    favoritesHeader

                    MessageState(
                        icon: "heart",
                        title: L("favorites.empty.title"),
                        message: L("favorites.empty.message")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.top, MagicWallLayout.contentTopInset)
                .padding(.bottom, 48)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        favoritesHeader

                        FavoritesRotationBar()
                            .padding(.horizontal, MagicWallLayout.gutter)

                        VideoGridView(
                            videos: videos,
                            membership: membership,
                            onOpen: onOpen,
                            onNewCategory: onNewCategory,
                            onRename: onRename
                        )
                        .padding(.horizontal, MagicWallLayout.gutter)
                    }
                    .padding(.top, MagicWallLayout.contentTopInset)
                    .padding(.bottom, 48)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var favoritesHeader: some View {
        SectionHeader(
            title: L("tab.favorites"),
            subtitle: videos.isEmpty ? nil : videoCountLabel(videos.count)
        )
        .padding(.horizontal, MagicWallLayout.gutter)
    }
}
