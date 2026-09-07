import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// One step back from out of view.
///
/// A layer the box around it has cut off already says so in the layers list,
/// but every way back was several moves away: move it by hand, or turn off the
/// container's Clip contents, or type a new number into the inspector. This is
/// the one move — slide the layer back over the container's edge, the shortest
/// distance, so where somebody put it survives as far as it can.
@Suite("Bring into view")
struct BringIntoViewTests {

    private func leaf(_ name: String, _ frame: CGRect) -> Layer {
        Layer(name: name, content: .annotation(AnnotationContent(shape: .rectangle)), frame: frame)
    }

    private func card(_ name: String = "Card", clips: Bool, _ children: [Layer],
                      at origin: CGPoint = .zero, size: CGFloat = 100) -> Layer {
        var content = GroupContent(children: children, clipsContents: clips)
        content.layout = .free(width: size, height: size)
        return Layer(name: name, content: .group(content),
                     frame: CGRect(origin: origin, size: .zero))
    }

    private func screen(_ children: [Layer], name: String = "Screen",
                        clips: Bool = true) -> Layer {
        Layer(name: name, content: .group(GroupContent(children: children, isFrame: true,
                                                       clipsContents: clips)),
              frame: CGRect(x: 0, y: 0, width: 100, height: 100))
    }

