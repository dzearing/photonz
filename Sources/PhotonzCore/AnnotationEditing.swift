import CoreGraphics
import Foundation

/// Which end of a line/arrow annotation an endpoint handle controls.
public enum AnnotationEndpoint: String, CaseIterable, Hashable, Sendable {
    case start
    case end
}

extension Layer {
    /// The layer's annotation content, nil for other content kinds.
    public var annotation: AnnotationContent? {
        if case .annotation(let a) = content { return a }
        return nil
    }

    /// The layer's measure content, nil for other content kinds.
    public var measure: MeasureContent? {
        if case .measure(let m) = content { return m }
        return nil
    }

    /// The bitmap this layer references, nil for non-image content.
    public var imageRef: ImageRef? {
        if case .image(let ref) = content { return ref }
        return nil
    }

    /// Lines/arrows and measures edit by dragging their two endpoints.
    /// Alignment guides don't: their items were scanned for the drawn span, so
    /// the guide is redrawn rather than stretched (a stale scan would lie).
    public var hasEndpointHandles: Bool {
        if let a = annotation { return a.shape == .line || a.shape == .arrow }
        if let m = measure { return m.alignment == nil }
        return false
    }

    /// A measure reference point's position in document coordinates.
    public func measureEndpoint(_ endpoint: AnnotationEndpoint) -> CGPoint? {
        guard let m = measure else { return nil }
        let local = endpoint == .start ? m.start : m.end
        return CGPoint(x: frame.minX + local.x, y: frame.minY + local.y)
    }

    /// Whether the selection chrome offers this layer's handles at all, and
    /// whether a press on one starts a drag.
    ///
    /// A locked layer offers none. Locking says the thing holds still, so a
    /// handle sitting on one would be an invitation the app then refuses:
    /// worse than no handle, because the only way to find that out is to try
    /// to drag it. The chrome, the press and the pointer cue all read this,
    /// so they cannot disagree about whether a handle is there.
    ///
    /// The blue selection outline is NOT a handle: you can still pick a locked
    /// layer out of the layers list and see which one it is.
    public var offersHandles: Bool { !isLocked }

    /// Whether the selection chrome offers the eight frame-resize handles.
    /// Lines/arrows use endpoint handles instead. Text resizes width-only: the
    /// handles set the wrap width and the renderer re-wraps to it (see
    /// `resizeWidthOnly`); font size still goes through the picker.
    public var allowsFrameResize: Bool {
        switch content {
        case .text: true
        case .annotation: !hasEndpointHandles
        // Calipers edit via endpoint handles; alignment guides not at all
        // (move/delete only) — neither offers the eight frame handles.
        case .measure: false
        // A group resizes, and everything in it scales with the box
        // (`docs/design/ui-building.md`). A COPY of a component is the one
        // that cannot: its contents are refilled from its original after every
        // edit, so a stretched copy would snap straight back — resize the
        // original instead and every copy follows.
        // A COPY of a component takes its own size rather than scaling its
        // contents: they are refilled from the original after every edit, so a
        // stretched copy would snap straight back. The box it is given is kept
        // as the copy's own and written back over the original's after every
        // sync (`InstanceSize`), which is what lets one nav bar be 1200 wide on
        // a desktop screen and 375 on a phone.
        case .group: true
        case .image, .zoomCallout, .collage: true
        }
    }

    /// Text resize only changes WIDTH (the wrap width); height follows from the
    /// re-wrap, and vertical handle drags don't stretch glyphs. Other content
    /// resizes freely in both axes.
    public var resizeWidthOnly: Bool {
        if case .text = content { return true }
        return false
    }

    /// An annotation endpoint's position in document coordinates.
    public func annotationEndpoint(_ endpoint: AnnotationEndpoint) -> CGPoint? {
        guard let a = annotation else { return nil }
        let local = endpoint == .start ? a.start : a.end
        return CGPoint(x: frame.minX + local.x, y: frame.minY + local.y)
    }

