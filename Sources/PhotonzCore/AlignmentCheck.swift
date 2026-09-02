import CoreGraphics
import Foundation

/// Which side of an edge the element it belongs to sits on, in coordinate
/// terms: `before` is the lower-coordinate side (left of a vertical edge,
/// above a horizontal one), `after` the higher. The guide's axis turns this
/// into the word a person uses (`AlignedEdge`).
public enum EdgeSide: String, Hashable, Codable, Sendable {
    case before
    case after
}

/// The edge of the elements an alignment guide judged, as a redliner names it:
/// a vertical guide with the elements to its right is checking their LEFT
/// edges.
public enum AlignedEdge: String, Hashable, Codable, Sendable, CaseIterable {
    case left, right, top, bottom

    /// The capitalized word for a row name or an inspector readout.
    public var word: String {
        switch self {
        case .left: "Left"
        case .right: "Right"
        case .top: "Top"
        case .bottom: "Bottom"
        }
    }

    /// The edge a guide of `axis` is judging when its elements sit on `side`.
    public init(axis: MeasureMode, side: EdgeSide) {
        switch (axis, side) {
        case (.vertical, .after): self = .left
        case (.vertical, .before): self = .right
        case (.horizontal, .after): self = .top
        case (.horizontal, .before): self = .bottom
        }
    }
}

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
    /// Which side of `edge` the element's ink is on, when the scan could tell
    /// (`AlignmentScan.elementSide`). Nil when it could not, and for items
    /// written before this existed.
    public var elementSide: EdgeSide?

    public init(edge: CGFloat, spanStart: CGFloat, spanEnd: CGFloat,
                elementSide: EdgeSide? = nil) {
        self.edge = edge
        self.spanStart = spanStart
        self.spanEnd = spanEnd
        self.elementSide = elementSide
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

    /// The device-px tolerance for a check on a capture of `pixelScale`, from
    /// the LOGICAL px number the user set. Every readout is in points, so the
    /// tolerance is too: on a Retina capture one point is two device px, and a
    /// single device px of wobble (a border's antialiasing, a rounded corner
    /// read a row early) is half a point, not a misalignment. A capture with
    /// no scale recorded is a 1x capture.
    public static func deviceTolerance(logical: CGFloat, pixelScale: CGFloat) -> CGFloat {
        logical * max(1, pixelScale)
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

    /// The side the elements ON THE REFERENCE sit on: the span-weighted vote of
    /// the items within `tolerance` of the settled line, so an outlier facing
    /// the other way does not get a say. Items that do not know their side
    /// abstain; a tie, or no evidence at all, is nil.
    public var referenceSide: EdgeSide? {
        guard !items.isEmpty else { return nil }
        let reference = items.count >= 2 ? referenceEdge : items[0].edge
        var before: CGFloat = 0
        var after: CGFloat = 0
        for item in items where abs(item.edge - reference) <= tolerance {
            let weight = max(abs(item.spanEnd - item.spanStart), 1)
            switch item.elementSide {
            case .before: before += weight
            case .after: after += weight
            case nil: break
            }
        }
        if before == after { return nil }
        return before > after ? .before : .after
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

    /// Two boundaries closer together than this are one boundary read twice:
    /// the two flanks of a border, of a glyph stem, or of an antialiased edge.
    /// Same distance as `ElementBounds` uses for the same call, and the two
    /// must agree: an element sized by hovering and checked by a guide is one
    /// element with one edge. Which flank is the element's edge is settled by
    /// `borderFlanks`.
    public static let pairSeparation: Double = 5

    /// The band, measured out from an edge, in which the scan looks for the
    /// element's own ink to learn which side it is on. It starts past the
    /// edge's antialiasing ramp and reaches far enough to catch a button's
    /// label sitting inside its border.
    public static let sideBand: ClosedRange<CGFloat> = 3...20
    /// How much more structure one side needs over the other before the scan
    /// will name it. Below this the answer is nil, and the row says "Edge"
    /// rather than guessing a side and being wrong.
    public static let sideMargin: Double = 2
    /// Mean gradient per pixel a band has to reach to count as ink at all; a
    /// flat background on both sides means the element is a plain box whose
    /// inside is as empty as its outside.
    public static let sideFloor: Double = 0.02

    /// Which side of an edge holds the element it belongs to, judged by which
    /// side has visual structure close by: glyph strokes and borders light up
    /// the gradient field on the ink side, background stays flat. Nil when
    /// neither side is clearly busier than the other.
    public static func elementSide(axis: MeasureMode, edge: CGFloat,
                                   span: ClosedRange<CGFloat>, in edges: EdgeMap) -> EdgeSide? {
        let lo = Double(sideBand.lowerBound), hi = Double(sideBand.upperBound)
        let e = Double(edge)
        let along = Double(span.lowerBound)...Double(span.upperBound)
        let before: Double, after: Double
        switch axis {
        case .vertical:
            before = edges.verticalGradientEnergy(xRange: (e - hi)...(e - lo), inYRange: along)
            after = edges.verticalGradientEnergy(xRange: (e + lo)...(e + hi), inYRange: along)
        case .horizontal:
            before = edges.horizontalGradientEnergy(yRange: (e - hi)...(e - lo), inXRange: along)
            after = edges.horizontalGradientEnergy(yRange: (e + lo)...(e + hi), inXRange: along)
        }
        if after >= sideFloor, after > before * sideMargin { return .after }
        if before >= sideFloor, before > after * sideMargin { return .before }
        return nil
    }

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

        // Every element-strength boundary near the guide, per sample, before
        // any is chosen: the pick needs to see whole runs, not one sample.
        var samples: [[EdgeCandidate]] = []
        var positions: [CGFloat] = []
        for i in 0...sampleCount {
            let t = span.lowerBound + length * CGFloat(i) / CGFloat(sampleCount)
            let window = (Double(t) - half)...(Double(t) + half)
            let candidates = (axis == .vertical
                ? edges.verticalEdges(inYRange: window)
                : edges.horizontalEdges(inXRange: window))
                .filter { $0.strength >= elementStrength
                    && abs($0.position - Double(position)) <= Double(captureRadius) }
            samples.append(candidates)
            positions.append(t)
        }
        let flanks = borderFlanks(in: samples)

        var items: [AlignmentItem] = []
        var run: (edges: [CGFloat], start: CGFloat, end: CGFloat)?

        func closeRun() {
            guard let r = run else { return }
            let mean = r.edges.reduce(0, +) / CGFloat(r.edges.count)
            let side = elementSide(axis: axis, edge: mean, span: r.start...r.end, in: edges)
            items.append(AlignmentItem(edge: mean, spanStart: r.start, spanEnd: r.end,
                                       elementSide: side))
            run = nil
        }

        for (i, candidates) in samples.enumerated() {
            let t = positions[i]
            let nearest = candidates.enumerated()
                .filter { !flanks[i].contains($0.offset) }
                .map(\.element)
                .min { abs($0.position - Double(position)) < abs($1.position - Double(position)) }
            guard let nearest else {
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

    /// One boundary read twice, and the reading that is NOT the element's
    /// edge: per sample, the indices into `samples[i]` of the candidates to
    /// leave alone.
    ///
    /// A bordered button's top is its outer edge and, three device px inside
    /// it on a 2x capture, the fainter edge where the border meets the fill.
    /// Its rounded corners only reach the outer one. A guide drawn along the
    /// inner flank (the anchor snap can land there) used to take it as the
    /// nearest edge on the straight run and the outer edge at the corners, so
    /// one button became three items and read 1 px out of line with the filled
    /// button beside it, whose top is one boundary.
    ///
    /// Boldness cannot settle which flank is the edge: the two sides of a glyph
    /// stem are as bold as each other, and which is bolder is noise. Extent
    /// can. The candidates are chained into tracks along the guide (each sample
    /// within `runMergeTolerance` of its track's running mean), and where two
    /// tracks sit within `pairSeparation` of each other and one runs strictly
    /// inside the other, the SHORTER one is the flank: a border's inner side
    /// stops at the corners, a descender line stops at the descender, and the
    /// edge that runs the whole element is the element's. Two readings of equal
    /// extent (a stem's two sides) are left to the guide's own position.
    static func borderFlanks(in samples: [[EdgeCandidate]]) -> [Set<Int>] {
        struct Track {
            var sum: Double = 0
            var count = 0
            var first: Int
            var last: Int
            var members: [(sample: Int, index: Int)] = []
            var mean: Double { sum / Double(max(count, 1)) }
        }
        var open: [Track] = []
        var closed: [Track] = []
        for (i, candidates) in samples.enumerated() {
            var extended = Set<Int>()
            var claimed = Set<Int>()
            for (c, candidate) in candidates.enumerated() {
                var best: (track: Int, distance: Double)?
                for (t, track) in open.enumerated() where !extended.contains(t) {
                    let distance = abs(candidate.position - track.mean)
                    if distance <= Double(runMergeTolerance),
                       distance < (best?.distance ?? .infinity) {
                        best = (t, distance)
                    }
                }
                guard let best else { continue }
                open[best.track].sum += candidate.position
                open[best.track].count += 1
                open[best.track].last = i
                open[best.track].members.append((i, c))
                extended.insert(best.track)
                claimed.insert(c)
            }
            var still: [Track] = []
            for (t, track) in open.enumerated() {
                if extended.contains(t) { still.append(track) } else { closed.append(track) }
            }
            open = still
            for (c, candidate) in candidates.enumerated() where !claimed.contains(c) {
                open.append(Track(sum: candidate.position, count: 1, first: i, last: i,
                                  members: [(i, c)]))
            }
        }
        closed.append(contentsOf: open)

        var flanks = [Set<Int>](repeating: [], count: samples.count)
        for track in closed {
            let isFlank = closed.contains { other in
                abs(other.mean - track.mean) < pairSeparation
                    && other.first <= track.first && track.last <= other.last
                    && other.last - other.first > track.last - track.first
            }
            guard isFlank else { continue }
            for member in track.members { flanks[member.sample].insert(member.index) }
        }
        return flanks
    }
}
