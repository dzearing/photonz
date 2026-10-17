import CoreGraphics
import Foundation

/// Finds the UI element under a probe point in a screenshot, for the Measure
/// tool's **Size** mode and the gap it reads in **Gap** mode (Next release).
///
/// A screenshot has no semantic UI tree, so "the element under the pointer" is
/// read from the picture. Two signals, and both are needed:
///
/// - `EdgeMap` says WHERE the boundaries are. It is block-summed, so it finds
///   them cheaply and to the pixel in the direction that matters, but it cannot
///   say how far along a boundary runs.
/// - `LumaField` says HOW FAR each one reaches (`EdgeRun`). That is what
///   separates the hairline under one settings row from the card border a few
///   pixels wider, which is exactly the difference between reading a row and
///   grabbing the whole card.
///
/// So an element is built from a PAIR of horizontal boundaries — one above the
/// pointer, one below — whose runs agree with each other. Agreement is the whole
/// trick: a button's top and bottom borders start and stop together, while a
/// glyph's baseline stops where the word does and never lines up with the
/// button's top. The agreed run gives the element's width; nearby vertical
/// boundaries sharpen its left and right, since a border reads more precisely
/// than the end of a run. Sides are placed at the OUTER boundary estimate — half
/// way between the gradient peak and the first clean background pixel outside
/// it — so a button measures the width a spec would quote, not the width of its
/// inside.
///
/// Every rung that survives is offered, innermost first, so Size mode's `[` and
/// `]` can shrink and grow the pick when the guess is not the element the person
/// meant. Nothing readable is a quiet miss (`nil`) — never a wrong box.
///
/// Both signals come from one analysis pass, so both arrive together: until the
/// screenshot has been analyzed there is no edge map and no brightness field and
/// detection is quiet, which is the same gate snapping already waits on.
public enum ElementBounds {

    /// How far from the probe (image px) each directional walk reaches before
    /// giving up.
    public static let defaultMaxRadius: Double = 600

    /// How many nested candidates the ladder is capped at. Long enough to reach
    /// a card from inside a button, short enough that `[` / `]` stays a handful
    /// of presses rather than an endless scroll.
    public static let candidateLimit = 10

    /// Two candidates this close on every side are the same element read twice,
    /// so the outer one is dropped. Sized so that every press of `]` visibly
    /// changes the pick rather than nudging it.
    private static let candidateMinGrowth: Double = 12

    /// How bold a boundary has to be, relative to the boldest one its query
    /// window offers, to be treated as a possible EDGE OF AN ELEMENT. Deliberately
    /// low: over a settings row's own label the boldest thing in the window is a
    /// glyph, and a threshold tuned to throw glyphs out throws the row out with
    /// them. What actually rules text out is geometry — a word's cap-height band
    /// is too short to be an element, and its baseline's run does not agree with
    /// the border above it.
    private static let elementFraction: Double = 0.2

    /// Two boundaries closer together than this are one boundary read twice (the
    /// two flanks of an antialiased border), so only the bolder one can define a
    /// side. Sharpening a side (below) still sees both, which is how a switch's
    /// outer edge is preferred over its knob four pixels inside it.
    private static let pairSeparation: Double = 5

    /// How far inside an element the pointer has to be for the pick to be that
    /// element. Standing within a pixel or two of a boundary is not pointing at
    /// what it encloses: it is what makes the middle of a switch read as the
    /// switch rather than as the knob whose edge happens to pass under the
    /// pointer.
    private static let probeMargin: Double = 4

    /// How much of the longer run the two runs must SHARE to be called the same
    /// element's width. A card's rounded top reads a little wider than the
    /// divider beneath it, so the test is a proportion rather than a pixel
    /// count; a glyph's baseline shares a small fraction of the border above it
    /// and is thrown out.
    private static let runAgreement: Double = 0.85

    /// How close a vertical boundary must be to the end of a run to be taken as
    /// that side's true edge.
    private static let sideSnap: Double = 12

    /// Smallest element worth offering, in IMAGE px, when the caller does not
    /// say. 20 is ten logical points on the 2x captures this tool is pointed at:
    /// small enough for a checkbox, big enough that the band between a word's
    /// cap height and its baseline — which looks exactly like a wide, short box
    /// — is not offered as something to measure.
    public static let defaultMinElement: Double = 20

    /// Half-width of the perpendicular query window centered on the probe —
    /// the same locality snapping's fallback window uses, so hover accepts the
    /// same edges a foot drag would land on.
    public static let defaultSpanRadius: Double = 32

    /// The element rect at `point`: the innermost candidate, or nil when no
    /// candidate is readable (including the not-yet-computed `EdgeMap.empty`).
    public static func detect(at point: CGPoint, in edges: EdgeMap,
                              luma: LumaField,
                              maxRadius: Double = defaultMaxRadius,
                              spanRadius: Double = defaultSpanRadius,
                              minElement: Double = defaultMinElement,
                              textGap: Double = TextLineBounds.defaultGap,
                              readsShapes: Bool = false) -> CGRect? {
        candidates(at: point, in: edges, luma: luma, maxRadius: maxRadius,
                   spanRadius: spanRadius, minElement: minElement, textGap: textGap,
                   limit: 1, readsShapes: readsShapes).first
    }