    /// The draggable endpoint (corner) for whichever endpoint-handled content
    /// this is — a line/arrow vertex or a measure's box corner.
    public func editEndpoint(_ endpoint: AnnotationEndpoint) -> CGPoint? {
        annotationEndpoint(endpoint) ?? measureEndpoint(endpoint)
    }

    /// The box the layer's INK actually fills, in document coordinates — what
    /// selection chrome should hug.
    ///
    /// A line or an arrow is a thin band inside a mostly empty frame: the frame
    /// is padded on all four sides so a round cap, an arrowhead's wings and a
    /// caption pill's shadow have room to rasterize into, and the caption's
    /// share of it is a deliberately generous guess at the pill's width. A blue
    /// outline drawn round THAT says a small arrow owns half the screen, which
    /// is what the user reported on 2026-09-05. This walks the shapes the
    /// rasterizer actually draws instead.
    ///
    /// `captionPillSize` is the pill as MEASURED (only PhotonzRender can
    /// measure type). Without one the caption's own generous estimate stands
    /// in, which is the same box the frame reserved.
    ///
    /// Everything that is not an open stroke already fills its frame, so it
    /// gets the frame it always had.
    public func drawnBounds(captionPillSize: CGSize? = nil) -> CGRect {
        guard let a = annotation, a.shape == .line || a.shape == .arrow else {
            return withoutSlack(frame)
        }
        let start = CGPoint(x: frame.minX + a.start.x, y: frame.minY + a.start.y)
        let end = CGPoint(x: frame.minX + a.end.x, y: frame.minY + a.end.y)
        // The stroke runs tail to tip for a line, and tail to inside the head
        // for an arrow — exactly what the rasterizer draws.
        let strokeEnd = a.shape == .arrow
            ? Geometry.arrowShaftEnd(start: start, end: end, strokeWidth: a.strokeWidth,
                                     scale: a.arrowheadScale, style: a.arrowheadStyle)
            : end
        // A round cap reaches half a stroke past each end and half a stroke
        // either side of the line.
        let cap = a.strokeWidth / 2
        var minX = min(start.x, strokeEnd.x) - cap, maxX = max(start.x, strokeEnd.x) + cap
        var minY = min(start.y, strokeEnd.y) - cap, maxY = max(start.y, strokeEnd.y) + cap
        func include(_ p: CGPoint) {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        if a.shape == .arrow,
           let head = Geometry.arrowheadBounds(start: start, end: end, strokeWidth: a.strokeWidth,
                                               scale: a.arrowheadScale, style: a.arrowheadStyle) {
            include(CGPoint(x: head.minX, y: head.minY))
            include(CGPoint(x: head.maxX, y: head.maxY))
        }
        if a.hasCaption {
            let size = captionPillSize ?? a.estimatedCaptionSize
            var probe = a
            probe.start = start
            probe.end = end
            let center = probe.captionPillCenter(forPillSize: size)
            include(CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2))
            include(CGPoint(x: center.x + size.width / 2, y: center.y + size.height / 2))
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// The layer with its frame set to `frame`. Annotation content remaps its
    /// endpoints so the drawn shape scales with the frame (a bare frame
    /// assignment would clip or distort it); zoom callouts re-derive their
    /// magnification from the new frame; a group re-fits so the box it occupies
    /// becomes `frame`, scaling everything inside it; other content just moves.
    ///
    /// A FRAME is the exception among groups: its box is a real size, and
    /// resizing it moves where it clips rather than magnifying the screen you
    /// are building on. What is ON the screen still follows any placement rule
    /// it was given, so a bar stretches across a screen dragged wider while
    /// everything nobody has given a rule to holds still.
    ///
    /// `fillingHeight` is the one thing a text box cannot work out for itself:
    /// normally its height is however tall its words came out, so a height
    /// handed to it is ignored. It is honoured when the container has STRETCHED
    /// this layer down its box, because then the height in `frame` is the
    /// container's answer rather than a guess, and only the two places that
    /// know that rule (`GroupFlow`, `LayerScaling`) ever pass it.
    /// `placedByContainer` is the other thing a layer cannot work out for
    /// itself: whether this box is a size somebody chose or a size the stack,
    /// grid or screen around it worked out while flowing. Only the two places
    /// that know that rule (`GroupFlow`, `LayerScaling`) ever pass it, and it
    /// matters for exactly one thing — a copy stretched across the shelf it
    /// sits in must not go on claiming that width as its own answer once the
    /// shelf changes.
    public func resized(to frame: CGRect, fillingHeight: Bool = false,
                        placedByContainer: Bool = false) -> Layer {
        if annotation != nil { return AnnotationBuilder.resized(self, to: frame) }
        if measure != nil { return MeasureBuilder.resized(self, to: frame) }
        if zoomCallout != nil { return ZoomCalloutBuilder.resized(self, to: frame) }
        if let group {
            // A copy is told how big it is and remembers being told, because
            // scaling what is inside one is work the next sync throws away.
            if group.instanceOf != nil, !placedByContainer {
                return LayerScaling.resizingCopy(self, to: frame)
            }
            if group.isFrame { return LayerScaling.refitting(self, to: frame) }
            // A group that arranges itself takes the size it is given: its flow
            // fills the new box, so typing a width on a stack makes the stack
            // that wide rather than magnifying everything in it.
            if group.layout != nil { return LayerScaling.rearranging(self, to: frame) }
            return LayerScaling.resizing(self, to: frame)
        }
        var layer = self
        layer.frame = frame
        // A width chosen by hand is an answer, so the container's answer is
        // dropped: from here on this box is a paragraph somebody made, and the
        // flow leaves its width alone.
        if !placedByContainer, text != nil,
           abs(frame.standardized.width - self.frame.standardized.width) > 0.01 {
            layer.wrappedByItsContainer = nil
        }
        // A text box's width IS its wrap width, so a new one re-wraps the words
        // and the box becomes as tall as they now need — dragged narrower it
        // gains lines, dragged wider it gives them back, and the top edge stays
        // put either way. A move, or a drag of the bottom edge, changes no wrap
        // and re-measures nothing (`docs/design/ui-building.md`, "A label grows
        // to fit what it says").
        if case .text(let content) = content, resizeWidthOnly {
            let box = frame.standardized
            let width = box.width
            if fillingHeight {
                // Told to fill the box it is in: it keeps the height it was
                // handed, and the words sit in it wherever Align says. Never
                // less than the words need, because a room too small to hold
                // them is not a reason to cut the last line off
                // (`docs/design/ui-building.md`, "Where the words sit in their
                // box").
                let needed = TextMeasurement.size(of: content, wrappingAt: width).height
                layer.frame = CGRect(x: box.minX, y: box.minY,
                                     width: width, height: max(box.height, needed))
            } else if abs(width - self.frame.standardized.width) > 0.01 {
                layer.frame = CGRect(x: box.minX, y: box.minY,
                                     width: width,
                                     height: TextMeasurement.size(of: content,
                                                                  wrappingAt: width).height)
            } else {
                layer.frame.size.height = self.frame.standardized.height
            }
        }
        return layer
    }
}

extension AnnotationBuilder {
    /// The layer with its annotation redrawn between document-space `start`
    /// and `end`: identity and style survive, the frame is rebuilt with render
    /// padding exactly like a fresh drag. Non-annotation layers pass through.
    public static func updating(_ layer: Layer, start: CGPoint, end: CGPoint) -> Layer {
        guard let a = layer.annotation else { return layer }
        let rebuilt = self.layer(content: a, from: start, to: end)
        var updated = layer
        updated.frame = rebuilt.frame
        updated.content = rebuilt.content
        return updated
    }

    /// Handle-resize remap: endpoints scale proportionally into the proposed
    /// frame, then the layer is rebuilt so the (unchanged) stroke width keeps
    /// its full render padding even after a downscale.
    public static func resized(_ layer: Layer, to frame: CGRect) -> Layer {
        guard let a = layer.annotation,
              layer.frame.width > 0, layer.frame.height > 0 else { return layer }
        func remap(_ p: CGPoint) -> CGPoint {
            CGPoint(x: frame.minX + p.x / layer.frame.width * frame.width,
                    y: frame.minY + p.y / layer.frame.height * frame.height)
        }
        return updating(layer, start: remap(a.start), end: remap(a.end))
    }

    /// Style edit on an existing annotation: endpoints stay anchored in
    /// document space while the frame re-pads for the new stroke width.
    /// `fillColorHex` is doubly-optional: outer nil keeps the current fill,
    /// `.some(nil)` clears it, `.some(hex)` sets it.
    public static func restyled(_ layer: Layer, colorHex: String? = nil,
                                paint: Paint? = nil,
                                strokeWidth: CGFloat? = nil,
                                arrowheadScale: CGFloat? = nil,
                                arrowheadStyle: ArrowheadStyle? = nil,
                                cornerRadius: CGFloat? = nil,
                                fillColorHex: String?? = nil,
                                fill: Paint?? = nil,
                                caption: String?? = nil,
                                captionFontSize: CGFloat? = nil,
                                captionRoundness: CGFloat? = nil) -> Layer {
        guard var a = layer.annotation,
              let start = layer.annotationEndpoint(.start),
              let end = layer.annotationEndpoint(.end) else { return layer }
        if let colorHex { a.colorHex = colorHex }
        // The whole paint, gradient and all. `colorHex` above is the flat way
        // in and stays exactly what it was.
        if let paint { a.paint = paint }
        if let strokeWidth { a.strokeWidth = strokeWidth }
        if let arrowheadScale { a.arrowheadScale = arrowheadScale }
        if let arrowheadStyle { a.arrowheadStyle = arrowheadStyle }
        if let cornerRadius { a.cornerRadius = cornerRadius }
        if let fillColorHex { a.fillColorHex = fillColorHex }
        if let fill { a.fill = fill }
        if let caption { a.caption = caption }
        if let captionFontSize { a.captionFontSize = captionFontSize }
        if let captionRoundness { a.captionRoundness = captionRoundness }
        var updated = layer
        updated.content = .annotation(a)
        return updating(updated, start: start, end: end)
    }
}

extension AnnotationBuilder {
    /// Picks where a captioned arrow's pill sits so it stays on the picture.
    /// The default spot (behind the tail) wins whenever it fits; otherwise the
    /// pill moves beside the tail, clear of the shaft and the head, and the
    /// frame is rebuilt around it. A hand-placed pill (`captionPinned`) is
    /// not re-picked: it keeps its offset from the tail and is only pulled
    /// back onto the picture. Endpoints never move. Pass nil for `canvas` to
    /// skip planning; captionless layers pass through.
    ///
    /// `captionPillSize` is the pill as MEASURED (only PhotonzRender can
    /// measure type). Without one the caption's own generous estimate stands
    /// in, and every edge the pill is held off is that much too far away: a
    /// sentence dropped against the right edge of the picture came to rest
    /// 157pt short of it. Same rule as `Layer.drawnBounds(captionPillSize:)`.
    public static func planningCaption(_ layer: Layer, canvas: CGSize?,
                                       captionPillSize: CGSize? = nil) -> Layer {
        guard let canvas, let a = layer.annotation, a.hasCaption,
              let start = layer.annotationEndpoint(.start),
              let end = layer.annotationEndpoint(.end) else { return layer }
        var probe = a
        probe.start = start
        probe.end = end
        let placement: CaptionPlacement
        if a.captionPinned, let pinned = a.captionOffset {
            placement = CaptionPlacement(
                attach: CaptionPlanner.keepingOnCanvas(pinned, for: probe, canvas: canvas,
                                                       pillSize: captionPillSize),
                growth: a.captionGrowth)
        } else {
            placement = CaptionPlanner.plan(for: probe, canvas: canvas,
                                            reserving: captionPillSize)
        }
        guard placement.attach != a.captionOffset || placement.growth != a.captionGrowth else {
            return layer
        }
        var content = a
        content.captionOffset = placement.attach
        content.captionGrowth = placement.growth
        var updated = layer
        updated.content = .annotation(content)
        return updating(updated, start: start, end: end)
    }

    /// The pill dragged by hand to center on `center` (document space): the
    /// spot is pinned relative to the tail so it rides along when the arrow
    /// moves, pulled back onto the picture if it would leave it, and the frame
    /// is rebuilt around it. Captionless layers pass through.
    ///
    /// `captionPillSize` is the pill as MEASURED: `center` names where the
    /// label you can SEE should sit, so the conversion into an attachment has
    /// to use the size it is really drawn at. Without one the estimate stands
    /// in, and the label lands short of the hand by half the difference.
    public static func placingCaption(_ layer: Layer, at center: CGPoint, canvas: CGSize?,
                                      captionPillSize: CGSize? = nil) -> Layer {
        guard let a = layer.annotation, a.hasCaption,
              let tail = layer.annotationEndpoint(.start) else { return layer }
        var content = a
        content.captionPinned = true
        // The drop freezes the direction as well as the spot: a pill placed by
        // hand must not swing around its attachment when the head later moves.
        content.captionGrowth = a.captionGrowthDirection()
        // The drop names where the PILL sits; the model stores where it hangs
        // from, so a caption typed later still grows away from the arrow.
        let attachment = CaptionPlanner.attachment(forPillCenter: center, of: a,
                                                   size: captionPillSize ?? a.estimatedCaptionSize)
        content.captionOffset = CGSize(width: attachment.x - tail.x, height: attachment.y - tail.y)
        var updated = layer
        updated.content = .annotation(content)
        // Rebuild the frame around the new spot even without a canvas to clamp
        // against, then clamp when there is one.
        guard let end = layer.annotationEndpoint(.end) else { return layer }
        return planningCaption(updating(updated, start: tail, end: end), canvas: canvas,
                               captionPillSize: captionPillSize)
    }

    /// Writes a caption and the spot the caption FIELD used, without re-picking
    /// it: what you saw on the last keystroke is what lands, so the pill does
    /// not jump on Return. An empty caption clears the spot with the text.
    ///
    /// `canvas` and `captionPillSize` are the one exception. A caption grows
    /// TALLER as lines are typed into it, both ways from the spot it hangs
    /// from, so a label that started as one line beside the tail can end up
    /// hanging off the top or bottom of the picture. Given the picture and the
    /// measured pill, a label that would fall off is pulled back on — and a
    /// label that fits is left exactly where it was, which is every ordinary
    /// caption.
    public static func captioning(_ layer: Layer, caption: String?,
                                  placement: CaptionPlacement, canvas: CGSize? = nil,
                                  captionPillSize: CGSize? = nil) -> Layer {
        guard var content = layer.annotation,
              let start = layer.annotationEndpoint(.start),
              let end = layer.annotationEndpoint(.end) else { return layer }
        content.caption = caption
        if content.hasCaption {
            content.captionOffset = placement.attach
            content.captionGrowth = placement.growth
            if let canvas {
                var probe = content
                probe.start = start
                probe.end = end
                let wanted = placement.attach ?? .zero
                let onCanvas = CaptionPlanner.keepingOnCanvas(wanted, for: probe, canvas: canvas,
                                                              pillSize: captionPillSize)
                if onCanvas != wanted { content.captionOffset = onCanvas }
            }
        } else {
            content.captionOffset = nil
            content.captionGrowth = nil
            content.captionPinned = false
        }
        var updated = layer
        updated.content = .annotation(content)
        return updating(updated, start: start, end: end)
    }

    /// Hands a hand-placed pill back to the planner: the automatic spot again.
    public static func releasingCaption(_ layer: Layer, canvas: CGSize?,
                                        captionPillSize: CGSize? = nil) -> Layer {
        guard let a = layer.annotation, a.captionPinned,
              let start = layer.annotationEndpoint(.start),
              let end = layer.annotationEndpoint(.end) else { return layer }
        var content = a
        content.captionPinned = false
        content.captionOffset = nil
        content.captionGrowth = nil
        var updated = layer
        updated.content = .annotation(content)
        return planningCaption(updating(updated, start: start, end: end), canvas: canvas,
                               captionPillSize: captionPillSize)
    }
}

/// Where a caption pill hangs from and which way it grows: the two things the
/// planner decides, and the two the caption field freezes when it opens so
/// nothing moves under the typing.
public struct CaptionPlacement: Hashable, Sendable {
    /// The attachment relative to the tail. Nil = the default spot, one gap
    /// past the tail along the shaft.
    public var attach: CGSize?
    /// The growth direction as a unit vector. Nil = along the shaft, away from
    /// the head.
    public var growth: CGSize?

    public init(attach: CGSize? = nil, growth: CGSize? = nil) {
        self.attach = attach
        self.growth = growth
    }
}

/// Where an arrow's caption pill goes when the tail is too close to the edge
/// of the picture for the default spot. Pure geometry: `content` must be in
/// document space (endpoints and canvas in the same coordinates).
///
/// The ranking is `LabelPlacer`'s, the same one the measurement readout and
/// the roles legend go through: this only says which spots exist and what the
/// pill has to keep off.
public enum CaptionPlanner {
    /// Nil-everything when the default spot behind the tail fits the canvas;
    /// otherwise the way the pill grows off the tail. Spots, in order: back
    /// along the shaft, then above the tail, below it, and beside it. Sitting
    /// on the head costs more than any lower-ranked spot, and sitting on the
    /// shaft more than the rank gap, so the label never hides what the arrow
    /// is pointing at.
    ///
    /// **Every spot hangs the pill straight off the tail**, so whichever one
    /// wins, the tail is the middle of the pill's near edge and the shaft runs
    /// into it. The spots used to sit one gap away and, above or below the
    /// tail, off to one side as well, which left the tail floating past a
    /// corner of the pill with a space between them (reported 2026-09-05).
    ///
    /// `reserving` is the pill the spot has to hold: the caption's own estimate
    /// by default, or `captionRoomProbeSize` when a field is opening and the
    /// sentence has not been typed yet.
    public static func plan(for content: AnnotationContent, canvas: CGSize,
                            reserving reserve: CGSize? = nil) -> CaptionPlacement {
        let bounds = CGRect(origin: .zero, size: canvas)
        let size = reserve ?? content.estimatedCaptionSize
        var free = content
        free.captionOffset = nil
        free.captionGrowth = nil
        let shaft = free.captionGrowthDirection()
        if bounds.contains(rect(of: free, size: size)) { return CaptionPlacement() }

        let tail = content.start
        let head = content.end
        let gap = AnnotationContent.captionGap
        // Which way the pill runs from the tail. Nil is the shaft's own
        // direction (the first choice), and the three squared directions it is
        // not are the fallbacks, in reading order.
        let others = [CGSize(width: 0, height: -1), CGSize(width: 0, height: 1),
                      CGSize(width: -1, height: 0), CGSize(width: 1, height: 0)]
        let spots: [CGSize?] = [nil] + others.filter { $0 != shaft }.map { Optional($0) }
        // What the arrow is POINTING AT is the subject: the pill may never sit
        // on it. Its own shaft is softer — a pill on the shaft still reads as
        // this arrow's, it just crowds the line — so it is priced like any
        // other leader running through something.
        let headRadius = content.strokeWidth * 3 * content.arrowheadScale + gap
        let headZone = CGRect(x: head.x - headRadius, y: head.y - headRadius,
                              width: 2 * headRadius, height: 2 * headRadius)
        // The shaft leaves the tail from INSIDE the pill now, so a crossing is
        // judged from a gap's travel down the shaft, against the pill shrunk by
        // a hair: touching the near edge is the point, not a collision.
        let run = hypot(head.x - tail.x, head.y - tail.y)
        let clear = run > gap
            ? CGPoint(x: tail.x + (head.x - tail.x) / run * gap,
                      y: tail.y + (head.y - tail.y) / run * gap)
            : head
        let candidates = spots.enumerated().map { rank, growth -> LabelCandidate<CaptionPlacement> in
            var probe = free
            probe.captionGrowth = growth
            let wanted = rect(of: probe, size: size)
            var cost = CGFloat(rank) * LabelPlacer.rankCost
            // Off the picture is already a flat charge in LabelPlacer; this
            // says WHICH of two bad directions is less bad, so the pill that
            // barely overhangs wins over the one that is half off.
            cost += overflow(of: wanted, in: bounds) * LabelPlacer.nudgeCost
            if LabelPlacer.segment(from: clear, to: head,
                                   crosses: [wanted.insetBy(dx: 0.5, dy: 0.5)]) {
                cost += LabelPlacer.crossingCost
            }
            return LabelCandidate(rect: wanted, payload: CaptionPlacement(growth: growth),
                                  cost: cost)
        }
        let avoid = [LabelAvoidance(rects: [headZone], weight: .flat(LabelPlacer.subjectCost))]
        guard let best = LabelPlacer.best(among: candidates, avoiding: avoid,
                                          within: bounds) else { return CaptionPlacement() }
        // Last resort: a pill that runs off the picture even in its best
        // direction is slid back on, which does let go of the tail. A label
        // half off the picture cannot be read at all, which is worse.
        var winner = free
        winner.captionGrowth = best.growth
        let wanted = rect(of: winner, size: size)
        let onCanvas = slidOntoCanvas(wanted, bounds: bounds)
        guard onCanvas != wanted else { return best }
        let anchor = slid(winner.captionAttachment(), by: onCanvas, from: wanted)
        return CaptionPlacement(attach: CGSize(width: anchor.x - tail.x,
                                               height: anchor.y - tail.y),
                                growth: best.growth)
    }

    /// How far `rect` reaches outside `bounds`, added up over all four sides.
    private static func overflow(of rect: CGRect, in bounds: CGRect) -> CGFloat {
        max(0, bounds.minX - rect.minX) + max(0, rect.maxX - bounds.maxX)
            + max(0, bounds.minY - rect.minY) + max(0, rect.maxY - bounds.maxY)
    }

    /// A hand-placed pill's attachment, pulled back onto the picture if the
    /// pill it holds would leave it. The person chose the spot, so nothing else
    /// is second-guessed: it may sit on the shaft or the head.
    ///
    /// `pillSize` is the pill as MEASURED. Without one the caption's own
    /// generous estimate stands in and the label is held that much further off
    /// every edge than it has to be.
    public static func keepingOnCanvas(_ offset: CGSize, for content: AnnotationContent,
                                       canvas: CGSize, pillSize: CGSize? = nil) -> CGSize {
        let bounds = CGRect(origin: .zero, size: canvas)
        let tail = content.start
        var probe = content
        probe.captionOffset = offset
        let wanted = rect(of: probe, size: pillSize ?? content.estimatedCaptionSize)
        let anchor = slid(probe.captionAttachment(),
                          by: slidOntoCanvas(wanted, bounds: bounds), from: wanted)
        return CGSize(width: anchor.x - tail.x, height: anchor.y - tail.y)
    }

    /// The attachment a pill of `size` centered on `center` hangs from: the
    /// middle of the side facing the arrow. The inverse of
    /// `captionPillCenter(forPillSize:)`, used wherever a spot arrives as a
    /// pill position (a drag's drop, a candidate slid back onto the picture).
    public static func attachment(forPillCenter center: CGPoint, of content: AnnotationContent,
                                  size: CGSize) -> CGPoint {
        let d = content.captionGrowthDirection()
        let extent = (abs(d.width) * size.width + abs(d.height) * size.height) / 2
        return CGPoint(x: center.x - d.width * extent, y: center.y - d.height * extent)
    }

    /// An attachment carried along by however far its pill had to slide to sit
    /// on the picture. The shift is applied to the point itself rather than
    /// re-derived from the moved pill, so a spot that did not slide comes back
    /// bit for bit.
    private static func slid(_ attachment: CGPoint, by pill: CGRect, from wanted: CGRect) -> CGPoint {
        CGPoint(x: attachment.x + (pill.minX - wanted.minX),
                y: attachment.y + (pill.minY - wanted.minY))
    }

    /// The pill `content` would draw at `size`, in `content`'s own coordinates.
    private static func rect(of content: AnnotationContent, size: CGSize) -> CGRect {
        let center = content.captionPillCenter(forPillSize: size)
        return CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                      width: size.width, height: size.height)
    }

    /// The nearest position that keeps `pill` inside `bounds` (itself when it
    /// already fits, centered when it never can).
    private static func slidOntoCanvas(_ pill: CGRect, bounds: CGRect) -> CGRect {
        func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
            lo <= hi ? min(max(v, lo), hi) : (lo + hi) / 2
        }
        return CGRect(x: clamp(pill.minX, bounds.minX, bounds.maxX - pill.width),
                      y: clamp(pill.minY, bounds.minY, bounds.maxY - pill.height),
                      width: pill.width, height: pill.height)
    }
}

