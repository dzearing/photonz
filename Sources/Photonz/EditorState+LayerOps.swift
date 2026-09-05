import AppKit
import CoreGraphics
import Observation
import PhotonzCore
import PhotonzRender
import SwiftUI
import UniformTypeIdentifiers

// Whole-layer commands: collage, merge down, rasterize, restacking, and
// promoting a selection to a layer of its own.
//
// Split out of EditorState.swift; nothing here changed on the way over.
extension EditorState {
    // MARK: - Collage (16.9)

    /// The layers "Arrange in Collage…" would arrange: the multi-selection's
    /// image layers when it holds at least two, else every visible, unlocked
    /// image layer (so the command works straight from the menu with nothing
    /// selected — the locked Background never participates).
    var collageLayerIDs: [UUID] {
        guard let document else { return [] }
        let eligible = document.layers.filter {
            if case .image = $0.content { return $0.isVisible && !$0.isLocked }
            return false
        }.map(\.id)
        let selected = eligible.filter { multiSelectedLayerIDs.contains($0) }
        return selected.count >= 2 ? selected : eligible
    }

    var canArrangeCollage: Bool { collageLayerIDs.count >= 2 }

    /// "Arrange in Collage": absorbs `collageLayerIDs` into ONE new collage
    /// layer (their refs become slots in reading order, frame = the union of
    /// their frames, the source layers are removed) in one undo step, then
    /// selects it. The collage is live: resize reflows, slots swap by drag,
    /// photos drop in from history/Finder/other layers.
    func arrangeSelectionAsCollage() {
        guard let document else { return }
        let ids = Set(collageLayerIDs)
        guard ids.count >= 2 else { return }
        discardDragPreview()
        let participants = document.layers.filter { ids.contains($0.id) }
        guard let collageLayer = Collage.layer(absorbing: participants),
              let topIndex = document.layers.lastIndex(where: { ids.contains($0.id) }) else { return }
        // The collage takes the TOP participant's stacking slot (indices below
        // it shift down by the number of removed participants beneath it).
        let insertIndex = topIndex - (participants.count - 1)
        selectedLayerID = nil
        perform { doc in
            doc.removeLayers(ids: ids)
            doc.addLayer(collageLayer, at: insertIndex)
        }
        selectedLayerID = collageLayer.id
    }

    /// Creates an empty 2×2 collage layer centered on the canvas.
    func newEmptyCollageLayer() {
        guard let document else { return }
        discardDragPreview()
        let canvas = document.canvasSize
        let size = CGSize(width: (canvas.width * 0.6).rounded(), height: (canvas.height * 0.6).rounded())
        let frame = CGRect(x: ((canvas.width - size.width) / 2).rounded(),
                           y: ((canvas.height - size.height) / 2).rounded(),
                           width: size.width, height: size.height)
        let layer = Collage.layer(content: CollageContent(slots: [CollageSlot(), CollageSlot(),
                                                                  CollageSlot(), CollageSlot()]),
                                  frame: frame)
        perform { $0.addLayer(layer) }
        selectedLayerID = layer.id
    }

