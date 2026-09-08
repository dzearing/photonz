import AppKit
import CoreGraphics
import Observation
import PhotonzCore
import PhotonzRender
import SwiftUI
import UniformTypeIdentifiers

// Pixel regions: filling them, deleting them, moving their content, and the
// foreground/background fill pair the paint bucket uses.
//
// Split out of EditorState.swift; nothing here changed on the way over.
extension EditorState {
    // MARK: - Fill colors (paint bucket)

    static let foregroundFillKey = "fill.foreground"
    static let backgroundFillKey = "fill.background"

    /// Whether the two fill commands have anything to paint. The Edit menu
    /// reads it to dim its rows, and the canvas presses ⌥⌫ under the same rule
    /// (`FillColors.canFill`), so a row that says yes and a key that does
    /// nothing cannot happen.
    var canFillWithFillColors: Bool {
        FillColors.canFill(hasPickedLayer: selectedLayerID != nil,
                           targetsPixels: selectionTargetsPixels,
                           hasRegion: selection != nil)
    }

    // MARK: - The selection box as four typed numbers

    /// The selection box when the Position & Size fields are describing the
    /// MARQUEE rather than the picked layers, else nil.
    ///
    /// The rule is `Nudge.target`, the same one the arrow keys use, so the
    /// panel and the keyboard can never disagree about whose numbers are on
    /// screen: with a selection tool in hand the marquee has both, and with
    /// the arrow tool the picked layer takes them back. A live region with
    /// nothing movable picked keeps them either way, since the alternative is
    /// a panel describing nothing.
    var regionGeometry: RegionGeometry? {
        guard selectionTargetsPixels, let region = selection,
              Nudge.target(pixelRegion: true,
                           regionToolActive: activeTool.isRegionSelectionTool,
                           layerWouldMove: nudgeWouldMoveALayer) == .region
        else { return nil }
        return RegionGeometry(bounds: region.bounds)
    }

    /// Whether an arrow key has a layer to move. The canvas asks the same
    /// question of its own copy of the selection (`nudgeWouldMoveALayer` in
    /// CanvasView); this is it asked of the state the panel reads, so the two
    /// answer alike. A locked layer counts as nothing, since a nudge and a
    /// typed number both leave it where it is.
    var nudgeWouldMoveALayer: Bool {
        let picked = actionableLayerIDs
        if picked.count > 1 { return document?.multiLayerDrag(moving: picked) != nil }
        guard let id = picked.first, let layer = document?.canvasLayer(id: id) else { return false }
        return !layer.isLocked
    }

    /// A number typed into one of the four fields while the panel is reading
    /// the marquee: the outline moves or scales to it.
    ///
    /// An undo step, like every other act on the marquee: a number typed here
    /// and an arrow key on the canvas both move the outline, so ⌘Z takes back
    /// either. A run of them collapses into one step, so holding the arrow in
    /// a field is one press to undo rather than thirty.
    func setRegionGeometry(field: LayerGeometryField, to value: CGFloat) {
        guard let box = regionGeometry?.applying(value, to: field) else { return }
        commitRegionBox(box)
    }

    /// An arrow key inside one of those fields: the same 1 and 10 the canvas
    /// nudges the marquee by, applied to the number you are standing in.
    func stepRegionGeometry(field: LayerGeometryField, direction: Int, coarse: Bool) {
        guard let box = regionGeometry?.stepping(field, direction: direction, coarse: coarse) else {
            return
        }
        commitRegionBox(box)
    }

    /// The outline scaled and moved so its box is exactly `box`. A refusal
    /// leaves the selection as it was rather than dropping it, so a slipped
    /// keystroke can never lose the marquee.
    private func commitRegionBox(_ box: CGRect) {
        guard let resized = selection?.resized(to: box) else { return }
        setSelection(resized, captureLayers: false, run: "region-geometry")
    }

    /// X — swap foreground and background, like Photoshop.
    func swapFillColors() {
        (foregroundFillHex, backgroundFillHex) = (backgroundFillHex, foregroundFillHex)
    }

