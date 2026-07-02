import CoreGraphics
import Foundation

/// Magnetizes a dragged ruler point to the UI boundaries detected in the
/// screenshot (`EdgeMap`) and to the integer pixel grid.
///
/// The model matches how a redliner thinks: the MOVING LINE snaps to parallel
/// edges it actually crosses. A horizontal leg being dragged up/down snaps its y
/// to horizontal boundaries (text tops/baselines/bottoms, borders) found within
/// the leg's x-span; a vertical line moving left/right snaps its x to vertical
/// boundaries (text-run starts, container edges) within its y-span. Callers pass
/// those spans; when omitted, a small window around the point is used.
///
/// Snapping is per-axis and independent. Tolerance is given in screen points and
/// divided by `zoom` so the magnet feels the same at any zoom. When no edge
/// captures an axis, the value rounds to the pixel grid so 1px sizer lines land
/// crisp. Captured edges are reported back for a highlight overlay.
public enum EdgeSnapping {

    public struct Snap: Equatable, Sendable {
        /// The snapped point.
        public var point: CGPoint
        /// The x of the vertical edge that captured (for a highlight), or nil if
        /// x only snapped to the pixel grid / stayed free.
        public var guideX: CGFloat?
        /// The y of the horizontal edge that captured, or nil.
        public var guideY: CGFloat?

        public init(point: CGPoint, guideX: CGFloat? = nil, guideY: CGFloat? = nil) {
            self.point = point
            self.guideX = guideX
            self.guideY = guideY
        }
    }

    /// Half-width of the fallback query window when the caller has no line span.
    public static let defaultSpanRadius: CGFloat = 32

    /// The magnet never shrinks below this many IMAGE pixels, so zooming far in
    /// (where screen tolerance ÷ zoom approaches 0) still snaps — high zoom is
    /// when pixel precision matters most. ⌘ bypasses when it gets in the way.
    public static let minimumImageTolerance: CGFloat = 4

    /// Snaps `point` against locally detected edges.
    /// - xSpan: x-range of the horizontal line the point moves (drives y-snap).
    /// - ySpan: y-range of the vertical line the point moves (drives x-snap).
    /// - zoom: canvas zoom; tolerance is `screenTolerance / zoom` in image space.
    /// - snapToPixelGrid: when no edge captures an axis, round it to whole pixels.
    public static func snap(_ point: CGPoint, edges: EdgeMap, zoom: CGFloat,
                            xSpan: ClosedRange<CGFloat>? = nil,
                            ySpan: ClosedRange<CGFloat>? = nil,
                            screenTolerance: CGFloat = 8,
                            snapToPixelGrid: Bool = true) -> Snap {
        let tolerance = max(zoom > 0 ? screenTolerance / zoom : screenTolerance,
                            minimumImageTolerance)

        let xWindow = ySpan ?? (point.y - defaultSpanRadius)...(point.y + defaultSpanRadius)
        let vertical = edges.verticalEdges(
            inYRange: Double(xWindow.lowerBound)...Double(xWindow.upperBound))
        let x = snapAxis(point.x, candidates: vertical,
                         tolerance: tolerance, pixelGrid: snapToPixelGrid)

        let yWindow = xSpan ?? (point.x - defaultSpanRadius)...(point.x + defaultSpanRadius)
        let horizontal = edges.horizontalEdges(
            inXRange: Double(yWindow.lowerBound)...Double(yWindow.upperBound))
        let y = snapAxis(point.y, candidates: horizontal,
                         tolerance: tolerance, pixelGrid: snapToPixelGrid)

        return Snap(point: CGPoint(x: x.value, y: y.value), guideX: x.guide, guideY: y.guide)
    }

    /// Snaps a single axis value to the best in-tolerance edge candidate,
    /// falling back to the pixel grid. The pick is STRENGTH-WEIGHTED, not
    /// nearest-wins: with the acceptance floor low enough to admit faint hairline
    /// dividers, weak antialiasing ghosts appear next to real text baselines — a
    /// strong edge a few px farther must beat a faint one right under the pointer,
    /// while a faint divider still captures when it's alone. Candidates snap at
    /// their POINTER-SIDE landing (the clean-background row hugging the element),
    /// and text-run clusters only expose the boundary lines on the pointer's
    /// side. Returns the captured position as the guide (nil for grid/free).
    private static func snapAxis(_ value: CGFloat, candidates: [EdgeCandidate],
                                 tolerance: CGFloat, pixelGrid: Bool) -> (value: CGFloat, guide: CGFloat?) {
        var best: (position: CGFloat, score: Double)?
        for candidate in approachSideFiltered(candidates, pointer: Double(value)) {
            // Approaching from below/right uses the element's after-side landing;
            // from above/left the before-side. (A redliner measures the gap up to
            // the element INCLUDING its antialiasing glow.)
            let landing = Double(value) > candidate.position ? candidate.edgeAfter
                                                             : candidate.edgeBefore
            let position = CGFloat(landing)
            let distance = abs(position - value)
            guard distance <= tolerance else { continue }
            // Halve the appeal every ~4px of distance; ties break toward nearer.
            let score = candidate.strength / (1.0 + Double(distance) / 4.0)
            if score > (best?.score ?? 0) {
                best = (position, score)
            }
        }
        if let best {
            return (best.position, best.position)
        }
        return (pixelGrid ? value.rounded() : value, nil)
    }

    /// Candidates closer together than this belong to one "run" (a text line's
    /// cap-top/x-height/baseline/descender lines all fall well inside it).
    private static let clusterGap: Double = 40

    /// The user's "closest side of the text" rule: a text run reads as a CLUSTER
    /// of parallel boundary lines. Approaching the run from below should only
    /// ever snap its bottom-side lines (baseline, descender bottom); from above
    /// only its top-side lines (cap top, x-height top). Isolated lines and
    /// hairline pairs (dividers, borders) pass through untouched.
    private static func approachSideFiltered(_ candidates: [EdgeCandidate],
                                             pointer: Double) -> [EdgeCandidate] {
        guard candidates.count > 2 else { return candidates }
        var result: [EdgeCandidate] = []
        var cluster: [EdgeCandidate] = []
        func flush() {
            defer { cluster.removeAll() }
            guard cluster.count >= 3,
                  let lo = cluster.first?.position, let hi = cluster.last?.position,
                  hi - lo >= 12 else {
                result.append(contentsOf: cluster)
                return
            }
            let mid = (lo + hi) / 2
            if pointer > mid {
                result.append(contentsOf: cluster.filter { $0.position >= mid })
            } else if pointer < mid {
                result.append(contentsOf: cluster.filter { $0.position <= mid })
            } else {
                result.append(contentsOf: cluster)
            }
        }
        for candidate in candidates { // sorted ascending by position
            if let last = cluster.last, candidate.position - last.position > clusterGap {
                flush()
            }
            cluster.append(candidate)
        }
        flush()
        return result
    }
}
