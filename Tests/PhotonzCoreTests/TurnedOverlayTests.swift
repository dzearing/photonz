import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Where a flat rectangle of the platform's — the inline typing field is the
/// one this was written for — has to sit and how far it has to swing to land
/// ON a layer rather than beside it, once that layer has been turned by its
/// own knob, by a card above it, or by both.
@Suite("An upright overlay on a turned layer")
struct TurnedOverlayTests {

    private func box(_ rect: CGRect, name: String = "Box") -> Layer {
        Layer(name: name, content: .annotation(AnnotationContent(shape: .rectangle)), frame: rect)
    }

    private func words(_ rect: CGRect, name: String = "Words") -> Layer {
        Layer(name: name, content: .text(TextContent(string: "Save")), frame: rect)
    }

    /// A card holding a bar and a line of words, turned about the middle of
    /// the box its contents make, which is (500, 400).
    private func card(rotation: CGFloat) -> Layer {
        let content = GroupContent(children: [
            box(CGRect(x: 300, y: 300, width: 400, height: 200), name: "Bar"),
            words(CGRect(x: 340, y: 340, width: 54, height: 32)),
        ])
        return Layer(name: "Card", content: .group(content),
                     frame: .zero, transform: LayerTransform(rotation: rotation))
    }

    private func document(_ layers: [Layer]) -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 1440, height: 1024), layers: layers)
    }

    // MARK: Nothing turned

    @Test("A layer nothing has turned leaves the overlay exactly where it was")
    func uprightIsUntouched() {
        let flat = card(rotation: 0)
        let doc = document([flat])
        let label = flat.children[1].id
        let overlay = doc.turnedOverlay(for: label, upright: CGPoint(x: 340, y: 340))
        #expect(overlay.origin == CGPoint(x: 340, y: 340))
        #expect(overlay.radians == 0)
        #expect(overlay.beyondATurn == false)
    }

    @Test("An id the document has never heard of is not a reason to move anything")
    func anUnknownLayerIsUpright() {
        let overlay = document([]).turnedOverlay(for: UUID(), upright: CGPoint(x: 12, y: 34))
        #expect(overlay.origin == CGPoint(x: 12, y: 34))
        #expect(overlay.radians == 0)
    }

    @Test("No layer at all is not a reason to move anything")
    func noLayerIsUpright() {
        let overlay = document([]).turnedOverlay(for: nil, upright: CGPoint(x: 12, y: 34))
        #expect(overlay.origin == CGPoint(x: 12, y: 34))
        #expect(overlay.radians == 0)
    }

    // MARK: A card above it

    @Test("Words inside a turned card get the corner the words are really drawn at")
    func aPieceFollowsTheCard() {
        let turned = card(rotation: 20 * .pi / 180)
        let doc = document([turned])
        let label = turned.children[1].id
        let overlay = doc.turnedOverlay(for: label, upright: CGPoint(x: 340, y: 340))
        // Twenty degrees clockwise about (500, 400) takes (340, 340) to
        // (370.17, 288.90) — the number the canvas reports for the words.
        #expect(abs(overlay.origin.x - 370.17) < 0.05)
        #expect(abs(overlay.origin.y - 288.90) < 0.05)
        #expect(abs(overlay.radians - 20 * .pi / 180) < 0.0001)
        #expect(overlay.beyondATurn == false)
    }

    @Test("The overlay's corner is the same point the canvas turns that corner to")
    func theCornerAgreesWithTheCanvas() {
        let turned = card(rotation: .pi / 3)
        let doc = document([turned])
        let label = turned.children[1].id
        let corner = CGPoint(x: 340, y: 340)
        let overlay = doc.turnedOverlay(for: label, upright: corner)
        let canvas = corner.applying(doc.inheritedTurn(of: label))
        #expect(abs(overlay.origin.x - canvas.x) < 0.0001)
        #expect(abs(overlay.origin.y - canvas.y) < 0.0001)
    }

    // MARK: Its own knob

    @Test("A layer turned by its own knob swings the overlay too")
    func aLoneLayerFollowsItsOwnTurn() {
        // 54 by 32 at (340, 340), so its middle is (367, 356).
        let lone = words(CGRect(x: 340, y: 340, width: 54, height: 32))
        var turned = lone
        turned.transform = LayerTransform(rotation: .pi / 2)
        let doc = document([turned])
        let overlay = doc.turnedOverlay(for: turned.id, upright: CGPoint(x: 340, y: 340))
        // A quarter turn about (367, 356) takes (340, 340) to (383, 329).
        #expect(abs(overlay.origin.x - 383) < 0.001)
        #expect(abs(overlay.origin.y - 329) < 0.001)
        #expect(abs(overlay.radians - .pi / 2) < 0.0001)
    }

    @Test("A layer turned by its own knob INSIDE a turned card takes both swings")
    func bothTurnsCompose() {
        var turned = card(rotation: 20 * .pi / 180)
        turned.children[1].transform = LayerTransform(rotation: 10 * .pi / 180)
        let doc = document([turned])
        let label = turned.children[1].id
        let overlay = doc.turnedOverlay(for: label, upright: CGPoint(x: 340, y: 340))
        #expect(abs(overlay.radians - 30 * .pi / 180) < 0.0001)
        // The corner is the piece's own turn about its own middle, then the
        // card's turn about the card's: (340, 340) -> (343.19, 335.55) ->
        // (374.69, 285.81).
        #expect(abs(overlay.origin.x - 374.69) < 0.05)
        #expect(abs(overlay.origin.y - 285.81) < 0.05)
    }

    // MARK: What a rectangle cannot match

    @Test("A leaning or mirrored layer says so, because a plain rectangle cannot match it")
    func skewAndFlipAreOwnedUpTo() {
        var leaning = words(CGRect(x: 340, y: 340, width: 54, height: 32))
        leaning.transform = LayerTransform(rotation: 0, skewX: 0.3)
        let skewed = document([leaning]).turnedOverlay(for: leaning.id,
                                                       upright: CGPoint(x: 340, y: 340))
        #expect(skewed.beyondATurn == true)

        var mirrored = words(CGRect(x: 340, y: 340, width: 54, height: 32))
        mirrored.transform = LayerTransform(rotation: 0, flipHorizontal: true)
        let flipped = document([mirrored]).turnedOverlay(for: mirrored.id,
                                                         upright: CGPoint(x: 340, y: 340))
        #expect(flipped.beyondATurn == true)
    }
}
