import XCTest

@testable import MagicWallCore

/// Deterministic generator so the cycle tests never flake.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}

final class FavoritesRotationTests: XCTestCase {
    func testEveryFavoriteIsShownOncePerCycle() {
        var rotation = FavoritesRotation()
        var generator = SeededGenerator(seed: 42)
        let favorites = ["a", "b", "c", "d", "e"]

        var shown: [String] = []
        for _ in 0..<favorites.count {
            guard let pick = rotation.next(from: favorites, avoiding: nil, using: &generator) else {
                return XCTFail("Expected a pick while the cycle is not exhausted")
            }
            shown.append(pick)
        }

        XCTAssertEqual(Set(shown).count, favorites.count, "Every favorite must appear exactly once per cycle")
        XCTAssertEqual(rotation.shownVideoIDs, Set(favorites))
    }

    func testNewCycleAvoidsTheVideoOnScreen() {
        var rotation = FavoritesRotation(shownVideoIDs: ["a", "b", "c"])
        var generator = SeededGenerator(seed: 7)

        guard let pick = rotation.next(from: ["a", "b", "c"], avoiding: "c", using: &generator) else {
            return XCTFail("Expected a pick after the cycle completed")
        }

        XCTAssertNotEqual(pick, "c", "A new cycle must not open with the video already on screen")
        XCTAssertEqual(rotation.shownVideoIDs, Set([pick]), "The new cycle starts from the picked video only")
    }

    func testSingleFavoriteRestartsWithItself() {
        var rotation = FavoritesRotation(shownVideoIDs: ["only"])
        var generator = SeededGenerator(seed: 1)

        let pick = rotation.next(from: ["only"], avoiding: "only", using: &generator)

        XCTAssertEqual(pick, "only", "With one favorite there is nothing else to show")
    }

    func testRemovedFavoritesAreForgottenMidCycle() {
        var rotation = FavoritesRotation(shownVideoIDs: ["a", "b", "c"])
        var generator = SeededGenerator(seed: 3)

        // "a" was unfavorited; "b" and "c" were already shown, "d" is new.
        let pick = rotation.next(from: ["b", "c", "d"], avoiding: "b", using: &generator)

        XCTAssertEqual(pick, "d")
        XCTAssertEqual(rotation.shownVideoIDs, ["b", "c", "d"])
    }

    func testEmptyEligibleListReturnsNil() {
        var rotation = FavoritesRotation(shownVideoIDs: ["a"])
        var generator = SeededGenerator(seed: 5)

        XCTAssertNil(rotation.next(from: [], avoiding: nil, using: &generator))
        XCTAssertTrue(rotation.shownVideoIDs.isEmpty)
    }

    func testPreferencesRoundTrip() {
        let preferences = RotationPreferences(
            enabled: true,
            interval: .thirtyMinutes,
            shownVideoIDs: ["a", "b"]
        )

        let decoded = RotationPreferences(encoded: preferences.encoded())

        XCTAssertEqual(decoded, preferences)
    }

    func testPreferencesRejectGarbage() {
        XCTAssertNil(RotationPreferences(encoded: nil))
        XCTAssertNil(RotationPreferences(encoded: "not json"))
    }

    func testDefaultIntervalIsFifteenMinutes() {
        XCTAssertEqual(RotationInterval.default, .fifteenMinutes)
        XCTAssertEqual(RotationInterval.oneHour.timeInterval, 3600)
        XCTAssertEqual(RotationInterval.allCases.map(\.minutes), [1, 5, 15, 30, 60])
    }

    // MARK: - Rotation mode

    func testLegacyJSONDecodesNewFieldsToTheirDefaults() {
        let legacy = #"{"enabled":true,"interval":30,"shownVideoIDs":["a","b"]}"#

        guard let decoded = RotationPreferences(encoded: legacy) else {
            return XCTFail("Legacy preferences must keep decoding")
        }

        XCTAssertTrue(decoded.enabled)
        XCTAssertEqual(decoded.interval, .thirtyMinutes)
        XCTAssertEqual(decoded.shownVideoIDs, ["a", "b"])
        XCTAssertEqual(decoded.mode, .sameOnAllDisplays)
        XCTAssertTrue(decoded.shownVideoIDsByScreen.isEmpty)
    }

    func testPreferencesRoundTripPreservesModeAndPerScreenProgress() {
        let preferences = RotationPreferences(
            enabled: true,
            interval: .fiveMinutes,
            shownVideoIDs: ["shared"],
            mode: .differentPerDisplay,
            shownVideoIDsByScreen: ["display:1": ["a"], "display:2": ["b"]]
        )

        let decoded = RotationPreferences(encoded: preferences.encoded())

        XCTAssertEqual(decoded, preferences)
        XCTAssertEqual(decoded?.mode, .differentPerDisplay)
        XCTAssertEqual(
            decoded?.shownVideoIDsByScreen,
            ["display:1": ["a"], "display:2": ["b"]]
        )
    }

    func testRotationModeHasExactlyTwoCasesWithLegacyDefault() {
        XCTAssertEqual(RotationMode.allCases.count, 2)
        XCTAssertEqual(RotationMode.default, .sameOnAllDisplays)
        XCTAssertEqual(
            Set(RotationMode.allCases),
            [.sameOnAllDisplays, .differentPerDisplay]
        )
    }

    func testBannedSetIsRespectedWhenPoolHasAlternatives() {
        var rotation = FavoritesRotation()
        var generator = SeededGenerator(seed: 11)

        let pick = rotation.next(
            from: ["a", "b", "c", "d"],
            avoiding: ["a", "b"],
            using: &generator
        )

        XCTAssertTrue(pick == "c" || pick == "d")
        XCTAssertEqual(rotation.shownVideoIDs, [pick!])
    }
}
