import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// What the picture's own row says about what is STILL in it after Separate
/// into Layers, once the pill has faded (`SeparationLeftover`).
@Suite("What a separation left behind")
struct SeparationLeftoverTests {

    @Test func aDenseScreenshotSaysHowManyAreLeftAndOffersTheNextBatch() {
        // The measured case from 2026-09-13: 142 pieces out of 724.
        let note = SeparationLeftover(runs: 138, boxes: 4, skipped: 0, crowded: 580)
        #expect(note.count == 580)
        #expect(note.text == "580 left")
        #expect(note.offersAnotherBatch)
        #expect(note.help.contains("580 pieces"))
        #expect(note.help.contains("Separating it again"))
    }

    @Test func bothReasonsAreCountedTogetherBecauseThatIsWhatYouCanSee() {
        let note = SeparationLeftover(runs: 90, boxes: 3, skipped: 26, crowded: 14)
        #expect(note.count == 40)
        #expect(note.text == "40 left")
        // Something the limit crowded out comes back on the next run, so the
        // offer stands even though some of the 40 never will.
        #expect(note.offersAnotherBatch)
    }

    @Test func piecesLeftOnlyBecauseTheyAreUnreadableDoNotOfferAnotherRun() {
        // 93 out and 26 left on this app's own window, none of them crowded:
        // running again would find the same 26 and refuse them the same way.
        let note = SeparationLeftover(runs: 90, boxes: 3, skipped: 26, crowded: 0)
        #expect(note.count == 26)
        #expect(note.text == "26 left, unclear")
        #expect(!note.offersAnotherBatch)
    }

    @Test func aPictureThatCameApartCompletelySaysNothingIsLeft() {
        let note = SeparationLeftover(runs: 11, boxes: 2, skipped: 0, crowded: 0)
        #expect(note.count == 0)
        #expect(note.text == "Nothing left")
        #expect(!note.offersAnotherBatch)
    }

    @Test func aPhotographSaysWhyRatherThanCountingItsGrass() {
        // The measured photograph: 437 pieces found in the grass and the rock
        // face, none readable, none anything a person would point at. The row
        // says the same sentence the pill says, for the same reason.
        let note = SeparationLeftover(runs: 0, boxes: 0, skipped: 437, crowded: 0)
        #expect(note.text == "Nothing readable")
        #expect(!note.offersAnotherBatch)
    }

    @Test func aCaptionBurntIntoAPhotographIsWorthCountingOutLoud() {
        // A handful of things a person is looking straight at and did not get.
        let note = SeparationLeftover(runs: 0, boxes: 0, skipped: 2, crowded: 0)
        #expect(note.text == "2 left, unclear")
        #expect(!note.offersAnotherBatch)
    }

    @Test func nothingFoundAtAllSaysTheSameSentenceAsAPhotograph() {
        let note = SeparationLeftover(runs: 0, boxes: 0, skipped: 0, crowded: 0)
        #expect(note.text == "Nothing readable")
        #expect(!note.offersAnotherBatch)
    }

    @Test func oneLeftIsSingular() {
        let note = SeparationLeftover(runs: 4, boxes: 0, skipped: 1, crowded: 0)
        #expect(note.text == "1 left, unclear")
        #expect(note.help.contains("1 piece is"))
    }

    @Test func everyLineFitsTheRowItIsPrintedOn() {
        // Measured, not a taste: the second line of a layers row has about 95
        // points on the dock's own width, which is eighteen characters at the
        // size it is set in. "Nothing left to separate" came out of the app
        // reading "Nothing left to sep...".
        let every = [
            SeparationLeftover(runs: 138, boxes: 4, skipped: 0, crowded: 580),
            SeparationLeftover(runs: 90, boxes: 3, skipped: 26, crowded: 0),
            SeparationLeftover(runs: 11, boxes: 2, skipped: 0, crowded: 0),
            SeparationLeftover(runs: 0, boxes: 0, skipped: 437, crowded: 0),
            SeparationLeftover(runs: 0, boxes: 0, skipped: 2, crowded: 0),
        ]
        for note in every {
            #expect(note.text.count <= 18, "\(note.text) is \(note.text.count) characters")
        }
    }

    @Test func theLineUnderTheWholeListNamesWhatItIsCounting() {
        // The row can say "580 left" because it is printed on the picture it is
        // counting. A line under the whole list cannot.
        #expect(SeparationLeftover.stillInThePicture(580) == "580 left in the picture")
        #expect(SeparationLeftover.stillInThePicture(1) == "1 left in the picture")
    }

    @Test func theRowAndThePillAgreeAboutTheNumber() {
        // The row is the pill's own count, kept: whatever the pill said is
        // still in the picture is what the row goes on saying.
        for (skipped, crowded) in [(0, 580), (26, 0), (26, 14), (0, 0)] {
            let note = SeparationLeftover(runs: 5, boxes: 1, skipped: skipped, crowded: crowded)
            #expect(note.count == skipped + crowded)
        }
    }
}

/// The note reaching the row it belongs to: the picture's own row, and no
/// other, keyed by the BITMAP so undo takes it away with the separation.
@Suite("The picture's row carries what it left behind")
struct SeparationLeftoverRowTests {

    private func capture() -> (document: PhotonzDocument, id: UUID, ref: ImageRef) {
        let ref = ImageRef(pixelSize: CGSize(width: 400, height: 300))
        let document = PhotonzDocument.withBaseImage(ref)
        return (document, document.layers[0].id, ref)
    }

    private let note = SeparationLeftover(runs: 138, boxes: 4, skipped: 0, crowded: 580)

    @Test func thePicturesOwnRowSaysWhatIsStillInIt() {
        let (document, id, ref) = capture()
        let rows = document.layerRows(expanded: [], selected: [], separations: [ref: note])
        #expect(rows.first { $0.id == id }?.separationNote == note)
    }

    @Test func noOtherRowSaysAnything() {
        var (document, _, ref) = capture()
        let piece = Layer(name: "Text 1", content: .text(TextContent(string: "Hi")),
                          frame: CGRect(x: 0, y: 0, width: 20, height: 10))
        document.layers.append(piece)
        let rows = document.layerRows(expanded: [], selected: [], separations: [ref: note])
        #expect(rows.filter { $0.separationNote != nil }.count == 1)
        #expect(rows.first { $0.name == "Text 1" }?.separationNote == nil)
    }

    @Test func aPictureNobodyHasSeparatedSaysNothing() {
        let (document, _, _) = capture()
        let rows = document.layerRows(expanded: [], selected: [])
        #expect(rows.allSatisfy { $0.separationNote == nil })
    }

    @Test func undoingTheSeparationTakesTheNoteWithIt() {
        // The note is held against the PATCHED bitmap. Undo puts the original
        // bitmap back on the layer, so the row stops claiming 580 are left in
        // a picture that holds all 724 again.
        var (document, id, original) = capture()
        let patched = ImageRef(pixelSize: CGSize(width: 400, height: 300))
        _ = document.separateIntoLayers(id: id, patched: patched, pieces: [])
        let held = [patched: note]
        #expect(document.layerRows(expanded: [], selected: [], separations: held)
            .first { $0.id == id }?.separationNote == note)

        // Undo, modelled the way history does it: the layer wears its original
        // bitmap again.
        document.updateLayer(id: id) { $0.content = .image(original) }
        #expect(document.layerRows(expanded: [], selected: [], separations: held)
            .first { $0.id == id }?.separationNote == nil)
    }
}
