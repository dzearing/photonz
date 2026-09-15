import AppKit
import PhotonzCore
import SwiftUI

// Reshaping a path on the canvas (Next, `next-reshape-a-path`): the points of a
// picked path, the levers that bend it, and the presses that move, add, convert
// and remove them.
//
// Everything that decides WHAT the new shape is lives in `PathContent`
// (PhotonzCore) and is tested there. This file converts between the view and
// the layer's own space, draws the chrome, and hands each finished change to
// the editor as one undo step.
//
// A path shows its points the moment it is picked, rather than hiding them
// behind a mode you have to know about. That is the same bargain a line or an
// arrow already makes in this app: pick it and its two ends are there to drag
// (`Layer.hasEndpointHandles`). A path is that generalised, so the habit
// carries over and nothing new has to be taught.

/// A point or a lever being dragged.
struct PathAnchorDrag {
    let layerID: UUID
    /// The shape as it was when the button went down, in the layer's own
    /// coordinates. Every frame of the drag is worked out from THIS rather
    /// than from the last frame, so a drag cannot drift.
    let original: PathContent
    /// The layer's box when the button went down, which is what the new box is
    /// measured from as the shape grows past its old edges.
    let originalFrame: CGRect
    let target: PathEditTarget
    /// Where the press landed and where the pointer is now, both in the layer's
    /// own untransformed space.
    let start: CGPoint
    var current: CGPoint
    /// The anchors travelling together, for a drag that moves points.
    let moving: Set<Int>
    /// Option: this point's two sides are not tied together.
    var breaking: Bool
    /// Latched once the pointer has really travelled, so a click that wobbles
    /// does not count as a reshape and leaves no undo step.
    var moved: Bool

    /// The shape as it stands right now.
    func reshaped() -> PathContent {
        var content = original
        let delta = CGPoint(x: current.x - start.x, y: current.y - start.y)
        switch target {
        case .anchor, .segment:
            content.moveAnchors(moving, by: delta)
        case .handle(let index, let side):
            content.setHandle(anchor: index, side: side, control: current, breaking: breaking)
        }
        return content
    }
}

extension CanvasNSView {

    // MARK: - What is showing

    /// The path whose points are on the canvas: one picked, with Select or the
    /// PEN in hand, in a release that can reshape one.
    ///
    /// The Pen counts because the Pen STAYS IN HAND after a shape lands
    /// (`EditorState.addPath`), so the moment somebody has just drawn a shape
    /// and wants to round a corner is a moment spent holding the Pen. Asking
    /// for Select there meant the points of the thing you had this second
    /// finished did not exist, with nothing on screen saying why — the whole
    /// of the report on 2026-09-14, "I don't understand how to make curved
    /// shapes, don't know how to delete a point, add a point, reposition a
    /// point".
    ///
    /// The two tools do not fight over the same pixels, because the Pen
    /// ALREADY treats a press on an existing anchor as acting on that anchor
    /// rather than placing a fresh one: clicking the first anchor closes the
    /// shape, clicking the last one finishes it, and a ring says so before you
    /// press (`refreshPenTarget`). A press on a POINT or a LEVER reshapes; a
    /// press anywhere else, the outline included, starts the next shape
    /// exactly as it did before (`CanvasNSView.mouseDown` runs
    /// `pathEditMouseDown` first, and it answers nothing off a point).
    ///
    /// What that costs, said out loud: double clicking the OUTLINE to add a
    /// point cannot work under the Pen, because the first of the two clicks
    /// starts a new path and lets this one go before the second arrives. That
    /// one gesture stays a Select gesture, and the chip under the Pen does not
    /// offer it (`PathEditHint.penOpening`).
    ///
    /// A path inside a copy offers nothing, like every other layer that offers
    /// no handles (`offersOwnHandles`). Neither does one on a SLANT: reshaping
    /// moves the box the shape sits in, a turn is measured about the middle of
    /// that box, and a point dragged out on a turned path would therefore swing
    /// the whole shape round under the hand. Straighten it with the A field and
    /// the points come back — which the chip now SAYS rather than leaving the
    /// points quietly missing (`PathEditHint.turned`).
    var editablePath: (id: UUID, layer: Layer, content: PathContent)? {
        guard Experiments.shared.reshapePathEnabled, toolCanReshapeAPath,
              let id = selectedLayerID, let layer = document?.canvasLayer(id: id),
              let content = layer.path, offersOwnHandles(layer),
              layer.transform.isIdentity else { return nil }
        return (id, layer, content)
    }

    /// Whether the tool in hand is one that shows a picked path its points.
    var toolCanReshapeAPath: Bool {
        tool == .select || (tool == .pen && Experiments.shared.penEnabled)
    }

