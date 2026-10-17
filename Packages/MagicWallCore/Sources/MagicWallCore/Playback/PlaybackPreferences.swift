import Foundation

/// Everything the engine persists about wallpaper playback.
///
/// These are the *automatic pause* rules only: the manual pause and the
/// sampled system state (power source, thermal pressure, sleep, lock) live in
/// memory. The defaults live here so ``PlaybackPolicy`` and `WallpaperEngine`
/// cannot drift apart: a fresh install keeps the wallpaper playing on battery
/// — pausing is opt-in — while the protective rules stay on.
public struct PlaybackPreferences: Codable, Equatable, Sendable {
    /// Key of the `app_settings` row that stores these preferences.
    public static let storageKey = "playbackPreferences"

    /// Pause the wallpaper while the Mac runs on battery.
    public var pauseOnBattery: Bool
    /// Pause while the desktop is hidden behind other windows.
    public var pauseWhenOccluded: Bool
    /// Pause in Low Power Mode.
    public var pauseOnLowPower: Bool
    /// Pause while the screen is locked.
    public var pauseWhenLocked: Bool
    /// Pause under serious or critical thermal pressure.
    public var pauseOnThermalPressure: Bool

    /// Fresh-install rules.
    public static let `default` = PlaybackPreferences()

    public init(
        pauseOnBattery: Bool = false,
        pauseWhenOccluded: Bool = true,
        pauseOnLowPower: Bool = true,
        pauseWhenLocked: Bool = true,
        pauseOnThermalPressure: Bool = true
    ) {
        self.pauseOnBattery = pauseOnBattery
        self.pauseWhenOccluded = pauseWhenOccluded
        self.pauseOnLowPower = pauseOnLowPower
        self.pauseWhenLocked = pauseWhenLocked
        self.pauseOnThermalPressure = pauseOnThermalPressure
    }

    private enum CodingKeys: String, CodingKey {
        case pauseOnBattery
        case pauseWhenOccluded
        case pauseOnLowPower
        case pauseWhenLocked
        case pauseOnThermalPressure
    }

    /// Missing keys fall back to the current defaults, so JSON written by an
    /// older build (or a future one with extra rules) keeps loading.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = PlaybackPreferences.default
        self.pauseOnBattery =
            try container.decodeIfPresent(Bool.self, forKey: .pauseOnBattery) ?? defaults.pauseOnBattery
        self.pauseWhenOccluded =
            try container.decodeIfPresent(Bool.self, forKey: .pauseWhenOccluded) ?? defaults.pauseWhenOccluded
        self.pauseOnLowPower =
            try container.decodeIfPresent(Bool.self, forKey: .pauseOnLowPower) ?? defaults.pauseOnLowPower
        self.pauseWhenLocked =
            try container.decodeIfPresent(Bool.self, forKey: .pauseWhenLocked) ?? defaults.pauseWhenLocked
        self.pauseOnThermalPressure =
            try container.decodeIfPresent(Bool.self, forKey: .pauseOnThermalPressure) ?? defaults.pauseOnThermalPressure
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
