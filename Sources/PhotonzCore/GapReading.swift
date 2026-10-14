import CoreGraphics
import Foundation

/// Gap mode: the space the pointer is in, measured between the nearest
/// distinct things that face each other ACROSS it.
///
/// The reading walks out from the pointer along its own row and its own
/// column, so a side only counts when it actually runs across the pointer's
/// position: the line above has to pass over the pointer, the button to the
/// right has to stand level with it. That is the whole difference from reading
/// edges out of a window around the pointer, where the side of a letter in the
/// next line down, a few pixels off, could pair with the side of the letter
/// beside it and win as "the gap" (the user, 2026-10-13, hovering between two
/// lines of a heading).
///
/// Text is read as whole lines (`TextLineBounds`): a walk that meets ink, or
/// passes between two letters of a line, takes the line's ink box as the side,
/// so the space between two lines reads from the bottom of the upper line's
/// ink, descenders included, to the top of the lower line's, ascenders
/// included, wherever along them the pointer is. That is the box a spec quotes
/// for a line of text, and the one Size mode already shows for it.
///
/// Each side is graded: a whole line of text or anything wider than a letter
/// stroke is a distinct ELEMENT; a single stroke or a speck is not. The axis
/// whose two sides are both elements wins, and only then the shorter span.
extension ElementBounds {

    /// How big a step in brightness, over two pixels, makes a boundary. Small
    /// enough for a hairline divider on a light page, big enough that a
    /// button's gradient fill or a soft shadow never reads as an edge.
    static let gapStepFloor = 12

    /// How many lines of text one reading may read. Each costs a fraction
    /// of a millisecond, and a walk past a column of labels would otherwise
    /// read every one of them.
    static let gapLineLookups = 16

    /// How far along a line of text, in text gaps, it is read on each side of
    /// where the walk met it: 400 px on a 2x capture, the whole of any label
    /// and most of a paragraph line.
    static let gapLineReach: Double = 25

    /// The tallest line Gap mode reads as text, in visible gaps: 320 px on a
    /// 2x capture, a hero heading.
    static let gapTallestLine: Double = 20

    /// The gap under `point`: the two facing sides of whatever sits on either
    /// side of it, across one axis. Nil when no axis has a side both ways.
    ///
    /// A gap needs only ONE axis: the space between two stacked cards has a
    /// top and a bottom and no sides at all. When both axes read, the axis
    /// whose sides are both distinct elements wins; between equals, the
    /// shorter span, because the tighter one is what a person means by "the
    /// gap". It is measured to the clean background hugging each side, since
    /// what is being measured is the whitespace, not the elements.
    ///
    /// `drawn` is the document's own boxes (`LayerElements.boxes`), whose edges
    /// are KNOWN rather than read out of the picture. On each of the four sides
    /// the nearer boundary wins, whichever it came from: the space between two
    /// rectangles you drew reads on a canvas with no picture in it at all, and
    /// the space between a drawn box and a button in the screenshot reads
    /// across both. `textGap` is the clean stretch that ends a line of text, in
    /// image px (`TextLineBounds`).
    public static func gap(at point: CGPoint, luma: LumaField,
                           drawn: [CGRect] = [],
                           textGap: Double = TextLineBounds.defaultGap,
                           maxRadius: Double = defaultMaxRadius) -> GapMeasurement? {
        let px = Double(point.x), py = Double(point.y)
        let read = gapSides(at: point, in: luma, textGap: textGap, maxRadius: maxRadius)
        let made = drawnLandings(at: point, in: drawn, maxRadius: maxRadius)
        // The fixed side order everywhere here: minY, maxY, minX, maxX.
        let sides: [GapSide?] = (0..<4).map { i in
            let lower = i % 2 == 0
            switch (read[i], made[i]) {
            case let (r?, m?):
                let madeIsNearer = lower ? m >= r.landing : m <= r.landing
                return madeIsNearer ? GapSide(landing: m, isElement: true) : r
            case let (r?, nil): return r
            case let (nil, m?): return GapSide(landing: m, isElement: true)
            case (nil, nil): return nil
            }
        }
        var options: [(gap: GapMeasurement, elements: Bool)] = []
        if let minY = sides[0], let maxY = sides[1],
           maxY.landing > minY.landing, minY.landing <= py, py <= maxY.landing {
            options.append((GapMeasurement(axis: .vertical,
                                           start: CGPoint(x: point.x, y: minY.landing),
                                           end: CGPoint(x: point.x, y: maxY.landing)),
                            minY.isElement && maxY.isElement))
        }
        if let minX = sides[2], let maxX = sides[3],
           maxX.landing > minX.landing, minX.landing <= px, px <= maxX.landing {
            options.append((GapMeasurement(axis: .horizontal,
                                           start: CGPoint(x: minX.landing, y: point.y),
                                           end: CGPoint(x: maxX.landing, y: point.y)),
                            minX.isElement && maxX.isElement))
        }
        // Distinct elements first; the vertical reading wins an exact tie, as
        // it always has.
        return options.min { a, b in
            if a.elements != b.elements { return a.elements }
            return a.gap.length < b.gap.length
        }?.gap
    }

