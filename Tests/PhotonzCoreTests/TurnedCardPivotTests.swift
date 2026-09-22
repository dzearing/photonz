import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Changing ONE piece inside a card that has been turned leaves every other
/// piece in that card exactly where it is drawn.
///
/// A turned group swings about the middle of the box its contents make, and
/// that box is measured live: the moment a piece inside grows, the point the
/// whole card swings about slides, and every other piece swings with it. This
/// is the promise that nothing but the piece under the hand moves.
@Suite("A turned card holds still while one piece in it changes")
struct TurnedCardPivotTests {

    private func box(_ rect: CGRect, name: String) -> Layer {
        Layer(name: name, content: .annotation(AnnotationContent(shape: .rectangle)), frame: rect)
    }

    /// The document `turned-piece-walk` builds: a 400x200 bar and a 120x60
    /// label, grouped and turned 20 degrees.
    private func turnedCard(degrees: CGFloat = 20)
    -> (document: PhotonzDocument, card: UUID, bar: UUID, label: UUID) {
        let content = GroupContent(children: [
            box(CGRect(x: 300, y: 300, width: 400, height: 200), name: "Bar"),
            box(CGRect(x: 340, y: 340, width: 120, height: 60), name: "Label"),
        ])
        let card = Layer(name: "Card", content: .group(content), frame: .zero,
                         transform: LayerTransform(rotation: degrees * .pi / 180))
        let document = PhotonzDocument(canvasSize: CGSize(width: 1440, height: 1024),
                                       layers: [card])
        return (document, card.id, card.children[0].id, card.children[1].id)
    }

