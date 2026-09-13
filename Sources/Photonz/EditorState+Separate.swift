import AppKit
import CoreGraphics
import PhotonzCore
import PhotonzRender

/// Separate into Layers (Next, `next-separate-into-layers`): every run of text
/// and every box in a picture comes out as its own layer, and the picture comes
/// back with the space each one came from filled in.
///
/// The reading and the pixel work live under it — `TextRunSweep` finds the runs,
/// `BoxSweep` finds the boxes and says which of them is really a shape,
/// `PatchDecision` says what goes in the hole, `LayerSeparator` does all of it
/// to a bitmap. This file is only the command: what it is offered on, getting
/// the work off the main thread, turning image pixels into document
/// coordinates, and landing the lot in ONE undo step.
///
/// Full design: `docs/design/separate-into-layers.md`.
@MainActor
extension EditorState {

    /// The name every separated run is given, numbered down the page. Without
    /// reading the actual characters this is the most a name can honestly say,
    /// and the order at least matches the order an eye scans the picture. When
    /// a later slice reads the words, this is the one line that changes.
    static let separatedRunName = "Text"

    /// And what a separated box is called. The app knows it is a box and does
    /// not know it is a button, so it says the thing it knows.
    static let separatedBoxName = "Box"

    /// Whether Separate into Layers applies to this layer (menu enablement).
    ///
    /// A picture, drawn the way its box says it is. A cropped or turned picture
    /// is out because the runs are found in the bitmap's own pixels and there
    /// would be no honest way back to where they sit on the canvas. The locked
    /// Background is deliberately IN: it is the picture a person actually
    /// starts from, and a lock stops a click from dragging a layer, not a
    /// command aimed at it by name.
    func canSeparateIntoLayers(id: UUID) -> Bool {
        guard Experiments.shared.separateIntoLayersEnabled,
              let layer = document?.layer(id: id), layer.imageRef != nil,
              layer.crop == nil, layer.transform.isIdentity
        else { return false }
        return true
    }

    /// Takes the picture apart.
    ///
    /// The sweep reads every pixel of the capture, which is not a frame's worth
    /// of work on a 12 megapixel one, so it runs off the main thread and the
    /// document is only touched when it comes back. Nothing is shown in the
    /// meantime on purpose: it lands in well under a second, and a spinner that
    /// flashes is worse than no spinner at all.
    func separateIntoLayers(id: UUID) {
        guard canSeparateIntoLayers(id: id), let document,
              let ref = document.layer(id: id)?.imageRef,
              let image = store.image(for: ref) else { return }
        guard !separationsInFlight.contains(id) else { return }
        separationsInFlight.insert(id)

        // The same two numbers Size mode reads a screenshot with, so what this
        // calls a run of text and what the measure tool calls one are the same
        // thing on the same capture, at 1x as well as 2x.
        let scale = max(1, document.pixelScale)
        let gap = Double(AlignmentScan.visibleGap * scale)
        let minElement = Double(max(10, 10 * scale))
        let cache = edgeMapCache
        let store = store
        Task.detached(priority: .userInitiated) { [weak self] in
            let luma = cache.lumaField(for: ref, store: store)
            let result = LayerSeparator.separate(image, luma: luma, gap: gap,
                                                 minElement: minElement)
            await MainActor.run {
                self?.separationsInFlight.remove(id)
                self?.applySeparation(id: id, result: result)
            }
        }
    }

    /// Lands what the sweep found: the picture's own bitmap becomes the patched
    /// one and the pieces are stacked over it, in a single `perform` and so in
    /// a single undo step, however many layers come out.
    private func applySeparation(id: UUID, result: LayerSeparator.Result?) {
        guard let document, let layer = document.layer(id: id),
              let ref = layer.imageRef else { return }
        guard let result, !result.pieces.isEmpty else {
            raiseCanvasNotice(.separatedIntoLayers(runs: 0, boxes: 0,
                                                   skipped: result?.skipped ?? 0))
            return
        }

        // Image pixels into the layer's own space. A screenshot opens at one
        // document point per image pixel, so this is usually the identity, but
        // a picture that has been scaled on the canvas has to carry its runs
        // with it or they would land somewhere else entirely.
        let pixels = ref.pixelSize
        let frame = layer.frame
        let sx = pixels.width > 0 ? frame.width / pixels.width : 1
        let sy = pixels.height > 0 ? frame.height / pixels.height : 1

        let patched = store.register(result.background)
        var runs = 0, boxes = 0
        let pieces = result.pieces.map { piece -> PhotonzDocument.SeparatedPiece in
            let placed = CGRect(x: frame.minX + piece.rect.minX * sx,
                                y: frame.minY + piece.rect.minY * sy,
                                width: piece.rect.width * sx,
                                height: piece.rect.height * sy)
            let name: String
            switch piece.kind {
            case .text:
                runs += 1
                name = "\(Self.separatedRunName) \(runs)"
            case .box:
                boxes += 1
                name = "\(Self.separatedBoxName) \(boxes)"
            }
            switch piece.body {
            case .picture(let image):
                return PhotonzDocument.SeparatedPiece(frame: placed,
                                                      ref: store.register(image), name: name)
            case .shape(let shape):
                // The shape was read in image pixels; the layer lives in the
                // picture's own space, so its rounding and its edge travel with
                // it. A picture shown at half size gets half the radius, which
                // is the only way a separated button keeps looking like the one
                // in the screenshot.
                let scale = (sx + sy) / 2
                return PhotonzDocument.SeparatedPiece(
                    frame: placed,
                    content: .shape(fill: shape.fill,
                                    radii: CornerRadii(
                                        topLeft: shape.radii.topLeft * scale,
                                        topRight: shape.radii.topRight * scale,
                                        bottomRight: shape.radii.bottomRight * scale,
                                        bottomLeft: shape.radii.bottomLeft * scale),
                                    borderWidth: shape.borderWidth * scale,
                                    borderColor: shape.borderColor),
                    name: name)
            }
        }

        discardDragPreview()
        var made: [UUID] = []
        perform { made = $0.separateIntoLayers(id: id, patched: patched, pieces: pieces) }
        guard !made.isEmpty else { return }
        // The FIRST piece down the page is left picked: one outline on the
        // canvas, where reading starts, so something visible says a piece is
        // now a thing of its own — and the layers list scrolls to the new rows.
        // Down the page rather than first in the list, because the list is
        // stacked boxes-then-words and the eye is not.
        //
        // Deliberately not all eleven. The canvas is identical the instant
        // after, so a person's first move is to grab a piece and drag it, and a
        // drag with everything picked would carry the whole page off the
        // picture in one go. One outline cannot do that.
        let first = pieces.indices.min {
            (pieces[$0].frame.minY, pieces[$0].frame.minX)
                < (pieces[$1].frame.minY, pieces[$1].frame.minX)
        }
        multiSelectedLayerIDs = []
        selectedLayerID = first.map { made[$0] } ?? made.first
        raiseCanvasNotice(.separatedIntoLayers(runs: runs, boxes: boxes,
                                               skipped: result.skipped))
    }
}
