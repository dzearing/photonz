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
        // Placing the grid's zero point owns the whole canvas: a press moves
        // the two markers to the pointer and nothing else on the canvas can be
        // picked up, selected or edited by accident.
        if gridOriginAdjust != nil {
            window?.makeFirstResponder(self)
            gridOriginDragging = true
            moveGridOrigin(toViewPoint: convert(event.locationInWindow, from: nil),
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
                selectedLayerFrame = document?.canvasLayer(id: named).map { $0.withoutSlack($0.frame) }
                onSelectLayerInGroup(named, document?.parentID(of: named))
                refreshOverlays()
            }
            return
        }
        // Double-click the window background — the matte OR the locked base image,
        // i.e. anywhere that isn't an editable layer — performs the standard
        // window zoom. `.hiddenTitleBar` leaves no real title bar to double-click,
        // and on an image that fills the window the matte alone wasn't reachable,
        // so this makes "double-click the bg to maximize" work everywhere. Editable
        // layers (text/annotations) stay double-click-to-edit.
        if event.clickCount == 2, document?.canvasHitTest(p, zoom: viewport.zoom) == nil {
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
                                        screenTolerance: CanvasPointer.cropTolerance) {
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
        // composite sweep is heavy); rect/ellipse start a marquee whose
        // corners magnetize to detected edges (⌘ = free). The combine mode
        // (⇧ add / ⌥ subtract / ⇧⌥ intersect) latches at gesture start.
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
            var anchor = p
            if !event.modifierFlags.contains(.command) {
                anchor = EdgeSnapping.snap(p, edges: edgeMap, zoom: viewport.zoom).point
            }
            resetDragMotion(p)
            regionDrag = (MarqueeDrag(anchor: anchor), mode, tool == .ellipseSelect)
            refreshOverlays()
            return
        }
        // Drawing tools own the pointer: every drag creates a new annotation
        // (or, for the zoom tool, defines the callout's source box).
        if tool.createsAnnotationByDrag || tool == .zoomCallout || tool == .frame {
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
                                    zoom: viewport.zoom, screenTolerance: 8) {
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
        if let id = selectedLayerID, let layer = selectedLayer, offersOwnHandles(layer),
           let content = layer.annotation,
           let endpoint = AnnotationEndpoints.hit(at: p, layer: layer, zoom: viewport.zoom),
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
            if pill.insetBy(dx: -tolerance, dy: -tolerance).contains(p) {
                let center = CGPoint(x: pill.midX, y: pill.midY)
                captionDrag = CaptionDrag(layerID: id,
                                          grip: CGSize(width: p.x - center.x, height: p.y - center.y),
                                          startCenter: center, current: p)
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
            let tolerance = viewport.zoom > 0 ? 9 / viewport.zoom : 9
            var best: (handle: MeasureHandle, distance: CGFloat)?
            for h in measureHandles(layer) {
                let d = hypot(p.x - h.point.x, p.y - h.point.y)
                if d <= tolerance, d < (best?.distance ?? .infinity) {
                    best = (h.handle, d)
                }
            }
            if best == nil, let pill = measureReadoutRect(layer),
               pill.insetBy(dx: -tolerance, dy: -tolerance).contains(p) {
                best = (.head, 0)
            }
            if let best {
                resetDragMotion(p)
                var drag = MeasureHandleDrag(
                    layerID: id, handle: best.handle, mode: m.mode,
                    originalStart: s, originalEnd: e, originalHeadOffset: m.headOffset,
                    originalReadout: MeasureReadoutPlacement(nudge: m.labelNudge,
                                                             pinned: m.labelPinned),
                    current: p)
                if best.handle == .head {
                    let head = MeasureContent.caliperGeometry(mode: m.mode, start: s, end: e,
                                                              headOffset: m.headOffset).labelAnchor
                    drag.grabCross = m.mode == .horizontal ? p.y - head.y : p.x - head.x
                    if let dm = documentMeasure(layer) {
                        let pill = dm.labelPosition(chipSize: dm.estimatedLabelSize)
                        drag.grabAlong = m.mode == .horizontal ? p.x - pill.x : p.y - pill.y
                    }
                    drag.guides = measureChipGuideLines(excluding: id)
                } else {
                    drag.guides = measureGuideLines(excluding: id)
                }
                measureHandleDrag = drag
                // The hand that invited this drag closes for its duration —
                // number, foot or head dot alike.
                if grabCue(at: p) != nil { applyGrabCursor(.closedHand) }
                refreshOverlays()
                return
            }
        }
        // Rotate knob, floated off the selected layer's top edge.
        if let id = selectedLayerID, let layer = selectedLayer, offersRotation(layer),
           let knob = layer.rotateKnobPoint(zoom: viewport.zoom),
           hypot(p.x - knob.x, p.y - knob.y) * viewport.zoom <= CanvasPointer.rotateTolerance {
            let center = CGPoint(x: layer.frame.midX, y: layer.frame.midY)
            transformDrag = TransformDragSession(
                layerID: id, kind: .rotate(grabAngle: TransformDrag.pointerAngle(p, around: center)),
                startTransform: layer.transform, center: center,
                frameSize: layer.frame.size, transform: layer.transform)
            applyGrabCursor(CanvasCursor.cursor(for: .rotate, transform: layer.transform))
            onDragBegin(id)
            refreshOverlays()
            return
        }
        // Frame handles. The pointer maps through the layer's inverse
        // transform so handles on a rotated/skewed layer hit where they draw.
        // ⌥ on a corner skews instead of resizing.
        if let id = selectedLayerID, let frame = selectedLayerFrame,
           selectedLayer.map(offersOwnHandles) ?? true, selectedLayer?.allowsFrameResize ?? true,
           let handle = Handles.hit(at: handleSpacePoint(p, layer: selectedLayer),
                                    frame: frame, zoom: viewport.zoom) {
            if event.modifierFlags.contains(.option), handle.isCorner, let layer = selectedLayer {
                transformDrag = TransformDragSession(
                    layerID: id, kind: .skew(corner: handle, grabPoint: p),
                    startTransform: layer.transform,
                    center: CGPoint(x: layer.frame.midX, y: layer.frame.midY),
                    frameSize: layer.frame.size, transform: layer.transform)
            } else {
                let untransformed = selectedLayer?.transform.isIdentity ?? true
                resizeDrag = ResizeDrag(
                    layerID: id, handle: handle, startFrame: frame, frame: frame,
                    peers: Experiments.shared.alignLayersEnabled && untransformed
                        ? (document?.snapPeers(excluding: id) ?? []) : [],
                    columns: untransformed ? columnBands(excluding: [id]) : [],
                    snapped: Snapping.FrameResult(frame: frame))
                applyGrabCursor(CanvasCursor.cursor(for: .resize(handle),
                                                    transform: selectedLayer?.transform ?? .identity))
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
                multiMove = MultiMoveDrag(
                    plan: plan,
                    pick: pick,
                    grabOffset: CGPoint(x: p.x - plan.bounds.origin.x,
                                        y: p.y - plan.bounds.origin.y),
                    peers: Experiments.shared.alignLayersEnabled
                        ? (document?.snapPeers(excluding: multiSelectedLayerIDs) ?? []) : [],
                    columns: columnBands(excluding: multiSelectedLayerIDs),
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
            selectedLayerFrame = seen
            moveDrag = MoveDrag(layerID: hit.id,
                                grabOffset: CGPoint(x: p.x - seen.origin.x,
                                                    y: p.y - seen.origin.y),
                                size: seen.size,
                                startOrigin: seen.origin,
                                peers: Experiments.shared.alignLayersEnabled
                                    ? (document?.snapPeers(excluding: hit.id) ?? []) : [],
                                columns: columnBands(excluding: [hit.id]),
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
            if press.clearsSelectionOnPress {
                onClickedNothing()
                if selectedLayerFrame != nil || isCanvasSelected {
                    selectedLayerFrame = nil
                    onSelectLayer(nil) // also drops the Canvas pseudo-selection
                }
            }
            marquee = MarqueeDrag(anchor: p)
        }
        refreshOverlays()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let viewport else { return }
        if gridOriginDragging {
            moveGridOrigin(toViewPoint: convert(event.locationInWindow, from: nil),
                           freeing: event.modifierFlags.contains(.command))
            return
        }
        let p = viewport.documentPoint(fromView: convert(event.locationInWindow, from: nil))
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
            let held = snapHold(freeing: event.modifierFlags.contains(.command))
            if drag.handle == .head {
                snapGuide = snapMeasureHead(&drag, pointer: p, zoom: viewport.zoom,
                                            snapping: !held.isFree, holding: held)
                snapHold.caught(x: snapGuide?.x, y: snapGuide?.y)
            } else if held.isFree {
                drag.current = p
                snapGuide = nil
            } else {
                trackDragMotion(p)
                // Window the edge candidates by the span from the opposite foot to
                // the pointer, exactly like the create drag.
                let fixed = drag.handle == .footA ? drag.originalEnd : drag.originalStart
                let snap = axisGated(
                    EdgeSnapping.snap(p, edges: edgeMap, zoom: viewport.zoom,
                                      xSpan: min(fixed.x, p.x)...max(fixed.x, p.x),
                                      ySpan: min(fixed.y, p.y)...max(fixed.y, p.y),
                                      includeCenters: measureSnapsToCenters,
                                      guides: drag.guides,
                                      holding: held),
                    raw: p)
                drag.current = snap.point
                snapGuide = (snap.guideX, snap.guideY)
                snapHold.caught(x: snap.guideX, y: snap.guideY)
            }
            measureHandleDrag = drag
            // Live re-render so the measured value updates as the handle moves.
            let (start, end, off, readout) = drag.params()
            onMeasureEndpointPreview(drag.layerID, start, end, off, readout)
            refreshOverlays()
        } else if var drag = captionDrag {
            drag.current = p
            captionDrag = drag
            // Live re-render so the pill follows the pointer.
            onCaptionPlacePreview(drag.layerID, drag.center)
            refreshOverlays()
        } else if var session = endpointDrag {
            session.drag.update(to: snappedAnnotationPoint(p, shape: session.content.shape,
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
                    currentAngle: TransformDrag.pointerAngle(p, around: session.center),
                    snapped: event.modifierFlags.contains(.shift))
            case .skew(let corner, let grabPoint):
                session.transform = TransformDrag.skewed(
                    session.startTransform, corner: corner,
                    by: CGPoint(x: p.x - grabPoint.x, y: p.y - grabPoint.y),
                    frameSize: session.frameSize)
            }
            transformDrag = session
            onTransformPreview(session.layerID, session.transform)
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
            drag.snapped = resizedFrame(for: layer, start: drag.startFrame, handle: drag.handle,
                                        pointer: p, preserveAspect: aspect,
                                        peers: snapping ? drag.peers : [],
                                        columns: snapping ? drag.columns : [],
                                        gridSpacing: snapping ? canvasSnapSpacing : nil,
                                        gridOrigin: canvasSnapOrigin,
                                        gridAxes: canvasSnapAxes,
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
            let proposed = CGPoint(x: p.x - drag.grabOffset.x, y: p.y - drag.grabOffset.y)
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
                    drag.snapped = Snapping.snapFrameOrigin(proposed, size: drag.size,
                                                            canvas: viewport.documentSize,
                                                            peers: drag.peers,
                                                            columnBands: drag.columns,
                                                            gridSpacing: canvasSnapSpacing,
                                                            gridOrigin: canvasSnapOrigin,
                                                            gridAxes: canvasSnapAxes,
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
            if drag.moved, !drag.copying, document?.canvasLayer(id: drag.layerID)?.imageRef != nil {
                hoverSlot = collageSlotTarget(at: p, excluding: drag.layerID)
            } else {
                hoverSlot = nil
            }
            applyGrabCursor(drag.copying ? .dragCopy : nil)
            adoptionHost = drag.moved
                ? adoptionHost(moving: [drag.layerID: CGRect(origin: drag.snapped.origin,
                                                             size: drag.size)])
                : nil
            moveDrag = drag
            refreshOverlays()
        } else if var drag = multiMove {
            let proposed = CGPoint(x: p.x - drag.grabOffset.x, y: p.y - drag.grabOffset.y)
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
            adoptionHost = adoptionHost(moving: drag.plan.members.reduce(into: [:]) { boxes, member in
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
            // Same corner magnetizing as a measure drag: the growing edges
            // window the candidates; ⌘ drags free.
            let held = snapHold(freeing: event.modifierFlags.contains(.command))
            if held.isFree {
                session.drag.update(to: p)
                snapGuide = nil
            } else {
                trackDragMotion(p)
                let snap = axisGated(
                    EdgeSnapping.snap(p, edges: edgeMap, zoom: viewport.zoom,
                                      xSpan: min(session.drag.anchor.x, p.x)...max(session.drag.anchor.x, p.x),
                                      ySpan: min(session.drag.anchor.y, p.y)...max(session.drag.anchor.y, p.y),
                                      holding: held),
                    raw: p)
                session.drag.update(to: snap.point)
                snapGuide = (snap.guideX, snap.guideY)
                snapHold.caught(x: snap.guideX, y: snap.guideY)
            }
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
            } else if drag.isClick(atZoom: viewport.zoom) {
                clearAnnotationPreview()
                // The press only dismissed the caption field: the arrow is
                // finished, so Select comes back as it does for Return or Esc.
                if closedField { onToolChange(ArrowCaptionEntry.toolAfterClosing(tool)) }
            } else if tool == .zoomCallout {
                clearAnnotationPreview()
                let end = drag.end(constrained: event.modifierFlags.contains(.shift), shape: .rectangle)
                // Build the same layer EditorState will commit, to drive the
                // flight animation from source box to placed frame.
                if let layer = ZoomCalloutBuilder.layer(from: drag.anchor, to: end,
                                                        canvas: viewport.documentSize,
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
            let (start, end, off, readout) = drag.params()
            onMeasureEndpointCommit(drag.layerID, start, end, off, readout)
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
                onDropCommit(drag.layerID, frame)
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
                onMoveSelectionCommit(origins, true)
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
            marqueePress = .replaces
            marqueeContext = nil
            guard press.commitsOnRelease(isClick: drag.isClick(atZoom: viewport.zoom)) else {
                // A ⇧-click that landed on nothing: the band comes down and
                // the selection stays exactly as it was.
                refreshOverlays()
                return
            }
            if drag.isClick(atZoom: viewport.zoom) {
                commitSelection(nil, capture: true) // a plain click deselects
                // Bare canvas means "nothing", and nothing includes the level
                // you were working at: the click steps back out of the group,
                // the way a click on a layer outside it already does. Without
                // this a click that let go of several pieces at once left you
                // standing inside a group with nothing picked, and the next
                // sweep would still be looking inside it.
                if level != nil { onSelectLayer(nil) }
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

    func commitSelection(_ region: SelectionRegion?, capture: Bool,
                                 inside context: UUID? = nil) {
        selection = region
        refreshOverlays()
        onSelectionChange(region, capture, context)
    }
}
