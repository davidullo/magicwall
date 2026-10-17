import Foundation
import SwiftUI

/// Languages the UI can be displayed in. English is the default; Italian is
/// kept as a first-class translation since the app is developed in Italy.
enum AppLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case en
    case it

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .en: return "English"
        case .it: return "Italiano"
        }
    }
}

/// Loads strings from `en.lproj` / `it.lproj` and supports switching language
/// at runtime without restarting the app.
///
/// Views do not need to observe this object: `MagicWallApp` re-identifies the
/// root view on language changes, which rebuilds the whole UI with the new
/// strings. Use the global `L(...)` helper in view bodies.
@MainActor
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    @Published private(set) var language: AppLanguage

    private static let defaultsKey = "appLanguage"

    private var bundle: Bundle

    init() {
        let stored = UserDefaults.standard.string(forKey: Self.defaultsKey)
        let initial = stored.flatMap(AppLanguage.init(rawValue:)) ?? .en
        language = initial
        bundle = Self.bundle(for: initial) ?? .main
    }

    func setLanguage(_ newLanguage: AppLanguage) {
        guard newLanguage != language else { return }
        language = newLanguage
        UserDefaults.standard.set(newLanguage.rawValue, forKey: Self.defaultsKey)
        bundle = Self.bundle(for: newLanguage) ?? .main
    }

    /// Looks up a key; missing keys fall back to the key itself so untranslated
    /// strings are obvious but never fatal.
    func string(for key: String) -> String {
        bundle.localizedString(forKey: key, value: key, table: nil)
    }

    func string(for key: String, _ arguments: CVarArg...) -> String {
        String(format: string(for: key), arguments: arguments)
    }

    private static func bundle(for language: AppLanguage) -> Bundle? {
        guard let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj") else {
            return nil
        }
        return Bundle(path: path)
    }
}

/// Shorthand used across view bodies: `Text(L("home.title"))`.
@MainActor
func L(_ key: String) -> String {
    LocalizationManager.shared.string(for: key)
}

/// Formatted variant: `L("import.summary", count)`.
@MainActor
func L(_ key: String, _ arguments: CVarArg...) -> String {
    LocalizationManager.shared.string(for: key, arguments)
}
