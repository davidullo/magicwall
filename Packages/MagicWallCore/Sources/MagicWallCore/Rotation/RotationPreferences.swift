import Foundation

/// How often the favorites rotation swaps the wallpaper.
public enum RotationInterval: Int, CaseIterable, Codable, Sendable {
    case oneMinute = 1
    case fiveMinutes = 5
    case fifteenMinutes = 15
    case thirtyMinutes = 30
    case oneHour = 60

    /// Interval applied when the user never picked one.
    public static let `default`: RotationInterval = .fifteenMinutes

    /// Interval in minutes, as shown in the UI.
    public var minutes: Int { rawValue }

    /// Interval in seconds, for timers.
    public var timeInterval: TimeInterval { TimeInterval(rawValue * 60) }
}

/// Whether every display shares one wallpaper or each display runs its own cycle.
public enum RotationMode: String, CaseIterable, Codable, Sendable {
    case sameOnAllDisplays
    case differentPerDisplay

    /// Mode applied when the user never picked one.
    public static let `default`: RotationMode = .sameOnAllDisplays
}

/// Progress of one rotation cycle across the favorites: every favorite is
/// shown once before any of them repeats.
public struct FavoritesRotation: Codable, Equatable, Sendable {
    /// Favorites already shown during the current cycle.
    public private(set) var shownVideoIDs: Set<String>

    public init(shownVideoIDs: Set<String> = []) {
        self.shownVideoIDs = shownVideoIDs
    }

    /// Picks the next video to show: a random favorite that has not been
    /// shown in the current cycle. When every eligible favorite has been
    /// shown, the cycle restarts — avoiding `previous` (the video that is on
    /// screen right now) whenever there is any other candidate.
    public mutating func next(from eligible: [String], avoiding previous: String?) -> String? {
        var generator = SystemRandomNumberGenerator()
        return next(from: eligible, avoiding: previous, using: &generator)
    }

    /// Deterministic variant so tests can pin the generator.
    public mutating func next(
        from eligible: [String],
        avoiding previous: String?,
        using generator: inout some RandomNumberGenerator
    ) -> String? {
        next(from: eligible, avoiding: previous.map { [$0] } ?? [], using: &generator)
    }

    /// Deterministic variant that can rule out a whole set of ids at once —
    /// used to keep the videos picked in the same tick distinct across displays.
    public mutating func next(
        from eligible: [String],
        avoiding banned: Set<String>,
        using generator: inout some RandomNumberGenerator
    ) -> String? {
        // Favorites removed (or deleted) mid-cycle stop being eligible.
        shownVideoIDs.formIntersection(eligible)

        var pool = eligible.filter { !shownVideoIDs.contains($0) && !banned.contains($0) }
        if pool.isEmpty {
            // Cycle complete: start over, avoiding an immediate repeat.
            shownVideoIDs.removeAll()
            pool = eligible.filter { !banned.contains($0) }
            if pool.isEmpty { pool = eligible }
        }

        guard let picked = pool.randomElement(using: &generator) else { return nil }
        shownVideoIDs.insert(picked)
        return picked
    }
}

/// Everything the engine persists about the favorites rotation.
public struct RotationPreferences: Codable, Equatable, Sendable {
    /// Key of the `app_settings` row that stores these preferences.
    public static let storageKey = "favoritesRotation"

    public var enabled: Bool
    public var interval: RotationInterval
    public var shownVideoIDs: Set<String>
    /// Wallpaper strategy: one shared video or one per display.
    public var mode: RotationMode
    /// Per-display cycle progress, keyed by the display's screen key.
    public var shownVideoIDsByScreen: [String: Set<String>]

    public init(
        enabled: Bool = false,
        interval: RotationInterval = .default,
        shownVideoIDs: Set<String> = [],
        mode: RotationMode = .default,
        shownVideoIDsByScreen: [String: Set<String>] = [:]
    ) {
        self.enabled = enabled
        self.interval = interval
        self.shownVideoIDs = shownVideoIDs
        self.mode = mode
        self.shownVideoIDsByScreen = shownVideoIDsByScreen
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
        case interval
        case shownVideoIDs
        case mode
        case shownVideoIDsByScreen
    }

    /// JSON persisted before `mode`/`shownVideoIDsByScreen` existed has neither
    /// key: both decode to their defaults so old settings keep loading.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.enabled = try container.decode(Bool.self, forKey: .enabled)
        self.interval = try container.decode(RotationInterval.self, forKey: .interval)
        self.shownVideoIDs = try container.decode(Set<String>.self, forKey: .shownVideoIDs)
        self.mode = try container.decodeIfPresent(RotationMode.self, forKey: .mode) ?? .default
        self.shownVideoIDsByScreen =
            try container.decodeIfPresent([String: Set<String>].self, forKey: .shownVideoIDsByScreen) ?? [:]
    }

    /// JSON representation stored in `app_settings`.
    public func encoded() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Decodes the JSON written by ``encoded()``; `nil` for missing or
    /// unreadable values.
    public init?(encoded: String?) {
        guard
            let encoded,
            let data = encoded.data(using: .utf8),
            let decoded = try? JSONDecoder().decode(Self.self, from: data)
        else { return nil }
        self = decoded
    }
}
