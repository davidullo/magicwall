import Foundation
import MagicWallCore
import SwiftUI

/// Holds the available themes, the active one, and persists them to
/// `~/Library/Application Support/MagicWall/themes.json`.
///
/// Any view can read the active theme tokens through
/// `@EnvironmentObject private var theme: ThemeStore` + `theme.active.*`.
@MainActor
final class ThemeStore: ObservableObject {
    @Published private(set) var themes: [ThemeConfiguration]
    @Published private(set) var activeThemeID: String

    private struct Persisted: Codable {
        var themes: [ThemeConfiguration]
        var activeThemeID: String
    }

    private static var storageURL: URL {
        AppPaths.appSupportDirectory.appendingPathComponent("themes.json")
    }

    init() {
        if let data = try? Data(contentsOf: Self.storageURL),
           let persisted = try? JSONDecoder().decode(Persisted.self, from: data),
           !persisted.themes.isEmpty {
            themes = persisted.themes
            activeThemeID = persisted.themes.contains(where: { $0.id == persisted.activeThemeID })
                ? persisted.activeThemeID
                : persisted.themes[0].id
        } else {
            themes = [.midnight]
            activeThemeID = ThemeConfiguration.midnight.id
        }
    }

    /// The theme currently applied to the whole app.
    var active: ThemeConfiguration {
        themes.first { $0.id == activeThemeID } ?? .midnight
    }

    // MARK: - Mutations

    /// Applies an existing saved theme.
    func activate(_ theme: ThemeConfiguration) {
        guard themes.contains(where: { $0.id == theme.id }) else {
            save(theme)
            return
        }
        activeThemeID = theme.id
        persist()
    }

    /// Inserts or updates a (user) theme. Built-ins are immutable: saving one
    /// creates an editable copy named "Name Custom".
    func save(_ theme: ThemeConfiguration) {
        var incoming = theme
        if incoming.isBuiltIn {
            incoming = ThemeConfiguration.makeNew(named: "\(incoming.name) Custom", basedOn: incoming)
        }
        if let index = themes.firstIndex(where: { $0.id == incoming.id }) {
            themes[index] = incoming
        } else {
            themes.append(incoming)
        }
        activeThemeID = incoming.id
        persist()
    }

    /// Applies live edits to the active theme without persisting a new entry.
    func updateActive(_ transform: (inout ThemeConfiguration) -> Void) {
        guard let index = themes.firstIndex(where: { $0.id == activeThemeID }) else { return }
        guard !themes[index].isBuiltIn else {
            // Editing a built-in forks it so the original stays pristine.
            var fork = themes[index]
            fork = ThemeConfiguration.makeNew(named: "\(fork.name) Custom", basedOn: fork)
            transform(&fork)
            themes.append(fork)
            activeThemeID = fork.id
            persist()
            return
        }
        transform(&themes[index])
        persist()
    }

    func duplicate(_ theme: ThemeConfiguration) {
        let copy = ThemeConfiguration.makeNew(named: "\(theme.name) Copy", basedOn: theme)
        themes.append(copy)
        activeThemeID = copy.id
        persist()
    }

    func delete(_ theme: ThemeConfiguration) {
        guard !theme.isBuiltIn else { return }
        themes.removeAll { $0.id == theme.id }
        if activeThemeID == theme.id {
            activeThemeID = themes.first(where: { $0.isBuiltIn })?.id ?? themes.first?.id ?? ThemeConfiguration.midnight.id
        }
        persist()
    }

    func resetToDefault() {
        if let builtIn = themes.first(where: { $0.isBuiltIn }) {
            activeThemeID = builtIn.id
        } else {
            themes.insert(.midnight, at: 0)
            activeThemeID = ThemeConfiguration.midnight.id
        }
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        let snapshot = Persisted(themes: themes, activeThemeID: activeThemeID)
        do {
            try AppPaths.ensureDirectories()
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: Self.storageURL, options: .atomic)
        } catch {
            // Persisting the theme is best-effort: the app keeps working with
            // the in-memory value even if the disk write fails.
            print("ThemeStore: failed to persist themes: \(error)")
        }
    }
}
