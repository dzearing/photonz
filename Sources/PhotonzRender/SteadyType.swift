import CoreGraphics
import CoreText
import Foundation
import PhotonzCore

// Type that holds still against itself while it scales, drifts or turns.
//
// The system draws a glyph from a small picture of it, put down on whole or
// quarter pixels: right for a label that never moves, and the jitter in one
// that does. Redrawn at 51, 52, 53 percent, each letter of a title rounded to
// its own pixel on every frame, up to 0.6 of a pixel either way and no two
// letters the same way (measured 2026-11-24). Turning the rounding off
// (`setShouldSubpixelQuantizeFonts`) still left 0.2 of a pixel.
//
// So in anything that plays, letters are filled as the outlines they are:
// every point of a letter lands exactly where the scale puts it. They are
// filled a hair fat, by what the system's font smoothing adds, so a title
// weighs what the same words weigh on a still picture.

/// Where a layer's box sits in the picture it is drawn into.
///
/// A whole number of pixels holds a box that is not a whole number of pixels,
/// at the exact part of a pixel it will land on, so the picture is laid on the
/// frame with nothing resampled and nothing stretched to fit.
public struct PixelPlacing: Hashable, Sendable {
    /// The picture's size, in its own pixels.
    public var width: Int
    public var height: Int
    /// The box's bottom left corner in the picture, in its pixels, y up.
    public var origin: CGPoint

    /// Whether each letter is put on a whole pixel, as the system puts one in
    /// a picture that never moves: a hair crisper, and safe only for words
    /// that are never shown at another size, where the rounding would go a
    /// different way for each letter.
    public var snapsLetters = false

    /// Clear pixels kept round the box.
    static let margin: CGFloat = 2

    /// A picture for a box of `box` pixels whose bottom left corner lands at
    /// `corner` on the frame, or, where that is nil (a box turned or seen
    /// through the camera lands on no pixel in particular), in the middle of
    /// its picture.
    public init(box: CGSize, corner: CGPoint?, snapsLetters: Bool = false) {
        self.snapsLetters = snapsLetters
        if let corner {
            let x = corner.x - corner.x.rounded(.down), y = corner.y - corner.y.rounded(.down)
            origin = CGPoint(x: Self.margin + x, y: Self.margin + y)
            width = Int((origin.x + box.width).rounded(.up) + Self.margin)
            height = Int((origin.y + box.height).rounded(.up) + Self.margin)
        } else {
            width = Int(box.width.rounded(.up) + Self.margin * 2)
            height = Int(box.height.rounded(.up) + Self.margin * 2)
            origin = CGPoint(x: (CGFloat(width) - box.width) / 2, y: (CGFloat(height) - box.height) / 2)
        }
    }

    /// How far the middle of the picture is from the middle of the box.
    func shift(box: CGSize) -> CGPoint {
        CGPoint(x: CGFloat(width) / 2 - (origin.x + box.width / 2),
                y: CGFloat(height) / 2 - (origin.y + box.height / 2))
    }
}

enum SteadyType {

    /// How much wider than its outline, in pixels, the system's font smoothing
    /// paints a glyph `pixels` tall in a colour of brightness `luma`: the same
    /// 0.69 of a pixel at every title size, less the smaller and the darker
    /// the type. Read off Core Graphics itself (macOS 27, 2026-11-24).
    static func smoothing(pixels: CGFloat, luma: CGFloat) -> CGFloat {
        guard pixels > 0 else { return 0 }
        let stops: [(luma: CGFloat, share: CGFloat)] = [(0.25, 0.0133), (0.5, 0.0187), (0.75, 0.0238), (1, 0.0328)]
        var share = stops[0].share
        for (low, high) in zip(stops, stops.dropFirst()) where luma > low.luma {
            let along = min(1, (luma - low.luma) / (high.luma - low.luma))
            share = low.share + (high.share - low.share) * along
        }
        return min(0.69, share * pixels)
    }

    /// ...and how far up it sits, as a share of it: the smoothing puts all but
    /// a sliver of it on the upper side, so a letter's feet stay on the line.
    static let smoothingLift: CGFloat = 0.435

    static func luma(_ color: CGColor) -> CGFloat {
        guard let parts = color.components, !parts.isEmpty else { return 0 }
        guard parts.count >= 4 else { return parts[0] }
        return 0.2126 * parts[0] + 0.7152 * parts[1] + 0.0722 * parts[2]
    }

