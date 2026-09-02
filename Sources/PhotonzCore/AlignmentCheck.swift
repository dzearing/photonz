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
    /// Whether each item is one thing a person would count. True when the scan
    /// read the picture and joined the edge runs that belong to one element
    /// (`AlignmentScan.items` given a `LumaField`); false when the items are
    /// raw runs from the block-summed edge map, which split a curved letter or
    /// a line of text into several and merge stacked things closer than a
    /// block. A row and the inspector print the count only when this is true:
    /// "Left edges, 3 items" against "Left edges". Checks saved before the
    /// scan read pixels decode false, since their counts were runs.
    public var itemsAreElements: Bool

    public init(items: [AlignmentItem], tolerance: CGFloat = 1, itemsAreElements: Bool = true) {
        self.items = items
        self.tolerance = tolerance
        self.itemsAreElements = itemsAreElements
    }

    private enum CodingKeys: String, CodingKey {
        case items, tolerance, itemsAreElements
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decode([AlignmentItem].self, forKey: .items)
        tolerance = try c.decode(CGFloat.self, forKey: .tolerance)
        itemsAreElements = try c.decodeIfPresent(Bool.self, forKey: .itemsAreElements) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(items, forKey: .items)
        try c.encode(tolerance, forKey: .tolerance)
        try c.encode(itemsAreElements, forKey: .itemsAreElements)
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
/// that keep seeing the same edge form one RUN. A sample that sees no edge or a
/// jump to a different edge position starts a new run.
///
/// Runs are not items. The edge map is block-summed (16px blocks), so it reads
/// a curved first letter as two or three left edges, the top of a line of text
/// as cap line and x-height line by turns, a pill's rounded end as its own
/// edge, and a faint card border as nothing wherever bold text shares its
/// block; and it reads two things stacked closer than a block as one. A person
/// counts none of those that way. So, given the picture (`LumaField`), the
/// runs are regrouped by what the pixels say along the guide: a boundary that
/// keeps reading between two runs, or ink on the element's own side between
/// them, makes them one item; a clean stretch of at least `visibleGap` logical
/// px is whitespace a person can see, and separates two. Each item's edge is
/// its dominant (longest) run, so a line of text judges by the line most of
/// its letters share, and its span is the stretch the pixels covered.
///
/// Without the picture (a check built from the edge map alone) runs a sample
/// apart are joined and nothing else is known; `AlignmentCheck.itemsAreElements`
/// is how the caller says which kind it stored.
public enum AlignmentScan {

    /// How far (px) from the drawn guide an edge still counts as "the edge you
    /// meant". Generous enough that a freehand drag doesn't need to be exact.
    public static let defaultCaptureRadius: CGFloat = 12
    /// Along-axis sampling distance (px).
    public static let defaultSampleStep: CGFloat = 8
    /// Consecutive samples within this distance (px) of each other's edge are
    /// the same element edge.
    public static let runMergeTolerance: CGFloat = 1.5

    /// Whitespace along the guide a person can see, in LOGICAL px: a clean
    /// stretch at least this long separates two items; anything closer reads
    /// as one thing. A word space is under 4 pt and letters are closer still,
    /// while stacked or side-by-side elements are almost never closer than
    /// 8 pt, so a line of text stays one item and two buttons stay two. An
    /// icon hugging its label closer than this counts with the label.
    public static let visibleGap: CGFloat = 8
    /// The brightness step (0...1) across a pixel that counts as ink on the
    /// element's side of an edge. Above a hairline divider's contrast, so a
    /// rule crossing the band is not the element continuing; well under any
    /// glyph, icon or fill edge.
    public static let inkFloor: Double = 0.15
    /// The brightness step that says the boundary itself is still there: the
    /// same floor `EdgeRun` walks with, low enough for a white card on a light
    /// grey background.
    public static let boundaryFloor: Double = 0.02
    /// How far either side of a run's edge the boundary may wander and still
    /// be that boundary (a rounded corner leaving, antialiasing).
    public static let boundaryDrift: CGFloat = 2

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

    /// How faint a reading may get, next to the boldest reading of its OWN
    /// boundary elsewhere along the guide, and still count as that boundary.
    /// See `elementTracks`; a boundary that never reaches `elementStrength`
    /// anywhere is not rescued by this at all.
    public static let weakElementFraction: Double = 0.5

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
    /// y = `span` checks vertical edges; `.horizontal` mirrors it. `luma` is
    /// the picture the runs are regrouped by (see the type note); `pixelScale`
    /// turns `visibleGap` into device px.
    public static func items(axis: MeasureMode, position: CGFloat,
                             span: ClosedRange<CGFloat>, in edges: EdgeMap,
                             luma: LumaField = .empty, pixelScale: CGFloat = 1,
                             captureRadius: CGFloat = defaultCaptureRadius,
                             sampleStep: CGFloat = defaultSampleStep,
                             elementStrength: Double = defaultElementStrength) -> [AlignmentItem] {
        let runs = runs(axis: axis, position: position, span: span, in: edges,
                        captureRadius: captureRadius, sampleStep: sampleStep,
                        elementStrength: elementStrength)
        guard !runs.isEmpty else { return [] }
        let groups = luma.isEmpty
            ? groupedBySample(runs, sampleStep: sampleStep)
            : groupedByPixels(runs, axis: axis, span: span, in: luma, pixelScale: pixelScale)
        return groups.map { group in
            // The dominant run speaks for the element: the one the guide ran
            // along longest, and on a tie the one nearest the drawn line.
            let dominant = group.runs.max { a, b in
                let la = a.end - a.start, lb = b.end - b.start
                return la != lb ? la < lb : abs(a.edge - position) > abs(b.edge - position)
            }
            let edge = dominant?.edge ?? position
            let side = elementSide(axis: axis, edge: edge, span: group.span, in: edges)
            return AlignmentItem(edge: edge, spanStart: group.span.lowerBound,
                                 spanEnd: group.span.upperBound, elementSide: side)
        }
    }

    /// One stretch of samples that kept seeing the same edge.
    struct Run: Equatable {
        var edge: CGFloat
        var start: CGFloat
        var end: CGFloat
    }

    /// Runs that belong to one element, and the stretch of the guide it covers.
    struct Group: Equatable {
        var runs: [Run]
        var span: ClosedRange<CGFloat>
    }

    /// The raw runs, in guide order.
    static func runs(axis: MeasureMode, position: CGFloat,
                     span: ClosedRange<CGFloat>, in edges: EdgeMap,
                     captureRadius: CGFloat = defaultCaptureRadius,
                     sampleStep: CGFloat = defaultSampleStep,
                     elementStrength: Double = defaultElementStrength) -> [Run] {
        guard !edges.isEmpty, span.upperBound > span.lowerBound, sampleStep > 0 else { return [] }
        let length = span.upperBound - span.lowerBound
        let sampleCount = max(1, Int((length / sampleStep).rounded(.up)))
        let half = Double(sampleStep) / 2

        // Every element-strength boundary near the guide, per sample, before
        // any is chosen: the pick needs to see whole runs, not one sample.
        var readings: [[EdgeCandidate]] = []
        var positions: [CGFloat] = []
        for i in 0...sampleCount {
            let t = span.lowerBound + length * CGFloat(i) / CGFloat(sampleCount)
            let window = (Double(t) - half)...(Double(t) + half)
            let candidates = (axis == .vertical
                ? edges.verticalEdges(inYRange: window)
                : edges.horizontalEdges(inXRange: window))
                .filter { $0.strength >= elementStrength * weakElementFraction
                    && abs($0.position - Double(position)) <= Double(captureRadius) }
            readings.append(candidates)
            positions.append(t)
        }
        let samples = elementTracks(in: readings, elementStrength: elementStrength)
        let flanks = borderFlanks(in: samples)

        var runs: [Run] = []
        var run: (edges: [CGFloat], start: CGFloat, end: CGFloat)?

        func closeRun() {
            guard let r = run else { return }
            let mean = r.edges.reduce(0, +) / CGFloat(r.edges.count)
            runs.append(Run(edge: mean, start: r.start, end: r.end))
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
        return runs
    }

    /// Without pixels: runs with no empty sample between them are one element.
    /// That joins a curved letter's fragments and a text line's cap and
    /// x-height runs; it cannot see a gap smaller than a block, and says so
    /// through `AlignmentCheck.itemsAreElements`.
    static func groupedBySample(_ runs: [Run], sampleStep: CGFloat) -> [Group] {
        var groups: [Group] = []
        for run in runs {
            if let last = groups.last, run.start - last.span.upperBound <= sampleStep * 1.5 {
                groups[groups.count - 1].runs.append(run)
                groups[groups.count - 1].span = last.span.lowerBound...run.end
            } else {
                groups.append(Group(runs: [run], span: run.start...run.end))
            }
        }
        return groups
    }

    /// With pixels: walk the guide one px at a time and ask, at each step,
    /// whether something is there. "Something" is the boundary itself still
    /// reading within `boundaryDrift` of the nearest runs' edges (a card edge
    /// the strength floor dropped, a curve on its way round a corner), or ink
    /// on the element's side of that edge (the letters under a cap line, the
    /// glyph a curved stroke belongs to). Only the response ACROSS the guide
    /// counts, so a divider crossing the band is not the element continuing.
    /// A clean stretch of `visibleGap` logical px ends an element. Runs are
    /// then handed to the element they overlap most; a run the pixels never
    /// backed (block bleed past the end of a thing) is dropped.
    static func groupedByPixels(_ runs: [Run], axis: MeasureMode, span: ClosedRange<CGFloat>,
                                in luma: LumaField, pixelScale: CGFloat) -> [Group] {
        let lo = Int(span.lowerBound.rounded(.down))
        let hi = Int(span.upperBound.rounded(.up))
        guard hi >= lo, !runs.isEmpty else { return [] }
        let gap = max(1, Int((visibleGap * max(1, pixelScale)).rounded()))
        let bandLo = Int(sideBand.lowerBound), bandHi = Int(sideBand.upperBound)
        let drift = Int(boundaryDrift.rounded(.up))

        func response(along t: Int, cross c: Int) -> Double {
            switch axis {
            case .vertical: luma.verticalResponse(x: c, y: t)
            case .horizontal: luma.horizontalResponse(x: t, y: c)
            }
        }

        // Presence along the guide.
        var present = [Bool](repeating: false, count: hi - lo + 1)
        var next = 0  // first run whose end is not before t
        for t in lo...hi {
            while next < runs.count, runs[next].end < CGFloat(t) { next += 1 }
            // The runs bracketing t: the one containing it, else its neighbours.
            var edges: [CGFloat] = []
            if next < runs.count, runs[next].start <= CGFloat(t) {
                edges = [runs[next].edge]
            } else {
                if next > 0 { edges.append(runs[next - 1].edge) }
                if next < runs.count { edges.append(runs[next].edge) }
            }
            guard let minEdge = edges.min(), let maxEdge = edges.max() else { continue }
            let low = Int(minEdge.rounded()) - drift
            let high = Int(maxEdge.rounded()) + drift
            var found = false
            for c in low...high where response(along: t, cross: c) >= boundaryFloor {
                found = true
                break
            }
            if !found {
                // Ink on either side of the edge: the element's own body.
                let after = (Int(maxEdge.rounded()) + bandLo)...(Int(maxEdge.rounded()) + bandHi)
                let before = (Int(minEdge.rounded()) - bandHi)...(Int(minEdge.rounded()) - bandLo)
                for band in [after, before] {
                    for c in band where response(along: t, cross: c) >= inkFloor {
                        found = true
                        break
                    }
                    if found { break }
                }
            }
            present[t - lo] = found
        }

        // Stretches: split on any clean run of `gap` px or more.
        var stretches: [ClosedRange<Int>] = []
        var open: (first: Int, last: Int)?
        var clean = 0
        for t in lo...hi {
            if present[t - lo] {
                if let o = open, clean >= gap {
                    stretches.append(o.first...o.last)
                    open = (t, t)
                } else if open == nil {
                    open = (t, t)
                } else {
                    open?.last = t
                }
                clean = 0
            } else {
                clean += 1
            }
        }
        if let o = open { stretches.append(o.first...o.last) }

        // Each stretch takes the part of every run that overlaps it: a run the
        // block-summed map carried across a gap it could not see is two
        // elements' worth of edge, and each gets its share. A run overlapping
        // no stretch was never backed by the pixels, and goes.
        var groups: [Group] = []
        for stretch in stretches {
            let span = CGFloat(stretch.lowerBound)...CGFloat(stretch.upperBound)
            let clipped: [Run] = runs.compactMap { run in
                let start = max(run.start, span.lowerBound)
                let end = min(run.end, span.upperBound)
                guard end >= start else { return nil }
                return Run(edge: run.edge, start: start, end: end)
            }
            if !clipped.isEmpty { groups.append(Group(runs: clipped, span: span)) }
        }
        return groups
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
    /// One boundary followed along the guide: the readings, sample by sample,
    /// that each landed within `runMergeTolerance` of the running mean of the
    /// ones before them. A sample that offers nothing near the mean ends the
    /// track: a boundary a person can see does not blink.
    struct Track {
        var sum: Double = 0
        var count = 0
        var first: Int
        var last: Int
        var members: [(sample: Int, index: Int)] = []
        var mean: Double { sum / Double(max(count, 1)) }
    }

    /// Every boundary in `samples`, chained along the guide. Each sample's
    /// readings extend the nearest open track they are close enough to, one
    /// reading per track, and anything left over opens a track of its own.
    static func tracks(in samples: [[EdgeCandidate]]) -> [Track] {
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
        return closed
    }

    /// The readings that belong to an ELEMENT, by hysteresis: a boundary counts
    /// if it reaches `elementStrength` ANYWHERE along its own track, and once
    /// it has, its fainter readings count too, down to `weakElementFraction`
    /// of its boldest. A boundary that never gets there is dropped whole.
    ///
    /// Strength is measured against the boldest reading in each SAMPLE, so a
    /// pale boundary fades wherever something bolder shares its window. Judging
    /// each reading alone therefore chops a pale edge into fragments, and a
    /// short fragment sitting inside a longer reading a few pixels away is
    /// exactly what `borderFlanks` throws out as the inner side of a border.
    /// That is how a guide down a row of toggles came to call the switched-off
    /// one 2 px out: its track is barely there against white, so its fragments
    /// were discarded in favour of the bolder edge of the knob just inside it,
    /// and the guide measured the knob.
    ///
    /// The rescue is deliberately relative to the boundary's own boldest
    /// reading rather than a flat floor. A real edge dips to a good fraction of
    /// itself; the ghost the block-summed map trails past a line of text is a
    /// small fraction of the line it echoes, so it stays out.
    static func elementTracks(in samples: [[EdgeCandidate]],
                              elementStrength: Double) -> [[EdgeCandidate]] {
        var keep = samples.map { [Bool](repeating: false, count: $0.count) }
        for track in tracks(in: samples) {
            let strengths = track.members.map { samples[$0.sample][$0.index].strength }
            guard let peak = strengths.max(), peak >= elementStrength else { continue }
            let faintest = min(elementStrength, peak * weakElementFraction)
            for (member, strength) in zip(track.members, strengths) where strength >= faintest {
                keep[member.sample][member.index] = true
            }
        }
        return samples.indices.map { i in
            samples[i].enumerated().filter { keep[i][$0.offset] }.map(\.element)
        }
    }

    static func borderFlanks(in samples: [[EdgeCandidate]]) -> [Set<Int>] {
        let closed = tracks(in: samples)
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
