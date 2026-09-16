import AppKit
import CoreGraphics
import PhotonzCore
import PhotonzRender

/// Turn into Text (Next, `next-separate-into-layers`): a picture of a run of
/// text becomes WORDS you can retype, in the face, size and colour the picture
/// was set in.
///
/// It is the step AFTER Separate into Layers rather than part of it, and that
/// is deliberate. Separating a screenshot is one thing a person asked for;
/// reading the words is another, it costs a recognition pass per run, and it is
/// the one step here that can come back and say no. Made automatic it would
/// slow the command everybody uses in order to sometimes surprise them; offered
/// as its own item in the same menu, it is there the moment they want it.
///
/// The reading lives under it — `TextReader` runs the recogniser and matches
/// the face, `TextReading` decides whether the match is good enough. This file
/// is only the command: what it is offered on, getting the work off the main
/// thread, putting the words exactly where the old ones were, and landing it in
/// ONE undo step.
///
/// Full design: `docs/design/separate-into-layers.md`.
@MainActor
extension EditorState {

    /// Whether Turn into Text applies to this layer (menu enablement).
    ///
    /// The same picture Separate into Layers is offered on, for the same
    /// reasons, and deliberately including the whole screenshot. A person who
    /// tries it on a whole page gets a sentence telling them to separate it
    /// first, which is a better answer than a menu item that is not there:
    /// a greyed row teaches nothing and a missing one teaches less.
    func canTurnIntoText(id: UUID) -> Bool {
        canSeparateIntoLayers(id: id)
    }

    /// Reads the words in a picture and puts them back as text.
    ///
    /// Off the main thread like the sweep, and for the same reason: it reads
    /// every pixel of the picture and then sets the words a few dozen times
    /// over to find the face. It lands in about forty milliseconds on a run in
    /// a release build, so nothing is shown while it works — a spinner that
    /// flashes is worse than no spinner.
    func turnIntoText(id: UUID) {
        guard canTurnIntoText(id: id), let document,
              let layer = document.layer(id: id), let ref = layer.imageRef,
              let image = store.image(for: ref) else { return }
        guard !separationsInFlight.contains(id) else { return }
        separationsInFlight.insert(id)

        // Two scales and they are different numbers. The capture's own is what
        // the TYPE was set at — a Retina screenshot holds two pixels per point
        // of the label in it — and the face is identified at that size, because
        // the system font is a different shape at label size and at heading
        // size. The layer's is how many of the picture's pixels fit in a
        // document point, which is what decides how big the words have to be
        // SET to cover the same space.
        let captureScale = max(1, document.pixelScale)
        let pixels = ref.pixelSize
        let layerScale = layer.frame.width > 0 ? pixels.width / layer.frame.width : 1
        Task.detached(priority: .userInitiated) { [weak self] in
            let read = TextReader.read(image, captureScale: captureScale,
                                       layerScale: layerScale)
            await MainActor.run {
                self?.separationsInFlight.remove(id)
                self?.applyTextReading(id: id, read: read)
            }
        }
    }

    /// Lands what was read: the picture becomes a text layer in the same slot,
    /// with the same identity, sitting so its words cover the ink the picture
    /// held.
    private func applyTextReading(id: UUID, read: TextReader.Read) {
        guard let document, let layer = document.layer(id: id) else { return }
        guard let reading = read.outcome.reading, let ink = read.inkRect,
              let ref = layer.imageRef else {
            raiseCanvasNotice(.turnedIntoText(read.outcome))
            return
        }
        // Image pixels into the layer's own space, the same conversion Separate
        // makes: a screenshot opens at one document point per image pixel, so
        // this is usually the identity, but a picture scaled on the canvas has
        // to carry its ink with it.
        let pixels = ref.pixelSize
        let frame = layer.frame
        let sx = pixels.width > 0 ? frame.width / pixels.width : 1
        let sy = pixels.height > 0 ? frame.height / pixels.height : 1
        let inkFrame = CGRect(x: frame.minX + ink.minX * sx, y: frame.minY + ink.minY * sy,
                              width: ink.width * sx, height: ink.height * sy)

        var text = TextContent(string: reading.string, fontName: reading.face.fontName,
                               fontSize: reading.fontSize, colorHex: reading.colorHex,
                               weight: reading.face.weight)
        // A run of text is one line, which is what a run IS, and it stays one
        // however narrow the box gets. Without this, dragging the new layer's
        // side handle would re-wrap a button's label into two lines inside the
        // button.
        text.staysOnOneLine = true
        let layerScale = sx > 0 ? 1 / sx : 1
        let box = TextReader.frame(for: text, placingInkAt: inkFrame, scale: layerScale)

        // Nothing renames the layer here, and that is the point: a piece of
        // text nobody has named by hand already wears its own words in the
        // layers list, so the row turns from `Text 9` into `Save Changes` the
        // instant the words land — and follows them if they are retyped
        // afterwards, which a name written down once could not
        // (`Layer.displayName`).
        // Deliberately no auto-contrast shadow, which is what typing fresh text
        // on a picture gets. These words were already legible where they came
        // from — they are going back exactly where they were — and a shadow
        // nobody asked for is the difference between a label that matches the
        // screenshot and one that nearly does.
        perform { $0.makeTextEditable(id: id, text: text, frame: box) }
        selectedLayerID = id
        multiSelectedLayerIDs = []
        raiseCanvasNotice(.turnedIntoText(read.outcome))
    }
}