    /// A press in the layer's own coordinates, measured from its corner.
    private func pathLocalPoint(_ p: CGPoint, layer: Layer) -> CGPoint {
        CGPoint(x: p.x - layer.frame.minX, y: p.y - layer.frame.minY)
    }

    // MARK: - The gesture

    /// A press with a path picked. True when the path took it, which stops the
    /// press from also moving the layer or starting a marquee.
    func pathEditMouseDown(at p: CGPoint, event: NSEvent) -> Bool {
        guard let viewport, let picked = editablePath else { return false }
        let local = pathLocalPoint(p, layer: picked.layer)
        guard let target = picked.content.editTarget(at: local, zoom: viewport.zoom,
                                                     handlesShowing: pathAnchorSelection) else {
            // A press in clear air lets the points go, so the next arrow key
            // moves the layer again rather than a point nobody can see is
            // still picked. The press itself carries on to whatever it would
            // otherwise have done.
            if !pathAnchorSelection.isEmpty {
                pathAnchorSelection = []
                refreshPathEditChrome()
                announcePathEditHint()
            }
            return false
        }
        let option = event.modifierFlags.contains(.option)
        let shift = event.modifierFlags.contains(.shift)
        pathChromeDriftPeak = 0

        // Two clicks in the same place change what a point IS, which is the one
        // gesture a drawing app can count on somebody trying.
        if event.clickCount == 2 {
            return pathEditDoubleClick(target, picked: picked)
        }

        switch target {
        case .anchor(let index):
            if shift {
                if pathAnchorSelection.contains(index) {
                    pathAnchorSelection.remove(index)
                } else {
                    pathAnchorSelection.insert(index)
                }
            } else if !pathAnchorSelection.contains(index) {
                pathAnchorSelection = [index]
            }
            pathAnchorDrag = PathAnchorDrag(
                layerID: picked.id, original: picked.content,
                originalFrame: picked.layer.frame, target: target, start: local, current: local,
                moving: pathAnchorSelection.isEmpty ? [index] : pathAnchorSelection,
                breaking: option, moved: false)
            applyGrabCursor(.closedHand)
        case .handle(let index, let side):
            // Option on a lever WITHOUT dragging it pulls that lever in, so
            // that side of the point runs straight: a point curved on one side
            // and straight on the other, which is what a rounded corner in a
            // real icon is made of. It is the same thing Option does in the
            // Pen, so it only has to be learnt once.
            if option {
                var content = picked.content
                content.clearHandle(anchor: index, side: side)
                commitPathEdit(picked.id, content)
                return true
            }
            pathAnchorDrag = PathAnchorDrag(
                layerID: picked.id, original: picked.content,
                originalFrame: picked.layer.frame, target: target, start: local, current: local,
                moving: [index], breaking: option, moved: false)
            applyGrabCursor(.closedHand)
        case .segment:
            // A press on the outline itself is a press on the SHAPE: it picks
            // the layer up and moves it, exactly as it did before there were
            // any points on it. Adding a point is the double click above.
            return false
        }
        refreshPathEditChrome()
        announcePathEditHint()
        refreshOverlays()
        return true
    }

    /// Two clicks change what the thing under them IS, which is one idiom
    /// answering three questions: on a point, a hard corner becomes a smooth
    /// bend and back; on a LEVER, that lever is pulled in, so that one side of
    /// the point runs straight while the other keeps its curve; on the outline,
    /// a new point lands exactly where they fell.
    ///
    /// The lever is the only one of the three that can name a SIDE, which is
    /// why straightening one side is hung on it. A point cannot: asked to
    /// become half-and-half it has no way to say which half, and a double
    /// click that guesses is a double click you undo.
    private func pathEditDoubleClick(_ target: PathEditTarget,
                                     picked: (id: UUID, layer: Layer, content: PathContent)) -> Bool {
        var content = picked.content
        switch target {
        case .anchor(let index):
            content.toggleAnchorKind(at: index)
            pathAnchorSelection = [index]
        case .handle(let index, let side):
            content.clearHandle(anchor: index, side: side)
            // The point stays picked, so its other lever is still on screen and
            // the chip can say what this point has become.
            pathAnchorSelection = [index]
        case .segment(let run, let at):
            guard let added = content.insertAnchor(onSegment: run, at: at) else { return false }
            pathAnchorSelection = [added]
        }
        commitPathEdit(picked.id, content)
        return true
    }