    /// Fills `id` with a color via the bucket semantics (`Fill.filled`): solid
    /// content for photos, interior fill for boxes, recolor for strokes/text/
    /// measures, backdrop for collages. One undo step; no-op when the content
    /// refuses (zoom callouts).
    func fillLayer(id: UUID, hex: String) {
        guard let layer = document?.layer(id: id) else { return }
        var solidRef: ImageRef?
        if layer.imageRef != nil {
            guard let solid = Self.solidImage(hex: hex) else { return }
            solidRef = store.register(solid)
        }
        guard let filled = Fill.filled(layer, colorHex: hex, solidRef: solidRef) else { return }
        discardDragPreview()
        perform { $0.updateLayer(id: id) { $0 = filled } }
        recordRecentColor(hex: hex)
    }

    /// Bucket click on the canvas: fill the hit layer — or, when the click
    /// lands on the locked Background (which hit-testing skips), fill that.
    /// `useBackground` (⌥) fills with the background color instead.
    func fillLayer(at point: CGPoint, hit: UUID?, useBackground: Bool) {
        // While a pixel region exists the bucket fills THE REGION, not the
        // layer — and clicks outside it do nothing (Photoshop).
        if selectionTargetsPixels, let region = selection {
            guard region.contains(point), let target = regionTargetID(preferring: hit) else { return }
            fillRegion(hex: useBackground ? backgroundFillHex : foregroundFillHex, into: target)
            return
        }
        let target = hit ?? document?.layers.first(where: {
            $0.isLocked && $0.imageRef != nil && $0.frame.contains(point)
        })?.id
        guard let target else { return }
        fillLayer(id: target, hex: useBackground ? backgroundFillHex : foregroundFillHex)
    }

    /// ⌥⌫ — fill the selected layer with the foreground (or background)
    /// color; with a pixel region active, fill the region instead.
    func fillSelectedLayer(useBackground: Bool) {
        let hex = useBackground ? backgroundFillHex : foregroundFillHex
        if selectionTargetsPixels, selection != nil {
            if let target = regionTargetID() { fillRegion(hex: hex, into: target) }
            return
        }
        guard let id = selectedLayerID else { return }
        fillLayer(id: id, hex: hex)
    }

    // MARK: - Region-targeted ops (17.5)

    /// The image layer a region op bakes into (`RegionTarget`): the layer you
    /// picked, so ⌫, fill, copy and a drag of the region's pixels all land on
    /// the same one. `hit` is the layer under the pointer, which only answers
    /// when nothing is picked, and the locked Background answers last.
    private func regionTargetID(preferring hit: UUID? = nil) -> UUID? {
        guard let document, let region = selection else { return nil }
        return RegionTarget.id(picked: selectedLayerID, hit: hit,
                               region: region.bounds, in: document)
    }

    /// Whether a region op could bake into THIS layer (`RegionTarget.canSlice`).
    func canSliceRegion(from id: UUID) -> Bool {
        guard let layer = document?.layer(id: id) else { return false }
        return RegionTarget.canSlice(layer)
    }

    /// Bakes a region op into an image layer's bitmap as ONE undo step. The
    /// region path maps from document space into bitmap pixels through the
    /// layer's frame (bitmaps stretch to their frame at render time).
    @discardableResult
    private func bakeRegion(into id: UUID, op: (CGImage, CGPath) -> CGImage?) -> Bool {
        guard let region = selection, let document,
              let layer = document.layer(id: id), let ref = layer.imageRef,
              layer.crop == nil, layer.transform.isIdentity,
              layer.frame.width > 0, layer.frame.height > 0,
              let bitmap = store.image(for: ref) else { return false }
        var docToBitmap = CGAffineTransform(scaleX: CGFloat(bitmap.width) / layer.frame.width,
                                            y: CGFloat(bitmap.height) / layer.frame.height)
            .translatedBy(x: -layer.frame.minX, y: -layer.frame.minY)
        let localPath = region.path.copy(using: &docToBitmap) ?? region.path
        guard let baked = op(bitmap, localPath) else { return false }
        let newRef = store.register(baked)
        discardDragPreview()
        perform { $0.updateLayer(id: id) { $0.content = .image(newRef) } }
        return true
    }

    /// Fills the selection region with `hex` into the target image layer's
    /// pixels. The selection stays up afterwards (Photoshop).
    @discardableResult
    func fillRegion(hex: String, into id: UUID) -> Bool {
        let filled = bakeRegion(into: id) { RegionOps.filled($0, path: $1, hex: hex) }
        if filled { recordRecentColor(hex: hex) }
        return filled
    }

