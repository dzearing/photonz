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

    /// What a box's own body is called once it has had to become a group to
    /// hold the words that were sitting on it. The number stays on the group,
    /// so the list reads `Box 2 \u{25B8} Fill, Text 9` rather than saying Box 2
    /// twice and leaving you to work out which one is the button.
    static let separatedShapeBodyName = "Fill"
    static let separatedPictureBodyName = "Picture"

    /// How many pieces make a separation big enough to arrive gathered into
    /// one shut group (`next-a-separation-arrives-shut`). The layers list
    /// shows about five rows at rest and its grab bar reaches maybe fifteen,
    /// so twenty is the line where a separation stops being a list you can
    /// look at and becomes one you have to hunt through. Under it the pieces
    /// arrive loose, because taking a card or a small pane apart should hand
    /// you its pieces rather than a twist to open.
    static let gathersASeparationOver = 20

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
    /// meantime on purpose: a spinner that flashes is worse than no spinner at
    /// all.
    ///
    /// Measured on a release build: a 4.6 megapixel window capture reads in 83
    /// ms and separates in 267; the biggest screen on this machine, 7.7
    /// megapixels, is 120 and 502. So the worst real case is a shade over half
    /// a second and the common one is a quarter. It got about five times slower
    /// on a whole-window capture when the box sweep learnt to read one (it used
    /// to find nothing there and stop almost immediately), which is the trade
    /// and it is worth it — but the next thing that pushes this past a second
    /// owes the command a progress indicator.
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
            // Nothing came out, so the bitmap is untouched and the note goes on
            // the ref the picture already wears: it is a verdict about THESE
            // pixels, and it has to outlive the pill the same way a count does.
            rememberWhatIsLeft(in: ref, runs: 0, boxes: 0,
                               skipped: result?.skipped ?? 0, crowded: result?.crowded ?? 0)
            raiseCanvasNotice(.separatedIntoLayers(runs: 0, boxes: 0,
                                                   skipped: result?.skipped ?? 0,
                                                   crowded: result?.crowded ?? 0))
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
        // Where the numbering picks up. A dense screenshot takes more than one
        // run to come apart — the pill says so and says to run it again — and
        // starting over at Text 1 each time would leave the list holding two
        // rows called Text 57. It also steps around any text layer already in
        // the document, since a typed one is called Text too.
        let taken = Set((document.allLayers).map(\.name))
        let firstRun = LayerNaming.numberAfter(Self.separatedRunName, taken: taken)
        let firstBox = LayerNaming.numberAfter(Self.separatedBoxName, taken: taken)
        var runs = 0, boxes = 0
        var bodyNames: [String] = []
        let flat = result.pieces.map { piece -> PhotonzDocument.SeparatedPiece in
            let placed = CGRect(x: frame.minX + piece.rect.minX * sx,
                                y: frame.minY + piece.rect.minY * sy,
                                width: piece.rect.width * sx,
                                height: piece.rect.height * sy)
            let name: String
            let isRun: Bool
            switch piece.kind {
            case .text:
                name = "\(Self.separatedRunName) \(firstRun + runs)"
                runs += 1
                isRun = true
            case .box:
                name = "\(Self.separatedBoxName) \(firstBox + boxes)"
                boxes += 1
                isRun = false
            }
            // The shadow was read in image pixels too, so it is scaled the
            // same way the rounding is: a picture shown at half size gets half
            // the blur and half the throw, which is the only way a separated
            // card keeps looking like the one in the screenshot.
            let shadow = piece.shadow.map { shadow -> ShadowStyle in
                var scaled = shadow
                let scale = (sx + sy) / 2
                scaled.radius = shadow.radius * scale
                scaled.offset = CGSize(width: shadow.offset.width * sx,
                                       height: shadow.offset.height * sy)
                scaled.spread = shadow.spread * scale
                return scaled
            }
            switch piece.body {
            case .picture(let image):
                bodyNames.append(Self.separatedPictureBodyName)
                return PhotonzDocument.SeparatedPiece(frame: placed,
                                                      ref: store.register(image), name: name,
                                                      shadow: shadow, isRunOfText: isRun)
            case .shape(let shape):
                bodyNames.append(Self.separatedShapeBodyName)
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
                    name: name, shadow: shadow, isRunOfText: isRun)
            }
        }

        // Arranged the way the screen was. A label that sits in a button is a
        // CHILD of that button, so picking the button up picks the label up
        // too, and the layers list reads like the screen rather than like a
        // pile. `LayerNesting` is the whole rule and it knows nothing about
        // what a piece is: it takes rectangles and hands back a tree.
        //
        // Only where groups exist. With `next-layer-groups` off the layers
        // panel draws no twist at all, so a group's children would be in the
        // document and out of every reach a person has; the flat pile is at
        // least a pile they can use.
        let pieces: [PhotonzDocument.SeparatedPiece]
        if Experiments.shared.layerGroupsEnabled {
            func assemble(_ node: LayerNesting.Node) -> PhotonzDocument.SeparatedPiece {
                let piece = flat[node.index]
                guard !node.children.isEmpty else { return piece }
                return PhotonzDocument.SeparatedPiece(
                    frame: piece.frame, content: piece.content, name: piece.name,
                    bodyName: bodyNames[node.index],
                    children: node.children.map(assemble), shadow: piece.shadow,
                    isRunOfText: piece.isRunOfText)
            }
            pieces = result.nested.map(assemble)
        } else {
            pieces = flat
        }

        discardDragPreview()
        // A separation big enough to fill the layers list can arrive inside
        // ONE shut group named after the picture it came from, so the list is
        // one row longer rather than a hundred and forty
        // (`next-a-separation-arrives-shut`). Small separations never gather:
        // taking a card apart hands you its pieces, and wrapping three of them
        // would be a twist to open for nothing.
        let sourceName = document.layer(id: id).map {
            Experiments.shared.rowSaysItsWordsEnabled ? $0.displayName : $0.name
        } ?? "Background"
        let gatheredAs = Experiments.shared.separationArrivesShutEnabled
            && pieces.count >= Self.gathersASeparationOver
            ? String(format: NSLocalizedString("%@ pieces", comment: "name of the group a big separation arrives in"), sourceName)
            : nil
        var made: [UUID] = []
        perform {
            made = $0.separateIntoLayers(id: id, patched: patched, pieces: pieces,
                                         gatheredAs: gatheredAs)
        }
        guard !made.isEmpty else { return }
        // Gathered, the ONE thing picked is the group itself, shut. Picking a
        // piece inside it would open every twist above it to bring its row
        // into view, which is the whole arrangement undone in the first frame.
        if gatheredAs != nil, let group = made.first.flatMap({ self.document?.parentID(of: $0) }) {
            multiSelectedLayerIDs = []
            selectedLayerID = group
            rememberWhatIsLeft(in: patched, runs: runs, boxes: boxes,
                               skipped: result.skipped, crowded: result.crowded)
            raiseCanvasNotice(.separatedIntoLayers(runs: runs, boxes: boxes,
                                                   skipped: result.skipped,
                                                   crowded: result.crowded))
            return
        }
        // Every group this made is left OPEN. The command has just invented
        // these layers and the pill says how many came out, so a list that
        // hides most of them behind a twist reads as having lost them. One
        // click closes any of them, and closing the box you are done with is
        // how the list gets short.
        if let document = self.document {
            let groups = made.compactMap { document.layer(id: $0) }
                .flatMap(\.selfAndDescendants).filter(\.isGroup).map(\.id)
            if !groups.isEmpty { expandedGroupIDs.formUnion(groups) }
        }
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
        rememberWhatIsLeft(in: patched, runs: runs, boxes: boxes,
                           skipped: result.skipped, crowded: result.crowded)
        // Both halves of what just happened: what came out, and what stayed in
        // the picture. A screenshot dense enough to have pieces crowded out
        // says so and says what to do about it, which is run the command again
        // on the same picture: the pieces that came out are no longer in it, so
        // the next run reaches the ones behind them.
        raiseCanvasNotice(.separatedIntoLayers(runs: runs, boxes: boxes,
                                               skipped: result.skipped,
                                               crowded: result.crowded))
    }

    /// The one picture the foot of the layers list is speaking for: the last
    /// one separated that still has a batch in it, and the layer wearing it.
    ///
    /// The row note alone is not enough, and a picture settled it: separating a
    /// dense page leaves the list 105 rows long, scrolled to the pieces, with
    /// the picture's own row thirty screens below the bottom of the panel. The
    /// count was kept and nobody could see it. So the offer also sits UNDER the
    /// list, where it cannot scroll away, for as long as there is another batch
    /// to take.
    ///
    /// Only while another run would reach something. A picture that came apart
    /// completely, or one whose leftovers are simply unreadable, has nothing to
    /// offer and its row says so on its own — and by then the list is short
    /// enough that the row is on screen anyway.
    var separationStillOffering: SeparationOffer? {
        guard Experiments.shared.whatIsLeftInThePictureEnabled,
              let ref = lastSeparated, let left = separationLeftovers[ref],
              left.offersAnotherBatch,
              // Gone from the document means undone, or the layer was deleted.
              // Either way there is nothing left to offer a second run of.
              let layer = document?.allLayers.first(where: { $0.imageRef == ref })
        else { return nil }
        return SeparationOffer(id: layer.id, name: layer.name, left: left)
    }

    /// What the foot of the layers list draws, when it draws anything.
    struct SeparationOffer: Equatable {
        let id: UUID
        let name: String
        let left: SeparationLeftover
    }

    /// Keeps what the pill just said, on the bitmap it said it about.
    ///
    /// The pill is a glance and then it is gone, and the number it carries —
    /// 580 still in the picture — is one somebody wants back an hour later. So
    /// the same two counts are held against the picture's own pixels, where the
    /// layers row reads them (`SeparationLeftover`). Against the BITMAP and not
    /// the layer, because undo puts the original pixels back and the note has
    /// to go with them: a row still saying 580 left over a picture that holds
    /// all 724 again is worse than a row saying nothing.
    private func rememberWhatIsLeft(in ref: ImageRef, runs: Int, boxes: Int,
                                    skipped: Int, crowded: Int) {
        guard Experiments.shared.whatIsLeftInThePictureEnabled else { return }
        separationLeftovers[ref] = SeparationLeftover(runs: runs, boxes: boxes,
                                                      skipped: skipped, crowded: crowded)
        lastSeparated = ref
    }
}
