import CoreGraphics
import Foundation

// MARK: - The camera's perspective, from the selection and the Info popover
//
// The user's prototype (`docs/design/mocks/pages/selection-transform.html`,
// approved 2026-11-01): perspective belongs to the document's one camera
// (`SceneCamera.perspective`, its angle of view), so changing it moves EVERY
// layer turned in 3D. In 3D a pill beside the mode chip shows it; a click
// opens None, Subtle, Normal, Strong and a slider, a sideways drag scrubs it,
// and Option on an edge pill scrubs it too, with dashed lines to the vanishing
// point while it moves. The tool bar's Info popover offers the same presets
// and slider.

public enum PerspectiveControl {
    public struct Preset: Hashable, Sendable {
        public let name: String
        public let degrees: Double
    }

    /// The prototype's four, in its order. Normal is the default camera's.
    public static let presets: [Preset] = [
        Preset(name: "None", degrees: 0), Preset(name: "Subtle", degrees: 20),
        Preset(name: "Normal", degrees: SceneCamera.defaultPerspective), Preset(name: "Strong", degrees: 90),
    ]

    /// What the slider and a scrub reach. The camera can be set wider by a
    /// typed number (`SceneCamera.widestPerspective`), and a scrub never
    /// snaps such a camera back down unasked.
    public static let range: ClosedRange<Double> = 0...120

    /// Points of sideways travel for each degree: the pill's own rate, and
    /// Option on an edge pill's slower one (both the prototype's).
    public static let pillRate: Double = 2
    public static let edgeRate: Double = 3

    /// The preset a value is exactly on, if any.
    public static func preset(matching degrees: Double) -> Preset? {
        presets.first { abs($0.degrees - degrees) < 0.5 }
    }

    /// What the pill says: None, or whole degrees.
    public static func label(_ degrees: Double) -> String {
        let whole = degrees.isFinite ? degrees.rounded() : 0
        return whole <= 0 ? "None" : "\(Int(whole))°"
    }

    /// A press on the pill becomes a scrub once the hand has really moved.
    public static func isScrub(_ delta: CGPoint) -> Bool { abs(delta.x) > 3 }

    /// The perspective after a sideways drag of `dx` view points from
    /// `start`, in whole degrees, inside `range` (or, from a camera already
    /// wider than it, no wider than it was).
    public static func scrubbed(from start: Double, by dx: CGFloat,
                                pointsPerDegree: Double = pillRate) -> Double {
        let begun = start.isFinite ? start : SceneCamera.defaultPerspective
        let moved = (begun + Double(dx) / pointsPerDegree).rounded()
        let ceiling = max(range.upperBound, begun)
        return min(max(moved, range.lowerBound), ceiling)
    }
}

// MARK: - A shadow that grows as a layer comes forward

/// A layer pulled toward the viewer is further from the canvas it casts its
/// shadow on, so the shadow falls further off and softer; one pushed back
/// casts a tighter one. Only what the layer already casts changes: a layer
/// with no shadow gains none, because that would restyle somebody's design.
public enum DepthShadow {
    /// How far forward doubles the shadow's offset and softness, in document
    /// points: the depth grip's rate makes that about eighty points of drag.
    public static let doublingDepth: Double = 200
    public static let largest: Double = 4
    public static let smallest: Double = 0.25

    /// How much bigger the shadow is at `depth`: one on the canvas.
    public static func scale(forDepth depth: Double) -> Double {
        guard depth.isFinite else { return 1 }
        return min(max(pow(2, depth / doublingDepth), smallest), largest)
    }

    /// `shadows` cast from `depth`: drop shadows further off and softer
    /// forward (and a little lighter, spread over more), tighter back. Inner
    /// shadows are inside the layer and do not move.
    public static func lifted(_ shadows: [ShadowStyle], depth: Double) -> [ShadowStyle] {
        let k = scale(forDepth: depth)
        guard abs(k - 1) > 1e-9 else { return shadows }
        return shadows.map { shadow in
            guard shadow.kind == .drop else { return shadow }
            var lifted = shadow
            lifted.radius = shadow.radius * CGFloat(k)
            lifted.offset = CGSize(width: shadow.offset.width * CGFloat(k), height: shadow.offset.height * CGFloat(k))
            if k > 1 { lifted.opacity = shadow.opacity * pow(k, -0.25) }
            return lifted
        }
    }
}

// MARK: - Where depth goes

extension Space3D {
    /// Where the dashed lines go while the perspective is scrubbed: the point
    /// a card's receding edges run to, read off the four corners the camera
    /// sees (`quad`, clockwise from top-left, in any one space). Of its two
    /// pairs of opposite edges, the pair that converges hardest (the one
    /// whose meeting point is nearer the card) is the one receding most. A
    /// card square on to the camera has edges that never meet, and its lines
    /// go to `fallback`: the middle of the view, where lines straight into
    /// the picture meet.
    public static func vanishingPoint(ofQuad quad: [CGPoint], fallback: CGPoint) -> CGPoint {
        guard quad.count == 4 else { return fallback }
        let centre = CGPoint(x: quad.reduce(0) { $0 + $1.x } / 4, y: quad.reduce(0) { $0 + $1.y } / 4)
        let size = max(hypot(quad[2].x - quad[0].x, quad[2].y - quad[0].y),
                       hypot(quad[3].x - quad[1].x, quad[3].y - quad[1].y), 1)
        /// Where the line through a, b meets the line through c, d.
        func meet(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> CGPoint? {
            let r = CGPoint(x: b.x - a.x, y: b.y - a.y), s = CGPoint(x: d.x - c.x, y: d.y - c.y)
            let cross = r.x * s.y - r.y * s.x
            let lengths = hypot(r.x, r.y) * hypot(s.x, s.y)
            guard lengths > 1e-9, abs(cross) / lengths > 1e-4 else { return nil }
            let t = ((c.x - a.x) * s.y - (c.y - a.y) * s.x) / cross
            return CGPoint(x: a.x + r.x * t, y: a.y + r.y * t)
        }
        // The sides (bottom to top) and the top and bottom (left to right).
        let candidates = [meet(quad[3], quad[0], quad[2], quad[1]), meet(quad[0], quad[1], quad[3], quad[2])]
            .compactMap { $0 }
            .filter { hypot($0.x - centre.x, $0.y - centre.y) < size * 40 }
        return candidates.min { hypot($0.x - centre.x, $0.y - centre.y) < hypot($1.x - centre.x, $1.y - centre.y) }
            ?? fallback
    }
}
