import CoreGraphics
import Foundation

/// One element edge an alignment guide crossed: where that element's edge
/// actually sits (cross-axis) and the along-axis run the element occupies.
/// Stored in the same space as the owning `MeasureContent`'s feet (layer-local
/// once built, document space while being assembled).
public struct AlignmentItem: Hashable, Codable, Sendable {
    /// The element edge's cross-axis coordinate: x for a vertical guide,
    /// y for a horizontal one.
    public var edge: CGFloat
    /// The along-axis extent of the element this edge belongs to.
    public var spanStart: CGFloat
    public var spanEnd: CGFloat

    public init(edge: CGFloat, spanStart: CGFloat, spanEnd: CGFloat) {
        self.edge = edge
        self.spanStart = spanStart
        self.spanEnd = spanEnd
    }
}

/// The payload that turns a `MeasureContent` into an alignment check: a guide
/// line whose value is a verdict, not a distance. The elements the guide
/// crossed are captured as `items` at creation time (the scan needs the edge
/// map, which never enters the document), and the verdict is derived from them
/// so it survives Codable round-trips without being stored.
public struct AlignmentCheck: Hashable, Codable, Sendable {
    public var items: [AlignmentItem]
    /// How far (px) an edge may sit from the reference line and still count as
    /// aligned.
    public var tolerance: CGFloat

    public init(items: [AlignmentItem], tolerance: CGFloat = 1) {
        self.items = items
        self.tolerance = tolerance
    }
}

/// What an alignment check found: the reference line (the median of the item
/// edges, so the majority defines "aligned" and one bad element can't drag the
/// line off), the worst deviation, and — beyond tolerance — which item is off.
public struct AlignmentVerdict: Hashable, Sendable {
    public var reference: CGFloat
    public var maxDelta: CGFloat
    public var outlierIndex: Int?
    public var isAligned: Bool

    public init(reference: CGFloat, maxDelta: CGFloat, outlierIndex: Int?, isAligned: Bool) {
        self.reference = reference
        self.maxDelta = maxDelta
        self.outlierIndex = outlierIndex
        self.isAligned = isAligned
    }
}

extension AlignmentCheck {
    /// The check's result, nil when there are fewer than two edges to compare.
    public var verdict: AlignmentVerdict? {
        guard items.count >= 2 else { return nil }
        let sorted = items.map(\.edge).sorted()
        let mid = sorted.count / 2
        let reference = sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
        var worstIndex = 0
        var worstDelta: CGFloat = 0
        for (index, item) in items.enumerated() {
            let delta = abs(item.edge - reference)
            if delta > worstDelta {
                worstDelta = delta
                worstIndex = index
            }
        }
        let aligned = worstDelta <= tolerance
        return AlignmentVerdict(reference: reference, maxDelta: worstDelta,
                                outlierIndex: aligned ? nil : worstIndex,
                                isAligned: aligned)
    }
}

/// Finds the element edges an alignment guide crosses. The guide is sampled
/// along its span; at each sample the nearest detected edge within
/// `captureRadius` of the guide's position is recorded, and consecutive samples
/// that keep seeing the same edge merge into one item. A sample that sees no
/// edge (a gap between elements) or a jump to a different edge position starts
/// a new item — that jump is exactly the misalignment being hunted, so the
/// merge tolerance is tighter than any delta worth flagging.
///
/// Resolution note: the edge map is block-summed (16px blocks), so two stacked
/// elements whose gap is smaller than a block can merge into one item when
/// their edges agree. That never changes the verdict — merged items were
/// aligned with each other by construction.
public enum AlignmentScan {

    /// How far (px) from the drawn guide an edge still counts as "the edge you
    /// meant". Generous enough that a freehand drag doesn't need to be exact.
    public static let defaultCaptureRadius: CGFloat = 12
    /// Along-axis sampling distance (px).
    public static let defaultSampleStep: CGFloat = 8
    /// Consecutive samples within this distance (px) of each other's edge are
    /// the same element edge.
    public static let runMergeTolerance: CGFloat = 1.5

    /// The element edges a guide line crosses, in document space. `axis` is the
    /// guide's direction: a `.vertical` guide at x = `position` spanning
    /// y = `span` checks vertical edges; `.horizontal` mirrors it.
    public static func items(axis: MeasureMode, position: CGFloat,
                             span: ClosedRange<CGFloat>, in edges: EdgeMap,
                             captureRadius: CGFloat = defaultCaptureRadius,
                             sampleStep: CGFloat = defaultSampleStep) -> [AlignmentItem] {
        guard !edges.isEmpty, span.upperBound > span.lowerBound, sampleStep > 0 else { return [] }
        let length = span.upperBound - span.lowerBound
        let sampleCount = max(1, Int((length / sampleStep).rounded(.up)))
        let half = Double(sampleStep) / 2

        var items: [AlignmentItem] = []
        var run: (edges: [CGFloat], start: CGFloat, end: CGFloat)?

        func closeRun() {
            guard let r = run else { return }
            let mean = r.edges.reduce(0, +) / CGFloat(r.edges.count)
            items.append(AlignmentItem(edge: mean, spanStart: r.start, spanEnd: r.end))
            run = nil
        }

        for i in 0...sampleCount {
            let t = span.lowerBound + length * CGFloat(i) / CGFloat(sampleCount)
            let window = (Double(t) - half)...(Double(t) + half)
            let candidates = axis == .vertical
                ? edges.verticalEdges(inYRange: window)
                : edges.horizontalEdges(inXRange: window)
            let nearest = candidates.min {
                abs($0.position - Double(position)) < abs($1.position - Double(position))
            }
            guard let nearest, abs(nearest.position - Double(position)) <= Double(captureRadius) else {
                closeRun()
                continue
            }
            let edge = CGFloat(nearest.position)
            if var r = run {
                let mean = r.edges.reduce(0, +) / CGFloat(r.edges.count)
                if abs(edge - mean) <= runMergeTolerance {
                    r.edges.append(edge)
                    r.end = t
                    run = r
                } else {
                    closeRun()
                    run = ([edge], t, t)
                }
            } else {
                run = ([edge], t, t)
            }
        }
        closeRun()
        return items
    }
}
