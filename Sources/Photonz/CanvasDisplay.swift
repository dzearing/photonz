import AppKit
import PhotonzCore
import PhotonzRender
import SwiftUI

// Drawing the canvas: the composite, the selection, the handles, the crop
// chrome, the marquee, the drag sprite and the snap guides. Everything here
// reads state and writes Core Animation layers. Split out of CanvasView.swift;
// `CanvasNSView`'s stored properties still live there.

extension CanvasNSView {
    // MARK: Display

    /// Everything the canvas is showing, in one call, from the SwiftUI view
    /// that owns it — and that is the ONLY caller. None of these carry a
    /// default on purpose: a defaulted argument here is a piece of the canvas
    /// that a second caller can silently switch off by not mentioning it,
    /// which is exactly how a pinch used to take the grid out. Anything that
    /// changes only part of the canvas gets its own method, like
    /// `applyViewport`.
    func apply(image: CGImage?, viewport: Viewport?, document: PhotonzDocument?,
               selection: SelectionRegion?, selectionTargetsPixels: Bool,
               cropRect: CGRect?, cropAspect: CropAspect,
               cropBounds: CGRect?, selectedLayerID: UUID?, selectedLayerFrame: CGRect?,
               groupContext: UUID?,
               multiSelectedLayerIDs: Set<UUID>,
               dragPreview: DragPreview?, tool: Tool, captionCloseRequest: Int,
               annotationContent: AnnotationContent?,
               calloutShape: ZoomCalloutShape,
               annotationStyle: LayerStyle?,
               textContent: TextContent?, measureContent: MeasureContent?,
               measureToolMode: MeasureToolMode,
               measureCandidateLevel: Int,
               measureSnapsToCenters: Bool,
               edgeMap: EdgeMap, lumaField: LumaField,
               isCanvasSelected: Bool,
               canvasGrid: CanvasGridSettings?,
               gridOriginAdjust: CGPoint?) {
        self.canvasGrid = canvasGrid
        let wasPlacingGridOrigin = self.gridOriginAdjust != nil
        if self.gridOriginAdjust != gridOriginAdjust {
            self.gridOriginAdjust = gridOriginAdjust
            // Leaving the mode drops whatever the markers had caught, so a
            // stale yellow line never outlives the placement.
            if gridOriginAdjust == nil {
                gridOriginDragging = false
                snapHold = .none
                snapGuide = nil
                applyGrabCursor(nil, force: true)
            } else if !wasPlacingGridOrigin {
                // The mode is usually entered from a menu or a button in the
                // panel, which leaves the keyboard there. The arrow keys are
                // half the feature, so the canvas takes it back rather than
                // waiting for a click to earn it.
                window?.makeFirstResponder(self)
                applyGrabCursor(.crosshair, force: true)
            }
        }
        self.multiSelectedLayerIDs = multiSelectedLayerIDs
        if self.isCanvasSelected != isCanvasSelected {
            self.isCanvasSelected = isCanvasSelected
            if !isCanvasSelected { canvasResizeDrag = nil }
        }
        self.annotationContent = annotationContent
        self.calloutShape = calloutShape
        self.annotationStyle = annotationStyle
        self.textContent = textContent
        self.measureContent = measureContent
        if measureToolMode != self.measureToolMode {
            // Switching Measure modes abandons whichever draft was in flight.
            self.measureToolMode = measureToolMode
            cancelMeasurePlacement()
            // Picking a mode in the tool options leaves the focus on a button, so
            // the canvas takes it back: otherwise `[` and `]` would go nowhere
            // until you had clicked the image at least once.
            if measureToolMode.picksAmongCandidates { window?.makeFirstResponder(self) }
        }
        if measureCandidateLevel != self.measureCandidateLevel {
            self.measureCandidateLevel = measureCandidateLevel
            refreshMeasureCreation(modifierFlags: [])
        }
        self.measureSnapsToCenters = measureSnapsToCenters
        self.edgeMap = edgeMap
        self.lumaField = lumaField
        self.cropAspect = cropAspect
        self.cropBounds = cropBounds
        if tool != self.tool {
            self.tool = tool
            // A tool switch mid-drag abandons the draft annotation/endpoint edit
            // and any in-progress caliper placement.
            annotationDrag = nil
            measurePlacement = nil
            measureFirstFootPress = false
            measurePressDownView = nil
            measureHandleDrag = nil
            if captionDrag != nil {
                captionDrag = nil
                onCaptionPlaceCancel()
            }
            alignmentDrag = nil
            alignmentPreviewLayer.isHidden = true
            regionDrag = nil
            regionOutlineDrag = nil
            if regionContentDrag != nil {
                regionContentDrag = nil
                onRegionMoveCancel()
            }
            snapGuide = nil
            applyGrabCursor(nil, force: true)
            endpointDrag = nil
            cropDrag = nil
            transformDrag = nil
            transformHold = nil
            hideMeasureHoverReadout()
            clearAnnotationPreview()
            // …but a typed text draft is worth keeping: commit it. Deferred a
            // tick because this runs inside a SwiftUI update. (A fresh arrow's
            // caption field no longer sees a tool switch on landing: the Arrow
            // tool stays in hand until the field closes.)
            if textSession != nil {
                DispatchQueue.main.async { [weak self] in self?.commitTextSession() }
            }
            pressClosedCaptionField = false
            window?.invalidateCursorRects(for: self)
        }
        if captionCloseRequest != self.captionCloseRequest {
            self.captionCloseRequest = captionCloseRequest
            // The tool bar re-picked the tool in hand while the caption field
            // was open: commit the draft and keep the tool. Deferred a tick,
            // like the tool-switch commit above, because this runs inside a
            // SwiftUI update.
            if textSession?.captionStyle != nil {
                DispatchQueue.main.async { [weak self] in self?.commitTextSession(keepTool: true) }
            }
        }
        // Undo while editing can delete the layer behind the editor.
        if let session = textSession, let layerID = session.layerID,
           let document, document.canvasLayer(id: layerID) == nil {
            DispatchQueue.main.async { [weak self] in self?.cancelTextSession() }
        }
        // The post-commit composite (a different image) now includes the new
        // annotation layer; the held preview shape can come down.
        if annotationCommitImage != nil, image !== annotationCommitImage {
            clearAnnotationPreview()
        }
        self.image = image
        self.viewport = viewport
        self.document = document
        self.selectedLayerID = selectedLayerID
        self.dragPreview = dragPreview
        // The post-commit composite has landed once the preview is cleared; the
        // sprite hold is no longer needed (and must not linger over a selection).
        if dragPreview == nil {
            holdSpriteUntilRender = false
            regionMoveHoldFrame = nil
        }
        // The held delta is only needed while the sprite is still floating.
        if let hold = transformHold, dragPreview?.layerID != hold.layerID {
            transformHold = nil
        }
        // While the user is mid-drag the local state is the truth; don't let an
        // unrelated SwiftUI update echo stale committed values over it.
        if marquee == nil, regionDrag == nil, regionOutlineDrag == nil, regionContentDrag == nil {
            self.selection = selection
            self.selectionTargetsPixels = selectionTargetsPixels
        }
        if cropDrag == nil {
            self.cropRect = cropRect
        }
        if moveDrag == nil, resizeDrag == nil {
            self.selectedLayerFrame = selectedLayerFrame
        }
        self.groupContext = groupContext
        // The document or the selection just changed under a resting pointer (a
        // drag landed, an undo moved a pill): the grab cue has to agree with
        // what is under the pointer NOW, not at the next mouse move.
        refreshGrabCursor()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        guard let image, let viewport else {
            endCalloutFlight()
            contentLayer.isHidden = true
            crispLayer.isHidden = true
            previewSpriteLayer.isHidden = true
            selectionBaseLayer.isHidden = true
            selectionAntsLayer.isHidden = true
            layerOutlineLayer.isHidden = true
            snapGuideLayer.isHidden = true
            snapDotLayer.isHidden = true
            hideMeasureHoverReadout()
            handlesLayer.isHidden = true
            rotateKnobLayer.isHidden = true
            annotationPreviewLayer.isHidden = true
            cropDimLayer.isHidden = true
            cropGridLayer.isHidden = true
            cropBorderLayer.isHidden = true
            cropHandlesLayer.isHidden = true
            if textSession != nil {
                DispatchQueue.main.async { [weak self] in self?.cancelTextSession() }
            }
            return
        }
        contentLayer.isHidden = false
        // refreshPreviewSprite (below) swaps in the underlay + floated sprite
        // while a drag preview is active; the full render replaces both after.
        // A callout flight holds the pre-commit composite so the baked-in
        // callout doesn't show at its destination before the sprite lands.
        contentLayer.contents = calloutHoldImage ?? image
        contentLayer.frame = viewport.documentFrameInView
        contentLayer.shadowPath = CGPath(rect: contentLayer.bounds, transform: nil)
        // Past 2× the user is inspecting pixels — show them squarely instead of smearing.
        contentLayer.magnificationFilter = viewport.zoom >= 2 ? .nearest : .linear

        refreshOverlaysInsideTransaction()
    }

