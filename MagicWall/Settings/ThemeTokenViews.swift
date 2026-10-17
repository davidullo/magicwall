import SwiftUI

/// One editable colour token of ``ThemeConfiguration``: a stable id plus the
/// writable key path that the theme editor mutates.
///
/// The display title and tooltip are looked up from `theme.token.<id>` and
/// `theme.token.<id>.help`, so keeping the table free of user-facing copy
/// guarantees every token stays localizable together with the rest of the UI.
struct ThemeColorToken: Identifiable {
    let id: String
    let keyPath: WritableKeyPath<ThemeConfiguration, String>

    /// Human readable name shown next to the well.
    @MainActor var title: String { L("theme.token.\(id)") }
    /// One-line explanation, surfaced as the control's tooltip.
    @MainActor var help: String { L("theme.token.\(id).help") }
}

/// A titled cluster of tokens, rendered as its own grid.
struct ThemeTokenGroup: Identifiable {
    let id: String
    let tokens: [ThemeColorToken]

    static let all: [ThemeTokenGroup] = [
        ThemeTokenGroup(id: "Brand", tokens: [
            ThemeColorToken(
                id: "accent",
                keyPath: \ThemeConfiguration.accent
            ),
            ThemeColorToken(
                id: "accentText",
                keyPath: \ThemeConfiguration.accentText
            )
        ]),
        ThemeTokenGroup(id: "Backgrounds", tokens: [
            ThemeColorToken(
                id: "windowBackground",
                keyPath: \ThemeConfiguration.windowBackground
            ),
            ThemeColorToken(
                id: "sidebarBackground",
                keyPath: \ThemeConfiguration.sidebarBackground
            ),
            ThemeColorToken(
                id: "surface",
                keyPath: \ThemeConfiguration.surface
            ),
            ThemeColorToken(
                id: "surfaceHover",
                keyPath: \ThemeConfiguration.surfaceHover
            ),
            ThemeColorToken(
                id: "surfaceSelected",
                keyPath: \ThemeConfiguration.surfaceSelected
            )
        ]),
        ThemeTokenGroup(id: "Text", tokens: [
            ThemeColorToken(
                id: "textPrimary",
                keyPath: \ThemeConfiguration.textPrimary
            ),
            ThemeColorToken(
                id: "textSecondary",
                keyPath: \ThemeConfiguration.textSecondary
            ),
            ThemeColorToken(
                id: "textTertiary",
                keyPath: \ThemeConfiguration.textTertiary
            )
        ]),
        ThemeTokenGroup(id: "Badges", tokens: [
            ThemeColorToken(
                id: "badgeBackground",
                keyPath: \ThemeConfiguration.badgeBackground
            ),
            ThemeColorToken(
                id: "badgeText",
                keyPath: \ThemeConfiguration.badgeText
            ),
            ThemeColorToken(
                id: "liveBadgeBackground",
                keyPath: \ThemeConfiguration.liveBadgeBackground
            ),
            ThemeColorToken(
                id: "liveBadgeText",
                keyPath: \ThemeConfiguration.liveBadgeText
            )
        ]),
        ThemeTokenGroup(id: "Buttons & chrome", tokens: [
            ThemeColorToken(
                id: "buttonSecondaryBackground",
                keyPath: \ThemeConfiguration.buttonSecondaryBackground
            ),
            ThemeColorToken(
                id: "buttonSecondaryText",
                keyPath: \ThemeConfiguration.buttonSecondaryText
            ),
            ThemeColorToken(
                id: "divider",
                keyPath: \ThemeConfiguration.divider
            )
        ])
    ]
}

// MARK: - Colour row

