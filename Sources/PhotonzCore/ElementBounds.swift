import CoreGraphics
import Foundation

/// Finds the UI element under a probe point in a screenshot, for the Measure
/// tool's hover-to-measure size readout (`next-measure-hover`, Next release).
///
/// A screenshot has no semantic UI tree, so "the element under the pointer" is
/// read from the same windowed `EdgeMap` queries snapping uses: from the probe,
/// walk each of the four directions for the nearest accepted edge, querying the
/// perpendicular window centered on the probe. Each side is taken at its
/// PROBE-SIDE luma landing (the visually clean position hugging the element,
/// the exact rule `EdgeSnapping` applies), so the rect reads the number a
/// redliner would measure to. All four sides within `maxRadius` make the rect;
/// any side missing is a quiet miss (`nil`) — never a wrong box. Nested
/// elements resolve to the innermost rect because the nearest edge per
/// direction wins by construction.
public enum ElementBounds {

    /// How far from the probe (image px) each directional walk reaches before
    /// giving up. Surfaced as the `next-measure-hover` flag's radius parameter.
    public static let defaultMaxRadius: Double = 600

    /// Half-width of the perpendicular query window centered on the probe —
    /// the same locality snapping's fallback window uses, so hover accepts the
    /// same edges a foot drag would land on.
    public static let defaultSpanRadius: Double = 32

    /// The element rect at `point`, or nil when any side has no accepted edge
    /// within `maxRadius` (including the not-yet-computed `EdgeMap.empty`).
    public static func detect(at point: CGPoint, in edges: EdgeMap,
                              maxRadius: Double = defaultMaxRadius,
                              spanRadius: Double = defaultSpanRadius) -> CGRect? {
        guard !edges.isEmpty, maxRadius > 0 else { return nil }
        let px = Double(point.x), py = Double(point.y)
        // One query per axis serves both of that axis's directions.
        let horizontal = edges.horizontalEdges(inXRange: (px - spanRadius)...(px + spanRadius))
        let vertical = edges.verticalEdges(inYRange: (py - spanRadius)...(py + spanRadius))
        guard let minY = nearestSide(horizontal, probe: py, lowerSide: true, maxRadius: maxRadius),
              let maxY = nearestSide(horizontal, probe: py, lowerSide: false, maxRadius: maxRadius),
              let minX = nearestSide(vertical, probe: px, lowerSide: true, maxRadius: maxRadius),
              let maxX = nearestSide(vertical, probe: px, lowerSide: false, maxRadius: maxRadius),
              maxX > minX, maxY > minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// The candidate nearest the probe on one side (`lowerSide` = positions at
    /// or below the probe coordinate), within `maxRadius`, read at its
    /// probe-side landing. Nil when that side has nothing accepted in range.
    private static func nearestSide(_ candidates: [EdgeCandidate], probe: Double,
                                    lowerSide: Bool, maxRadius: Double) -> Double? {
        var best: (distance: Double, landing: Double)?
        for candidate in candidates {
            let onSide = lowerSide ? candidate.position <= probe : candidate.position > probe
            guard onSide else { continue }
            let distance = abs(probe - candidate.position)
            guard distance <= maxRadius else { continue }
            if distance < (best?.distance ?? .infinity) {
                // The probe sits on the element side of this edge: above the
                // probe that's the after-side landing, below it the before-side.
                best = (distance, lowerSide ? candidate.edgeAfter : candidate.edgeBefore)
            }
        }
        return best?.landing
    }
}