/// An in-progress endpoint drag on a line/arrow layer. Mirrors
/// `AnnotationDrag`: the canvas feeds it pointer positions, the geometry
/// (including ⇧ 45° snap around the fixed endpoint) lives here.
public struct AnnotationEndpointDrag: Equatable, Sendable {
    public let endpoint: AnnotationEndpoint
    public let shape: AnnotationShape
    /// The endpoint that stays put, in document coordinates.
    public let fixed: CGPoint
    /// The dragged endpoint's current position, in document coordinates.
    public var current: CGPoint

    public init?(layer: Layer, endpoint: AnnotationEndpoint) {
        guard layer.hasEndpointHandles, let a = layer.annotation,
              let fixed = layer.annotationEndpoint(endpoint == .start ? .end : .start),
              let moving = layer.annotationEndpoint(endpoint) else { return nil }
        self.endpoint = endpoint
        self.shape = a.shape
        self.fixed = fixed
        self.current = moving
    }

    public mutating func update(to point: CGPoint) {
        current = point
    }

    /// The annotation's document-space endpoints with this drag applied.
    /// Constrained (⇧) snaps the moved endpoint to 45° around the fixed one,
    /// the same rule drag-to-create uses.
    public func endpoints(constrained: Bool) -> (start: CGPoint, end: CGPoint) {
        var target = current
        if constrained {
            var drag = AnnotationDrag(anchor: fixed)
            drag.update(to: current)
            target = drag.end(constrained: true, shape: shape)
        }
        return endpoint == .start ? (start: target, end: fixed) : (start: fixed, end: target)
    }
}

/// Endpoint-handle hit-testing, mirroring `Handles`: document coordinates in,
/// tolerance in screen points so handles feel the same size at any zoom.
public enum AnnotationEndpoints {
    public static func hit(at p: CGPoint, layer: Layer, zoom: CGFloat,
                           screenTolerance: CGFloat = 8) -> AnnotationEndpoint? {
        guard layer.hasEndpointHandles else { return nil }
        let tolerance = zoom > 0 ? screenTolerance / zoom : screenTolerance
        var best: (endpoint: AnnotationEndpoint, distance: CGFloat)?
        for endpoint in AnnotationEndpoint.allCases {
            guard let ep = layer.editEndpoint(endpoint) else { continue }
            let distance = hypot(p.x - ep.x, p.y - ep.y)
            if distance <= tolerance, distance < (best?.distance ?? .infinity) {
                best = (endpoint, distance)
            }
        }
        return best?.endpoint
    }
}
