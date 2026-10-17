import AppKit
import MagicWallCore
import SwiftUI
import UniformTypeIdentifiers

/// Root view of the library window: a translucent sidebar plus the detail area.
///
/// Owns nothing but presentation state: the current tab, the previewed video,
/// drag & drop targeting and a cached map of video → category IDs (rebuilt only
/// when the library actually changes, never while scrolling).
struct ContentView: View {
    @EnvironmentObject private var viewModel: LibraryViewModel
    @EnvironmentObject private var engine: WallpaperEngine
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var starterService: StarterWallpaperService

    @State private var tab: AppTab = .home
    @State private var previewVideo: Video?
    @State private var isDropTargeted = false
    @State private var membership: [String: Set<Int64>] = [:]

    /// Automatic pause currently announced in the banner (one notice per rule
    /// and session — the menu bar keeps showing the state anyway).
    @State private var pauseNotice: PlaybackPolicy.Reason?
    @State private var shownPauseNotices: Set<String> = []

    @State private var isStarterSheetPresented = false

    @State private var isNamingCategory = false
    @State private var newCategoryName = ""

    @State private var renamingVideo: Video?
    @State private var renameText = ""

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                SidebarView(
                    tab: $tab,
                    onImport: { viewModel.presentImportPanel() },
                    onShuffle: { viewModel.applyRandomToAllScreens() }
                )

