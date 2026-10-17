import Foundation

/// Pure decision logic for wallpaper playback.
///
/// The policy has no access to AppKit, IOKit, timers or UI: every piece of
/// system state is injected through ``Inputs``. That keeps the "should the
/// wallpaper be playing?" decision deterministic and easy to reason about,
/// while ``WallpaperEngine`` owns the (side-effecting) sampling of the system
/// and the applying of the result.
struct PlaybackPolicy {
    /// Why playback is currently suspended. Several reasons can hold at once;
    /// the first one is the most "user intent"-ish, which is handy for UI copy.
    enum Reason: String, Equatable, CaseIterable {
        case userPaused
        case onBattery
        case lowPowerMode
        case thermalPressure
        case screenLocked
        case displaysAsleep
        case systemAsleep
        case sessionInactive
        case desktopOccluded

        /// Short, human readable label (English, matches the rest of the app).
        var label: String {
            switch self {
            case .userPaused: return "Paused manually"
            case .onBattery: return "On battery power"
            case .lowPowerMode: return "Low Power Mode"
            case .thermalPressure: return "Thermal pressure"
            case .screenLocked: return "Screen locked"
            case .displaysAsleep: return "Displays asleep"
            case .systemAsleep: return "System asleep"
            case .sessionInactive: return "Session inactive"
            case .desktopOccluded: return "Desktop hidden"
            }
        }
    }

    /// Everything the decision depends on.
    ///
    /// The first block is user intent (preferences + manual pause), the second
    /// is sampled system state.
    struct Inputs: Equatable {
        // MARK: User intent

        var userPaused = false
        var pauseOnBattery = true
        var pauseOnLowPower = true
        var pauseOnThermalPressure = true
        var pauseWhenLocked = true
        var pauseWhenOccluded = true

        // MARK: System state

        var powerSourceIsBattery = false
        var lowPowerModeEnabled = false
        var thermalState: ProcessInfo.ThermalState = .nominal
        var screenIsLocked = false
        var displaysAreAsleep = false
        var systemIsAsleep = false
        var sessionIsActive = true
        var desktopIsOccluded = false
    }

    /// Ordered list of the reasons currently suspending playback.
    ///
    /// Reasons that are not gated by a preference (sleep, lock of the session)
    /// always apply: a sleeping or locked machine must never keep a video
    /// decoding in the background.
    static func pauseReasons(for inputs: Inputs) -> [Reason] {
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

    static func shouldPlay(_ inputs: Inputs) -> Bool {
        pauseReasons(for: inputs).isEmpty
    }
}
