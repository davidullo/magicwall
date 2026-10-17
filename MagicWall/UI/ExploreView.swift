import MagicWallCore
import SwiftUI

/// Discovery page: horizontal category chips on top of the adaptive grid.
struct ExploreView: View {
    let videos: [Video]
    let membership: [String: Set<Int64>]
    let onOpen: (Video) -> Void
    let onNewCategory: () -> Void
    let onRename: (Video) -> Void

    @EnvironmentObject private var viewModel: LibraryViewModel
    @Environment(\.libraryDidMutate) private var libraryDidMutate
    @State private var selectedCategoryID: Int64?

    var body: some View {
        Group {
            if viewModel.videos.isEmpty {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    chips
                        .accessibilityIdentifier("explore.chips")

                    EmptyLibraryState(onImport: { viewModel.presentImportPanel() })
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.top, MagicWallLayout.contentTopInset)
                .padding(.bottom, 48)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        header
                        chips
                            .accessibilityIdentifier("explore.chips")

                        if filteredVideos.isEmpty {
                            MessageState(
                                icon: "tray",
                                title: L("explore.empty.title"),
                                message: L("explore.empty.message")
                            )
                        } else {
                            VideoGridView(
                                videos: filteredVideos,
                                membership: membership,
                                onOpen: onOpen,
                                onNewCategory: onNewCategory,
                                onRename: onRename
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
        .onChange(of: viewModel.categories) { _, _ in
            if let id = selectedCategoryID, !viewModel.categories.contains(where: { $0.id == id }) {
                selectedCategoryID = nil
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        SectionHeader(
            title: L("tab.explore"),
            subtitle: viewModel.videos.isEmpty
                ? nil
                : videoCountLabel(filteredVideos.count),
            trailing: AnyView(
                HeaderActionButton(title: L("category.new"), systemImage: "folder.badge.plus") {
                    onNewCategory()
                }
            )
        )
        .padding(.horizontal, MagicWallLayout.gutter)
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                CategoryChip(
                    title: L("explore.filter.all"),
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
                        Button(L("category.delete"), role: .destructive) {
                            viewModel.deleteCategory(category)
                            libraryDidMutate()
                        }
                    }
                }
            }
            .padding(.horizontal, MagicWallLayout.gutter)
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

    @EnvironmentObject private var theme: ThemeStore
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text(title)
                    .font(.system(size: 12.5, weight: isSelected ? .bold : .medium))
                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        isSelected
                            ? theme.active.accentTextColor.opacity(0.22)
                            : theme.active.badgeBackgroundColor,
                        in: Capsule()
                    )
            }
            .foregroundStyle(isSelected ? theme.active.accentTextColor : theme.active.textSecondaryColor)
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background {
                if isSelected {
                    Capsule().fill(theme.active.accentShapeStyle)
                } else {
                    Capsule()
                        .fill(isHovering ? theme.active.surfaceHoverColor : theme.active.surfaceColor)
                        .overlay(Capsule().strokeBorder(theme.active.dividerColor, lineWidth: 1))
                }
            }
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { isHovering = $0 }
    }
}
