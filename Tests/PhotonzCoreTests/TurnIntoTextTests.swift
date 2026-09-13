import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// Turn into Text at the document level: what happens to the LAYER when a
/// picture of a run of text becomes words, and what the pill says about it.
///
/// The reading itself — the recogniser, the face match, the refusals — is
/// measured against a real screenshot in
/// `PhotonzRenderTests/ReadRunAsTextFixtureTests.swift`. This is the mutation
/// and the sentence.
@Suite("A separated run becomes words you can retype")
struct TurnIntoTextTests {

    private let ref = ImageRef(pixelSize: CGSize(width: 180, height: 40))

    private func document(named name: String = "Text 9") -> PhotonzDocument {
        var document = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600))
        document.addLayer(Layer(name: "Background",
                                content: .image(ImageRef(pixelSize: CGSize(width: 800, height: 600))),
                                frame: CGRect(x: 0, y: 0, width: 800, height: 600)))
        var run = Layer(name: name, content: .image(ref),
                        frame: CGRect(x: 100, y: 80, width: 180, height: 40))
        run.isVisible = true
        document.addLayer(run)
        return document
    }

    private var words: TextContent {
        TextContent(string: "Save Changes", fontName: "SF Pro", fontSize: 27,
                    colorHex: "#FFFFFF", weight: .semibold)
    }

    @Test func theLayerKeepsItsIdentityAndItsSlotAndChangesWhatItIsMadeOf() throws {
        var document = self.document()
        let id = try #require(document.layers.last?.id)
        let box = CGRect(x: 98, y: 74, width: 190, height: 52)
        document.makeTextEditable(id: id, text: words, frame: box, name: "Save Changes")
        let layer = try #require(document.layer(id: id))
        #expect(layer.text?.string == "Save Changes")
        #expect(layer.imageRef == nil)
        #expect(layer.frame == box)
        #expect(layer.name == "Save Changes")
        // Same slot, same count: this replaces a layer, it does not add one.
        #expect(document.layers.count == 2)
        #expect(document.layers.last?.id == id)
    }

    @Test func aNameSomebodyTypedIsNotTakenAway() throws {
        // The caller decides, because only the caller knows whether the name
        // was the app's own numbering or a person's word. Passing nothing has
        // to leave the name exactly alone.
        var document = self.document(named: "Primary button label")
        let id = try #require(document.layers.last?.id)
        document.makeTextEditable(id: id, text: words, frame: .zero, name: nil)
        #expect(document.layer(id: id)?.name == "Primary button label")
    }

    @Test func anAppWrittenNameIsTheOneThisReplaces() throws {
        // `Text 9` is what Separate into Layers calls a run it could not read
        // the words of, and it is an automatic name by the app's own rule — so
        // the words are free to take its place.
        #expect(LayerNaming.isAutoName("Text 9"))
        #expect(!LayerNaming.isAutoName("Save Changes"))
    }

    @Test func nothingHappensToSomethingThatIsNotAPicture() throws {
        var document = self.document()
        let id = try #require(document.layers.last?.id)
        document.makeTextEditable(id: id, text: words, frame: .zero, name: "Save Changes")
        let before = document
        document.makeTextEditable(id: id, text: words, frame: .zero, name: "Twice")
        #expect(document.layer(id: id)?.name == before.layer(id: id)?.name)
        #expect(document.layer(id: id)?.text?.string == "Save Changes")
    }

    @Test func aCroppedOrTurnedPictureIsPutBackStraight() throws {
        // The reading happens in the bitmap's own pixels, so a crop or a turn
        // would have no honest way back to where the words sit on the canvas.
        // The command is not offered on one; if it ever were, the geometry that
        // could not be honoured is cleared rather than left to lie.
        var document = self.document()
        let id = try #require(document.layers.last?.id)
        document.updateLayer(id: id) {
            $0.crop = CGRect(x: 2, y: 2, width: 10, height: 10)
            $0.transform = LayerTransform(rotation: 0.3)
        }
        document.makeTextEditable(id: id, text: words, frame: .zero, name: nil)
        #expect(document.layer(id: id)?.crop == nil)
        #expect(document.layer(id: id)?.transform.isIdentity == true)
    }

    // MARK: - What the pill says

    private func pill(_ outcome: TextReading.Outcome) -> CopyConfirmation {
        CopyConfirmation(subject: .turnedIntoText(outcome), shownAt: Date())
    }

    @Test func wordsThatLandedSayWhatFaceTheyAreIn() throws {
        let reading = TextReading.Reading(
            string: "Save Changes",
            face: TextReading.Face(fontName: "SF Pro", weight: .semibold),
            fontSize: 27, colorHex: "#FFFFFF", agreement: 0.78, provenance: .matched)
        let pill = pill(.read(reading))
        #expect(pill.title == "Turned into text")
        #expect(pill.detail == "Save Changes, set in SF Pro Semibold")
    }

    @Test func aFallbackSaysThatItIsOne() throws {
        // The difference between "this is the face" and "this is the closest I
        // can set" is the whole promise of the feature, so it is said out loud
        // rather than hidden in a score.
        let reading = TextReading.Reading(
            string: "Copy to clipboard",
            face: TextReading.Face(fontName: "SF Pro", weight: .regular),
            fontSize: 27, colorHex: "#111111", agreement: 0.66, provenance: .fallback)
        #expect(pill(.read(reading)).detail
            == "Copy to clipboard, set in SF Pro, the closest face to the picture")
    }

    @Test func everyRefusalIsASentenceYouCanDoSomethingAbout() throws {
        #expect(pill(.refused(.noFaceMatches)).title == "Still a picture")
        for refusal in [TextReading.Refusal.notAPicture, .noWords, .moreThanOneRun,
                        .tooFaint, .noFaceMatches] {
            let detail = pill(.refused(refusal)).detail
            #expect(!detail.isEmpty)
            #expect(!detail.contains("—"))
        }
        #expect(pill(.refused(.moreThanOneRun)).detail.contains("Separate into Layers first"))
    }

    @Test func aRefusalStaysUpLongEnoughToRead() throws {
        // It is a whole sentence naming a thing to go and do, and the ordinary
        // pill life is under the time it takes to read one.
        #expect(pill(.refused(.moreThanOneRun)).lifetime == CopyConfirmation.breakLifetime)
    }
}
