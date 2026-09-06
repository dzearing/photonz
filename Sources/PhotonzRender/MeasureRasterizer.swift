import CoreGraphics
import CoreText
import Foundation
import PhotonzCore

/// Rasterizes a caliper (`MeasureContent`) into a transparent-background CGImage:
/// the squared-U outline (two legs + head bar) with lightly rounded corners, plus
/// the label pill. While the pill still rides the line, the line **stops on the
/// pill's outline** from either side, so a translucent pill never reveals a
/// stroke behind it and the number still reads as part of the line that made it.
/// When the pill has moved out of the way of what the measurement describes
/// (`MeasureLabelPlacement`, UX-PATTERNS D14) the line draws whole and a leader
/// keeps the pill attached, ending on that same outline.
///
/// The pill used to be omitted here and drawn as an AppKit overlay on the live
/// canvas instead (a Liquid-Glass capsule). That made the chip unreachable by
/// everything that acts on a LAYER — opacity, shadow, blend mode, transform —
/// so the canvas and the export disagreed. The caliper is one object; it is one
/// raster.
///
/// Drawing happens in the layer's local top-left space — the same space
/// `start`/`end` are stored in — and the readout uses the content's unit,
/// divided by `pixelScale` for points.
public enum MeasureRasterizer {

    /// Draws `measure` inside `size` (the layer's box, in document points).
    ///
    /// `scale` is how many pixels the result gets per document point, so a
    /// zoomed-in canvas can bake the caliper and its readout at the resolution
    /// they are about to be seen at rather than blowing a document-sized
    /// picture of them up afterwards. It scales the DRAWING, never the caliper:
    /// the line width, the corner radius and the chip are stated in the same
    /// points at every scale, so nothing shifts or resizes when a sharper copy
    /// arrives — and a "1px" caliper still covers exactly one image pixel.
    public static func rasterize(_ measure: MeasureContent, size: CGSize,
                                 pixelScale: CGFloat, scale: CGFloat = 1) -> CGImage? {
        guard scale > 0, scale.isFinite else { return nil }
        let width = Int((size.width * scale).rounded())
        let height = Int((size.height * scale).rounded())
        guard width >= 1, height >= 1 else { return nil }

        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }

        // Flip to top-left coordinates (matches AnnotationRasterizer/TextRasterizer)
        // and scale, so everything below goes on stating document points.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)

