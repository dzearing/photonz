import AppKit
import CoreGraphics
import Observation
import PhotonzCore
import PhotonzRender
import SwiftUI
import UniformTypeIdentifiers

// Cut, copy, paste and select-all, including where a repeated paste lands.
//
// Split out of EditorState.swift; nothing here changed on the way over.
extension EditorState {
    // MARK: - Clipboard

    /// ⌘C with a layer selected: the layer's model JSON (plus its bitmap for
    /// image layers — ImageRefs only mean something in this window's store)
    /// goes on the pasteboard under a Photonz-private type.
    ///
    /// With NO layer selected, ⌘C copies the marquee region — or, with no
    /// marquee either, the whole canvas — flattened from the composite. So
    /// ⌘A → ⌘C → ⌘V duplicates what you see (background included), and the
    /// PNG also pastes into other apps.
    func copySelectedLayer() {
        // A pixel region supersedes the layer (even one that's selected —
        // e.g. the fresh layer from ⌘N): ⌘C copies the region, not the layer.
        if selectionTargetsPixels, selection != nil {
            copyRegionFromComposite()
            return
        }
        if let id = selectedLayerID, let layer = document?.layer(id: id) {
            var imageData: Data?
            if case .image(let ref) = layer.content, let cg = store.image(for: ref) {
                imageData = ImageCodec.encode(cg, format: .png)
            }
            // The payload travels in CANVAS coordinates: a button copied out of
            // a screen remembers where it was on the canvas, not where it was
            // inside that screen, so pasting it lands it back over the screen.
            let travelling = document?.detachedLayer(id: id) ?? layer
            guard let payload = try? JSONEncoder().encode(LayerTransfer(layer: travelling, imageData: imageData)) else { return }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setData(payload, forType: NSPasteboard.PasteboardType(LayerTransfer.pasteboardType))
            // A copied measurement also travels as its spec line, so ⌘C then
            // ⌘V in a chat or a doc pastes "- Width: 128 px (size)" instead of
            // nothing. Photonz's own paste still prefers the layer payload.
            if let document, let line = MeasureSpecList.specLine(for: layer, in: document) {
                pasteboard.setString(line, forType: .string)
            }
            return
        }
        guard let document else { return }
        let canvas = CGRect(origin: .zero, size: document.canvasSize)
        let region = selection.map { Geometry.pixelAligned($0.bounds) } ?? canvas
        guard region.width >= 1, region.height >= 1,
              let raster = previewRenderer.rasterize(region: region, of: document, store: store),
              let png = ImageCodec.encode(raster, format: .png) else { return }
        // A Photonz image-layer payload (⌘V lands it as a layer over the copied
        // spot) plus a plain PNG for interoperability.
        let layer = Layer(name: "Copied Selection",
                          content: .image(ImageRef(pixelSize: region.size)), frame: region)
        guard let payload = try? JSONEncoder().encode(LayerTransfer(layer: layer, imageData: png)) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(payload, forType: NSPasteboard.PasteboardType(LayerTransfer.pasteboardType))
        pasteboard.setData(png, forType: .png)
    }

    /// The pixel region copied from the composite, CLIPPED to its path —
    /// transparent outside a wand blob or ellipse. Pastes as a layer over the
    /// copied spot in Photonz, and as a PNG elsewhere.
    private func copyRegionFromComposite() {
        guard let document, let selection else { return }
        let canvas = CGRect(origin: .zero, size: document.canvasSize)
        let frame = selection.path.boundingBoxOfPath.integral.intersection(canvas)
        guard !frame.isNull, frame.width >= 1, frame.height >= 1,
              let composite = previewRenderer.rasterize(region: canvas, of: document, store: store),
              let clipped = RegionOps.extracted(composite, path: selection.path),
              let png = ImageCodec.encode(clipped, format: .png) else { return }
        let layer = Layer(name: "Copied Selection",
                          content: .image(ImageRef(pixelSize: frame.size)), frame: frame)
        guard let payload = try? JSONEncoder().encode(LayerTransfer(layer: layer, imageData: png)) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(payload, forType: NSPasteboard.PasteboardType(LayerTransfer.pasteboardType))
        pasteboard.setData(png, forType: .png)
    }

    /// ⌘X: copy the selected (unlocked) layer, then remove it.
    func cutSelectedLayer() {
        guard let id = selectedLayerID, let layer = document?.layer(id: id),
              !layer.isLocked else { return }
        copySelectedLayer()
        deleteLayer(id: id)
    }

    /// ⌘A (Preview convention): marquee the whole canvas.
    func selectAll() {
        guard let document else { return }
        setSelection(SelectionRegion.rect(CGRect(origin: .zero, size: document.canvasSize)))
    }

    /// ⇧⌘A: clear the marquee.
    func deselect() {
        setSelection(nil)
    }

    /// ⇧⌘I (Photoshop): select everything OUTSIDE the current region. The
    /// result is a pixel-semantics region regardless of how the original was
    /// made — "the rest of the canvas" isn't a layer rubber-band.
    func invertSelection() {
        guard let document, let selection else { return }
        let full = SelectionRegion.rect(CGRect(origin: .zero, size: document.canvasSize))
        setSelection(full?.combining(selection, mode: .subtract), captureLayers: false)
    }

    /// File > New from Clipboard (⌘N, Preview convention): a clipboard image
    /// becomes a new document; beeps when the clipboard has none.
    func newFromClipboard() {
        if let image = NSImage(pasteboard: .general)?
            .cgImage(forProposedRect: nil, context: nil, hints: nil) {
            openCapture(image)
        } else {
            NSSound.beep()
        }
    }