                detail
            }
            .frame(minWidth: 980, minHeight: 620)
            .background(theme.active.windowBackgroundColor)
            .background(WindowChromeConfigurator())
            .ignoresSafeArea()

            // The preview floats above the whole window — sidebar included — so
            // it can never linger behind the user while they navigate beneath it.
            if let video = previewVideo {
                VideoPreviewView(
                    video: video,
                    onNewCategory: beginCategoryCreation,
                    onRename: beginRenaming,
                    onClose: {
                        withAnimation(.easeOut(duration: 0.15)) { previewVideo = nil }
                    }
                )
                .ignoresSafeArea()
                .transition(.opacity)
                .zIndex(3)
            }
        }
        .environment(\.libraryDidMutate, { rebuildMembership() })
        .preferredColorScheme(theme.active.preferredColorScheme)
        .task { rebuildMembership() }
        .task { await presentStarterOfferIfNeeded() }
        .onChange(of: viewModel.videos) { _, _ in
            rebuildMembership()
            maybePresentStarterOffer()
        }
        .onChange(of: engine.pauseReasons) { _, reasons in
            updatePauseNotice(for: reasons)
        }
        .onChange(of: starterService.status) { _, newStatus in
            // The library must learn about the newly downloaded videos once the
            // batch reaches a resting state.
            switch newStatus {
            case .installed, .partial:
                viewModel.refresh()
            case .available, .downloading, .failed:
                break
            }
        }
        .sheet(isPresented: $isStarterSheetPresented) {
            StarterWallpaperSheet(
                service: starterService,
                onClose: { isStarterSheetPresented = false }
            )
            .environmentObject(theme)
        }
        .onChange(of: viewModel.categories) { _, _ in rebuildMembership() }
        .onChange(of: tab) { _, newTab in
            if previewVideo != nil {
                withAnimation(.easeOut(duration: 0.15)) { previewVideo = nil }
            }
            if newTab == .library {
                viewModel.refresh()
            }
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted) { providers in
            Task { await handleDrop(providers) }
            return true
        }
        .alert(L("category.new"), isPresented: $isNamingCategory) {
            TextField(L("category.nameField"), text: $newCategoryName)
            Button(L("category.create")) { createCategory() }
            Button(L("common.cancel"), role: .cancel) { newCategoryName = "" }
        } message: {
            Text(L("category.new.message"))
        }
        .alert(L("video.rename.title"), isPresented: isRenamingVideoPresented) {
            TextField(L("video.rename.field"), text: $renameText)
                .accessibilityIdentifier("rename.field")
            Button(L("common.save")) { commitRename() }
                .accessibilityIdentifier("rename.save")
            Button(L("common.cancel"), role: .cancel) {
                renamingVideo = nil
                renameText = ""
            }
            .accessibilityIdentifier("rename.cancel")
        } message: {
            Text(L("video.rename.message"))
        }
    }

    // MARK: - Detail

    private var detail: some View {
        ZStack(alignment: .top) {
            content
            overlays
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.active.windowBackgroundColor)
    }

    // MARK: - Tab content

    @ViewBuilder
    private var content: some View {
        let query = viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        if !query.isEmpty {
            searchResults(query: query)
        } else {
            switch tab {
            case .home:
                HomeView(
                    videos: viewModel.videos,
                    membership: membership,
                    onOpen: open,
                    onNewCategory: beginCategoryCreation,
                    onRename: beginRenaming
                )
            case .explore:
                ExploreView(
                    videos: viewModel.videos,
                    membership: membership,
                    onOpen: open,
                    onNewCategory: beginCategoryCreation,
                    onRename: beginRenaming
                )
            case .library:
                LibraryView(
                    videos: viewModel.videos,
                    membership: membership,
                    onOpen: open,
                    onNewCategory: beginCategoryCreation,
                    onRename: beginRenaming
                )
            case .favorites:
                FavoritesView(
                    videos: viewModel.videos.filter { viewModel.favoriteIDs.contains($0.id) },
                    membership: membership,
                    onOpen: open,
                    onNewCategory: beginCategoryCreation,
                    onRename: beginRenaming
                )
            }
        }
    }

    private func searchResults(query: String) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                SectionHeader(
                    title: L("search.results", query),
                    subtitle: videoCountLabel(viewModel.displayVideos.count)
                )
                .padding(.horizontal, MagicWallLayout.gutter)

                if viewModel.displayVideos.isEmpty {
                    MessageState(
                        icon: "magnifyingglass",
                        title: L("search.empty.title"),
                        message: L("search.empty.message")
                    )
                } else {
                    VideoGridView(
                        videos: viewModel.displayVideos,
                        membership: membership,
                        onOpen: open,
                        onNewCategory: beginCategoryCreation,
                        onRename: beginRenaming
                    )
                    .padding(.horizontal, MagicWallLayout.gutter)
                }
            }
            .padding(.top, MagicWallLayout.contentTopInset)
            .padding(.bottom, 48)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Overlays

    @ViewBuilder
    private var overlays: some View {
        VStack(spacing: 10) {
            if isDropTargeted {
                banner(
                    text: L("drop.hint"),
                    icon: "arrow.down.circle.fill",
                    tint: theme.active.accentColor,
                    dismiss: nil
                )
            } else if let error = viewModel.lastError {
                banner(
                    text: error,
                    icon: "exclamationmark.triangle.fill",
                    tint: theme.active.dangerColor,
                    dismiss: { viewModel.lastError = nil }
                )
            } else if let reason = pauseNotice {
                pauseNoticeBanner(reason)
            } else if let message = viewModel.statusMessage {
                banner(
                    text: message,
                    icon: "checkmark.circle.fill",
                    tint: theme.active.liveBadgeBackgroundColor,
                    dismiss: nil
                )
                .task(id: message) {
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    if viewModel.statusMessage == message {
                        withAnimation(.easeOut(duration: 0.15)) { viewModel.statusMessage = nil }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 22)
        .animation(.easeOut(duration: 0.15), value: viewModel.statusMessage)
        .animation(.easeOut(duration: 0.15), value: isDropTargeted)

        dropHighlight
    }

    private var dropHighlight: some View {
        RoundedRectangle(cornerRadius: theme.active.cornerRadiusValue + 6, style: .continuous)
            .strokeBorder(
                theme.active.accentColor,
                style: StrokeStyle(lineWidth: 3, dash: [10, 7])
            )
            .background(
                RoundedRectangle(cornerRadius: theme.active.cornerRadiusValue + 6, style: .continuous)
                    .fill(theme.active.accentColor.opacity(0.10))
            )
            .padding(10)
            .opacity(isDropTargeted ? 1 : 0)
            .allowsHitTesting(false)
    }

    private func banner(
        text: String,
        icon: String,
        tint: Color,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        dismiss: (() -> Void)?
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)

            Text(text)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(theme.active.textPrimaryColor)
                .lineLimit(2)

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .buttonStyle(.plain)
            }

            if let dismiss {
                Button {
                    withAnimation(.easeOut(duration: 0.12)) { dismiss() }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(theme.active.textTertiaryColor)
                }
                .buttonStyle(.plain)
                .help(L("common.dismiss"))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(theme.active.surfaceHoverColor, in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Actions

    /// Banner shown the first time an automatic rule stops the wallpaper, with
    /// the direct fix for the battery rule so the user never has to hunt for
    /// the setting while the desktop looks frozen.
    private func pauseNoticeBanner(_ reason: PlaybackPolicy.Reason) -> some View {
        banner(
            text: L("playback.notice.paused", L("engine.reason.\(reason.rawValue)")),
            icon: "pause.circle.fill",
            tint: theme.active.accentColor,
            actionTitle: reason == .onBattery ? L("playback.notice.battery.action") : nil,
            action: reason == .onBattery ? { continueOnBattery() } : nil,
            dismiss: { dismissPauseNotice() }
        )
    }

    /// Keeps the wallpaper running on battery from now on (the preference is
    /// persisted) and drops the notice.
    private func continueOnBattery() {
        engine.pauseOnBattery = false
        dismissPauseNotice()
    }

    private func dismissPauseNotice() {
        withAnimation(.easeOut(duration: 0.12)) { pauseNotice = nil }
    }

    /// Announces the first automatic pause of each rule once per session;
    /// reasons the user cannot act on (sleep, lock, hidden desktop) stay in the
    /// menu bar only.
    private func updatePauseNotice(for reasons: [PlaybackPolicy.Reason]) {
        guard let reason = reasons.first(where: \.deservesUserNotice) else {
            if pauseNotice != nil { dismissPauseNotice() }
            return
        }
        guard !shownPauseNotices.contains(reason.rawValue) else { return }
        shownPauseNotices.insert(reason.rawValue)
        withAnimation(.easeInOut(duration: 0.15)) { pauseNotice = reason }
    }

    /// Waits a beat for the initial library load before deciding the library is
    /// empty (the view model has no "loaded" flag), then offers the starter
    /// wallpapers on first launch.
    private func presentStarterOfferIfNeeded() async {
        try? await Task.sleep(nanoseconds: 700_000_000)
        maybePresentStarterOffer()
    }

    private func maybePresentStarterOffer() {
        guard !isStarterSheetPresented else { return }
        guard !StarterWallpaperService.isOfferDisabledByEnvironment else { return }
        guard viewModel.videos.isEmpty else { return }
        guard !starterService.hasBeenOffered else { return }
        guard starterService.status == .available else { return }
        isStarterSheetPresented = true
    }

    private func open(_ video: Video) {
        withAnimation(.easeOut(duration: 0.15)) { previewVideo = video }
    }

    private func beginCategoryCreation() {
        newCategoryName = ""
        isNamingCategory = true
    }

    private var isRenamingVideoPresented: Binding<Bool> {
        Binding(
            get: { renamingVideo != nil },
            set: { isPresented in
                if !isPresented {
                    renamingVideo = nil
                    renameText = ""
                }
            }
        )
    }

    private func beginRenaming(_ video: Video) {
        renameText = video.title
        renamingVideo = video
    }

    private func commitRename() {
        guard let video = renamingVideo else { return }
        renamingVideo = nil
        guard let updated = viewModel.rename(video, to: renameText) else { return }
        if previewVideo?.id == updated.id {
            previewVideo = updated
        }
    }

    private func createCategory() {
        let name = newCategoryName
        newCategoryName = ""
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        viewModel.createCategory(named: name)
        rebuildMembership()
    }

    /// One pass over the library keeps category lookups O(1) everywhere else.
    private func rebuildMembership() {
        var map: [String: Set<Int64>] = [:]
        for video in viewModel.videos {
            let ids = Set(viewModel.categories(for: video).compactMap(\.id))
            if !ids.isEmpty {
                map[video.id] = ids
            }
        }
        membership = map
    }

    // MARK: - Drag & drop

    private func handleDrop(_ providers: [NSItemProvider]) async {
        var urls: [URL] = []
        for provider in providers {
            if let url = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) as? URL {
                urls.append(url)
                continue
            }
            if let data = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) as? Data,
               let string = String(data: data, encoding: .utf8),
               let url = URL(string: string) {
                urls.append(url)
            }
        }
        guard !urls.isEmpty else { return }
        await viewModel.importVideos(urls)
    }
}

// MARK: - Starter wallpaper offer

/// First-launch sheet offering the bundled starter wallpapers. It mirrors the
/// download lifecycle (offer → progress → done / failure) inside a single
/// surface that cannot be dismissed by clicking outside.
private struct StarterWallpaperSheet: View {
    @ObservedObject var service: StarterWallpaperService
    let onClose: () -> Void

    @EnvironmentObject private var theme: ThemeStore

    private var catalog: StarterWallpaperCatalog { StarterWallpaperCatalog.current }

    var body: some View {
        VStack(spacing: 20) {
            icon

            VStack(spacing: 8) {
                Text(L("starter.offer.title"))
                    .font(.system(size: 20, weight: theme.active.titleFontWeight, design: .rounded))
                    .foregroundStyle(theme.active.textPrimaryColor)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.active.textSecondaryColor)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if case .available = service.status {
                qualityPicker
            }

            controls
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 28)
        .frame(width: 430)
        .background(theme.active.windowBackgroundColor)
        .interactiveDismissDisabled(true)
    }

    /// Quality choice offered before the first download: the size label makes
    /// the trade-off explicit instead of hiding it behind a default.
    @ViewBuilder
    private var qualityPicker: some View {
        VStack(spacing: 7) {
            Picker("", selection: Binding(
                get: { service.quality },
                set: { service.setQuality($0) }
            )) {
                ForEach(StarterWallpaperQuality.allCasesInOrder, id: \.self) { quality in
                    Text(L("starter.quality.\(quality.rawValue).size", byteLabel(catalog.totalBytes(for: quality))))
                        .tag(quality)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("starter.offer.quality")

            Text(L("starter.quality.hint"))
                .font(.system(size: 11))
                .foregroundStyle(theme.active.textTertiaryColor)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var icon: some View {
        ZStack {
            Circle()
                .fill(iconTint.opacity(0.14))
                .frame(width: 88, height: 88)

            Image(systemName: iconName)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(iconTint)
        }
    }

    private var iconName: String {
        switch service.status {
        case .failed: return "exclamationmark.triangle.fill"
        case .installed, .partial: return "checkmark.circle.fill"
        case .available, .downloading: return "sparkles.tv"
        }
    }

    private var iconTint: Color {
        if case .failed = service.status { return theme.active.dangerColor }
        return theme.active.accentColor
    }

    private var message: String {
        switch service.status {
        case .available:
            return L(
                "starter.offer.message",
                catalog.wallpapers.count,
                byteLabel(catalog.totalBytes(for: service.quality))
            )
        case .downloading(let completed, let total, let downloaded, let totalBytes):
            return L(
                "starter.download.progress",
                completed,
                total,
                byteLabel(downloaded),
                byteLabel(totalBytes)
            )
        case .failed(let reason):
            return L("starter.download.failed", reason)
        case .installed, .partial:
            let count = service.installedCount()
            return count == 1
                ? L("starter.download.done.one", count)
                : L("starter.download.done.other", count)
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch service.status {
        case .available:
            VStack(spacing: 10) {
                PrimaryActionButton(
                    title: L("starter.offer.download", byteLabel(catalog.totalBytes(for: service.quality))),
                    systemImage: "arrow.down.circle"
                ) {
                    Task { await service.downloadAll() }
                }
                .accessibilityIdentifier("starter.offer.download")

                SecondaryActionButton(
                    title: L("starter.offer.later"),
                    systemImage: "clock"
                ) {
                    service.dismissOffer()
                    onClose()
                }
                .accessibilityIdentifier("starter.offer.later")
            }

        case .downloading(let completed, let total, let downloaded, let totalBytes):
            VStack(spacing: 12) {
                ProgressView(value: Double(completed), total: Double(max(total, 1)))
                    .tint(theme.active.accentColor)
                    .frame(width: 300)

                Text(L(
                    "starter.download.progress",
                    completed,
                    total,
                    byteLabel(downloaded),
                    byteLabel(totalBytes)
                ))
                .font(.system(size: 11.5))
                .foregroundStyle(theme.active.textSecondaryColor)
                .multilineTextAlignment(.center)

                SecondaryActionButton(
                    title: L("starter.download.cancel"),
                    systemImage: "xmark"
                ) {
                    service.cancel()
                }
                .accessibilityIdentifier("starter.download.cancel")
            }

        case .failed:
            HStack(spacing: 10) {
                PrimaryActionButton(title: L("starter.action.retry"), systemImage: "arrow.clockwise") {
                    Task { await service.downloadAll() }
                }
                .accessibilityIdentifier("starter.action.retry")

                SecondaryActionButton(title: L("common.close"), systemImage: "xmark") {
                    onClose()
                }
                .accessibilityIdentifier("starter.action.close")
            }

        case .installed, .partial:
            PrimaryActionButton(title: L("common.close"), systemImage: "checkmark") {
                onClose()
            }
            .accessibilityIdentifier("starter.action.close")
        }
    }

    private func byteLabel(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
