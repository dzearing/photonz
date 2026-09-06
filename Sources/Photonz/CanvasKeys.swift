import AppKit
import PhotonzCore
import PhotonzRender
import SwiftUI

// Keys the canvas itself answers: nudging what is selected, escaping a drag,
// deleting, and the single-letter tool switches. Split out of CanvasView.swift;
// `CanvasNSView`'s stored properties still live there.

extension CanvasNSView {
    override func keyDown(with event: NSEvent) {
        // Adjusting the grid takes every key the canvas would otherwise act on,
        // so an arrow moves the markers rather than the last layer you happened
        // to have selected, ⏎ finishes the adjustment rather than opening a
        // text box, and ⌫ takes off the guide you are holding.
        if gridAdjust != nil {
            if let delta = Nudge.delta(keyCode: event.keyCode,
                                       large: event.modifierFlags.contains(.shift)) {
                nudgeGridOrigin(by: delta)
                return
            }
            if event.keyCode == 36 || event.keyCode == 76 { // ⏎ / keypad ⏎
                gridOriginDragging = false
                onGridAdjustCommit()
                return
            }
            if event.keyCode == 53 { // ⎋
                gridOriginDragging = false
                onGridAdjustCancel()
                return
            }
            // ⌫ / ⌦ take the guide you are holding off the picture. Nothing is
            // held until you pin one or click one, so there is no way for this
            // to delete a guide you were not looking at.
            if event.keyCode == 51 || event.keyCode == 117 {
                onGuideDelete()
                return
            }
            return
        }
        // Size mode: [ shrinks the pick, ] grows it. A flat screenshot has no
        // element tree, so the first guess is a guess — these two keys are what
        // make a wrong guess a half-second correction instead of a dead end.
        if tool == .measure, measureToolMode.picksAmongCandidates,
           event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
           let characters = event.charactersIgnoringModifiers,
           characters == "[" || characters == "]" {
            let level = max(0, measureCandidateLevel + (characters == "]" ? 1 : -1))
            measureCandidateLevel = level
            onCandidateLevelChange(level)
            refreshMeasureCreation(modifierFlags: event.modifierFlags)
            return
        }
        if tool == .crop, event.keyCode == 36 || event.keyCode == 76 { // ⏎ / keypad ⏎
            cropDrag = nil
            onCropCommit()
            return
        }
        // Enter / Return edits the selected text layer's content (same as a
        // double-click). Only when idle — while the inline editor is up the
        // NSTextView owns Return (newline).
        if event.keyCode == 36 || event.keyCode == 76,
           moveDrag == nil, resizeDrag == nil, transformDrag == nil,
           let id = selectedLayerID, let layer = document?.canvasLayer(id: id), !layer.isLocked,
           case .text = layer.content {
            beginTextSession(layerID: id, at: layer.frame.origin)
            return
        }
        // ⌥⌫ fills the selected layer — or the pixel region — with the
        // foreground color (Photoshop). EditorState routes region vs layer.
        if event.keyCode == 51 || event.keyCode == 117,
           event.modifierFlags.contains(.option),
           selectedLayerID != nil || (selectionTargetsPixels && selection != nil) {
            onFillSelected(false)
            return
        }
        // ⌫ with a pixel region erases the region (or fills the locked
        // Background with the BG color) instead of touching layers.
        if event.keyCode == 51 || event.keyCode == 117,
           selectionTargetsPixels, selection != nil {
            onDeleteRegion()
            return
        }
        // Delete / forward-delete with a marquee multi-selection removes them
        // all (one undo step) — the "sweep around a bunch of annotations and
        // hit ⌫" cleanup gesture.
        if event.keyCode == 51 || event.keyCode == 117, !multiSelectedLayerIDs.isEmpty {
            onDeleteLayers(Array(multiSelectedLayerIDs))
            return
        }
        // ⌫ on the locked Background (which the delete path below skips):
        // reset it to the background fill color — "clear to default".
        if event.keyCode == 51 || event.keyCode == 117,
           let id = selectedLayerID, let layer = document?.canvasLayer(id: id),
           layer.isLocked, layer.imageRef != nil {
            onClearBackground()
            return
        }
        // Delete / forward-delete removes the selected (unlocked) layer.
        if event.keyCode == 51 || event.keyCode == 117,
           let id = selectedLayerID, let layer = document?.canvasLayer(id: id), !layer.isLocked {
            onDeleteLayer(id)
            return
        }
        // How far an arrow key travels. While the grid is pulling it is whole
        // grid cells, so the keys put a layer exactly where a drag would, and
        // ⌘ frees a nudge from the grid the same way it frees a drag.
        let coarseNudge = event.modifierFlags.contains(.shift)
        let nudgeGrid = event.modifierFlags.contains(.command) ? nil : canvasNudgeGrid
        // Arrow keys nudge a whole multi-selection: every picked layer travels
        // the same distance, in ONE undo step, exactly as dragging the
        // selection on the canvas does. Same plan, so a locked layer stays put
        // and a piece inside a picked group is not moved twice. The distance
        // comes from the selection's own corner, so the block lands on the
        // grid rather than each layer drifting onto it separately.
        // This comes first because a multi-selection has no primary layer at
        // all — `selectedLayerID` is nil — so the branch below can never fire.
        if Nudge.isArrow(keyCode: event.keyCode),
           moveDrag == nil, resizeDrag == nil, transformDrag == nil,
           pickedLayerIDs.count > 1,
           let plan = document?.multiLayerDrag(moving: pickedLayerIDs),
           let delta = Nudge.delta(keyCode: event.keyCode, large: coarseNudge,
                                   grid: nudgeGrid, from: plan.bounds.origin) {
            onMoveSelectionCommit(plan.origins(offsetBy: delta), false)
            refreshOverlays()
            return
        }
        // Arrow keys nudge the selected layer.
        if Nudge.isArrow(keyCode: event.keyCode),
           moveDrag == nil, resizeDrag == nil, transformDrag == nil,
           let id = selectedLayerID, let layer = document?.canvasLayer(id: id), !layer.isLocked,
           let delta = Nudge.delta(keyCode: event.keyCode, large: coarseNudge, grid: nudgeGrid,
                                   from: layer.withoutSlack(layer.frame).origin) {
            // The box you see, because that is what every commit out of this
            // view carries (`EditorState.storedCanvasFrame` puts the slack of
            // a text box back).
            let frame = layer.withoutSlack(layer.frame).offsetBy(dx: delta.dx, dy: delta.dy)
            selectedLayerFrame = frame
            onFrameCommit(id, frame)
            refreshOverlays()
            return
        }
        if event.keyCode == 53 { // Esc, in priority order: cancel drag → ants → layer → tool
            if let drag = cropDrag {
                cropDrag = nil
                cropRect = drag.startRect
                refreshOverlays()
                return
            }
            if measurePlacement != nil || alignmentDrag != nil {
                cancelMeasurePlacement()
                refreshOverlays()
                return
            }
            if annotationDrag != nil {
                annotationDrag = nil
                snapGuide = nil
                clearAnnotationPreview()
                refreshOverlays()
                return
            }
            if let session = endpointDrag {
                endpointDrag = nil
                snapGuide = nil
                clearAnnotationPreview()
                // Committing the original endpoints is a History no-op but
                // resets the preview render, like the resize-drag cancel.
                onAnnotationEndpointsCommit(session.layerID, session.originalStart, session.originalEnd)
                refreshOverlays()
                return
            }
            if captionDrag != nil {
                captionDrag = nil
                onCaptionPlaceCancel() // no history was touched; restores the render
                refreshGrabCursor()
                refreshOverlays()
                return
            }
            if let drag = measureHandleDrag {
                measureHandleDrag = nil
                snapGuide = nil
                let (start, end, off, readout) = drag.originalParams()
                onMeasureEndpointCommit(drag.layerID, start, end, off, readout) // History no-op; restores render
                refreshGrabCursor()
                refreshOverlays()
                return
            }
            if let session = transformDrag {
                transformDrag = nil
                // Committing the start transform is a History no-op but resets
                // the preview render.
                onTransformCommit(session.layerID, session.startTransform)
                refreshOverlays()
                return
            }
            if let drag = resizeDrag {
                resizeDrag = nil
                selectedLayerFrame = drag.startFrame
                // Committing the start frame is a History no-op but resets the preview render.
                onFrameCommit(drag.layerID, drag.startFrame)
                refreshOverlays()
                return
            }
            if let drag = moveDrag {
                moveDrag = nil
                applyGrabCursor(nil)
                let frame = CGRect(origin: drag.startOrigin, size: drag.size)
                selectedLayerFrame = frame
                // A copy drag never wrote anything down, so Esc is simply
                // "put the real picture back" — no copy is left behind.
                if drag.copying { onCopyDragCancel() } else { onFrameCommit(drag.layerID, frame) }
                adoptionHost = nil
                refreshOverlays()
                return
            }
            if let drag = multiMove {
                multiMove = nil
                applyGrabCursor(nil)
                if drag.copying {
                    onCopyDragCancel()
                } else {
                    // Putting everything back where it started is a History
                    // no-op, and it resets the preview render.
                    onMoveSelectionCommit(drag.plan.origins(movingBoundsTo: drag.plan.bounds.origin), false)
                }
                adoptionHost = nil
                refreshOverlays()
                return
            }
            if regionContentDrag != nil {
                regionContentDrag = nil
                onRegionMoveCancel()
                refreshOverlays()
                return
            }
            if regionOutlineDrag != nil {
                regionOutlineDrag = nil
                refreshOverlays()
                return
            }
            if regionDrag != nil {
                regionDrag = nil
                snapGuide = nil
                refreshOverlays()
                return
            }
            if marquee != nil || selection != nil {
                marquee = nil
                commitSelection(nil, capture: true)
                return
            }
            // Stepping out of a group comes ahead of clearing the selection:
            // inside one, Escape leaves it with the group selected; only at the
            // top does Escape deselect, the way it always has.
            if onExitGroup() {
                selectedLayerFrame = nil // re-read from the selection that lands
                refreshOverlays()
                return
            }
            if selectedLayerFrame != nil {
                selectedLayerFrame = nil
                onSelectLayer(nil)
                refreshOverlays()
                return
            }
            if tool != .select {
                onToolChange(.select)
                return
            }
        }
        super.keyDown(with: event)
    }
}