    /// ⌘V: a copied Photonz layer pastes offset with a fresh identity; any
    /// system image (screenshot, copied web image) pastes as a new layer —
    /// or opens as a document when none is open.
    func paste() {
        // Pasting lands a NEW layer — the marquee belonged to the moment
        // before it; keeping stale ants over fresh content misleads
        // (Photoshop also deselects on a plain paste).
        setSelection(nil)
        let pasteboard = NSPasteboard.general
        if let data = pasteboard.data(forType: NSPasteboard.PasteboardType(LayerTransfer.pasteboardType)),
           let transfer = try? JSONDecoder().decode(LayerTransfer.self, from: data) {
            pasteLayer(transfer)
            return
        }
        if let image = NSImage(pasteboard: pasteboard)?
            .cgImage(forProposedRect: nil, context: nil, hints: nil) {
            pasteImage(image)
        }
    }

    /// Where the next paste goes, given where the first one belongs.
    ///
    /// Undoing a paste takes its copy back out of the document, so the ladder
    /// is trimmed to the copies that are still there and the next paste lands
    /// exactly where the undone one did — undo then paste puts back what you
    /// just took away, rather than opening a hole or landing on top of a copy
    /// that is still standing.
    private func cascadedPasteFrame(landingAt first: CGRect) -> CGRect {
        if pasteLadder?.clipboard != NSPasteboard.general.changeCount { pasteLadder = nil }
        while let last = pasteLadder?.rungs.last, document?.layer(id: last.layer) == nil {
            pasteLadder?.rungs.removeLast()
        }
        return PasteCascade.frame(landingAt: first, after: pasteLadder?.rungs.last?.frame,
                                  canvas: document?.canvasSize ?? .zero)
    }

    /// Remembers a paste so the next one can step past it. The frame is in
    /// canvas coordinates, which is the space the ladder is built in.
    private func recordPaste(_ id: UUID, at frame: CGRect) {
        let clipboard = NSPasteboard.general.changeCount
        if pasteLadder?.clipboard != clipboard { pasteLadder = (clipboard, []) }
        pasteLadder?.rungs.append((id, frame))
    }

    private func pasteLayer(_ transfer: LayerTransfer) {
        var layer = transfer.layer.duplicated()
        if case .image = transfer.layer.content {
            guard let data = transfer.imageData, let cg = ImageCodec.decode(data) else { return }
            // The payload's ImageRef belonged to the source window's store.
            layer.content = .image(store.register(cg))
        }
        if document == nil, case .image(let ref) = layer.content,
           let cg = store.image(for: ref) {
            openCapture(cg)
            return
        }
        guard let document else { return }
        // Each paste of one clipboard steps past the last, so pasting twice
        // leaves two copies you can see and tell apart rather than one hidden
        // exactly under the other.
        layer.frame = cascadedPasteFrame(landingAt: PasteCascade.stepped(transfer.layer.frame))
        // Named the way duplicating this layer names it, so the two ways of
        // making a copy agree and the pasted row can be told from the one it
        // came from. A name nothing here is using is kept as it is, so a layer
        // pasted into another document, or cut and pasted back, reads the same
        // as it always did (`LayerNaming.pastedName`).
        layer.name = LayerNaming.pastedName(of: transfer.layer.name,
                                            taken: Set(document.allLayers.map(\.name)))
        discardDragPreview()
        // Pasted over a screen means pasted ONTO it: the layer keeps the spot
        // it looks like it landed on and becomes part of that screen, the same
        // way a shape drawn there does.
        perform { [layer] in $0.addLayerDrawnOnFrame(layer) }
        selectedLayerID = layer.id
        recordPaste(layer.id, at: layer.frame)
    }

    /// `point` is where a drag let go, in canvas coordinates; nil for ⌘V,
    /// which has no pointer and falls back to the middle of the canvas.
    ///
    /// `fileName` is the file the picture came out of, so the layer can carry
    /// its name instead of a generic one. nil for the clipboard, which has no
    /// file behind it (`PlacedImageNaming`). A name already in use here takes
    /// the next free number, so placing the same file twice reads as two rows
    /// rather than one word repeated.
    func pasteImage(_ image: CGImage, at point: CGPoint? = nil,
                            fileName: String? = nil, landingAt landing: LayerDrop? = nil) {
        guard let document else {
            openCapture(image)
            return
        }
        let ref = store.register(image)
        // A drop on the panel points at a place in the STACK, not a place on
        // the picture, so it is sized to the list it is joining and centred
        // there. Everything else lands the way it always has.
        var frame = landing.map { document.placementForIncomingImage(size: ref.pixelSize, landingAt: $0) }
            ?? document.placementForIncomingImage(size: ref.pixelSize, at: point)
        guard !frame.isEmpty else { return }
        // ⌘V has no pointer, so the same picture keeps arriving in the middle
        // of the canvas: each one after the first steps past the last so you
        // can see the one you just made. A drop lands where you let go, which
        // is already somewhere you chose, so it never cascades.
        if point == nil, landing == nil { frame = cascadedPasteFrame(landingAt: frame) }
        // Numbered against what is already here, so dropping one file in twice
        // gives two rows you can tell apart instead of the same word twice.
        let name = PlacedImageNaming.layerName(fileName: fileName,
                                               taken: Set(document.allLayers.map(\.name)))
        let layer = Layer(name: name, content: .image(ref), frame: frame)
        discardDragPreview()
        perform {
            // The panel drew a line saying exactly where this goes, so that is
            // where it goes. The fallback is the way every other drop lands.
            if let landing, $0.insertLayer(layer, landing) { return }
            $0.addLayerDrawnOnFrame(layer)
        }
        // Landing inside a group opens it, so you can see where it went.
        if case .inside(let groupID) = landing { expandedGroupIDs.insert(groupID) }
        selectedLayerID = layer.id
        if point == nil, landing == nil { recordPaste(layer.id, at: frame) }
    }
}
