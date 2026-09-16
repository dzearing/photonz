import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A piece inside a turned card is editable on the slant: the canvas can put a
/// pointer back into the upright space the piece's own numbers are stated in,
/// and the things it lines itself up with are the ones stated in that same
/// space.
@Suite("A piece inside a turned card")
struct TurnedPieceEditTests {

    private func box(_ rect: CGRect, name: String = "Box") -> Layer {
        Layer(name: name, content: .annotation(AnnotationContent(shape: .rectangle)), frame: rect)
    }

    /// A card holding a label and a bar, turned a quarter clockwise about the
    /// middle of the box its contents make.
    private func card(rotation: CGFloat) -> Layer {
        let content = GroupContent(children: [
            box(CGRect(x: 100, y: 100, width: 40, height: 20), name: "Bar"),
            box(CGRect(x: 105, y: 105, width: 10, height: 10), name: "Label"),
        ])
        return Layer(name: "Card", content: .group(content),
                     frame: .zero, transform: LayerTransform(rotation: rotation))
    }

    // MARK: The door back into upright space

    @Test("A canvas point comes back as the place the piece's own numbers speak in")
    func aPointerLandsInTheCardsUprightSpace() {
        let turned = card(rotation: .pi / 2)
        let document = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400),
                                       layers: [turned])
        let label = turned.children[1].id
        // The label's own top left is (105, 105); the quarter turn about
        // (120, 110) puts it on screen at (125, 95).
        let onScreen = CGPoint(x: 105, y: 105).applying(document.inheritedTurn(of: label))
        #expect(abs(onScreen.x - 125) < 0.001)
        #expect(abs(onScreen.y - 95) < 0.001)
        // ...and the door takes it straight back.
        let back = document.uprightPoint(onScreen, in: label)
        #expect(abs(back.x - 105) < 0.001)
        #expect(abs(back.y - 105) < 0.001)
    }

    @Test("A layer sitting loose on the canvas takes the pointer unchanged")
    func nothingHappensWithoutATurn() {
        let upright = card(rotation: 0)
        let document = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400),
                                       layers: [upright])
        let label = upright.children[1].id
        let p = CGPoint(x: 37, y: 91)
        #expect(document.uprightPoint(p, in: label) == p)
        #expect(document.uprightPoint(p, in: upright.id) == p)
        // An id the document has never heard of is not a reason to move a point.
        #expect(document.uprightPoint(p, in: UUID()) == p)
    }

    @Test("A pointer that travels along the screen travels along the card")
    func adragFollowsThePointer() {
        let turned = card(rotation: .pi / 2)
        let document = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400),
                                       layers: [turned])
        let label = turned.children[1].id
        let from = document.uprightPoint(CGPoint(x: 200, y: 200), in: label)
        let to = document.uprightPoint(CGPoint(x: 210, y: 200), in: label)
        // Ten points to the RIGHT on screen is ten points UP the card, once the
        // card has been turned a quarter clockwise. That is what stops a drag
        // going off at an angle to the hand holding it.
        #expect(abs(to.x - from.x) < 0.001)
        #expect(abs((to.y - from.y) - -10) < 0.001)
    }

    // MARK: What it lines up with

    @Test("A piece inside a turned card lines up with the other pieces in that card")
    func peersComeFromInsideTheCard() {
        let turned = card(rotation: .pi / 2)
        let outside = box(CGRect(x: 300, y: 300, width: 50, height: 50), name: "Outside")
        let document = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400),
                                       layers: [turned, outside])
        let label = turned.children[1].id
        let peers = document.snapPeers(excluding: label)
        // The bar beside it, stated where the label's own numbers are stated.
        #expect(peers == [CGRect(x: 100, y: 100, width: 40, height: 20)])
        // And nothing from the upright canvas: that box is measured on a
        // different slant, so lining up with it would land the label somewhere
        // neither box agrees on.
        #expect(!peers.contains(outside.frame))
    }

    @Test("A piece in an upright card still lines up with the whole picture")
    func anUprightDocumentIsUnchanged() {
        let plain = card(rotation: 0)
        let outside = box(CGRect(x: 300, y: 300, width: 50, height: 50), name: "Outside")
        let document = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400),
                                       layers: [plain, outside])
        let label = plain.children[1].id
        let peers = document.snapPeers(excluding: label)
        #expect(peers.contains(outside.frame))
        #expect(peers.contains(CGRect(x: 100, y: 100, width: 40, height: 20)))
    }

    // MARK: The gestures themselves
    //
    // The canvas composes these four core pieces for every drag on the
    // selected layer: `uprightPoint` to take the card's swing off the pointer,
    // `handleSpacePoint` to take the layer's own turn off it, `Handles` to
    // work the frame out, and `Snapping` for the magnets. What follows drives
    // that composition the way `CanvasPointerDrags` drives it, so the
    // behaviour a person gets is held to a number rather than to a picture.
    // (A scripted walk photographs the same thing; it cannot run at all while
    // the Mac's screen is locked, and this can.)

    /// A card turned 20 degrees holding a bar and a small label.
    private func turnedCardDocument() -> (document: PhotonzDocument, label: UUID, card: Layer) {
        let degrees: CGFloat = 20
        let content = GroupContent(children: [
            box(CGRect(x: 300, y: 300, width: 400, height: 200), name: "Bar"),
            box(CGRect(x: 340, y: 340, width: 120, height: 60), name: "Label"),
        ])
        let card = Layer(name: "Card", content: .group(content), frame: .zero,
                         transform: LayerTransform(rotation: degrees * .pi / 180))
        let document = PhotonzDocument(canvasSize: CGSize(width: 1440, height: 1024),
                                       layers: [card])
        return (document, card.children[1].id, card)
    }

    /// Where a box's middle sits ON SCREEN: the box placed on the canvas, then
    /// swung by the card above it.
    private func screenCentre(_ box: CGRect, in document: PhotonzDocument,
                              of id: UUID) -> CGPoint {
        CGPoint(x: box.midX, y: box.midY).applying(document.inheritedTurn(of: id))
    }

    @Test("Dragging a piece inside a turned card moves it with the pointer, not at an angle to it")
    func aDragTravelsAsFarAsTheHandDoes() throws {
        let (document, label, _) = turnedCardDocument()
        let box = try #require(document.canvasBounds(of: label))
        let before = screenCentre(box, in: document, of: label)

        // The press, then the pointer 200 points to the RIGHT on screen — the
        // way the canvas reads them: through the door that takes the card's
        // swing off (`CanvasPointerDrags.mouseDown`/`mouseDragged`).
        let press = document.uprightPoint(before, in: label)
        let grab = CGPoint(x: press.x - box.minX, y: press.y - box.minY)
        let moved = document.uprightPoint(CGPoint(x: before.x + 200, y: before.y), in: label)
        let landed = CGRect(origin: CGPoint(x: moved.x - grab.x, y: moved.y - grab.y),
                            size: box.size)

        let after = screenCentre(landed, in: document, of: label)
        #expect(abs(after.x - (before.x + 200)) < 0.001)
        #expect(abs(after.y - before.y) < 0.001)
        // ...and it really did move on a slant in its own numbers, which is
        // what makes the screen travel straight.
        #expect(abs(landed.minY - box.minY) > 10)
        // The exact landing, which is the number turned-piece-walk claims on
        // the real app: the walk cannot run on a locked screen and this can.
        #expect(abs(landed.minX - 527.94) < 0.01)
        #expect(abs(landed.minY - 271.60) < 0.01)
    }

    @Test("Resizing a piece inside a turned card keeps the opposite corner where it was on screen")
    func aResizeHoldsTheFarCorner() throws {
        let (document, label, _) = turnedCardDocument()
        var placed = try #require(document.canvasLayer(id: label))
        let start = placed.frame
        let turn = document.inheritedTurn(of: label)
        let farBefore = placed.transformedCorners[2].applying(turn)

        // The top left handle, taken hold of where it DRAWS and pulled out and
        // up the screen. The canvas reads the pointer through both doors.
        // The very point turned-piece-walk drags to, so the two agree.
        let pulled = CGPoint(x: 320, y: 250)
        let local = CanvasPointer.handleSpacePoint(document.uprightPoint(pulled, in: label),
                                                   layer: placed)
        var frame = Handles.resize(start, dragging: .topLeft, to: local, preserveAspect: false)
        frame = Handles.anchoredFrame(start: start, proposed: frame, handle: .topLeft,
                                      transform: placed.transform)

        placed.frame = frame
        let farAfter = placed.transformedCorners[2].applying(turn)
        #expect(abs(farAfter.x - farBefore.x) < 0.001)
        #expect(abs(farAfter.y - farBefore.y) < 0.001)
        // The corner under the hand went where the hand went.
        let grabbed = placed.transformedCorners[0].applying(turn)
        #expect(abs(grabbed.x - pulled.x) < 0.001)
        #expect(abs(grabbed.y - pulled.y) < 0.001)
        // And it really did get bigger, so the claim above is not about a
        // resize that never happened.
        #expect(frame.width > start.width)
        #expect(frame.height > start.height)
        // The exact numbers turned-piece-walk claims on the real app.
        #expect(abs(frame.minX - 279.55) < 0.01)
        #expect(abs(frame.minY - 320.61) < 0.01)
        #expect(abs(frame.width - 180.45) < 0.01)
        #expect(abs(frame.height - 79.39) < 0.01)
        #expect(abs(farAfter.x - 462.41) < 0.01)
        #expect(abs(farAfter.y - 386.32) < 0.01)
    }

    @Test("The magnets catch a piece on the card's own edge, measured along the card")
    func theMagnetsReadTheTurnedPositions() throws {
        let (document, label, _) = turnedCardDocument()
        let box = try #require(document.canvasBounds(of: label))
        let peers = document.snapPeers(excluding: label)
        // Nudged towards the bar's left edge, in the card's own space: 38
        // points left of where it sits, which leaves it 2 points short.
        let proposed = CGPoint(x: box.minX - 38, y: box.minY)
        let result = Snapping.snapFrameOrigin(proposed, size: box.size, canvas: .zero,
                                              peers: peers, zoom: 1)
        #expect(abs(result.origin.x - 300) < 0.001)
        #expect(result.guideX == 300)
        // The bar's bottom edge is 100 points away down the card, so nothing
        // pulls that way and the nudge keeps the height it had.
        #expect(abs(result.origin.y - box.minY) < 0.001)
    }

    @Test("The exact nudge turned-piece-walk makes lands on the card's own left edge")
    func theWalksOwnNudgeLandsWhereItClaims() throws {
        let (document, label, _) = turnedCardDocument()
        let box = try #require(document.canvasBounds(of: label))
        // The walk presses at (416, 338) and lets go at (381, 325), both on
        // screen, with no key held.
        let press = document.uprightPoint(CGPoint(x: 416, y: 338), in: label)
        let grab = CGPoint(x: press.x - box.minX, y: press.y - box.minY)
        let release = document.uprightPoint(CGPoint(x: 381, y: 325), in: label)
        let proposed = CGPoint(x: release.x - grab.x, y: release.y - grab.y)
        // A piece on a slant is offered its card's pieces and none of the
        // upright lines: no canvas edges, no grid, no rulers.
        let result = Snapping.snapFrameOrigin(proposed, size: box.size, canvas: .zero,
                                              peers: document.snapPeers(excluding: label),
                                              zoom: 1)
        #expect(abs(result.origin.x - 300) < 0.01)
        // Nothing pulls down the card: the bar's own top and bottom edges are
        // 40 and 100 points away, so the nudge keeps the height it had.
        #expect(abs(result.origin.y - 339.75) < 0.01)
    }

    @Test("A turned card inside the card is a slant of its own, so it is not walked into")
    func aTurnWithinATurnKeepsItsOwnSpace() {
        var outer = card(rotation: .pi / 2)
        let badge = Layer(name: "Badge",
                          content: .group(GroupContent(children: [
                              box(CGRect(x: 0, y: 0, width: 8, height: 8), name: "Dot"),
                          ])),
                          frame: CGRect(x: 120, y: 100, width: 0, height: 0),
                          transform: LayerTransform(rotation: .pi / 4))
        outer.children.append(badge)
        let document = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400),
                                       layers: [outer])
        let label = outer.children[1].id
        let peers = document.snapPeers(excluding: label)
        // The badge's own box is a real edge in the card's space, so it stays.
        #expect(peers.contains(CGRect(x: 120, y: 100, width: 8, height: 8)))
        // The dot inside it is on a second slant, so it does not.
        #expect(peers.count == 2)
    }
}
