import AppKit
import CoreGraphics
import Dispatch
import PhotonzCore
import PhotonzRender

/// One run handed to a batch reading: everything the reader needs about it,
/// off the main actor. File scope rather than nested in the extension below,
/// because the extension is `@MainActor` and this travels into a detached task.
private struct RunToRead: Sendable {
    let id: UUID
    let image: CGImage
    /// How many of the picture's pixels fit in a document point, which is what
    /// decides how big the words have to be SET to cover the same space.
    let layerScale: CGFloat
}

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
        guard let landed = wordsAndBox(for: read, on: layer) else {
            raiseCanvasNotice(.turnedIntoText(read.outcome))
            return
        }

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
        perform { $0.makeTextEditable(id: id, text: landed.text, frame: landed.box) }
        selectedLayerID = id
        multiSelectedLayerIDs = []
        raiseCanvasNotice(.turnedIntoText(read.outcome))
        // The caret goes in LAST, once the words are really there: the canvas
        // opens its field over the layer it finds in the document.
        if thenType { askToTypeIn(id) }
    }

    /// What a reading becomes on the canvas: the words, and the box that puts
    /// them exactly where the picture's ink was.
    ///
    /// Nil for a reading that came back with nothing, which is the caller's to
    /// explain: one run says why in the pill, a batch counts it.
    private func wordsAndBox(for read: TextReader.Read,
                             on layer: Layer) -> (text: TextContent, box: CGRect)? {
        guard let reading = read.outcome.reading, let ink = read.inkRect,
              let ref = layer.imageRef else { return nil }
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
        return (text, TextReader.frame(for: text, placingInkAt: inkFrame, scale: layerScale))
    }

    // MARK: - Every label at once (`next-read-every-label`)

    /// Layer ▸ Turn into Text, over everything picked.
    ///
    /// Mirrors Turn Into Picture, which reads the whole selection and has done
    /// since 2026-09-16: right clicking one of five picked labels and getting
    /// only that one back was the odd command out.
    func turnIntoTextForSelection() {
        guard Experiments.shared.readEveryLabelEnabled else {
            if let id = selectedLayerID { turnIntoText(id: id) }
            return
        }
        turnIntoTextForLayers(ids: actionableLayerIDs)
    }

    /// Whether that row has anything to read.
    var canTurnIntoTextSelection: Bool {
        guard Experiments.shared.readEveryLabelEnabled else {
            return selectedLayerID.map { canTurnIntoText(id: $0) } ?? false
        }
        return !runsToRead(actionableLayerIDs).isEmpty
    }

    /// A layer row's Turn into Text: the whole selection when the row you right
    /// clicked is part of it, else that row on its own (`rowMenuTargets`), the
    /// one rule every other row of that menu already follows.
    func turnIntoTextForRow(id: UUID) {
        guard Experiments.shared.readEveryLabelEnabled else { turnIntoText(id: id); return }
        turnIntoTextForLayers(ids: rowMenuTargets(id))
    }

    /// Reads the words in several runs at once and lands every one that came
    /// back in ONE undo step.
    ///
    /// This is the shape the study asked for and the one a run at a time cannot
    /// have: read together, the runs can be compared with each other. The page
    /// votes on the family it is set in, every run is held to the winner, and a
    /// run the winner cannot account for stays a picture rather than coming
    /// back a weight heavier than the identical label beside it. Measured, that
    /// takes the strays to nought, at a cost of one reading of thirty-one on
    /// this app's own window (`docs/design/separate-reads-the-words.md`).
    ///
    /// One target is not a batch: it falls through to `turnIntoText(id:)`, so
    /// the singular pill still names the words and the face that came back, and
    /// a refusal still says why in a sentence.
    func turnIntoTextForLayers(ids: Set<UUID>) {
        guard let document else { return }
        let targets = runsToRead(ids).filter { !separationsInFlight.contains($0) }
        guard targets.count > 1 else {
            if let only = targets.first { turnIntoText(id: only) }
            return
        }
        // The capture's own scale is what the TYPE was set at, and it belongs
        // to the document rather than to any one run.
        let captureScale = max(1, document.pixelScale)
        let work: [RunToRead] = targets.compactMap { id in
            guard let layer = document.layer(id: id), let ref = layer.imageRef,
                  let image = store.image(for: ref) else { return nil }
            let scale = layer.frame.width > 0 ? ref.pixelSize.width / layer.frame.width : 1
            return RunToRead(id: id, image: image, layerScale: scale)
        }
        guard work.count > 1 else {
            if let only = work.first { turnIntoText(id: only.id) }
            return
        }
        let ids = work.map(\.id)
        separationsInFlight.formUnion(ids)
        // A family already settled for every page these runs came off is used
        // as it stands, so a batch and a label read on its own can never come
        // back in two different families on one screenshot.
        let pages = Set(work.map { document.parentID(of: $0.id) })
        let known = familyAlreadySettled(for: pages)
        let runs = work.map { TextReader.PageRun(image: $0.image, layerScale: $0.layerScale) }
        // Two seconds on the densest capture measured, and pressing the button
        // took the pill that offered it off screen. Without this the press
        // looks like it did nothing at all.
        raiseCanvasNotice(.readingTheWords(labels: work.count))
        Task.detached(priority: .userInitiated) { [weak self] in
            let reads = TextReader.readPage(runs, captureScale: captureScale,
                                            preferring: known, spreadingOverTheCores: true)
            // What the page turned out to be set in. Every reading that came
            // back is in it, so asking them is asking the page.
            let family = TextReading.pageFamily(of: reads.compactMap(\.outcome.reading)) ?? known
            await MainActor.run {
                guard let self else { return }
                self.separationsInFlight.subtract(ids)
                for key in pages { self.familyTheRunsAreSetIn[key] = family }
                self.applyBatchReading(Array(zip(ids, reads)), family: family)
            }
        }
    }

    /// The runs a batch would read, in the order the document holds them.
    ///
    /// A GROUP stands for the runs inside it, which is what makes the Layer
    /// menu a real door to this: a big separation arrives as one shut group
    /// with the group picked, so Turn into Text on it reads the screenshot.
    /// Anything else stands for itself, so pointing at one picture still means
    /// that picture, whole screenshots included — a person who aims Turn into
    /// Text at an unseparated capture gets the sentence telling them to
    /// separate it first, exactly as before.
    private func runsToRead(_ ids: Set<UUID>) -> [UUID] {
        guard let document else { return [] }
        var out: [UUID] = []
        var seen = Set<UUID>()
        for layer in document.allLayers where ids.contains(layer.id) {
            for piece in layer.selfAndDescendants {
                guard piece.id == layer.id || piece.holdsWordsToRead else { continue }
                guard canTurnIntoText(id: piece.id), seen.insert(piece.id).inserted else { continue }
                out.append(piece.id)
            }
        }
        return out
    }

    /// The family these pages have already been asked about, when they have all
    /// been asked and they all said the same thing. Nil is "ask again", which
    /// on a batch is the better answer anyway: a batch asks every run rather
    /// than a dozen of them.
    private func familyAlreadySettled(for pages: Set<UUID?>) -> String? {
        let known = pages.compactMap { familyTheRunsAreSetIn[$0] ?? nil }
        guard known.count == pages.count, Set(known).count == 1 else { return nil }
        return known.first
    }

    /// Lands a batch: every run that came back becomes words in ONE mutation,
    /// so one undo press takes the whole lot back, and one line says how many
    /// landed, what family they are in, and how many stayed pictures.
    private func applyBatchReading(_ found: [(UUID, TextReader.Read)], family: String?) {
        guard let document else { return }
        var edits: [(id: UUID, text: TextContent, box: CGRect)] = []
        var stayed = 0
        for (id, read) in found {
            // Gone from the document: undone, or deleted, while the reading was
            // still going. It is not a run that stayed a picture, it is a run
            // there is no longer anything to say about.
            guard let layer = document.layer(id: id) else { continue }
            guard let landed = wordsAndBox(for: read, on: layer) else {
                stayed += 1
                continue
            }
            edits.append((id, landed.text, landed.box))
        }
        // Somebody pressed undo while it read: the labels this was about are
        // pictures again and nothing happened. A line counting them would be
        // the app reporting on a state that no longer exists.
        guard !edits.isEmpty || stayed > 0 else { return }
        guard !edits.isEmpty else {
            raiseCanvasNotice(.turnedIntoTextInBatch(
                TextReading.Batch(read: 0, stillPictures: stayed, family: family)))
            return
        }
        discardDragPreview()
        // Nothing is selected or scrolled to afterwards. The person is looking
        // at a screenshot that is identical the instant after, and moving the
        // selection onto one of forty labels would be the app pointing at a
        // label nobody asked about.
        perform { document in
            for edit in edits {
                document.makeTextEditable(id: edit.id, text: edit.text, frame: edit.box)
            }
        }
        raiseCanvasNotice(.turnedIntoTextInBatch(
            TextReading.Batch(read: edits.count, stillPictures: stayed, family: family)))
    }
}
