import MagicWallCore
import SwiftUI

/// Landing page: hero banner plus horizontal shelves.
struct HomeView: View {
    let videos: [Video]
    let membership: [String: Set<Int64>]
    let onOpen: (Video) -> Void
    let onNewCategory: () -> Void

    @EnvironmentObject private var viewModel: LibraryViewModel

    var body: some View {
        ScrollView {
            if videos.isEmpty {
                EmptyLibraryState(onImport: { viewModel.presentImportPanel() })
            } else {
                LazyVStack(alignment: .leading, spacing: 30) {
                    if let hero = heroVideo {
                        HeroBanner(video: hero, onOpen: { onOpen(hero) })
                            .accessibilityIdentifier("home.hero")
                    }

                    ForEach(shelves) { shelf in
                        VideoShelf(
                            title: shelf.title,
                            subtitle: shelf.subtitle,
                            videos: shelf.videos,
                            membership: membership,
                            onOpen: onOpen,
                            onNewCategory: onNewCategory
                        )
                    }
                }
                .padding(.bottom, 48)
            }
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Derived content

    private var recent: [Video] {
        videos.sorted { $0.importedAt > $1.importedAt }
    }

    private var heroVideo: Video? { recent.first }

    private var continueWatching: [Video] {
        videos
            .filter { $0.lastPlayedAt != nil }
            .sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }
    }

    private var favorites: [Video] {
        recent.filter { viewModel.favoriteIDs.contains($0.id) }
    }

    private var shelves: [HomeShelf] {
        var result: [HomeShelf] = []

        result.append(HomeShelf(
            id: "recent",
            title: L("home.shelf.recent"),
            subtitle: videoCountLabel(recent.count),
            videos: recent
        ))

        if !continueWatching.isEmpty {
            result.append(HomeShelf(
                id: "continue",
                title: L("home.shelf.continue"),
                subtitle: nil,
                videos: continueWatching
            ))
        }

        if !favorites.isEmpty {
            result.append(HomeShelf(
                id: "favorites",
                title: L("tab.favorites"),
                subtitle: "\(favorites.count)",
                videos: favorites
            ))
        }

        let shelvesByCategory = viewModel.categories.compactMap { category -> HomeShelf? in
            guard let id = category.id else { return nil }
            let items = recent.filter { membership[$0.id]?.contains(id) == true }
            guard !items.isEmpty else { return nil }
            return HomeShelf(
                id: "category-\(id)",
                title: category.name,
                subtitle: "\(items.count)",
                videos: items
            )
        }
        .prefix(4)

        result.append(contentsOf: shelvesByCategory)
        return result
    }
}

private struct HomeShelf: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let videos: [Video]
}

// MARK: - Hero

private struct HeroBanner: View {
    let video: Video
    let onOpen: () -> Void

    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var viewModel: LibraryViewModel
    @EnvironmentObject private var engine: WallpaperEngine

    private var isFavorite: Bool { viewModel.favoriteIDs.contains(video.id) }
    private var isLive: Bool { engine.statuses.contains { $0.videoID == video.id } }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            backdrop
            theme.active.heroScrim
            theme.active.heroHorizontalScrim

            VStack(alignment: .leading, spacing: 14) {
                eyebrow
                title
                badges
                actions
            }
            .padding(.horizontal, MagicWallLayout.gutter)
            .padding(.bottom, 34)
        }
        .frame(height: MagicWallLayout.heroHeight)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private var backdrop: some View {
        PosterImageView(url: video.posterURL, fallbackTitle: video.title)
            .frame(maxWidth: .infinity)
            .frame(height: MagicWallLayout.heroHeight)
    }

    private var eyebrow: some View {
        HStack(spacing: 8) {
            Text(L("home.hero.featured"))
                .font(.system(size: 10, weight: .heavy))
                .tracking(1.6)
                .foregroundStyle(theme.active.textSecondaryColor)
            if isLive {
                LiveBadge()
            }
        }
    }

    private var title: some View {
        Text(video.title)
            .font(.system(size: 42, weight: theme.active.titleFontWeight, design: .rounded))
            .foregroundStyle(theme.active.textPrimaryColor)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .shadow(color: .black.opacity(0.45), radius: 12, y: 4)
            .frame(maxWidth: 780, alignment: .leading)
    }

    private var badges: some View {
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

    private var actions: some View {
        HStack(spacing: 12) {
            PrimaryActionButton(
                title: L("home.hero.play"),
                systemImage: "play.fill"
            ) {
                viewModel.applyToAllScreens(video)
            }

            SecondaryActionButton(title: L("home.hero.preview"), systemImage: "rectangle.inset.filled.and.person.filled") {
                onOpen()
            }

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
            .animation(.easeOut(duration: 0.12), value: isFavorite)
        }
        .padding(.top, 4)
    }
}
