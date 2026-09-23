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
    /// Where the shape's own coordinates sat when the button went down: the
    /// box the new box is measured from as the shape grows past its old edges,
    /// and the turn every frame of the drag is read through.
    ///
    /// Taken at the PRESS and held, because both move as the shape grows: a
    /// drag that re-read them each frame would chase its own tail, the same
    /// reason `original` is the shape as it was rather than as it is.
    let space: PathEditSpace
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

/// A box being swept over the points of a path.
///
/// An icon of any real detail has thirty or forty points, and gathering one
/// side of it a ⇧ click at a time is thirty clicks with no mistakes allowed.
/// This is the gesture every drawing tool has had for thirty years: drag a box
/// across the points you want and take them all at once.
struct PathPointSweepDrag {
    let layerID: UUID
    /// Where the shape's own coordinates sat when the press landed, so the
    /// points can be asked where they are ON SCREEN and matched against the
    /// box the hand actually drew.
    let space: PathEditSpace
    /// ⇧: the catch is added to what was already picked.
    let adding: Bool
    /// What was picked when the press landed, which is what an abandoned
    /// sweep puts back.
    let before: Set<Int>
    /// The level the band is latched to, should it turn out to be about the
    /// LAYERS after all: the group you have stepped inside, the screen the
    /// press landed on, or nil out on the canvas. Read at the press, the same
    /// moment the layer band reads it (`marqueeContext`).
    let level: UUID?
    var drag: MarqueeDrag
}

extension CanvasNSView {

    // MARK: - What is showing

    /// The path whose points are on the canvas: one picked, with Select or the
    /// PEN in hand, in a release that can reshape one.
    ///
    /// The Pen counts because a shape gets picked up again with the Pen as
    /// often as with Select: press P over a finished path and its points are
    /// there to round a corner with. Asking for Select meant the points of a
    /// shape under a drawing tool did not exist, with nothing on screen saying
    /// why — the whole of the report on 2026-09-14, "I don't understand how to
    /// make curved shapes, don't know how to delete a point, add a point,
    /// reposition a point". It is NOT conditional on the Pen staying in hand
    /// after a shape lands, which it no longer does (`EditorState.addPath`
    /// hands back to Select like every other tool that makes something); it is
    /// right on its own terms, so nobody who keeps the Pen is stranded.
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
    /// no handles (`offersOwnHandles`).
    ///
    /// A path on a SLANT used to offer nothing either, and the reason was real:
    /// reshaping moves the box the shape sits in, a turn is measured about the
    /// middle of that box, so growing the box moved the point the shape swings
    /// about and took the drawing with it. An icon is full of pieces at an
    /// angle, which made the one shape you most want to round a corner on the
    /// one shape you could not touch. It is answered now rather than refused:
    /// the press is read through the turn, and the new box is placed to cancel
    /// exactly the slide the old pivot caused (`PathEditSpace`).
    var editablePath: (id: UUID, layer: Layer, content: PathContent)? {
        guard Experiments.shared.reshapePathEnabled, toolCanReshapeAPath,
              let id = selectedLayerID, let layer = document?.canvasLayer(id: id),
              let content = layer.path, offersOwnHandles(layer) else { return nil }
        return (id, layer, content)
    }

    /// Whether the tool in hand is one that shows a picked path its points.
    var toolCanReshapeAPath: Bool {
        tool == .select || (tool == .pen && Experiments.shared.penEnabled)
    }

    /// Where a layer's own coordinates sit on the canvas: its corner, its own
    /// turn, and the turn of any card it is inside. The one place this file
    /// asks the question, so a press, a drawn point and a refitted box cannot
    /// disagree about where the shape is.
    func pathEditSpace(of layer: Layer) -> PathEditSpace {
        PathEditSpace(layer: layer, inheritedTurn: inheritedTurn(of: layer.id))
    }

    /// A press in the layer's own coordinates, measured from its corner and
    /// through whatever has turned it.
    private func pathLocalPoint(_ p: CGPoint, layer: Layer) -> CGPoint {
        pathEditSpace(of: layer).local(p)
    }

    // MARK: - The gesture