    /// Where a layer's four corners are DRAWN: its box on the upright canvas,
    /// swung by every card above it.
    private func drawnCorners(of id: UUID, in document: PhotonzDocument) -> [CGPoint] {
        guard let box = document.canvasBounds(of: id) else { return [] }
        let turn = document.inheritedTurn(of: id)
        return [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
                CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY)]
            .map { $0.applying(turn) }
    }

    private func expectSame(_ a: [CGPoint], _ b: [CGPoint], within tolerance: CGFloat = 0.5,
                            _ what: String, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(a.count == b.count, "\(what): corner counts differ",
                sourceLocation: sourceLocation)
        for (one, two) in zip(a, b) {
            #expect(abs(one.x - two.x) < tolerance && abs(one.y - two.y) < tolerance,
                    "\(what): \(one) moved to \(two)", sourceLocation: sourceLocation)
        }
    }

    /// The exact pull `turned-piece-walk` makes: the label's top left handle
    /// dragged to (320, 250) on screen. `TurnedPieceEditTests` works out that
    /// this lands the label's own box at (279.55, 320.61, 180.45x79.39).
    private let pulledLabelFrame = CGRect(x: 279.5462, y: 320.6072,
                                          width: 180.4538, height: 79.3928)

    // MARK: The bug this suite exists for

    @Test("Resizing one piece leaves every other piece in the card exactly where it was drawn")
    func theRestOfTheCardHoldsStill() throws {
        var (document, _, bar, label) = turnedCard()
        let before = drawnCorners(of: bar, in: document)
        #expect(!before.isEmpty)

        document.holdingTurnedPivots(above: label) { document in
            document.updateLayer(id: label) { $0.frame = self.pulledLabelFrame }
        }

        expectSame(before, drawnCorners(of: bar, in: document), "the bar nobody touched")
    }

    @Test("The corner opposite the handle stays put on a turned card")
    func theFarCornerHoldsStill() throws {
        var (document, _, _, label) = turnedCard()
        let before = drawnCorners(of: label, in: document)

        document.holdingTurnedPivots(above: label) { document in
            document.updateLayer(id: label) { $0.frame = self.pulledLabelFrame }
        }

        let after = drawnCorners(of: label, in: document)
        // Bottom right: the corner across from the top left handle that was
        // pulled. The walk reads (462, 386) before the pull and must read the
        // same after it.
        #expect(abs(after[2].x - before[2].x) < 0.5)
        #expect(abs(after[2].y - before[2].y) < 0.5)
        #expect(abs(after[2].x - 462.41) < 0.5)
        #expect(abs(after[2].y - 386.32) < 0.5)
        // ...and the piece really did grow, so the claim above is not about a
        // resize that never happened.
        #expect(try #require(document.layer(id: label)).frame.width > 120)
    }

    @Test("Moving one piece inside a turned card leaves the others where they were drawn")
    func aMoveHoldsTheRestOfTheCardToo() throws {
        var (document, _, bar, label) = turnedCard()
        let before = drawnCorners(of: bar, in: document)

        document.holdingTurnedPivots(above: label) { document in
            document.updateLayer(id: label) { $0.frame = $0.frame.offsetBy(dx: 60, dy: -25) }
        }

        expectSame(before, drawnCorners(of: bar, in: document), "the bar nobody touched")
    }

    @Test("The piece under the hand lands where the pointer put it")
    func thePieceItselfLandsWhereItWasAimed() throws {
        var (document, _, _, label) = turnedCard()
        // Where the pulled box would be DRAWN under the card's turn as it
        // stands before the change: that is the picture the pointer was
        // aiming at while it dragged.
        let turn = document.inheritedTurn(of: label)
        let aimed = [CGPoint(x: pulledLabelFrame.minX, y: pulledLabelFrame.minY),
                     CGPoint(x: pulledLabelFrame.maxX, y: pulledLabelFrame.minY),
                     CGPoint(x: pulledLabelFrame.maxX, y: pulledLabelFrame.maxY),
                     CGPoint(x: pulledLabelFrame.minX, y: pulledLabelFrame.maxY)]
            .map { $0.applying(turn) }

        document.holdingTurnedPivots(above: label) { document in
            document.updateLayer(id: label) { $0.frame = self.pulledLabelFrame }
        }

        expectSame(aimed, drawnCorners(of: label, in: document), "the piece that was pulled")
    }

    // MARK: The numbers `turned-piece-walk` claims on the real app
    //
    // The walk photographs the same thing; it needs an unlocked screen and
    // this does not, so the arithmetic is held here as well.

    @Test("The walk's numbers after the pull")
    func theWalksNumbersAfterThePull() throws {
        var (document, card, bar, label) = turnedCard()
        let barBefore = drawnCorners(of: bar, in: document)
        #expect(abs(barBefore[2].x - 653.74) < 0.1)
        #expect(abs(barBefore[2].y - 562.37) < 0.1)

        document.holdingTurnedPivots(above: label) { document in
            document.updateLayer(id: label) { $0.frame = self.pulledLabelFrame }
        }

        // The label's own box is still exactly where the drag aimed it, in
        // the CARD's space...
        let stored = try #require(document.layer(id: label)).frame
        #expect(abs(stored.minX - 279.55) < 0.01)
        #expect(abs(stored.minY - 320.61) < 0.01)
        // ...and on the upright canvas it reads a little different, because
        // the card's own anchor took the swing that would otherwise have gone
        // through every piece in the card. This is the number the walk claims.
        let canvas = try #require(document.canvasBounds(of: label))
        #expect(abs(canvas.minX - 280.17) < 0.01)
        #expect(abs(canvas.minY - 317.11) < 0.01)
        #expect(abs(try #require(document.layer(id: card)).frame.minX - 0.617) < 0.01)
        #expect(abs(try #require(document.layer(id: card)).frame.minY - -3.497) < 0.01)
        // The two on-screen corners the walk reads, both unmoved.
        let barAfter = drawnCorners(of: bar, in: document)
        #expect(abs(barAfter[2].x - 653.74) < 0.1)
        #expect(abs(barAfter[2].y - 562.37) < 0.1)
        let labelAfter = drawnCorners(of: label, in: document)
        #expect(abs(labelAfter[2].x - 462.41) < 0.1)
        #expect(abs(labelAfter[2].y - 386.32) < 0.1)
    }

    // MARK: Everywhere it must change nothing

    @Test("An upright card is not touched at all")
    func nothingHappensWithoutATurn() throws {
        var (document, card, bar, label) = turnedCard(degrees: 0)
        let anchor = try #require(document.layer(id: card)).frame
        let before = drawnCorners(of: bar, in: document)

        document.holdingTurnedPivots(above: label) { document in
            document.updateLayer(id: label) { $0.frame = self.pulledLabelFrame }
        }

        #expect(try #require(document.layer(id: card)).frame == anchor)
        expectSame(before, drawnCorners(of: bar, in: document), "the bar in an upright card")
    }

    @Test("A layer sitting loose on the canvas is not touched at all")
    func aLooseLayerIsUnchanged() {
        var document = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400),
                                       layers: [box(CGRect(x: 10, y: 10, width: 20, height: 20),
                                                    name: "Loose")])
        let id = document.layers[0].id
        let untouched = document
        document.holdingTurnedPivots(above: id) { document in
            document.updateLayer(id: id) { $0.frame = CGRect(x: 0, y: 0, width: 50, height: 50) }
        }
        var expected = untouched
        expected.updateLayer(id: id) { $0.frame = CGRect(x: 0, y: 0, width: 50, height: 50) }
        #expect(document.layers[0].frame == expected.layers[0].frame)
    }

    @Test("A screen holds its own box, so nothing on it ever slides the rest")
    func aScreenNeedsNoHolding() throws {
        var content = GroupContent(children: [
            box(CGRect(x: 10, y: 10, width: 40, height: 20), name: "Button"),
            box(CGRect(x: 10, y: 50, width: 40, height: 20), name: "Second"),
        ])
        content.isFrame = true
        let screen = Layer(name: "Screen", content: .group(content),
                           frame: CGRect(x: 100, y: 100, width: 300, height: 400),
                           transform: LayerTransform(rotation: .pi / 8))
        var document = PhotonzDocument(canvasSize: CGSize(width: 1000, height: 1000),
                                       layers: [screen])
        let button = screen.children[0].id, second = screen.children[1].id
        let anchor = screen.frame
        let before = drawnCorners(of: second, in: document)

        document.holdingTurnedPivots(above: button) { document in
            document.updateLayer(id: button) { $0.frame = CGRect(x: 0, y: 0, width: 90, height: 90) }
        }

        #expect(try #require(document.layer(id: screen.id)).frame == anchor)
        expectSame(before, drawnCorners(of: second, in: document), "the other thing on the screen")
    }

    @Test("Taking a piece out of a turned card leaves the rest of it where it was drawn")
    func aDeleteHoldsTheRestOfTheCard() throws {
        var (document, _, bar, label) = turnedCard()
        let before = drawnCorners(of: bar, in: document)

        document.holdingTurnedPivots(above: label) { document in
            document.removeLayer(id: label)
        }

        expectSame(before, drawnCorners(of: bar, in: document), "the bar that was left behind")
    }

    @Test("Emptying a turned card leaves its anchor alone")
    func anEmptiedCardIsNotThrownAcrossTheCanvas() throws {
        var (document, card, bar, label) = turnedCard()
        let anchor = try #require(document.layer(id: card)).frame

        document.holdingTurnedPivots(above: [bar, label]) { document in
            document.removeLayers(ids: [bar, label])
        }

        #expect(try #require(document.layer(id: card)).frame == anchor)
    }

    // MARK: A card within a card

    @Test("A piece inside a turned badge inside a turned card holds both still")
    func aTurnWithinATurnHoldsBothStill() throws {
        let badge = Layer(name: "Badge",
                          content: .group(GroupContent(children: [
                              box(CGRect(x: 0, y: 0, width: 20, height: 20), name: "Dot"),
                              box(CGRect(x: 30, y: 0, width: 20, height: 20), name: "Second dot"),
                          ])),
                          frame: CGRect(x: 360, y: 350, width: 0, height: 0),
                          transform: LayerTransform(rotation: .pi / 5))
        var content = GroupContent(children: [
            box(CGRect(x: 300, y: 300, width: 400, height: 200), name: "Bar"),
        ])
        content.children.append(badge)
        let card = Layer(name: "Card", content: .group(content), frame: .zero,
                         transform: LayerTransform(rotation: 20 * .pi / 180))
        var document = PhotonzDocument(canvasSize: CGSize(width: 1440, height: 1024),
                                       layers: [card])
        let bar = card.children[0].id
        let dot = badge.children[0].id
        let secondDot = badge.children[1].id
        let barBefore = drawnCorners(of: bar, in: document)
        let secondBefore = drawnCorners(of: secondDot, in: document)

        document.holdingTurnedPivots(above: dot) { document in
            document.updateLayer(id: dot) { $0.frame = CGRect(x: -15, y: -12, width: 35, height: 32) }
        }

        expectSame(barBefore, drawnCorners(of: bar, in: document), "the bar in the outer card")
        expectSame(secondBefore, drawnCorners(of: secondDot, in: document),
                   "the other dot in the badge")
    }
}
