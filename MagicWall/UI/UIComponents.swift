import AppKit
import MagicWallCore
import SwiftUI

// MARK: - Mutation notifier

/// Lets leaf views (cards, menu items) tell `ContentView` that library data
/// changed behind the view model's back — e.g. a category assignment — so the
/// cached per-video category membership can be rebuilt.
private struct LibraryDidMutateKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var libraryDidMutate: () -> Void {
        get { self[LibraryDidMutateKey.self] }
        set { self[LibraryDidMutateKey.self] = newValue }
    }
}

/// Applies a wallpaper on a single screen identified by its engine key.
@MainActor
func applyWallpaper(
    _ video: Video,
    toScreenKey key: String,
    viewModel: LibraryViewModel,
    engine: WallpaperEngine
) {
    guard let screen = NSScreen.screens.first(where: { $0.magicWallKey == key }) else { return }
    engine.apply(video, to: screen)
    viewModel.statusMessage = L("video.status.playingOnScreen", video.title, screen.magicWallName)
}

/// Localized count phrase for videos, e.g. "3 videos" / "3 video".
@MainActor
func videoCountLabel(_ count: Int) -> String {
    count == 1 ? L("common.videoCount.one", count) : L("common.videoCount.other", count)
}

// MARK: - Poster

/// Crops a poster into a fixed aspect ratio box (16:9 by default).
struct PosterThumbnail: View {
    let video: Video
    var aspectRatio: CGFloat = 16 / 9

    var body: some View {
        Color.clear
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay {
                PosterImageView(url: video.posterURL, fallbackTitle: video.title)
            }
            .clipped()
    }
}

// MARK: - Small building blocks

struct MetadataBadge: View {
    let icon: String
    let text: String

    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(text)
                .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(theme.active.badgeTextColor)
        .background(theme.active.badgeBackgroundColor, in: Capsule())
    }
}

struct LiveBadge: View {
    var compact = false

    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(theme.active.liveBadgeTextColor)
                .frame(width: 5, height: 5)
            Text(L("common.live"))
                .font(.system(size: compact ? 9 : 10, weight: .heavy))
                .tracking(0.4)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .foregroundStyle(theme.active.liveBadgeTextColor)
        .background(theme.active.liveBadgeBackgroundColor, in: Capsule())
    }
}

/// Primary call-to-action: flat accent fill by default, gradient only when the
/// active theme enables it.
struct PrimaryActionButton: View {
    let title: String
    let systemImage: String
    var compact = false
    let action: () -> Void

    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: compact ? 12 : 13.5, weight: .bold))
                .padding(.horizontal, compact ? 13 : 20)
                .padding(.vertical, compact ? 7 : 10)
                .foregroundStyle(theme.active.accentTextColor)
                .background(theme.active.accentShapeStyle, in: Capsule())
        }
        .buttonStyle(PressableButtonStyle())
    }
}

/// Secondary button (soft surface fill) used next to `PrimaryActionButton`.
struct SecondaryActionButton: View {
    let title: String
    let systemImage: String
    var compact = false
    let action: () -> Void

    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: compact ? 12 : 13.5, weight: .semibold))
                .padding(.horizontal, compact ? 12 : 18)
                .padding(.vertical, compact ? 7 : 10)
                .foregroundStyle(theme.active.buttonSecondaryTextColor)
                .background(theme.active.buttonSecondaryBackgroundColor, in: Capsule())
        }
        .buttonStyle(PressableButtonStyle())
    }
}

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String?
    var trailing: AnyView?

    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.system(size: 21, weight: theme.active.titleFontWeight))
                .foregroundStyle(theme.active.textPrimaryColor)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.active.textSecondaryColor)
            }
            Spacer(minLength: 8)
            if let trailing {
                trailing
            }
        }
    }
}

/// Compact surface button used by section headers ("New category", "Shuffle").
struct HeaderActionButton: View {
    let title: String
    let systemImage: String
    var isEnabled = true
    let action: () -> Void

    @EnvironmentObject private var theme: ThemeStore
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.active.buttonSecondaryTextColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    isHovering ? theme.active.surfaceHoverColor : theme.active.buttonSecondaryBackgroundColor,
                    in: Capsule()
                )
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Empty states

struct EmptyLibraryState: View {
    let onImport: () -> Void

    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(theme.active.accentColor.opacity(0.14))
                    .frame(width: 96, height: 96)
                Image(systemName: "sparkles.tv")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(theme.active.accentColor)
            }
            Text(L("empty.library.title"))
                .font(.system(size: 22, weight: theme.active.titleFontWeight))
                .foregroundStyle(theme.active.textPrimaryColor)
            Text(L("empty.library.message"))
                .font(.callout)
                .foregroundStyle(theme.active.textSecondaryColor)
                .multilineTextAlignment(.center)
            PrimaryActionButton(title: L("common.importVideos"), systemImage: "plus", action: onImport)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 70)
    }
}