    func pathEditMouseDragged(to p: CGPoint, event: NSEvent) {
        guard let viewport, var drag = pathAnchorDrag else { return }
        // The layer's box travels with the shape, so the press point has to be
        // measured against the box it was taken in rather than the one under
        // the pointer now.
        let origin = drag.originalFrame.origin
        drag.current = CGPoint(x: p.x - origin.x, y: p.y - origin.y)
        if hypot(drag.current.x - drag.start.x, drag.current.y - drag.start.y)
            * viewport.zoom >= CanvasNSView.pathEditDragThreshold {
            drag.moved = true
        }
        drag.breaking = event.modifierFlags.contains(.option)
        pathAnchorDrag = drag
        guard drag.moved else { return }
        let content = drag.reshaped()
        // The box follows the shape while the drag is in flight, or a point
        // dragged out past the old edge would be drawn cut off and then jump
        // back into place on release.
        selectedLayerFrame = CGRect(origin: CGPoint(x: origin.x + content.bounds.minX,
                                                    y: origin.y + content.bounds.minY),
                                    size: content.bounds.size)
        onPathPreview(drag.layerID, content)
        refreshOverlays()
        // The reading is taken at the END of the frame, after every refresh
        // this frame ran, because the fault being guarded against is a later
        // pass undoing an earlier one.
        pathChromeDriftPeak = max(pathChromeDriftPeak, pathChromeDrift)
    }

    /// The release. True when a path drag was in flight.
    @discardableResult
    func pathEditMouseUp(at p: CGPoint, event: NSEvent) -> Bool {
        guard let drag = pathAnchorDrag else { return false }
        applyGrabCursor(nil)
        // A press that never really moved leaves no undo step behind: it was a
        // click that picked a point, which is not a change to the drawing.
        if drag.moved {
            // The drag is still in hand while this runs, so the chrome the
            // commit draws is the shape the drag ended on rather than the one
            // the document still holds for the moment it takes the committed
            // document to come back round. Nothing jumps on release.
            commitPathEdit(drag.layerID, drag.reshaped())
            pathAnchorDrag = nil
        } else {
            pathAnchorDrag = nil
            refreshPathEditChrome()
            refreshOverlays()
        }
        return true
    }

    /// How far the pointer must travel, ON SCREEN, before a press counts as a
    /// reshape. The same four points the Pen and every other drag in the app
    /// call the difference between a click and a drag.
    static let pathEditDragThreshold: CGFloat = 4

    // MARK: - The keys

    /// Delete with points picked takes THOSE points out rather than the whole
    /// layer. True when the path answered the key.
    ///
    /// With nothing picked it answers nothing, so Delete still deletes the
    /// layer, which is what it means everywhere else.
    func pathEditDeleteKey() -> Bool {
        guard let picked = editablePath, !pathAnchorSelection.isEmpty else { return false }
        var content = picked.content
        guard content.removeAnchors(pathAnchorSelection) else {
            // Down to two points there is no shape left to take from, so the
            // key does nothing rather than quietly deleting the layer out from
            // under a gesture that was aimed at one point.
            return true
        }
        pathAnchorSelection = []
        commitPathEdit(picked.id, content)
        return true
    }

    /// An arrow key with points picked nudges THOSE points, by the same step
    /// every other nudge in the app uses. True when the path answered it.
    func pathEditNudge(by delta: CGPoint) -> Bool {
        guard let picked = editablePath, !pathAnchorSelection.isEmpty else { return false }
        var content = picked.content
        content.moveAnchors(pathAnchorSelection, by: delta)
        commitPathEdit(picked.id, content)
        return true
    }

    /// Escape with points picked lets them go rather than dropping the layer,
    /// so the way back out of reshaping is the key it always is.
    func pathEditEscape() -> Bool {
        guard editablePath != nil, !pathAnchorSelection.isEmpty else { return false }
        pathAnchorSelection = []
        refreshPathEditChrome()
        announcePathEditHint()
        refreshOverlays()
        return true
    }

    private func commitPathEdit(_ id: UUID, _ content: PathContent) {
        guard let layer = document?.canvasLayer(id: id) else { return }
        let box = content.bounds
        selectedLayerFrame = CGRect(x: layer.frame.minX + box.minX,
                                    y: layer.frame.minY + box.minY,
                                    width: box.width, height: box.height)
        onPathEditCommit(id, content)
        refreshPathEditChrome()
        announcePathEditHint(showing: content)
        refreshOverlays()
    }

