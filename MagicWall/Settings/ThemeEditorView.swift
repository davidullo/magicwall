import SwiftUI

/// The "Theme" tab: a compact theme picker, a live preview and collapsible
/// groups of design tokens.
///
/// Every edit goes through `themeStore.updateActive`, so the whole app updates
/// as soon as a colour, the corner radius or the title weight changes. Editing a
/// built-in theme forks it into an editable copy (handled by ``ThemeStore``).
struct ThemeEditorView: View {
    @EnvironmentObject private var themeStore: ThemeStore

    @State private var isShowingSaveAs = false
    @State private var newThemeName = ""
    @State private var expandedGroups: Set<String> = ["Brand"]

    private var theme: ThemeConfiguration { themeStore.active }

    var body: some View {
        SettingsPage(
            title: L("settings.tab.theme"),
            subtitle: L("settings.theme.subtitle"),
            identifier: "theme.editor"
        ) {
            themePickerCard
            previewSection
            colorsSection
            shapeSection
            actionsSection
        }
        .alert(L("theme.alert.saveAs.title"), isPresented: $isShowingSaveAs) {
            TextField(L("theme.alert.saveAs.nameField"), text: $newThemeName)
            Button(L("common.cancel"), role: .cancel) {}
            Button(L("common.save")) { saveAsNewTheme() }
        } message: {
            Text(L("theme.alert.saveAs.message"))
        }
    }

    // MARK: - Active theme

    private var themePickerCard: some View {
        SettingsCard {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("theme.activeTheme"))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(themeStore.active.textTertiaryColor)

                    Picker(
                        selection: Binding(
                            get: { themeStore.activeThemeID },
                            set: { id in
                                guard let item = themeStore.themes.first(where: { $0.id == id }) else { return }
                                themeStore.activate(item)
                            }
                        )
                    ) {
                        ForEach(themeStore.themes) { item in
                            Text(item.name).tag(item.id)
                        }
                    } label: {
                        Text(L("theme.activeTheme"))
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 200, alignment: .leading)
                    .accessibilityIdentifier("theme.picker")
                }

                if theme.isBuiltIn {
                    pill(L("theme.pill.builtIn"), color: themeStore.active.textTertiaryColor)
                }

                Spacer(minLength: 8)

                Menu {
                    Button(L("theme.action.duplicate")) {
                        themeStore.duplicate(theme)
                    }

                    Divider()

                    Button(L("common.delete"), role: .destructive) {
                        themeStore.delete(theme)
                    }
                    .disabled(theme.isBuiltIn)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(themeStore.active.buttonSecondaryTextColor)
                        .frame(width: 28, height: 28)
                        .background(themeStore.active.buttonSecondaryBackgroundColor, in: Circle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(L("theme.manage.help"))
            }
            .padding(.vertical, 7)

            if theme.isBuiltIn {
                SettingsDivider()

                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10.5, weight: .semibold))

                    Text(L("theme.builtIn.fork"))
                        .font(.system(size: 11))
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }
                .foregroundStyle(themeStore.active.textSecondaryColor)
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Preview

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSubheader(title: L("home.hero.preview"), systemImage: "eye")
            ThemePreviewCard(theme: theme)
        }
    }

    // MARK: - Colours

    private var colorsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSubheader(title: L("theme.section.colors"), systemImage: "paintpalette")

            ForEach(ThemeTokenGroup.all) { group in
                ThemeTokenGroupCard(
                    group: group,
                    title: groupTitle(group),
                    theme: theme,
                    isExpanded: expandedBinding(for: group.id),
                    bindingFor: { token in
                        colorBinding(for: token)
                    }
                )
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

    private func expandedBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { expandedGroups.contains(id) },
            set: { isExpanded in
                if isExpanded {
                    expandedGroups.insert(id)
                } else {
                    expandedGroups.remove(id)
                }
            }
        )
    }

    // MARK: - Shape & typography

    private var shapeSection: some View {
        SettingsCard(title: L("theme.section.shape"), systemImage: "square.on.circle") {
            SettingsRow(L("theme.cornerRadius")) {
                HStack(spacing: 10) {
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
                    .tint(themeStore.active.accentColor)
                    .frame(width: 150)

                    Text("\(Int(theme.cornerRadius.rounded())) pt")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(themeStore.active.textSecondaryColor)
                        .frame(width: 38, alignment: .trailing)
                }
            }

            SettingsDivider()

            SettingsRow(L("theme.titleWeight")) {
                Picker(
                    selection: Binding(
                        get: { theme.titleWeight },
                        set: { newValue in
                            themeStore.updateActive { configuration in
                                configuration.titleWeight = newValue
                            }
                        }
                    )
                ) {
                    ForEach(ThemeConfiguration.titleWeightOptions, id: \.self) { option in
                        Text(L("theme.titleWeight.\(option)")).tag(option)
                    }
                } label: {
                    Text(L("theme.titleWeight"))
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 145)
            }

            SettingsDivider()

            SettingsToggleRow(
                title: L("theme.useGradients"),
                isOn: Binding(
                    get: { theme.useGradients },
                    set: { newValue in
                        themeStore.updateActive { configuration in
                            configuration.useGradients = newValue
                        }
                    }
                )
            )
            .help(L("theme.useGradients.help"))
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        HStack(spacing: 10) {
            SettingsActionButton(
                title: L("theme.saveAs"),
                systemImage: "square.and.arrow.down",
                kind: .primary
            ) {
                newThemeName = "\(theme.name) Custom"
                isShowingSaveAs = true
            }

            SettingsActionButton(
                title: L("theme.resetToDefault"),
                systemImage: "arrow.counterclockwise"
            ) {
                themeStore.resetToDefault()
            }

            Spacer(minLength: 12)

            SettingsActionButton(
                title: L("theme.revert"),
                systemImage: "arrow.uturn.backward"
            ) {
                // Re-activating the saved theme drops any unsaved live edit.
                themeStore.activate(theme)
            }
            .help(L("theme.revert.help"))
        }
        .padding(.top, 2)
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

    private func pill(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 9.5, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.16), in: Capsule())
            .foregroundStyle(color)
    }
}
