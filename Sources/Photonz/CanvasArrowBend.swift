import AppKit
import PhotonzCore

// Bending an arrow by its middle (Next, `next-arrow-bend`).
//
// A picked arrow wears a smaller handle halfway along its line. Drag it and
// the arrow curves through it, the head turning to follow; let go back on the
// straight line, double click it, or pick Straighten Arrow and it is straight
// again. ⇧ keeps the handle on the line square across the middle, so the curve
// stays an even arc. The drag rides the endpoint drag's session (a session with
// `bendHandle` set), so cancelling with Esc, the held preview after letting go
// and every "is a drag in flight" check already know about it.
//
// The model is `ArrowBend` in PhotonzCore: the handle's spot is stored against
// the straight line between the ends, so moving an end keeps the curve's shape.

extension CanvasNSView {
    /// How close to the straight line, in screen points, a handle let go
    /// counts as on it.
    static let bendStraightensWithin: CGFloat = 6

    /// The selected layer's bend handle in document coordinates, when it is
    /// offered: arrows only, at Next defaults, and only when the handle would
    /// sit clear of both end handles (on a short arrow the ends win).
    func offeredBendHandle(_ layer: Layer) -> CGPoint? {
        guard Experiments.shared.arrowBendEnabled, offersOwnHandles(layer), !layer.isLocked,
              let handle = layer.bendHandle, let viewport,
              let start = layer.annotationEndpoint(.start),
              let end = layer.annotationEndpoint(.end) else { return nil }
        let clear = min(hypot(handle.x - start.x, handle.y - start.y),
                        hypot(handle.x - end.x, handle.y - end.y)) * viewport.zoom
        return clear >= 20 ? handle : nil
    }

    /// A press on the selected arrow's bend handle. A double click straightens
    /// it; a single press starts a bend. True when the press was taken.
    func beginBendDrag(at q: CGPoint, event: NSEvent) -> Bool {
        guard let id = selectedLayerID, let viewport,
              let layer = document?.canvasLayer(id: id),
              let handle = offeredBendHandle(layer),
              AnnotationEndpoints.bendHit(at: q, layer: layer, zoom: viewport.zoom),
              let content = layer.annotation,
              let drag = AnnotationEndpointDrag(layer: layer, endpoint: .end),
              let start = layer.annotationEndpoint(.start),
              let end = layer.annotationEndpoint(.end) else { return false }
        if event.clickCount >= 2 {
            guard content.bend != nil else { return true }
            onArrowBendCommit(id, CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2),
                              .infinity)
            refreshOverlays()
            return true
        }
        var session = EndpointDragSession(layerID: id, content: content,
                                          originalStart: start, originalEnd: end, drag: drag)
        session.bendHandle = handle
        session.bendHandleStart = handle
        endpointDrag = session
        applyGrabCursor(.closedHand)
        onDragBegin(id)
        refreshEndpointPreview(constrained: false)
        refreshOverlays()
        return true
    }

    /// Where the handle goes for a pointer at `u`: the pointer, or with ⇧ the
    /// nearest point on the line square across the middle of the arrow.
    func bendHandlePoint(_ u: CGPoint, session: EndpointDragSession, even: Bool) -> CGPoint {
        guard even else { return u }
        let s = session.originalStart, e = session.originalEnd
        let dx = e.x - s.x, dy = e.y - s.y
        let length = hypot(dx, dy)
        guard length > 0 else { return u }
        let mid = CGPoint(x: (s.x + e.x) / 2, y: (s.y + e.y) / 2)
        let nx = -dy / length, ny = dx / length
        let across = (u.x - mid.x) * nx + (u.y - mid.y) * ny
        return CGPoint(x: mid.x + nx * across, y: mid.y + ny * across)
    }

    /// The tolerance a let-go handle is judged with, in document points.
    var bendStraightTolerance: CGFloat {
        guard let zoom = viewport?.zoom, zoom > 0 else { return Self.bendStraightensWithin }
        return Self.bendStraightensWithin / zoom
    }

    /// The content a bend drag previews: the arrow between its document-space
    /// ends, curved through the handle where it is now.
    func bendPreviewContent(_ session: EndpointDragSession) -> AnnotationContent {
        var content = session.content
        content.start = session.originalStart
        content.end = session.originalEnd
        if let handle = session.bendHandle {
            content.bend = content.bend(through: handle, straightWithin: bendStraightTolerance)
        }
        return content
    }
}
