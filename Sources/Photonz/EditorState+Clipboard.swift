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

    /// Whether a marquee that means PIXELS is up. A rubber band thrown round
    /// a few layers is a way of picking layers, not a hole cut in the picture,
    /// so it never crops a copy.
    ///
    /// ⌘J reads the same two properties, so New Layer via Copy and ⌘C agree
    /// about what you picked and what the marquee means.
    var hasPixelRegion: Bool { selectionTargetsPixels && selection != nil }

    /// The picked layer, when there really is one in this document.
    var pickedLayerID: UUID? {
        guard let id = selectedLayerID, document?.layer(id: id) != nil else { return nil }
        return id
    }

    /// ⌘C: **copy takes what you picked, and a marquee crops it.**
    ///
    /// With a layer picked, the copy is that layer: whole when nothing is
    /// marqueed (its model JSON, plus its bitmap for image layers, since
    /// ImageRefs only mean something in this window's store), and its pixels
    /// inside the marquee when one is. Nothing from the layers around it comes
    /// along either way.
    ///
    /// With NO layer picked there is nothing to prefer, so ⌘C takes every
    /// layer flattened together inside the marquee — or, with no marquee
    /// either, the whole canvas. So ⌘A → ⌘C → ⌘V with nothing picked
    /// duplicates what you see, background included, and the PNG also pastes
    /// into other apps.
    ///
    /// Everything flattened together is ⇧⌘C (`copyMerged`).
    @discardableResult
    func copySelectedLayer() -> Bool {
        // Off, the old rule stands: a marquee supersedes the layer, so ⌘C
        // hands back the flattened region and the layer you picked is nowhere
        // in it. Dropping the picked layer here is all that takes.
        let picked = Experiments.shared.copyPicksYourLayerEnabled || !hasPixelRegion
            ? pickedLayerID : nil
        switch CopyRoute.copy(picked: picked, pixelRegion: hasPixelRegion,
                              hasDocument: document != nil) {
        case .nothing, .mergedImage: return false
        case .layer(let id): return copyWholeLayer(id)
        case .layerRegion(let id): return copyLayerRegion(id)
        case .mergedRegion: return copyMergedRegion()
        }
    }

    /// ⇧⌘C: every layer flattened together — the marquee's worth of it when
    /// one is up, and the whole picture when none is (`copyCompositeToClipboard`,
    /// which is the hand-off copy and carries the spec list with it).
    func copyMerged() {
        guard Experiments.shared.copyPicksYourLayerEnabled else {
            copyCompositeToClipboard() // off: ⇧⌘C is File ▸ Copy Image, as it was
            return
        }
        switch CopyRoute.copyMerged(pixelRegion: hasPixelRegion, hasDocument: document != nil) {
        case .mergedRegion: copyMergedRegion()
        case .mergedImage: copyCompositeToClipboard()
        default: return
        }
    }

    /// The whole picked layer, as a layer.
    private func copyWholeLayer(_ id: UUID) -> Bool {
        guard let layer = document?.layer(id: id) else { return false }
        var imageData: Data?
        if case .image(let ref) = layer.content, let cg = store.image(for: ref) {
            imageData = ImageCodec.encode(cg, format: .png)
        }
        // The payload travels in CANVAS coordinates: a button copied out of
        // a screen remembers where it was on the canvas, not where it was
        // inside that screen, so pasting it lands it back over the screen.
        let travelling = document?.detachedLayer(id: id) ?? layer
        guard let payload = try? JSONEncoder().encode(LayerTransfer(layer: travelling, imageData: imageData)) else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(payload, forType: NSPasteboard.PasteboardType(LayerTransfer.pasteboardType))
        // A copied measurement also travels as its spec line, so ⌘C then
        // ⌘V in a chat or a doc pastes "- Width: 128 px (size)" instead of
        // nothing. Photonz's own paste still prefers the layer payload.
        if let document, let line = MeasureSpecList.specLine(for: layer, in: document) {
            pasteboard.setString(line, forType: .string)
        }
        return true
    }

    /// The picked layer's pixels inside the marquee, and nothing from the
    /// layers around it: the layer is drawn ALONE (`render(_:store:only:)`)
    /// before the marquee crops it, clipped to its path so a wand blob or an
    /// ellipse comes out with the shape it was drawn in.
    ///
    /// The copy is then trimmed to the pixels that are actually there, the way
    /// slicing a layer with ⌫ tightens it to what survives, so a marquee flung
    /// round a small drawing hands back the drawing and not a big transparent
    /// box. A marquee that misses the layer entirely copies NOTHING and beeps:
    /// an invisible rectangle on the clipboard is worse than an honest refusal.
    private func copyLayerRegion(_ id: UUID) -> Bool {
        guard let document, let selection, let layer = document.layer(id: id) else { return false }
        guard let piece = previewRenderer.layerRegion(of: id, in: document, store: store,
                                                      path: selection.path) else {
            NSSound.beep() // nothing of that layer is inside the marquee
            return false
        }
        // Named after the layer it came out of, so pasting it reads as "Button
        // copy" rather than an anonymous scrap.
        return put(Layer(name: layer.name, content: .image(ImageRef(pixelSize: piece.frame.size)),
                         frame: piece.frame),
                   picture: piece.image)
    }

    /// Every layer flattened together inside the marquee — or the whole canvas
    /// when there is no marquee — CLIPPED to the marquee's path, so it is
    /// transparent outside a wand blob or an ellipse. Pastes as a layer over
    /// the copied spot in Photonz, and as a picture elsewhere.
    @discardableResult
    private func copyMergedRegion() -> Bool {
        guard let document else { return false }
        let canvas = CGRect(origin: .zero, size: document.canvasSize)
        let path = selection?.path ?? CGPath(rect: canvas, transform: nil)
        let frame = path.boundingBoxOfPath.integral.intersection(canvas)
        guard !frame.isNull, frame.width >= 1, frame.height >= 1,
              let composite = previewRenderer.rasterize(region: canvas, of: document, store: store),
              let clipped = RegionOps.extracted(composite, path: path) else { return false }
        return put(Layer(name: "Copied Selection", content: .image(ImageRef(pixelSize: frame.size)),
                         frame: frame),
                   picture: clipped)
    }

    /// A copied piece of picture on the pasteboard: the Photonz payload first,
    /// so ⌘V lands it back as a layer over the spot it came from, then PNG and
    /// TIFF so it pastes into other apps as the picture it is.
    private func put(_ layer: Layer, picture image: CGImage) -> Bool {
        guard let png = ImageCodec.encode(image, format: .png),
              let payload = try? JSONEncoder().encode(LayerTransfer(layer: layer, imageData: png))
        else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(payload, forType: NSPasteboard.PasteboardType(LayerTransfer.pasteboardType))
        pasteboard.setData(png, forType: .png)
        // TIFF for the long tail of AppKit apps that ask for nothing else.
        let tiffSource = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        if let tiff = tiffSource.tiffRepresentation { pasteboard.setData(tiff, forType: .tiff) }
        return true
    }

    /// ⌘X: cut follows copy. With a marquee up it takes the picked layer's
    /// pixels OUT of the marquee and leaves the rest of the layer standing
    /// (Photoshop); with no marquee it takes the whole unlocked layer.
    func cutSelectedLayer() {
        if Experiments.shared.copyPicksYourLayerEnabled, hasPixelRegion,
           let id = pickedLayerID, canSliceRegion(from: id) {
            // Nothing copied means nothing to cut: the marquee missed the
            // layer, and it already beeped.
            guard copyLayerRegion(id) else { return }
            deleteRegion() // slices the same layer the copy came off
            return
        }
        guard let id = selectedLayerID, let layer = document?.layer(id: id),
              !layer.isLocked else { return }
        // Cutting the layer whole copies it whole, marquee or no marquee: a
        // clipboard holding a corner of something the document no longer has
        // is the worse of the two answers.
        guard copyWholeLayer(id) else { return }
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
    ///
    /// Whatever arrived, it is the thing you are now working on: it is picked,
    /// and the pointer comes into your hand to move it, because dragging what
    /// you just pasted is the next thing anyone does. Undo hands your tool
    /// back (`handOverPointer`).
    func paste() {
        // Pasting lands a NEW layer — the marquee belonged to the moment
        // before it; keeping stale ants over fresh content misleads
        // (Photoshop also deselects on a plain paste).
        setSelection(nil)
        let tool = activeTool
        // The paste's own edit clears this on the way through, so the run it
        // belongs to is carried across by hand.
        let carried = pasteToolReturn
        let pasteboard = NSPasteboard.general
        var landed: UUID?
        if let data = pasteboard.data(forType: NSPasteboard.PasteboardType(LayerTransfer.pasteboardType)),
           let transfer = try? JSONDecoder().decode(LayerTransfer.self, from: data) {
            landed = pasteLayer(transfer)
        } else if let image = NSImage(pasteboard: pasteboard)?
            .cgImage(forProposedRect: nil, context: nil, hints: nil) {
            landed = pasteImage(image)
        }
        guard let landed else { return }
        handOverPointer(pasted: landed, held: tool, carrying: carried)
    }

    /// The pasted layer is picked and the pointer is in hand, so the next drag
    /// moves what you just pasted instead of drawing over it.
    ///
    /// A paste that failed, or that opened a new document instead of landing a
    /// layer, never gets here: switching the tool for nothing is exactly the
    /// kind of small theft that makes a tool bar feel untrustworthy.
    private func handOverPointer(pasted id: UUID, held tool: Tool,
                                 carrying carried: PasteToolReturn?) {
        guard Experiments.shared.pasteHandsYouThePointerEnabled else { return }
        setTool(.select)
        // Picking a tool drops the picked layer for tools that do not keep one,
        // and clears the tool memory. Select keeps it, but saying so here means
        // the paste is picked no matter which tool it came out of.
        selectedLayerID = id
        pasteToolReturn = PasteToolReturn.after(pasting: id, holding: tool, carrying: carried)
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

    /// The layer this paste landed, or nil when nothing landed: a payload that
    /// would not decode, or a paste into an empty window, which opens the
    /// picture as a document of its own instead.
    @discardableResult
    private func pasteLayer(_ transfer: LayerTransfer) -> UUID? {
        var layer = transfer.layer.duplicated()
        if case .image = transfer.layer.content {
            guard let data = transfer.imageData, let cg = ImageCodec.decode(data) else { return nil }
            // The payload's ImageRef belonged to the source window's store.
            layer.content = .image(store.register(cg))
        }
        if document == nil, case .image(let ref) = layer.content,
           let cg = store.image(for: ref) {
            openCapture(cg)
            return nil
        }
        guard let document else { return nil }
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
        return layer.id
    }

    /// `point` is where a drag let go, in canvas coordinates; nil for ⌘V,
    /// which has no pointer and falls back to the middle of the canvas.
    ///
    /// `fileName` is the file the picture came out of, so the layer can carry
    /// its name instead of a generic one. nil for the clipboard, which has no
    /// file behind it (`PlacedImageNaming`). A name already in use here takes
    /// the next free number, so placing the same file twice reads as two rows
    /// rather than one word repeated.
    ///
    /// Returns the layer it landed, or nil when the picture opened as a
    /// document of its own instead of joining one.
    @discardableResult
    func pasteImage(_ image: CGImage, at point: CGPoint? = nil,
                            fileName: String? = nil, landingAt landing: LayerDrop? = nil) -> UUID? {
        guard let document else {
            openCapture(image)
            return nil
        }
        let ref = store.register(image)
        // A drop on the panel points at a place in the STACK, not a place on
        // the picture, so it is sized to the list it is joining and centred
        // there. Everything else lands the way it always has.
        var frame = landing.map { document.placementForIncomingImage(size: ref.pixelSize, landingAt: $0) }
            ?? document.placementForIncomingImage(size: ref.pixelSize, at: point)
        guard !frame.isEmpty else { return nil }
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
        return layer.id
    }
}
