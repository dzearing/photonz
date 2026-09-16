import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Double clicking the words on a button, when those words are a layer INSIDE
/// the button rather than a layer of their own.
///
/// This is the shape Separate into Layers hands back: a button comes out as a
/// group holding its own fill and its own label, so the words a person wants to
/// change are one level down. The canvas resolves a double click in a fixed
/// order — step into the group if there is anywhere to go, otherwise open the
/// words — and the tests below walk that order the way `CanvasNSView.mouseDown`
/// walks it, so the chain cannot quietly stop half way.
///
/// It exists because a runner read the code on 2026-09-13 and concluded the
/// descent could never stop returning a step, which was wrong: the walk that
/// looked broken was clicking three times into a field that had already opened.
@Suite("Double clicking a label inside a group")
struct DoubleClickALabelTests {

    private func id(_ doc: PhotonzDocument, _ name: String) -> UUID {
        doc.allLayers.first { $0.name == name }?.id ?? UUID()
    }

    /// Canvas 500×500 holding an unlocked page and, on it, "Button": a group at
    /// (200, 400) with "Fill" at local (0, 0) 248×60 and "Label" on top of it
    /// at local (37, 18) 174×29. So on the canvas the button covers
    /// (200, 400)–(448, 460) and its label covers (237, 418)–(411, 447) — the
    /// same arrangement `settings-pane-2x` separates into.
    private func makeButton(labelIsWords: Bool) -> PhotonzDocument {
        let fill = Layer(name: "Fill", content: .image(ImageRef(pixelSize: CGSize(width: 248, height: 60))),
                         frame: CGRect(x: 0, y: 0, width: 248, height: 60))
        var label = Layer(name: "Label",
                          content: .image(ImageRef(pixelSize: CGSize(width: 174, height: 29))),
                          frame: CGRect(x: 37, y: 18, width: 174, height: 29))
        label.isARunOfText = true
        if labelIsWords {
            label.content = .text(TextContent(string: "Save Changes"))
        }
        let button = Layer(name: "Button", content: .group(GroupContent(children: [fill, label])),
                           frame: CGRect(x: 200, y: 400, width: 0, height: 0))
        let page = Layer(name: "Page", content: .image(ImageRef(pixelSize: CGSize(width: 500, height: 500))),
                         frame: CGRect(x: 0, y: 0, width: 500, height: 500))
        return PhotonzDocument(canvasSize: CGSize(width: 500, height: 500), layers: [page, button])
    }

    /// A point on the words themselves.
    private let onTheLabel = CGPoint(x: 320, y: 432)

    // MARK: - The gesture, step by step

    @Test func aPlainClickPicksTheWholeButton() {
        let doc = makeButton(labelIsWords: true)
        let pick = doc.selectionTarget(at: onTheLabel, inside: nil)
        #expect(pick?.id == id(doc, "Button"))
        #expect(pick?.context == nil)
    }

    @Test func theFirstDoubleClickPicksTheLabelInsideIt() {
        let doc = makeButton(labelIsWords: true)
        let step = doc.descendTarget(at: onTheLabel, inside: nil)
        #expect(step?.id == id(doc, "Label"))
        #expect(step?.context == id(doc, "Button"))
    }

    /// The claim the whole task was about: the descent DOES stop. Standing
    /// inside the button with the label picked, a double click has nowhere left
    /// to go, which is what hands the gesture on to "open these words".
    @Test func theSecondDoubleClickHasNowhereLeftToGoAndSoOpensTheWords() {
        let doc = makeButton(labelIsWords: true)
        let button = id(doc, "Button")
        #expect(doc.descendTarget(at: onTheLabel, inside: button) == nil)
        let hit = doc.canvasHitTest(onTheLabel)
        #expect(hit?.id == id(doc, "Label"))
        guard case .text = hit?.content else { Issue.record("the label is not words"); return }
    }

    /// Standing inside the button already — which is where Turn into Text
    /// leaves you — the very first double click opens the words. That is not a
    /// bug, and it is why a walk that double clicks three times ends up typing
    /// into a field that opened on click one.
    @Test func alreadyInsideTheButtonOneDoubleClickIsEnough() {
        let doc = makeButton(labelIsWords: true)
        #expect(doc.descendTarget(at: onTheLabel, inside: id(doc, "Button")) == nil)
    }