/// A `ColorPicker` plus the token name and its current hex value.
struct ThemeColorRow: View {
    let token: ThemeColorToken
    let hex: String
    @Binding var color: Color

    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        HStack(spacing: 8) {
            ColorPicker(token.title, selection: $color, supportsOpacity: true)
                .labelsHidden()
                .help(token.help)

            VStack(alignment: .leading, spacing: 1) {
                Text(token.title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(theme.active.textPrimaryColor)
                    .lineLimit(1)
                Text(hex.uppercased())
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(theme.active.textTertiaryColor)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .help(token.help)
    }
}

/// Collapsible card for one group of theme tokens. Keeping the groups closed
/// by default turns the editor from a 17-row wall into a short, scannable list.
struct ThemeTokenGroupCard: View {
    let group: ThemeTokenGroup
    let title: String
    let theme: ThemeConfiguration
    @Binding var isExpanded: Bool
    let bindingFor: (ThemeColorToken) -> Binding<Color>

    @EnvironmentObject private var themeStore: ThemeStore

    private static let columns = [
        GridItem(.flexible(), spacing: 18, alignment: .top),
        GridItem(.flexible(), spacing: 18, alignment: .top)
    ]

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(themeStore.active.textPrimaryColor)

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(themeStore.active.textTertiaryColor)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("theme.group.\(group.id)")

            if isExpanded {
                SettingsDivider()

                LazyVGrid(columns: Self.columns, spacing: 8) {
                    ForEach(group.tokens) { token in
                        ThemeColorRow(
                            token: token,
                            hex: theme[keyPath: token.keyPath],
                            color: bindingFor(token)
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 7)
                .padding(.bottom, 11)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            themeStore.active.surfaceColor,
            in: RoundedRectangle(cornerRadius: themeStore.active.cornerRadiusValue, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: themeStore.active.cornerRadiusValue, style: .continuous)
                .strokeBorder(themeStore.active.dividerColor, lineWidth: 1)
        )
    }
}

// MARK: - Preview

/// Compact live preview built entirely from the tokens of `theme`, so a colour
/// change is visible immediately without leaving the editor.
struct ThemePreviewCard: View {
    let theme: ThemeConfiguration

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: theme.cornerRadiusValue, style: .continuous)
                .fill(theme.windowBackgroundColor)

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Text(L("theme.preview.libraryTitle"))
                        .font(.title3.weight(theme.titleFontWeight))
                        .foregroundStyle(theme.textPrimaryColor)

                    Text(L("common.live"))
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(theme.liveBadgeBackgroundColor, in: Capsule())
                        .foregroundStyle(theme.liveBadgeTextColor)

                    Text("4K")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(theme.badgeBackgroundColor, in: Capsule())
                        .foregroundStyle(theme.badgeTextColor)

                    Spacer(minLength: 0)
                }

                Text(L("theme.preview.secondary"))
                    .font(.callout)
                    .foregroundStyle(theme.textSecondaryColor)

                Text(L("theme.preview.tertiary"))
                    .font(.caption)
                    .foregroundStyle(theme.textTertiaryColor)

                Rectangle()
                    .fill(theme.dividerColor)
                    .frame(height: 1)

                HStack(spacing: 10) {
                    Text(L("video.play"))
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(primaryFill, in: buttonShape)
                        .foregroundStyle(theme.accentTextColor)

                    Text(L("home.hero.preview"))
                        .font(.callout)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(theme.buttonSecondaryBackgroundColor, in: buttonShape)
                        .foregroundStyle(theme.buttonSecondaryTextColor)

                    Spacer(minLength: 0)
                }
            }
            .padding(18)
        }
        .frame(height: 210)
        .overlay(
            RoundedRectangle(cornerRadius: theme.cornerRadiusValue, style: .continuous)
                .strokeBorder(theme.dividerColor, lineWidth: 1)
        )
    }

    /// Accent fill, optionally softened into a gradient when the theme enables it.
    private var primaryFill: AnyShapeStyle {
        guard theme.useGradients else { return AnyShapeStyle(theme.accentColor) }
        return AnyShapeStyle(
            LinearGradient(
                colors: [theme.accentColor.opacity(0.70), theme.accentColor],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var buttonShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: max(4, theme.cornerRadiusValue * 0.6),
            style: .continuous
        )
    }
}