    /// How much taller than its words a rung may be and still be a CONTROL
    /// wearing them as its label. A button is two to three times its label's
    /// ink height, a tab item four; a dialog with a centered title is ten
    /// times it and more.
    private static let captionHeightRatio: Double = 5

    /// The nested ladder of element rects around `point`, innermost first, each
    /// containing the one before it. Empty when nothing is readable.
    ///
    /// A line of text under the pointer (`TextLineBounds`) is the first rung,
    /// so a heading or a row label reads as an element and `]` climbs from it
    /// to the row and the card. The one exception is a control's own label:
    /// words centered in a rung not much taller than they are (a button, a
    /// tab, a chip) belong to that rung, and pointing at them means it. A
    /// readout that flickered between a word and its button as the pointer
    /// crossed the letters would be worse than one that is quietly wrong.
    /// `textGap` is the clean stretch that ends a line, in image px.
    ///
    /// `readsShapes` adds the things a pair of straight edges cannot see
    /// (`ShapeBounds`): round avatars, icons, badges, photos and the stacks
    /// they sit in. Next's Size mode turns it on; everything else reads as it
    /// always did, which keeps Current's readout placement exactly as it was.
    public static func candidates(at point: CGPoint, in edges: EdgeMap,
                                  luma: LumaField,
                                  maxRadius: Double = defaultMaxRadius,
                                  spanRadius: Double = defaultSpanRadius,
                                  minElement: Double = defaultMinElement,
                                  textGap: Double = TextLineBounds.defaultGap,
                                  limit: Int = candidateLimit,
                                  readsShapes: Bool = false) -> [CGRect] {
        let found = ladder(at: point, in: edges, luma: luma, maxRadius: maxRadius,
                           spanRadius: spanRadius, minElement: minElement, textGap: textGap,
                           limit: limit, readsShapes: readsShapes)
        return Array(found.rungs.dropFirst(found.start).prefix(limit))
    }

    /// The ladder Size mode steps along, and the rung it starts on.
    ///
    /// Usually that is the first, innermost rung. On a control's own label
    /// (the words on a button, a pill, a tab) it is the control, and the
    /// label is the rung below it: pointing at the words means the button,
    /// and `[` still reaches the words. Everything below `start` is what `[`
    /// steps down to; `candidates` hands back the ladder from `start` on.
    public struct Ladder: Equatable, Sendable {
        public var rungs: [CGRect]
        public var start: Int

        public init(rungs: [CGRect], start: Int = 0) {
            self.rungs = rungs
            self.start = rungs.isEmpty ? 0 : min(max(0, start), rungs.count - 1)
        }

        /// The rung `level` steps from the start (negative steps down), held
        /// to the ladder's ends.
        public func rung(_ level: Int) -> CGRect? {
            guard !rungs.isEmpty else { return nil }
            return rungs[min(max(start + level, 0), rungs.count - 1)]
        }
    }

    public static func ladder(at point: CGPoint, in edges: EdgeMap,
                              luma: LumaField,
                              maxRadius: Double = defaultMaxRadius,
                              spanRadius: Double = defaultSpanRadius,
                              minElement: Double = defaultMinElement,
                              textGap: Double = TextLineBounds.defaultGap,
                              limit: Int = candidateLimit,
                              readsShapes: Bool = false) -> Ladder {
        guard !edges.isEmpty, !luma.isEmpty, maxRadius > 0, limit > 0 else { return Ladder(rungs: []) }
        var shape = readsShapes
            ? ShapeBounds.shape(at: point, in: luma, minElement: minElement, maxRadius: maxRadius)
            : nil
        let text = TextLineBounds.detect(at: point, in: luma, gap: textGap,
                                         minElement: minElement, maxRadius: maxRadius)
        // Buttons, pills and cards: big ones, gradient ones, ones with a glow,
        // ones the page's own brightness in another colour (`ObjectBounds`).
        // A letter or a word read as an object is the line reader's business.
        var objects: [CGRect] = []
        if readsShapes {
            let read = ObjectBounds.reading(at: point, in: luma, minElement: minElement)
            let slack = CGFloat(probeSlack)
            objects = read.objects.filter { object in
                text.map { !$0.insetBy(dx: -slack, dy: -slack).contains(object) } ?? true
            }
            if let inner = objects.first {
                if let found = shape, same(found.bounds, inner) {
                    // Two readings of one thing: a spec quotes the outer edge.
                    if inner.insetBy(dx: -1, dy: -1).contains(found.bounds) { shape?.bounds = inner }
                    objects.removeFirst()
                } else if shape == nil {
                    shape = ShapeBounds.Reading(bounds: inner, onBody: true, background: read.background)
                    objects.removeFirst()
                }
            }
        }
        var found = baseLadder(at: point, shape: shape, text: text, in: edges, luma: luma,
                               maxRadius: maxRadius, spanRadius: spanRadius, minElement: minElement,
                               limit: limit)
        for object in objects {
            // A pair reading of the same thing that stops where its round ends
            // begin is the object read short: the object takes its place.
            if let short = found.rungs.firstIndex(where: { readsShort($0, object) }) {
                found.rungs[short] = object
                continue
            }
            let rungs = insert(object, into: found.rungs)
            if rungs.count > found.rungs.count,
               let at = rungs.firstIndex(of: object), at <= found.start, found.start < found.rungs.count {
                found.start += 1
            }
            found.rungs = rungs
        }
        if readsShapes {
            // Out past the start, a rung whose edge runs through a line of
            // print is a pairing of one thing's edge with a line through
            // another's words, not an object: the pill's top with the middle
            // of the small print under it. `]` never steps there.
            let kept = found.rungs.enumerated().filter { index, rung in
                index <= found.start || !cutsALine(rung, in: luma, textGap: textGap,
                                                   minElement: minElement, maxRadius: maxRadius)
            }
            found = Ladder(rungs: kept.map(\.element), start: found.start)
        }
        return Ladder(rungs: Array(found.rungs.prefix(found.start + limit)), start: found.start)
    }

