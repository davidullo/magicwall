import AppKit
import MagicWallCore
import SwiftUI

/// Fullscreen preview overlay: the real video, muted and looping, with the
/// wallpaper actions on top of it.
struct VideoPreviewView: View {
    let video: Video
    let onNewCategory: () -> Void
    let onClose: () -> Void

    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var viewModel: LibraryViewModel
    @EnvironmentObject private var engine: WallpaperEngine
    @Environment(\.libraryDidMutate) private var libraryDidMutate

    private var isFavorite: Bool { viewModel.favoriteIDs.contains(video.id) }
    private var isLive: Bool { engine.statuses.contains { $0.videoID == video.id } }

    var body: some View {
        ZStack {
            Color.black
                // Leaf element so the identifier does not override the
                // identifiers of the preview's own controls.
                .accessibilityIdentifier("preview.overlay")

            PreviewVideoPlayerView(url: video.fileURL)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onClose() }

            theme.active.previewBottomScrim
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                bottomBar
            }
        }
        .background(Color.black)
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack(alignment: .center, spacing: 12) {
            if isLive {
                LiveBadge()
            }

            Spacer(minLength: 8)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(.black.opacity(0.45), in: Circle())
                    .overlay(Circle().strokeBorder(theme.active.dividerColor, lineWidth: 1))
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityIdentifier("preview.close")
            .keyboardShortcut(.cancelAction)
            .help(L("preview.close.help"))
        }
        // Clear of the macOS traffic lights, which stay visible above the
        // preview because the window uses a full-size transparent titlebar.
        .padding(.leading, 88)
        .padding(.trailing, 24)
        .padding(.top, 18)
        .padding(.bottom, 40)
        .background(theme.active.previewTopScrim)
    }

    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(video.title)
                .font(.system(size: 34, weight: theme.active.titleFontWeight, design: .rounded))
                .foregroundStyle(theme.active.textPrimaryColor)
                .lineLimit(2)
                .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
                .frame(maxWidth: 820, alignment: .leading)

            metadata

            controls
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 34)
        .padding(.top, 70)
        .padding(.bottom, 34)
        .contentShape(Rectangle())
        .onTapGesture {
            // Swallow taps so they do not dismiss the preview.
        }
    }

    private var metadata: some View {
        HStack(spacing: 7) {
            if video.resolutionLabel != "—" {
                MetadataBadge(icon: "rectangle.on.rectangle", text: video.resolutionLabel)
            }
            if video.durationLabel != "—" {
                MetadataBadge(icon: "clock", text: video.durationLabel)
            }
            if let codec = video.codec, !codec.isEmpty {
                MetadataBadge(icon: "film", text: codec)
            }
            if video.fileSizeLabel != "—" {
                MetadataBadge(icon: "internaldrive", text: video.fileSizeLabel)
            }
            if video.fps > 0 {
                MetadataBadge(icon: "speedometer", text: "\(Int(video.fps.rounded())) fps")
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            PrimaryActionButton(title: L("video.applyToAllScreens"), systemImage: "play.fill") {
                viewModel.applyToAllScreens(video)
            }

            if engine.statuses.count > 1 {
                screenMenu
            }

            Menu {
                CategoriesMenuBody(items: categoryItems, actions: menuActions)
            } label: {
                CircleIconButtonLabel(systemImage: "folder")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(L("preview.manageCategories.help"))

            Button {
                viewModel.toggleFavorite(video)
            } label: {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isFavorite ? theme.active.accentColor : theme.active.textPrimaryColor)
                    .frame(width: 38, height: 38)
                    .background(theme.active.buttonSecondaryBackgroundColor, in: Circle())
            }
            .buttonStyle(PressableButtonStyle())
            .help(isFavorite ? L("card.favorite.remove") : L("card.favorite.add"))

            Button {
                viewModel.delete(video)
                onClose()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.active.dangerColor)
                    .frame(width: 38, height: 38)
                    .background(theme.active.buttonSecondaryBackgroundColor, in: Circle())
            }
            .buttonStyle(PressableButtonStyle())
            .help(L("preview.delete.help"))
        }
    }

    private var screenMenu: some View {
        Menu {
            ForEach(engine.statuses) { status in
                Button {
                    applyWallpaper(video, toScreenKey: status.id, viewModel: viewModel, engine: engine)
                } label: {
                    if status.videoID == video.id {
                        Label(L("video.screenAlreadyActive", status.name), systemImage: "checkmark")
                    } else {
                        Text(status.name)
                    }
                }
            }
        } label: {
            SecondaryActionButtonLabel(title: L("video.applyToScreen"), systemImage: "display")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: - Menu data

    private var categoryItems: [CategoryToggleItem] {
        VideoMenuFactory.categoryItems(for: video, viewModel: viewModel)
    }

    private var menuActions: VideoMenuActions {
        VideoMenuFactory.actions(
            for: video,
            viewModel: viewModel,
            engine: engine,
            onNewCategory: onNewCategory,
            didMutate: libraryDidMutate
        )
    }
}

/// Circular label used by menu-styled overlay buttons.
struct CircleIconButtonLabel: View {
    let systemImage: String
    var size: CGFloat = 38

    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(theme.active.textPrimaryColor)
            .frame(width: size, height: size)
            .background(theme.active.buttonSecondaryBackgroundColor, in: Circle())
    }
}

/// Capsule label matching `SecondaryActionButton`, usable as a `Menu` label.
struct SecondaryActionButtonLabel: View {
    let title: String
    let systemImage: String

    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 13.5, weight: .semibold))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .foregroundStyle(theme.active.buttonSecondaryTextColor)
            .background(theme.active.buttonSecondaryBackgroundColor, in: Capsule())
    }
}

/// The category items of `CategoriesMenu` without its "Categories" wrapper,
/// so they can live directly in a top-level menu.
struct CategoriesMenuBody: View {
    let items: [CategoryToggleItem]
    let actions: VideoMenuActions

    var body: some View {
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
