import Foundation

/// Pure decision logic for wallpaper playback.
///
/// The policy has no access to AppKit, IOKit, timers or UI: every piece of
/// system state is injected through ``Inputs``. That keeps the "should the
/// wallpaper be playing?" decision deterministic and easy to reason about,
/// while the app's `WallpaperEngine` owns the (side-effecting) sampling of the
/// system and the applying of the result.
public enum PlaybackPolicy {
    /// Why playback is currently suspended. Several reasons can hold at once;
    /// the first one is the most "user intent"-ish, which is handy for UI copy.
    public enum Reason: String, Equatable, Hashable, CaseIterable, Sendable {
        case userPaused
        case onBattery
        case lowPowerMode
        case thermalPressure
        case screenLocked
        case displaysAsleep
        case systemAsleep
        case sessionInactive
        case desktopOccluded

        /// Whether the user can act on this reason from the UI. Used to show a
        /// one-off in-app notice instead of pausing silently.
        public var deservesUserNotice: Bool {
            switch self {
            case .onBattery, .lowPowerMode, .thermalPressure:
                return true
            case .userPaused, .screenLocked, .displaysAsleep, .systemAsleep,
                 .sessionInactive, .desktopOccluded:
                return false
            }
        }
    }

    /// Everything the decision depends on.
    ///
    /// The first block is user intent (preferences + manual pause), the second
    /// is sampled system state.
    public struct Inputs: Equatable, Sendable {
        // MARK: User intent

        public var userPaused = false
        public var pauseOnBattery = PlaybackPreferences.default.pauseOnBattery
        public var pauseOnLowPower = PlaybackPreferences.default.pauseOnLowPower
        public var pauseOnThermalPressure = PlaybackPreferences.default.pauseOnThermalPressure
        public var pauseWhenLocked = PlaybackPreferences.default.pauseWhenLocked
        public var pauseWhenOccluded = PlaybackPreferences.default.pauseWhenOccluded

        // MARK: System state

        public var powerSourceIsBattery = false
        public var lowPowerModeEnabled = false
        public var thermalState: ProcessInfo.ThermalState = .nominal
        public var screenIsLocked = false
        public var displaysAreAsleep = false
        public var systemIsAsleep = false
        public var sessionIsActive = true
        public var desktopIsOccluded = false

        public init() {}

        /// Seeds the user-intent block from the persisted rules.
        public init(preferences: PlaybackPreferences) {
            self.pauseOnBattery = preferences.pauseOnBattery
            self.pauseOnLowPower = preferences.pauseOnLowPower
            self.pauseOnThermalPressure = preferences.pauseOnThermalPressure
            self.pauseWhenLocked = preferences.pauseWhenLocked
            self.pauseWhenOccluded = preferences.pauseWhenOccluded
        }
    }

    /// Ordered list of the reasons currently suspending playback.
    ///
    /// Reasons that are not gated by a preference (sleep, lock of the session)
    /// always apply: a sleeping or locked machine must never keep a video
    /// decoding in the background.
    public static func pauseReasons(for inputs: Inputs) -> [Reason] {
        var reasons: [Reason] = []

        if inputs.userPaused { reasons.append(.userPaused) }
        if inputs.pauseOnBattery, inputs.powerSourceIsBattery { reasons.append(.onBattery) }
        if inputs.pauseOnLowPower, inputs.lowPowerModeEnabled { reasons.append(.lowPowerMode) }
        if inputs.pauseOnThermalPressure,
           inputs.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue {
            reasons.append(.thermalPressure)
        }
        if inputs.pauseWhenLocked, inputs.screenIsLocked { reasons.append(.screenLocked) }
        if inputs.displaysAreAsleep { reasons.append(.displaysAsleep) }
        if inputs.systemIsAsleep { reasons.append(.systemAsleep) }
        if !inputs.sessionIsActive { reasons.append(.sessionInactive) }
        if inputs.pauseWhenOccluded, inputs.desktopIsOccluded { reasons.append(.desktopOccluded) }

        return reasons
    }

    public static func shouldPlay(_ inputs: Inputs) -> Bool {
        pauseReasons(for: inputs).isEmpty
    }
}