    private func doc(_ layers: [Layer]) -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 400, height: 400), layers: layers)
    }

    private func id(_ document: PhotonzDocument, _ name: String) -> UUID {
        document.allLayers.first { $0.name == name }?.id ?? UUID()
    }

    private func box(_ document: PhotonzDocument, _ name: String) -> CGRect {
        document.layer(id: id(document, name))?.localBounds ?? .null
    }

    // MARK: - Whether there is a way back to offer

    @Test("A layer pushed right out of a clipping card has a way back")
    func aCutAwayChildCanComeBack() {
        let document = doc([card(clips: true, [leaf("Label", CGRect(x: 10, y: 200,
                                                                   width: 60, height: 20))])])
        #expect(document.canBringLayerIntoView(id: id(document, "Label")))
    }

    @Test("A layer still inside is offered nothing: there is nothing to fix")
    func aChildInsideHasNoWayBack() {
        let document = doc([card(clips: true, [leaf("Label", CGRect(x: 10, y: 10,
                                                                    width: 60, height: 20))])])
        #expect(!document.canBringLayerIntoView(id: id(document, "Label")))
    }

    @Test("A layer hanging half out is left alone, since it was never marked")
    func aHalfwayChildIsLeftAlone() {
        let document = doc([card(clips: true, [leaf("Label", CGRect(x: 60, y: 10,
                                                                    width: 80, height: 20))])])
        #expect(!document.canBringLayerIntoView(id: id(document, "Label")))
    }

    @Test("Nothing is offered while the container is not cutting anything off")
    func aCardThatDoesNotClipOffersNothing() {
        let document = doc([card(clips: false, [leaf("Label", CGRect(x: 10, y: 200,
                                                                     width: 60, height: 20))])])
        #expect(!document.canBringLayerIntoView(id: id(document, "Label")))
    }

    @Test("A layer out on the canvas, under no container at all, is offered nothing")
    func aLayerOnTheCanvasOffersNothing() {
        let document = doc([leaf("Label", CGRect(x: 900, y: 900, width: 60, height: 20))])
        #expect(!document.canBringLayerIntoView(id: id(document, "Label")))
    }

    // MARK: - Where it lands

    @Test("It comes back the shortest way: over the edge it left by, and no further")
    func itSlidesBackOverTheNearestEdge() {
        var document = doc([card(clips: true, [leaf("Label", CGRect(x: 10, y: 200,
                                                                    width: 60, height: 20))])])
        let moved = document.bringLayerIntoView(id: id(document, "Label"))
        #expect(moved)
        // Straight up to sit on the card's bottom edge. X never moved: it was
        // never the reason the layer was out of view.
        #expect(box(document, "Label") == CGRect(x: 10, y: 80, width: 60, height: 20))
    }

    @Test("A layer off the left comes back against the left edge")
    func itSlidesBackFromTheLeft() {
        var document = doc([card(clips: true, [leaf("Label", CGRect(x: -300, y: 30,
                                                                    width: 60, height: 20))])])
        let moved = document.bringLayerIntoView(id: id(document, "Label"))
        #expect(moved)
        #expect(box(document, "Label") == CGRect(x: 0, y: 30, width: 60, height: 20))
    }

    @Test("A layer off two edges at once comes back over both")
    func itSlidesBackOnBothAxes() {
        var document = doc([card(clips: true, [leaf("Label", CGRect(x: 400, y: -90,
                                                                     width: 60, height: 20))])])
        let moved = document.bringLayerIntoView(id: id(document, "Label"))
        #expect(moved)
        #expect(box(document, "Label") == CGRect(x: 40, y: 0, width: 60, height: 20))
    }

    @Test("A layer too big for the container lands on the container's corner")
    func anOversizeLayerLandsOnTheCorner() {
        var document = doc([card(clips: true, [leaf("Wide", CGRect(x: 500, y: 500,
                                                                    width: 300, height: 300))])])
        let moved = document.bringLayerIntoView(id: id(document, "Wide"))
        #expect(moved)
        #expect(box(document, "Wide").origin == CGPoint(x: 0, y: 0))
    }

    @Test("A screen brings its own layers back the same way")
    func aScreenBringsItsChildrenBack() {
        var document = doc([screen([leaf("Label", CGRect(x: 20, y: 300,
                                                          width: 60, height: 20))])])
        let moved = document.bringLayerIntoView(id: id(document, "Label"))
        #expect(moved)
        #expect(box(document, "Label") == CGRect(x: 20, y: 80, width: 60, height: 20))
    }

    @Test("Nothing else in the document moves")
    func onlyTheOneLayerMoves() {
        var document = doc([card(clips: true, [
            leaf("Gone", CGRect(x: 10, y: 200, width: 60, height: 20)),
            leaf("Here", CGRect(x: 5, y: 5, width: 30, height: 30))])])
        let moved = document.bringLayerIntoView(id: id(document, "Gone"))
        #expect(moved)
        #expect(box(document, "Here") == CGRect(x: 5, y: 5, width: 30, height: 30))
    }

    @Test("Once it is back it stops offering, because there is nothing left to fix")
    func theOfferGoesAwayOnceItIsBack() {
        var document = doc([card(clips: true, [leaf("Label", CGRect(x: 10, y: 200,
                                                                    width: 60, height: 20))])])
        let label = id(document, "Label")
        let came = document.bringLayerIntoView(id: label)
        #expect(came)
        #expect(!document.canBringLayerIntoView(id: label))
        let again = document.bringLayerIntoView(id: label)
        #expect(!again)
    }

    // MARK: - Nesting

    @Test("It lands inside every box in force, not only the nearest one")
    func itLandsInsideTheOuterBoxToo() {
        // An inner card sits astride the screen's right edge, so the half of
        // it past x = 100 is cut off by the screen even though the inner card
        // is happy to show it. A layer coming back must clear BOTH.
        let inner = card("Inner", clips: true,
                         [leaf("Label", CGRect(x: 10, y: 300, width: 20, height: 10))],
                         at: CGPoint(x: 60, y: 0), size: 80)
        var document = doc([screen([inner])])
        let moved = document.bringLayerIntoView(id: id(document, "Label"))
        #expect(moved)
        let landed = box(document, "Label")
        // In the inner card's space the screen's right edge is at x = 40.
        #expect(landed.maxX <= 40)
        #expect(landed.maxY <= 80)
    }

    @Test("A layer inside a group that is itself cut away comes back on its own")
    func aChildOfACutAwayGroupComesBackAlone() {
        let inner = card("Inner", clips: false,
                         [leaf("Label", CGRect(x: 0, y: 0, width: 10, height: 10))],
                         at: CGPoint(x: 0, y: 300), size: 40)
        var document = doc([screen([inner])])
        #expect(document.canBringLayerIntoView(id: id(document, "Label")))
        let moved = document.bringLayerIntoView(id: id(document, "Label"))
        #expect(moved)
        // Inner starts 300 down, so in Inner's space the screen's bottom edge
        // is at y = -200 and the layer has to travel up past it.
        #expect(box(document, "Label") == CGRect(x: 0, y: -210, width: 10, height: 10))
    }

    @Test("The container itself is offered a way back when its own parent cut it off")
    func aCutAwayContainerComesBackToo() {
        let inner = card("Inner", clips: true,
                         [leaf("Label", CGRect(x: 0, y: 0, width: 10, height: 10))],
                         at: CGPoint(x: 0, y: 300), size: 40)
        var document = doc([screen([inner])])
        let moved = document.bringLayerIntoView(id: id(document, "Inner"))
        #expect(moved)
        #expect(box(document, "Inner").origin == CGPoint(x: 0, y: 60))
    }

    // MARK: - Where the container decides, the layer is not the thing to move

    /// A stack 100 wide holding a row of items, clipped.
    private func stack(_ children: [Layer], gap: CGFloat = 0, size: CGFloat = 100) -> Layer {
        var content = GroupContent(children: children, clipsContents: true)
        content.layout = GroupLayout(kind: .stack, direction: .column, gap: gap,
                                     width: size, height: size)
        return Layer(name: "Stack", content: .group(content), frame: .zero)
    }

    @Test("A layer in a stack is offered nothing: the stack decides where it sits")
    func aLayerInAStackIsNotOffered() {
        let document = doc([stack([leaf("A", CGRect(x: 0, y: 0, width: 40, height: 40)),
                                   leaf("B", CGRect(x: 0, y: 200, width: 40, height: 40))])])
        #expect(!document.canBringLayerIntoView(id: id(document, "B")))
    }

    @Test("A locked layer is offered nothing: it is locked so that nothing moves it")
    func aLockedLayerIsNotOffered() {
        var lost = leaf("Label", CGRect(x: 10, y: 200, width: 60, height: 20))
        lost.isLocked = true
        let document = doc([card(clips: true, [lost])])
        #expect(!document.canBringLayerIntoView(id: id(document, "Label")))
    }

    @Test("The mark still says a stacked layer is out of view, it just offers no press")
    func aStackedLayerIsStillMarked() {
        let document = doc([stack([leaf("A", CGRect(x: 0, y: 0, width: 40, height: 40)),
                                   leaf("B", CGRect(x: 0, y: 200, width: 40, height: 40))])])
        let expanded = Set(document.allLayers.filter(\.isOpenableGroup).map(\.id))
        let rows = document.layerRows(expanded: expanded, selected: [])
        let row = rows.first { $0.name == "B" }
        #expect(row?.outOfView?.container == "Stack")
        #expect(row?.outOfView?.canReturn == false)
    }

    @Test("The row of a layer that can come back says so")
    func aFreeLayerSaysItCanComeBack() {
        let document = doc([card(clips: true, [leaf("Label", CGRect(x: 10, y: 200,
                                                                    width: 60, height: 20))])])
        let rows = document.layerRows(expanded: [id(document, "Card")], selected: [])
        #expect(rows.first { $0.name == "Label" }?.outOfView?.canReturn == true)
    }

    @Test("A shut group speaking for what it hides never claims a layer can come back")
    func aShutGroupClaimsNothing() {
        let document = doc([card(clips: true, [leaf("Gone", CGRect(x: 10, y: 200,
                                                                    width: 60, height: 20))])])
        let row = document.layerRows(expanded: [], selected: []).first { $0.name == "Card" }
        #expect(row?.outOfView?.hiddenInside == 1)
        #expect(row?.outOfView?.canReturn == false)
    }

    // MARK: - Every marked row can be pressed, and no other

    @Test("Every row wearing the mark has a way back, and no unmarked row does")
    func theOfferMatchesTheMark() {
        let inner = card("Inner", clips: true, [
            leaf("Gone", CGRect(x: 0, y: 200, width: 10, height: 10)),
            leaf("Here", CGRect(x: 0, y: 0, width: 10, height: 10))],
                         at: CGPoint(x: 0, y: 0), size: 40)
        let document = doc([screen([inner, leaf("Adrift", CGRect(x: 0, y: 400,
                                                                 width: 10, height: 10))])])
        let expanded = Set(document.allLayers.filter(\.isOpenableGroup).map(\.id))
        for row in document.layerRows(expanded: expanded, selected: []) {
            // A row marked only because a SHUT group is hiding something has
            // no layer of its own to move; every other mark is one press.
            let marked = row.outOfView?.canReturn == true
            #expect(document.canBringLayerIntoView(id: row.id) == marked,
                    "\(row.name) marked: \(marked)")
        }
    }
}
