import AppKit
import PhotonzCore
import PhotonzRender
import SwiftUI

// The canvas gestures: press, drag and release, plus the keys that act on
// what is being dragged. Every tool's drag starts in `mouseDown` here. Split
// out of CanvasView.swift; `CanvasNSView`'s stored properties still live there.

extension CanvasNSView {
    // MARK: Pointer: layer move or marquee

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let viewport else { return }
        onCanvasPressed()
        // A fresh press, so whatever Escape called off belongs to the last
        // gesture. Cleared here rather than where the pivot is grabbed, so a
        // release that never arrived cannot leave the canvas swallowing every
        // drag after it.
        motionPivotCancelled = false
        motionPathCancelled = false
        // Adjusting the grid owns the whole canvas: nothing on it can be picked
        // up, selected or edited by accident. A press means one of three
        // things, in this order — grab the zero point by its knob or its two
        // markers, pick up a guide already pinned under the pointer, or pin a
        // new guide on the line the pointer is lighting.
        if gridAdjust != nil {
            window?.makeFirstResponder(self)
            beginGridAdjustPress(at: convert(event.locationInWindow, from: nil),
                                 freeing: event.modifierFlags.contains(.command))
            return
        }
        // Every press starts a drag that is standing on nothing and has not
        // been freed: whatever the last one caught, or whether ⌘ let it go,
        // is none of this one's business. A caliper being placed is the
        // exception — it is ONE gesture spread over two clicks, and the line
        // its preview is showing has to still be the line the click lands on.
        if measurePlacement == nil { snapHold = .none }
        // A click outside the inline text editor commits it; the click is
        // swallowed so committing never doubles as starting something else.
        // The one exception is the fresh arrow's caption field: the Arrow tool
        // stayed in hand while it is open, so this press commits the draft AND
        // starts the next arrow (a plain click hands back to Select on mouse-up).
        // A press anywhere else on the canvas lands the name being typed above a
        // screen or component, and is swallowed: committing never doubles as
        // starting something else. (A press INSIDE the field never reaches here.)
        if canvasNameField != nil {
            commitCanvasRename()
            return
        }
        if let session = textSession {
            if session.captionStyle != nil,
               ArrowCaptionEntry.pressOutsideField(tool: tool) == .commitAndDraw {
                commitTextSession(keepTool: true)
                pressClosedCaptionField = true
            } else {
                commitTextSession()
                return
            }
        }
        window?.makeFirstResponder(self)
        let viewPoint = convert(event.locationInWindow, from: nil)
        let p = viewport.documentPoint(fromView: viewPoint)
        // The name above a screen or component is a handle on it: click it to
        // pick that box, double click it to rename it where it sits. It is chrome,
        // the same size at every zoom, so it is resolved in view space and
        // before anything document-shaped runs — including the double click on
        // bare canvas that zooms the window, which is what this strip does
        // everywhere the letters are not.
        if tool == .select, let named = nameLabelHit(at: viewPoint) {
            if event.clickCount == 2 {
                beginCanvasRename(named)
            } else if event.modifierFlags.contains(.shift) {
                // ⇧-click on a name does what ⇧-click on the picture does: adds
                // that box to the selection, or drops it when it is in.
                onExtendSelection(named)
                refreshOverlays()
            } else {
                // A name is the box's handle, so it is a handle you can DRAG
                // as well as click. It matters most for a screen: a screen's
                // empty surface sweeps a band over what is on it, so the name
                // is the one grab that moves the screen itself without picking
                // it first, and it is above every screen at every zoom.
                beginNameLabelDrag(named, at: p, event: event)
                refreshOverlays()
            }
            return
        }
        // A picked path shows its points, and they own the press: dragging one
        // reshapes the outline rather than picking the whole layer up. It is
        // read here, before the double click that zooms the window, because a
        // double click on a path IS the gesture that adds and converts points
        // (`CanvasPathEdit`).
        if pathEditMouseDown(at: p, event: event) { return }
        // Double-click the window background — the matte OR the locked base image,
        // i.e. anywhere that isn't an editable layer — performs the standard
        // window zoom. `.hiddenTitleBar` leaves no real title bar to double-click,
        // and on an image that fills the window the matte alone wasn't reachable,
        // so this makes "double-click the bg to maximize" work everywhere. Editable
        // layers (text/annotations) stay double-click-to-edit.
        //
        // Which tools it belongs to is the TOOL's answer, not a list of
        // exemptions here (`Tool.doubleClickOnEmptyCanvasZoomsWindow`). The
        // gesture stays with Select, Crop and the marquee trio, which put
        // nothing on the picture; every tool that draws, measures or paints
        // owns its own clicks, because two of them placed quickly a short span
        // apart arrive as a double click and the window used to win. That was
        // reproduced with the Pen on 2026-09-13 — 1280x900 to 1728x1028 on the
        // second click, and the anchor never landed — and a short edge on an
        // icon is exactly that pair of clicks.
        if event.clickCount == 2, tool.doubleClickOnEmptyCanvasZoomsWindow,
           document?.canvasHitTest(p, zoom: viewport.zoom) == nil {
            performWindowTitleBarAction()
            return
        }
        // The text tool places a new block wherever you click - on the grid,
        // like everything else drawn on it, and exactly under the pointer
        // with Command held.
        if tool == .text {
            beginTextSession(layerID: nil, at: snappedTextOrigin(p, event: event))
            return
        }
        // Crop mode owns the pointer: handles resize, inside moves, outside
        // draws a fresh rect. Double-click inside commits.
        if tool == .crop {
            if event.clickCount == 2, let rect = cropRect, rect.contains(p) {
                cropDrag = nil
                onCropCommit()
                return
            }
            if let rect = cropRect,
               let handle = Handles.hit(at: p, frame: rect, zoom: viewport.zoom,
                                        screenTolerance: CanvasPointer.cropTolerance,
                                        edgeGrab: Experiments.shared.edgeGrabEnabled) {
                cropDrag = CropDrag(kind: .resize(handle), startRect: rect, lastPoint: p)
                // The hover cue already put these arrows up, but a press that
                // arrived without one (a click straight onto a handle) still
                // has to hold them for the drag.
                if Experiments.shared.grabCueEnabled {
                    applyGrabCursor(CanvasCursor.cursor(for: .resize(handle), transform: .identity))
                }
            } else if let rect = cropRect, rect.contains(p) {
                cropDrag = CropDrag(kind: .move, startRect: rect, lastPoint: p)
            } else {
                cropDrag = CropDrag(kind: .define(anchor: p), startRect: cropRect, lastPoint: p)
            }
            return
        }
        // Paint bucket: click fills the hit layer (or the locked Background,
        // resolved app-side since hit-testing skips locked layers). ⌥ fills
        // with the background color.
        if tool == .fill {
            onFillAt(p, document?.canvasHitTest(p, zoom: viewport.zoom)?.id,
                     event.modifierFlags.contains(.option))
            return
        }
        // Region selection tools. The wand floods app-side (async — the
        // composite sweep is heavy); rect/ellipse start a marquee, which
        // follows the pointer exactly and takes no magnet at all. The combine
        // mode (⇧ add / ⌥ subtract / ⇧⌥ intersect) latches at gesture start.
        if tool == .wand {
            onWandAt(p, SelectionRegion.Mode(shift: event.modifierFlags.contains(.shift),
                                             option: event.modifierFlags.contains(.option)))
            return
        }
        if tool == .rectSelect || tool == .ellipseSelect {
            let mode = SelectionRegion.Mode(shift: event.modifierFlags.contains(.shift),
                                            option: event.modifierFlags.contains(.option))
            // A plain drag starting INSIDE the region moves its PIXELS (user
            // expectation 2026-07-05 — deliberate deviation from Photoshop,
            // where a marquee drag moves only the outline). ⌘-drag moves
            // just the outline; so does a region with nothing bakeable under
            // it. A ⇧/⌥ modifier still starts a new combining shape.
            if mode == .replace, let base = selection, base.contains(p) {
                if !event.modifierFlags.contains(.command), selectionTargetsPixels,
                   let frame = onRegionMoveBegin(false) {
                    regionContentDrag = (p, p, frame)
                } else {
                    regionOutlineDrag = (p, p, base)
                }
                refreshOverlays()
                return
            }
            regionDrag = (MarqueeDrag(anchor: MarqueeDrag.corner(at: p)), mode,
                          tool == .ellipseSelect)
            refreshOverlays()
            return
        }
        // The Pen owns every press while it is in hand: it draws over several
        // clicks rather than in one drag, so there is no hit test, no marquee
        // and no selection underneath it.
        if tool == .pen, penMouseDown(at: p, event: event) { return }
        // Drawing tools own the pointer: every drag creates a new annotation
        // (or, for the zoom tool, defines the callout's source box).
        if tool.createsAnnotationByDrag || tool == .zoomCallout || tool == .frame
            || tool == .lens {
            // The end you START from lands on an edge too. There is no shaft yet
            // to say which way the mark points, so the first point takes
            // whichever lines are near it — the same thing a caliper's first
            // foot does.
            resetDrawSnapMemory()
            let anchor = snappedAnnotationPoint(p, shape: tool.annotationShape,
                                                opposite: nil, event: event)
            annotationDrag = AnnotationDrag(anchor: anchor)
            refreshAnnotationPreview(constrained: event.modifierFlags.contains(.shift))
            refreshOverlays()
            return
        }
        // The measure tool: the measuring line is drawn EITHER by click/click OR
        // by press-drag-release; the head is a final click. On the first press we
        // place foot A and remember the down point so mouse-up can tell a click
        // (stay for a foot-B click) from a drag (line done → set the head).
        if tool == .measure {
            // Alignment mode: the press anchors a guide drag (snapped onto the
            // nearby edge — the edge you meant, not the pixel you hit).
            if measureChecksAlignment {
                let anchor = snapMeasureAnchor(p, modifiers: event.modifierFlags)
                alignmentDrag = (anchor, anchor)
                refreshAlignmentPreview()
                return
            }
            // Size and Gap commit on the click itself, so the press only tracks
            // the pointer; mouse-up does the work.
            if measureToolMode.commitsOnClick {
                measurePressDownView = convert(event.locationInWindow, from: nil)
                hoverPoint = measurePressDownView
                refreshMeasureCreation(modifierFlags: event.modifierFlags)
                return
            }
            measurePressDownView = convert(event.locationInWindow, from: nil)
            hoverPoint = measurePressDownView
            if measurePlacement == nil {
                resetDragMotion(p)
                measurePlacementHold = nil
                measurePlacement = .firstPlaced(foot1: snapMeasureAnchor(p, modifiers: event.modifierFlags))
                measureFirstFootPress = true
            } else {
                measureFirstFootPress = false
            }
            refreshMeasureCreation(modifierFlags: event.modifierFlags)
            return
        }
        // Canvas pseudo-selection: the boundary handles resize the CANVAS.
        // Only handle hits are captured — clicks elsewhere fall through to
        // normal layer selection / marquee (which also deselects the canvas).
        if isCanvasSelected, tool == .select,
           let handle = Handles.hit(at: p, frame: CGRect(origin: .zero, size: viewport.documentSize),
                                    zoom: viewport.zoom, screenTolerance: 8,
                                    edgeGrab: Experiments.shared.edgeGrabEnabled) {
            canvasResizeDrag = (handle, CGRect(origin: .zero, size: viewport.documentSize), false)
            applyGrabCursor(CanvasCursor.cursor(for: .resize(handle), transform: .identity))
            refreshOverlays()
            return
        }
        // A double click always DESCENDS: on a group it picks the piece under
        // the pointer, and only once there is nothing left to go into does it
        // mean what it always meant — opening a text layer to type, or an
        // arrow's caption. That is what makes double clicking a group holding
        // a label select the label, and double clicking again start typing.
        if event.clickCount == 2, let step = groupAwareDescent(at: p, zoom: viewport.zoom) {
            selectedLayerFrame = document?.canvasLayer(id: step.id).map { $0.withoutSlack($0.frame) }
            onSelectLayerInGroup(step.id, step.context)
            refreshOverlays()
            return
        }
        // A double click on the words of a COPY types them, in ONE gesture.
        // A copy is one object — clicking it picks the whole thing and there
        // is nothing inside to select — so the extra step a group asks for
        // would buy nothing here. The words land on the copy's own wording
        // knob; with no knob for them, `beginTextSession` says so instead of
        // opening a field whose contents would be thrown away.
        if event.clickCount == 2, componentsEnabled,
           let pieceID = document?.textPiece(at: p, zoom: viewport.zoom),
           let piece = document?.canvasLayer(id: pieceID) {
            beginTextSession(layerID: pieceID, at: piece.frame.origin)
            return
        }
        // Double-click on a text layer re-opens it for inline editing. Checked
        // before handles: on a small text layer the handle hit zones cover the
        // whole frame and would eat the double-click.
        if event.clickCount == 2, let hit = document?.canvasHitTest(p, zoom: viewport.zoom),
           case .text = hit.content {
            beginTextSession(layerID: hit.id, at: hit.frame.origin)
            return
        }
        // Double-click a label the separation has not read yet: read the words
        // and then put the caret in them (Next `next-double-click-reads-a-label`).
        // The gesture already means "I want to change these words" one line
        // above; on a run of text lifted off a screenshot it used to mean
        // nothing at all, and finding Turn into Text in a menu was the only way
        // through. The reading is a moment's work off the main thread, so the
        // field opens when it lands rather than here
        // (`EditorState.readTheWordsThenType`).
        if event.clickCount == 2, Experiments.shared.doubleClickReadsALabelEnabled,
           let hit = document?.canvasHitTest(p, zoom: viewport.zoom), hit.holdsWordsToRead {
            // Picked first, so the outline says which label is being read
            // while it is being read, and so a refusal leaves the thing it is
            // about in hand.
            selectedLayerFrame = document?.canvasLayer(id: hit.id).map { $0.withoutSlack($0.frame) }
            onSelectLayerInGroup(hit.id, document?.parentID(of: hit.id))
            onReadTheWordsThenType(hit.id)
            refreshOverlays()
            return
        }
        // Double-click an arrow to add or edit its caption (Next flag).
        if event.clickCount == 2, Experiments.shared.arrowCaptionsEnabled,
           let hit = document?.canvasHitTest(p, zoom: viewport.zoom),
           hit.annotation?.shape == .arrow {
            beginCaptionSession(layer: hit)
            return
        }
        // Handles take priority over moves: they extend past the layer's frame.
        // Lines/arrows expose their endpoints; everything else (that resizes)
        // gets the eight frame handles.
        let selectedLayer = selectedLayerID.flatMap { id in document?.canvasLayer(id: id) }
        // Every grab aimed at the SELECTED layer reads this pointer rather than
        // the raw one. On almost everything the two are the same point; on a
        // piece inside a card that has been TURNED it is that point written in
        // the card's own upright space, which is the space the piece's frame,
        // its handles and its knob are all stated in (`uprightPoint`).
        let q = uprightPoint(p, of: selectedLayerID)
        if let id = selectedLayerID, let layer = selectedLayer, offersOwnHandles(layer),
           let content = layer.annotation,
           let endpoint = AnnotationEndpoints.hit(at: q, layer: layer, zoom: viewport.zoom),
           let drag = AnnotationEndpointDrag(layer: layer, endpoint: endpoint),
           let start = layer.annotationEndpoint(.start), let end = layer.annotationEndpoint(.end) {
            endpointDrag = EndpointDragSession(layerID: id, content: content,
                                               originalStart: start, originalEnd: end, drag: drag)
            // The hand that invited this drag closes for its duration, the same
            // as a caliper foot or a caption pill.
            applyGrabCursor(.closedHand)
            onDragBegin(id)
            refreshEndpointPreview(constrained: event.modifierFlags.contains(.shift))
            refreshOverlays()
            return
        }
        // A selected arrow's caption pill is a grab of its own: drag it to the
        // spot you want and it stays there (Next flag). Endpoint handles won
        // above, so the tail handle keeps priority where the two overlap.
        if let id = selectedLayerID, let layer = selectedLayer, !layer.isLocked,
           Experiments.shared.arrowCaptionsEnabled,
           let pill = captionPillRect(layer) {
            let tolerance = viewport.zoom > 0 ? 6 / viewport.zoom : 6
            if pill.insetBy(dx: -tolerance, dy: -tolerance).contains(q) {
                let center = CGPoint(x: pill.midX, y: pill.midY)
                captionDrag = CaptionDrag(layerID: id,
                                          grip: CGSize(width: q.x - center.x, height: q.y - center.y),
                                          startCenter: center, current: q)
                applyGrabCursor(.closedHand)
                refreshOverlays()
                return
            }
        }
        // A placed caliper is edited by dragging one of its three handles (the
        // two feet or the head); the others stay put and the value/label update
        // live. The readout pill is the head's grab too: dragging the number
        // moves it, and it is the only grab while it sits on the head dot.
        if let id = selectedLayerID, let layer = selectedLayer, offersOwnHandles(layer),
           let m = layer.measure,
           let s = layer.measureEndpoint(.start), let e = layer.measureEndpoint(.end) {
            let slack = CanvasPointer.measureHandleTolerance
            let tolerance = viewport.zoom > 0 ? slack / viewport.zoom : slack
            var best: (handle: MeasureHandle, point: CGPoint, distance: CGFloat)?
            for h in measureHandles(layer) {
                let d = hypot(q.x - h.point.x, q.y - h.point.y)
                if d <= tolerance, d < (best?.distance ?? .infinity) {
                    best = (h.handle, h.point, d)
                }
            }
            if best == nil, let pill = measureReadoutRect(layer),
               pill.insetBy(dx: -tolerance, dy: -tolerance).contains(q) {
                best = (.head, q, 0)
            }
            if let best {
                resetDragMotion(q)
                var drag = MeasureHandleDrag(
                    layerID: id, handle: best.handle, mode: m.mode,
                    originalStart: s, originalEnd: e, originalHeadOffset: m.headOffset,
                    originalReadout: MeasureReadoutPlacement(nudge: m.labelNudge,
                                                             pinned: m.labelPinned),
                    pressPoint: q, current: q)
                if best.handle == .head {
                    let head = MeasureContent.caliperGeometry(mode: m.mode, start: s, end: e,
                                                              headOffset: m.headOffset).labelAnchor
                    drag.grabCross = m.mode == .horizontal ? q.y - head.y : q.x - head.x
                    if let dm = documentMeasure(layer) {
                        let pill = dm.labelPosition(chipSize: dm.estimatedLabelSize)
                        drag.grabAlong = m.mode == .horizontal ? q.x - pill.x : q.y - pill.y
                    }
                    drag.guides = measureChipGuideLines(excluding: id)
                } else {
                    // A foot taken hold of a few points off its dot keeps that
                    // grip for the whole drag: it travels as far as the hand
                    // travelled, the way the hand travelled, instead of jumping
                    // under the pointer the moment the drag starts. The head
                    // has had this all along, through grabCross/grabAlong.
                    drag.grip = MeasureHandleGrip.taken(pressing: q, handle: best.point,
                                                        zoom: viewport.zoom, tolerance: slack)
                    drag.guides = measureGuideLines(excluding: id)
                    drag.layerLines = measureLayerLines(excluding: id)
                }
                measureHandleDrag = drag
                // The hand that invited this drag closes for its duration —
                // number, foot or head dot alike.
                if grabCue(at: p) != nil { applyGrabCursor(.closedHand) }
                refreshOverlays()
                return
            }
        }
        // The pivot: a crosshair sitting ON the drawing, and very often right
        // in the middle of it, so it is read here — before the box's own
        // handles, and before the press that would pick the layer up. It does
        // not simply win: the nearest drawn mark takes the press, so the turn
        // knob still answers a hand aimed at the turn knob and seven corners
        // still resize while the eighth holds a crosshair
        // (`motionPivotTakesPress`, `docs/design/canvas-hit-order.md`). It
        // only ever answers while a turning layer is picked, so the rest of
        // the time there is nothing here at all.
        if motionPivotMouseDown(at: p, event: event) { return }
        // The square on the middle of a moving layer's path: small, and only
        // there while that layer is picked, so it is read before the press
        // that would pick up whatever is under it (`CanvasMotionPath.swift`).
        if motionPathMouseDown(at: p, event: event) {
            refreshOverlays()
            return
        }
        // Rotate knob, floated off the selected layer's top edge.
        if let id = selectedLayerID, let layer = selectedLayer, offersRotation(layer),
           let knob = layer.rotateKnobPoint(zoom: viewport.zoom),
           hypot(q.x - knob.x, q.y - knob.y) * viewport.zoom <= CanvasPointer.rotateTolerance {
            // About whatever this layer turns about, which is its middle
            // unless a turn on it hangs it somewhere else (`Layer.turnPivot`).
            // The knob has to measure the same turn the picture takes or it
            // would run away from the hand on a bell.
            let center = layer.turnPivot
            transformDrag = TransformDragSession(
                layerID: id, kind: .rotate(grabAngle: TransformDrag.pointerAngle(q, around: center)),
                startTransform: layer.transform, center: center,
                frameSize: layer.frame.size, transform: layer.transform)
            applyGrabCursor(CanvasCursor.cursor(for: .rotate, transform: apparentTransform(of: layer)))
            onDragBegin(id)
            refreshOverlays()
            return
        }
        // The four dots inside a shape's corners, each rounding the corner it
        // sits in (`next-corner-handles`). Read BEFORE the frame handles: they
        // sit inside the outline rather than on it, so nothing is taken from a
        // resize, and ⌥ over a dot has to mean all four corners rather than the
        // skew it means on a corner square.
        if Experiments.shared.cornerHandlesEnabled, tool == .select,
           let id = selectedLayerID, let layer = selectedLayer, let frame = selectedLayerFrame,
           offersOwnHandles(layer), layer.offersCornerRadiusHandles,
           let corner = CornerRadiusHandles.hit(at: handleSpacePoint(p, layer: layer),
                                                frame: frame, radii: layer.roundedCornerRadii,
                                                zoom: viewport.zoom) {
            let radii = layer.roundedCornerRadii
            cornerRadiusDrag = CornerRadiusDrag(
                layerID: id, corner: corner, startRadii: radii, radii: radii,
                allCorners: event.modifierFlags.contains(.option))
            if grabCue(at: p) != nil { applyGrabCursor(.closedHand) }
            refreshOverlays()
            return
        }
        // Frame handles. The pointer maps through the layer's inverse
        // transform so handles on a rotated/skewed layer hit where they draw.
        // ⌥ on a corner skews instead of resizing.
        // A path showing its points offers no frame handles, so it takes no
        // press on one either: the chrome and the press read the same question,
        // or there would be eight targets nobody can see (`CanvasDisplay`).
        if let id = selectedLayerID, let frame = selectedLayerFrame, editablePath == nil,
           selectedLayer.map(offersOwnHandles) ?? true, selectedLayer?.allowsFrameResize ?? true,
           let handle = Handles.hit(at: handleSpacePoint(p, layer: selectedLayer),
                                    frame: frame, zoom: viewport.zoom,
                                    edgeGrab: Experiments.shared.edgeGrabEnabled) {
            if event.modifierFlags.contains(.option), handle.isCorner, let layer = selectedLayer {
                transformDrag = TransformDragSession(
                    layerID: id, kind: .skew(corner: handle, grabPoint: q),
                    startTransform: layer.transform,
                    center: CGPoint(x: layer.frame.midX, y: layer.frame.midY),
                    frameSize: layer.frame.size, transform: layer.transform)
            } else {
                let untransformed = selectedLayer?.transform.isIdentity ?? true
                resizeDrag = ResizeDrag(
                    layerID: id, handle: handle, startFrame: frame, frame: frame,
                    peers: Experiments.shared.alignLayersEnabled && untransformed
                        ? (document?.snapPeers(excluding: id) ?? []) : [],
                    columns: untransformed && !isOnASlant(id) ? columnBands(excluding: [id]) : [],
                    snapped: Snapping.FrameResult(frame: frame))
                applyGrabCursor(CanvasCursor.cursor(for: .resize(handle),
                                                    transform: apparentTransform(of: selectedLayer)))
            }
            onDragBegin(id)
            refreshOverlays()
            return
        }
        // A SELECTED collage exposes its filled cells for swap-by-drag (like
        // measure corners: selection first, then inner manipulation). Grabbing
        // a gutter, the backdrop margin, or an empty well still moves the layer,
        // and anything drawn OVER the cell (hit-test winner) keeps the click.
        if tool == .select, let id = selectedLayerID, let layer = selectedLayer,
           !layer.isLocked, let content = layer.collage,
           document?.canvasHitTest(p, zoom: viewport.zoom)?.id == id,
           let slot = Collage.slotIndex(at: p, in: layer),
           content.slots[slot].imageRef != nil {
            slotDrag = (id, slot)
            refreshOverlays()
            return
        }
        // Select (V) drag starting inside a pixel region moves the region's
        // CONTENT within its layer (Photoshop Move tool); ⌥ moves a copy.
        // Falls through to normal layer moves when nothing bakeable is there.
        if selectionTargetsPixels, let region = selection, region.contains(p),
           let frame = onRegionMoveBegin(event.modifierFlags.contains(.option)) {
            regionContentDrag = (p, p, frame)
            refreshOverlays()
            return
        }
        // A drag across a screen's own empty surface sweeps a band over what
        // is ON that screen. The room between the things on a screen belongs
        // to picking them — that is what a screen is for — and treating it as
        // the screen's own picture meant a band inside a screen could not be
        // drawn at all: the drag picked the screen up and moved it instead.
        // A screen you have ALREADY picked still moves from its middle, so a
        // selected screen never feels stuck (`ScreenSurfacePress`), and every
        // screen moves by its name whether it is picked or not.
        if tool == .select, groupSelectionEnabled, event.clickCount == 1,
           case .sweep(let screen)? = document?.screenSurfacePress(
               at: p, zoom: viewport.zoom, picked: pickedLayerIDs,
               captionPillSize: Self.captionPillSizing) {
            beginScreenSurfaceSweep(screen, at: p, event: event)
            refreshOverlays()
            return
        }
        if let pick = groupAwarePick(at: p, zoom: viewport.zoom),
           let hit = document?.canvasLayer(id: pick.id) {
            // ⇧-click adds what you clicked to the selection, or drops it when
            // it is already in — the Layers list gesture, on the picture. It
            // resolves through the same walk a plain click does, so at the top
            // level you add whole groups and inside a group you add its own
            // pieces. The press is swallowed either way: it is about what is
            // selected, and starting a move here would drag one member of a
            // selection out from under the rest.
            if tool == .select, event.clickCount == 1,
               event.modifierFlags.contains(.shift) {
                if let extend = groupAwareExtend(at: p, zoom: viewport.zoom) {
                    onExtendSelection(extend)
                }
                refreshOverlays()
                return
            }
            // The press landed on something already picked: the whole
            // selection travels with the pointer, and the press KEEPS that
            // selection instead of replacing it with the one layer underneath.
            // Selecting first and moving one piece is what a press on anything
            // else does, and it is what a click that never moves still does.
            if tool == .select, event.clickCount == 1,
               multiSelectedLayerIDs.contains(pick.id),
               let plan = document?.multiLayerDrag(moving: multiSelectedLayerIDs),
               plan.members.count > 1, plan.members.contains(where: { $0.id == pick.id }) {
                let grab = uprightPoint(p, of: pick.id)
                multiMove = MultiMoveDrag(
                    plan: plan,
                    pick: pick,
                    grabOffset: CGPoint(x: grab.x - plan.bounds.origin.x,
                                        y: grab.y - plan.bounds.origin.y),
                    peers: Experiments.shared.alignLayersEnabled
                        ? (document?.snapPeers(excluding: multiSelectedLayerIDs) ?? []) : [],
                    columns: isOnASlant(pick.id) ? []
                        : columnBands(excluding: multiSelectedLayerIDs),
                    snapped: Snapping.Result(origin: plan.bounds.origin),
                    copying: copyDragModifier(event))
                refreshOverlays()
                return
            }
            let copying = copyDragModifier(event)
            onSelectLayerInGroup(pick.id, pick.context)
            // Dragging a PIECE inside a copy drags the whole copy. The piece
            // itself cannot move: its place comes from the original and the
            // next sync puts it back, so a drag on it would look like the
            // canvas ignoring the pointer. Moving the copy is what the person
            // grabbing its label meant anyway.
            var hit = hit
            if let piece = componentPiece(of: pick.id),
               let copy = document?.canvasLayer(id: piece.instance) {
                hit = copy
            }
            // A piece inside a card that has been TURNED is dragged on its
            // own, and it follows the pointer: the travel below is measured in
            // the card's upright space, which is the space the piece's place
            // is written in, so ten points to the right on screen is ten
            // points along the card (`uprightPoint`).
            // The drag preview (two full renders, then a pass to hand the
            // canvas its sprite) starts once the pointer really travels, in
            // mouseDragged, not here: most presses on a layer are clicks that
            // never move, and a click has no use for a sprite. Per-move
            // previews fall back to full submits until the renders land, so a
            // drag loses nothing but the head start. A copy drag still never
            // gets a sprite at all; mouseDragged checks that before it asks.
            // The box you see: a label lines up by its last letter, and what
            // this drag commits is read back as a visible box.
            let seen = hit.withoutSlack(hit.frame)
            let grab = uprightPoint(p, of: hit.id)
            selectedLayerFrame = seen
            moveDrag = MoveDrag(layerID: hit.id,
                                grabOffset: CGPoint(x: grab.x - seen.origin.x,
                                                    y: grab.y - seen.origin.y),
                                size: seen.size,
                                startOrigin: seen.origin,
                                peers: Experiments.shared.alignLayersEnabled
                                    ? (document?.snapPeers(excluding: hit.id) ?? []) : [],
                                // The columns screens stand in are drawn on the
                                // upright canvas, so a piece on a slant has no
                                // business catching one.
                                columns: isOnASlant(hit.id) ? [] : columnBands(excluding: [hit.id]),
                                snapped: Snapping.Result(origin: hit.frame.origin),
                                copying: copying)
        } else {
            // A ⇧-click is aimed at a layer, so one that lands on bare canvas
            // is a miss, not a deselect: it must not throw away the selection
            // it was about to be added to. The rubber band still starts either
            // way, so ⇧-dragging out on the canvas is unchanged; only the
            // press that never moves is spared, and mouse-up finishes the rule.
            let press = BareCanvasPress(shift: tool == .select
                && event.modifierFlags.contains(.shift))
            marqueePress = press
            marqueeContext = Experiments.shared.layerGroupsEnabled ? groupContext : nil
            marqueeClickTarget = nil // bare canvas: a click that never travels picks nothing
            // The press itself no longer lets go of the layer: what the
            // gesture turns out to be decides that, and the press does not
            // know yet. A click deselects on the way back up, and a band
            // deselects only if it CATCHES something — a band thrown round
            // empty canvas says WHERE, not WHAT, and the layer it was drawn
            // over stays picked so ⌫ can clear those pixels out of it.
            if press.clearsSelectionOnPress { onClickedNothing() }
            marquee = MarqueeDrag(anchor: p)
        }
        refreshOverlays()
    }

    /// Takes hold of a box by its NAME — the strip of chrome drawn above every
    /// screen and every component.
    ///
    /// Clicking a name has always picked its box; this makes dragging one move
    /// the box, which is what a handle drawn beside something ought to do. It
    /// is the always-there way to move a screen now that a drag on a screen's
    /// empty surface sweeps what is on it instead, and it needs no selection
    /// first: the name lights up under the pointer, and it sits above the
    /// screen at the same size at every zoom.
    ///
    /// The whole selection travels when the name belongs to something already
    /// in it, exactly as a press on the picture does. A press that never
    /// travels commits nothing, so a plain click on a name is still a click.
    private func beginNameLabelDrag(_ id: UUID, at p: CGPoint, event: NSEvent) {
        guard let layer = document?.canvasLayer(id: id), !layer.isLocked else {
            selectedLayerFrame = document?.canvasLayer(id: id).map { $0.withoutSlack($0.frame) }
            onSelectLayerInGroup(id, document?.parentID(of: id))
            return
        }
        if multiSelectedLayerIDs.contains(id),
           let plan = document?.multiLayerDrag(moving: multiSelectedLayerIDs),
           plan.members.count > 1, plan.members.contains(where: { $0.id == id }) {
            multiMove = MultiMoveDrag(
                plan: plan,
                pick: (id, document?.parentID(of: id)),
                grabOffset: CGPoint(x: p.x - plan.bounds.origin.x,
                                    y: p.y - plan.bounds.origin.y),
                peers: Experiments.shared.alignLayersEnabled
                    ? (document?.snapPeers(excluding: multiSelectedLayerIDs) ?? []) : [],
                columns: columnBands(excluding: multiSelectedLayerIDs),
                snapped: Snapping.Result(origin: plan.bounds.origin),
                copying: copyDragModifier(event))
            return
        }
        let seen = layer.withoutSlack(layer.frame)
        selectedLayerFrame = seen
        onSelectLayerInGroup(id, document?.parentID(of: id))
        moveDrag = MoveDrag(layerID: id,
                            grabOffset: CGPoint(x: p.x - seen.origin.x,
                                                y: p.y - seen.origin.y),
                            size: seen.size,
                            startOrigin: seen.origin,
                            peers: Experiments.shared.alignLayersEnabled
                                ? (document?.snapPeers(excluding: id) ?? []) : [],
                            columns: columnBands(excluding: [id]),
                            snapped: Snapping.Result(origin: seen.origin),
                            copying: copyDragModifier(event))
    }

    /// Starts a band latched to `screen`, so the sweep picks from what is on
    /// that screen and never reaches past it. Everything else is the press on
    /// bare canvas: ⇧ spares what was already picked and adds the catch to it,
    /// a plain press lets go first. The one difference is what a press that
    /// never travels means — out on the canvas it picks nothing, and here it
    /// picks the screen, which is what a click on a screen's surface has
    /// always done.
    private func beginScreenSurfaceSweep(_ screen: UUID, at p: CGPoint, event: NSEvent) {
        let press = BareCanvasPress(shift: event.modifierFlags.contains(.shift))
        marqueePress = press
        marqueeContext = screen
        marqueeClickTarget = screen
        // As on bare canvas, the press keeps its hands off the selection: the
        // release picks the screen for a click, and a band decides only when
        // it catches something.
        if press.clearsSelectionOnPress { onClickedNothing() }
        marquee = MarqueeDrag(anchor: p)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let viewport else { return }
        if gridOriginDragging {
            moveGridOrigin(toViewPoint: convert(event.locationInWindow, from: nil),
                           freeing: event.modifierFlags.contains(.command))
            return
        }
        if guideDragging {
            dragHeldGuide(toViewPoint: convert(event.locationInWindow, from: nil))
            return
        }
        let p = viewport.documentPoint(fromView: convert(event.locationInWindow, from: nil))
        // A point of a path taken hold of owns the rest of the gesture, even
        // with the Pen in hand: the Pen shows a picked path its points now, so
        // the press that started this drag was a press on a point rather than
        // the first anchor of a new shape. Read before the Pen, or the drag
        // would be handed to a session that never began.
        if pathAnchorDrag != nil {
            pathEditMouseDragged(to: p, event: event)
            return
        }
        // A box being swept over the points owns the rest of the gesture too:
        // the press that started it landed off the shape, where a rubber band
        // over LAYERS would otherwise have been drawn.
        if pathPointSweep != nil {
            pathPointSweepDragged(to: p)
            return
        }
        if tool == .pen {
            penMouseDragged(to: p, event: event)
            return
        }
        // The cancelled case belongs here too: after Escape the pivot has
        // given the drag back, and this keeps the rest of the gesture from
        // falling through to the shape the crosshair was sitting on.
        if motionPivotDrag != nil || motionPivotCancelled {
            motionPivotMouseDragged(to: p, event: event)
            return
        }
        if motionPathDrag != nil || motionPathCancelled {
            motionPathMouseDragged(to: p)
            return
        }
        // The pointer as the layer under the hand reads it. On a piece inside a
        // card that has been TURNED it is the same point written in the card's
        // upright space, which is where that piece's frame and handles live;
        // everywhere else it is the pointer unchanged (`uprightPoint`).
        let dragging = measureHandleDrag?.layerID ?? captionDrag?.layerID
            ?? endpointDrag?.layerID ?? transformDrag?.layerID ?? cornerRadiusDrag?.layerID
            ?? resizeDrag?.layerID ?? moveDrag?.layerID ?? multiMove?.pick.id
        let u = uprightPoint(p, of: dragging)
        if var drag = cropDrag {
            let bounds = cropBounds ?? CGRect(origin: .zero, size: viewport.documentSize)
            switch drag.kind {
            case .resize(let handle):
                guard let start = drag.startRect else { break }
                cropRect = Crop.resize(start, dragging: handle, to: p,
                                       aspect: cropAspect, bounds: bounds)
            case .move:
                if let rect = cropRect {
                    cropRect = Crop.moved(rect, by: CGPoint(x: p.x - drag.lastPoint.x,
                                                            y: p.y - drag.lastPoint.y),
                                          in: bounds)
                }
            case .define(let anchor):
                // An empty drag (a stray click) keeps the existing rect.
                cropRect = Crop.dragRect(anchor: anchor, current: p, aspect: cropAspect,
                                         bounds: bounds) ?? drag.startRect
            }
            drag.lastPoint = p
            cropDrag = drag
            refreshOverlays()
        } else if var drag = annotationDrag {
            drag.update(to: snappedAnnotationPoint(p, shape: tool.annotationShape,
                                                   opposite: drag.anchor, event: event))
            annotationDrag = drag
            refreshAnnotationPreview(constrained: event.modifierFlags.contains(.shift))
            refreshOverlays()
        } else if var drag = alignmentDrag {
            drag.current = p
            alignmentDrag = drag
            refreshAlignmentPreview()
        } else if tool == .measure {
            // Caliper creation is click-based; a drag between clicks just updates
            // the placement preview (same as moving with the button up).
            handleMeasureHover(event)
        } else if var drag = measureHandleDrag {
            // A FOOT magnetizes to detected UI edges (per-axis), to the lines the
            // other measurements already put down, and to the pixel grid. The
            // HEAD is the label position, not a measured point, so the picture's
            // edges have no say over it — but the other readouts do: it lines up
            // with the chips around it. ⌘ drags either one free.
            //
            // ⇧ holds a FOOT on the line the caliper is on, so the end you have
            // hold of slides along that line and nothing else moves: you change
            // how long the measurement is without changing what it is measuring
            // across. It is read on every move rather than latched at the press
            // — the same live constraint ⇧ already is for a drawn annotation —
            // so pressing it halfway through takes the line the caliper has got
            // to by then, and letting go hands the drag straight back to the
            // pointer. The two keys compose and each still means one thing: ⌘
            // ignores the magnets, ⇧ holds the line.
            let held = snapHold(freeing: event.modifierFlags.contains(.command))
            // Where the FOOT is going for this pointer position: the pointer
            // plus the grip the press took. Everything downstream is asked
            // about this point rather than the raw pointer, so the magnets
            // judge the edges near the FOOT rather than the edges near the
            // hand, and the ⇧ line is the line the foot has to stay on.
            let q = drag.grip.handlePoint(for: u)
            if drag.handle != .head {
                drag.heldLine = MeasureLineHold.holding(
                    drag.heldLine, shiftDown: event.modifierFlags.contains(.shift),
                    mode: drag.mode, fixedFoot: drag.fixedFoot())
            }
            if drag.handle == .head {
                snapGuide = snapMeasureHead(&drag, pointer: u, zoom: viewport.zoom,
                                            snapping: !held.isFree, holding: held)
                snapHold.caught(x: snapGuide?.x, y: snapGuide?.y)
            } else if held.isFree {
                drag.current = drag.heldLine?.project(q) ?? q
                snapGuide = nil
            } else {
                trackDragMotion(u)
                // Window the edge candidates by the span from the opposite foot to
                // the foot being dragged, exactly like the create drag.
                let fixed = drag.handle == .footA ? drag.originalEnd : drag.originalStart
                let snap = axisGated(
                    EdgeSnapping.snap(q, edges: edgeMap, zoom: viewport.zoom,
                                      xSpan: min(fixed.x, q.x)...max(fixed.x, q.x),
                                      ySpan: min(fixed.y, q.y)...max(fixed.y, q.y),
                                      includeCenters: measureSnapsToCenters,
                                      guides: drag.guides,
                                      layerLines: drag.layerLines,
                                      holding: held),
                    raw: q)
                // The magnets are asked exactly what a free drag asks them,
                // and then the held line has the last word: an edge ALONG the
                // line still catches, one that would pull the foot off it is
                // not taken and its guide does not light.
                let landing = MeasureLineHold.landing(snapped: snap.point, guideX: snap.guideX,
                                                      guideY: snap.guideY, on: drag.heldLine)
                drag.current = landing.point
                snapGuide = (landing.guideX, landing.guideY)
                snapHold.caught(x: landing.guideX, y: landing.guideY)
            }
            // A press only becomes an edit once the hand has actually
            // travelled: the grab has slack around the dot, so a press that
            // has not moved is someone taking hold of the end, not moving it.
            // Once true it stays true — a drag that comes back to where it
            // started is still a drag.
            drag.moved = drag.moved || MeasureHandlePress.travelled(from: drag.pressPoint, to: u,
                                                                    zoom: viewport.zoom)
            measureHandleDrag = drag
            // Live re-render so the measured value updates as the handle moves,
            // but nothing is previewed before the press counts as a drag: the
            // caliper would jump a few pixels and settle back on release.
            if drag.moved {
                let (start, end, off, readout) = drag.params()
                onMeasureEndpointPreview(drag.layerID, start, end, off, readout)
            }
            refreshOverlays()
        } else if var drag = captionDrag {
            drag.current = u
            captionDrag = drag
            // Live re-render so the pill follows the pointer.
            onCaptionPlacePreview(drag.layerID, drag.center)
            refreshOverlays()
        } else if var session = endpointDrag {
            session.drag.update(to: snappedAnnotationPoint(u, shape: session.content.shape,
                                                           opposite: session.drag.fixed,
                                                           event: event))
            endpointDrag = session
            refreshEndpointPreview(constrained: event.modifierFlags.contains(.shift))
            refreshOverlays()
        } else if var session = transformDrag {
            switch session.kind {
            case .rotate(let grabAngle):
                session.transform.rotation = TransformDrag.rotation(
                    from: session.startTransform.rotation, grabAngle: grabAngle,
                    currentAngle: TransformDrag.pointerAngle(u, around: session.center),
                    snapped: event.modifierFlags.contains(.shift))
            case .skew(let corner, let grabPoint):
                session.transform = TransformDrag.skewed(
                    session.startTransform, corner: corner,
                    by: CGPoint(x: u.x - grabPoint.x, y: u.y - grabPoint.y),
                    frameSize: session.frameSize)
            }
            transformDrag = session
            onTransformPreview(session.layerID, session.transform)
            refreshOverlays()
        } else if var drag = cornerRadiusDrag {
            // ⌥ is read on every move rather than latched at the press, so
            // taking hold of one corner and then deciding you meant all four
            // does not cost you the drag — and letting go of the key hands the
            // other three straight back.
            drag.allCorners = event.modifierFlags.contains(.option)
            let layer = document?.canvasLayer(id: drag.layerID)
            let frame = selectedLayerFrame ?? layer?.frame ?? .zero
            let wanted = CornerRadiusHandles.radius(draggingTo: handleSpacePoint(p, layer: layer),
                                                    corner: drag.corner, in: frame)
            drag.radii = CornerRadiusHandles.radii(drag.startRadii, corner: drag.corner,
                                                   to: wanted, allCorners: drag.allCorners)
            cornerRadiusDrag = drag
            onCornerRadiiPreview(drag.layerID, drag.radii)
            refreshOverlays()
        } else if var drag = resizeDrag {
            let layer = document?.canvasLayer(id: drag.layerID)
            // ⇧ keeps the proportions and ⌘ drags free of every magnet: one key
            // that means "ignore the magnets" everywhere on the canvas, and a
            // ratio nobody may quietly break. Either one hands back exactly the
            // resize this has always done.
            let aspect = event.modifierFlags.contains(.shift)
            let held = snapHold(freeing: event.modifierFlags.contains(.command))
            let snapping = !aspect && !held.isFree
            // Same rule as a move: a piece on a slant has nothing to say to the
            // grid or the rulers, which are drawn upright.
            let slant = isOnASlant(drag.layerID)
            drag.snapped = resizedFrame(for: layer, start: drag.startFrame, handle: drag.handle,
                                        pointer: p, preserveAspect: aspect,
                                        peers: snapping ? drag.peers : [],
                                        columns: snapping ? drag.columns : [],
                                        gridSpacing: snapping && !slant ? canvasSnapSpacing : nil,
                                        gridOrigin: canvasSnapOrigin,
                                        gridAxes: canvasSnapAxes,
                                        guides: slant ? [] : canvasSnapGuides,
                                        holding: snapping ? held : .none)
            // The lit grid line counts as a line the drag is standing on, so it
            // holds through a wobble exactly as a guide does.
            snapHold.caught(x: drag.snapped.guideX ?? drag.snapped.gridX,
                            y: drag.snapped.guideY ?? drag.snapped.gridY)
            drag.frame = drag.snapped.frame
            resizeDrag = drag
            onFramePreview(drag.layerID, drag.frame)
            refreshOverlays()
        } else if var drag = moveDrag {
            let proposed = CGPoint(x: u.x - drag.grabOffset.x, y: u.y - drag.grabOffset.y)
            // Read the copy modifier BEFORE deciding to float a sprite: a copy
            // drag never gets one, because the sprite's underlay hides the layer
            // it lifts and the original has to stay visible where it is.
            if copyDragModifier(event) { drag.copying = true }
            if !drag.moved {
                let travel = hypot(proposed.x - drag.startOrigin.x, proposed.y - drag.startOrigin.y)
                drag.moved = travel * viewport.zoom >= 4
                // The press has become a drag: now the sprite is worth making.
                if drag.moved, !drag.copying { onDragBegin(drag.layerID) }
            }
            if drag.moved {
                // ⌘ drags free, the way it already does for a measure foot or a
                // region corner: one key that means "ignore the magnets"
                // everywhere on the canvas.
                let held = snapHold(freeing: event.modifierFlags.contains(.command))
                if held.isFree {
                    drag.snapped = Snapping.Result(origin: proposed)
                } else {
                    // The picture's edges, the grid and the rulers are all
                    // drawn on the upright canvas. A piece inside a card on a
                    // slant is measured in the card's own space, so it lines
                    // up with the other pieces in the card and leaves the
                    // upright three alone: catching one of them would land it
                    // somewhere neither the piece nor the line agrees on.
                    let slant = isOnASlant(drag.layerID)
                    drag.snapped = Snapping.snapFrameOrigin(proposed, size: drag.size,
                                                            canvas: slant ? .zero : viewport.documentSize,
                                                            peers: drag.peers,
                                                            columnBands: drag.columns,
                                                            gridSpacing: slant ? nil : canvasSnapSpacing,
                                                            gridOrigin: canvasSnapOrigin,
                                                            gridAxes: canvasSnapAxes,
                                                            guides: slant ? [] : canvasSnapGuides,
                                                            zoom: viewport.zoom,
                                                            holding: held)
                }
                snapHold.caught(x: drag.snapped.guideX ?? drag.snapped.gridX,
                                y: drag.snapped.guideY ?? drag.snapped.gridY)
                if drag.copying {
                    onCopyDragPreview([drag.layerID: drag.snapped.origin])
                } else {
                    onFramePreview(drag.layerID, CGRect(origin: drag.snapped.origin, size: drag.size))
                }
            }
            // A dragged photo layer offers itself to collage slots under the
            // pointer — releasing over the highlighted cell absorbs it. A copy
            // drag never does: being swallowed by a cell is not what "leave the
            // original and take a copy" asked for.
            // A piece being nudged INSIDE a card on a slant is not looking for
            // a new home: both of these would take it out of the card it is
            // being tidied within, and both read boxes on the upright canvas
            // that its own numbers cannot be compared with.
            let slanted = isOnASlant(drag.layerID)
            if drag.moved, !drag.copying, !slanted,
               document?.canvasLayer(id: drag.layerID)?.imageRef != nil {
                hoverSlot = collageSlotTarget(at: p, excluding: drag.layerID)
            } else {
                hoverSlot = nil
            }
            applyGrabCursor(drag.copying ? .dragCopy : nil)
            adoptionHost = drag.moved && !slanted
                ? adoptionHost(moving: [drag.layerID: CGRect(origin: drag.snapped.origin,
                                                             size: drag.size)])
                : nil
            moveDrag = drag
            refreshOverlays()
        } else if var drag = multiMove {
            let proposed = CGPoint(x: u.x - drag.grabOffset.x, y: u.y - drag.grabOffset.y)
            if !drag.moved {
                let travel = hypot(proposed.x - drag.plan.bounds.origin.x,
                                   proposed.y - drag.plan.bounds.origin.y)
                drag.moved = travel * viewport.zoom >= 4
            }
            if copyDragModifier(event) { drag.copying = true }
            if drag.moved {
                // ⌘ drags free of the magnets, exactly as it does for one layer.
                let held = snapHold(freeing: event.modifierFlags.contains(.command))
                if held.isFree {
                    drag.snapped = Snapping.Result(origin: proposed)
                } else {
                    drag.snapped = Snapping.snapFrameOrigin(proposed, size: drag.plan.bounds.size,
                                                            canvas: viewport.documentSize,
                                                            peers: drag.peers,
                                                            columnBands: drag.columns,
                                                            gridSpacing: canvasSnapSpacing,
                                                            gridOrigin: canvasSnapOrigin,
                                                            gridAxes: canvasSnapAxes,
                                                            guides: canvasSnapGuides,
                                                            zoom: viewport.zoom,
                                                            holding: held)
                }
                snapHold.caught(x: drag.snapped.guideX ?? drag.snapped.gridX,
                                y: drag.snapped.guideY ?? drag.snapped.gridY)
                let origins = drag.plan.origins(movingBoundsTo: drag.snapped.origin)
                if drag.copying {
                    onCopyDragPreview(origins)
                } else {
                    onMoveSelectionPreview(origins)
                }
            }
            // Several layers dropped into one collage cell means nothing, so a
            // multi-drag never offers itself to one.
            hoverSlot = nil
            applyGrabCursor(drag.copying ? .dragCopy : nil)
            adoptionHost = isOnASlant(drag.pick.id) ? nil
                : adoptionHost(moving: drag.plan.members.reduce(into: [:]) { boxes, member in
                    guard let origins = drag.liveOrigins, let origin = origins[member.id] else { return }
                    boxes[member.id] = CGRect(origin: origin, size: member.bounds.size)
                })
            multiMove = drag
            refreshOverlays()
        } else if let drag = slotDrag {
            // Swap drag: highlight the destination cell (same collage only).
            if let target = collageSlotTarget(at: p), target.collageID == drag.collageID,
               target.index != drag.from {
                hoverSlot = target
            } else {
                hoverSlot = nil
            }
            refreshOverlays()
        } else if var drag = canvasResizeDrag {
            let base = CGRect(origin: .zero, size: viewport.documentSize)
            var rect = Handles.resize(base, dragging: drag.handle, to: p,
                                      preserveAspect: false, minSize: 16)
            // ⇧ resizes symmetrically around the center: the opposite edge(s)
            // mirror the drag, so content stays centered on commit.
            drag.centered = event.modifierFlags.contains(.shift)
            if drag.centered {
                let dx = drag.handle.movesMaxX ? rect.maxX - base.maxX
                    : (drag.handle.movesMinX ? base.minX - rect.minX : 0)
                let dy = drag.handle.movesMaxY ? rect.maxY - base.maxY
                    : (drag.handle.movesMinY ? base.minY - rect.minY : 0)
                let width = max(16, base.width + 2 * dx)
                let height = max(16, base.height + 2 * dy)
                rect = CGRect(x: base.midX - width / 2, y: base.midY - height / 2,
                              width: width, height: height)
            }
            drag.rect = rect
            canvasResizeDrag = drag
            refreshOverlays()
        } else if var session = regionContentDrag {
            session.current = p
            regionContentDrag = session
            refreshOverlays()
        } else if var session = regionOutlineDrag {
            session.current = p
            regionOutlineDrag = session
            refreshOverlays()
        } else if var session = regionDrag {
            // Both corners are the pointer: a selection is chosen by hand and
            // nothing in the picture pulls it. See `MarqueeDrag.corner`.
            session.drag.update(to: MarqueeDrag.corner(at: p))
            regionDrag = session
            refreshOverlays()
        } else if var drag = marquee {
            drag.update(to: p)
            marquee = drag
            refreshOverlays()
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let viewport else { return }
        if gridOriginDragging {
            gridOriginDragging = false
            snapHold = .none
            snapGuide = nil
            refreshOverlays()
            return
        }
        if guideDragging {
            guideDragging = false
            refreshOverlays()
            return
        }
        // The release of a path-point drag, before the Pen, for the same reason
        // its `mouseDragged` is: with the Pen in hand this drag belongs to the
        // points, and `pathEditMouseUp` answers nothing when no such drag is in
        // flight, so the Pen still gets every press that was really its own.
        if pathEditMouseUp(at: viewport.documentPoint(fromView: convert(event.locationInWindow, from: nil)),
                           event: event) {
            return
        }
        // And the release of a box swept over the points, for the same reason
        // and in the same place: it answers nothing when no sweep is in
        // flight, so every other release is untouched.
        if pathPointSweepMouseUp(atZoom: viewport.zoom) { return }
        if tool == .pen {
            penMouseUp(at: viewport.documentPoint(fromView: convert(event.locationInWindow, from: nil)),
                       event: event)
            return
        }
        if motionPivotDrag != nil || motionPivotCancelled {
            motionPivotMouseUp()
            return
        }
        if motionPathDrag != nil || motionPathCancelled {
            motionPathCancelled = false
            motionPathMouseUp()
            return
        }
        // The measure tool advances its placement on mouse-up (click/click) or on
        // a press-drag release (down/drag/release draws the line).
        if let drag = alignmentDrag {
            alignmentDrag = nil
            alignmentPreviewLayer.isHidden = true
            finishAlignmentDrag(from: drag.anchor,
                                to: viewport.documentPoint(fromView: convert(event.locationInWindow, from: nil)))
            return
        }
        if tool == .measure, measureToolMode.commitsOnClick {
            let up = convert(event.locationInWindow, from: nil)
            measurePressDownView = nil
            hoverPoint = up
            // Commit exactly what the preview was showing. A miss stays a quiet
            // no-op rather than dropping a caliper somewhere arbitrary.
            refreshMeasureCreation(modifierFlags: event.modifierFlags)
            if let rect = measureElementPreview {
                // Grab what the preview steered around before the preview goes:
                // the commit has to place the readouts against the same picture.
                let around = measureElementNeighbors
                hideMeasureHoverReadout()
                onElementSizeCommit(rect, around)
            } else if let gap = measureGapPreview {
                hideMeasureHoverReadout()
                onGapCommit(gap)
            }
            return
        }
        if tool == .measure {
            let up = convert(event.locationInWindow, from: nil)
            let down = measurePressDownView ?? up
            let dragged = hypot(up.x - down.x, up.y - down.y) > 4
            advanceMeasurePlacement(at: viewport.documentPoint(fromView: up),
                                    dragged: dragged, modifiers: event.modifierFlags)
            measurePressDownView = nil
            return
        }
        if cropDrag != nil {
            cropDrag = nil
            if let rect = cropRect { onCropRectChange(rect) }
            // The box just moved under the resting pointer (a fresh rect drawn,
            // a corner dragged), so the pointer has to say what is under it NOW.
            refreshGrabCursor(at: convert(event.locationInWindow, from: nil))
            refreshOverlays()
        } else if let drag = annotationDrag {
            annotationDrag = nil
            snapGuide = nil
            let closedField = pressClosedCaptionField
            pressClosedCaptionField = false
            // The frame tool answers a click as well as a drag: a click drops a
            // frame at the size you made last, which is how a second screen
            // costs one click rather than a trip to a dialog.
            if tool == .frame {
                clearAnnotationPreview()
                let end = drag.isClick(atZoom: viewport.zoom)
                    ? drag.anchor
                    : drag.end(constrained: event.modifierFlags.contains(.shift), shape: .rectangle)
                onFrameCreate(drag.anchor, end)
            } else if tool == .lens, !lensMagnifies, !drag.isClick(atZoom: viewport.zoom) {
                // The composite has to be redrawn for a lens anyway — its
                // picture is whatever is underneath it — so the draft box goes
                // now rather than being held over a commit it cannot match.
                clearAnnotationPreview()
                onLensCreate(drag.anchor,
                             drag.end(constrained: event.modifierFlags.contains(.shift),
                                      shape: .rectangle))
            } else if drag.isClick(atZoom: viewport.zoom) {
                clearAnnotationPreview()
                // The press only dismissed the caption field: the arrow is
                // finished, so Select comes back as it does for Return or Esc.
                if closedField { onToolChange(ArrowCaptionEntry.toolAfterClosing(tool)) }
            } else if toolDragsOutAMagnifiedRegion {
                clearAnnotationPreview()
                let end = drag.end(constrained: event.modifierFlags.contains(.shift), shape: .rectangle)
                // Build the same layer EditorState will commit, to drive the
                // flight animation from source box to placed frame. The
                // magnification comes in with it: built at the default instead,
                // the box flew to a frame the wrong size and then jumped to the
                // right one the moment the real layer landed.
                if let layer = ZoomCalloutBuilder.layer(from: drag.anchor, to: end,
                                                        canvas: viewport.documentSize,
                                                        magnification: calloutMagnification,
                                                        shape: calloutShape,
                                                        avoiding: document?.placedZoomCalloutRects ?? []) {
                    beginCalloutFlight(for: layer)
                    onZoomCalloutCommit(drag.anchor, end)
                }
            } else {
                // Leave the preview shape up until the re-rendered composite
                // (which includes the new layer) lands — no flash.
                annotationCommitImage = image
                let shape = tool.annotationShape ?? .line
                let created = onAnnotationCommit(drag.anchor,
                                                 drag.end(constrained: event.modifierFlags.contains(.shift),
                                                          shape: shape))
                // A fresh arrow immediately offers its caption (Next flag):
                // type to label it, Esc or an empty commit leaves it plain.
                if let created { beginCaptionSession(layer: created) }
            }
        } else if let drag = measureHandleDrag {
            measureHandleDrag = nil
            snapGuide = nil
            // A press that never travelled is a click on the handle, not an
            // edit: the foot or the readout stays exactly where it was placed,
            // the reading is the same number, and no undo step is taken.
            if drag.moved {
                let (start, end, off, readout) = drag.params()
                onMeasureEndpointCommit(drag.layerID, start, end, off, readout)
            } else {
                onMeasureEndpointCancel()
            }
            refreshGrabCursor(at: convert(event.locationInWindow, from: nil))
            refreshOverlays()
        } else if let drag = captionDrag {
            captionDrag = nil
            // A press with no movement is a click on the pill, not a placement:
            // no undo step, the render just settles back.
            let moved = hypot(drag.center.x - drag.startCenter.x,
                              drag.center.y - drag.startCenter.y) * viewport.zoom >= 2
            if moved {
                onCaptionPlaceCommit(drag.layerID, drag.center)
            } else {
                onCaptionPlaceCancel()
            }
            refreshGrabCursor(at: convert(event.locationInWindow, from: nil))
            refreshOverlays()
        } else if let session = endpointDrag {
            endpointDrag = nil
            snapGuide = nil
            let (start, end) = session.drag.endpoints(constrained: event.modifierFlags.contains(.shift))
            // Same no-flash hold as drag-to-create: the vector preview (over
            // the underlay) stands in until the re-rendered composite lands.
            annotationCommitImage = image
            endpointHoldLayerID = session.layerID
            onAnnotationEndpointsCommit(session.layerID, start, end)
            refreshGrabCursor(at: convert(event.locationInWindow, from: nil))
            refreshOverlays()
        } else if let session = transformDrag {
            transformDrag = nil
            if session.transform != session.startTransform {
                // Hold the sprite at the final transform until the post-commit
                // composite lands — otherwise it flashes back.
                transformHold = (session.layerID, session.startTransform, session.transform)
                onTransformCommit(session.layerID, session.transform)
            }
            refreshGrabCursor(at: convert(event.locationInWindow, from: nil))
            refreshOverlays()
        } else if let drag = cornerRadiusDrag {
            cornerRadiusDrag = nil
            // A press that never moved a corner leaves no undo step behind.
            if drag.changed { onCornerRadiiCommit(drag.layerID, drag.radii) }
            refreshGrabCursor(at: convert(event.locationInWindow, from: nil))
            refreshOverlays()
        } else if let drag = resizeDrag {
            resizeDrag = nil
            if drag.frame != drag.startFrame {
                selectedLayerFrame = drag.frame
                holdSpriteUntilRender = true
                onFrameCommit(drag.layerID, drag.frame)
            }
            refreshGrabCursor(at: convert(event.locationInWindow, from: nil))
            refreshOverlays()
        } else if let drag = moveDrag {
            moveDrag = nil
            applyGrabCursor(nil)
            if drag.copying {
                hoverSlot = nil
                if drag.moved {
                    let frame = CGRect(origin: drag.snapped.origin, size: drag.size)
                    // The copy is what ends up selected, and it is the same
                    // size in the same place, so the handles stay put.
                    selectedLayerFrame = frame
                    onCopyDragCommit([drag.layerID: drag.snapped.origin])
                } else {
                    // ⌥ and a click that never travelled: a plain click, and
                    // nothing was ever made.
                    onCopyDragCancel()
                }
                refreshOverlays()
                return
            }
            if drag.moved, let target = hoverSlot,
               document?.canvasLayer(id: drag.layerID)?.imageRef != nil {
                // Released over a collage cell: the photo layer becomes that
                // slot's content instead of landing at the drop position.
                hoverSlot = nil
                onAbsorbLayerIntoCollage(drag.layerID, target.collageID, target.index)
            } else if drag.moved {
                let frame = CGRect(origin: drag.snapped.origin, size: drag.size)
                selectedLayerFrame = frame
                holdSpriteUntilRender = true
                // A piece tidied INSIDE a card on a slant stays in that card.
                // Changing hands is a decision made by where a thing lands on
                // the upright canvas, and this one never left its card.
                if isOnASlant(drag.layerID) {
                    onFrameCommit(drag.layerID, frame)
                } else {
                    onDropCommit(drag.layerID, frame)
                }
            }
            hoverSlot = nil
            adoptionHost = nil
            refreshOverlays()
        } else if let drag = multiMove {
            multiMove = nil
            applyGrabCursor(nil)
            if drag.copying {
                if let origins = drag.liveOrigins { onCopyDragCommit(origins) }
                else { onCopyDragCancel() }
            } else if let origins = drag.liveOrigins {
                onMoveSelectionCommit(origins, !isOnASlant(drag.pick.id))
            }
            // The press kept the whole selection so the group could travel.
            // If it never travelled it was a click on one layer, so now it
            // narrows to that layer — the press-keeps/click-narrows rule every
            // other Mac app follows. ⌥ makes no difference: an ⌥ press that
            // never moved made no copy, so it is a plain click too.
            if PickedMemberPress(moved: drag.moved).narrowsSelection {
                // The frame goes in first so the handles land on the layer in
                // the same beat as the click, rather than a refresh later.
                selectedLayerFrame = document?.canvasLayer(id: drag.pick.id).map { $0.withoutSlack($0.frame) }
                onSelectLayerInGroup(drag.pick.id, drag.pick.context)
            }
            adoptionHost = nil
            refreshOverlays()
        } else if let drag = slotDrag {
            slotDrag = nil
            if let target = hoverSlot, target.collageID == drag.collageID {
                onSwapCollageSlots(drag.collageID, drag.from, target.index)
            }
            hoverSlot = nil
            refreshOverlays()
        } else if let drag = canvasResizeDrag {
            canvasResizeDrag = nil
            let size = CGSize(width: drag.rect.width.rounded(), height: drag.rect.height.rounded())
            if size != viewport.documentSize {
                onCanvasResize(size, drag.centered ? .center : .fixing(oppositeOf: drag.handle))
            }
            refreshGrabCursor(at: convert(event.locationInWindow, from: nil))
            refreshOverlays()
        } else if let session = regionContentDrag {
            regionContentDrag = nil
            let delta = roundedDelta(from: session.start, to: session.current)
            if delta == .zero {
                onRegionMoveCancel()
            } else {
                // Hold the sprite at its destination until the baked
                // composite lands (the standard no-flash trick).
                regionMoveHoldFrame = session.frame.offsetBy(dx: delta.x, dy: delta.y)
                onRegionMoveCommit(delta)
            }
            refreshOverlays()
        } else if let session = regionOutlineDrag {
            regionOutlineDrag = nil
            let delta = roundedDelta(from: session.start, to: session.current)
            if delta != .zero,
               let moved = session.base.translated(by: CGVector(dx: delta.x, dy: delta.y)) {
                commitSelection(moved, capture: false)
            } else {
                refreshOverlays()
            }
        } else if let session = regionDrag {
            regionDrag = nil
            snapGuide = nil
            if session.drag.isClick(atZoom: viewport.zoom) {
                // A plain click deselects (Photoshop); a click with a combine
                // modifier held contributes nothing and changes nothing.
                if session.mode == .replace {
                    commitSelection(nil, capture: false)
                } else {
                    refreshOverlays()
                }
            } else {
                let shape = session.drag.selectionRect(in: viewport.documentSize)
                    .map(Geometry.pixelAligned)
                    .flatMap { session.isEllipse ? SelectionRegion.ellipse(in: $0) : SelectionRegion.rect($0) }
                if let shape {
                    commitSelection(SelectionRegion.combine(selection, with: shape, mode: session.mode),
                                    capture: false)
                } else {
                    refreshOverlays()
                }
            }
        } else if let drag = marquee {
            marquee = nil
            let press = marqueePress
            let level = marqueeContext
            let clickTarget = marqueeClickTarget
            marqueePress = .replaces
            marqueeContext = nil
            marqueeClickTarget = nil
            // The band was started on a screen's surface and never travelled,
            // so it was a click on that screen, and it still means everything
            // a click on a screen's surface has always meant: plain picks the
            // screen, ⇧ adds it to what is picked or drops it again. Only the
            // DRAG changed meaning.
            if drag.isClick(atZoom: viewport.zoom), let clickTarget,
               document?.canvasLayer(id: clickTarget) != nil {
                if press.sweepAddsToSelection {
                    onExtendSelection(clickTarget)
                } else {
                    selectedLayerFrame = document?.canvasLayer(id: clickTarget)
                        .map { $0.withoutSlack($0.frame) }
                    onSelectLayerInGroup(clickTarget, document?.parentID(of: clickTarget))
                }
                refreshOverlays()
                return
            }
            guard press.commitsOnRelease(isClick: drag.isClick(atZoom: viewport.zoom)) else {
                // A ⇧-click that landed on nothing: the band comes down and
                // the selection stays exactly as it was.
                refreshOverlays()
                return
            }
            if drag.isClick(atZoom: viewport.zoom) {
                // A plain click on bare canvas is the gesture that means
                // "nothing", so THIS is where the selection is let go — the
                // press used to do it, which threw the pick away before the
                // gesture had said whether it was a click or a band.
                // Nothing includes the level you were working at: the click
                // steps back out of the group, the way a click on a layer
                // outside it already does. Without that a click that let go of
                // several pieces at once left you standing inside a group with
                // nothing picked, and the next sweep would still be looking
                // inside it.
                selectedLayerFrame = nil
                onSelectLayer(nil) // also drops the Canvas pseudo-selection
                commitSelection(nil, capture: true)
                return
            }
            // A sweep decides the selection whatever started it, so the
            // Library tile lets go here the way the plain press already did.
            if !press.clearsSelectionOnPress { onClickedNothing() }
            let region = drag.selectionRect(in: viewport.documentSize)
                .map(Geometry.pixelAligned).flatMap(SelectionRegion.rect)
            if press.sweepAddsToSelection {
                // ⇧-sweep: the catch joins what was already picked. The band
                // itself comes down, because it describes only this sweep and
                // not the whole selection — the outlines carry that, the same
                // way they do after a ⇧-click on the picture. A pixel region
                // belongs to the region tools, so that one stays put.
                if let region {
                    if !selectionTargetsPixels { selection = nil }
                    onAddSweptLayers(region, level)
                } else {
                    refreshOverlays() // swept only empty space: nothing changes
                }
                return
            }
            commitSelection(region, capture: true, inside: level)
        }
    }

    /// `run` names a burst of changes that undo as one act: the arrow keys
    /// walking the outline are one, a drag or a click is not.
    func commitSelection(_ region: SelectionRegion?, capture: Bool,
                                 inside context: UUID? = nil, run: String? = nil) {
        selection = region
        refreshOverlays()
        onSelectionChange(region, capture, context, run)
    }
}
