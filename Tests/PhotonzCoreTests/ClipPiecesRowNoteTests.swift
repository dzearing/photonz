import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// What a cut clip says on its row in the layers list.
///
/// A cut adds a piece to a clip and never a second row (UX-PATTERNS D18 item
/// 3, `docs/design/video-surface.md` §10.5), which is what stops a list
/// growing a row per cut — and left the list with no sign a recording had ever
/// been cut at all. The row says how many pieces it is in, and only when there
/// is more than one: a recording nobody has touched reads exactly as it always
/// did.
@Suite("A cut clip's row says how many pieces")
struct ClipPiecesRowNoteTests {

    private static func document(cuts: [Int]) -> PhotonzDocument {
        var layer = ClipPiecesTests.clipLayer()
        if !cuts.isEmpty {
            var pieces = layer.clipPieces!
            for ms in cuts {
                let split = pieces.split(atMS: ms)
                #expect(split)
            }
            layer.setClipPieces(pieces)
        }
        return ClipPiecesTests.document(layer)
    }

    private static func note(_ document: PhotonzDocument) -> ClipPiecesNote? {
        document.layerRows(expanded: [], selected: []).first?.piecesNote
    }

    // MARK: - The count, and nothing at all until there is one

    @Test func anUncutRecordingSaysNothingExtra() {
        #expect(Self.note(Self.document(cuts: [])) == nil)
    }

    @Test func aLayerThatDoesNotOccupyTimeSaysNothing() {
        let still = Layer(name: "Background",
                          content: .annotation(AnnotationContent(shape: .rectangle,
                                                                 colorHex: "#101010")),
                          frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(Self.note(ClipPiecesTests.document(still)) == nil)
    }

    @Test func oneCutSaysTwoPieces() {
        #expect(Self.note(Self.document(cuts: [4000]))?.text == "2 pieces")
    }

    @Test func twoCutsSayThreePieces() {
        let note = Self.note(Self.document(cuts: [2000, 6000]))
        #expect(note?.count == 3)
        #expect(note?.text == "3 pieces")
    }

    /// The count follows the clip: throwing pieces away until one is left
    /// takes the line off the row, because the clip is an ordinary stretch
    /// again and `setClipPieces` has already stopped storing pieces for it.
    @Test func throwingPiecesAwayUntilOneIsLeftTakesTheLineOff() {
        var document = Self.document(cuts: [2000, 6000])
        let id = document.layers[0].id
        let tookTheLast = document.removeClipPiece(id, at: 2)
        #expect(tookTheLast)
        #expect(Self.note(document)?.text == "2 pieces")
        let tookTheMiddle = document.removeClipPiece(id, at: 1)
        #expect(tookTheMiddle)
        #expect(Self.note(document) == nil)
    }

    /// A clip nobody has cut but somebody has retimed is still one piece, so
    /// it says nothing: what it is doing with time is the Speed section's
    /// sentence, not a count of pieces there are none of.
    @Test func aRetimedSinglePieceIsNotACutClip() {
        var layer = ClipPiecesTests.clipLayer()
        var pieces = layer.clipPieces!
        let retimed = pieces.setSpeed(ofPiece: 0, percent: 200)
        #expect(retimed)
        layer.setClipPieces(pieces)
        #expect(layer.cuts != nil)
        #expect(Self.note(ClipPiecesTests.document(layer)) == nil)
    }

    // MARK: - What the line says

    /// Short, because the slot is narrow: the row shares its width with a
    /// thumbnail, a padlock and an eye, and `SeparationLeftover` measured what
    /// is left at about eighteen characters before the tail is cut off.
    @Test func theLineFitsTheSlotItSharesWithTheThumbnailAndTheEye() {
        for cuts in [[4000], [2000, 6000], [1000, 2000, 3000, 4000, 5000]] {
            let text = Self.note(Self.document(cuts: cuts))?.text ?? ""
            #expect(text.count <= 18)
        }
    }

    /// The hover carries the sentence the line has no room for, and it is the
    /// one a person needs: this clip did not become three layers.
    @Test func theHoverSaysACutNeverAddsARow() {
        let help = Self.note(Self.document(cuts: [2000, 6000]))?.help ?? ""
        #expect(help.contains("3 pieces"))
        #expect(help.lowercased().contains("one row"))
    }

    // MARK: - It rides with the row wherever the row is shown

    /// A search result is a row like any other: a recording found by name
    /// still says how many pieces it is in.
    @Test func aSearchResultKeepsTheCount() {
        let document = Self.document(cuts: [2000, 6000])
        let rows = document.layerRows(matching: "record", selected: [])
        #expect(rows.count == 1)
        #expect(rows.first?.piecesNote?.text == "3 pieces")
    }
}