    /// A press with a path picked. True when the path took it, which stops the
    /// press from also moving the layer or starting a marquee.
    func pathEditMouseDown(at p: CGPoint, event: NSEvent) -> Bool {
        guard let viewport, let picked = editablePath else { return false }
        let local = pathLocalPoint(p, layer: picked.layer)
        guard let target = picked.content.editTarget(
            at: local, zoom: viewport.zoom,
            handlesShowing: PathContent.leversShowing(for: pathAnchorSelection)) else {
            // A press off the shape, where a rubber band would otherwise have
            // started, sweeps a box over the POINTS instead of over the
            // layers. Nothing is let go yet: the release says whether this was
            // a box or a click, and a click in clear air still means what it
            // always did.
            if beginPathPointSweep(at: p, picked: picked, event: event) { return true }
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
                space: pathEditSpace(of: picked.layer),
                target: target, start: local, current: local,
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
                space: pathEditSpace(of: picked.layer),
                target: target, start: local, current: local,
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
        // The layer's box travels with the shape, so the pointer is read in the
        // space the press was taken in rather than the one under it now.
        drag.current = drag.space.local(p)
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
        // back into place on release. On a turned shape it is placed so the
        // rest of the drawing does not slide with it (`steadyFrame`), which is
        // the same box the commit will land on.
        selectedLayerFrame = drag.space.steadyFrame(contentBounds: content.bounds)
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

    // MARK: - Sweeping a box over the points

    /// A press off the shape, with its points showing: starts a box over the
    /// POINTS. True when the sweep took the press.
    ///
    /// The space it claims is the space a rubber band would otherwise have
    /// been drawn in — bare canvas, or the empty surface of a screen — and
    /// nothing else. A press on the outline still picks the shape up, a press
    /// inside a FILLED one still moves it, and a press on another layer still
    /// picks that layer. So the only thing that changed meaning is a band
    /// drawn while a path is showing its points, which could not previously be
    /// drawn at all without throwing the path away first.
    ///
    /// Select only. With the Pen in hand a press off the points starts the
    /// next shape, which is the Pen's whole job and is what its chip promises.
    private func beginPathPointSweep(at p: CGPoint,
                                     picked: (id: UUID, layer: Layer, content: PathContent),
                                     event: NSEvent) -> Bool {
        guard Experiments.shared.reshapePathEnabled, tool == .select, event.clickCount == 1,
              pressWouldDrawABand(at: p) else { return false }
        pathPointSweep = PathPointSweepDrag(
            layerID: picked.id, space: pathEditSpace(of: picked.layer),
            adding: event.modifierFlags.contains(.shift),
            before: pathAnchorSelection,
            level: pathPointSweepLevel(at: p),
            drag: MarqueeDrag(anchor: MarqueeDrag.corner(at: p)))
        refreshOverlays()
        return true
    }

    /// Whether a press here is one that would have started a rubber band: bare
    /// canvas, or the empty surface of a screen (`screenSurfacePress`). Those
    /// are the two places a band belongs, so those are the two places the
    /// point sweep takes over.
    private func pressWouldDrawABand(at p: CGPoint) -> Bool {
        guard let viewport else { return false }
        if groupAwarePick(at: p, zoom: viewport.zoom) == nil { return true }
        if groupSelectionEnabled,
           case .sweep? = document?.screenSurfacePress(
               at: p, zoom: viewport.zoom, picked: pickedLayerIDs,
               captionPillSize: Self.captionPillSizing) {
            return true
        }
        return false
    }

    /// Which list a band started here would pick from, were it to turn out to
    /// be about the layers: the screen it was drawn on, or the group you have
    /// stepped inside, or the top level. Word for word what the layer band
    /// latches at its own press (`marqueeContext`).
    private func pathPointSweepLevel(at p: CGPoint) -> UUID? {
        guard groupSelectionEnabled else { return nil }
        if let viewport, groupAwarePick(at: p, zoom: viewport.zoom) == nil { return groupContext }
        if let viewport,
           case .sweep(let screen)? = document?.screenSurfacePress(
               at: p, zoom: viewport.zoom, picked: pickedLayerIDs,
               captionPillSize: Self.captionPillSizing) {
            return screen
        }
        return groupContext
    }

    /// The band on screen, read the way the LAYER band reads it: clamped to
    /// the canvas, and nil when it is too small to have gone round anything.
    private func pathPointSweepLayerBand(_ sweep: PathPointSweepDrag) -> CGRect? {
        guard let viewport else { return nil }
        return sweep.drag.selectionRect(in: viewport.documentSize)
    }

    /// The layers this band has gone right round, the shape whose points are
    /// showing excepted. Non-empty means the band is about the LAYERS, and
    /// that is the whole of how the two gestures are told apart
    /// (`PhotonzDocument.layerIDs(swept:besides:inside:)`).
    func pathPointSweepLayerCatch(_ sweep: PathPointSweepDrag) -> [UUID] {
        guard let document, let band = pathPointSweepLayerBand(sweep) else { return [] }
        return document.layerIDs(swept: band, besides: sweep.layerID, inside: sweep.level)
    }

    /// The box as it grows. The points it has caught so far are picked LIVE,
    /// so the answer is on the shape before the button comes up rather than
    /// after it.
    func pathPointSweepDragged(to p: CGPoint) {
        guard var sweep = pathPointSweep else { return }
        sweep.drag.update(to: MarqueeDrag.corner(at: p))
        pathPointSweep = sweep
        // Once the box has gone right round something else it is a LAYER band,
        // and it says so while it is still in flight: the points it had
        // gathered are handed back, the outlines of what it holds come up, and
        // the band takes the look the layer band wears (`CanvasDisplay`). So
        // nothing about letting go is a surprise.
        pathAnchorSelection = pathPointSweepLayerCatch(sweep).isEmpty
            ? PathPointSweep.selection(caught: pathPointSweepCatch(sweep),
                                       startingFrom: sweep.before,
                                       adding: sweep.adding)
            : sweep.before
        refreshPathEditChrome()
        refreshOverlays()
    }

    /// The release. True when a sweep was in flight.
    ///
    /// A box that never travelled is a click in clear air, and it still means
    /// everything it has always meant: the points are let go, and so is the
    /// layer, so one click off the shape is still the way out of reshaping.
    @discardableResult
    func pathPointSweepMouseUp(atZoom zoom: CGFloat) -> Bool {
        guard let sweep = pathPointSweep else { return false }
        pathPointSweep = nil
        if sweep.drag.isClick(atZoom: zoom) {
            pathAnchorSelection = []
            refreshPathEditChrome()
            announcePathEditHint()
            // ⇧ takes nothing away, on a path's points as on anything else, so
            // a ⇧ click that missed leaves both the points and the layer
            // exactly as they were.
            guard !sweep.adding else {
                refreshOverlays()
                return true
            }
            // A plain click off the shape is the gesture that means "nothing",
            // and it means it at both levels: the points let go, and so does
            // the layer. Word for word what a click on bare canvas does when
            // no path is showing its points (`mouseUp`), so one click is still
            // the whole way out of reshaping.
            selectedLayerFrame = nil
            onSelectLayer(nil)
            commitSelection(nil, capture: true)
            return true
        }
        // A band that went right round something else on the canvas is the
        // gesture everybody already knows, so it does what it has always done:
        // those layers are picked up, and the shape whose points were showing
        // lets go with them. Before this the points took every band drawn
        // anywhere, so one picked path made sweeping up layers impossible
        // (switch-says-mixed-walk, 2026-09-19).
        if let band = pathPointSweepLayerBand(sweep), !pathPointSweepLayerCatch(sweep).isEmpty {
            pathAnchorSelection = []
            refreshPathEditChrome()
            announcePathEditHint()
            let region = SelectionRegion.rect(Geometry.pixelAligned(band))
            if sweep.adding {
                // ⇧ adds the catch to what was already picked, exactly as a
                // ⇧-band drawn anywhere else does. The band itself comes down:
                // it describes this sweep and not the whole selection.
                if let region {
                    if !selectionTargetsPixels { selection = nil }
                    onAddSweptLayers(region, sweep.level)
                } else {
                    refreshOverlays()
                }
                return true
            }
            // A plain band replaces. The press kept its hands off the
            // selection, so letting go of the old pick happens here.
            onClickedNothing()
            selectedLayerFrame = nil
            commitSelection(region, capture: true, inside: sweep.level)
            return true
        }
        pathAnchorSelection = PathPointSweep.selection(caught: pathPointSweepCatch(sweep),
                                                       startingFrom: sweep.before,
                                                       adding: sweep.adding)
        refreshPathEditChrome()
        announcePathEditHint()
        refreshOverlays()
        return true
    }

    /// Lets go of a sweep in flight and puts back what was picked before it,
    /// which is what Escape means everywhere else a drag can be abandoned.
    @discardableResult
    func pathPointSweepCancel() -> Bool {
        guard let sweep = pathPointSweep else { return false }
        pathPointSweep = nil
        pathAnchorSelection = sweep.before
        refreshPathEditChrome()
        announcePathEditHint()
        refreshOverlays()
        return true
    }

    /// The points inside the box right now: the band is the upright box the
    /// hand drew, and it takes the points it visibly goes round, so a turned
    /// shape answers a sweep the same way a straight one does.
    private func pathPointSweepCatch(_ sweep: PathPointSweepDrag) -> Set<Int> {
        guard let content = document?.canvasLayer(id: sweep.layerID)?.path else { return [] }
        return content.anchorIndices(in: pathPointSweepRect(sweep), of: sweep.space)
    }

    /// The box on the canvas right now, in document coordinates.
    ///
    /// Not `MarqueeDrag.selectionRect`, which is the LAYER band's answer: that
    /// one clamps to the canvas and calls a box of no height empty, and a
    /// sweep straight across a row of points is exactly a box of no height. A
    /// line drawn through three points is a gesture that means those three
    /// points, and a path can reach past the edge of the canvas besides.
    func pathPointSweepRect(_ sweep: PathPointSweepDrag) -> CGRect {
        CGRect(x: sweep.drag.anchor.x, y: sweep.drag.anchor.y,
               width: sweep.drag.current.x - sweep.drag.anchor.x,
               height: sweep.drag.current.y - sweep.drag.anchor.y).standardized
    }

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
        // The key means the way it points, on the canvas: a point of a shape
        // turned thirty degrees goes UP when you press up, rather than up the
        // shape's own grain, which on a turn is up and sideways at once.
        content.moveAnchors(pathAnchorSelection,
                            by: pathEditSpace(of: picked.layer).localVector(delta))
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
        // The same box the refit will give it, turned shape included, so the
        // outline does not step sideways between here and the document coming
        // back round (`PathBuilder.refit`).
        selectedLayerFrame = pathEditSpace(of: layer).steadyFrame(contentBounds: content.bounds)
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
    /// Levers only appear for the ONE point you have picked, which is the
    /// whole answer to a shape disappearing under its own scaffolding: an icon
    /// with twenty points wears twenty small dots rather than twenty dots,
    /// forty arms and forty more dots. It is what Figma does, and it is why
    /// you can still see what you are editing.
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
        // Where the shape's own coordinates sit on the canvas. A committed path
        // is normalised against its box (`PathBuilder.refit`), so it is the
        // layer's own space; an in-flight one is still measured from the box
        // the button went down in, which is what the preview is refitted from.
        // Either way the turn on it is part of the answer, or the dots would
        // sit in a straight square beside the shape they belong to.
        let space = drag?.space ?? pathEditSpace(of: picked.layer)
        func chromePoint(_ local: CGPoint) -> CGPoint {
            viewport.viewPoint(fromDocument: space.document(local))
        }
        let accent = NSColor.controlAccentColor.cgColor

        // The levers first, so the arms run UNDER the dots rather than across
        // them. They belong to ONE picked point: a box that sweeps up thirty
        // of them would otherwise bury the shape under sixty arms and sixty
        // more dots (`PathContent.leversShowing`), which is the very thing
        // drawing them per picked point avoids.
        let levers = CGMutablePath()
        let showingLevers = PathContent.leversShowing(for: pathAnchorSelection)
        for index in showingLevers.sorted() where content.anchors.indices.contains(index) {
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
        pathChromeSpace = space
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
                let here = drag.space.document(a)
                let there = pathChromeSpace.document(b)
                worst = max(worst, hypot(here.x - there.x, here.y - there.y) * viewport.zoom)
            }
        }
        return worst
    }
}
