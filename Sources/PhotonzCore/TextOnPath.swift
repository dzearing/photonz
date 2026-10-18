import CoreGraphics
import Foundation

// A title's words set along a drawn curve (task
// `a-title-s-words-can-follow-a-curved-path`,
// `docs/design/mocks/pages/video-motion.html`, "Text on a path": "A headline
// flows along any vector path. The path is editable, so the type reflows as you
// reshape the curve.").
//
// **The text owns its curve.** Photoshop's type on a path, Illustrator's and
// SVG's `textPath` all work this way: the path stops being a shape with a line
// of its own and becomes the line the letters sit on. So putting words on a
// path moves the path's points INTO the text, and reshaping the curve is
// reshaping the text: the same points and levers a path shows, on the text
// layer, with nothing else on the canvas to keep in step.
//
// Every letter sits with its baseline on the curve and is turned to the way the
// curve runs under its middle, the way SVG sets a `textPath`. Letters that run
// off the end of an open curve are not drawn (SVG drops them too); round a
// closed one they carry on.
//
// The maths lives here, in the pure core, given each letter's width. The
// renderer measures the letters with CoreText and draws each one where this
// says (`TextRasterizer.rasterizeOnPath`).

/// The curve a text's words are set along, and where along it they start.
public struct TextOnPath: Hashable, Codable, Sendable {
    /// The curve, in the text layer's own top-left coordinates, as a path's
    /// points and levers. Its line and fill are never drawn: only the points
    /// matter, and keeping a whole `PathContent` is what lets every tool that
    /// reshapes a path reshape this one.
    public var guide: PathContent
    /// Where the first letter starts, as a percent of the curve's length.
    /// Below nought the first words are still on their way and are not drawn
    /// yet; keyed from there to nought, the words travel on along the curve.
    public var startPercent: Double

    public init(guide: PathContent, startPercent: Double = 0) {
        self.guide = guide
        self.startPercent = startPercent
    }

    /// The range a person may set Start in. A whole length either way is
    /// enough to bring every word in from off one end or send it off the other.
    public static let startRange: ClosedRange<Double> = -100...100

    /// How far along the curve the first letter starts, in points.
    public func startDistance(along walk: PathWalk) -> CGFloat {
        CGFloat(startPercent / 100) * walk.length
    }

    /// Words on a curve are one line: the curve IS the line. A break becomes a
    /// space, so "Ship it" over "faster" reads "Ship it faster" along it.
    public static func lineOfWords(_ string: String) -> String {
        var line = ""
        var lastWasBreak = false
        for character in string {
            if character.isNewline {
                if !lastWasBreak { line.append(" ") }
                lastWasBreak = true
            } else {
                line.append(character)
                lastWasBreak = false
            }
        }
        return line
    }

    /// How far a letter can reach from the curve it sits on, at `fontSize`:
    /// a cap above it, a descender below it, and a turned letter's corner past
    /// either. The picture of words on a curve is that much bigger than the
    /// curve's own box on every side (`Layer.contentOutset`).
    public static func reach(fontSize: CGFloat) -> CGFloat {
        (max(0, fontSize) * 1.5).rounded(.up)
    }
}

extension TextContent {

    /// The same text with its curve, or nil for words set in a box.
    public var isOnPath: Bool { onPath != nil }
}

// MARK: - Walking along a curve

/// A curve measured along its length, so a distance along it can be turned
/// into a place and a heading.
///
/// It reads the path's first ring only: words follow one line, and a shape
/// with a hole in it has no single line to follow.
public struct PathWalk: Sendable {

    /// One measured step: which run it is on, at what parameter, and how far
    /// along the whole curve that is.
    private struct Mark: Sendable {
        let run: Int
        let t: CGFloat
        let distance: CGFloat
        let point: CGPoint
    }

    private let runs: [PathSegment]
    private let marks: [Mark]
    /// Whether the curve joins back to its start, so a distance past its end
    /// comes round again.
    public let isClosed: Bool
    /// How long the curve is, in the points its anchors are stated in.
    public let length: CGFloat

