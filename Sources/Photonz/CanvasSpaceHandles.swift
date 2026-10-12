import AppKit
import PhotonzCore

// Tipping, swinging and pushing a picked layer in depth, on the canvas
// (Next, `next-turn-in-depth`; mock `video-depth.html`, design A on the
// decision card `...-how-do-you-turn-a-layer-toward-o`).
//
// The turn knob grows two arcs when the pointer rests on it: drag the flat one
// sideways to swing the layer (Rotation Y), the tall one up or down to tip it
// (Rotation X). The knob itself still turns the layer flat, as it always has.
// An arrow off the layer's pivot pushes it away when dragged up and pulls it
// nearer when dragged down. Shift steps a turn in 15 degree steps, and a pill
// under the layer says the one value the drag is changing.
//
// A layer that is NOT turned in space wears nothing new until the pointer
// rests on its knob, so plain 2D editing, and a marked-up screenshot, look
// exactly as they did. A layer that is turned keeps its depth arrow and a
// crosshair on its pivot, because the pivot is where its turn is taken.
//
// Where everything sits and what a drag does is `SpaceHandles` and `SpaceDrag`
// (PhotonzCore), tested there. This file only finds the three points on
// screen, draws, and hands one finished turn to the editor.

/// A 3D handle in the hand.
struct SpaceHandleDrag {
    let layerID: UUID
    let handle: SpaceHandle
    /// The turn the layer showed when the hand took hold, keys and all.
    let start: LayerTurn3D
    /// Where the press landed, in view points.
    let press: CGPoint
    /// What the drag has made of it so far.
    var turn: LayerTurn3D
    /// Latched once the pointer has really travelled, so a click that wobbles
    /// leaves no undo step behind.
    var moved: Bool
}

/// Where the 3D handles were last drawn, so the press and the pointer cue
/// read exactly what is on screen.
struct DrawnSpaceHandles {
    let layerID: UUID
    let handles: SpaceHandles
    /// The arcs are showing.
    let arcs: Bool
    /// The depth arrow is showing.
    let depth: Bool
    /// The layer is seen in space (the document is), so its knob is where
    /// `handles` put it rather than where the flat knob sits.
    let inSpace: Bool
    /// The layer as drawn, in view points: the arcs stay out while the pointer
    /// is over it.
    let drawn: CGRect
}

extension CanvasNSView {

    /// The three colours of the mock's handles: red tips (X), green swings
    /// (Y), blue pushes in depth (Z), the colours Motion and Final Cut give
    /// the same three axes.
    enum SpaceHandleColour {
        static let tip = CGColor(srgbRed: 1.0, green: 0.42, blue: 0.37, alpha: 1)
        static let swing = CGColor(srgbRed: 0.24, green: 0.81, blue: 0.56, alpha: 1)
        static let depth = CGColor(srgbRed: 0.44, green: 0.61, blue: 1.0, alpha: 1)
        /// A dark rim under each, so they read on a white screenshot and a
        /// dark one alike.
        static let rim = CGColor(gray: 0, alpha: 0.45)
    }

    var spaceHandlesOffered: Bool { Experiments.shared.turnInDepthEnabled && tool == .select }

    func setUpSpaceHandleChrome() {
        for shape in [spaceHandleRimLayer, spaceSwingLayer, spaceTipLayer, spaceDepthLayer,
                      spaceCrosshairLayer] {
            shape.fillColor = nil
            shape.lineCap = .round
            shape.lineJoin = .round
            shape.isHidden = true
            shape.zPosition = 99
            layer?.addSublayer(shape)
        }
        spaceHandleRimLayer.strokeColor = SpaceHandleColour.rim
        spaceHandleRimLayer.lineWidth = 5
        spaceHandleRimLayer.zPosition = 98
        spaceSwingLayer.strokeColor = SpaceHandleColour.swing
        spaceTipLayer.strokeColor = SpaceHandleColour.tip
        spaceDepthLayer.strokeColor = SpaceHandleColour.depth
        // Their widths and the dimming of the ones not under the pointer are
        // `styleSpaceHandles` (`CanvasHandleHover`).
        styleSpaceHandles()
        spaceCrosshairLayer.strokeColor = CGColor(gray: 1, alpha: 0.95)
        spaceCrosshairLayer.lineWidth = 1.5
    }

