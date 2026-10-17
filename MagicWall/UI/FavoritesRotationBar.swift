import MagicWallCore
import SwiftUI

/// Compact control for the favorites rotation, shown at the top of the
/// Favorites tab: on/off switch, interval menu and "next now", with a live
/// caption reporting the countdown and the progress through the cycle.
///
/// Deliberately the only place where the rotation is configured inside the
/// library window — three controls, no extra screens.
struct FavoritesRotationBar: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var viewModel: LibraryViewModel
    @EnvironmentObject private var engine: WallpaperEngine

    private var favoriteCount: Int { viewModel.favoriteIDs.count }

    /// Favorites of the current cycle already shown on screen.
    private var shownCount: Int {
        engine.rotationShownVideoIDs.intersection(viewModel.favoriteIDs).count
    }

    private var isEnabled: Binding<Bool> {
        Binding(
            get: { engine.rotationEnabled },
            set: { engine.setRotationEnabled($0) }
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            icon
            labels

            Spacer(minLength: 12)

            Toggle(L("rotation.title"), isOn: isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(theme.active.accentColor)
                .accessibilityIdentifier("favorites.rotation.toggle")

            intervalMenu
            modeMenu
            nextButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            theme.active.surfaceColor,
            in: RoundedRectangle(cornerRadius: theme.active.cornerRadiusValue, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: theme.active.cornerRadiusValue, style: .continuous)
                .strokeBorder(theme.active.dividerColor, lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.15), value: engine.rotationEnabled)
    }

    // MARK: - Labels

    private var icon: some View {
        Image(systemName: "arrow.triangle.2.circlepath")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(theme.active.accentColor)
            .frame(width: 30, height: 30)
            .background(theme.active.accentColor.opacity(0.14), in: Circle())
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L("rotation.title"))
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(theme.active.textPrimaryColor)

            caption
        }
    }

    @ViewBuilder
    private var caption: some View {
        if engine.rotationEnabled {
            if favoriteCount == 0 {
                captionText(L("rotation.noFavorites"), monospacedDigits: false)
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    captionText(captionString(now: context.date), monospacedDigits: true)
                        .accessibilityIdentifier("favorites.rotation.caption")
                }
            }
        }
    }

    /// Same-wallpaper mode also reports the progress through the cycle;
    /// per-display mode only reports the countdown, since a single "x of y"
    /// makes no sense when every display has its own cycle.
    private func captionString(now: Date) -> String {
        switch engine.rotationMode {
        case .sameOnAllDisplays:
            return L("rotation.nextChange", countdown(now: now), shownCount, favoriteCount)
        case .differentPerDisplay:
            return L("rotation.nextChange.different", countdown(now: now), L("rotation.mode.short.different"))
        }
    }

    private func captionText(_ text: String, monospacedDigits: Bool) -> some View {
        Text(text)
            .font(monospacedDigits ? .system(size: 11).monospacedDigit() : .system(size: 11))
            .foregroundStyle(theme.active.textSecondaryColor)
            .lineLimit(1)
    }

    /// "12:34" style countdown to the next automatic change.
    private func countdown(now: Date) -> String {
        guard let fireDate = engine.nextRotationDate else { return "0:00" }
        let remaining = max(0, Int(fireDate.timeIntervalSince(now).rounded(.up)))
        return String(format: "%d:%02d", remaining / 60, remaining % 60)
    }

    // MARK: - Controls

    private var intervalMenu: some View {
        Menu {
            ForEach(RotationInterval.allCases, id: \.self) { interval in
                Button {
                    engine.setRotationInterval(interval)
                } label: {
                    if interval == engine.rotationInterval {
                        Label(rotationIntervalLabel(interval), systemImage: "checkmark")
                    } else {
                        Text(rotationIntervalLabel(interval))
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(rotationIntervalLabel(engine.rotationInterval))
                    .font(.system(size: 12, weight: .semibold))

                Image(systemName: "chevron.down")
                    .font(.system(size: 8.5, weight: .bold))
            }
            .foregroundStyle(theme.active.buttonSecondaryTextColor)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(theme.active.buttonSecondaryBackgroundColor, in: Capsule())
            .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityIdentifier("favorites.rotation.interval")
        .help(L("rotation.interval.help"))
    }

    /// Icon-only menu picking the wallpaper strategy; a caption-less control
    /// keeps the bar from getting crowded.
    private var modeMenu: some View {
        Menu {
            ForEach(RotationMode.allCases, id: \.self) { mode in
                Button {
                    engine.setRotationMode(mode)
                } label: {
                    if mode == engine.rotationMode {
                        Label(rotationModeLabel(mode), systemImage: "checkmark")
                    } else {
                        Text(rotationModeLabel(mode))
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: rotationModeSymbol(engine.rotationMode))
                    .font(.system(size: 11.5, weight: .semibold))

                Image(systemName: "chevron.down")
                    .font(.system(size: 8.5, weight: .bold))
            }
            .foregroundStyle(theme.active.buttonSecondaryTextColor)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(theme.active.buttonSecondaryBackgroundColor, in: Capsule())
            .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityIdentifier("favorites.rotation.mode")
        .help(L("rotation.mode.help"))
    }

    private func rotationModeLabel(_ mode: RotationMode) -> String {
        switch mode {
        case .sameOnAllDisplays: L("rotation.mode.same")
        case .differentPerDisplay: L("rotation.mode.different")
        }
    }

    private func rotationModeSymbol(_ mode: RotationMode) -> String {
        switch mode {
        case .sameOnAllDisplays: "rectangle.on.rectangle"
        case .differentPerDisplay: "square.split.2x1"
        }
    }

    private var nextButton: some View {
        Button {
            engine.advanceRotationNow()
        } label: {
            Image(systemName: "forward.end.fill")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(theme.active.textPrimaryColor)
                .frame(width: 30, height: 30)
                .background(theme.active.buttonSecondaryBackgroundColor, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityIdentifier("favorites.rotation.next")
        .help(L("rotation.nextNow.help"))
    }
}
