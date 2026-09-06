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
        /// The vertical CANVAS GRID line the point came to rest on, when the
        /// grid is what placed it. Nil when a real edge won instead, or when
        /// the grid is not pulling. Kept apart from `guideX` for the same
        /// reason `Snapping.Result` keeps them apart: a guide says "you lined
        /// up with that thing" and is news, a grid line says "you are on this
        /// line", and the canvas lights the two differently.
        public var gridX: CGFloat?
        /// The same for the horizontal grid line.
        public var gridY: CGFloat?

        public init(point: CGPoint, guideX: CGFloat? = nil, guideY: CGFloat? = nil,
                    gridX: CGFloat? = nil, gridY: CGFloat? = nil) {
            self.point = point
            self.guideX = guideX
            self.guideY = guideY
            self.gridX = gridX
            self.gridY = gridY
        }
    }

    /// Extra snap lines the caller supplies alongside the detected edges:
    /// document x positions that a vertical line may land on, and y positions
    /// for a horizontal one. `MeasureSnapping` fills these from the other
    /// measurements on the canvas, so callouts line up with each other.
    public struct GuideLines: Equatable, Sendable {
        /// x positions — candidates for the x axis.
        public var vertical: [CGFloat]
        /// y positions — candidates for the y axis.
        public var horizontal: [CGFloat]

        public init(vertical: [CGFloat] = [], horizontal: [CGFloat] = []) {
            self.vertical = vertical
            self.horizontal = horizontal
        }

        public static let none = GuideLines()
        public var isEmpty: Bool { vertical.isEmpty && horizontal.isEmpty }
    }

    /// A supplied guide outranks a detected edge, because somebody put it
    /// there on purpose: at equal distance the guide takes the snap. It is
    /// deliberately not overwhelming — a maximally strong edge sitting under
    /// the pointer still beats a guide roughly two pixels away, so lining up
    /// with a neighbouring callout never costs you the pixel edge you are
    /// actually standing on.
    public static let guideStrength: Double = 1.5

    /// Half-width of the fallback query window when the caller has no line span.
    public static let defaultSpanRadius: CGFloat = 32

    /// The magnet never shrinks below this many IMAGE pixels, so zooming far in
    /// (where screen tolerance ÷ zoom approaches 0) still snaps — high zoom is
    /// when pixel precision matters most. ⌘ bypasses when it gets in the way.
    public static let minimumImageTolerance: CGFloat = 4

    /// A midpoint candidate scores at this fraction of its pair's fainter
    /// strength, so a real edge at equal distance always wins the tie and
    /// midpoints of antialiasing-ghost pairs stay too weak to steal a snap.
    public static let centerScoreFactor: Double = 0.5

    /// The magnet's reach in IMAGE pixels at a given zoom.
    public static func tolerance(zoom: CGFloat, screenTolerance: CGFloat = 8) -> CGFloat {
        max(zoom > 0 ? screenTolerance / zoom : screenTolerance, minimumImageTolerance)
    }

    /// Snaps ONE axis to supplied guide lines alone — no detected edges, no
    /// centers. What a readout chip's cross-axis drag uses: the chip is not a
    /// measured point, so the picture's own edges have no say over where it
    /// parks, but the other chips do.
    public static func snapValue(_ value: CGFloat, toGuides guides: [CGFloat], zoom: CGFloat,
                                 screenTolerance: CGFloat = 8,
                                 snapToPixelGrid: Bool = true,
                                 holding held: CGFloat? = nil) -> (value: CGFloat, guide: CGFloat?) {
        snapAxis(value, candidates: [], guides: guides,
                 tolerance: tolerance(zoom: zoom, screenTolerance: screenTolerance),
                 includeCenters: false, pixelGrid: snapToPixelGrid, held: held)
    }

    /// Snaps `point` against locally detected edges.
    /// - xSpan: x-range of the horizontal line the point moves (drives y-snap).
    /// - ySpan: y-range of the vertical line the point moves (drives x-snap).
    /// - zoom: canvas zoom; tolerance is `screenTolerance / zoom` in image space.
    /// - includeCenters: also offer the midpoint between each pair of adjacent
    ///   accepted edges — element centers and gap centers fall out of the same
    ///   rule (`next-measure-center-snap`, "Edges and centers").
    /// - snapToPixelGrid: when no edge captures an axis, round it to whole pixels.
    /// - guides: extra lines the caller wants this point to land on, whatever
    ///   the picture underneath says (the other measurements on the canvas).
    /// - holding: the lines this drag already caught. A line being SHOWN keeps
    ///   the point until the pointer is clearly away from it, so a wobbling
    ///   hand cannot take a snap and give it back on alternate frames. See
    ///   `SnapHold`.
    public static func snap(_ point: CGPoint, edges: EdgeMap, zoom: CGFloat,
                            xSpan: ClosedRange<CGFloat>? = nil,
                            ySpan: ClosedRange<CGFloat>? = nil,
                            screenTolerance: CGFloat = 8,
                            includeCenters: Bool = false,
                            snapToPixelGrid: Bool = true,
                            guides: GuideLines = .none,
                            holding held: SnapHold = .none) -> Snap {
        let tolerance = tolerance(zoom: zoom, screenTolerance: screenTolerance)

        let xWindow = ySpan ?? (point.y - defaultSpanRadius)...(point.y + defaultSpanRadius)
        let vertical = edges.verticalEdges(
            inYRange: Double(xWindow.lowerBound)...Double(xWindow.upperBound))
        let x = snapAxis(point.x, candidates: vertical, guides: guides.vertical,
                         tolerance: tolerance,
                         includeCenters: includeCenters, pixelGrid: snapToPixelGrid,
                         held: held.x)

        let yWindow = xSpan ?? (point.x - defaultSpanRadius)...(point.x + defaultSpanRadius)
        let horizontal = edges.horizontalEdges(
            inXRange: Double(yWindow.lowerBound)...Double(yWindow.upperBound))
        let y = snapAxis(point.y, candidates: horizontal, guides: guides.horizontal,
                         tolerance: tolerance,
                         includeCenters: includeCenters, pixelGrid: snapToPixelGrid,
                         held: held.y)

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
                                 guides: [CGFloat] = [],
                                 tolerance: CGFloat, includeCenters: Bool,
                                 pixelGrid: Bool,
                                 held: CGFloat? = nil) -> (value: CGFloat, guide: CGFloat?) {
        // A line already caught outranks everything else while the pointer is
        // anywhere near it — twice as near as it took to catch. Scores decide
        // which line to TAKE; nothing but distance decides when to let one go,
        // or the answer would change under a hand that is standing still.
        if let held, abs(held - value) <= tolerance * SnapHold.releaseFactor {
            return (held, held)
        }
        var best: (position: CGFloat, score: Double)?
        // Supplied guides go first so an equal-scoring edge cannot displace
        // them, and so guides tie-break toward the lower position.
        for line in guides {
            let distance = abs(line - value)
            guard distance <= tolerance else { continue }
            let score = guideStrength / (1.0 + Double(distance) / 4.0)
            if score > (best?.score ?? 0) {
                best = (line, score)
            }
        }
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
        // Midpoints between adjacent accepted edges: element centers and gap
        // centers fall out of the same rule. Built from the UNFILTERED list —
        // the approach-side rule is about which side of a text run an edge snap
        // may land on, while a center is a target of its own. Running after the
        // edge loop with a strict `>` means a real edge keeps any exact tie.
        if includeCenters {
            for (a, b) in zip(candidates, candidates.dropFirst()) {
                let position = CGFloat(a.position + b.position) / 2
                let distance = abs(position - value)
                guard distance <= tolerance else { continue }
                let score = centerScoreFactor * min(a.strength, b.strength)
                    / (1.0 + Double(distance) / 4.0)
                if score > (best?.score ?? 0) {
                    best = (position, score)
                }
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