    func hideSpaceHandles() {
        for shape in [spaceHandleRimLayer, spaceSwingLayer, spaceTipLayer, spaceDepthLayer,
                      spaceCrosshairLayer] where !shape.isHidden {
            shape.isHidden = true
            shape.path = nil
        }
        drawnSpaceHandles = nil
    }

    /// Draws the handles for the picked layer, given where its top edge, its
    /// middle and its pivot landed on screen, and where the flat knob is
    /// (nil for a layer seen in space, whose knob floats off the edge the
    /// camera sees). Returns where the knob is to be drawn.
    @discardableResult
    func drawSpaceHandles(for layer: Layer, topMid: CGPoint, middle: CGPoint, pivot: CGPoint,
                          flatKnob: CGPoint?, drawn: CGRect, turned: Bool) -> CGPoint? {
        let handles = flatKnob.map { knob in
            // Keep the flat knob exactly where it has always been: the arcs
            // grow from it rather than moving it.
            SpaceHandles(topMid: topMid,
                         middle: CGPoint(x: topMid.x - (knob.x - topMid.x), y: topMid.y - (knob.y - topMid.y)),
                         pivot: pivot)
        } ?? SpaceHandles(topMid: topMid, middle: middle, pivot: pivot)
        guard spaceHandlesOffered else {
            hideSpaceHandles()
            // No arcs and no arrow, but a knob that has moved with the layer
            // still has to be caught where it is drawn.
            drawnSpaceHandles = DrawnSpaceHandles(layerID: layer.id, handles: handles, arcs: false,
                                                  depth: false, inSpace: flatKnob == nil, drawn: drawn)
            return handles.knob
        }
        let holding = spaceHandleDrag?.layerID == layer.id
        let arcs = holding ? spaceHandleDrag?.handle != .depth : spaceArcsOutFor == layer.id
        let depth = holding || turned || spaceArcsOutFor == layer.id
        drawnSpaceHandles = DrawnSpaceHandles(layerID: layer.id, handles: handles, arcs: arcs,
                                              depth: depth, inSpace: flatKnob == nil, drawn: drawn)
        let rim = CGMutablePath()
        func put(_ path: CGPath?, on shape: CAShapeLayer) {
            guard let path else {
                shape.isHidden = true
                shape.path = nil
                return
            }
            shape.path = path
            shape.isHidden = false
            rim.addPath(path)
        }
        put(arcs ? Self.arcPath(handles.swingArc) : nil, on: spaceSwingLayer)
        put(arcs ? Self.arcPath(handles.tipArc) : nil, on: spaceTipLayer)
        if depth {
            let arrow = handles.depthArrow
            let path = CGMutablePath()
            path.move(to: arrow.tail)
            path.addLine(to: arrow.head)
            Self.addHead(to: path, at: arrow.head, from: arrow.tail)
            put(path, on: spaceDepthLayer)
        } else {
            put(nil, on: spaceDepthLayer)
        }
        // A crosshair on the pivot of a layer turned in space, unless the
        // motion pivot is already drawing one there.
        if depth, showingMotionPivot?.layerID != layer.id {
            let c = handles.pivot, arm: CGFloat = 9
            let cross = CGMutablePath()
            cross.addEllipse(in: CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10))
            cross.move(to: CGPoint(x: c.x - arm, y: c.y))
            cross.addLine(to: CGPoint(x: c.x + arm, y: c.y))
            cross.move(to: CGPoint(x: c.x, y: c.y - arm))
            cross.addLine(to: CGPoint(x: c.x, y: c.y + arm))
            spaceCrosshairLayer.path = cross
            spaceCrosshairLayer.isHidden = false
            rim.addPath(cross)
        } else {
            spaceCrosshairLayer.isHidden = true
            spaceCrosshairLayer.path = nil
        }
        spaceHandleRimLayer.path = rim
        spaceHandleRimLayer.isHidden = rim.isEmpty
        styleSpaceHandles()
        return handles.knob
    }

    private static func arcPath(_ arc: SpaceHandles.Arc) -> CGPath {
        let path = CGMutablePath()
        path.move(to: arc.start)
        path.addQuadCurve(to: arc.end, control: arc.control)
        // An arrowhead at each end, pointing the way the end travels.
        addHead(to: path, at: arc.start, from: arc.control)
        addHead(to: path, at: arc.end, from: arc.control)
        return path
    }

    /// A small open chevron at `tip`, pointing away from `from`.
    private static func addHead(to path: CGMutablePath, at tip: CGPoint, from: CGPoint) {
        let angle = atan2(tip.y - from.y, tip.x - from.x)
        let size: CGFloat = 5
        for side in [CGFloat(2.5), -2.5] {
            path.move(to: tip)
            path.addLine(to: CGPoint(x: tip.x + cos(angle + side) * size,
                                     y: tip.y + sin(angle + side) * size))
        }
    }

    // MARK: The pointer resting

    /// Brings the arcs out when the pointer rests on the picked layer's knob,
    /// and puts them away once it has left the layer. Called on every pointer
    /// move.
    func refreshSpaceArcs(at viewPoint: CGPoint?) {
        guard spaceHandleDrag == nil else { return }
        let wanted: UUID? = {
            guard spaceHandlesOffered, let viewPoint, let shown = drawnSpaceHandles else { return nil }
            if spaceArcsOutFor == shown.layerID,
               shown.handles.holds(at: viewPoint, over: shown.drawn) { return shown.layerID }
            return shown.handles.reveals(at: viewPoint) ? shown.layerID : nil
        }()
        guard wanted != spaceArcsOutFor else { return }
        spaceArcsOutFor = wanted
        refreshOverlays()
    }

    /// The 3D handle a press at `viewPoint` would take, or nil.
    func spaceHandleHit(atView viewPoint: CGPoint) -> SpaceHandle? {
        guard spaceHandlesOffered, let shown = drawnSpaceHandles, shown.layerID == selectedLayerID,
              let layer = document?.canvasLayer(id: shown.layerID), !layer.isLocked else { return nil }
        return shown.handles.hit(at: viewPoint, arcs: shown.arcs, depth: shown.depth)
    }

    /// Whether `viewPoint` is on the knob of a picked layer seen in space,
    /// which floats off the edge the camera sees rather than the flat one.
    func spaceKnobHit(atView viewPoint: CGPoint) -> Bool {
        guard let shown = drawnSpaceHandles, shown.inSpace, shown.layerID == selectedLayerID else { return false }
        return hypot(viewPoint.x - shown.handles.knob.x, viewPoint.y - shown.handles.knob.y)
            <= CanvasPointer.rotateTolerance
    }

    // MARK: The drag

    /// A press on one of the 3D handles: takes hold and returns true.
    func spaceHandleMouseDown(atView viewPoint: CGPoint) -> Bool {
        guard let handle = spaceHandleHit(atView: viewPoint), let id = selectedLayerID,
              let layer = document?.canvasLayer(id: id) else { return false }
        let start = layer.turn3D ?? LayerTurn3D()
        spaceHandleDrag = SpaceHandleDrag(layerID: id, handle: handle, start: start, press: viewPoint,
                                          turn: start, moved: false)
        applyGrabCursor(.closedHand)
        // The name beside the pointer has said its piece: the pill under the
        // drag carries the value from here.
        hideSpaceLabel()
        refreshOverlays()
        return true
    }

    /// The hand moving with a 3D handle held. True when one is held.
    func spaceHandleMouseDragged(atView viewPoint: CGPoint, event: NSEvent) -> Bool {
        guard var drag = spaceHandleDrag, let viewport else { return false }
        let delta = CGPoint(x: viewPoint.x - drag.press.x, y: viewPoint.y - drag.press.y)
        if hypot(delta.x, delta.y) > 2 { drag.moved = true }
        guard drag.moved else { return true }
        drag.turn = SpaceDrag.turned(drag.start, by: drag.handle, delta: delta, zoom: viewport.zoom,
                                     snapped: event.modifierFlags.contains(.shift),
                                     nearest: nearestDepth)
        spaceHandleDrag = drag
        onSpaceTurnPreview(drag.layerID, drag.turn)
        refreshOverlays()
        return true
    }

    /// Letting go: one undo step, or none for a press that never moved.
    func spaceHandleMouseUp(event: NSEvent) -> Bool {
        guard let drag = spaceHandleDrag else { return false }
        spaceHandleDrag = nil
        if drag.moved, drag.turn != drag.start {
            onSpaceTurnCommit(drag.layerID, drag.turn)
        }
        refreshGrabCursor(at: convert(event.locationInWindow, from: nil))
        refreshOverlays()
        return true
    }

    /// The nearest a layer may come to the camera before it would pass it.
    private var nearestDepth: Double? {
        guard let document else { return nil }
        let projection = document.projection
        guard projection.hasPerspective else { return nil }
        return (projection.eyeDistance - projection.offset.z) * 0.8
    }
}
