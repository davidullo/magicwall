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
        // Favorites removed (or deleted) mid-cycle stop being eligible.
        shownVideoIDs.formIntersection(eligible)

        var pool = eligible.filter { !shownVideoIDs.contains($0) }
        if pool.isEmpty {
            // Cycle complete: start over, avoiding an immediate repeat.
            shownVideoIDs.removeAll()
            pool = eligible.filter { $0 != previous }
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

    public init(
        enabled: Bool = false,
        interval: RotationInterval = .default,
        shownVideoIDs: Set<String> = []
    ) {
        self.enabled = enabled
        self.interval = interval
        self.shownVideoIDs = shownVideoIDs
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
