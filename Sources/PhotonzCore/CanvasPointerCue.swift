import CoreGraphics
import Foundation

/// What the pointer should say a press would do, at one point on the canvas.
///
/// Every handle drawn around a selected object is a small target — an eight
/// point square, a dot — sitting on top of a much larger one, the object
/// itself. Without a cue the pointer looks identical over both, so the only
/// way to find out whether the next press resizes or moves is to press and
/// see. This answers first.
public enum CanvasPointerCue: Hashable, Sendable {
    /// Something that drags freely wherever you take it: a caption pill, a
    /// caliper's number or one of its dots, either end of a line or arrow.
    case grab
    /// One of the eight handles round a frame. Which corner or edge decides
    /// which way the pointer's arrows point.
    case resize(ResizeHandle)
    /// The knob floated off the top edge that turns the selection.
    case rotate
}

/// Resolves the pointer cue for a point on the canvas.
///
/// The order here MIRRORS the press precedence in `CanvasView.mouseDown`. That
/// is the whole contract: a cue that offered a resize where a press would have
/// moved the layer would be worse than no cue at all, because it would be
/// confidently wrong about the one thing it exists to answer.
public enum CanvasPointer {
    /// Screen-point slop around the rotate knob, matching the press.
    public static let rotateTolerance: CGFloat = 8

    /// What the pointer should show at `p` (document coordinates) over
    /// `layer`, which must be the SELECTED layer: an unselected object draws
    /// no handles and offers none of these presses.
    ///
    /// `frame` is the selection's live frame (the canvas holds it separately
    /// so it can lead the document during a drag); nil means no frame handles
    /// were offered, so none is cued. `offersRotation` is the same question the
    /// chrome asks before drawing the knob, so the cue and the knob can never
    /// disagree about whether it is there. A locked layer answers nil
    /// everywhere: it offers no handles for a pointer to promise.
    public static func cue(at p: CGPoint, layer: Layer, frame: CGRect?, zoom: CGFloat,
                           captionsEnabled: Bool, offersRotation: Bool) -> CanvasPointerCue? {
        // A locked layer has no handles to cue: the chrome draws none and the
        // press starts nothing, so the pointer stays a plain arrow over all of
        // it. See `Layer.offersHandles`.
        guard layer.offersHandles else { return nil }
        // Endpoint handles come first, and only for annotations: a caliper's
        // feet look like endpoints but the press routes them to the measure
        // branch below, which is where their hand comes from.
        if layer.annotation != nil,
           AnnotationEndpoints.hit(at: p, layer: layer, zoom: zoom) != nil { return .grab }
        // The caption pill, and a caliper's number, feet and head dot.
        if CanvasGrab.hit(at: p, layer: layer, zoom: zoom,
                          captionsEnabled: captionsEnabled) != nil { return .grab }
        // The rotate knob, which floats clear of the top edge and so is never
        // in a frame handle's way.
        if offersRotation, let knob = layer.rotateKnobPoint(zoom: zoom),
           hypot(p.x - knob.x, p.y - knob.y) * zoom <= rotateTolerance { return .rotate }
        // The eight frame handles, found in the layer's own untransformed
        // space so a turned or slanted layer answers where its handles draw.
        guard let frame, layer.allowsFrameResize else { return nil }
        let local = handleSpacePoint(p, layer: layer)
        return Handles.hit(at: local, frame: frame, zoom: zoom).map { .resize($0) }
    }

    /// Screen-point slop around a crop handle, matching the crop press, which
    /// is more generous than a layer's because the crop box has no body to
    /// pick up by: missing a handle there starts drawing a whole new rect.
    public static let cropTolerance: CGFloat = 8

    /// What the pointer should show at `p` (document coordinates) while the
    /// Crop tool holds the canvas.
    ///
    /// The crop press has three outcomes: a handle resizes the box, a press
    /// inside moves it, and a press outside draws a fresh one. Only the first
    /// is invisible beforehand, because a handle is a few points of target
    /// sitting on top of the whole box, so only the first gets a cue. Inside
    /// and outside answer nil and keep the Crop crosshair, which already says
    /// this tool draws and drags.
    ///
    /// The crop box is axis-aligned in document space, so unlike a layer there
    /// is no transform to read the handles through.
    public static func cropCue(at p: CGPoint, cropRect: CGRect?,
                               zoom: CGFloat) -> CanvasPointerCue? {
        guard let cropRect else { return nil }
        return Handles.hit(at: p, frame: cropRect, zoom: zoom,
                           screenTolerance: cropTolerance).map { .resize($0) }
    }