    /// Takes delivery of a redrawn patch of what you can see.
    func applyCrispTile(_ tile: CrispTile?, viewport tileViewport: Viewport?) {
        guard crispTile?.image !== tile?.image || crispTileViewport != tileViewport else { return }
        crispTile = tile
        crispTileViewport = tileViewport
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        refreshCrispDisplay()
        CATransaction.commit()
    }

    /// Lays the redrawn patch over the composite, or takes it away.
    ///
    /// It only goes up while it is still a picture of THIS moment: the camera
    /// where it was drawn, the composite it was drawn from. A drag floats a
    /// sprite over a held-back composite and a callout flight holds the frame
    /// from before the callout landed, so both of those hide it rather than
    /// let a sharp copy of the settled document contradict what is on screen.
    private func refreshCrispDisplay() {
        guard let viewport, let tile = crispTile, crispTileViewport == viewport,
              !contentLayer.isHidden, dragPreview == nil, calloutHoldImage == nil else {
            if !crispLayer.isHidden {
                crispLayer.isHidden = true
                crispLayer.contents = nil
            }
            return
        }
        crispLayer.contents = tile.image
        crispLayer.frame = viewRect(forDocRect: tile.region, in: viewport)
        crispLayer.contentsScale = window?.backingScaleFactor ?? 2
        // At 1:1 with the screen this never resamples; the filter only matters
        // if a fractional zoom leaves it a hair off.
        crispLayer.magnificationFilter = viewport.zoom >= 2 ? .nearest : .linear
        crispLayer.isHidden = false
    }

