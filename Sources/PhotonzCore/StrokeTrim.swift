import CoreGraphics
import Foundation

// Strokes that draw themselves on (task
// `title-backgrounds-move-gradients-grain-and-the-r`).
//
// A line, an arrow's shaft or a path's outline can be drawn only part of the
// way along: from `start` to `end`, each a fraction of the whole stroke. Keying
// the end from nothing to all of it draws the line on, the way After Effects'
// Trim Paths and an SVG stroke's dash offset both do. Like every other look it
// is read at the moment drawn: the rasterizer strokes the trimmed path, and the
// line in the document is the one you drew.

/// How much of a stroke is drawn: from `start` to `end` along it, each 0 to 1.
public struct StrokeTrim: Hashable, Codable, Sendable {
    public var start: Double
    public var end: Double

    public init(start: Double = 0, end: Double = 1) {
        self.start = min(max(start, 0), 1)
        self.end = min(max(end, 0), 1)
    }

    /// The whole stroke: nothing trimmed.
    public static let whole = StrokeTrim()

    /// Whether this draws the whole stroke, so there is nothing to do.
    public var isWhole: Bool { start <= 0.0001 && end >= 0.9999 }

    /// Whether this draws nothing at all.
    public var isEmpty: Bool { end - start <= 0.0001 }

    /// How finely a curve is walked to measure it: plenty for a stroke, whose
    /// end is the only place the approximation could show.
    static let curveSteps = 48

    /// How long a path is, along every piece of it.
    public static func length(of path: CGPath) -> CGFloat {
        segments(of: path).reduce(0) { $0 + $1.length }
    }

    /// The part of `path` this trim keeps, as straight runs fine enough that a
    /// curve still reads as a curve. The whole path, untouched, when nothing
    /// is trimmed; an empty path when nothing is left.
    public func applied(to path: CGPath) -> CGPath {
        guard !isWhole else { return path }
        let out = CGMutablePath()
        guard !isEmpty else { return out }
        let pieces = Self.segments(of: path)
        let total = pieces.reduce(0) { $0 + $1.length }
        guard total > 0 else { return out }
        let from = CGFloat(start) * total, to = CGFloat(end) * total
        var walked: CGFloat = 0
        var open = false
        var lastSubpath = -1
        for piece in pieces {
            let a = walked, b = walked + piece.length
            walked = b
            // A new subpath (a second ring, or the next figure) lifts the pen.
            if piece.subpath != lastSubpath { open = false; lastSubpath = piece.subpath }
            guard b > from, a < to, piece.length > 0 else { continue }
            let t0 = max(0, (from - a) / piece.length), t1 = min(1, (to - a) / piece.length)
            let p0 = piece.point(at: t0), p1 = piece.point(at: t1)
            if !open {
                out.move(to: p0)
                open = true
            }
            out.addLine(to: p1)
        }
        return out
    }

    /// One straight run of a path, and which figure of it the run is in.
    struct Segment {
        var from: CGPoint
        var to: CGPoint
        var subpath: Int
        var length: CGFloat { hypot(to.x - from.x, to.y - from.y) }
        func point(at t: CGFloat) -> CGPoint {
            CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
        }
    }

    /// The path walked as straight runs, curves cut into `curveSteps` each.
    static func segments(of path: CGPath) -> [Segment] {
        var runs: [Segment] = []
        var current = CGPoint.zero
        var figureStart = CGPoint.zero
        var figure = -1
        func line(to point: CGPoint) {
            runs.append(Segment(from: current, to: point, subpath: figure))
            current = point
        }
        path.applyWithBlock { element in
            let kind = element.pointee.type
            let points = element.pointee.points
            switch kind {
            case .moveToPoint:
                figure += 1
                current = points[0]
                figureStart = current
            case .addLineToPoint:
                line(to: points[0])
            case .addQuadCurveToPoint:
                let start = current, control = points[0], end = points[1]
                for step in 1...curveSteps {
                    let t = CGFloat(step) / CGFloat(curveSteps), u = 1 - t
                    line(to: CGPoint(x: u * u * start.x + 2 * u * t * control.x + t * t * end.x,
                                     y: u * u * start.y + 2 * u * t * control.y + t * t * end.y))
                }
            case .addCurveToPoint:
                let start = current, c1 = points[0], c2 = points[1], end = points[2]
                for step in 1...curveSteps {
                    let t = CGFloat(step) / CGFloat(curveSteps), u = 1 - t
                    let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
                    line(to: CGPoint(x: a * start.x + b * c1.x + c * c2.x + d * end.x,
                                     y: a * start.y + b * c1.y + c * c2.y + d * end.y))
                }
            case .closeSubpath:
                if current != figureStart { line(to: figureStart) }
            @unknown default:
                break
            }
        }
        return runs
    }
}

extension Layer {

    /// How much of this layer's line is drawn, where it has a line of its own
    /// with some width to it: the whole of it when nothing has trimmed it. Nil
    /// on anything without one.
    var strokeTrimForMotion: StrokeTrim? {
        if let path { return path.strokeWidth > 0 ? (path.trim ?? .whole) : nil }
        guard let annotation, annotation.strokeWidth > 0 else { return nil }
        return annotation.trim ?? .whole
    }

    /// Sets how much of the line is drawn. A whole line holds no trim at all,
    /// so a line drawn all the way on is exactly the line it was.
    mutating func setStrokeTrimForMotion(_ trim: StrokeTrim) {
        let kept: StrokeTrim? = trim.isWhole ? nil : trim
        if var path {
            path.trim = kept
            content = .path(path)
        } else if var annotation {
            annotation.trim = kept
            content = .annotation(annotation)
        }
    }
}