    /// One side of a gap: where its whitespace ends, and whether what ends it
    /// is a distinct element rather than a letter stroke.
    struct GapSide: Equatable {
        var landing: Double
        var isElement: Bool
    }

    /// The four sides read off the picture, in the order minY, maxY, minX, maxX.
    static func gapSides(at point: CGPoint, in luma: LumaField,
                         textGap: Double, maxRadius: Double) -> [GapSide?] {
        guard !luma.isEmpty, maxRadius > 0 else { return [nil, nil, nil, nil] }
        let x = Int(floor(Double(point.x))), y = Int(floor(Double(point.y)))
        guard x >= 0, y >= 0, x < luma.width, y < luma.height else { return [nil, nil, nil, nil] }
        let walker = GapWalker(luma: luma, x: x, y: y, point: point,
                               textGap: max(1, textGap), reach: Int(maxRadius.rounded()))
        return [walker.walk(vertical: true, step: -1), walker.walk(vertical: true, step: 1),
                walker.walk(vertical: false, step: -1), walker.walk(vertical: false, step: 1)]
    }

    /// The nearest DRAWN edge on each of the four sides of the probe, in the
    /// order minY, maxY, minX, maxX.
    ///
    /// A box's horizontal edges count only where the box actually passes over
    /// or under the pointer, and its vertical edges only where it passes beside
    /// it: the same rule the picture's walk keeps. A box the pointer is INSIDE
    /// offers its own two edges, so pointing into a rectangle in Gap mode
    /// measures the room inside it, exactly as it does over a card in a
    /// screenshot.
    static func drawnLandings(at point: CGPoint, in drawn: [CGRect],
                              maxRadius: Double) -> [Double?] {
        guard !drawn.isEmpty else { return [nil, nil, nil, nil] }
        let px = Double(point.x), py = Double(point.y)
        var sides: [Double?] = [nil, nil, nil, nil]
        func offer(_ edge: Double, probe: Double, lower: Int, upper: Int) {
            guard abs(edge - probe) <= maxRadius else { return }
            let side = edge <= probe ? lower : upper
            if let current = sides[side] {
                sides[side] = side == lower ? max(current, edge) : min(current, edge)
            } else {
                sides[side] = edge
            }
        }
        for box in drawn.map({ $0.standardized }) {
            if px >= Double(box.minX), px <= Double(box.maxX) {
                offer(Double(box.minY), probe: py, lower: 0, upper: 1)
                offer(Double(box.maxY), probe: py, lower: 0, upper: 1)
            }
            if py >= Double(box.minY), py <= Double(box.maxY) {
                offer(Double(box.minX), probe: px, lower: 2, upper: 3)
                offer(Double(box.maxX), probe: px, lower: 2, upper: 3)
            }
        }
        return sides
    }
}

/// One pointer's four walks over the brightness field. A class so the four
/// walks share the lines they have read: the line above the pointer is often
/// the line beside it too, and reading a line is the expensive part.
private final class GapWalker {
    let luma: LumaField
    let x: Int, y: Int
    let point: CGPoint
    let textGap: Double
    let reach: Int
    /// What the pointer is standing on: the background every side is a
    /// departure from.
    let background: Int
    /// Every line of text read so far, and the seeds that read as no line.
    private var lines: [CGRect] = []
    private var misses: [CGPoint] = []
    private var lookups = 0

    init(luma: LumaField, x: Int, y: Int, point: CGPoint, textGap: Double, reach: Int) {
        self.luma = luma
        self.x = x
        self.y = y
        self.point = point
        self.textGap = textGap
        self.reach = reach
        background = Int(luma.samples[y * luma.width + x])
    }

    @inline(__always) func sample(_ a: Int, _ b: Int) -> Int {
        Int(luma.samples[b * luma.width + a])
    }

