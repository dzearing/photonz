import AppKit
import PhotonzCore
import PhotonzRender
import SwiftUI

// What the pointer says before you press: hover tracking, the grab cue for a
// caption pill or caliper handle, the copy badge, and the cursor each tool
// paints over the canvas. Split out of CanvasView.swift; `CanvasNSView`'s
// stored properties still live there.

extension CanvasNSView {
    // MARK: Hover snap dot (measure tool)

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseMoved, .mouseEnteredAndExited,
                                            .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        // While the grid is being adjusted nothing on the canvas is hoverable:
        // no name label lights up, no handle offers itself. What the pointer
        // does instead is light the grid line a click would pin a guide onto.
        if gridAdjust != nil {
            refreshGuideHighlight(at: convert(event.locationInWindow, from: nil))
            refreshGrabCursor(at: convert(event.locationInWindow, from: nil))
            return
        }
        handleMeasureHover(event)
        refreshNameLabelHover(at: convert(event.locationInWindow, from: nil))
        refreshGrabCursor(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        hoverPoint = nil
        refreshNameLabelHover(at: nil)
        applyGrabCursor(nil)
        if tool == .measure { refreshMeasureCreation(modifierFlags: event.modifierFlags) }
    }

    // MARK: Pointer cue (what every handle says it does)


    /// What a press at `p` (document coords) would take hold of, for cue
    /// purposes: a caption pill, or a caliper's number, feet or head dot, on
    /// the SELECTED layer. Nil for every other press.
    func grabCue(at p: CGPoint) -> CanvasGrab? {
        guard Experiments.shared.grabCueEnabled, tool == .select, let viewport,
              let layer = selectedLayerID.flatMap({ id in document?.canvasLayer(id: id) })
        else { return nil }
        return CanvasGrab.hit(at: p, layer: layer, zoom: viewport.zoom,
                              captionsEnabled: Experiments.shared.arrowCaptionsEnabled,
                              captionPillSize: layer.measuredCaptionPillSize)
    }

    /// What a press at `p` (document coords) would do, and the transform to
    /// read it through — the whole answer the pointer gives, for every handle
    /// on the canvas rather than just the ones you drag with a hand.
    ///
    /// The order MIRRORS `mouseDown`: the canvas's own boundary handles are
    /// captured before anything else, then the selected layer's handles in
    /// `CanvasPointer`'s order. A cue that ran ahead of the press would be
    /// confidently wrong about the one thing it exists to answer.
    private func pointerCue(at p: CGPoint) -> (cue: CanvasPointerCue, transform: LayerTransform)? {
        guard Experiments.shared.grabCueEnabled, let viewport else { return nil }
        // Crop is its own mode with its own pointer, and its crosshair keeps
        // every spot the crosshair is still true of: inside the box, where a
        // press moves it, and outside, where a press draws a fresh one. It
        // gives way only on the eight handles, which are the one press you
        // cannot see coming. The box is axis-aligned, so no transform.
        if tool == .crop {
            return CanvasPointer.cropCue(at: p, cropRect: cropRect, zoom: viewport.zoom)
                .map { ($0, .identity) }
        }
        guard tool == .select else { return nil }
        if isCanvasSelected,
           let handle = Handles.hit(at: p, frame: CGRect(origin: .zero, size: viewport.documentSize),
                                    zoom: viewport.zoom, screenTolerance: 8) {
            return (.resize(handle), .identity)
        }
        guard let layer = selectedLayerID.flatMap({ id in document?.canvasLayer(id: id) })
        else { return nil }
        // No live frame means no frame handles were offered, so none is cued.
        let cue = CanvasPointer.cue(at: p, layer: layer, frame: selectedLayerFrame,
                                    zoom: viewport.zoom,
                                    captionsEnabled: Experiments.shared.arrowCaptionsEnabled,
                                    offersRotation: offersRotation(layer),
                                    captionPillSize: layer.measuredCaptionPillSize)
        return cue.map { ($0, layer.transform) }
    }

    /// Whether this event asks for the drag to leave the original behind and
    /// carry a copy (⌥, the Photoshop and Figma gesture). Select only: every
    /// other tool has its own meaning for ⌥, and the ones on the canvas that
    /// do — skewing from a corner handle, the region tools — are read before
    /// a layer drag can ever start.
    func copyDragModifier(_ event: NSEvent) -> Bool {
        tool == .select && event.modifierFlags.contains(.option)
    }

    /// Whether a press at `p` (document coords) would start a layer drag that
    /// ⌥ could copy: something pickable, and not one of the selected layer's
    /// own handles, where ⌥ already means skew.
    private func copyDragCue(at p: CGPoint) -> Bool {
        guard tool == .select, let viewport,
              groupAwarePick(at: p, zoom: viewport.zoom) != nil else { return false }
        let selected = selectedLayerID.flatMap { id in document?.canvasLayer(id: id) }
        guard let frame = selectedLayerFrame, selected?.allowsFrameResize ?? true,
              Handles.hit(at: handleSpacePoint(p, layer: selected),
                          frame: frame, zoom: viewport.zoom) != nil else { return true }
        return false
    }