    /// Whether a line of text crosses one of `rung`'s edges: read just inside
    /// each side, a line that reaches into the rung and out past it.
    private static func cutsALine(_ rung: CGRect, in luma: LumaField, textGap: Double,
                                  minElement: Double, maxRadius: Double) -> Bool {
        let slack = CGFloat(probeSlack)
        let inside = rung.insetBy(dx: 2, dy: 2)
        guard inside.width > 0, inside.height > 0 else { return false }
        var probes: [CGPoint] = []
        for f in [0.1, 0.3, 0.5, 0.7, 0.9] {
            let x = inside.minX + CGFloat(f) * inside.width
            probes.append(CGPoint(x: x, y: inside.minY))
            probes.append(CGPoint(x: x, y: inside.maxY))
        }
        for f in [0.25, 0.5, 0.75] {
            let y = inside.minY + CGFloat(f) * inside.height
            probes.append(CGPoint(x: inside.minX, y: y))
            probes.append(CGPoint(x: inside.maxX, y: y))
        }
        var seen: [CGRect] = []
        for probe in probes {
            guard let line = TextLineBounds.detect(at: probe, in: luma, gap: textGap,
                                                   minElement: minElement, maxRadius: maxRadius),
                  !seen.contains(line) else { continue }
            seen.append(line)
            let shared = line.intersection(rung)
            guard !shared.isNull, shared.width > slack, shared.height > slack else { continue }
            if !rung.insetBy(dx: -slack, dy: -slack).contains(line) { return true }
        }
        return false
    }

    private static func baseLadder(at point: CGPoint, shape: ShapeBounds.Reading?, text: CGRect?,
                                   in edges: EdgeMap, luma: LumaField, maxRadius: Double,
                                   spanRadius: Double, minElement: Double, limit: Int) -> Ladder {
        var shape = shape
        // With a shape in hand the whole pair ladder is needed, to see which
        // of its rungs hold the shape and which are pieces of its picture.
        let pairLimit = shape == nil ? limit : candidateLimit
        if let found = shape, found.onBody, let text,
           text.insetBy(dx: CGFloat(-probeSlack), dy: CGFloat(-probeSlack)).contains(found.bounds) {
            // The line reader ran through a shape. An avatar or an icon beside
            // its label is a picture with words next to it, and pointing at it
            // means the picture; a letter is just a letter of the line.
            guard isPicture(found, besideTextIn: text, luma: luma) else {
                shape = nil
                return textLadder(text, at: point, shape: nil, in: edges, luma: luma,
                                  maxRadius: maxRadius, spanRadius: spanRadius,
                                  minElement: minElement, limit: limit)
            }
            let rungs = pairRungs(at: point, in: edges, luma: luma, maxRadius: maxRadius,
                                  spanRadius: spanRadius, minElement: minElement,
                                  limit: candidateLimit)
            let ladder = shaped(found, rungs, luma: luma)
            return Ladder(rungs: Array(insert(text, into: ladder).prefix(limit)))
        }
        guard let text else {
            let rungs = pairRungs(at: point, in: edges, luma: luma, maxRadius: maxRadius,
                                  spanRadius: spanRadius, minElement: minElement, limit: pairLimit)
            return Ladder(rungs: Array(shaped(shape, rungs, luma: luma).prefix(limit)))
        }
        return textLadder(text, at: point, shape: shape, in: edges, luma: luma,
                          maxRadius: maxRadius, spanRadius: spanRadius,
                          minElement: minElement, limit: limit)
    }

