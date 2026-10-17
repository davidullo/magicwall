import XCTest

@testable import MagicWallCore

/// The playback policy is the "should the wallpaper be playing?" decision:
/// these tests pin the defaults (a fresh install keeps playing on battery) and
/// the reasons that always apply.
final class PlaybackPolicyTests: XCTestCase {
    func testDefaultRuntimeKeepsPlayingOnBattery() {
        var inputs = PlaybackPolicy.Inputs()
        inputs.powerSourceIsBattery = true

        XCTAssertEqual(PlaybackPolicy.pauseReasons(for: inputs), [])
        XCTAssertTrue(PlaybackPolicy.shouldPlay(inputs))
    }

    func testBatteryPausesOnlyWhenTheRuleIsOn() {
        var inputs = PlaybackPolicy.Inputs()
        inputs.powerSourceIsBattery = true
        inputs.pauseOnBattery = true

        XCTAssertEqual(PlaybackPolicy.pauseReasons(for: inputs), [.onBattery])
        XCTAssertFalse(PlaybackPolicy.shouldPlay(inputs))
    }

    func testProtectiveRulesAreOnByDefault() {
        var inputs = PlaybackPolicy.Inputs()
        inputs.lowPowerModeEnabled = true
        XCTAssertEqual(PlaybackPolicy.pauseReasons(for: inputs), [.lowPowerMode])

        inputs = PlaybackPolicy.Inputs()
        inputs.thermalState = .serious
        XCTAssertEqual(PlaybackPolicy.pauseReasons(for: inputs), [.thermalPressure])

        inputs = PlaybackPolicy.Inputs()
        inputs.screenIsLocked = true
        XCTAssertEqual(PlaybackPolicy.pauseReasons(for: inputs), [.screenLocked])

        inputs = PlaybackPolicy.Inputs()
        inputs.desktopIsOccluded = true
        XCTAssertEqual(PlaybackPolicy.pauseReasons(for: inputs), [.desktopOccluded])
    }

    func testSleepAndSessionReasonsAlwaysApply() {
        var inputs = PlaybackPolicy.Inputs()
        inputs.pauseOnBattery = false
        inputs.pauseOnLowPower = false
        inputs.pauseOnThermalPressure = false
        inputs.pauseWhenLocked = false
        inputs.pauseWhenOccluded = false

        inputs.displaysAreAsleep = true
        XCTAssertEqual(PlaybackPolicy.pauseReasons(for: inputs), [.displaysAsleep])

        inputs = PlaybackPolicy.Inputs()
        inputs.systemIsAsleep = true
        XCTAssertEqual(PlaybackPolicy.pauseReasons(for: inputs), [.systemAsleep])

        inputs = PlaybackPolicy.Inputs()
        inputs.sessionIsActive = false
        XCTAssertEqual(PlaybackPolicy.pauseReasons(for: inputs), [.sessionInactive])
    }

    func testUserIntentComesFirst() {
        var inputs = PlaybackPolicy.Inputs()
        inputs.userPaused = true
        inputs.powerSourceIsBattery = true
        inputs.pauseOnBattery = true
        inputs.lowPowerModeEnabled = true

        XCTAssertEqual(
            PlaybackPolicy.pauseReasons(for: inputs),
            [.userPaused, .onBattery, .lowPowerMode]
        )
    }

    func testInputsCanBeSeededFromPersistedPreferences() {
        let preferences = PlaybackPreferences(
            pauseOnBattery: true,
            pauseWhenOccluded: false,
            pauseOnLowPower: false,
            pauseWhenLocked: false,
            pauseOnThermalPressure: false
        )
        var inputs = PlaybackPolicy.Inputs(preferences: preferences)
        inputs.powerSourceIsBattery = true
        inputs.lowPowerModeEnabled = true
        inputs.screenIsLocked = true
        inputs.desktopIsOccluded = true

        XCTAssertEqual(PlaybackPolicy.pauseReasons(for: inputs), [.onBattery])
    }

    func testNoticesOnlyForActionableReasons() {
        XCTAssertTrue(PlaybackPolicy.Reason.onBattery.deservesUserNotice)
        XCTAssertTrue(PlaybackPolicy.Reason.lowPowerMode.deservesUserNotice)
        XCTAssertTrue(PlaybackPolicy.Reason.thermalPressure.deservesUserNotice)
        XCTAssertFalse(PlaybackPolicy.Reason.userPaused.deservesUserNotice)
        XCTAssertFalse(PlaybackPolicy.Reason.screenLocked.deservesUserNotice)
        XCTAssertFalse(PlaybackPolicy.Reason.displaysAsleep.deservesUserNotice)
        XCTAssertFalse(PlaybackPolicy.Reason.systemAsleep.deservesUserNotice)
        XCTAssertFalse(PlaybackPolicy.Reason.sessionInactive.deservesUserNotice)
        XCTAssertFalse(PlaybackPolicy.Reason.desktopOccluded.deservesUserNotice)
    }
}

/// The persisted rules: defaults, round-trip and forward/backward compatible
/// decoding.
final class PlaybackPreferencesTests: XCTestCase {
    func testDefaultsPlayOnBatteryAndKeepProtectiveRules() {
        let defaults = PlaybackPreferences.default
        XCTAssertFalse(defaults.pauseOnBattery)
        XCTAssertTrue(defaults.pauseWhenOccluded)
        XCTAssertTrue(defaults.pauseOnLowPower)
        XCTAssertTrue(defaults.pauseWhenLocked)
        XCTAssertTrue(defaults.pauseOnThermalPressure)
    }

    func testEncodeDecodeRoundTrip() {
        let preferences = PlaybackPreferences(
            pauseOnBattery: true,
            pauseWhenOccluded: false,
            pauseOnLowPower: true,
            pauseWhenLocked: false,
            pauseOnThermalPressure: true
        )

        let restored = PlaybackPreferences(encoded: preferences.encoded())
        XCTAssertEqual(restored, preferences)
    }

    func testMissingKeysDecodeToDefaults() {
        // JSON written by a build that only knew about the battery rule.
        let restored = PlaybackPreferences(encoded: #"{"pauseOnBattery":true}"#)

        XCTAssertEqual(restored?.pauseOnBattery, true)
        XCTAssertEqual(restored?.pauseWhenOccluded, PlaybackPreferences.default.pauseWhenOccluded)
        XCTAssertEqual(restored?.pauseOnLowPower, PlaybackPreferences.default.pauseOnLowPower)
        XCTAssertEqual(restored?.pauseWhenLocked, PlaybackPreferences.default.pauseWhenLocked)
        XCTAssertEqual(restored?.pauseOnThermalPressure, PlaybackPreferences.default.pauseOnThermalPressure)
    }

    func testUnreadablePayloadIsNil() {
        XCTAssertNil(PlaybackPreferences(encoded: nil))
        XCTAssertNil(PlaybackPreferences(encoded: "not json"))
    }
}