    /// The label's box is stated against the button's corner, so what the
    /// canvas opens the field over has to be the canvas-space box or the words
    /// would be typed 200 points to the left of the button.
    @Test func theFieldOpensOverTheLabelWhereItSitsOnTheCanvas() {
        let doc = makeButton(labelIsWords: true)
        #expect(doc.canvasLayer(id: id(doc, "Label"))?.frame
                == CGRect(x: 237, y: 418, width: 174, height: 29))
    }

    // MARK: - A label the separation has not read yet

    @Test func aSeparatedRunStillSaysItHoldsWordsToRead() {
        let doc = makeButton(labelIsWords: false)
        #expect(doc.layer(id: id(doc, "Label"))?.holdsWordsToRead == true)
    }

    @Test func wordsAlreadyReadAreNotReadAgain() {
        let doc = makeButton(labelIsWords: true)
        #expect(doc.layer(id: id(doc, "Label"))?.holdsWordsToRead == false)
    }

    @Test func anOrdinaryPictureIsNeverReadByADoubleClick() {
        let doc = makeButton(labelIsWords: false)
        // The page is a picture too, and a double click on a photo that turned
        // the photo into whatever word it happened to contain would be the
        // worst thing this gesture could do.
        #expect(doc.layer(id: id(doc, "Page"))?.holdsWordsToRead == false)
        #expect(doc.layer(id: id(doc, "Fill"))?.holdsWordsToRead == false)
    }

    @Test func aLockedRunIsLeftAlone() {
        var doc = makeButton(labelIsWords: false)
        doc.updateLayer(id: id(doc, "Label")) { $0.isLocked = true }
        #expect(doc.layer(id: id(doc, "Label"))?.holdsWordsToRead == false)
    }

    @Test func aRunThatHasBeenCroppedOrTurnedIsLeftAlone() {
        var doc = makeButton(labelIsWords: false)
        let label = id(doc, "Label")
        doc.updateLayer(id: label) { $0.crop = CGRect(x: 0, y: 0, width: 10, height: 10) }
        #expect(doc.layer(id: label)?.holdsWordsToRead == false)
        doc.updateLayer(id: label) {
            $0.crop = nil
            $0.transform.rotation = 0.2
        }
        #expect(doc.layer(id: label)?.holdsWordsToRead == false)
    }

    // MARK: - Where the mark comes from

    @Test func separatingMarksTheRunsOfTextAndNothingElse() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 500, height: 500), layers: [
            Layer(name: "Shot", content: .image(ImageRef(pixelSize: CGSize(width: 500, height: 500))),
                  frame: CGRect(x: 0, y: 0, width: 500, height: 500))
        ])
        let shot = doc.layers[0].id
        let ref = ImageRef(pixelSize: CGSize(width: 10, height: 10))
        let label = PhotonzDocument.SeparatedPiece(
            frame: CGRect(x: 37, y: 18, width: 174, height: 29), ref: ref, name: "Text 9",
            isRunOfText: true)
        let button = PhotonzDocument.SeparatedPiece(
            frame: CGRect(x: 200, y: 400, width: 248, height: 60), ref: ref, name: "Box 4",
            bodyName: "Fill", children: [label])
        doc.separateIntoLayers(id: shot, patched: ref, pieces: [button])
        #expect(doc.allLayers.first { $0.name == "Text 9" }?.isARunOfText == true)
        #expect(doc.allLayers.first { $0.name == "Fill" }?.isARunOfText != true)
        #expect(doc.allLayers.first { $0.name == "Box 4" }?.isARunOfText != true)
    }

    @Test func aDocumentWrittenBeforeThisMarkExistedReadsBackUnchanged() throws {
        let doc = makeButton(labelIsWords: false)
        let round = try JSONDecoder().decode(PhotonzDocument.self,
                                             from: JSONEncoder().encode(doc))
        #expect(round.allLayers.first { $0.name == "Label" }?.isARunOfText == true)
        #expect(round.allLayers.first { $0.name == "Fill" }?.isARunOfText == nil)
    }
}
