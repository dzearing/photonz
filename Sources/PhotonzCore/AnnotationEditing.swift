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
    /// magnification from the new frame; other content just moves.
    public func resized(to frame: CGRect) -> Layer {
        if annotation != nil { return AnnotationBuilder.resized(self, to: frame) }
        if measure != nil { return MeasureBuilder.resized(self, to: frame) }
        if zoomCallout != nil { return ZoomCalloutBuilder.resized(self, to: frame) }
        var layer = self
        layer.frame = frame
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
                                strokeWidth: CGFloat? = nil,
                                arrowheadScale: CGFloat? = nil,
                                cornerRadius: CGFloat? = nil,
                                fillColorHex: String?? = nil,
                                caption: String?? = nil,
                                captionFontSize: CGFloat? = nil) -> Layer {
        guard var a = layer.annotation,
              let start = layer.annotationEndpoint(.start),
              let end = layer.annotationEndpoint(.end) else { return layer }
        if let colorHex { a.colorHex = colorHex }
        if let strokeWidth { a.strokeWidth = strokeWidth }
        if let arrowheadScale { a.arrowheadScale = arrowheadScale }
        if let cornerRadius { a.cornerRadius = cornerRadius }
        if let fillColorHex { a.fillColorHex = fillColorHex }
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
        let offset: CGSize?
        if a.captionPinned, let pinned = a.captionOffset {
            offset = CaptionPlanner.keepingOnCanvas(pinned, for: probe, canvas: canvas)
        } else {
            offset = CaptionPlanner.plan(for: probe, canvas: canvas)
        }
        guard offset != a.captionOffset else { return layer }
        var content = a
        content.captionOffset = offset
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
        content.captionOffset = CGSize(width: center.x - tail.x, height: center.y - tail.y)
        var updated = layer
        updated.content = .annotation(content)
        // Rebuild the frame around the new spot even without a canvas to clamp
        // against, then clamp when there is one.
        guard let end = layer.annotationEndpoint(.end) else { return layer }
        return planningCaption(updating(updated, start: tail, end: end), canvas: canvas)
    }

    /// Hands a hand-placed pill back to the planner: the automatic spot again.
    public static func releasingCaption(_ layer: Layer, canvas: CGSize?) -> Layer {
        guard let a = layer.annotation, a.captionPinned,
              let start = layer.annotationEndpoint(.start),
              let end = layer.annotationEndpoint(.end) else { return layer }
        var content = a
        content.captionPinned = false
        content.captionOffset = nil
        var updated = layer
        updated.content = .annotation(content)
        return planningCaption(updating(updated, start: start, end: end), canvas: canvas)
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
    /// Nil when the default spot behind the tail fits the canvas; otherwise
    /// the pill center relative to the tail. Candidates, in order: the default
    /// spot slid back onto the picture, then above, below, left of and right of
    /// the tail (each slid onto the picture). Sitting on the head costs more
    /// than any lower-ranked spot, and sitting on the shaft more than the rank
    /// gap, so the label never hides what the arrow is pointing at.
    public static func plan(for content: AnnotationContent, canvas: CGSize) -> CGSize? {
        let bounds = CGRect(origin: .zero, size: canvas)
        let size = content.estimatedCaptionSize
        var free = content
        free.captionOffset = nil
        let defaultAnchor = free.captionAnchor()
        if bounds.contains(rect(at: defaultAnchor, size: size)) { return nil }

        let tail = content.start
        let head = content.end
        let gap = AnnotationContent.captionGap
        let spots = [
            defaultAnchor,
            CGPoint(x: tail.x, y: tail.y - gap - size.height / 2),
            CGPoint(x: tail.x, y: tail.y + gap + size.height / 2),
            CGPoint(x: tail.x - gap - size.width / 2, y: tail.y),
            CGPoint(x: tail.x + gap + size.width / 2, y: tail.y),
        ]
        // What the arrow is POINTING AT is the subject: the pill may never sit
        // on it. Its own shaft is softer — a pill on the shaft still reads as
        // this arrow's, it just crowds the line — so it is priced like any
        // other leader running through something.
        let headRadius = content.strokeWidth * 3 * content.arrowheadScale + gap
        let headZone = CGRect(x: head.x - headRadius, y: head.y - headRadius,
                              width: 2 * headRadius, height: 2 * headRadius)
        let candidates = spots.enumerated().map { rank, spot -> LabelCandidate<CGPoint> in
            let anchor = slidOntoCanvas(spot, size: size, bounds: bounds)
            let pill = rect(at: anchor, size: size)
            var cost = CGFloat(rank) * LabelPlacer.rankCost
            if LabelPlacer.segment(from: tail, to: head,
                                   crosses: [pill.insetBy(dx: -gap / 2, dy: -gap / 2)]) {
                cost += LabelPlacer.crossingCost
            }
            return LabelCandidate(rect: pill, payload: anchor, cost: cost)
        }
        let avoid = [LabelAvoidance(rects: [headZone], weight: .flat(LabelPlacer.subjectCost))]
        guard let best = LabelPlacer.best(among: candidates, avoiding: avoid,
                                          within: bounds) else { return nil }
        return CGSize(width: best.x - tail.x, height: best.y - tail.y)
    }

    /// A hand-placed pill's offset, pulled back onto the picture if the spot
    /// (`offset` from the tail) would leave it. The person chose the spot, so
    /// nothing else is second-guessed: it may sit on the shaft or the head.
    public static func keepingOnCanvas(_ offset: CGSize, for content: AnnotationContent,
                                       canvas: CGSize) -> CGSize {
        let bounds = CGRect(origin: .zero, size: canvas)
        let tail = content.start
        let anchor = slidOntoCanvas(CGPoint(x: tail.x + offset.width, y: tail.y + offset.height),
                                    size: content.estimatedCaptionSize, bounds: bounds)
        return CGSize(width: anchor.x - tail.x, height: anchor.y - tail.y)
    }

    private static func rect(at anchor: CGPoint, size: CGSize) -> CGRect {
        CGRect(x: anchor.x - size.width / 2, y: anchor.y - size.height / 2,
               width: size.width, height: size.height)
    }

    /// The nearest center that keeps a `size` pill inside `bounds` (the pill's
    /// own center when it already fits, the canvas center when it never can).
    private static func slidOntoCanvas(_ anchor: CGPoint, size: CGSize, bounds: CGRect) -> CGPoint {
        func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
            lo <= hi ? min(max(v, lo), hi) : (lo + hi) / 2
        }
        return CGPoint(x: clamp(anchor.x, bounds.minX + size.width / 2, bounds.maxX - size.width / 2),
                       y: clamp(anchor.y, bounds.minY + size.height / 2, bounds.maxY - size.height / 2))
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
