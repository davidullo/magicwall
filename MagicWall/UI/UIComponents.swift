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
    viewModel.statusMessage = "“\(video.title)” applicato su \(screen.magicWallName)."
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

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(text)
                .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(.white.opacity(0.92))
        .background(Color.white.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
    }
}

struct LiveBadge: View {
    var compact = false

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(.white)
                .frame(width: 5, height: 5)
            Text(compact ? "LIVE" : "IN ONDA")
                .font(.system(size: compact ? 9 : 10, weight: .heavy))
                .tracking(0.4)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .foregroundStyle(.white)
        .background(MagicWallTheme.live, in: Capsule())
    }
}

/// Filled gradient call-to-action button.
struct GradientActionButton: View {
    let title: String
    let systemImage: String
    var compact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: compact ? 12 : 14, weight: .semibold))
                .padding(.horizontal, compact ? 13 : 20)
                .padding(.vertical, compact ? 7 : 11)
                .foregroundStyle(.white)
                .background(MagicWallTheme.accentGradient, in: Capsule())
        }
        .buttonStyle(PressableButtonStyle())
    }
}

/// Tinted secondary button used next to `GradientActionButton`.
struct TintedActionButton: View {
    let title: String
    let systemImage: String
    var compact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: compact ? 12 : 14, weight: .semibold))
                .padding(.horizontal, compact ? 12 : 18)
                .padding(.vertical, compact ? 7 : 11)
                .foregroundStyle(.white.opacity(0.95))
                .background(Color.white.opacity(0.14), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        }
        .buttonStyle(PressableButtonStyle())
    }
}

/// Small circular icon button for top bars and overlay chrome.
struct CircleIconButton: View {
    let systemImage: String
    var size: CGFloat = 30
    var tint: Color = .white
    var background: Color = Color.white.opacity(0.12)
    var help: String?
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(isHovering ? background.opacity(1.4) : background, in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { isHovering = $0 }
        .help(help ?? "")
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

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let trailing {
                trailing
            }
        }
    }
}

// MARK: - Empty states

struct EmptyLibraryState: View {
    let onImport: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(MagicWallTheme.accent.opacity(0.14))
                    .frame(width: 96, height: 96)
                Image(systemName: "sparkles.tv")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(MagicWallTheme.accentGradient)
            }
            Text("La tua libreria è vuota")
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text("Trascina qui i tuoi video MP4/MOV oppure importali\ne scegli il wallpaper che animerà il desktop.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            GradientActionButton(title: "Importa video", systemImage: "plus", action: onImport)
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

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
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
        Menu("Categorie") {
            if items.isEmpty {
                Text("Nessuna categoria")
            }
            ForEach(items) { item in
                Toggle(item.name, isOn: Binding(
                    get: { item.isOn },
                    set: { _ in actions.toggleCategory(item.id) }
                ))
            }
            Divider()
            Button("Nuova categoria…", action: actions.newCategory)
            if !items.isEmpty {
                Menu("Elimina categoria") {
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
        Button("Riproduci come wallpaper", action: actions.applyToAll)
        if statuses.count > 1 {
            Menu("Applica su schermo") {
                ForEach(statuses) { status in
                    Button(status.name) { actions.applyToScreen(status.id) }
                }
            }
        }
        Divider()
        CategoriesMenu(items: categoryItems, actions: actions)
        Divider()
        Button(isFavorite ? "Rimuovi dai preferiti" : "Aggiungi ai preferiti", action: actions.toggleFavorite)
        Button("Elimina video", role: .destructive, action: actions.delete)
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