        let rgba = RGBA(hex: measure.strokeColorHex) ?? RGBA(r: 1, g: 0.23, b: 0.19)
        let color = CGColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a)
        // The chip's fill is its own color; its alpha comes from `chipOpacity`
        // (the hex never carries alpha — see MeasureContent.chipColorHex).
        let chip = RGBA(hex: measure.chipColorHex) ?? RGBA(r: 1, g: 1, b: 1)
        let chipColor = CGColor(srgbRed: chip.r, green: chip.g, blue: chip.b,
                                alpha: min(max(measure.chipOpacity, 0), 1))
        // Caliper lines are ACTUAL image pixels — a "1px" caliper is exactly one
        // image pixel (pixel-precise redlining), NOT scaled up by pixelScale.
        let lineWidth = measure.strokeWidth
        context.setStrokeColor(color)
        context.setLineWidth(lineWidth)
        // Round caps/joins so the corners read refined, not sharp.
        context.setLineCap(.round)
        context.setLineJoin(.round)

        let g = measure.caliperGeometry()

        // An alignment check draws a dashed guide with tick marks and a verdict
        // chip instead of the squared-U caliper.
        if measure.alignment != nil {
            drawAlignmentCheck(measure, geometry: g, pixelScale: pixelScale,
                               color: color, chipColor: chipColor, in: context)
            return context.makeImage()
        }

        // Where the readout lands, and what the line has to do about it.
        let labelText = measure.chipText(pixelScale: pixelScale)
        let plan = labelPlan(measure, geometry: g, text: labelText,
                             attachments: [(g.footA, g.headA), (g.headA, g.headB),
                                           (g.headB, g.footB)])

        // Two rounded L legs, each running as far as the chip and no further.
        drawSide(foot: g.footA, head: g.headA, mid: g.labelAnchor, plan: plan, in: context)
        drawSide(foot: g.footB, head: g.headB, mid: g.labelAnchor, plan: plan, in: context)

        if let leader = plan.leader { drawLeader(leader, in: context) }

        if measure.showLabel {
            drawPill(labelText, at: plan.center, chipSize: plan.size,
                     fontSize: measure.labelPointSize,
                     borderWidth: lineWidth, fill: chipColor, border: color,
                     textColorHex: measure.textColorHex, in: context)
        }

        return context.makeImage()
    }

    /// An alignment check (§9, decision D1): a dashed guide along the feet
    /// line, a short solid tick where each element that AGREES crosses it, a
    /// heavier bracket enclosing the gap between the guide and the one element
    /// that does not, and the verdict chip ("Left edges aligned" / "Left
    /// edges, off 4 px": the picture carries no row name, so the chip names
    /// the edge itself) wherever the content's `labelPlacement` puts it —
    /// never on the rows being judged.
    private static func drawAlignmentCheck(_ measure: MeasureContent, geometry g: CaliperGeometry,
                                           pixelScale: CGFloat, color: CGColor,
                                           chipColor: CGColor, in context: CGContext) {
        guard let check = measure.alignment else { return }
        let labelText = measure.chipText(pixelScale: pixelScale)
        let plan = labelPlan(measure, geometry: g, text: labelText,
                             attachments: [(g.footA, g.footB)])

        // Dashed guide. It is split around the chip ONLY while the chip still
        // rides it: once the verdict has moved out of the way of the rows it is
        // judging (D14), a gap in the guide would be decoration.
        context.setLineDash(phase: 0, lengths: [6, 4])
        if let pill = plan.pill {
            for foot in [g.footA, g.footB] {
                guard let cut = pill.entry(from: foot, toward: pill.center) else { continue }
                context.move(to: foot)
                context.addLine(to: cut)
                context.strokePath()
            }
        } else {
            context.move(to: g.footA)
            context.addLine(to: g.footB)
            context.strokePath()
        }
        context.setLineDash(phase: 0, lengths: [])

        let vertical = measure.mode == .vertical
        let guidePos = vertical ? g.footA.x : g.footA.y
        let outlier = check.verdict?.outlierIndex
        let tick = MeasureBuilder.alignmentTickHalf
        // The stretch of the guide the pill is sitting on, if it still is: the
        // solid runs below have to leave it alone for the same reason the dashes
        // do — a translucent pill must never show a stroke through it.
        let gap: ClosedRange<CGFloat>? = {
            guard let pill = plan.pill else { return nil }
            let centre = vertical ? pill.center.y : pill.center.x
            let half = vertical ? pill.rect.height / 2 : pill.rect.width / 2
            return (centre - half)...(centre + half)
        }()
        for (index, item) in check.items.enumerated() {
            let spanMid = (item.spanStart + item.spanEnd) / 2
            if index == outlier {
                // The offender gets a bracket, not a tick: out from the guide to
                // where this element's edge REALLY sits, down that edge for the
                // element's whole run, and back to the guide. It encloses the
                // error, so the gap is a shape you can see at a glance rather
                // than a hairline you have to hunt for — and it can never be
                // mistaken for one of the ticks saying "this one agrees".
                let lo = min(item.spanStart, item.spanEnd)
                let hi = max(item.spanStart, item.spanEnd)
                context.saveGState()
                context.setLineWidth(max(measure.strokeWidth * 2, 2))
                context.move(to: point(cross: guidePos, along: lo, vertical: vertical))
                context.addLine(to: point(cross: item.edge, along: lo, vertical: vertical))
                context.addLine(to: point(cross: item.edge, along: hi, vertical: vertical))
                context.addLine(to: point(cross: guidePos, along: hi, vertical: vertical))
                context.strokePath()
                context.restoreGState()
            } else {
                // An element that agrees: the guide goes SOLID for the length of
                // its run, and a short perpendicular tick marks the crossing. The
                // dashes are the guide travelling; solid is the guide confirming,
                // so what the check actually covered is visible without counting
                // anything.
                for run in clip(min(item.spanStart, item.spanEnd)...max(item.spanStart, item.spanEnd),
                                around: gap) {
                    context.move(to: point(cross: guidePos, along: run.lowerBound, vertical: vertical))
                    context.addLine(to: point(cross: guidePos, along: run.upperBound, vertical: vertical))
                    context.strokePath()
                }
                context.move(to: point(cross: guidePos - tick, along: spanMid, vertical: vertical))
                context.addLine(to: point(cross: guidePos + tick, along: spanMid, vertical: vertical))
                context.strokePath()
            }
        }

        if let leader = plan.leader { drawLeader(leader, in: context) }

        if measure.showLabel {
            drawPill(labelText, at: plan.center, chipSize: plan.size,
                     fontSize: measure.labelPointSize,
                     borderWidth: measure.strokeWidth, fill: chipColor, border: color,
                     textColorHex: measure.textColorHex, in: context)
        }
    }

    // MARK: - Where the readout lands (UX-PATTERNS D14)

    /// Everything drawing needs to know about the readout: where the pill
    /// centres, the outline the measurement's own line has to stop on while the
    /// pill still rides it, and the leader that keeps a relocated pill attached
    /// to its subject.
    private struct LabelPlan {
        var center: CGPoint
        var size: CGSize
        /// The pill's outline while it still rides the line; nil = the line is
        /// drawn whole, because the readout has moved off it.
        var pill: Pill?
        var leader: (from: CGPoint, to: CGPoint)?
    }

    /// The pill as a shape to run into: the capsule `PillRasterizer` draws, so
    /// a line meeting it lands on the actual curve rather than on a bounding
    /// box corner that is not there.
    private struct Pill {
        var rect: CGRect
        var radius: CGFloat

        var center: CGPoint { CGPoint(x: rect.midX, y: rect.midY) }

        /// True while `p` is within the outline.
        ///
        /// A capsule is every point no further than `radius` from the rect
        /// shrunk by `radius`, which is one test for the flat sides and the
        /// round caps alike.
        func contains(_ p: CGPoint) -> Bool {
            let r = clampedRadius
            let core = rect.insetBy(dx: r, dy: r)
            let dx = max(core.minX - p.x, 0, p.x - core.maxX)
            let dy = max(core.minY - p.y, 0, p.y - core.maxY)
            return dx * dx + dy * dy <= r * r
        }

        private var clampedRadius: CGFloat {
            max(0, min(radius, rect.width / 2, rect.height / 2))
        }

        /// Where the straight run `from → toward` crosses the outline, or nil
        /// when there is no crossing to find — `from` is already inside, which
        /// is the caller's signal that the pill has swallowed it.
        ///
        /// The shape is convex and `toward` is inside it, so there is exactly
        /// one crossing and halving the run converges straight onto it. Thirty
        /// odd containment tests per line is nothing beside the thousands of
        /// pixels the same raster is about to paint, and it keeps the caps and
        /// the sides on one code path.
        func entry(from: CGPoint, toward: CGPoint) -> CGPoint? {
            guard !contains(from), contains(toward) else { return nil }
            func point(_ t: CGFloat) -> CGPoint {
                CGPoint(x: from.x + (toward.x - from.x) * t, y: from.y + (toward.y - from.y) * t)
            }
            var outside: CGFloat = 0, inside: CGFloat = 1
            for _ in 0..<32 {
                let mid = (outside + inside) / 2
                if contains(point(mid)) { inside = mid } else { outside = mid }
            }
            return point(inside)
        }
    }

    /// A relocated readout has to keep reading as part of its measurement. Up
    /// to this far (px) plain adjacency does that on its own; past it, a leader
    /// line draws the connection.
    private static let adjacencyReach: CGFloat = 10

    private static func labelPlan(_ measure: MeasureContent, geometry g: CaliperGeometry,
                                  text: String,
                                  attachments: [(CGPoint, CGPoint)]) -> LabelPlan {
        guard measure.showLabel else {
            return LabelPlan(center: g.labelAnchor, size: .zero, pill: nil, leader: nil)
        }
        let size = chipFootprint(for: text, fontSize: measure.labelPointSize,
                                 padding: measure.labelPadding,
                                 minWidth: measure.labelMinPillWidth)
        let center = measure.labelPosition(chipSize: size)
        let outline = Pill(rect: CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                                        width: size.width, height: size.height),
                           radius: PillRasterizer.cornerRadius(for: size))

        // The measurement's own line stops on the outline only while the pill
        // is still riding it; once the readout has moved, the line is whole.
        let rides = measure.labelRidesTheLine(chipSize: size)

        // Attach: from the closest point of the measurement's own strokes to
        // where that line meets the pill.
        var leader: (from: CGPoint, to: CGPoint)?
        if !rides, let anchor = nearestPoint(on: attachments, to: center),
           let entry = outline.entry(from: anchor, toward: center),
           hypot(entry.x - anchor.x, entry.y - anchor.y) > adjacencyReach {
            leader = (anchor, entry)
        }
        return LabelPlan(center: center, size: size, pill: rides ? outline : nil, leader: leader)
    }

    /// One side of the caliper, drawn as far as the readout and no further.
    ///
    /// The head bar runs in from `head` toward the chip and ends ON the pill's
    /// outline, so its round cap tucks under the pill's own border — same ink,
    /// same width — and the two read as one line with nothing showing through
    /// the fill. There used to be five points of daylight there instead, which
    /// is what made the number look like it was floating.
    ///
    /// When the chip is wider than the span it describes there is no head bar
    /// left to arrive on: the pill has swallowed the corner, so the LEG ends on
    /// the outline instead and there is no corner to round. Wider still and it
    /// swallows the foot too, and this side draws nothing at all — a stroke
    /// there could only ever be seen through the pill.
    private static func drawSide(foot: CGPoint, head: CGPoint, mid: CGPoint,
                                 plan: LabelPlan, in context: CGContext) {
        guard let pill = plan.pill else {
            drawLeg(foot: foot, head: head, toward: mid, in: context)
            return
        }
        if let armEnd = pill.entry(from: head, toward: pill.center) {
            drawLeg(foot: foot, head: head, toward: armEnd, in: context)
        } else if let legEnd = pill.entry(from: foot, toward: head) {
            context.move(to: foot)
            context.addLine(to: legEnd)
            context.strokePath()
        }
    }

    /// Closest point on any of the measurement's own segments to `p`.
    private static func nearestPoint(on segments: [(CGPoint, CGPoint)], to p: CGPoint) -> CGPoint? {
        var best: CGPoint?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (a, b) in segments {
            let dx = b.x - a.x, dy = b.y - a.y
            let lengthSquared = dx * dx + dy * dy
            let t = lengthSquared > 0
                ? min(max(((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared, 0), 1)
                : 0
            let q = CGPoint(x: a.x + dx * t, y: a.y + dy * t)
            let d = hypot(q.x - p.x, q.y - p.y)
            if d < bestDistance { bestDistance = d; best = q }
        }
        return best
    }

    /// The leader: a plain solid line, never dashed, so it reads as "this label
    /// belongs to that measurement" and not as more measurement.
    private static func drawLeader(_ leader: (from: CGPoint, to: CGPoint),
                                   in context: CGContext) {
        context.saveGState()
        context.setLineDash(phase: 0, lengths: [])
        context.move(to: leader.from)
        context.addLine(to: leader.to)
        context.strokePath()
        context.restoreGState()
    }

    /// `run` with `gap` cut out of it: nothing, one piece or two.
    private static func clip(_ run: ClosedRange<CGFloat>,
                             around gap: ClosedRange<CGFloat>?) -> [ClosedRange<CGFloat>] {
        guard let gap, gap.overlaps(run) else { return [run] }
        var pieces: [ClosedRange<CGFloat>] = []
        if run.lowerBound < gap.lowerBound { pieces.append(run.lowerBound...gap.lowerBound) }
        if gap.upperBound < run.upperBound { pieces.append(gap.upperBound...run.upperBound) }
        return pieces
    }

    /// A point from guide-relative coordinates: `cross` is the guide's own axis
    /// position (x for a vertical guide), `along` the span axis.
    private static func point(cross: CGFloat, along: CGFloat, vertical: Bool) -> CGPoint {
        vertical ? CGPoint(x: cross, y: along) : CGPoint(x: along, y: cross)
    }

    /// The chip's footprint = measured text (at `fontSize`) + padding on all
    /// sides, floored at `minWidth` so a one or two digit readout still reads
    /// as the badge a longer one is (`MeasureContent.labelBadgeAspect`).
    private static func chipFootprint(for text: String, fontSize: CGFloat, padding: CGFloat,
                                      minWidth: CGFloat) -> CGSize {
        PillRasterizer.footprint(for: text, fontSize: fontSize, padding: padding,
                                 minWidth: minWidth)
    }

    /// One caliper leg: `foot → (rounded corner at head) → toward` (the head-line
    /// cut edge, or the head midpoint when there's no chip gap).
    private static func drawLeg(foot: CGPoint, head: CGPoint, toward: CGPoint, in context: CGContext) {
        let legLen = hypot(head.x - foot.x, head.y - foot.y)
        let armLen = hypot(toward.x - head.x, toward.y - head.y)
        let radius = max(0, min(MeasureContent.cornerRadius, legLen / 2, armLen))
        let path = CGMutablePath()
        path.move(to: foot)
        if radius > 0.5, armLen > 0.5 {
            path.addArc(tangent1End: head, tangent2End: toward, radius: radius)
            path.addLine(to: toward)
        } else {
            path.addLine(to: head)
            if armLen > 0.5 { path.addLine(to: toward) }
        }
        context.addPath(path)
        context.strokePath()
    }

    /// Draws the flattened readout centered at `anchor`: the chip `fill`, a
    /// border in the caliper's stroke color, and text in the readout color — the
    /// three independently editable measure colors. The capsule itself is the
    /// shared `PillRasterizer` (arrow captions draw the same pill).
    private static func drawPill(_ string: String, at anchor: CGPoint, chipSize: CGSize,
                                 fontSize: CGFloat, borderWidth: CGFloat, fill: CGColor,
                                 border: CGColor, textColorHex: String, in context: CGContext) {
        PillRasterizer.draw(string, at: anchor, chipSize: chipSize, fontSize: fontSize,
                            borderWidth: borderWidth, fill: fill, border: border,
                            textColorHex: textColorHex, in: context)
    }
}
