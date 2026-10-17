import Foundation

/// Coordinates the favorites rotation across the connected displays.
///
/// Two strategies are supported: a single shared pick for every display
/// (``RotationMode/sameOnAllDisplays``) or an independent pick per display
/// (``RotationMode/differentPerDisplay``), where the videos chosen in the
/// same tick are kept distinct whenever the favorites allow it.
public struct RotationPlanner: Sendable {
    public init() {}

    /// A single pick shared by every display (same-wallpaper mode).
    public func pick(
        for screenKeys: [String],
        rotation: inout FavoritesRotation,
        eligible: [String],
        current: [String: String],
        using generator: inout some RandomNumberGenerator
    ) -> String? {
        rotation.next(from: eligible, avoiding: Set(current.values), using: &generator)
    }

    /// One pick per display (different-wallpaper mode). `rotations` is mutated
    /// in place so each display keeps its own cycle across ticks.
    public func picks(
        for screenKeys: [String],
        eligible: [String],
        current: [String: String],
        rotations: inout [String: FavoritesRotation],
        distinctAcrossScreens: Bool,
        using generator: inout some RandomNumberGenerator
    ) -> [String: String] {
        guard !eligible.isEmpty else { return [:] }

        var result: [String: String] = [:]
        var taken: Set<String> = []

        for key in screenKeys {
            let ownCurrent = current[key].map { Set([$0]) } ?? []
            let otherCurrent = Set(current.filter { $0.key != key }.values)

            var rotation = rotations[key] ?? FavoritesRotation()
            var picked: String?

            if distinctAcrossScreens {
                picked = rotation.next(
                    from: eligible,
                    avoiding: taken.union(ownCurrent).union(otherCurrent),
                    using: &generator
                )
                if picked == nil {
                    picked = rotation.next(
                        from: eligible,
                        avoiding: taken.union(ownCurrent),
                        using: &generator
                    )
                }
                if picked == nil {
                    picked = rotation.next(from: eligible, avoiding: Set<String>(), using: &generator)
                }
            } else {
                picked = rotation.next(from: eligible, avoiding: ownCurrent, using: &generator)
                if picked == nil {
                    picked = rotation.next(from: eligible, avoiding: Set<String>(), using: &generator)
                }
            }

            let url = picked ?? ownCurrent.first
            // Persist the mutated cycle even when the pick fell back.
            rotations[key] = rotation
            if let url {
                result[key] = url
                taken.insert(url)
            }
        }

        return result
    }
}