    /// A file dropped onto a collage cell: decode and fill that slot.
    func dropImage(at url: URL, intoCollage collageID: UUID, slot: Int) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
        fillCollageSlot(collageID: collageID, slot: slot, image: image)
    }

    /// Fills a collage slot with a new image (a history/Finder drop).
    func fillCollageSlot(collageID: UUID, slot: Int, image: CGImage) {
        let ref = store.register(image)
        perform { doc in
            doc.updateLayer(id: collageID) { layer in
                if var content = layer.collage {
                    content.fill(slot: slot, with: ref)
                    layer.content = .collage(content)
                }
            }
        }
    }

    /// Drops an existing photo layer into a collage slot: the layer's ref
    /// moves into the slot and the layer disappears — one undo step.
    func absorbLayer(id: UUID, intoCollage collageID: UUID, slot: Int) {
        guard id != collageID,
              let ref = document?.layers.first(where: { $0.id == id })?.imageRef else { return }
        discardDragPreview()
        if selectedLayerID == id { selectedLayerID = nil }
        perform { doc in
            doc.removeLayers(ids: [id])
            doc.updateLayer(id: collageID) { layer in
                if var content = layer.collage {
                    content.fill(slot: slot, with: ref)
                    layer.content = .collage(content)
                }
            }
        }
        selectedLayerID = collageID
    }

    /// Swaps two slots' photos (drag between cells).
    func swapCollageSlots(collageID: UUID, _ i: Int, _ j: Int) {
        guard i != j else { return }
        perform { doc in
            doc.updateLayer(id: collageID) { layer in
                if var content = layer.collage {
                    content.swapSlots(i, j)
                    layer.content = .collage(content)
                }
            }
        }
    }

    /// Inspector mutations, each one undo step.
    func updateCollage(layerID: UUID, _ mutate: (inout CollageContent) -> Void) {
        perform { doc in
            doc.updateLayer(id: layerID) { layer in
                if var content = layer.collage {
                    mutate(&content)
                    layer.content = .collage(content)
                }
            }
        }
    }

    // MARK: - Merge down (Photoshop ⌘E)

    /// ⌘E: merge the selected layer into the one below it — or the marquee
    /// multi-selection into one — as a single rasterized image layer.
    func mergeDown() {
        guard let document else { return }
        if multiSelectedLayerIDs.count >= 2 {
            mergeLayers(ids: document.layers.filter { multiSelectedLayerIDs.contains($0.id) }.map(\.id))
        } else if let id = selectedLayerID {
            mergeDown(id: id)
        }
    }

    /// Merge one specific layer into the layer directly below it (the panel's
    /// context menu, which acts on the clicked row, not the selection).
    func mergeDown(id: UUID) {
        guard let document, let idx = document.index(of: id), idx > 0 else { return }
        mergeLayers(ids: [document.layers[idx - 1].id, id])
    }

    /// Whether ⌘E has something to merge (menu enablement).
    var canMergeDown: Bool {
        guard let document else { return false }
        if multiSelectedLayerIDs.count >= 2 { return true }
        guard let id = selectedLayerID, let idx = document.index(of: id), idx > 0,
              !document.layers[idx].isLocked else { return false }
        return true
    }

    /// Composites the given layers (bottom-up order) into ONE image layer, in
    /// one undo step: their styles, blend modes, and transforms bake into the
    /// bitmap; the result takes the bottom participant's slot, name, and lock
    /// (so merging into the locked Background stays a background). All
    /// participants must be visible — a hidden layer would silently rasterize
    /// to nothing. Only the bottom layer may be locked (merge INTO it).
    private func mergeLayers(ids: [UUID]) {
        guard let document, ids.count >= 2 else { return }
        let idSet = Set(ids)
        let participants = document.layers.filter { idSet.contains($0.id) }
        guard participants.count >= 2, participants.allSatisfy(\.isVisible),
              let bottom = participants.first,
              participants.dropFirst().allSatisfy({ !$0.isLocked }) else { return }

        // The merged bitmap covers everything the participants can draw:
        // transformed bounds padded by each style's reach, clamped to canvas.
        var union = CGRect.null
        for layer in participants {
            var bounds = layer.frame
            if !layer.transform.isIdentity {
                let corners = layer.transformedCorners
                if let first = corners.first {
                    bounds = corners.dropFirst().reduce(CGRect(origin: first, size: .zero)) {
                        $0.union(CGRect(origin: $1, size: .zero))
                    }
                }
            }
            let pad = layer.style.previewPadding
            union = union.union(bounds.insetBy(dx: -pad, dy: -pad))
        }
        let region = Geometry.clampCrop(union, toCanvas: document.canvasSize)
        guard region.width >= 1, region.height >= 1 else { return }

        // Composite ONLY the participants (over transparency), so layers in
        // between or below don't leak into the merged bitmap.
        var temp = document
        temp.layers = participants
        guard let raster = previewRenderer.rasterize(region: region, of: temp, store: store) else { return }
        let ref = store.register(raster)
        let merged = Layer(name: bottom.name, content: .image(ref), frame: region,
                           isLocked: bottom.isLocked)
        discardDragPreview()
        perform { doc in
            guard let insertAt = doc.index(of: bottom.id) else { return }
            doc.removeLayers(ids: idSet)
            doc.addLayer(merged, at: insertAt)
        }
        selectedLayerID = merged.id
    }

    // MARK: - Rasterize (vector shape → pixels)

    /// Whether "Rasterize Layer" applies to the given layer (menu enablement).
    func canRasterizeLayer(id: UUID) -> Bool {
        document?.layer(id: id)?.isRasterizable ?? false
    }

    /// Bakes a vector shape/annotation layer into pixels in one undo step: the
    /// shape is rendered WITH all its style effects (blur, shadow, border, corner
    /// radius, opacity) and geometry (crop, transform) into a bitmap covering its
    /// padded on-canvas footprint, that bitmap is stored, and the layer's content
    /// becomes `.image` with its now-baked style reset. Looks pixel-identical;
    /// undo restores the editable vector shape. The layer keeps its slot/name/id.
    func rasterizeLayer(id: UUID) {
        guard let document, let layer = document.layer(id: id), layer.isRasterizable else { return }

        // The baked bitmap covers everything the layer can draw: its transformed
        // bounds padded by the style's reach (shadow/blur), clamped to canvas —
        // exactly how merge-down sizes its result, so nothing is clipped.
        var bounds = layer.frame
        if !layer.transform.isIdentity {
            let corners = layer.transformedCorners
            if let first = corners.first {
                bounds = corners.dropFirst().reduce(CGRect(origin: first, size: .zero)) {
                    $0.union(CGRect(origin: $1, size: .zero))
                }
            }
        }
        let pad = layer.style.previewPadding
        let region = Geometry.clampCrop(bounds.insetBy(dx: -pad, dy: -pad), toCanvas: document.canvasSize)
        guard region.width >= 1, region.height >= 1 else { return }

        // Composite ONLY this layer (over transparency) so nothing below leaks in.
        var temp = document
        var only = layer
        only.isVisible = true
        temp.layers = [only]
        guard let raster = previewRenderer.rasterize(region: region, of: temp, store: store) else { return }
        let ref = store.register(raster)
        discardDragPreview()
        perform { $0.rasterizeLayer(id: id, rasterized: ref, frame: region) }
        selectedLayerID = id
    }

    // MARK: - Restacking (Photoshop ⌘] ⌘[ ⇧⌘] ⇧⌘[)

    func bringLayerForward(id: UUID) { restack(id: id, .forward) }
    func sendLayerBackward(id: UUID) { restack(id: id, .backward) }
    func bringLayerToFront(id: UUID) { restack(id: id, .toFront) }
    func sendLayerToBack(id: UUID) { restack(id: id, .toBack) }

    /// Moves a layer in the stack (row context menu). A member of the
    /// multi-selection takes the whole selection with it; on its own, locked
    /// layers stay put and nothing can be pushed underneath the locked
    /// Background at the bottom.
    private func restack(id: UUID, _ step: PhotonzDocument.RestackStep) {
        if multiSelectedLayerIDs.contains(id) {
            restackSelectedLayers(step)
            return
        }
        guard let document else { return }
        var preview = document
        guard preview.restackLayers(ids: [id], step) else { return }
        discardDragPreview()
        perform { $0.restackLayers(ids: [id], step) }
    }

    /// Drag-reorder from the layers panel (SwiftUI `onMove` indices, visual
    /// top-down order). One undo step.
    func moveLayers(visualSources: IndexSet, visualDestination: Int) {
        discardDragPreview()
        perform { $0.moveLayers(visualSources: visualSources, visualDestination: visualDestination) }
    }

    // MARK: - Promote selection

    /// ⌘J: rasterizes the marquee selection from the current composite and
    /// stacks it as a new image layer (one undo step). The new layer is
    /// selected; the marquee clears — it has done its job.
    func promoteSelectionToLayer() {
        guard let document, let selection else { return }
        let canvas = CGRect(origin: .zero, size: document.canvasSize)
        let raster: CGImage?
        let frame: CGRect
        if selectionTargetsPixels {
            // Pixel region: the promoted bitmap is clipped to the path —
            // transparent outside a wand blob or ellipse.
            frame = selection.path.boundingBoxOfPath.integral.intersection(canvas)
            raster = previewRenderer.rasterize(region: canvas, of: document, store: store)
                .flatMap { RegionOps.extracted($0, path: selection.path) }
        } else {
            frame = Geometry.pixelAligned(selection.bounds)
            raster = previewRenderer.rasterize(region: frame, of: document, store: store)
        }
        guard let raster, !frame.isNull else { return }
        let ref = store.register(raster)
        var newID: UUID?
        perform { newID = $0.promoteRegionToLayer(region: frame, rasterized: ref, name: "Promoted Layer").id }
        self.selection = nil // like Photoshop's Layer via Copy, ⌘J consumes the selection
        selectedLayerID = newID
    }

    /// One-click blur-behind: a single full-canvas rasterization becomes a
    /// blurred backdrop layer plus a sharp cutout cropped to the selection
    /// (one undo step). The focus layer ends up selected so its blur radius
    /// or crop can be adjusted immediately.
    func blurBehindSelection() {
        guard let document, let region = selection.map({ Geometry.pixelAligned($0.bounds) }),
              let raster = previewRenderer.rasterize(region: CGRect(origin: .zero, size: document.canvasSize),
                                                     of: document, store: store) else { return }
        let ref = store.register(raster)
        var focusID: UUID?
        perform { focusID = $0.blurBehind(selection: region, rasterized: ref).focus.id }
        selection = nil
        selectedLayerID = focusID
    }
}
