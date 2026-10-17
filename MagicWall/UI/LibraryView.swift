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

                if viewModel.videos.isEmpty {
                    EmptyLibraryState(onImport: { viewModel.presentImportPanel() })
                } else {
                    VideoGridView(
                        videos: videos,
                        membership: membership,
                        onOpen: onOpen,
                        onNewCategory: onNewCategory
                    )
                    .padding(.horizontal, MagicWallTheme.gutter)
                }
            }
            .padding(.top, 26)
            .padding(.bottom, 48)
        }
        .scrollIndicators(.hidden)
    }

    private var header: some View {
        SectionHeader(
            title: "Libreria",
            subtitle: viewModel.videos.isEmpty
                ? nil
                : "\(viewModel.videos.count) video · \(viewModel.librarySizeLabel)",
            trailing: AnyView(
                HStack(spacing: 8) {
                    Button {
                        onNewCategory()
                    } label: {
                        Label("Nuova categoria", systemImage: "folder.badge.plus")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.white.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(PressableButtonStyle())

                    Button {
                        viewModel.applyRandomToAllScreens()
                    } label: {
                        Label("Casuale", systemImage: "shuffle")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.white.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(PressableButtonStyle())
                    .disabled(viewModel.videos.isEmpty)
                    .opacity(viewModel.videos.isEmpty ? 0.5 : 1)
                }
            )
        )
        .padding(.horizontal, MagicWallTheme.gutter)
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
                    title: "Preferiti",
                    subtitle: videos.isEmpty ? nil : "\(videos.count) video"
                )
                .padding(.horizontal, MagicWallTheme.gutter)

                if viewModel.videos.isEmpty {
                    EmptyLibraryState(onImport: { viewModel.presentImportPanel() })
                } else if videos.isEmpty {
                    MessageState(
                        icon: "heart",
                        title: "Nessun preferito",
                        message: "Tocca il cuore su una card per ritrovare qui i tuoi wallpaper migliori."
                    )
                } else {
                    VideoGridView(
                        videos: videos,
                        membership: membership,
                        onOpen: onOpen,
                        onNewCategory: onNewCategory
                    )
                    .padding(.horizontal, MagicWallTheme.gutter)
                }
            }
            .padding(.top, 26)
            .padding(.bottom, 48)
        }
        .scrollIndicators(.hidden)
    }
}
