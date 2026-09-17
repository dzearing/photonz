import AppKit
import CoreGraphics
import Dispatch
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

    /// Double clicking a label that is still a picture: read the words and
    /// then put the caret in them (Next, `next-double-click-reads-a-label`).
    ///
    /// The gesture already means "I want to change these words" on a text
    /// layer, and on a separated label it used to mean nothing at all. The
    /// reading is the same one Turn into Text does, on the ONE run under the
    /// pointer, so the guess lands where the person is looking and one undo
    /// press takes back exactly that. A reading that comes back with nothing
    /// raises the same line at the bottom of the canvas the menu row raises,
    /// and opens no field: there would be no words in it.
    ///
    /// Only offered on a run the separation lifted off a screenshot
    /// (`Layer.holdsWordsToRead`). Reading replaces the picture with what was
    /// found in it, which on an ordinary photo would be a picture turned into
    /// whatever word happened to be on a sign in it.
    ///
    /// Why this rather than reading every run inside Separate into Layers:
    /// `docs/design/separate-reads-the-words.md`.
    func readTheWordsThenType(id: UUID) {
        guard Experiments.shared.doubleClickReadsALabelEnabled,
              document?.layer(id: id)?.holdsWordsToRead == true else { return }
        typeAfterReading = id
        turnIntoText(id: id)
    }

    /// How many of a page's runs are asked before its family is settled.
    ///
    /// A vote does not need a census. The window this was measured on reads
    /// thirty-one runs and twenty-seven of them are the system font, so a dozen
    /// asked at random name the family with room to spare, and a dozen is about
    /// a tenth of a second of work spread over the cores — paid once, on the
    /// first label anybody turns into text, and never again for that page.
    private static let votersOnTheFamily = 12

    /// Reads the words in a picture and puts them back as text.
    ///
    /// Off the main thread like the sweep, and for the same reason: it reads
    /// every pixel of the picture and then sets the words a few dozen times
    /// over to find the face. It lands in about forty milliseconds on a run in
    /// a release build, so nothing is shown while it works — a spinner that
    /// flashes is worse than no spinner.
    ///
    /// It also settles what family the page is set in before it chooses a face,
    /// because a run cannot tell by looking at itself that it is the odd one
    /// out: on this app's own window four labels of thirty-one came back in a
    /// family the window does not contain, confidently, so "Border 1" arrived
    /// heavier than the identical "Border 2" below it. A dozen of the runs
    /// lying beside this one are asked what family they are, the answer is
    /// remembered for the rest of that separation, and this run is then set in
    /// the family that won. Where there is no page to ask, nothing votes and
    /// the run decides for itself exactly as it did
    /// (`docs/design/separate-into-layers.md`, "The page it came from settles
    /// the family").
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
        // And the family the rest of the page is in, which is the one thing
        // this run cannot work out by looking at itself.
        let page = document.parentID(of: id)
        let asked = familyTheRunsAreSetIn.index(forKey: page) != nil
        let settled = familyTheRunsAreSetIn[page] ?? nil
        let voters = asked ? [] : runsVotingOnTheFamily(with: id)
        Task.detached(priority: .userInitiated) { [weak self] in
            let family = asked ? settled
                : Self.familyTheseRunsVoteFor(voters, captureScale: captureScale)
            let read = TextReader.read(image, captureScale: captureScale,
                                       layerScale: layerScale, preferring: family)
            await MainActor.run {
                self?.separationsInFlight.remove(id)
                // Asked once per page and then remembered, including when the
                // answer was that nothing could be read: a vote nobody can cast
                // is still an answer, and re-counting it on every label would
                // pay for it over and over.
                if !asked, !voters.isEmpty { self?.familyTheRunsAreSetIn[page] = family }
                self?.applyTextReading(id: id, read: read)
            }
        }
    }

    /// The runs whose vote settles what family this page is set in: the ones
    /// lying beside this one, this one included, spread across them rather than
    /// taken off the top so a sample is not one panel's worth.
    ///
    /// "Beside" is the group the separation put them in, or the canvas itself
    /// when it left them loose. Empty for anything that is not a separated run,
    /// which is how Turn into Text on a whole screenshot, or on a picture
    /// somebody dragged in, goes on deciding exactly as it did.
    private func runsVotingOnTheFamily(with id: UUID) -> [CGImage] {
        guard let document, document.layer(id: id)?.isARunOfText == true else { return [] }
        let beside = document.parentID(of: id)
            .flatMap { document.layer(id: $0)?.children } ?? document.layers
        let runs = beside.filter { $0.isARunOfText == true && $0.imageRef != nil }
        guard !runs.isEmpty else { return [] }
        let step = max(1, runs.count / Self.votersOnTheFamily)
        var picked = stride(from: 0, to: runs.count, by: step).prefix(Self.votersOnTheFamily)
            .map { runs[$0] }
        if !picked.contains(where: { $0.id == id }), let mine = runs.first(where: { $0.id == id }) {
            picked[0] = mine
        }
        return picked.compactMap { $0.imageRef }.compactMap { store.image(for: $0) }
    }

    /// What a handful of runs say the family is, counted off the main thread
    /// and across the cores.
    ///
    /// Nil where none of them could be read, which leaves the run deciding for
    /// itself exactly as it did before — a page with no vote overrules nobody.
    private nonisolated static func familyTheseRunsVoteFor(
        _ images: [CGImage], captureScale: CGFloat
    ) -> String? {
        guard !images.isEmpty else { return nil }
        var families = [String?](repeating: nil, count: images.count)
        families.withUnsafeMutableBufferPointer { buffer in
            guard let raw = buffer.baseAddress else { return }
            DispatchQueue.concurrentPerform(iterations: images.count) { i in
                (raw + i).pointee = TextReader.family(in: images[i], captureScale: captureScale)
            }
        }
        return TextReading.pageFamily(ofFamilies: families.compactMap { $0 })
    }

    /// Lands what was read: the picture becomes a text layer in the same slot,
    /// with the same identity, sitting so its words cover the ink the picture
    /// held.
    private func applyTextReading(id: UUID, read: TextReader.Read) {
        guard let document, let layer = document.layer(id: id) else { return }
        // Whoever asked for this reading wanted to type in it afterwards. The
        // intent is spent here whatever the answer is, so a refusal never
        // leaves the next Turn into Text opening a field nobody asked for.
        let thenType = typeAfterReading == id
        typeAfterReading = nil
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
        // The caret goes in LAST, once the words are really there: the canvas
        // opens its field over the layer it finds in the document.
        if thenType { askToTypeIn(id) }
    }
}