    /// Every line of `frame`, drawn as outlines. `grouped` where something
    /// behind each letter (a glow, a shadow) must see the letter as one piece.
    static func draw(_ frame: CTFrame, base: CGPoint, scale: CGFloat, snaps: Bool, grouped: Bool = false,
                     in context: CGContext) {
        guard let lines = CTFrameGetLines(frame) as? [CTLine], !lines.isEmpty else { return }
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        for (line, origin) in zip(lines, origins) {
            for run in (CTLineGetGlyphRuns(line) as? [CTRun]) ?? [] {
                draw(run, at: place(origin, base: base), scale: scale, snaps: snaps,
                     grouped: grouped, in: context)
            }
        }
    }

    /// Where a line sits: on a whole point, as the system puts one on a whole
    /// pixel, so the feet of the letters are crisp at rest. A point of the
    /// SETTING, magnified with it, so it is the same place at every scale.
    static func place(_ origin: CGPoint, base: CGPoint) -> CGPoint {
        CGPoint(x: base.x + origin.x, y: (base.y + origin.y).rounded())
    }

    /// `count` glyphs of `run` from `from`, on a line whose origin is
    /// `origin`, in a context of `scale` pixels a point.
    static func draw(_ run: CTRun, from: Int = 0, count: Int? = nil, at origin: CGPoint, scale: CGFloat,
                     snaps: Bool, grouped: Bool = false, in context: CGContext) {
        let total = CTRunGetGlyphCount(run)
        let length = min(count ?? total, total - from)
        guard length > 0 else { return }
        let attributes = CTRunGetAttributes(run) as NSDictionary
        guard let held = attributes[kCTFontAttributeName as String] else { return }
        let value = held as CFTypeRef
        guard CFGetTypeID(value) == CTFontGetTypeID() else { return }
        let font = unsafeDowncast(value, to: CTFont.self)
        // Colour glyphs (an emoji) are pictures with no outline to fill.
        if CTFontGetSymbolicTraits(font).contains(.traitColorGlyphs) {
            context.saveGState()
            context.setAllowsFontSubpixelQuantization(false)
            context.setShouldSubpixelQuantizeFonts(false)
            context.textMatrix = .identity
            context.textPosition = origin
            CTRunDraw(run, context, CFRange(location: from, length: length))
            context.restoreGState()
            return
        }
        var glyphs = [CGGlyph](repeating: 0, count: length)
        var positions = [CGPoint](repeating: .zero, count: length)
        CTRunGetGlyphs(run, CFRange(location: from, length: length), &glyphs)
        CTRunGetPositions(run, CFRange(location: from, length: length), &positions)
        /// Each letter's outline put down on its own: a fill costs by the box
        /// it covers, and the whole line as one path cost three times this.
        func eachLetter(fattenedBy fat: CGFloat, lift: CGFloat, _ paint: () -> Void) {
            for index in 0..<length {
                guard let glyph = CTFontCreatePathForGlyph(font, glyphs[index], nil) else { continue }
                context.saveGState()
                context.translateBy(x: origin.x + positions[index].x, y: origin.y + positions[index].y)
                if snaps {
                    let now = context.ctm
                    if now.b == 0, now.c == 0, now.a != 0, now.d != 0 {
                        context.translateBy(x: (now.tx.rounded() - now.tx) / now.a,
                                            y: (now.ty.rounded() - now.ty) / now.d)
                    }
                }
                context.translateBy(x: 0, y: lift)
                context.addPath(fat > 0 ? Self.fattened(glyph, by: fat) : glyph)
                paint()
                context.restoreGState()
            }
        }
        func color(_ key: CFString) -> CGColor? {
            guard let held = attributes[key as String] else { return nil }
            let value = held as CFTypeRef
            guard CFGetTypeID(value) == CGColor.typeID else { return nil }
            return unsafeDowncast(value, to: CGColor.self)
        }
        let fill = color(kCTForegroundColorAttributeName) ?? CGColor(gray: 0, alpha: 1)
        let size = CTFontGetSize(font)
        context.saveGState()
        defer { context.restoreGState() }
        if let percent = attributes[kCTStrokeWidthAttributeName as String] as? NSNumber, percent.doubleValue != 0 {
            // An outline's underlay: filled and stroked (negative), or hollow.
            let stroke = color(kCTStrokeColorAttributeName) ?? fill
            guard fill.alpha > 0 || stroke.alpha > 0 else { return }
            context.setLineWidth(abs(CGFloat(percent.doubleValue)) / 100 * size)
            context.setFillColor(fill)
            context.setStrokeColor(stroke)
            if grouped { context.beginTransparencyLayer(auxiliaryInfo: nil) }
            eachLetter(fattenedBy: 0, lift: 0) {
                context.drawPath(using: percent.doubleValue < 0 ? .fillStroke : .stroke)
            }
            if grouped { context.endTransparencyLayer() }
            return
        }
        guard fill.alpha > 0 else { return }
        let fat = smoothing(pixels: size * scale, luma: luma(fill)) / scale
        // One fill of one outline: filled and then stroked, a pixel on the
        // edge was covered twice over by how the two happened to fall on it,
        // and the letters went back to slipping, a tenth of a pixel each.
        context.setFillColor(fill)
        if grouped { context.beginTransparencyLayer(auxiliaryInfo: nil) }
        eachLetter(fattenedBy: fat / 2, lift: fat * smoothingLift) { context.fillPath() }
        if grouped { context.endTransparencyLayer() }
    }

