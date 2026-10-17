import XCTest

@testable import MagicWallCore

/// Deterministic generator so the planner tests never flake.
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

final class RotationPlannerTests: XCTestCase {
    func testTwoScreensGetDistinctPicksAndCompleteTheirOwnCycle() {
        let planner = RotationPlanner()
        let screens = ["display:1", "display:2"]
        let favorites = ["a", "b", "c", "d"]

        var rotations: [String: FavoritesRotation] = [:]
        var current = ["display:1": "a", "display:2": "b"]
        var generator = SeededGenerator(seed: 42)

        for tick in 1...favorites.count {
            let picks = planner.picks(
                for: screens,
                eligible: favorites,
                current: current,
                rotations: &rotations,
                distinctAcrossScreens: true,
                using: &generator
            )

            XCTAssertEqual(picks.count, screens.count, "Every screen must receive a pick on tick \(tick)")

            // The two videos chosen in the same tick never repeat.
            XCTAssertEqual(Set(picks.values).count, screens.count, "Picks within a tick must be distinct")

            // No screen shows the video that was already on it.
            for key in screens {
                XCTAssertNotEqual(picks[key], current[key], "\(key) must not repeat its current video")
            }

            // Each screen's cycle grows by one every tick: no repeat until all
            // four favorites have been shown.
            for key in screens {
                XCTAssertEqual(
                    rotations[key]?.shownVideoIDs.count,
                    tick,
                    "\(key) must advance its cycle by exactly one each tick"
                )
            }

            current = picks
        }

        // After a full cycle every favorite was shown exactly once per screen.
        for key in screens {
            XCTAssertEqual(rotations[key]?.shownVideoIDs, Set(favorites))
        }
    }

    func testTwoFavoritesOnTwoScreensNeverReturnNil() {
        let planner = RotationPlanner()
        let screens = ["display:1", "display:2"]
        let favorites = ["a", "b"]

        var rotations: [String: FavoritesRotation] = [:]
        let current = ["display:1": "a", "display:2": "b"]
        var generator = SeededGenerator(seed: 7)

        let picks = planner.picks(
            for: screens,
            eligible: favorites,
            current: current,
            rotations: &rotations,
            distinctAcrossScreens: true,
            using: &generator
        )

        XCTAssertEqual(picks.count, 2)
        XCTAssertNotNil(picks["display:1"])
        XCTAssertNotNil(picks["display:2"])
        XCTAssertEqual(Set(picks.values), Set(favorites), "The two exhausted screens fall back to the two favorites")
    }

    func testSingleFavoriteCanBeSharedByBothScreens() {
        let planner = RotationPlanner()
        let screens = ["display:1", "display:2"]
        let favorites = ["only"]

        var rotations: [String: FavoritesRotation] = [:]
        var generator = SeededGenerator(seed: 99)

        let picks = planner.picks(
            for: screens,
            eligible: favorites,
            current: [:],
            rotations: &rotations,
            distinctAcrossScreens: true,
            using: &generator
        )

        XCTAssertEqual(picks.count, 2)
        XCTAssertEqual(picks["display:1"], "only")
        XCTAssertEqual(picks["display:2"], "only")
    }

    func testEmptyEligibleListReturnsEmptyDictionary() {
        let planner = RotationPlanner()
        var rotations: [String: FavoritesRotation] = [:]
        var generator = SeededGenerator(seed: 3)

        let picks = planner.picks(
            for: ["display:1", "display:2"],
            eligible: [],
            current: ["display:1": "a"],
            rotations: &rotations,
            distinctAcrossScreens: true,
            using: &generator
        )

        XCTAssertTrue(picks.isEmpty)
    }

    func testSharedPickNeverRepeatsAnythingOnScreen() {
        let planner = RotationPlanner()
        var rotation = FavoritesRotation()
        var generator = SeededGenerator(seed: 21)

        let pick = planner.pick(
            for: ["display:1", "display:2"],
            rotation: &rotation,
            eligible: ["a", "b", "c"],
            current: ["display:1": "a", "display:2": "b"],
            using: &generator
        )

        XCTAssertEqual(pick, "c", "The only favorite not on screen must be chosen")
        XCTAssertEqual(rotation.shownVideoIDs, ["c"])
    }
}