    /// ⌫ with a pixel region: SLICE the target image layer — erase the
    /// region, then tighten the layer's frame to the surviving pixels
    /// (Photoshop's bounds are derived from content, so deletes shrink
    /// layers there too). Deleting every pixel removes the layer. The locked
    /// Background instead fills with the background color and keeps its
    /// size (it must stay canvas-sized).
    func deleteRegion() {
        guard selectionTargetsPixels, let region = selection else { return }
        // A picked layer no piece can be taken out of takes the op nowhere
        // else (`RegionTarget`), so this used to be a key that did nothing and
        // said nothing. Say which it was instead (`RegionSliceRefusal`).
        if Experiments.shared.cutSaysWhatItCannotDoEnabled,
           let picked = pickedLayerID, let layer = document?.layer(id: picked),
           let refusal = RegionSliceRefusal.refusal(for: layer, action: .erase) {
            raiseCanvasNotice(.regionSliceRefused(refusal))
            return
        }
        guard let id = regionTargetID(),
              let document, let layer = document.layer(id: id) else { return }
        if layer.isLocked {
            fillRegion(hex: backgroundFillHex, into: id)
            return
        }
        guard let ref = layer.imageRef, layer.crop == nil, layer.transform.isIdentity,
              layer.frame.width > 0, layer.frame.height > 0,
              let bitmap = store.image(for: ref) else { return }
        var docToBitmap = CGAffineTransform(scaleX: CGFloat(bitmap.width) / layer.frame.width,
                                            y: CGFloat(bitmap.height) / layer.frame.height)
            .translatedBy(x: -layer.frame.minX, y: -layer.frame.minY)
        let localPath = region.path.copy(using: &docToBitmap) ?? region.path
        guard let erased = RegionOps.erased(bitmap, path: localPath) else { return }
        discardDragPreview()
        guard let trimmed = RegionOps.trimmed(erased) else {
            deleteLayer(id: id) // the delete consumed the whole layer
            return
        }
        let newRef = store.register(trimmed.image)
        let newFrame = trimmed.rect.applying(docToBitmap.inverted())
        perform { $0.updateLayer(id: id) {
            $0.content = .image(newRef)
            $0.frame = newFrame
        } }
    }

    // MARK: Region content move (Photoshop Move-tool semantics)

    /// Select(V)-tool drag starting inside a pixel region: lift the region's
    /// pixels off the target layer and float them (⌥ floats a COPY, leaving
    /// the original). Returns the floating content's doc frame — the canvas
    /// drives the sprite with it — or nil when nothing bakeable is under the
    /// region. Preview pieces render off-main like a layer drag.
    func beginRegionMove(copy: Bool) -> CGRect? {
        guard selectionTargetsPixels, let region = selection, let document,
              let targetID = regionTargetID(), let layer = document.layer(id: targetID),
              let ref = layer.imageRef, layer.crop == nil, layer.transform.isIdentity,
              layer.frame.width > 0, layer.frame.height > 0,
              let bitmap = store.image(for: ref) else { return nil }
        var docToBitmap = CGAffineTransform(scaleX: CGFloat(bitmap.width) / layer.frame.width,
                                            y: CGFloat(bitmap.height) / layer.frame.height)
            .translatedBy(x: -layer.frame.minX, y: -layer.frame.minY)
        let localPath = region.path.copy(using: &docToBitmap) ?? region.path
        // The hole: transparent on normal layers; the locked Background gets
        // the background color (Photoshop's Move-from-Background behavior).
        let holed = layer.isLocked
            ? RegionOps.filled(bitmap, path: localPath, hex: backgroundFillHex)
            : RegionOps.erased(bitmap, path: localPath)
        guard let holed, let content = RegionOps.extracted(bitmap, path: localPath) else { return nil }
        let localBounds = localPath.boundingBoxOfPath.integral
            .intersection(CGRect(x: 0, y: 0, width: bitmap.width, height: bitmap.height))
        let contentFrame = localBounds.applying(docToBitmap.inverted())
        regionMove = (targetID, content, contentFrame, holed, copy)

        // Preview pieces (async, like beginLayerDrag): underlay = composite
        // with the hole showing (or unchanged for a copy), sprite = content.
        dragPreview = nil
        clearPreviewAfterNextFrame = false
        dragPreviewGeneration += 1
        let generation = dragPreviewGeneration
        var underlayDoc = displayFiltered(document)
        var tempRef: ImageRef?
        if !copy {
            let holedRef = store.register(holed)
            tempRef = holedRef
            underlayDoc.updateLayer(id: targetID) { $0.content = .image(holedRef) }
        }
        let blend = layer.effectiveBlendMode
        let renderer = previewRenderer
        let store = store
        Task.detached(priority: .userInitiated) { [weak self] in
            let underlay = renderer.render(underlayDoc, store: store)
            if let tempRef { store.remove(tempRef) }
            await MainActor.run {
                guard let self, self.dragPreviewGeneration == generation, let underlay else { return }
                self.dragPreview = DragPreview(layerID: targetID, underlay: underlay,
                                               sprite: content, padding: 0, blendMode: blend)
            }
        }
        return contentFrame
    }