    /// How many straight pieces each run is measured in. Forty-eight keeps a
    /// letter within a hundredth of a point of where it belongs on the most
    /// lopsided run a lever can make, and costs nothing next to drawing them.
    public static let piecesPerRun = 48

    public init(_ guide: PathContent, piecesPerRun: Int = PathWalk.piecesPerRun) {
        let firstRing = guide.ringRanges.first.map { guide.anchors[$0] } ?? []
        var ring = guide
        ring.anchors = Array(firstRing)
        ring.ringStarts = []
        runs = ring.segments
        isClosed = guide.isClosed
        var marks: [Mark] = []
        var total: CGFloat = 0
        let pieces = max(1, piecesPerRun)
        for (index, run) in runs.enumerated() {
            var last = run.start
            if marks.isEmpty { marks.append(Mark(run: index, t: 0, distance: 0, point: last)) }
            for step in 1...pieces {
                let t = CGFloat(step) / CGFloat(pieces)
                let next = Self.point(on: run, at: t)
                total += hypot(next.x - last.x, next.y - last.y)
                marks.append(Mark(run: index, t: t, distance: total, point: next))
                last = next
            }
        }
        self.marks = marks
        length = total
    }

    /// Where the curve is `distance` along it, and which way it is heading
    /// there, as an angle in radians in the layer's top-left space (nought is
    /// rightwards, a quarter turn is straight down). Nil off either end of an
    /// open curve, and for a curve with no length.
    public func place(atDistance distance: CGFloat) -> (point: CGPoint, angle: CGFloat)? {
        guard length > 0, distance.isFinite else { return nil }
        var wanted = distance
        if isClosed {
            wanted = wanted.truncatingRemainder(dividingBy: length)
            if wanted < 0 { wanted += length }
        } else if wanted < 0 || wanted > length {
            return nil
        }
        // The first mark at or past the distance, found by halving.
        var low = 0, high = marks.count - 1
        while low < high {
            let middle = (low + high) / 2
            if marks[middle].distance < wanted { low = middle + 1 } else { high = middle }
        }
        let after = marks[low]
        let before = low > 0 ? marks[low - 1] : after
        let run: Int
        let t: CGFloat
        if after.run == before.run, after.distance > before.distance {
            let share = (wanted - before.distance) / (after.distance - before.distance)
            run = after.run
            t = before.t + (after.t - before.t) * share
        } else {
            run = after.run
            t = after.t
        }
        let segment = runs[run]
        let point = Self.point(on: segment, at: t)
        var heading = segment.heading(at: t)
        if hypot(heading.dx, heading.dy) < 1e-9 {
            heading = CGVector(dx: after.point.x - before.point.x, dy: after.point.y - before.point.y)
        }
        return (point, atan2(heading.dy, heading.dx))
    }

    /// A run's point at `t`. A straight run is read as the line it is, so
    /// equal steps of `t` are equal distances along it: as a cubic with its
    /// levers on its own ends it bunches up at either end.
    private static func point(on run: PathSegment, at t: CGFloat) -> CGPoint {
        guard run.isStraight else { return run.point(at: t) }
        return CGPoint(x: run.start.x + (run.end.x - run.start.x) * t,
                       y: run.start.y + (run.end.y - run.start.y) * t)
    }
}

extension PathSegment {

    /// The way the run is going at `t`: its derivative, which is the tangent.
    /// A straight run goes from its start to its end everywhere along it.
    public func heading(at t: CGFloat) -> CGVector {
        if isStraight { return CGVector(dx: end.x - start.x, dy: end.y - start.y) }
        let u = 1 - t
        func d(_ p0: CGFloat, _ p1: CGFloat, _ p2: CGFloat, _ p3: CGFloat) -> CGFloat {
            3 * u * u * (p1 - p0) + 6 * u * t * (p2 - p1) + 3 * t * t * (p3 - p2)
        }
        return CGVector(dx: d(start.x, control1.x, control2.x, end.x),
                        dy: d(start.y, control1.y, control2.y, end.y))
    }
}

// MARK: - Setting the letters