    /// Every handle on the canvas says what it does before you press it: an
    /// open hand over the parts that drag on their own (a pill, one of a
    /// caliper's dots, either end of a line), the platform's resize arrows over
    /// the eight handles round a frame, and a curved arrow over the rotate
    /// knob. Nothing else on the canvas says a small square on top of a big
    /// object is a different press, so this is the whole invitation.
    ///
    /// A drag in flight keeps the pointer it started with — the hand closes,
    /// resize and rotate hold — so nothing switches under way. That is why
    /// every drag session bails out here rather than re-reading the pointer.
    func refreshGrabCursor(at viewPoint: CGPoint? = nil) {
        // Adjusting the grid owns the pointer: an open hand over the zero
        // point's own markers, and a crosshair everywhere else, where a click
        // pins or picks up a guide.
        if gridAdjust != nil {
            let where_ = viewPoint
                ?? window.map { convert($0.mouseLocationOutsideOfEventStream, from: nil) }
            let doc = where_.flatMap { point in viewport?.documentPoint(fromView: point) }
            return applyGrabCursor(doc.flatMap { gridAdjustCursor(at: $0) } ?? .crosshair,
                                   force: true)
        }
        guard captionDrag == nil, measureHandleDrag == nil, resizeDrag == nil,
              endpointDrag == nil, transformDrag == nil, canvasResizeDrag == nil,
              cropDrag == nil else { return }
        let point = viewPoint ?? window.map { convert($0.mouseLocationOutsideOfEventStream, from: nil) }
        guard let viewport, let point, bounds.contains(point) else { return applyGrabCursor(nil) }
        let doc = viewport.documentPoint(fromView: point)
        let hit = pointerCue(at: doc)
        #if PHOTONZ_PLAYTEST
        recordPlaytestCue(hit)
        #endif
        if let hit {
            return applyGrabCursor(CanvasCursor.cursor(for: hit.cue, transform: hit.transform))
        }
        // Nothing on the canvas says a drag can leave a copy behind, so the
        // badged pointer is the whole invitation: hold ⌥ over a layer and the
        // cursor answers before you have pressed anything.
        applyGrabCursor(pointerModifiers.contains(.option) && copyDragCue(at: doc) ? .dragCopy : nil)
    }

    /// Forces `cursor` onto the pointer, or gives it back. Only a CHANGE
    /// touches `NSCursor`: mouseMoved fires constantly and re-setting the same
    /// cursor flickers it on some setups. `force` overrides that for the one
    /// case where nothing here changed but the pointer still has to be re-read:
    /// a TOOL switch, where the crosshair on screen belongs to the tool being
    /// put down and no cue of ours is holding it.
    func applyGrabCursor(_ cursor: NSCursor?, force: Bool = false) {
        guard force || cursor !== grabCursor else { return }
        grabCursor = cursor
        if let cursor {
            cursor.set()
        } else {
            // Hand the pointer back to whatever the tool asks for.
            window?.invalidateCursorRects(for: self)
            (toolCursor ?? .arrow).set()
        }
    }

    override func resetCursorRects() {
        if let toolCursor { addCursorRect(bounds, cursor: toolCursor) }
    }

    /// The cursor the ACTIVE TOOL paints over the whole canvas, or nil when it
    /// leaves the plain arrow (Select, Fill). The grab cue restores this when
    /// the pointer leaves a pill, so a hand never lingers over a crosshair tool.
    private var toolCursor: NSCursor? {
        if tool.isRegionSelectionTool {
            // The badge mirrors the LIVE modifiers so the combine mode is
            // visible before the drag starts (⇧ +, ⌥ −, ⇧⌥ ×).
            return SelectionCursor.cursor(for: selectionMode)
        }
        if tool.createsAnnotationByDrag || tool == .crop || tool == .zoomCallout
            || tool == .measure { return .crosshair }
        if tool == .text { return .iBeam }
        return nil
    }

    /// The combine mode the current modifier state implies.
    private var selectionMode: SelectionRegion.Mode {
        SelectionRegion.Mode(shift: pointerModifiers.contains(.shift),
                             option: pointerModifiers.contains(.option))
    }

    /// Modifier keys reach the first responder as flagsChanged, not keyDown;
    /// tracking them keeps the selection cursor's +/−/× badge live.
    override func flagsChanged(with event: NSEvent) {
        pointerModifiers = event.modifierFlags
        if tool.isRegionSelectionTool, let window {
            window.invalidateCursorRects(for: self)
            // invalidate alone waits for the next mouse move; set the cursor
            // now if the pointer is already over the canvas.
            let local = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            if bounds.contains(local) {
                SelectionCursor.cursor(for: selectionMode).set()
            }
        }
        // ⌥ pressed or let go over a layer flips the copy badge on the pointer
        // while it rests there, rather than waiting for the next mouse move.
        if tool == .select, moveDrag == nil, multiMove == nil { refreshGrabCursor() }
        // ⌘ toggles measure snapping — refresh the hover dot so it jumps on/off
        // the edge live while held.
        refreshMeasureCreation(modifierFlags: event.modifierFlags)
        super.flagsChanged(with: event)
    }
}