    /// Mouse-up: bake the floated content into the target layer at its new
    /// spot — ONE undo step — and move the selection outline with it. A zero
    /// delta (a mere click) bakes nothing.
    func commitRegionMove(delta: CGPoint) {
        guard let session = regionMove, delta != .zero,
              let document, let layer = document.layer(id: session.targetID),
              let ref = layer.imageRef, let bitmap = store.image(for: ref),
              layer.frame.width > 0, layer.frame.height > 0 else {
            cancelRegionMove()
            return
        }
        let base = session.copy ? bitmap : session.holed
        // The stamp rect in bitmap pixels: content frame + delta, mapped back.
        let docToBitmap = CGAffineTransform(scaleX: CGFloat(bitmap.width) / layer.frame.width,
                                            y: CGFloat(bitmap.height) / layer.frame.height)
            .translatedBy(x: -layer.frame.minX, y: -layer.frame.minY)
        let stampRect = session.contentFrame.offsetBy(dx: delta.x, dy: delta.y)
            .applying(docToBitmap)
        guard let stamped = RegionOps.stamped(base, overlay: session.content, at: stampRect) else {
            cancelRegionMove()
            return
        }
        regionMove = nil
        dragPreviewGeneration += 1 // cancels an in-flight preview session
        clearPreviewAfterNextFrame = dragPreview != nil
        let newRef = store.register(stamped)
        perform { $0.updateLayer(id: session.targetID) { $0.content = .image(newRef) } }
        // The selection follows its content (Photoshop), inside the same step
        // as the bake: one ⌘Z puts the pixels and the outline back together.
        if let moved = selection?.translated(by: CGVector(dx: delta.x, dy: delta.y)) {
            setSelection(moved, captureLayers: false, recording: false)
        }
    }

    /// Esc / zero-move: drop the float; the document never changed.
    func cancelRegionMove() {
        regionMove = nil
        dragPreviewGeneration += 1
        dragPreview = nil
    }

    /// Layer ▸ New Layer: a canvas-sized transparent image layer on top,
    /// selected — with the selection region PRESERVED, so select → new layer
    /// → fill lands paint on the fresh layer (the Photoshop flow).
    func newEmptyLayer() {
        guard let document else { return }
        let size = document.canvasSize
        let w = Int(size.width.rounded()), h = Int(size.height.rounded())
        guard w > 0, h > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let transparent = context.makeImage() else { return }
        let ref = store.register(transparent)
        let layer = Layer(name: "Layer", content: .image(ref),
                          frame: CGRect(origin: .zero, size: size))
        perform { $0.addLayer(layer) }
        selectedLayerID = layer.id
    }

    /// ⌫ with the (locked) Background selected: reset it to the background
    /// color — "clear it / make the background default".
    func clearBackgroundLayer() {
        guard let id = selectedLayerID, let layer = document?.layer(id: id),
              layer.isLocked, layer.imageRef != nil else { return }
        fillLayer(id: id, hex: backgroundFillHex)
    }

    /// A tiny solid bitmap; layer frames stretch it (identical pixels resample
    /// to the same color).
    private static func solidImage(hex: String) -> CGImage? {
        guard let rgba = RGBA(hex: hex),
              let context = CGContext(data: nil, width: 8, height: 8,
                                      bitsPerComponent: 8, bytesPerRow: 32,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        return context.makeImage()
    }
}