/// One letter set on the curve: where its baseline starts, how wide it is,
/// and how far it is turned.
public struct PathLetter: Hashable, Sendable {
    /// The left end of the letter's baseline, in the layer's own coordinates.
    public let origin: CGPoint
    /// How far the letter advances along its baseline.
    public let width: CGFloat
    /// How far the letter is turned, in radians, clockwise on screen.
    public let angle: CGFloat

    public init(origin: CGPoint, width: CGFloat, angle: CGFloat) {
        self.origin = origin
        self.width = width
        self.angle = angle
    }

    /// The middle of its baseline: the point that sits on the curve.
    public var middle: CGPoint {
        CGPoint(x: origin.x + cos(angle) * width / 2, y: origin.y + sin(angle) * width / 2)
    }
}

public enum TextOnPathLayout {

    /// One letter as a straight line of type would set it: how far along the
    /// line it starts and how far it advances.
    public struct Glyph: Hashable, Sendable {
        public let x: CGFloat
        public let width: CGFloat
        public init(x: CGFloat, width: CGFloat) {
            self.x = x
            self.width = width
        }
    }

    /// Where each letter goes on the curve, nil for one off the end of it.
    ///
    /// Each letter's MIDDLE is carried along the curve by the distance it had
    /// from the start of the line, and the letter is turned to the way the
    /// curve runs there, with its baseline across the curve at that point.
    /// That is the SVG `textPath` rule, and it is what keeps letters on a
    /// tight bend from overlapping their neighbours or opening gaps.
    public static func letters(_ glyphs: [Glyph], on walk: PathWalk,
                               startDistance: CGFloat) -> [PathLetter?] {
        glyphs.map { glyph in
            let middle = startDistance + glyph.x + glyph.width / 2
            guard let place = walk.place(atDistance: middle) else { return nil }
            let half = glyph.width / 2
            return PathLetter(origin: CGPoint(x: place.point.x - cos(place.angle) * half,
                                              y: place.point.y - sin(place.angle) * half),
                              width: glyph.width, angle: place.angle)
        }
    }
}

// MARK: - Reading how well the letters follow

/// How closely a set of letters follows a curve, read independently of how
/// they were placed: for each letter, the nearest point of the curve to the
/// middle of its baseline, the curve's own direction there, and how far off
/// both the letter is. Words set flat across an arc, or all turned by one
/// angle, read badly; words set on the curve read close to nought.
public struct TextOnPathReading: Hashable, Sendable {
    /// The largest difference between a letter's turn and the curve's
    /// direction under it, in degrees.
    public let worstTurnDegrees: Double
    /// The largest distance from a letter's baseline middle to the curve.
    public let worstBaselineDistance: Double
    /// How many letters were read.
    public let letterCount: Int

    public init(letters: [PathLetter], along guide: PathContent) {
        let runs = guide.segments
        var worstTurn = 0.0
        var worstDistance = 0.0
        for letter in letters {
            let target = letter.middle
            var best: (distance: CGFloat, run: PathSegment, t: CGFloat)?
            for run in runs {
                // A coarse look along the run, then a fine one round the best.
                var bestT: CGFloat = 0
                var bestD = CGFloat.infinity
                for step in 0...200 {
                    let t = CGFloat(step) / 200
                    let p = run.point(at: t)
                    let d = hypot(p.x - target.x, p.y - target.y)
                    if d < bestD { bestD = d; bestT = t }
                }
                for step in -50...50 {
                    let t = min(max(bestT + CGFloat(step) / 10_000, 0), 1)
                    let p = run.point(at: t)
                    let d = hypot(p.x - target.x, p.y - target.y)
                    if d < bestD { bestD = d; bestT = t }
                }
                if best == nil || bestD < (best?.distance ?? .infinity) { best = (bestD, run, bestT) }
            }
            guard let best else { continue }
            let heading = best.run.heading(at: best.t)
            let along = atan2(heading.dy, heading.dx)
            var difference = Double(letter.angle - along) * 180 / .pi
            difference = (difference + 540).truncatingRemainder(dividingBy: 360) - 180
            worstTurn = max(worstTurn, abs(difference))
            worstDistance = max(worstDistance, Double(best.distance))
        }
        worstTurnDegrees = worstTurn
        worstBaselineDistance = worstDistance
        letterCount = letters.count
    }
}