    /// Tells the chip what to say, and takes it down when no path is showing
    /// its points.
    ///
    /// `showing` is the shape RIGHT NOW when the caller has one the document
    /// has not caught up with yet: a commit hands the canvas its own copy back
    /// through SwiftUI, so asking the document a moment after a gesture gives
    /// the shape as it was before it. That is what left the chip saying "drag a
    /// lever to bend the curve" about a point whose lever had just been pulled
    /// in.
    ///
    /// The same words are never published twice, because this runs on every
    /// overlay pass and the chip is a piece of observed state: setting it to
    /// what it already says would rebuild the editor's chrome for nothing.
    func announcePathEditHint(showing content: PathContent? = nil) {
        let line = pathEditHintLine(showing: content)
        guard line != pathEditHintShowing else { return }
        pathEditHintShowing = line
        onPathEditHintChange(line)
    }

    /// The words that belong on the chip right now, nil when no path is
    /// showing its points.
    private func pathEditHintLine(showing content: PathContent? = nil) -> String? {
        guard let picked = editablePath else { return nil }
        // The one point picked, where there is exactly one, so the chip can say
        // what THAT point is rather than one line for every point there is.
        let shape = content ?? picked.content
        let only = pathAnchorSelection.count == 1 ? pathAnchorSelection.first : nil
        let anchor = only.flatMap { shape.anchors.indices.contains($0) ? shape.anchors[$0] : nil }
        return PathEditHint.line(picked: pathAnchorSelection.count, anchor: anchor,
                                 penInHand: tool == .pen)
    }

    // MARK: - The chrome

    func setUpPathEditChrome() {
        pathAnchorsLayer.isHidden = true
        pathAnchorsLayer.zPosition = 97
        pathAnchorsLayer.lineWidth = 1

        pathPickedAnchorsLayer.isHidden = true
        pathPickedAnchorsLayer.zPosition = 98
        pathPickedAnchorsLayer.lineWidth = 1

        pathLeversLayer.fillColor = nil
        pathLeversLayer.isHidden = true
        pathLeversLayer.zPosition = 97
        pathLeversLayer.lineWidth = 1

        for shape in [pathLeversLayer, pathAnchorsLayer, pathPickedAnchorsLayer] {
            layer?.addSublayer(shape)
        }
    }

    /// Draws the points of the picked path, and the levers of the points that
    /// are picked within it.
    ///
    /// Levers only appear for the points you have picked, which is the whole
    /// answer to a shape disappearing under its own scaffolding: an icon with
    /// twenty points wears twenty small dots rather than twenty dots, forty
    /// arms and forty more dots. It is what Figma does, and it is why you can
    /// still see what you are editing.
    func refreshPathEditChrome() {
        guard let viewport, let picked = editablePath else {
            for shape in [pathLeversLayer, pathAnchorsLayer, pathPickedAnchorsLayer] {
                shape.isHidden = true
                shape.path = nil
            }
            pathChromeShowing = nil
            return
        }
        // A drag in flight is the shape RIGHT NOW; the document is the shape as
        // it was when the button went down, because a preview is rendered and
        // never committed. The drag is asked here rather than handed in by the
        // one caller that knows about it, so that every other way the chrome
        // gets refreshed mid-drag — an overlay pass, a scroll, a zoom, a window
        // resize — draws the same live shape. Handing it in was the bug: the
        // drag drew the live points and the overlay pass right behind it
        // painted the old ones back over them, so the shape bent under a set of
        // points that never moved until the button came up (2026-09-14).
        let drag = pathAnchorDrag.flatMap { $0.layerID == picked.id ? $0 : nil }
        let content = drag?.reshaped() ?? picked.content
        // Where the shape's own coordinates sit in the document. A committed
        // path is normalised against its box (`PathBuilder.refit`), so it is
        // the layer's corner; an in-flight one is still measured from the box
        // the button went down in, which is what the preview is refitted from.
        let origin = drag?.originalFrame.origin ?? picked.layer.frame.origin
        func chromePoint(_ local: CGPoint) -> CGPoint {
            viewport.viewPoint(fromDocument: CGPoint(x: origin.x + local.x,
                                                     y: origin.y + local.y))
        }
        let accent = NSColor.controlAccentColor.cgColor

        // The levers first, so the arms run UNDER the dots rather than across
        // them.
        let levers = CGMutablePath()
        for index in pathAnchorSelection.sorted() where content.anchors.indices.contains(index) {
            let anchor = content.anchors[index]
            let centre = chromePoint(anchor.point)
            for end in [anchor.controlIn, anchor.controlOut] where end != anchor.point {
                let p = chromePoint(end)
                levers.move(to: centre)
                levers.addLine(to: p)
                levers.addEllipse(in: CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7))
            }
        }
        pathLeversLayer.path = levers
        pathLeversLayer.strokeColor = accent
        pathLeversLayer.isHidden = levers.isEmpty

