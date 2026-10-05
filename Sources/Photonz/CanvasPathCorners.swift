import AppKit
import PhotonzCore

// Rounding a picked path's corners by pulling a knob in from the corner (Next,
// under `next-reshape-a-path`): the live corners Figma and Illustrator have.
//
// With a path picked and the pointer over it, every sharp corner shows a small
// round knob a short way inside it. Pulling one in rounds the corners; pushing
// it back out sharpens them again. All the sharp corners round together, as
// Figma's and Illustrator's do; ⌥ rounds only the one being pulled. The radius
// lands on whole grid steps while the grid pulls, ⌘ frees it, and the pill
// under the shape reads it.
//
// What the knob places and what a pull means are `PathCornerRounding.swift`
// in PhotonzCore, tested there. This file reads the pointer, draws the knobs
// and hands the finished pull to the editor as one undo step.

/// A corner knob being pulled.
struct PathCornerDrag {
    let layerID: UUID
    /// The shape as it was when the button went down. Every frame of the pull
    /// is worked out from this, so it cannot drift.
    let original: PathContent
    /// Where the shape's own coordinates sat at the press.
    let space: PathEditSpace
    /// The corner whose knob is in hand.
    let index: Int
    /// ⌥: only this corner rounds. Read on every move, so the key can be taken
    /// up or let go part way through.
    var oneCorner: Bool
    /// The radius the pull has landed on so far.
    var radius: CGFloat
    /// Latched once the pointer has really travelled, so a click on a knob
    /// leaves no undo step.
    var moved: Bool

    /// The shape as it stands right now.
    func reshaped() -> PathContent {
        var content = original
        if oneCorner {
            content.setCornerRadius(radius, at: index)
        } else {
            content.setCornerRadius(radius)
        }
        return content
    }
}

extension CanvasNSView {

    // MARK: - Where the knobs are

    /// Whether the knobs are offered at all: Select in hand, a path showing
    /// its points. Under the Pen a press inside a shape starts the next shape,
    /// so nothing there may be a knob.
    private var pathCornerKnobsOffered: Bool {
        tool == .select && editablePath != nil
    }

    /// The corner whose knob is under `p` (document coordinates), if any.
    /// Every knob drawn is a target and nothing else is: the press reads the
    /// same knobs the chrome draws.
    func pathCornerKnobHit(at p: CGPoint) -> Int? {
        guard pathCornerKnobsOffered, let viewport, let picked = editablePath,
              pathCornerPointerIsOver(p) else { return nil }
        let local = pathEditSpace(of: picked.layer).local(p)
        return picked.content.cornerKnobHit(at: local, zoom: viewport.zoom)
    }

    /// Whether the pointer at `p` is over the picked path: inside its box, or
    /// a few points outside it, which is when its knobs show.
    private func pathCornerPointerIsOver(_ p: CGPoint) -> Bool {
        guard let viewport, let picked = editablePath else { return false }
        let local = pathEditSpace(of: picked.layer).local(p)
        let slop = PathContent.cornerKnobRest / max(viewport.zoom, 0.01)
        return picked.content.bounds.insetBy(dx: -slop, dy: -slop).contains(local)
    }

    /// Follows the pointer: the knobs come up as it reaches the shape and go
    /// as it leaves, so a picked path with twenty corners is not wearing
    /// twenty extra dots while you look at it from across the canvas.
    func refreshPathCornerHover(at viewPoint: CGPoint?) {
        let over: Bool
        if let viewPoint, let viewport, pathCornerKnobsOffered {
            over = pathCornerPointerIsOver(viewport.documentPoint(fromView: viewPoint))
        } else {
            over = false
        }
        guard over != pathCornerKnobsHovered else { return }
        pathCornerKnobsHovered = over
        refreshPathEditChrome()
    }

    // MARK: - The gesture