struct MessageState: View {
    let icon: String
    let title: String
    let message: String

    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(theme.active.textTertiaryColor)
            Text(title)
                .font(.system(size: 18, weight: theme.active.titleFontWeight))
                .foregroundStyle(theme.active.textPrimaryColor)
            Text(message)
                .font(.callout)
                .foregroundStyle(theme.active.textSecondaryColor)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - Context menu plumbing
//
// Context-menu content is built by the parent view (which has the environment
// objects in scope) and handed to `VideoContextMenu` as plain data + closures,
// so the menu never has to resolve an `EnvironmentObject` lazily.

struct CategoryToggleItem: Identifiable {
    let id: Int64
    let name: String
    let isOn: Bool
}

struct VideoMenuActions {
    var applyToAll: () -> Void = {}
    var applyToScreen: (String) -> Void = { _ in }
    var toggleFavorite: () -> Void = {}
    var delete: () -> Void = {}
    var toggleCategory: (Int64) -> Void = { _ in }
    var newCategory: () -> Void = {}
    var deleteCategory: (Int64) -> Void = { _ in }
}

struct CategoriesMenu: View {
    let items: [CategoryToggleItem]
    let actions: VideoMenuActions

    var body: some View {
        Menu(L("category.menu")) {
            if items.isEmpty {
                Text(L("category.none"))
            }
            ForEach(items) { item in
                Toggle(item.name, isOn: Binding(
                    get: { item.isOn },
                    set: { _ in actions.toggleCategory(item.id) }
                ))
            }
            Divider()
            Button(L("category.newEllipsis"), action: actions.newCategory)
            if !items.isEmpty {
                Menu(L("category.delete")) {
                    ForEach(items) { item in
                        Button(item.name, role: .destructive) {
                            actions.deleteCategory(item.id)
                        }
                    }
                }
            }
        }
    }
}

struct VideoContextMenu: View {
    let video: Video
    let isFavorite: Bool
    let statuses: [WallpaperEngine.ScreenStatus]
    let categoryItems: [CategoryToggleItem]
    let actions: VideoMenuActions

    var body: some View {
        Button(L("video.play"), action: actions.applyToAll)
        if statuses.count > 1 {
            Menu(L("video.applyToScreen")) {
                ForEach(statuses) { status in
                    Button(status.name) { actions.applyToScreen(status.id) }
                }
            }
        }
        Divider()
        CategoriesMenu(items: categoryItems, actions: actions)
        Divider()
        Button(isFavorite ? L("card.favorite.remove") : L("card.favorite.add"), action: actions.toggleFavorite)
        Button(L("video.delete"), role: .destructive, action: actions.delete)
    }
}

/// Builds the plain data + closures a `VideoContextMenu` needs.
@MainActor
enum VideoMenuFactory {
    static func actions(
        for video: Video,
        viewModel: LibraryViewModel,
        engine: WallpaperEngine,
        onNewCategory: @escaping () -> Void,
        didMutate: @escaping () -> Void
    ) -> VideoMenuActions {
        VideoMenuActions(
            applyToAll: { viewModel.applyToAllScreens(video) },
            applyToScreen: { key in
                applyWallpaper(video, toScreenKey: key, viewModel: viewModel, engine: engine)
            },
            toggleFavorite: { viewModel.toggleFavorite(video) },
            delete: { viewModel.delete(video) },
            toggleCategory: { categoryID in
                guard let category = viewModel.categories.first(where: { $0.id == categoryID }) else { return }
                viewModel.toggleCategory(category, for: video)
                didMutate()
            },
            newCategory: onNewCategory,
            deleteCategory: { categoryID in
                guard let category = viewModel.categories.first(where: { $0.id == categoryID }) else { return }
                viewModel.deleteCategory(category)
                didMutate()
            }
        )
    }

    static func categoryItems(
        for video: Video,
        categories: [VideoCategory],
        membership: [String: Set<Int64>]
    ) -> [CategoryToggleItem] {
        let assigned = membership[video.id] ?? []
        return categories.compactMap { category in
            guard let id = category.id else { return nil }
            return CategoryToggleItem(id: id, name: category.name, isOn: assigned.contains(id))
        }
    }

    static func categoryItems(for video: Video, viewModel: LibraryViewModel) -> [CategoryToggleItem] {
        let assigned = Set(viewModel.categories(for: video).compactMap(\.id))
        return viewModel.categories.compactMap { category in
            guard let id = category.id else { return nil }
            return CategoryToggleItem(id: id, name: category.name, isOn: assigned.contains(id))
        }
    }
}