    /// `glyph` with its edge moved out by `distance` all the way round, its
    /// counters closing by as much: every side of its control polygon moved
    /// along its own normal and the sides met again where they cross.
    ///
    /// Right for the third of a pixel it is asked for. Not a general offset:
    /// moved further than a stroke is wide it would fold over itself.
    static func fattened(_ glyph: CGPath, by distance: CGFloat) -> CGPath {
        struct Contour {
            /// The control polygon, its end not repeated.
            var points: [CGPoint] = []
            /// How many of `points` each segment after the move adds.
            var kinds: [CGPathElementType] = []
        }
        var contours: [Contour] = []
        glyph.applyWithBlock { element in
            let e = element.pointee
            switch e.type {
            case .moveToPoint:
                contours.append(Contour(points: [e.points[0]]))
            case .addLineToPoint, .addQuadCurveToPoint, .addCurveToPoint:
                guard !contours.isEmpty else { return }
                let count = e.type == .addLineToPoint ? 1 : e.type == .addQuadCurveToPoint ? 2 : 3
                for i in 0..<count { contours[contours.count - 1].points.append(e.points[i]) }
                contours[contours.count - 1].kinds.append(e.type)
            default: break
            }
        }
        // Which way round the letter's outside runs: the way its area counts.
        var area: CGFloat = 0
        for contour in contours {
            let p = contour.points
            for i in p.indices {
                let q = p[(i + 1) % p.count]
                area += p[i].x * q.y - q.x * p[i].y
            }
        }
        guard area != 0 else { return glyph }
        let side: CGFloat = area > 0 ? 1 : -1
        let out = CGMutablePath()
        for contour in contours where contour.points.count > 2 {
            var p = contour.points
            // Closed back onto its own start: the last segment's end IS the
            // first point, and the polygon holds it once.
            let closes = hypot(p[0].x - p[p.count - 1].x, p[0].y - p[p.count - 1].y) < 1e-6
            if closes { p.removeLast() }
            let count = p.count
            guard count > 2 else { continue }
            func normal(_ a: CGPoint, _ b: CGPoint) -> CGVector? {
                let dx = b.x - a.x, dy = b.y - a.y, l = hypot(dx, dy)
                guard l > 1e-7 else { return nil }
                return CGVector(dx: dy / l * side, dy: -dx / l * side)
            }
            /// The normal of the side into `i`, past any side of no length.
            func into(_ i: Int) -> CGVector? {
                for back in 1..<count {
                    if let n = normal(p[(i - back + count) % count], p[(i - back + 1 + count) % count]) { return n }
                }
                return nil
            }
            func outOf(_ i: Int) -> CGVector? {
                for on in 0..<(count - 1) {
                    if let n = normal(p[(i + on) % count], p[(i + on + 1) % count]) { return n }
                }
                return nil
            }
            var moved = p
            for i in 0..<count {
                guard let a = into(i), let b = outOf(i) else { continue }
                // Along the two normals' middle, far enough that both sides
                // moved the whole distance, and never more than twice it.
                let dot = a.dx * b.dx + a.dy * b.dy
                let reach = distance / max(0.5, 1 + dot)
                moved[i] = CGPoint(x: p[i].x + (a.dx + b.dx) * reach, y: p[i].y + (a.dy + b.dy) * reach)
            }
            if closes { moved.append(moved[0]) }
            out.move(to: moved[0])
            var at = 1
            for kind in contour.kinds {
                switch kind {
                case .addLineToPoint:
                    out.addLine(to: moved[at]); at += 1
                case .addQuadCurveToPoint:
                    out.addQuadCurve(to: moved[at + 1], control: moved[at]); at += 2
                default:
                    out.addCurve(to: moved[at + 2], control1: moved[at], control2: moved[at + 1]); at += 3
                }
            }
            out.closeSubpath()
        }
        return out
    }
}
