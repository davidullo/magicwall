import SwiftUI

// MARK: - Page shell

/// Standard scrollable page used by every Settings section. The page owns the
/// title block and the themed background so individual tabs only compose cards.
struct SettingsPage<Content: View>: View {
    let title: String
    let subtitle: String?
    let identifier: String?
    let content: Content

    @EnvironmentObject private var theme: ThemeStore

    init(
        title: String,
        subtitle: String? = nil,
        identifier: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.identifier = identifier
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    titleView

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 12.5))
                            .foregroundStyle(theme.active.textSecondaryColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                content
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 30)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background(theme.active.windowBackgroundColor)
    }

    @ViewBuilder
    private var titleView: some View {
        if let identifier {
            titleText.accessibilityIdentifier(identifier)
        } else {
            titleText
        }
    }

    private var titleText: some View {
        Text(title)
            .font(.system(size: 26, weight: theme.active.titleFontWeight, design: .rounded))
            .foregroundStyle(theme.active.textPrimaryColor)
    }
}

// MARK: - Cards and rows

/// Rounded, themed container for a group of related settings.
struct SettingsCard<Content: View>: View {
    let title: String?
    let systemImage: String?
    let content: Content

    @EnvironmentObject private var theme: ThemeStore

    init(title: String? = nil, systemImage: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                HStack(spacing: 8) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(theme.active.accentColor)
                    }

                    Text(title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(theme.active.textPrimaryColor)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)

                SettingsDivider()
            }

            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
        }
        .background(
            theme.active.surfaceColor,
            in: RoundedRectangle(cornerRadius: theme.active.cornerRadiusValue, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: theme.active.cornerRadiusValue, style: .continuous)
                .strokeBorder(theme.active.dividerColor, lineWidth: 1)
        )
    }
}

/// Generic row with a title, an optional caption, and a trailing control.
struct SettingsRow<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let trailing: Trailing

    @EnvironmentObject private var theme: ThemeStore

    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(theme.active.textPrimaryColor)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.active.textSecondaryColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 12)

            trailing
        }
        .padding(.vertical, 9)
    }
}

/// Toggle row used across the General and Theme tabs.
struct SettingsToggleRow: View {
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool

    @EnvironmentObject private var theme: ThemeStore

    init(title: String, subtitle: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
    }

    var body: some View {
        SettingsRow(title, subtitle: subtitle) {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(theme.active.accentColor)
                .accessibilityLabel(title)
        }
    }
}

/// Read-only value row for library stats.
struct SettingsValueRow: View {
    let title: String
    let value: String
    var monospaced = true

    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        SettingsRow(title) {
            Text(value)
                .font(.system(size: 12.5, weight: .medium, design: monospaced ? .monospaced : .default))
                .foregroundStyle(theme.active.textSecondaryColor)
        }
    }
}

/// Informational row: symbol plus secondary copy, no control. Carries the
/// sentence of context a setting needs that a subtitle alone cannot.
struct SettingsHintRow: View {
    let text: String
    var systemImage = "info.circle"

    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.active.textTertiaryColor)

            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(theme.active.textSecondaryColor)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
    }
}

/// Small section label used above free-standing groups (preview, colors).
struct SettingsSubheader: View {
    let title: String
    var systemImage: String?

    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        HStack(spacing: 7) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
            }

            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(0.8)
        }
        .foregroundStyle(theme.active.textTertiaryColor)
    }
}

struct SettingsDivider: View {
    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        Rectangle()
            .fill(theme.active.dividerColor)
            .frame(height: 1)
    }
}

// MARK: - Buttons

/// Themed replacement for `.bordered` buttons, which would otherwise fall back
/// to system chrome and ignore the active theme.
struct SettingsActionButton: View {
    enum Kind {
        case primary
        case secondary
        case destructive
    }

    let title: String
    var systemImage: String?
    var kind: Kind = .secondary
    var isEnabled = true
    /// Applied to the button itself, not to the wrapper: UI tests look up
    /// `SettingsActionButton`s by identifier, and a container identifier does
    /// not reach the button element.
    var identifier: String?
    let action: () -> Void

    @EnvironmentObject private var theme: ThemeStore
    @State private var isHovering = false

    var body: some View {
        if let identifier {
            button.accessibilityIdentifier(identifier)
        } else {
            button
        }
    }

    private var button: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .semibold))
                }

                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                fill,
                in: RoundedRectangle(cornerRadius: theme.active.controlRadius, style: .continuous)
            )
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { isHovering = $0 }
    }

    private var foreground: Color {
        switch kind {
        case .primary: return theme.active.accentTextColor
        case .secondary: return theme.active.buttonSecondaryTextColor
        case .destructive: return theme.active.dangerColor
        }
    }

    private var fill: AnyShapeStyle {
        switch kind {
        case .primary:
            return theme.active.accentShapeStyle
        case .secondary:
            return isHovering
                ? AnyShapeStyle(theme.active.surfaceHoverColor)
                : AnyShapeStyle(theme.active.buttonSecondaryBackgroundColor)
        case .destructive:
            return isHovering
                ? AnyShapeStyle(theme.active.dangerColor.opacity(0.16))
                : AnyShapeStyle(theme.active.buttonSecondaryBackgroundColor)
        }
    }
}

// MARK: - Sidebar navigation

struct SettingsNavItem: View {
    let identifier: String
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    @EnvironmentObject private var theme: ThemeStore
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 12.5, weight: .semibold))
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? theme.active.accentColor : theme.active.textSecondaryColor)

                Text(title)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? theme.active.textPrimaryColor : theme.active.textSecondaryColor)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                background,
                in: RoundedRectangle(cornerRadius: theme.active.controlRadius, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .onHover { isHovering = $0 }
    }

    private var background: Color {
        if isSelected {
            return theme.active.surfaceSelectedColor
        }
        return isHovering ? theme.active.surfaceHoverColor : .clear
    }
}
