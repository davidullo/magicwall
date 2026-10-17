import MagicWallCore
import SwiftUI

/// Discovery page: horizontal category chips on top of the adaptive grid.
struct ExploreView: View {
    let videos: [Video]
    let membership: [String: Set<Int64>]
    let onOpen: (Video) -> Void
    let onNewCategory: () -> Void

    @EnvironmentObject private var viewModel: LibraryViewModel
    @Environment(\.libraryDidMutate) private var libraryDidMutate
    @State private var selectedCategoryID: Int64?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                header
                chips

                if viewModel.videos.isEmpty {
                    EmptyLibraryState(onImport: { viewModel.presentImportPanel() })
                } else if filteredVideos.isEmpty {
                    MessageState(
                        icon: "tray",
                        title: "Nessun video in questa categoria",
                        message: "Trascina qui i video o assegnane uno dal menu contestuale delle card."
                    )
                } else {
                    VideoGridView(
                        videos: filteredVideos,
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
        .onChange(of: viewModel.categories) { _, _ in
            if let id = selectedCategoryID, !viewModel.categories.contains(where: { $0.id == id }) {
                selectedCategoryID = nil
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        SectionHeader(
            title: "Explore",
            subtitle: viewModel.videos.isEmpty ? nil : "\(filteredVideos.count) video",
            trailing: AnyView(
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
            )
        )
        .padding(.horizontal, MagicWallTheme.gutter)
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                CategoryChip(
                    title: "Tutte",
                    count: viewModel.videos.count,
                    isSelected: selectedCategoryID == nil
                ) {
                    selectedCategoryID = nil
                }

                ForEach(viewModel.categories) { category in
                    CategoryChip(
                        title: category.name,
                        count: count(for: category),
                        isSelected: selectedCategoryID == category.id
                    ) {
                        selectedCategoryID = category.id
                    }
                    .contextMenu {
                        Button("Elimina categoria", role: .destructive) {
                            viewModel.deleteCategory(category)
                            libraryDidMutate()
                        }
                    }
                }
            }
            .padding(.horizontal, MagicWallTheme.gutter)
            .padding(.vertical, 2)
        }
    }

    // MARK: - Filtering

    private var filteredVideos: [Video] {
        guard let selectedCategoryID else { return videos }
        return videos.filter { membership[$0.id]?.contains(selectedCategoryID) == true }
    }

    private func count(for category: VideoCategory) -> Int {
        guard let id = category.id else { return 0 }
        return videos.reduce(into: 0) { total, video in
            if membership[video.id]?.contains(id) == true { total += 1 }
        }
    }
}

/// Pill-shaped category filter.
private struct CategoryChip: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text(title)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.white.opacity(isSelected ? 0.22 : 0.10), in: Capsule())
            }
            .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.75))
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background {
                if isSelected {
                    Capsule().fill(MagicWallTheme.accentGradient)
                } else {
                    Capsule()
                        .fill(MagicWallTheme.surface)
                        .overlay(Capsule().strokeBorder(
                            isHovering ? Color.white.opacity(0.22) : MagicWallTheme.stroke,
                            lineWidth: 1
                        ))
                }
            }
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { isHovering = $0 }
    }
}
