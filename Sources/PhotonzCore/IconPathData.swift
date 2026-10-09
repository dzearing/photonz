import CoreGraphics
import Foundation

/// Reading the outline of an icon as the design system writes it: the `d`
/// attribute of an SVG `<path>` (`docs/design/mocks/shared/icons.mjs`).
///
/// The starter Button carries a leading icon, and the icons the variants mock
/// offers (Sparkle, Wand, Swatch, Layers, Brush) are written once, in that
/// file, as path data. Copying the numbers across verbatim is what keeps the
/// glyph on the canvas the same glyph the mock draws, rather than a lookalike
/// somebody traced by hand.
///
/// It reads the commands those icons use and no more: move, line, horizontal,
/// vertical, cubic and elliptical arc, absolute and relative, and close. An
/// arc becomes cubics, a quarter turn at most each, because a path in this
/// app is anchors and handles and nothing else.
public enum IconPathData {

    /// One run of the outline: the anchors it passes through, and whether it
    /// joins back to where it started.
    public struct Run: Hashable, Sendable {
        public var anchors: [PathAnchor]
        public var isClosed: Bool
    }

    /// Every run in `data`, in the order it draws them. Anything it cannot
    /// read ends the reading there rather than guessing: an icon with a
    /// stroke missing is a bug somebody can see, a stroke invented is not.
    public static func runs(_ data: String) -> [Run] {
        var reader = Reader(data)
        var runs: [Run] = []
        var anchors: [PathAnchor] = []
        var current = CGPoint.zero
        var start = CGPoint.zero
        var command: Character = "M"

        func finish(closed: Bool) {
            defer { anchors = [] }
            guard anchors.count >= 2 else { return }
            var points = anchors
            // A closed run whose last anchor lands back on its first carries the
            // curve INTO the first anchor on that anchor, so the join is not
            // drawn as a second, zero-length corner.
            if closed, points.count > 2,
               let last = points.last, let first = points.first,
               hypot(last.point.x - first.point.x, last.point.y - first.point.y) < 0.001 {
                points[0].handleIn = last.handleIn
                points.removeLast()
            }
            runs.append(Run(anchors: points, isClosed: closed))
        }

        func lineTo(_ point: CGPoint) {
            if anchors.isEmpty { anchors.append(PathAnchor(point: current)) }
            anchors.append(PathAnchor(point: point))
            current = point
        }

        func curveTo(_ c1: CGPoint, _ c2: CGPoint, _ end: CGPoint) {
            if anchors.isEmpty { anchors.append(PathAnchor(point: current)) }
            let last = anchors.count - 1
            anchors[last].handleOut = CGPoint(x: c1.x - current.x, y: c1.y - current.y)
            anchors.append(PathAnchor(point: end,
                                      handleIn: CGPoint(x: c2.x - end.x, y: c2.y - end.y)))
            current = end
        }

        while let next = reader.command(continuing: command) {
            command = next
            let relative = command.isLowercase
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
            }
            switch command.lowercased().first {
            case "m":
                guard let x = reader.number(), let y = reader.number() else { return runs }
                finish(closed: false)
                current = point(x, y)
                start = current
                anchors = [PathAnchor(point: current)]
                // Pairs after a move are lines, as SVG reads them.
                command = relative ? "l" : "L"
            case "l":
                guard let x = reader.number(), let y = reader.number() else { return runs }
                lineTo(point(x, y))
            case "h":
                guard let x = reader.number() else { return runs }
                lineTo(CGPoint(x: relative ? current.x + x : x, y: current.y))
            case "v":
                guard let y = reader.number() else { return runs }
                lineTo(CGPoint(x: current.x, y: relative ? current.y + y : y))
            case "c":
                guard let x1 = reader.number(), let y1 = reader.number(),
                      let x2 = reader.number(), let y2 = reader.number(),
                      let x = reader.number(), let y = reader.number() else { return runs }
                curveTo(point(x1, y1), point(x2, y2), point(x, y))
            case "a":
                guard let rx = reader.number(), let ry = reader.number(),
                      let rotation = reader.number(), let large = reader.flag(),
                      let sweep = reader.flag(),
                      let x = reader.number(), let y = reader.number() else { return runs }
                let end = point(x, y)
                for curve in arc(from: current, to: end, radii: CGSize(width: rx, height: ry),
                                 rotation: rotation, large: large, sweep: sweep) {
                    curveTo(curve.0, curve.1, curve.2)
                }
                if anchors.last?.point != end { lineTo(end) }
            case "z":
                // A close makes the run a closed one, ending where it began.
                if let first = anchors.first?.point, let last = anchors.last?.point,
                   hypot(last.x - first.x, last.y - first.y) >= 0.001 {
                    // The straight side back to the start is the close itself.
                }
                finish(closed: true)
                current = start
                anchors = []
            default:
                return runs
            }
        }
        finish(closed: false)
        return runs
    }

    /// A circle as a closed run of four quarter curves, which is how the icons'
    /// solid dots are drawn.
    public static func circle(center: CGPoint, radius r: CGFloat) -> Run {
        let k = r * 0.5522847498
        let points = [CGPoint(x: center.x, y: center.y - r), CGPoint(x: center.x + r, y: center.y),
                      CGPoint(x: center.x, y: center.y + r), CGPoint(x: center.x - r, y: center.y)]
        let tangents = [CGPoint(x: k, y: 0), CGPoint(x: 0, y: k),
                        CGPoint(x: -k, y: 0), CGPoint(x: 0, y: -k)]
        let anchors = zip(points, tangents).map { point, out in
            PathAnchor(point: point, handleIn: CGPoint(x: -out.x, y: -out.y), handleOut: out,
                       kind: .smooth)
        }
        return Run(anchors: anchors, isClosed: true)
    }

    // MARK: - Arcs

    /// An SVG elliptical arc as cubic curves (each control, control, end),
    /// following the endpoint-to-centre conversion in the SVG specification,
    /// appendix F.6.
    static func arc(from p0: CGPoint, to p1: CGPoint, radii: CGSize, rotation degrees: CGFloat,
                    large: Bool, sweep: Bool) -> [(CGPoint, CGPoint, CGPoint)] {
        var rx = abs(radii.width), ry = abs(radii.height)
        guard rx > 0, ry > 0, p0 != p1 else { return [] }
        let phi = degrees * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1 = cosPhi * dx + sinPhi * dy
        let y1 = -sinPhi * dx + cosPhi * dy
        // Radii too small to reach are scaled up until they just do.
        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 {
            rx *= lambda.squareRoot()
            ry *= lambda.squareRoot()
        }
        let numerator = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var factor = denominator == 0 ? 0 : (max(numerator, 0) / denominator).squareRoot()
        if large == sweep { factor = -factor }
        let cx1 = factor * rx * y1 / ry
        let cy1 = -factor * ry * x1 / rx
        let center = CGPoint(x: cosPhi * cx1 - sinPhi * cy1 + (p0.x + p1.x) / 2,
                             y: sinPhi * cx1 + cosPhi * cy1 + (p0.y + p1.y) / 2)
        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        }
        let theta = angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
        var delta = angle((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
        if !sweep, delta > 0 { delta -= 2 * .pi }
        if sweep, delta < 0 { delta += 2 * .pi }

        let pieces = max(1, Int((abs(delta) / (.pi / 2)).rounded(.up)))
        let step = delta / CGFloat(pieces)
        let t = 4 / 3 * tan(step / 4)
        func onEllipse(_ a: CGFloat) -> CGPoint {
            CGPoint(x: center.x + rx * cos(a) * cosPhi - ry * sin(a) * sinPhi,
                    y: center.y + rx * cos(a) * sinPhi + ry * sin(a) * cosPhi)
        }
        func derivative(_ a: CGFloat) -> CGPoint {
            CGPoint(x: -rx * sin(a) * cosPhi - ry * cos(a) * sinPhi,
                    y: -rx * sin(a) * sinPhi + ry * cos(a) * cosPhi)
        }
        var curves: [(CGPoint, CGPoint, CGPoint)] = []
        var a = theta
        for index in 0..<pieces {
            let b = a + step
            let start = onEllipse(a), end = index == pieces - 1 ? p1 : onEllipse(b)
            let da = derivative(a), db = derivative(b)
            curves.append((CGPoint(x: start.x + t * da.x, y: start.y + t * da.y),
                           CGPoint(x: end.x - t * db.x, y: end.y - t * db.y),
                           end))
            a = b
        }
        return curves
    }

    // MARK: - Reading the text

    /// Walks path data one token at a time. SVG lets numbers run together
    /// ("1.32-3.09", ".5.5"), so a number ends where the next one plainly
    /// starts.
    struct Reader {
        private let characters: [Character]
        private var index = 0

        init(_ text: String) { characters = Array(text) }

        private mutating func skipSeparators() {
            while index < characters.count,
                  characters[index] == " " || characters[index] == "," || characters[index].isNewline
                    || characters[index] == "\t" { index += 1 }
        }

        /// The next command letter, or `continuing` again when more numbers
        /// follow without one (an implicit repeat). Nil at the end.
        mutating func command(continuing: Character) -> Character? {
            skipSeparators()
            guard index < characters.count else { return nil }
            let c = characters[index]
            if c.isLetter {
                index += 1
                return c
            }
            // A bare number repeats the last command; a close takes none.
            return continuing.lowercased() == "z" ? nil : continuing
        }

        mutating func number() -> CGFloat? {
            skipSeparators()
            var text = ""
            var seenDot = false, seenExponent = false
            while index < characters.count {
                let c = characters[index]
                if c == "-" || c == "+" {
                    guard text.isEmpty || text.last == "e" || text.last == "E" else { break }
                } else if c == "." {
                    guard !seenDot, !seenExponent else { break }
                    seenDot = true
                } else if c == "e" || c == "E" {
                    guard !seenExponent, !text.isEmpty else { break }
                    seenExponent = true
                } else if !c.isNumber {
                    break
                }
                text.append(c)
                index += 1
            }
            return Double(text).map { CGFloat($0) }
        }

        /// An arc's flag: a single 0 or 1, which SVG lets sit against the next
        /// number with nothing between them.
        mutating func flag() -> Bool? {
            skipSeparators()
            guard index < characters.count else { return nil }
            switch characters[index] {
            case "0": index += 1; return false
            case "1": index += 1; return true
            default: return nil
            }
        }
    }
}