    /// The nearest side along one walk: up or down the pointer's column
    /// (`vertical`), or left or right along its row. `step` is -1 toward
    /// the origin, +1 away from it.
    func walk(vertical: Bool, step: Int) -> ElementBounds.GapSide? {
        let start = vertical ? y : x
        let across = vertical ? x : y
        let limit = vertical ? luma.height : luma.width
        let crossLimit = vertical ? luma.width : luma.height
        let floor = ElementBounds.gapStepFloor
        let inkFloor = Int((TextLineBounds.inkFloor * 255).rounded())
        let window = max(1, Int(textGap.rounded()))
        let base = background
        @inline(__always) func at(_ along: Int, _ cross: Int) -> Int {
            vertical ? sample(cross, along) : sample(along, cross)
        }
        var quietUntil = start
        for k in 1...max(1, reach) {
            let pos = start + step * k
            guard pos >= 0, pos < limit else { return nil }
            let behind = start + step * max(0, k - 2)
            if abs(at(pos, across) - at(behind, across)) >= floor {
                // Something stands right in the pointer's line. A letter of a
                // line of text stands for its whole line; anything else is
                // its own side.
                if let line = line(at: pos, cross: across, vertical: vertical, step: step) {
                    return line
                }
                let landing = Double(step < 0 ? pos + 1 : pos)
                return ElementBounds.GapSide(landing: landing,
                                             isElement: body(at: pos + step, across: across,
                                                             vertical: vertical, base: base) >= textGap)
            }
            // Nothing in the pointer's own line, but ink close beside it may be
            // a line of text the pointer is passing between two letters of.
            guard step * (pos - quietUntil) > 0 else { continue }
            var nearest: Int?
            for offset in 0...window {
                for cross in [across - offset, across + offset] where cross >= 0 && cross < crossLimit {
                    if abs(at(pos, cross) - base) >= inkFloor { nearest = cross; break }
                }
                if nearest != nil { break }
            }
            guard let seed = nearest else { continue }
            if let line = line(at: pos, cross: seed, vertical: vertical, step: step) {
                return line
            }
            // Not a line that stands across the pointer: let the walk pass
            // half a text gap before asking again.
            quietUntil = pos + step * max(1, window / 2)
        }
        return nil
    }

    /// The line of text at (`pos`, `cross`) as this walk's side, when there
    /// is one and it stands across the pointer: it runs past the pointer on
    /// the other axis, lies wholly on this walk's side of it, and its facing
    /// edge is no further out than where the walk met it (a button's label,
    /// inside the button the walk just met, is not the button's side).
    private func line(at pos: Int, cross: Int, vertical: Bool, step: Int) -> ElementBounds.GapSide? {
        let seed = vertical ? CGPoint(x: cross, y: pos) : CGPoint(x: pos, y: cross)
        guard let box = read(seed) else { return nil }
        let p = Double(vertical ? point.y : point.x)
        let q = Double(vertical ? point.x : point.y)
        let lo = Double(vertical ? box.minX : box.minY), hi = Double(vertical ? box.maxX : box.maxY)
        let near = Double(step < 0 ? (vertical ? box.maxY : box.maxX) : (vertical ? box.minY : box.minX))
        let met = Double(step < 0 ? pos + 1 : pos)
        let standsAcross = lo <= q && q <= hi
        let onThisSide = step < 0 ? near <= p : near > p
        let notBeyond = step < 0 ? near >= met - 1 : near <= met + 1
        guard standsAcross, onThisSide, notBeyond else { return nil }
        return ElementBounds.GapSide(landing: near, isElement: true)
    }

    /// The line of text through `seed`, read once per pointer.
    private func read(_ seed: CGPoint) -> CGRect? {
        if let known = lines.first(where: { $0.insetBy(dx: -1, dy: -1).contains(seed) }) {
            return known
        }
        if misses.contains(where: { abs($0.x - seed.x) <= 2 && abs($0.y - seed.y) <= 2 }) {
            return nil
        }
        guard lookups < ElementBounds.gapLineLookups else { return nil }
        lookups += 1
        guard let box = TextLineBounds.detect(at: seed, in: luma, gap: textGap,
                                              minElement: 1.25 * textGap,
                                              maxRadius: ElementBounds.gapLineReach * textGap,
                                              tallestInGaps: ElementBounds.gapTallestLine,
                                              background: UInt8(clamping: background)) else {
            misses.append(seed)
            return nil
        }
        lines.append(box)
        return box
    }

    /// How wide the thing the walk met is, a step inside it: the run of pixels
    /// along the other axis that stand off the background. A card's border or
    /// a button runs on; a letter stroke stops within a few pixels.
    private func body(at along: Int, across: Int, vertical: Bool, base: Int) -> Double {
        let limit = vertical ? luma.height : luma.width
        let crossLimit = vertical ? luma.width : luma.height
        guard along >= 0, along < limit else { return 0 }
        let floor = ElementBounds.gapStepFloor
        @inline(__always) func off(_ cross: Int) -> Bool {
            let v = vertical ? sample(cross, along) : sample(along, cross)
            return abs(v - base) >= floor
        }
        guard off(across) else { return 0 }
        let cap = Int(textGap.rounded()) + 1
        var run = 1
        var c = across - 1
        while c >= 0, off(c), run <= cap { run += 1; c -= 1 }
        c = across + 1
        while c < crossLimit, off(c), run <= cap { run += 1; c += 1 }
        return Double(run)
    }
}

/// One gap reading: the two facing edges of the elements on either side of the
/// click, and the axis they face across. Rendered by the SAME caliper every
/// other mode produces: a gap has no look of its own.
public struct GapMeasurement: Equatable, Sendable {
    public var axis: MeasureMode
    public var start: CGPoint
    public var end: CGPoint

    public init(axis: MeasureMode, start: CGPoint, end: CGPoint) {
        self.axis = axis
        self.start = start
        self.end = end
    }

    /// The gap's width in document pixels.
    public var length: CGFloat {
        axis == .horizontal ? abs(end.x - start.x) : abs(end.y - start.y)
    }
}