    func refreshOverlays() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        refreshOverlaysInsideTransaction()
        CATransaction.commit()
    }

    func refreshOverlaysInsideTransaction() {
        refreshCanvasGrid()
        refreshCrispDisplay()
        refreshMarqueeDisplay()
        refreshLayerSelectionDisplay()
        refreshCropDisplay()
        refreshPreviewSprite()
        refreshTextEditorDisplay()
        refreshCollageChrome()
        refreshDropLanding()
        refreshMeasureCreation(modifierFlags: NSEvent.modifierFlags)
    }

    /// Editor-only collage chrome: dashed wells with a plus glyph over every
    /// empty slot (drop discovery), and the accent highlight on whichever slot
    /// an eligible drag currently hovers. Wells skip transformed collages —
    /// axis-aligned chrome on a rotated layer would lie about the target.
    private func refreshCollageChrome() {
        guard let viewport, let document else {
            collageWellsLayer.isHidden = true
            slotHighlightLayer.isHidden = true
            return
        }
        let wells = CGMutablePath()
        for layer in document.layers
        where layer.isVisible && layer.collage != nil && layer.transform.isIdentity {
            guard let content = layer.collage else { continue }
            let cells = Collage.slotFrames(for: content, in: layer.frame.size)
            for (slot, cell) in zip(content.slots, cells) where slot.imageRef == nil {
                let docRect = cell.offsetBy(dx: layer.frame.minX, dy: layer.frame.minY)
                let rect = viewRect(forDocRect: docRect, in: viewport).insetBy(dx: 2, dy: 2)
                guard rect.width > 8, rect.height > 8 else { continue }
                let radius = min(6, rect.width / 2, rect.height / 2)
                wells.addRoundedRect(in: rect, cornerWidth: radius, cornerHeight: radius)
                let arm = min(10, rect.width / 4, rect.height / 4)
                let center = CGPoint(x: rect.midX, y: rect.midY)
                wells.move(to: CGPoint(x: center.x - arm, y: center.y))
                wells.addLine(to: CGPoint(x: center.x + arm, y: center.y))
                wells.move(to: CGPoint(x: center.x, y: center.y - arm))
                wells.addLine(to: CGPoint(x: center.x, y: center.y + arm))
            }
        }
        collageWellsLayer.path = wells
        collageWellsLayer.isHidden = wells.isEmpty

        if let hoverSlot, let layer = document.canvasLayer(id: hoverSlot.collageID),
           let content = layer.collage {
            let cells = Collage.slotFrames(for: content, in: layer.frame.size)
            if cells.indices.contains(hoverSlot.index) {
                let docRect = cells[hoverSlot.index].offsetBy(dx: layer.frame.minX, dy: layer.frame.minY)
                slotHighlightLayer.path = CGPath(rect: viewRect(forDocRect: docRect, in: viewport),
                                                 transform: nil)
                slotHighlightLayer.isHidden = false
                return
            }
        }
        slotHighlightLayer.isHidden = true
    }

    /// Where the drag in the air would land: a filled outline the exact size of
    /// what it is carrying, plus a dashed box around the frame it would join.
    /// Both are gone the moment the drag leaves or lands.
    private func refreshDropLanding() {
        guard let viewport else {
            dropLandingLayer.isHidden = true
            dropHostFrameLayer.isHidden = true
            return
        }
        guard let landing = dropLanding else {
            dropLandingLayer.isHidden = true
            // A move drag draws no landing box — the layer itself is already
            // under the pointer, so a second outline of the same size would
            // just double the edge — but it draws the same dashed screen.
            outlineHostFrame(adoptionHost, in: viewport)
            return
        }
        let rect = viewRect(forDocRect: landing.rect, in: viewport)
        let radius = min(6, rect.width / 2, rect.height / 2)
        dropLandingLayer.path = CGPath(roundedRect: rect, cornerWidth: radius,
                                            cornerHeight: radius, transform: nil)
        dropLandingLayer.isHidden = false

        outlineHostFrame(landing.host, in: viewport)
    }

    /// The dashed box around the screen a drop would join. Drawn just OUTSIDE
    /// the frame: something the same size as the screen it is joining would
    /// otherwise hide the very cue that says so.
    private func outlineHostFrame(_ host: UUID?, in viewport: Viewport) {
        guard let host, let bounds = document?.canvasBounds(of: host) else {
            dropHostFrameLayer.isHidden = true
            return
        }
        let box = viewRect(forDocRect: bounds, in: viewport).insetBy(dx: -3, dy: -3)
        dropHostFrameLayer.path = CGPath(rect: box, transform: nil)
        dropHostFrameLayer.isHidden = false
    }

    /// The topmost visible, unlocked collage layer whose slot contains the
    /// document-space point (gutters and backdrop margins don't count).
    func collageSlotTarget(at p: CGPoint,
                                   excluding excluded: UUID? = nil) -> (collageID: UUID, index: Int)? {
        guard let document else { return nil }
        for layer in document.layers.reversed()
        where layer.collage != nil && layer.id != excluded && layer.isVisible && !layer.isLocked {
            if let slot = Collage.slotIndex(at: p, in: layer) { return (layer.id, slot) }
        }
        return nil
    }

    /// Crop chrome: dimmed surround (even-odd: document frame minus the crop
    /// rect), rule-of-thirds grid, white border, eight handles.
    private func refreshCropDisplay() {
        guard tool == .crop, let viewport, let rect = cropRect else {
            cropDimLayer.isHidden = true
            cropGridLayer.isHidden = true
            cropBorderLayer.isHidden = true
            cropHandlesLayer.isHidden = true
            return
        }
        let rectInView = viewRect(forDocRect: rect, in: viewport)

        // For a per-layer crop the dim covers just the layer's frame — only
        // that layer's pixels outside the rect go away.
        let dim = CGMutablePath()
        if let cropBounds {
            dim.addRect(viewRect(forDocRect: cropBounds, in: viewport))
        } else {
            dim.addRect(viewport.documentFrameInView)
        }
        dim.addRect(rectInView)
        cropDimLayer.path = dim

        let grid = CGMutablePath()
        for line in Crop.thirdsLines(in: rect) {
            grid.move(to: viewport.viewPoint(fromDocument: line.from))
            grid.addLine(to: viewport.viewPoint(fromDocument: line.to))
        }
        cropGridLayer.path = grid

        cropBorderLayer.path = CGPath(rect: rectInView, transform: nil)

        let handles = CGMutablePath()
        // A crop box dragged down to a thumbnail gets the same treatment as a
        // tiny layer: handles step outside it so there is still a middle to
        // pick the box up by. `Handles.layout` is what the press reads too.
        let cropHandleLayout = Handles.layout(in: rect, zoom: viewport.zoom)
        for handle in cropHandleLayout.handles {
            let p = viewport.viewPoint(fromDocument: cropHandleLayout.point(for: handle))
            handles.addRect(CGRect(x: p.x - 4.5, y: p.y - 4.5, width: 9, height: 9))
        }
        cropHandlesLayer.path = handles

        cropDimLayer.isHidden = false
        cropGridLayer.isHidden = false
        cropBorderLayer.isHidden = false
        cropHandlesLayer.isHidden = false
    }

    /// The frame the drag preview should float at, or nil when the preview
    /// isn't applicable (no preview, or it belongs to another layer).
    private var previewedFrame: CGRect? {
        guard let dragPreview else { return nil }
        // Only float the sprite once a drag is genuinely under way. On mere
        // mouse-DOWN (or before the move threshold) the frame hasn't changed, so
        // showing the sprite would needlessly swap the live composite for the
        // gamma-composited bitmap — which shifts semi-transparent effects like
        // shadows. Keep the real composite until the layer actually moves/resizes.
        if let resizeDrag, resizeDrag.layerID == dragPreview.layerID,
           resizeDrag.frame != resizeDrag.startFrame {
            return resizeDrag.frame
        }
        if let moveDrag, moveDrag.layerID == dragPreview.layerID, moveDrag.moved {
            return CGRect(origin: moveDrag.snapped.origin, size: moveDrag.size)
        }
        // Region content move: the sprite is the lifted region, positioned by
        // its own content frame (not the layer's).
        if let session = regionContentDrag {
            let delta = roundedDelta(from: session.start, to: session.current)
            guard delta != .zero else { return nil }
            return session.frame.offsetBy(dx: delta.x, dy: delta.y)
        }
        if let hold = regionMoveHoldFrame, moveDrag == nil, resizeDrag == nil {
            return hold
        }
        // Drag ended but the post-commit render hasn't landed yet: hold the
        // sprite at the committed frame so nothing flashes. Only after a real
        // commit — never for a static selection (see `holdSpriteUntilRender`).
        if moveDrag == nil, resizeDrag == nil, holdSpriteUntilRender,
           selectedLayerID == dragPreview.layerID {
            return selectedLayerFrame
        }
        return nil
    }

    private func refreshPreviewSprite() {
        // Endpoint drags re-shape the layer per move — a stretched sprite
        // can't represent that, so the vector preview draws over the underlay
        // alone (during the drag and through the post-commit hold).
        if let dragPreview, let holdID = endpointDrag?.layerID ?? endpointHoldLayerID,
           holdID == dragPreview.layerID {
            contentLayer.contents = dragPreview.underlay
            previewSpriteLayer.isHidden = true
            return
        }
        guard let viewport, let dragPreview, let frame = previewedFrame else {
            previewSpriteLayer.isHidden = true
            if let image, !contentLayer.isHidden { contentLayer.contents = image }
            return
        }
        contentLayer.contents = dragPreview.underlay
        previewSpriteLayer.contents = dragPreview.sprite
        let padded = frame.insetBy(dx: -dragPreview.padding, dy: -dragPreview.padding)
        let spriteRect = viewRect(forDocRect: padded, in: viewport)
        // Bounds + position instead of frame: a rotate/skew drag floats the
        // sprite with a delta transform (set below), and CALayer.frame is
        // undefined under a non-identity transform.
        previewSpriteLayer.bounds = CGRect(origin: .zero, size: spriteRect.size)
        previewSpriteLayer.position = CGPoint(x: spriteRect.midX, y: spriteRect.midY)
        previewSpriteLayer.setAffineTransform(spriteDeltaTransform(for: dragPreview.layerID))
        switch dragPreview.blendMode {
        case .normal: previewSpriteLayer.compositingFilter = nil
        case .multiply: previewSpriteLayer.compositingFilter = "multiplyBlendMode"
        case .screen: previewSpriteLayer.compositingFilter = "screenBlendMode"
        }
        previewSpriteLayer.isHidden = false
    }

    /// What a rotate/skew drag adds on top of the sprite bitmap (which was
    /// rendered with the start transform baked in): current ∘ start⁻¹, the
    /// linear parts only — CALayer applies it about the sprite's center,
    /// which coincides with the layer's transform center.
    private func spriteDeltaTransform(for layerID: UUID) -> CGAffineTransform {
        let session: (start: LayerTransform, current: LayerTransform)?
        if let transformDrag, transformDrag.layerID == layerID {
            session = (transformDrag.startTransform, transformDrag.transform)
        } else if let transformHold, transformHold.layerID == layerID {
            session = (transformHold.start, transformHold.transform)
        } else {
            session = nil
        }
        guard let session, session.start != session.current else { return .identity }
        return session.start.affineTransform(around: .zero).inverted()
            .concatenating(session.current.affineTransform(around: .zero))
    }

    private func refreshMarqueeDisplay() {
        // The ants show, in priority order: the live region-tool combination
        // (base region ⊕ in-flight shape as ONE path), the live arrow
        // marquee, else the committed region.
        var antsDocPath: CGPath?
        var marqueeRect: CGRect? // the arrow marquee's live rubber-band rect
        if let session = regionOutlineDrag {
            // Outline-only move: the ants slide with the pointer.
            let delta = roundedDelta(from: session.start, to: session.current)
            antsDocPath = session.base.translated(by: CGVector(dx: delta.x, dy: delta.y))?.path
        } else if let session = regionContentDrag {
            // Content move: the outline travels with the floated pixels.
            let delta = roundedDelta(from: session.start, to: session.current)
            antsDocPath = selection?.translated(by: CGVector(dx: delta.x, dy: delta.y))?.path
        } else if let viewport, let session = regionDrag {
            let shape = session.drag.selectionRect(in: viewport.documentSize)
                .flatMap { session.isEllipse ? SelectionRegion.ellipse(in: $0) : SelectionRegion.rect($0) }
            if let shape {
                antsDocPath = SelectionRegion.combine(selection, with: shape, mode: session.mode)?.path
            } else {
                antsDocPath = selection?.path
            }
        } else if let viewport, let marquee {
            let rect = marquee.selectionRect(in: viewport.documentSize)
            antsDocPath = rect.map { CGPath(rect: $0, transform: nil) }
            marqueeRect = rect
        } else {
            antsDocPath = selection?.path
        }
        if let viewport, let docPath = antsDocPath {
            // Document space → view space is a pure scale + translate (the view
            // is flipped, so no y-inversion).
            let docOrigin = viewport.viewPoint(fromDocument: .zero)
            var docToView = CGAffineTransform(translationX: docOrigin.x, y: docOrigin.y)
                .scaledBy(x: viewport.zoom, y: viewport.zoom)
            let path = docPath.copy(using: &docToView) ?? docPath
            selectionBaseLayer.path = path
            selectionAntsLayer.path = path
            selectionBaseLayer.isHidden = false
            selectionAntsLayer.isHidden = false
        } else {
            selectionBaseLayer.isHidden = true
            selectionAntsLayer.isHidden = true
        }
        refreshMultiSelectOutlines(marqueeRect: marqueeRect)
    }

    /// An outline around every layer in the multi-selection, so what is picked
    /// is obvious on the picture and not just in the Layers list.
    ///
    /// Mid-sweep the set is derived live from the marquee rect; the rest of the
    /// time it is the echoed selection state, whatever put it there — a
    /// committed sweep, a ⇧-click on the canvas, a row click in the list. It
    /// does NOT hang off the rubber band: a ⇧-click selection has no band, and
    /// before this it drew nothing at all.
    private func refreshMultiSelectOutlines(marqueeRect: CGRect?) {
        // The region tools select pixels rather than layers, so their in-flight
        // shape never outlines anything.
        guard let viewport, let document, regionDrag == nil else {
            multiSelectOutlineLayer.isHidden = true
            return
        }
        // Mid-sweep the band says what is picked. A ⇧-press that has not moved
        // is not a sweep — it spares the selection — so what is already picked
        // stays outlined rather than blinking out while the button is down.
        let captured: Set<UUID>
        if marquee != nil, let rect = marqueeRect {
            // With ⇧ the band adds, so mid-sweep it outlines the layers it has
            // taken in AND the ones already picked: what you let go on is what
            // you saw.
            captured = marqueePress.selection(
                afterSweeping: document.layerIDs(fullyInside: rect, inside: marqueeContext),
                startingFrom: pickedLayerIDs)
        } else if marquee != nil, marqueePress.clearsSelectionOnPress {
            captured = []
        } else {
            captured = multiSelectedLayerIDs
        }
        let outlines = CGMutablePath()
        // A drag in flight moves the picture per mouse move, but the document
        // still holds the pre-drag positions, so the outlines carry the same
        // offset or they would come away from the layers they belong to. Only
        // what the drag actually carries moves: a locked member holds still.
        let travelling = multiMove?.moved == true
            ? Set(multiMove?.plan.members.map(\.id) ?? []) : []
        let delta = multiMove?.delta ?? .zero
        // Canvas coordinates, so a member that lives inside a group is outlined
        // where it draws rather than where it is stored.
        for id in captured.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let layer = document.canvasLayer(id: id) else { continue }
            let shift = travelling.contains(id) ? delta : .zero
            let corners = inkCorners(of: layer).map {
                viewport.viewPoint(fromDocument: CGPoint(x: $0.x + shift.x, y: $0.y + shift.y))
            }
            outlines.addLines(between: corners)
            outlines.closeSubpath()
        }
        multiSelectOutlineLayer.path = outlines
        multiSelectOutlineLayer.isHidden = outlines.isEmpty
    }

    /// The box a selection outline hugs: the ink the layer actually puts down.
    ///
    /// A line or an arrow rasterizes into a frame padded on all four sides for
    /// its round cap, its arrowhead's wings and a caption pill's shadow, and
    /// the caption's share of that padding is a deliberately generous guess at
    /// the pill's width — 423 points reserved for a pill that measures 261. A
    /// blue box round THAT made a small captioned arrow look like it owned half
    /// the screen (reported 2026-09-05). The pill goes in at the width it
    /// really measures, which only this side of the app can ask for.
    private func inkBox(of layer: Layer) -> CGRect {
        guard let a = layer.annotation, a.hasCaption else { return layer.drawnBounds() }
        return layer.drawnBounds(
            captionPillSize: CaptionMetrics.pillSize(for: a.caption ?? "", in: a))
    }

    /// `inkBox` as the polygon a rotated or skewed layer's outline draws, the
    /// same way `Layer.transformedCorners` turns its frame: about the centre of
    /// the STORED box, which is the point the renderer turns the layer about.
    private func inkCorners(of layer: Layer) -> [CGPoint] {
        let box = inkBox(of: layer)
        let corners = [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
                       CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY)]
        guard !layer.transform.isIdentity else { return corners }
        let t = layer.transform.affineTransform(
            around: CGPoint(x: layer.frame.midX, y: layer.frame.midY))
        return corners.map { $0.applying(t) }
    }

    private func refreshLayerSelectionDisplay() {
        refreshGroupContextOutline()
        refreshColumnChrome()
        refreshFrameChrome()
        refreshComponentChrome()
        // Placing the grid's zero point: nothing on the canvas is selected, so
        // the usual chrome has nothing to draw, but the two markers still catch
        // edges and the yellow line has to say which one — otherwise the pull
        // happens invisibly and reads as the markers drifting.
        if gridOriginAdjust != nil {
            layerOutlineLayer.isHidden = true
            handlesLayer.isHidden = true
            rotateKnobLayer.isHidden = true
            if let viewport {
                refreshSnapGuides(in: viewport)
            } else {
                snapGuideLayer.isHidden = true
            }
            return
        }
        // The Canvas pseudo-selection: outline + eight handles on the document
        // boundary (or the in-flight proposed boundary). No rotate knob — the
        // canvas doesn't rotate.
        if isCanvasSelected, let viewport {
            rotateKnobLayer.isHidden = true
            snapGuideLayer.isHidden = true
            let docRect = canvasResizeDrag?.rect ?? CGRect(origin: .zero, size: viewport.documentSize)
            let rect = viewRect(forDocRect: docRect, in: viewport).insetBy(dx: 0.5, dy: 0.5)
            layerOutlineLayer.path = CGPath(rect: rect, transform: nil)
            layerOutlineLayer.isHidden = false
            let handles = CGMutablePath()
            let canvasHandleLayout = Handles.layout(in: docRect, zoom: viewport.zoom)
            for handle in canvasHandleLayout.handles {
                let p = viewport.viewPoint(fromDocument: canvasHandleLayout.point(for: handle))
                handles.addRect(CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8))
            }
            handlesLayer.path = handles
            handlesLayer.isHidden = false
            return
        }
        // A selected layer carries into the region/fill tools (it's the
        // target of region ops), but its outline/handles are SELECT-mode
        // chrome — grabbing them does nothing elsewhere, so hide them. The
        // yellow guide is not selection chrome: an arrow being drawn catches
        // the picture's edges and has to say which one, exactly as a caliper
        // does, so it survives the tool check.
        guard tool == .select else {
            layerOutlineLayer.isHidden = true
            handlesLayer.isHidden = true
            rotateKnobLayer.isHidden = true
            if annotationDrag != nil, let viewport {
                refreshSnapGuides(in: viewport)
            } else {
                snapGuideLayer.isHidden = true
            }
            return
        }
        // A multi-selection has no primary layer, so no outline, handles or
        // knob of its own — each member carries its own outline. Its drag still
        // lines up with the picture and with the layers that stayed behind, so
        // the guide is drawn here rather than being lost with the rest.
        if multiMove != nil, let viewport {
            layerOutlineLayer.isHidden = true
            handlesLayer.isHidden = true
            rotateKnobLayer.isHidden = true
            refreshSnapGuides(in: viewport)
            return
        }
        let frame: CGRect?
        if let resizeDrag {
            frame = resizeDrag.frame
        } else if let moveDrag {
            frame = CGRect(origin: moveDrag.snapped.origin, size: moveDrag.size)
        } else {
            frame = selectedLayerFrame
        }
        guard let viewport, let frame else {
            layerOutlineLayer.isHidden = true
            snapGuideLayer.isHidden = true
            handlesLayer.isHidden = true
            rotateKnobLayer.isHidden = true
            return
        }
        guard let selectedLayer = selectedLayerID.flatMap({ id in document?.canvasLayer(id: id) }) else {
            layerOutlineLayer.isHidden = true
            snapGuideLayer.isHidden = true
            handlesLayer.isHidden = true
            rotateKnobLayer.isHidden = true
            return
        }
        let dragInFlight = moveDrag != nil || resizeDrag != nil || transformDrag != nil
            || endpointDrag != nil || endpointHoldLayerID != nil || measureHandleDrag != nil
            || captionDrag != nil
        // The blue selection outline hides during a RESIZE (frame handles,
        // annotation endpoints, a caliper handle, or a caption pill drag that
        // re-shapes the frame) so the edges being aligned stay unobstructed;
        // it still tracks moves and rotates.
        let resizing = resizeDrag != nil || endpointDrag != nil || measureHandleDrag != nil
            || captionDrag != nil

        // The outline (and frame-handle placement) follows the layer's
        // transform — the in-flight one during a rotate/skew drag.
        let activeTransform = transformDrag?.transform ?? selectedLayer.transform
        // The chrome turns about the centre of the box the RENDERER turns the
        // layer about, which is the stored one: a text box's slack sits on its
        // far edges, so its centre is half of that past the middle of the
        // words the outline is drawn round.
        let slack = selectedLayer.boxSlack
        let center = CGPoint(x: frame.midX + slack.width / 2, y: frame.midY + slack.height / 2)
        let docToHandle = activeTransform.isIdentity
            ? CGAffineTransform.identity
            : activeTransform.affineTransform(around: center)
        func chromePoint(_ docPoint: CGPoint) -> CGPoint {
            viewport.viewPoint(fromDocument: docPoint.applying(docToHandle))
        }

        // Universal blue selection box around what the layer DRAWS, for every
        // object type.
        if resizing {
            layerOutlineLayer.isHidden = true
        } else {
            var box = inkBox(of: selectedLayer)
            // The frame above may be an in-flight move; carry the ink with it.
            if frame.origin != selectedLayer.frame.origin {
                box = box.offsetBy(dx: frame.minX - selectedLayer.frame.minX,
                                   dy: frame.minY - selectedLayer.frame.minY)
            }
            let outline = CGMutablePath()
            outline.addLines(between: [
                chromePoint(CGPoint(x: box.minX, y: box.minY)),
                chromePoint(CGPoint(x: box.maxX, y: box.minY)),
                chromePoint(CGPoint(x: box.maxX, y: box.maxY)),
                chromePoint(CGPoint(x: box.minX, y: box.maxY)),
            ])
            outline.closeSubpath()
            layerOutlineLayer.path = outline
            layerOutlineLayer.isHidden = false
        }

        if selectedLayer.hasEndpointHandles {
            // Lines/arrows/measures edit by their endpoints (round handles), not
            // the eight frame handles; no rotate knob.
            rotateKnobLayer.isHidden = true
            if !dragInFlight, offersOwnHandles(selectedLayer) {
                let handles = CGMutablePath()
                // Calipers expose their three handles (two feet + head); lines/
                // arrows their two ends.
                let points: [CGPoint] = selectedLayer.measure != nil
                    ? drawnMeasureHandles(selectedLayer)
                    : AnnotationEndpoint.allCases.compactMap { selectedLayer.editEndpoint($0) }
                for dp in points {
                    let p = viewport.viewPoint(fromDocument: dp)
                    handles.addEllipse(in: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10))
                }
                handlesLayer.path = handles
                handlesLayer.isHidden = false
            } else {
                handlesLayer.isHidden = true
            }
        } else {
            // Eight square frame handles, hidden mid-drag and for text (which
            // resizes width-only via its own affordance).
            if !dragInFlight, offersOwnHandles(selectedLayer), selectedLayer.allowsFrameResize {
                let handles = CGMutablePath()
                // Handles fit the thing they are round: on a selection too
                // small to hold them, the four edge midpoints drop away and the
                // corners step outside the outline, so the object itself is
                // still there to be grabbed and dragged. The press reads the
                // same layout, so every square drawn is a target and nothing
                // else is.
                let handleLayout = Handles.layout(in: frame, zoom: viewport.zoom)
                for handle in handleLayout.handles {
                    let p = chromePoint(handleLayout.point(for: handle))
                    handles.addRect(CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8))
                }
                handlesLayer.path = handles
                handlesLayer.isHidden = false
            } else {
                handlesLayer.isHidden = true
            }

            // Rotate knob with its stem, off the (transformed) top edge.
            if !dragInFlight, offersRotation(selectedLayer),
               let knob = selectedLayer.rotateKnobPoint(zoom: viewport.zoom) {
                let knobInView = viewport.viewPoint(fromDocument: knob)
                let topMid = chromePoint(CGPoint(x: frame.midX, y: frame.minY))
                let path = CGMutablePath()
                path.move(to: topMid)
                path.addLine(to: knobInView)
                path.addEllipse(in: CGRect(x: knobInView.x - 5, y: knobInView.y - 5,
                                           width: 10, height: 10))
                rotateKnobLayer.path = path
                rotateKnobLayer.isHidden = false
            } else {
                rotateKnobLayer.isHidden = true
            }
        }

        refreshSnapGuides(in: viewport)
    }

    /// The guides on screen RIGHT NOW, whichever kind of drag put them there.
    /// A scripted walk samples this between the moves of one drag to count how
    /// often a snap is taken and given back, which is the only way to measure
    /// flicker from outside.
    var liveSnapGuides: (x: CGFloat?, y: CGFloat?) {
        let move = moveDrag?.snapped ?? multiMove.flatMap { $0.moved ? $0.snapped : nil }
        let resize = resizeDrag?.snapped
        return (move?.guideX ?? resize?.guideX ?? snapGuide?.x,
                move?.guideY ?? resize?.guideY ?? snapGuide?.y)
    }

    /// The lines that say what a drag just lined itself up with. Guides span
    /// the whole document so the alignment target is obvious. Driven by
    /// layer-move snapping OR a measure corner snapping to a detected UI edge —
    /// both magnetize to a document x/y and want the same full-span line.
    private func refreshSnapGuides(in viewport: Viewport) {
        let guides = CGMutablePath()
        let docFrame = viewport.documentFrameInView
        // A multi-selection snaps by the box it makes, and draws the same guide
        // a one-layer drag does. A RESIZE draws it too: it is lining up with
        // the same things a move lines up with.
        let move = moveDrag?.snapped ?? multiMove.flatMap { $0.moved ? $0.snapped : nil }
        let resize = resizeDrag?.snapped
        let guideX = move?.guideX ?? resize?.guideX ?? snapGuide?.x
        let guideY = move?.guideY ?? resize?.guideY ?? snapGuide?.y
        let spanX = move?.guideXSpan ?? resize?.guideXSpan
        let spanY = move?.guideYSpan ?? resize?.guideYSpan
        // A line to the picture's own edge or middle spans the whole picture,
        // because that is what it lines up with. A line to another LAYER
        // reaches only across the boxes it joins, with a little overhang, so a
        // canvas full of boxes does not fill with full-height rules every time
        // something is dragged.
        if let x = guideX {
            let vx = viewport.viewPoint(fromDocument: CGPoint(x: x, y: 0)).x
            let ends = viewSpan(spanX, vertical: true, in: viewport)
                ?? (docFrame.minY, docFrame.maxY)
            guides.move(to: CGPoint(x: vx, y: ends.0))
            guides.addLine(to: CGPoint(x: vx, y: ends.1))
        }
        if let y = guideY {
            let vy = viewport.viewPoint(fromDocument: CGPoint(x: 0, y: y)).y
            let ends = viewSpan(spanY, vertical: false, in: viewport)
                ?? (docFrame.minX, docFrame.maxX)
            guides.move(to: CGPoint(x: ends.0, y: vy))
            guides.addLine(to: CGPoint(x: ends.1, y: vy))
        }
        snapGuideLayer.path = guides
        snapGuideLayer.isHidden = guides.isEmpty
        refreshGridSnapLines(in: viewport)
    }

    /// The grid line a drag came to rest on, lit up while it holds it.
    ///
    /// It answers a different question from the yellow guides above. A guide
    /// says "you lined up with THAT thing" and is news; the grid is pulling all
    /// the time, so a yellow cross on screen through every drag would say
    /// nothing and would drain the yellow of its meaning. Instead the line the
    /// edge landed on is drawn again in the grid's own accent at full strength,
    /// running right across the view the way the grid does, so the answer to
    /// "what did it catch" is one of the lines you are already looking at.
    ///
    /// The moment a real edge wins on an axis, `gridX`/`gridY` go quiet for
    /// that axis and the yellow guide takes over, which is exactly the handover
    /// a person expects: the grid holds you until something better does.
    private func refreshGridSnapLines(in viewport: Viewport) {
        let move = moveDrag?.snapped ?? multiMove.flatMap { $0.moved ? $0.snapped : nil }
        let resize = resizeDrag?.snapped
        let x = move?.gridX ?? resize?.gridX
        let y = move?.gridY ?? resize?.gridY
        guard canvasGridEnabled, x != nil || y != nil,
              bounds.width > 0.5, bounds.height > 0.5 else {
            gridSnapLayer.path = nil
            gridSnapLayer.isHidden = true
            return
        }
        let path = CGMutablePath()
        // Whole view points, for the same reason the grid itself rounds: a one
        // point line off the pixel grid is a two point smear, and this one has
        // to sit exactly on the line underneath it.
        if let x {
            let vx = viewport.viewPoint(fromDocument: CGPoint(x: x, y: 0)).x.rounded()
            path.move(to: CGPoint(x: vx, y: bounds.minY))
            path.addLine(to: CGPoint(x: vx, y: bounds.maxY))
        }
        if let y {
            let vy = viewport.viewPoint(fromDocument: CGPoint(x: 0, y: y)).y.rounded()
            path.move(to: CGPoint(x: bounds.minX, y: vy))
            path.addLine(to: CGPoint(x: bounds.maxX, y: vy))
        }
        gridSnapLayer.path = path
        gridSnapLayer.isHidden = path.isEmpty
    }

    /// The grid lines lit up RIGHT NOW, for a scripted walk to read: the same
    /// pair `refreshGridSnapLines` draws, in document points.
    var liveGridSnapLines: (x: CGFloat?, y: CGFloat?) {
        let move = moveDrag?.snapped ?? multiMove.flatMap { $0.moved ? $0.snapped : nil }
        let resize = resizeDrag?.snapped
        return (move?.gridX ?? resize?.gridX, move?.gridY ?? resize?.gridY)
    }

    /// A guide's reach, from canvas points into view points, with a few points
    /// of overhang at each end so the line visibly passes THROUGH the boxes it
    /// joins rather than stopping exactly at their corners.
    private func viewSpan(_ span: Snapping.Span?, vertical: Bool,
                          in viewport: Viewport) -> (CGFloat, CGFloat)? {
        guard let span else { return nil }
        let a = vertical
            ? viewport.viewPoint(fromDocument: CGPoint(x: 0, y: span.start)).y
            : viewport.viewPoint(fromDocument: CGPoint(x: span.start, y: 0)).x
        let b = vertical
            ? viewport.viewPoint(fromDocument: CGPoint(x: 0, y: span.end)).y
            : viewport.viewPoint(fromDocument: CGPoint(x: span.end, y: 0)).x
        return (min(a, b) - 6, max(a, b) + 6)
    }
}