    /// A press on a corner knob. True when a knob took it.
    func pathCornerMouseDown(at p: CGPoint, event: NSEvent) -> Bool {
        guard event.clickCount == 1, let picked = editablePath,
              let index = pathCornerKnobHit(at: p) else { return false }
        let content = picked.content
        // The pull starts from what the corner is DRAWN at, so a radius asked
        // for past what the edges hold does not leave a dead stretch to pull
        // through before anything moves.
        pathCornerDrag = PathCornerDrag(
            layerID: picked.id, original: content, space: pathEditSpace(of: picked.layer),
            index: index, oneCorner: event.modifierFlags.contains(.option),
            radius: content.drawnCornerRadius(at: index), moved: false)
        pathCornerKnobsHovered = true
        applyGrabCursor(.closedHand)
        refreshPathEditChrome()
        refreshOverlays()
        return true
    }

    func pathCornerMouseDragged(to p: CGPoint, event: NSEvent) {
        guard let viewport, var drag = pathCornerDrag else { return }
        let zoom = viewport.zoom
        let local = drag.space.local(p)
        drag.oneCorner = event.modifierFlags.contains(.option)
        let asked = drag.original.cornerRadius(draggingKnobAt: drag.index, to: local, zoom: zoom)
        // The most this corner can be drawn: where it meets its neighbours'
        // arcs, all of them rounding with it or each as it stands.
        let limit = drag.original.cornerRadiusLimit(at: drag.index, allCorners: !drag.oneCorner)
        // ⌘ frees the pull from the grid, the key that frees every drag on the
        // canvas (`snapHold`).
        let free = event.modifierFlags.contains(.command)
        let landed = PathContent.landedCornerRadius(
            min(asked, limit), gridSpacing: free ? nil : canvasNudgeGrid?.spacing, zoom: zoom)
        let radius = min(landed, limit)
        if radius != drag.radius || drag.oneCorner != pathCornerDrag?.oneCorner {
            drag.moved = true
        }
        drag.radius = radius
        pathCornerDrag = drag
        guard drag.moved else { return }
        onPathPreview(drag.layerID, drag.reshaped())
        refreshOverlays()
    }

    /// The release. True when a knob was being pulled.
    @discardableResult
    func pathCornerMouseUp(event: NSEvent) -> Bool {
        guard let drag = pathCornerDrag else { return false }
        applyGrabCursor(nil)
        if drag.moved, drag.reshaped() != drag.original {
            // The drag is still in hand while the commit draws the chrome, so
            // the knobs stay where the hand left them.
            commitPathEdit(drag.layerID, drag.reshaped())
        }
        pathCornerDrag = nil
        refreshPathEditChrome()
        refreshOverlays()
        refreshGrabCursor(at: convert(event.locationInWindow, from: nil))
        return true
    }

    // MARK: - The chrome

    /// Draws the knobs inside the picked path's sharp corners, or takes them
    /// away. Called from `refreshPathEditChrome`, with the shape as it stands
    /// right now and the space it is drawn through.
    func refreshPathCornerKnobs(content: PathContent, space: PathEditSpace) {
        let pulling = pathCornerDrag != nil
        guard let viewport, pathCornerKnobsOffered, pathAnchorDrag == nil, pathPointSweep == nil,
              pulling || pathCornerKnobsHovered else {
            pathCornerKnobsLayer.isHidden = true
            pathCornerKnobsLayer.path = nil
            return
        }
        let knobs = CGMutablePath()
        for knob in content.cornerKnobs(zoom: viewport.zoom) {
            // While one is in hand with ⌥, only that corner is moving, so only
            // its knob is drawn: the others would sit still beside a gesture
            // that is not about them.
            if let drag = pathCornerDrag, drag.oneCorner, knob.index != drag.index { continue }
            let p = viewport.viewPoint(fromDocument: space.document(knob.point))
            // The same seven point dot the rectangle's own corner dots wear,
            // so rounding looks like rounding wherever it is done.
            knobs.addEllipse(in: CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7))
        }
        pathCornerKnobsLayer.path = knobs
        pathCornerKnobsLayer.fillColor = NSColor.white.cgColor
        pathCornerKnobsLayer.strokeColor = NSColor.controlAccentColor.cgColor
        pathCornerKnobsLayer.isHidden = knobs.isEmpty
    }
}
