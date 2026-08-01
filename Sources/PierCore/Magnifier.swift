import CoreGraphics
import Foundation

/// The swell under the pointer.
///
/// Kept as pure arithmetic on purpose: this is the one piece of a dock everybody notices
/// when it's wrong, and it's much easier to prove correct than to eyeball.
public struct Magnifier: Sendable, Equatable {
    /// 0 turns it off; 1 makes the hovered icon twice its size.
    public var strength: Double
    /// How many tiles either side get pulled up with it.
    public var radius: Double

    public init(strength: Double = 0.55, radius: Double = 2.2) {
        self.strength = min(max(strength, 0), 1)
        self.radius = max(radius, 0.001)
    }

    public var isEnabled: Bool { strength > 0 }

    /// Scale for one item, given how many tiles away the pointer is.
    public func scale(distanceInItems distance: Double) -> Double {
        guard isEnabled else { return 1 }
        let normalized = min(abs(distance) / radius, 1)
        // Raised cosine: 1 at the centre, 0 at the edge of the radius, and flat at both
        // ends so the swell has no visible seam where it stops.
        let falloff = (cos(normalized * .pi) + 1) / 2
        return 1 + strength * falloff
    }

    /// Scales for every item. `hovered` is a fractional item index — 2.5 means the
    /// pointer is on the boundary between the third and fourth tiles.
    public func scales(count: Int, hovered: Double?) -> [Double] {
        guard count > 0 else { return [] }
        guard let hovered, isEnabled else { return Array(repeating: 1, count: count) }
        return (0..<count).map { scale(distanceInItems: Double($0) - hovered) }
    }

    /// How far each item slides along the axis so its neighbours' growth doesn't overlap
    /// it. Items before the pointer move back, items after move forward, and the total
    /// displacement is symmetric so the dock doesn't drift.
    public func offsets(count: Int, hovered: Double?, itemLength: Double) -> [Double] {
        let scales = self.scales(count: count, hovered: hovered)
        guard let hovered, isEnabled, count > 0 else {
            return Array(repeating: 0, count: count)
        }

        var offsets = Array(repeating: 0.0, count: count)
        let growth = scales.map { ($0 - 1) * itemLength }

        // Everything to the left of the pointer is pushed left by half of the growth of
        // each tile between it and the pointer, and vice versa.
        for index in 0..<count {
            var displacement = 0.0
            if Double(index) < hovered {
                for other in (index + 1)..<count where Double(other) <= hovered + 0.5 {
                    displacement -= growth[other] / 2
                }
            } else {
                for other in 0..<index where Double(other) >= hovered - 0.5 {
                    displacement += growth[other] / 2
                }
            }
            offsets[index] = displacement
        }
        return offsets
    }

    /// Widest the dock can get while magnified — what the window has to leave room for.
    public var maximumScale: Double { 1 + strength }
}