    /// The ladder when a line of text is under the pointer: the line first,
    /// unless a control is wearing it as its label, when the control is where
    /// the ladder starts and the line is one `[` below it.
    private static func textLadder(_ text: CGRect, at point: CGPoint, shape: ShapeBounds.Reading?,
                                   in edges: EdgeMap, luma: LumaField, maxRadius: Double,
                                   spanRadius: Double, minElement: Double, limit: Int) -> Ladder {
        let slack = CGFloat(probeSlack)
        func holds(_ rung: CGRect) -> Bool { rung.insetBy(dx: -slack, dy: -slack).contains(text) }
        let pairLimit = shape == nil ? limit : candidateLimit
        var rungs = pairRungs(at: point, in: edges, luma: luma, maxRadius: maxRadius,
                              spanRadius: spanRadius, minElement: minElement, limit: pairLimit)
        // A rung that does not hold the whole line is a fragment of it (one
        // letter's top and baseline can agree with each other), not a
        // container. When that is all a short ladder found, the full ladder is
        // needed to see the rung that does hold the words, since that one
        // decides whether they are its caption.
        if let first = rungs.first, !holds(first), pairLimit < candidateLimit {
            rungs = pairRungs(at: point, in: edges, luma: luma, maxRadius: maxRadius,
                              spanRadius: spanRadius, minElement: minElement,
                              limit: candidateLimit)
        }
        rungs = shaped(shape, rungs, luma: luma)
        let containing = rungs.filter(holds)
        if let control = containing.first, hugs(control, text) {
            if rungs.first == control, grows(control, beyond: text) {
                return Ladder(rungs: [text] + Array(rungs.prefix(limit)), start: 1)
            }
            return Ladder(rungs: Array(rungs.prefix(limit)))
        }
        var ladder = [text]
        for rect in containing where ladder.count < limit && grows(rect, beyond: ladder.last) {
            ladder.append(rect)
        }
        return Ladder(rungs: ladder)
    }

    // MARK: Shapes on the ladder

    /// How close two readings of one thing have to be, side by side, to be
    /// the same reading. The pair ladder's number wins a tie, so nothing it
    /// already measured moves.
    private static let sameReading: CGFloat = 3

    /// How bold (0...255 from the background) anything in the band between a
    /// rung and a shape around it may be for that band to be a shadow or a
    /// glow, which belongs to no spec.
    private static let haloContrast = 51

    /// The pair ladder with the shape under the pointer put where it belongs.
    ///
    /// On the shape's own paint the shape is the first rung, and pair rungs
    /// INSIDE it are dropped: two straight edges across a photo are a piece of
    /// the photo, not a thing to measure. Two exceptions keep today's numbers:
    /// a first rung that already reads the shape stays as it is, and a shape
    /// that is only a first rung plus a soft band round it is that rung and its
    /// shadow. A shape the pointer is in a HOLE of (a white button inside a
    /// filled banner) is a container, slotted in after what it holds. A stack
    /// the shape belongs to comes right after it, one `]` away.
    private static func shaped(_ shape: ShapeBounds.Reading?, _ rungs: [CGRect],
                               luma: LumaField) -> [CGRect] {
        guard let shape else { return rungs }
        let b = shape.bounds
        guard shape.onBody else { return insert(b, into: rungs) }
        let group = ShapeBounds.group(of: shape, in: luma)
        if let first = rungs.first {
            if same(first, b) {
                // Two readings of one thing. A spec quotes the outer edge of a
                // border, and the shape reader reads to the last pixel that
                // differs from the page, so the outer of the two wins.
                var rungs = rungs
                if b.insetBy(dx: -1, dy: -1).contains(first) { rungs[0] = b }
                return group.map { insert($0, into: rungs) } ?? rungs
            }
            if b.insetBy(dx: -sameReading, dy: -sameReading).contains(first),
               isHalo(b, around: first, luma: luma, background: shape.background) {
                return rungs
            }
        }
        var ladder = [b]
        if let group, grows(group, beyond: b) { ladder.append(group) }
        for rung in rungs where grows(rung, beyond: ladder.last) { ladder.append(rung) }
        return ladder
    }

    /// Whether `rung` is `object` read short: inside it, the same along one
    /// axis, and nine tenths of it or more along the other. Two straight
    /// edges across a pill stop where its round ends begin.
    private static func readsShort(_ rung: CGRect, _ object: CGRect) -> Bool {
        guard object.insetBy(dx: -1, dy: -1).contains(rung), !same(rung, object) else { return false }
        let rows = abs(rung.minY - object.minY) <= sameReading && abs(rung.maxY - object.maxY) <= sameReading
        let columns = abs(rung.minX - object.minX) <= sameReading && abs(rung.maxX - object.maxX) <= sameReading
        return (rows && rung.width >= 0.9 * object.width) || (columns && rung.height >= 0.9 * object.height)
    }

    private static func same(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= sameReading && abs(a.minY - b.minY) <= sameReading
            && abs(a.maxX - b.maxX) <= sameReading && abs(a.maxY - b.maxY) <= sameReading
    }

