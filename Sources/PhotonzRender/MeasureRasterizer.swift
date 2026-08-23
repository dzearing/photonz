import CoreGraphics
import CoreText
import Foundation
import PhotonzCore

/// Rasterizes a caliper (`MeasureContent`) into a transparent-background CGImage:
/// the squared-U outline (two legs + head bar) with lightly rounded corners, plus
/// the label pill. While the pill still rides the line, the line is **split
/// around it** (a gap), so a translucent pill never reveals a stroke behind it.
/// When the pill has moved out of the way of what the measurement describes
/// (`MeasureLabelPlacement`, UX-PATTERNS D14) the line draws whole and a leader
/// keeps the pill attached.
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

    public static func rasterize(_ measure: MeasureContent, size: CGSize,
                                 pixelScale: CGFloat) -> CGImage? {
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        guard width >= 1, height >= 1 else { return nil }

        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }

        // Flip to top-left coordinates (matches AnnotationRasterizer/TextRasterizer).
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)

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
        let labelText = measure.label(pixelScale: pixelScale)
        let plan = labelPlan(measure, geometry: g, text: labelText,
                             attachments: [(g.footA, g.headA), (g.headA, g.headB),
                                           (g.headB, g.footB)])

        // Two rounded L legs; the head line is cut only where the chip still
        // rides it.
        let mid = g.labelAnchor
        func gapEdge(toward p: CGPoint) -> CGPoint {
            guard let split = plan.splitCenter, plan.gapHalf > 0 else { return mid }
            return along(from: split, toward: p, distance: plan.gapHalf)
        }
        drawLeg(foot: g.footA, head: g.headA, toward: gapEdge(toward: g.headA), in: context)
        drawLeg(foot: g.footB, head: g.headB, toward: gapEdge(toward: g.headB), in: context)

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
    /// that does not, and the verdict chip ("aligned" / "off 4 px") wherever the
    /// content's `labelPlacement` puts it — never on the rows being judged.
    private static func drawAlignmentCheck(_ measure: MeasureContent, geometry g: CaliperGeometry,
                                           pixelScale: CGFloat, color: CGColor,
                                           chipColor: CGColor, in context: CGContext) {
        guard let check = measure.alignment else { return }
        let labelText = measure.label(pixelScale: pixelScale)
        let plan = labelPlan(measure, geometry: g, text: labelText,
                             attachments: [(g.footA, g.footB)])

        // Dashed guide. It is split around the chip ONLY while the chip still
        // rides it: once the verdict has moved out of the way of the rows it is
        // judging (D14), a gap in the guide would be decoration.
        context.setLineDash(phase: 0, lengths: [6, 4])
        if let split = plan.splitCenter, plan.gapHalf > 0 {
            for foot in [g.footA, g.footB] {
                context.move(to: foot)
                context.addLine(to: along(from: split, toward: foot, distance: plan.gapHalf))
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
            guard let split = plan.splitCenter, plan.gapHalf > 0 else { return nil }
            let centre = vertical ? split.y : split.x
            return (centre - plan.gapHalf)...(centre + plan.gapHalf)
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
    /// centres, whether the measurement's own line still splits around it, and
    /// the leader that keeps a relocated pill attached to its subject.
    private struct LabelPlan {
        var center: CGPoint
        var size: CGSize
        /// The point on the line the split is centred on; nil = draw it whole.
        var splitCenter: CGPoint?
        var gapHalf: CGFloat
        var leader: (from: CGPoint, to: CGPoint)?
    }

    /// A relocated readout has to keep reading as part of its measurement. Up
    /// to this far (px) plain adjacency does that on its own; past it, a leader
    /// line draws the connection.
    private static let adjacencyReach: CGFloat = 10

    private static func labelPlan(_ measure: MeasureContent, geometry g: CaliperGeometry,
                                  text: String,
                                  attachments: [(CGPoint, CGPoint)]) -> LabelPlan {
        guard measure.showLabel else {
            return LabelPlan(center: g.labelAnchor, size: .zero, splitCenter: nil,
                             gapHalf: 0, leader: nil)
        }
        let size = chipFootprint(for: text, fontSize: measure.labelPointSize,
                                 padding: measure.labelPadding)
        let center = measure.labelPosition(chipSize: size)
        let rect = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                          width: size.width, height: size.height)

        // The split exists so a translucent pill never reveals a stroke behind
        // it — only meaningful while the pill is still on the line.
        var splitCenter: CGPoint?
        var gapHalf: CGFloat = 0
        if measure.labelRidesTheLine(chipSize: size) {
            let offset = measure.labelOffset(chipSize: size)
            splitCenter = CGPoint(x: g.labelAnchor.x + offset.x, y: g.labelAnchor.y + offset.y)
            gapHalf = min(measure.chipAxisHalfExtent(chipSize: size) + MeasureContent.chipLineGap,
                          measure.rawDistance / 2)
        }

        // Attach: from the closest point of the measurement's own strokes to
        // where that line enters the pill.
        var leader: (from: CGPoint, to: CGPoint)?
        if splitCenter == nil, let anchor = nearestPoint(on: attachments, to: center),
           !rect.contains(anchor), let entry = entryPoint(from: anchor, to: center, rect: rect),
           hypot(entry.x - anchor.x, entry.y - anchor.y) > adjacencyReach {
            leader = (anchor, entry)
        }
        return LabelPlan(center: center, size: size, splitCenter: splitCenter,
                         gapHalf: gapHalf, leader: leader)
    }

    /// The point `distance` away from `origin` in the direction of `target`,
    /// never overshooting `target` itself.
    private static func along(from origin: CGPoint, toward target: CGPoint,
                              distance: CGFloat) -> CGPoint {
        let dx = target.x - origin.x, dy = target.y - origin.y
        let len = hypot(dx, dy)
        guard len > 0 else { return origin }
        let t = min(distance / len, 1)
        return CGPoint(x: origin.x + dx * t, y: origin.y + dy * t)
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

    /// Where the segment `from → to` first crosses into `rect` (`to` is the
    /// rect's centre, so there is always a crossing unless `from` is inside).
    private static func entryPoint(from: CGPoint, to: CGPoint, rect: CGRect) -> CGPoint? {
        let dx = to.x - from.x, dy = to.y - from.y
        var enter: CGFloat = 0, exit: CGFloat = 1
        func clip(_ origin: CGFloat, _ delta: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> Bool {
            if abs(delta) < 1e-9 { return origin >= lo && origin <= hi }
            let t1 = (lo - origin) / delta, t2 = (hi - origin) / delta
            enter = max(enter, min(t1, t2))
            exit = min(exit, max(t1, t2))
            return enter <= exit
        }
        guard clip(from.x, dx, rect.minX, rect.maxX),
              clip(from.y, dy, rect.minY, rect.maxY) else { return nil }
        return CGPoint(x: from.x + dx * enter, y: from.y + dy * enter)
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

    /// The chip's footprint = measured text (at `fontSize`) + padding on all sides.
    private static func chipFootprint(for text: String, fontSize: CGFloat, padding: CGFloat) -> CGSize {
        PillRasterizer.footprint(for: text, fontSize: fontSize, padding: padding)
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
