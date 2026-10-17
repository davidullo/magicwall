import SwiftUI

/// The "Theme" tab: the list of saved themes plus a live editor for the active
/// one.
///
/// Every edit goes through `themeStore.updateActive`, so the whole app updates
/// as soon as a colour, the corner radius or the title weight changes. Editing a
/// built-in theme forks it into an editable copy (handled by ``ThemeStore``).
struct ThemeEditorView: View {
    @EnvironmentObject private var themeStore: ThemeStore

    @State private var isShowingSaveAs = false
    @State private var newThemeName = ""

    private var theme: ThemeConfiguration { themeStore.active }

    private static let columns = [
        GridItem(.flexible(), spacing: 18, alignment: .top),
        GridItem(.flexible(), spacing: 18, alignment: .top)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                themesSection
                colorsSection
                shapeSection
                previewSection
                actionsSection
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("theme.editor")
        .alert(L("theme.alert.saveAs.title"), isPresented: $isShowingSaveAs) {
            TextField(L("theme.alert.saveAs.nameField"), text: $newThemeName)
            Button(L("common.cancel"), role: .cancel) {}
            Button(L("common.save")) { saveAsNewTheme() }
        } message: {
            Text(L("theme.alert.saveAs.message"))
        }
    }

    // MARK: - Saved themes

    private var themesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(L("theme.section.saved"), systemImage: "square.stack.3d.up")

            VStack(spacing: 6) {
                ForEach(themeStore.themes) { item in
                    themeRow(item)
                }
            }
        }
    }

    private func themeRow(_ item: ThemeConfiguration) -> some View {
        let isActive = item.id == themeStore.activeThemeID

        return HStack(spacing: 10) {
            Circle()
                .fill(item.accentColor)
                .frame(width: 12, height: 12)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
                .help(L("theme.accent.help"))

            Text(item.name)
                .fontWeight(isActive ? .semibold : .regular)

            if isActive {
                pill(L("theme.pill.active"), color: .accentColor)
            }
            if item.isBuiltIn {
                pill(L("theme.pill.builtIn"), color: .secondary)
            }

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                Button(L("theme.action.activate")) { themeStore.activate(item) }
                    .disabled(isActive)

                Button(L("theme.action.duplicate")) { themeStore.duplicate(item) }

                Button(L("common.delete")) { themeStore.delete(item) }
                    .disabled(item.isBuiltIn)
                    .help(item.isBuiltIn ? L("theme.builtIn.cannotDelete") : L("theme.delete.help"))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 12)
        .background(
            Color.primary.opacity(isActive ? 0.08 : 0.04),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }

    private func pill(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }

    // MARK: - Colours

    private var colorsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                sectionHeader(L("theme.section.colors"), systemImage: "paintpalette")
                Spacer(minLength: 8)
                Text(theme.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if theme.isBuiltIn {
                Label(
                    L("theme.builtIn.fork"),
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            ForEach(ThemeTokenGroup.all) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(groupTitle(group))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: Self.columns, spacing: 10) {
                        ForEach(group.tokens) { token in
                            ThemeColorRow(
                                token: token,
                                hex: theme[keyPath: token.keyPath],
                                color: colorBinding(for: token)
                            )
                        }
                    }
                }
            }
        }
    }

    /// `Color` ⇄ hex bridge: reads the stored token and writes back the new
    /// value through the store so the change is applied and persisted.
    private func colorBinding(for token: ThemeColorToken) -> Binding<Color> {
        Binding(
            get: { Color(themeHex: theme[keyPath: token.keyPath]) },
            set: { newColor in
                let hex = newColor.themeHexString
                themeStore.updateActive { configuration in
                    configuration[keyPath: token.keyPath] = hex
                }
            }
        )
    }

    // MARK: - Shape & typography

    private var shapeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(L("theme.section.shape"), systemImage: "square.on.circle")

            HStack(spacing: 12) {
                Text(L("theme.cornerRadius"))
                Slider(
                    value: Binding(
                        get: { theme.cornerRadius },
                        set: { newValue in
                            themeStore.updateActive { configuration in
                                configuration.cornerRadius = newValue
                            }
                        }
                    ),
                    in: 4...28,
                    step: 1
                )
                Text("\(Int(theme.cornerRadius.rounded())) pt")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 46, alignment: .trailing)
            }

            LabeledContent {
                Picker(selection: Binding(
                    get: { theme.titleWeight },
                    set: { newValue in
                        themeStore.updateActive { configuration in
                            configuration.titleWeight = newValue
                        }
                    }
                )) {
                    ForEach(ThemeConfiguration.titleWeightOptions, id: \.self) { option in
                        Text(L("theme.titleWeight.\(option)")).tag(option)
                    }
                } label: {
                    Text(L("theme.titleWeight"))
                }
                .labelsHidden()
                .pickerStyle(.menu)
            } label: {
                Text(L("theme.titleWeight"))
            }

            Toggle(L("theme.useGradients"), isOn: Binding(
                get: { theme.useGradients },
                set: { newValue in
                    themeStore.updateActive { configuration in
                        configuration.useGradients = newValue
                    }
                }
            ))
            .help(L("theme.useGradients.help"))
        }
    }

    // MARK: - Preview

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(L("home.hero.preview"), systemImage: "eye")
            ThemePreviewCard(theme: theme)
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        HStack(spacing: 10) {
            Button(L("theme.saveAs")) {
                newThemeName = "\(theme.name) Custom"
                isShowingSaveAs = true
            }

            Button(L("theme.resetToDefault")) {
                themeStore.resetToDefault()
            }

            Spacer(minLength: 12)

            Button(L("theme.revert")) {
                // Re-activating the saved theme drops any unsaved live edit.
                themeStore.activate(theme)
            }
            .help(L("theme.revert.help"))
        }
    }

    // MARK: - Helpers

    /// Localized title for a token group, keyed by its stable (English) id.
    private func groupTitle(_ group: ThemeTokenGroup) -> String {
        switch group.id {
        case "Brand": return L("theme.group.brand")
        case "Backgrounds": return L("theme.group.backgrounds")
        case "Text": return L("theme.group.text")
        case "Badges": return L("theme.group.badges")
        case "Buttons & chrome": return L("theme.group.buttons")
        default: return group.id
        }
    }

    private func saveAsNewTheme() {
        let name = newThemeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        themeStore.save(ThemeConfiguration.makeNew(named: name, basedOn: theme))
    }

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
    }
}