        // Every point, in the same white dot with an accent ring the Pen leaves
        // behind while it draws, so the shape does not change appearance the
        // moment you pick it up.
        let dots = CGMutablePath()
        let pickedDots = CGMutablePath()
        for (index, anchor) in content.anchors.enumerated() {
            let p = chromePoint(anchor.point)
            let isPicked = pathAnchorSelection.contains(index)
            // The same eight points across a frame handle is, because a point
            // is a target of exactly that size (`PathContent.editTargetRadius`)
            // and a dot smaller than its own target is a dot you aim at and
            // miss. A picked one is a little larger again.
            let r: CGFloat = isPicked ? 5 : 4
            let box = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
            // A smooth bend is round and a hard corner is square, so what a
            // point IS can be read off the canvas rather than remembered. A
            // point curved on ONE side is drawn half way between the two,
            // which is what it is. Without a third dot it wears the hard
            // corner's square — it IS a corner by kind, since its two sides
            // are not tied together — and a rounded corner in an icon looks
            // exactly like a sharp one until you drag something.
            //
            // The dot says WHETHER, not WHICH SIDE: the outline itself already
            // shows which run is straight, and a glyph turned to face the
            // straight side read as a diamond at eight points across rather
            // than as anything anybody could name.
            let into = isPicked ? pickedDots : dots
            if anchor.kind == .smooth {
                into.addEllipse(in: box)
            } else if anchor.isHalfSmooth {
                // Half way between the two, because that is what the point is.
                into.addPath(CGPath(roundedRect: box, cornerWidth: r * 0.6,
                                    cornerHeight: r * 0.6, transform: nil))
            } else {
                into.addRect(box)
            }
        }
        pathAnchorsLayer.path = dots
        pathAnchorsLayer.fillColor = NSColor.white.cgColor
        pathAnchorsLayer.strokeColor = accent
        pathAnchorsLayer.isHidden = dots.isEmpty

        // A picked point is filled in the accent instead of hollow: one look
        // says which points an arrow key or Delete is about to reach.
        pathPickedAnchorsLayer.path = pickedDots
        pathPickedAnchorsLayer.fillColor = accent
        pathPickedAnchorsLayer.strokeColor = NSColor.white.cgColor
        pathPickedAnchorsLayer.isHidden = pickedDots.isEmpty

        pathChromeShowing = content
        pathChromeOrigin = origin
        // The chip is told from here as well, because this is the one place
        // that runs whenever the shape changes for ANY REASON — an undo, a
        // redo, a change made from a panel — rather than only after a gesture
        // this file handled.
        //
        // Handed over on the next turn of the runloop, because this also runs
        // inside the canvas's own update pass and the chip is observed state:
        // setting it here and now would be a change made while the views that
        // read it are being built. A gesture does not wait for this — it
        // announces its own result as it commits — so the delay is only ever
        // on a change that came from somewhere else.
        let line = pathEditHintLine(showing: content)
        if line != pathEditHintShowing {
            pathEditHintShowing = line
            DispatchQueue.main.async { [weak self] in self?.onPathEditHintChange(line) }
        }
    }

    // MARK: - Is the chrome on the shape?

    /// How far the points now on screen are from the points of the shape the
    /// canvas is drawing, in screen points: zero when the chrome is on the
    /// shape, and the length of the whole gesture when it is stuck where the
    /// drag began.
    ///
    /// It exists because the lag this measures is invisible to every other
    /// check: the document is right, the render is right, and the picture at
    /// the end of the drag is right. Only a reading taken WHILE the button is
    /// down catches it, which is what `expectChrome` in a walk asks for.
    var pathChromeDrift: CGFloat {
        guard let viewport, let drag = pathAnchorDrag else { return 0 }
        // A drag in flight with no points on screen is as far off the shape as
        // it is possible to be, not zero drift.
        guard let showing = pathChromeShowing else { return .infinity }
        let truth = drag.reshaped()
        guard truth.anchors.count == showing.anchors.count else { return .infinity }
        var worst: CGFloat = 0
        for (index, anchor) in truth.anchors.enumerated() {
            let drawn = showing.anchors[index]
            for (a, b) in [(anchor.point, drawn.point),
                           (anchor.controlIn, drawn.controlIn),
                           (anchor.controlOut, drawn.controlOut)] {
                let here = CGPoint(x: drag.originalFrame.minX + a.x,
                                   y: drag.originalFrame.minY + a.y)
                let there = CGPoint(x: pathChromeOrigin.x + b.x, y: pathChromeOrigin.y + b.y)
                worst = max(worst, hypot(here.x - there.x, here.y - there.y) * viewport.zoom)
            }
        }
        return worst
    }
}
