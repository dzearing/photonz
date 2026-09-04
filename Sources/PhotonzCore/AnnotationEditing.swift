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
                                cornerRadius: CGFloat? = nil,
                                fillColorHex: String?? = nil,
                                fill: Paint?? = nil,
                                caption: String?? = nil,
                                captionFontSize: CGFloat? = nil) -> Layer {
        guard var a = layer.annotation,
              let start = layer.annotationEndpoint(.start),
              let end = layer.annotationEndpoint(.end) else { return layer }
        if let colorHex { a.colorHex = colorHex }
        // The whole paint, gradient and all. `colorHex` above is the flat way
        // in and stays exactly what it was.
        if let paint { a.paint = paint }
        if let strokeWidth { a.strokeWidth = strokeWidth }
        if let arrowheadScale { a.arrowheadScale = arrowheadScale }
        if let cornerRadius { a.cornerRadius = cornerRadius }
        if let fillColorHex { a.fillColorHex = fillColorHex }
        if let fill { a.fill = fill }
        if let caption { a.caption = caption }
        if let captionFontSize { a.captionFontSize = captionFontSize }
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
    public static func planningCaption(_ layer: Layer, canvas: CGSize?) -> Layer {
        guard let canvas, let a = layer.annotation, a.hasCaption,
              let start = layer.annotationEndpoint(.start),
              let end = layer.annotationEndpoint(.end) else { return layer }
        var probe = a
        probe.start = start
        probe.end = end
        let placement: CaptionPlacement
        if a.captionPinned, let pinned = a.captionOffset {
            placement = CaptionPlacement(
                attach: CaptionPlanner.keepingOnCanvas(pinned, for: probe, canvas: canvas),
                growth: a.captionGrowth)
        } else {
            placement = CaptionPlanner.plan(for: probe, canvas: canvas)
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
    public static func placingCaption(_ layer: Layer, at center: CGPoint, canvas: CGSize?) -> Layer {
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
                                                   size: a.estimatedCaptionSize)
        content.captionOffset = CGSize(width: attachment.x - tail.x, height: attachment.y - tail.y)
        var updated = layer
        updated.content = .annotation(content)
        // Rebuild the frame around the new spot even without a canvas to clamp
        // against, then clamp when there is one.
        guard let end = layer.annotationEndpoint(.end) else { return layer }
        return planningCaption(updating(updated, start: tail, end: end), canvas: canvas)
    }

    /// Writes a caption and the spot the caption FIELD used, without re-picking
    /// it: what you saw on the last keystroke is what lands, so the pill does
    /// not jump on Return. An empty caption clears the spot with the text.
    public static func captioning(_ layer: Layer, caption: String?,
                                  placement: CaptionPlacement) -> Layer {
        guard var content = layer.annotation,
              let start = layer.annotationEndpoint(.start),
              let end = layer.annotationEndpoint(.end) else { return layer }
        content.caption = caption
        if content.hasCaption {
            content.captionOffset = placement.attach
            content.captionGrowth = placement.growth
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
    public static func releasingCaption(_ layer: Layer, canvas: CGSize?) -> Layer {
        guard let a = layer.annotation, a.captionPinned,
              let start = layer.annotationEndpoint(.start),
              let end = layer.annotationEndpoint(.end) else { return layer }
        var content = a
        content.captionPinned = false
        content.captionOffset = nil
        content.captionGrowth = nil
        var updated = layer
        updated.content = .annotation(content)
        return planningCaption(updating(updated, start: start, end: end), canvas: canvas)
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
    /// otherwise the spot the pill hangs from and the way it grows. Spots, in
    /// order: back along the shaft, then above the tail, below it, and beside
    /// it, each running whichever way has the room. Sitting on the head costs
    /// more than any lower-ranked spot, and sitting on the shaft more than the
    /// rank gap, so the label never hides what the arrow is pointing at.
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
        let right = CGSize(width: 1, height: 0)
        let left = CGSize(width: -1, height: 0)
        // Where the pill hangs from and which way it runs. A caption is one
        // line, so it only ever grows sideways: a spot above or below the tail
        // therefore starts AT the tail and runs off to one side, rather than
        // straddling it and spreading both ways into whatever is beside it.
        let row = gap + size.height / 2
        let spots: [(attach: CGPoint, growth: CGSize?)] = [
            (CGPoint(x: tail.x + shaft.width * gap, y: tail.y + shaft.height * gap), nil),
            (CGPoint(x: tail.x, y: tail.y - row), right),
            (CGPoint(x: tail.x, y: tail.y - row), left),
            (CGPoint(x: tail.x, y: tail.y + row), right),
            (CGPoint(x: tail.x, y: tail.y + row), left),
            (CGPoint(x: tail.x - gap, y: tail.y), left),
            (CGPoint(x: tail.x + gap, y: tail.y), right),
        ]
        // What the arrow is POINTING AT is the subject: the pill may never sit
        // on it. Its own shaft is softer — a pill on the shaft still reads as
        // this arrow's, it just crowds the line — so it is priced like any
        // other leader running through something.
        let headRadius = content.strokeWidth * 3 * content.arrowheadScale + gap
        let headZone = CGRect(x: head.x - headRadius, y: head.y - headRadius,
                              width: 2 * headRadius, height: 2 * headRadius)
        let candidates = spots.enumerated().map { rank, spot -> LabelCandidate<CaptionPlacement> in
            var probe = free
            probe.captionGrowth = spot.growth
            probe.captionOffset = CGSize(width: spot.attach.x - tail.x,
                                         height: spot.attach.y - tail.y)
            let wanted = rect(of: probe, size: size)
            let pill = slidOntoCanvas(wanted, bounds: bounds)
            // A caption grows sideways, so horizontal room is what a direction
            // is worth: every point the pill has to slide left or right to fit
            // is a point it will have to slide again on the next keystroke.
            var cost = CGFloat(rank) * LabelPlacer.rankCost
            cost += abs(pill.minX - wanted.minX) * LabelPlacer.nudgeCost
            if LabelPlacer.segment(from: tail, to: head,
                                   crosses: [pill.insetBy(dx: -gap / 2, dy: -gap / 2)]) {
                cost += LabelPlacer.crossingCost
            }
            let anchor = slid(probe.captionAttachment(), by: pill, from: wanted)
            let placement = CaptionPlacement(
                attach: CGSize(width: anchor.x - tail.x, height: anchor.y - tail.y),
                growth: spot.growth)
            return LabelCandidate(rect: pill, payload: placement, cost: cost)
        }
        let avoid = [LabelAvoidance(rects: [headZone], weight: .flat(LabelPlacer.subjectCost))]
        guard let best = LabelPlacer.best(among: candidates, avoiding: avoid,
                                          within: bounds) else { return CaptionPlacement() }
        return best
    }

    /// A hand-placed pill's attachment, pulled back onto the picture if the
    /// pill it holds would leave it. The person chose the spot, so nothing else
    /// is second-guessed: it may sit on the shaft or the head.
    public static func keepingOnCanvas(_ offset: CGSize, for content: AnnotationContent,
                                       canvas: CGSize) -> CGSize {
        let bounds = CGRect(origin: .zero, size: canvas)
        let tail = content.start
        var probe = content
        probe.captionOffset = offset
        let wanted = rect(of: probe, size: content.estimatedCaptionSize)
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
