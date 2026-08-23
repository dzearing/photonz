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

/// What an alignment check found: the reference line (the edge the majority of
/// the crossed elements agree on, so one bad element can't drag the line off),
/// the worst deviation, and — beyond tolerance — which item is off.
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
    /// The line the majority of the crossed elements agree on — the reference
    /// an "aligned" verdict is measured against.
    ///
    /// The edges are grouped into clusters (each edge within `tolerance` of its
    /// cluster's running mean) and each cluster is weighed by how much GUIDE
    /// LENGTH its elements occupy, not by how many items it holds: an element
    /// the guide runs down for 100px is more of a majority than two it clips
    /// for 8px, and a scan that splits one label into two runs can't outvote a
    /// pair that really agrees. The heaviest cluster's span-weighted mean is
    /// the reference, so the guide always settles on an edge something actually
    /// sits on. A genuine tie (two edges, two clusters of equal weight) has no
    /// majority to find, so it falls back to the median and splits the
    /// difference.
    private var referenceEdge: CGFloat {
        let sorted = items.sorted { $0.edge < $1.edge }
        var clusters: [(sum: CGFloat, weight: CGFloat)] = []
        for item in sorted {
            // Length the guide spends on this element; a zero-length run still
            // counts as one sample's worth of evidence, never nothing.
            let weight = max(abs(item.spanEnd - item.spanStart), 1)
            if let last = clusters.last, abs(item.edge - last.sum / last.weight) <= tolerance {
                clusters[clusters.count - 1] = (last.sum + item.edge * weight,
                                                last.weight + weight)
            } else {
                clusters.append((item.edge * weight, weight))
            }
        }
        let heaviest = clusters.max { $0.weight < $1.weight }
        let isTie = clusters.filter { $0.weight == heaviest?.weight }.count > 1
        if let heaviest, !isTie { return heaviest.sum / heaviest.weight }
        // No majority: the median, which for two disagreeing edges is the
        // midpoint — neither is more right than the other.
        let edges = sorted.map(\.edge)
        let mid = edges.count / 2
        return edges.count % 2 == 1 ? edges[mid] : (edges[mid - 1] + edges[mid]) / 2
    }

    /// The check's result, nil when there are fewer than two edges to compare.
    public var verdict: AlignmentVerdict? {
        guard items.count >= 2 else { return nil }
        let reference = referenceEdge
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

    /// How bold a boundary has to be, next to the boldest one its own sample
    /// window offers, before the guide will treat it as the edge of an ELEMENT.
    ///
    /// Below this it is a ghost, not an element. The edge map sums in 16px
    /// blocks, so the block holding the bottom of a line of text keeps echoing
    /// that text's left edge for a sample or two BELOW the words, a couple of
    /// pixels further out and a fraction as strong. Nothing on the screen sits
    /// there. Letting those samples become an item is how a guide down a label
    /// that is 4px out came to report 5: the echo was further from the
    /// reference than the real edge, so it won the worst-offender vote and
    /// spoke for an element that does not exist.
    ///
    /// Deliberately the same fraction as `ElementBounds`' own element floor:
    /// both are asking one map the same question, and an answer that differed
    /// between hovering an element and checking its edge would be a bug of its
    /// own.
    public static let defaultElementStrength: Double = 0.2

    /// The element edges a guide line crosses, in document space. `axis` is the
    /// guide's direction: a `.vertical` guide at x = `position` spanning
    /// y = `span` checks vertical edges; `.horizontal` mirrors it.
    public static func items(axis: MeasureMode, position: CGFloat,
                             span: ClosedRange<CGFloat>, in edges: EdgeMap,
                             captureRadius: CGFloat = defaultCaptureRadius,
                             sampleStep: CGFloat = defaultSampleStep,
                             elementStrength: Double = defaultElementStrength) -> [AlignmentItem] {
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
            let candidates = (axis == .vertical
                ? edges.verticalEdges(inYRange: window)
                : edges.horizontalEdges(inXRange: window))
                .filter { $0.strength >= elementStrength }
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