    /// Maps a document point into `layer`'s untransformed frame space, the
    /// same conversion frame-handle hit-testing and resizing use.
    public static func handleSpacePoint(_ p: CGPoint, layer: Layer) -> CGPoint {
        guard !layer.transform.isIdentity else { return p }
        let center = CGPoint(x: layer.frame.midX, y: layer.frame.midY)
        return p.applying(layer.transform.affineTransform(around: center).inverted())
    }
}

extension Layer {
    /// The rotate knob's position in document coordinates: floated off the
    /// midpoint of the (transformed) top edge, 18 screen points out, so it
    /// stays the same distance from the edge at every zoom.
    public func rotateKnobPoint(zoom: CGFloat) -> CGPoint? {
        let corners = transformedCorners
        guard corners.count == 4, zoom > 0 else { return nil }
        let topMid = CGPoint(x: (corners[0].x + corners[1].x) / 2,
                             y: (corners[0].y + corners[1].y) / 2)
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let dx = topMid.x - center.x
        let dy = topMid.y - center.y
        let length = hypot(dx, dy)
        let offset = 18 / zoom
        guard length > 0 else { return CGPoint(x: topMid.x, y: topMid.y - offset) }
        return CGPoint(x: topMid.x + dx / length * offset, y: topMid.y + dy / length * offset)
    }
}

/// The line a resize pointer's arrows point along.
///
/// There are four, not eight: the platform draws ONE pointer per axis, so a
/// frame's top and bottom handles wear the same picture, as do its top-left
/// and bottom-right. Naming the pointer by its axis rather than by the handle
/// that asked for it is the only way to say truthfully what is on screen.
public enum ResizeAxis: String, Hashable, Sendable, CaseIterable {
    case upDown = "up-down"
    case leftRight = "left-right"
    case upLeftDownRight = "up-left-down-right"
    case upRightDownLeft = "up-right-down-left"
}

extension ResizeHandle {
    /// The axis this handle's resize pointer points along.
    public var axis: ResizeAxis {
        switch self {
        case .top, .bottom: .upDown
        case .left, .right: .leftRight
        case .topLeft, .bottomRight: .upLeftDownRight
        case .topRight, .bottomLeft: .upRightDownLeft
        }
    }

    /// The direction this handle points away from the frame's center, as a
    /// unit vector in document space (y grows downward). Corners are the
    /// 45° diagonals, which is also all the platform's resize pointers offer.
    public var outwardVector: CGPoint {
        let x: CGFloat = movesMinX ? -1 : (movesMaxX ? 1 : 0)
        let y: CGFloat = movesMinY ? -1 : (movesMaxY ? 1 : 0)
        let length = hypot(x, y)
        return length > 0 ? CGPoint(x: x / length, y: y / length) : .zero
    }
}

extension Handles {
    /// The handle whose direction matches where `handle` actually SITS once
    /// `transform` has turned, slanted or mirrored the frame.
    ///
    /// The pointer has to agree with your eyes, not with the model: on a layer
    /// turned a quarter of the way round, the handle the app calls "top" is
    /// sitting on the right-hand side, and a pointer pushing up and down there
    /// would just look broken. Snaps to the nearest of the eight directions,
    /// which is the set of resize pointers the platform draws.
    public static func screenHandle(for handle: ResizeHandle,
                                    transform: LayerTransform) -> ResizeHandle {
        guard !transform.isIdentity else { return handle }
        let t = transform.affineTransform(around: .zero)
        let v = handle.outwardVector
        // Linear part only: where the handle sits relative to the center is a
        // direction, so the transform's translation has nothing to say about it.
        let turned = CGPoint(x: v.x * t.a + v.y * t.c, y: v.x * t.b + v.y * t.d)
        guard hypot(turned.x, turned.y) > 1e-9 else { return handle }
        let angle = atan2(turned.y, turned.x)
        var best: (handle: ResizeHandle, distance: CGFloat)?
        for candidate in ResizeHandle.allCases {
            let c = candidate.outwardVector
            var delta = abs(atan2(c.y, c.x) - angle)
            if delta > .pi { delta = 2 * .pi - delta }
            if delta < (best?.distance ?? .infinity) { best = (candidate, delta) }
        }
        return best?.handle ?? handle
    }
}