    /// `rect` slotted into a nested ladder: after every rung it holds, before
    /// every rung that holds it. A ladder it would not nest in (a rung crosses
    /// it) or already reads it is handed back untouched.
    private static func insert(_ rect: CGRect, into rungs: [CGRect]) -> [CGRect] {
        let slack = CGFloat(probeSlack)
        guard !rungs.contains(where: { same($0, rect) }) else { return rungs }
        var out: [CGRect] = []
        var placed = false
        for rung in rungs {
            if !placed, rect.insetBy(dx: -slack, dy: -slack).contains(rung) {
                out.append(rung)
                continue
            }
            if !placed {
                guard grows(rung, beyond: rect), grows(rect, beyond: out.last) else { return rungs }
                out.append(rect)
                placed = true
            }
            out.append(rung)
        }
        if !placed {
            guard grows(rect, beyond: out.last) else { return rungs }
            out.append(rect)
        }
        return out
    }

    /// Whether everything in `shape` outside `inner` is soft: a drop shadow or
    /// a glow round the element `inner` already reads.
    private static func isHalo(_ shape: CGRect, around inner: CGRect, luma: LumaField,
                               background: Int) -> Bool {
        let x0 = Int(shape.minX), x1 = Int(shape.maxX), y0 = Int(shape.minY), y1 = Int(shape.maxY)
        guard x0 < x1, y0 < y1 else { return false }
        // The rung's own border can sit a pixel or two outside what it reads.
        let own = inner.insetBy(dx: -sameReading, dy: -sameReading)
        var strongest = 0
        for y in max(0, y0)..<min(luma.height, y1) {
            for x in max(0, x0)..<min(luma.width, x1)
            where !own.contains(CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5)) {
                strongest = max(strongest, abs(Int(luma.samples[y * luma.width + x]) - background))
                if strongest >= haloContrast { return false }
            }
        }
        return true
    }

    /// Whether a shape lying inside a line of text is a picture beside the
    /// words (an avatar by a name) rather than one of the letters: the rest of
    /// the line's ink is clearly shorter than it is.
    private static func isPicture(_ shape: ShapeBounds.Reading, besideTextIn text: CGRect,
                                  luma: LumaField) -> Bool {
        let b = shape.bounds
        let floor = Int((TextLineBounds.inkFloor * 255).rounded())
        var top = Int.max, bottom = -1
        let y0 = max(0, Int(text.minY)), y1 = min(luma.height, Int(text.maxY))
        for x in max(0, Int(text.minX))..<min(luma.width, Int(text.maxX)) {
            guard Double(x) < Double(b.minX) - 2 || Double(x) > Double(b.maxX) + 2 else { continue }
            for y in y0..<y1
            where abs(Int(luma.samples[y * luma.width + x]) - shape.background) >= floor {
                top = min(top, y)
                bottom = max(bottom, y)
            }
        }
        guard bottom >= top else { return true }
        return Double(bottom - top + 1) <= 0.75 * Double(b.height)
    }

    /// Whether `rung` is a control wearing `text` as its label: the words are
    /// centered in it and it is not much taller than they are.
    private static func hugs(_ rung: CGRect, _ text: CGRect) -> Bool {
        guard Double(rung.height) <= captionHeightRatio * Double(text.height) else { return false }
        let leftPad = Double(text.minX - rung.minX)
        let rightPad = Double(rung.maxX - text.maxX)
        // A fifth of the width: a button with an icon on one side of its
        // words (a download arrow) pushes the words that far off centre.
        let tolerance = max(4, 0.2 * Double(rung.width))
        return abs(leftPad - rightPad) <= tolerance
    }

    /// The ladder read from pairs of boundaries alone, innermost first.
    private static func pairRungs(at point: CGPoint, in edges: EdgeMap,
                                  luma: LumaField, maxRadius: Double, spanRadius: Double,
                                  minElement: Double, limit: Int) -> [CGRect] {
        let px = Double(point.x), py = Double(point.y)
        let sides = sides(at: point, in: edges, maxRadius: maxRadius, spanRadius: spanRadius)
        let above = pairable(sides[0])
        let below = pairable(sides[1])
        guard !above.isEmpty, !below.isEmpty else { return [] }

        // Every top paired with every bottom, shortest pair first, so the rungs
        // come out smallest first. It has to be every pair: walking outward one
        // boundary at a time misses elements whenever something is painted
        // between the probe and one of their edges. Under a settings row's
        // label the glyph edges above the probe are nearer than the row's top,
        // so a walk keeps stepping the top up through them and, being nearer,
        // steps the bottom past the row's own bottom before the top ever gets
        // there: the pair that IS the row is never tried, and the row goes
        // missing exactly where a caliper's foot lands under its text. Trying
        // every pair is cheap — the run walks are memoized per row, and a
        // pair whose runs disagree is rejected before anything else is done —
        // and a rung is only ever a pair whose runs agree, never a cross
        // product of everything in range.
        var pairs: [(top: Side, bottom: Side)] = []
        for top in above {
            for bottom in below where bottom.bound - top.bound >= minElement {
                pairs.append((top, bottom))
            }
        }
        pairs.sort { a, b in
            let ha = a.bottom.bound - a.top.bound, hb = b.bottom.bound - b.top.bound
            return ha != hb ? ha < hb : a.top.distance < b.top.distance
        }
        var found: [CGRect] = []
        var runs: [Int: ClosedRange<Int>?] = [:]
        for pair in pairs {
            if let rect = rung(top: pair.top, bottom: pair.bottom, px: px, py: py,
                               left: sides[2], right: sides[3], luma: luma,
                               minElement: minElement, runs: &runs),
               grows(rect, beyond: found.last) {
                found.append(rect)
                if found.count >= limit { break }
            }
        }
        return found
    }

    /// One rung: the element bounded above by `top` and below by `bottom`, or nil
    /// when those two boundaries do not describe one.
    ///
    /// Width comes from the stretch the two boundaries BOTH cover. They have to
    /// agree at each end, which is what rules out a pairing of a border with a
    /// baseline. `runs` memoizes the walk per row, since growing the pair
    /// revisits the same boundary many times.
    private static func rung(top: Side, bottom: Side, px: Double, py: Double,
                             left: [Side], right: [Side], luma: LumaField,
                             minElement: Double,
                             runs: inout [Int: ClosedRange<Int>?]) -> CGRect? {
        guard bottom.bound - top.bound >= minElement else { return nil }

        func run(_ side: Side) -> ClosedRange<Int>? {
            let row = Int(side.peak.rounded())
            if let cached = runs[row] { return cached }
            let walked = EdgeRun.horizontal(row: row, seedX: Int(px.rounded()), in: luma)
            runs[row] = walked
            return walked
        }
        guard let topRun = run(top), let bottomRun = run(bottom) else { return nil }
        let shared = Double(min(topRun.upperBound, bottomRun.upperBound)
                            - max(topRun.lowerBound, bottomRun.lowerBound))
        let longest = Double(max(topRun.count, bottomRun.count))
        guard shared >= runAgreement * longest else { return nil }
        var lower = Double(max(topRun.lowerBound, bottomRun.lowerBound))
        // A run's last covered pixel is the element's last pixel; the boundary
        // itself is the far side of it.
        var upper = Double(min(topRun.upperBound, bottomRun.upperBound)) + 1
        lower = snapped(lower, to: left, outward: true) ?? lower
        upper = snapped(upper, to: right, outward: false) ?? upper

        guard upper - lower >= minElement,
              lower + probeMargin <= px, px <= upper - probeMargin,
              top.bound + probeMargin <= py, py <= bottom.bound - probeMargin else { return nil }
        return CGRect(x: lower, y: top.bound,
                      width: upper - lower, height: bottom.bound - top.bound)
    }

    /// The boundaries on one side that may DEFINE an element edge: bold enough
    /// to be structure, and thinned so the two flanks of one antialiased border
    /// cannot be mistaken for the top and bottom of something 3 px tall.
    private static func pairable(_ side: [Side]) -> [Side] {
        var kept: [Side] = []
        for candidate in side.filter({ $0.strength >= elementFraction })
            .sorted(by: { $0.strength > $1.strength }) {
            if kept.contains(where: { abs($0.peak - candidate.peak) < pairSeparation }) { continue }
            kept.append(candidate)
        }
        return kept.sorted { $0.distance < $1.distance }
    }

    /// A run's end refined to a real vertical boundary sitting on it.
    ///
    /// Only ever OUTWARD. The run is a floor on how far the element reaches —
    /// the boundary was still readable there — so a vertical border a few pixels
    /// further out is the element's true edge (a run stops just inside a rounded
    /// corner, and a switch's knob sits just inside the switch). One that lies
    /// INSIDE the run is something painted on the element, and pulling in to it
    /// would make the readout wobble as the pointer moved.
    private static func snapped(_ end: Double, to side: [Side], outward: Bool) -> Double? {
        let hits = side.filter { candidate in
            abs(candidate.peak - end) <= sideSnap
                && (outward ? candidate.bound <= end + 1 : candidate.bound >= end - 1)
        }
        guard !hits.isEmpty else { return nil }
        return outward ? hits.map(\.bound).min() : hits.map(\.bound).max()
    }

    /// How far past an element's edge the neighbour probe stands. Far enough
    /// to be properly inside whatever is touching it (`probeMargin` is 4), close
    /// enough that it reads the row against this one rather than something
    /// across the page.
    public static let neighborProbeReach: Double = 12

    /// What is immediately AROUND `rect`: the row under a row, the button beside
    /// a button. Size mode hands these to the readout planner, because a number
    /// parked in the next row down reads as that row's number even when the
    /// pixels underneath it happen to be blank.
    ///
    /// One probe just past the middle of each side, at each distance in
    /// `reaches`, innermost pick only. Two distances is the usual call: one
    /// close enough to find what is touching the element, one as far out as the
    /// number itself will travel, so a button 30 px away is still seen.
    /// Anything that swallows the element — its card, the window behind it — is
    /// dropped: a readout cannot steer out of a box it is standing inside, and
    /// pretending otherwise would only push the number somewhere arbitrary.
    public static func neighbors(of rect: CGRect, in edges: EdgeMap, luma: LumaField,
                                 maxRadius: Double = defaultMaxRadius,
                                 spanRadius: Double = defaultSpanRadius,
                                 minElement: Double = defaultMinElement,
                                 textGap: Double = TextLineBounds.defaultGap,
                                 reaches: [Double] = [neighborProbeReach],
                                 readsShapes: Bool = false) -> [CGRect] {
        guard !edges.isEmpty, !luma.isEmpty, rect.width > 0, rect.height > 0 else { return [] }
        let slack = CGFloat(probeSlack)
        var found: [CGRect] = []
        for reach in reaches {
            probe(rect, reach: CGFloat(reach), slack: slack, into: &found, in: edges, luma: luma,
                  maxRadius: maxRadius, spanRadius: spanRadius, minElement: minElement,
                  textGap: textGap, readsShapes: readsShapes)
        }
        return found
    }

    /// The four probes at one distance, appending whatever is new to `found`.
    private static func probe(_ rect: CGRect, reach r: CGFloat, slack: CGFloat,
                              into found: inout [CGRect], in edges: EdgeMap, luma: LumaField,
                              maxRadius: Double, spanRadius: Double, minElement: Double,
                              textGap: Double, readsShapes: Bool) {
        // Each probe carries the test for what a neighbour on THAT side looks
        // like: it has to begin where the element ends. A box that reaches back
        // across the element is a band read off the picture, not the row next
        // door, and steering a number around something invisible is worse than
        // leaving it where it belongs.
        let probes: [(point: CGPoint, beyond: (CGRect) -> Bool)] = [
            (CGPoint(x: rect.midX, y: rect.minY - r), { $0.maxY <= rect.minY + slack }),
            (CGPoint(x: rect.midX, y: rect.maxY + r), { $0.minY >= rect.maxY - slack }),
            (CGPoint(x: rect.minX - r, y: rect.midY), { $0.maxX <= rect.minX + slack }),
            (CGPoint(x: rect.maxX + r, y: rect.midY), { $0.minX >= rect.maxX - slack }),
        ]
        for probe in probes {
            guard probe.point.x >= 0, probe.point.y >= 0,
                  Double(probe.point.x) < Double(edges.width),
                  Double(probe.point.y) < Double(edges.height),
                  let hit = detect(at: probe.point, in: edges, luma: luma, maxRadius: maxRadius,
                                   spanRadius: spanRadius, minElement: minElement,
                                   textGap: textGap, readsShapes: readsShapes),
                  probe.beyond(hit),
                  !found.contains(where: { $0.insetBy(dx: -slack, dy: -slack).contains(hit) })
            else { continue }
            found.append(hit)
        }
    }

    /// How far a foot may sit from an element's painted edge and still count as
    /// standing on it. A snapped foot lands on the clean background hugging the
    /// element, which the antialiasing ramp or a drop shadow can put several
    /// pixels past the boundary detection names.
    public static let footEdgeTolerance: Double = 8

    /// What a hand-drawn caliper is ABOUT: the elements its two feet landed on.
    ///
    /// A foot carries only a point, so this reads the element back off the
    /// picture the way Size mode reads its neighbours: one probe just past the
    /// foot on each side, along the measuring axis. A hit counts only when its
    /// facing edge is at the foot (a click in the middle of a button is not a
    /// click on its edge), and a hit the caliper runs INSIDE (a card's edge to
    /// a button within it) is dropped, because a number cannot steer out of a
    /// box it is standing in. Measuring one element edge to edge by hand gives
    /// that element once, exactly what Size mode would have handed over. When
    /// two bordered elements face each other across the caliper, the strip of
    /// whitespace between them can read as a band of its own and come back too;
    /// that band is the gap being measured, and keeping the number off it is
    /// what Gap mode's head reach already does, so it is left in.
    ///
    /// Placement-time work only: two probes per foot, never per mouse move.
    public static func subjects(from start: CGPoint, to end: CGPoint, mode: MeasureMode,
                                in edges: EdgeMap, luma: LumaField,
                                maxRadius: Double = defaultMaxRadius,
                                spanRadius: Double = defaultSpanRadius,
                                minElement: Double = defaultMinElement,
                                textGap: Double = TextLineBounds.defaultGap) -> [CGRect] {
        guard !edges.isEmpty, !luma.isEmpty else { return [] }
        let horizontal = mode == .horizontal
        func along(_ p: CGPoint) -> CGFloat { horizontal ? p.x : p.y }
        func alongMin(_ r: CGRect) -> CGFloat { horizontal ? r.minX : r.minY }
        func alongMax(_ r: CGRect) -> CGFloat { horizontal ? r.maxX : r.maxY }
        let tolerance = CGFloat(footEdgeTolerance)
        let reach = CGFloat(neighborProbeReach)
        let slack = CGFloat(probeSlack)
        var found: [CGRect] = []
        for (foot, other) in [(start, end), (end, start)] {
            let a = along(foot), b = along(other)
            for sign: CGFloat in [-1, 1] {
                let probe = horizontal ? CGPoint(x: foot.x + sign * reach, y: foot.y)
                                       : CGPoint(x: foot.x, y: foot.y + sign * reach)
                guard probe.x >= 0, probe.y >= 0,
                      Double(probe.x) < Double(edges.width),
                      Double(probe.y) < Double(edges.height),
                      let hit = detect(at: probe, in: edges, luma: luma, maxRadius: maxRadius,
                                       spanRadius: spanRadius, minElement: minElement,
                                       textGap: textGap)
                else { continue }
                // The face of the hit nearest the foot has to BE the foot.
                let facing = sign < 0 ? alongMax(hit) : alongMin(hit)
                guard abs(facing - a) <= tolerance else { continue }
                // The caliper may end at the hit's far edge (its own size) but
                // not inside it: that is a container, not a subject.
                let far = sign < 0 ? alongMin(hit) : alongMax(hit)
                let runsInside = sign < 0 ? (b < a && far < b - tolerance)
                                          : (b > a && far > b + tolerance)
                guard !runsInside else { continue }
                guard !found.contains(where: { $0.insetBy(dx: -slack, dy: -slack).contains(hit) })
                else { continue }
                found.append(hit)
            }
        }
        return found
    }

    /// How far a neighbour may bleed back over the element before it stops
    /// being a neighbour. A painted border has two flanks and detection can
    /// name either, so a couple of pixels of slop is the picture, not a nest.
    private static let probeSlack: Double = 3

    /// Whether a rung belongs on the ladder after `previous`: it has to CONTAIN
    /// what came before (a ladder that narrows on the way out is a shuffle, not
    /// a ladder) and be enough bigger on some side to be worth a keypress.
    private static func grows(_ rect: CGRect, beyond previous: CGRect?) -> Bool {
        guard let previous else { return true }
        guard rect.insetBy(dx: -1, dy: -1).contains(previous) else { return false }
        return Double(previous.minX - rect.minX) >= candidateMinGrowth
            || Double(previous.minY - rect.minY) >= candidateMinGrowth
            || Double(rect.maxX - previous.maxX) >= candidateMinGrowth
            || Double(rect.maxY - previous.maxY) >= candidateMinGrowth
    }

    /// One accepted boundary on one side of the probe.
    private struct Side {
        /// Distance from the probe to the gradient peak.
        var distance: Double
        /// The gradient peak — the middle of the transition ramp.
        var peak: Double
        /// Where the ELEMENT's edge is taken to be: the outer flank of the
        /// boundary pixel. The peak names the pixel the transition sits in, so
        /// the element's edge is half a pixel further out — but no further,
        /// because a drop shadow's clean-background landing can be six pixels
        /// out and would inflate the card by three.
        var bound: Double
        /// The clean background position on the PROBE's side — what a gap
        /// measures to.
        var landing: Double
        var strength: Double
    }

    /// The four sides' candidates, in the fixed order minY, maxY, minX, maxX,
    /// each nearest first.
    private static func sides(at point: CGPoint, in edges: EdgeMap,
                              maxRadius: Double, spanRadius: Double) -> [[Side]] {
        guard !edges.isEmpty, maxRadius > 0 else { return [[], [], [], []] }
        let px = Double(point.x), py = Double(point.y)
        // One query per axis serves both of that axis's directions.
        let horizontal = edges.horizontalEdges(inXRange: (px - spanRadius)...(px + spanRadius))
        let vertical = edges.verticalEdges(inYRange: (py - spanRadius)...(py + spanRadius))
        return [
            sideLandings(horizontal, probe: py, lowerSide: true, maxRadius: maxRadius),
            sideLandings(horizontal, probe: py, lowerSide: false, maxRadius: maxRadius),
            sideLandings(vertical, probe: px, lowerSide: true, maxRadius: maxRadius),
            sideLandings(vertical, probe: px, lowerSide: false, maxRadius: maxRadius),
        ]
    }

    /// Every accepted candidate on one side (`lowerSide` = positions at or below
    /// the probe coordinate) within `maxRadius`, nearest first. The probe sits on
    /// the element side of the boundary, so above the probe the clean background
    /// OUTSIDE the element is the before-side landing and below it the
    /// after-side.
    private static func sideLandings(_ candidates: [EdgeCandidate], probe: Double,
                                     lowerSide: Bool, maxRadius: Double) -> [Side] {
        candidates
            .filter { lowerSide ? $0.position <= probe : $0.position > probe }
            .map { candidate in
                let outer = lowerSide ? candidate.edgeBefore : candidate.edgeAfter
                let flank = min(max(outer - candidate.position, -0.5), 0.5)
                return Side(distance: abs(probe - candidate.position),
                            peak: candidate.position,
                            bound: candidate.position + flank,
                            landing: lowerSide ? candidate.edgeAfter : candidate.edgeBefore,
                            strength: candidate.strength)
            }
            .filter { $0.distance <= maxRadius }
            .sorted { $0.distance < $1.distance }
    }
}
