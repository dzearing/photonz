import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A container too small for what is inside it, made to fit.
///
/// Inside a stack or a grid a layer has no position of its own, so sliding it
/// back over the edge is not the fix and the row never offered it: the mark
/// said the container was too small and left somebody to go and find its
/// height. This is that fix, on the row that already names the problem — the
/// container grows to the size its contents need, and nothing else changes.
@Suite("A container made to fit")
struct ContainerFitTests {

    private func leaf(_ name: String, _ size: CGFloat = 40) -> Layer {
        Layer(name: name, content: .annotation(AnnotationContent(shape: .rectangle)),
              frame: CGRect(x: 0, y: 0, width: size, height: size))
    }

    private func container(_ layout: GroupLayout, name: String = "Card",
                           clips: Bool = true, _ children: [Layer]) -> Layer {
        var content = GroupContent(children: children, clipsContents: clips)
        content.layout = layout
        return Layer(name: name, content: .group(content), frame: .zero)
    }

    /// A column of items, laid out for real, so every box a test reads is the
    /// box the flow put there.
    private func doc(_ layers: [Layer]) -> PhotonzDocument {
        var document = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400), layers: layers)
        document.reflowLayouts()
        return document
    }

    private func id(_ document: PhotonzDocument, _ name: String) -> UUID {
        document.allLayers.first { $0.name == name }?.id ?? UUID()
    }

    private func layout(_ document: PhotonzDocument, _ name: String) -> GroupLayout? {
        document.layer(id: id(document, name))?.group?.layout
    }

    /// A column stack 100 wide and `height` tall, holding three 40-point items
    /// with no gap: the third one starts at 80 and is right outside a box 80
    /// tall.
    private func shortColumn(height: CGFloat? = 80, maxHeight: CGFloat? = nil,
                             clips: Bool = true) -> Layer {
        container(GroupLayout(kind: .stack, direction: .column, gap: 0,
                              width: 100, height: height, maxHeight: maxHeight),
                  clips: clips,
                  [leaf("A"), leaf("B"), leaf("C")])
    }

    // MARK: - Whether there is a fix to offer

    @Test("A column that cut off its last row offers to grow tall enough for it")
    func aShortColumnOffersToGrow() {
        let document = doc([shortColumn()])
        let fit = document.containerFit(bringingIntoView: id(document, "C"))
        #expect(fit?.name == "Card")
        #expect(fit?.height == 120)
        #expect(fit?.width == nil)
    }

    @Test("The offer says what it will change before it is taken")
    func theOfferNamesTheNumber() {
        let document = doc([shortColumn()])
        #expect(document.containerFit(bringingIntoView: id(document, "C"))?.change == "taller (120)")
    }

    @Test("A container big enough for everything in it is offered nothing")
    func aContainerThatFitsIsLeftAlone() {
        let document = doc([shortColumn(height: 200)])
        for name in ["A", "B", "C"] {
            #expect(document.containerFit(bringingIntoView: id(document, name)) == nil)
        }
    }

    @Test("A container that shows what does not fit is offered nothing: nothing is hidden")
    func aContainerThatDoesNotClipIsLeftAlone() {
        let document = doc([shortColumn(clips: false)])
        #expect(document.containerFit(bringingIntoView: id(document, "C")) == nil)
    }

    @Test("A row cut off across offers the width it needs")
    func aNarrowRowOffersAWidth() {
        let document = doc([container(GroupLayout(kind: .stack, direction: .row, gap: 0,
                                                  width: 80, height: 40),
                                      [leaf("A"), leaf("B"), leaf("C")])])
        let fit = document.containerFit(bringingIntoView: id(document, "C"))
        #expect(fit?.width == 120)
        #expect(fit?.height == nil)
        #expect(fit?.change == "wider (120)")
    }

    @Test("A card whose words wrap to its width is made taller, never wider")
    func aWrappingCardOnlyGrowsDown() {
        let text = TextContent(string: "Save all the changes now", fontSize: 10)
        let label = Layer(name: "Words", content: .text(text),
                          frame: CGRect(origin: .zero, size: TextMeasurement.size(of: text)))
        var document = doc([container(GroupLayout(kind: .stack, direction: .column, gap: 0,
                                                  width: 100, height: 20),
                                      [label, leaf("Tail", 20)])])
        let fit = document.containerFit(bringingIntoView: id(document, "Tail"))
        // The words are wrapping to 100. Freeing the width would put them back
        // on one line and the card would come out half as wide again as it was
        // asked to be, on the axis nothing was ever cut off.
        #expect(fit?.width == nil)
        #expect((fit?.height ?? 0) > 20)
        let made = document.makeRoomForLayer(id: id(document, "Tail"))
        #expect(made)
        #expect(layout(document, "Card")?.width == 100)
    }

    @Test("A container cut off both ways says both numbers")
    func bothSidesReadAsOne() {
        let fit = ContainerFit(container: UUID(), name: "Card", width: 80, height: 120,
                               fitted: .free())
        #expect(fit.change == "bigger (80 × 120)")
    }

    @Test("A ceiling holding the box down is the number that moves")
    func aCeilingIsTheNumberThatMoves() {
        var document = doc([shortColumn(height: nil, maxHeight: 80)])
        let fit = document.containerFit(bringingIntoView: id(document, "C"))
        #expect(fit?.height == 120)
        let made = document.makeRoomForLayer(id: id(document, "C"))
        #expect(made)
        // The box goes on being the size of its contents: what was too low was
        // the ceiling, so the ceiling is what moved.
        #expect(layout(document, "Card")?.height == nil)
        #expect(layout(document, "Card")?.maxHeight == 120)
    }

    @Test("A layer that is still in view is offered nothing")
    func aLayerInViewIsOfferedNothing() {
        let document = doc([shortColumn()])
        #expect(document.containerFit(bringingIntoView: id(document, "A")) == nil)
    }

    @Test("A layer that can simply move back is left to move: its container is big enough")
    func aLayerWithAMoveOfItsOwnIsOfferedNothing() {
        var lost = leaf("Lost")
        lost.frame = CGRect(x: 10, y: 300, width: 40, height: 40)
        let free = container(.free(width: 100, height: 100), [lost])
        let document = doc([free])
        #expect(document.canBringLayerIntoView(id: id(document, "Lost")))
        #expect(document.containerFit(bringingIntoView: id(document, "Lost")) == nil)
    }

    @Test("The contents of a copy are not offered: its size belongs to its original")
    func aCopyIsOfferedNothing() {
        var document = doc([shortColumn()])
        let card = id(document, "Card")
        guard let component = document.makeComponent(id: card),
              let copy = document.insertComponentInstance(of: component,
                                                          at: CGPoint(x: 300, y: 300)) else {
            Issue.record("the card did not become a component")
            return
        }
        document.syncComponentInstances()
        document.reflowLayouts()
        guard let inside = document.layer(id: copy)?.children.last else {
            Issue.record("the copy has no contents")
            return
        }
        #expect(document.layer(id: copy)?.isComponentInstance == true)
        #expect(document.containerFit(bringingIntoView: inside.id) == nil)
    }

    @Test("A locked container is not resized behind the lock")
    func aLockedContainerIsOfferedNothing() {
        var card = shortColumn()
        card.isLocked = true
        let document = doc([card])
        #expect(document.containerFit(bringingIntoView: id(document, "C")) == nil)
    }

    // MARK: - What taking it changes

    @Test("Taking it brings the layer back into view")
    func takingItBringsTheLayerBack() {
        var document = doc([shortColumn()])
        let made = document.makeRoomForLayer(id: id(document, "C"))
        #expect(made)
        document.reflowLayouts()
        let rows = document.layerRows(expanded: [id(document, "Card")], selected: [])
        #expect(rows.first { $0.name == "C" }?.outOfView == nil)
    }

    @Test("It changes the container's size and nothing else")
    func itChangesTheSizeAndNothingElse() {
        var document = doc([shortColumn()])
        let before = layout(document, "Card")
        let corner = document.layer(id: id(document, "Card"))?.frame.origin
        let boxes = ["A", "B", "C"].map { document.layer(id: id(document, $0))?.frame }
        let made = document.makeRoomForLayer(id: id(document, "C"))
        #expect(made)
        document.reflowLayouts()
        var expected = before
        expected?.height = 120
        #expect(layout(document, "Card") == expected)
        #expect(document.layer(id: id(document, "Card"))?.frame.origin == corner)
        #expect(["A", "B", "C"].map { document.layer(id: id(document, $0))?.frame } == boxes)
    }

    @Test("One undo puts the size back")
    func oneUndoPutsTheSizeBack() {
        var history = History(document: doc([shortColumn()]))
        let lost = id(history.current, "C")
        history.perform { $0.makeRoomForLayer(id: lost) }
        #expect(layout(history.current, "Card")?.height == 120)
        history.undo()
        #expect(layout(history.current, "Card")?.height == 80)
    }

    @Test("Nothing is recorded where there was nothing to fix")
    func nothingIsRecordedWhereItAlreadyFits() {
        var document = doc([shortColumn(height: 200)])
        let made = document.makeRoomForLayer(id: id(document, "C"))
        #expect(!made)
    }

    // MARK: - What the row says

    @Test("The row of a stacked layer offers the container's size, not a move")
    func theRowOffersTheSize() {
        let document = doc([shortColumn()])
        let rows = document.layerRows(expanded: [id(document, "Card")], selected: [])
        let row = rows.first { $0.name == "C" }?.outOfView
        #expect(row?.container == "Card")
        #expect(row?.canReturn == false)
        #expect(row?.growsContainer == "taller (120)")
    }

    @Test("A row that can move back on its own says nothing about the container's size")
    func aRowThatCanMoveSaysNothingAboutTheSize() {
        var lost = leaf("Lost")
        lost.frame = CGRect(x: 10, y: 300, width: 40, height: 40)
        let document = doc([container(.free(width: 100, height: 100), [lost])])
        let rows = document.layerRows(expanded: [id(document, "Card")], selected: [])
        let row = rows.first { $0.name == "Lost" }?.outOfView
        #expect(row?.canReturn == true)
        #expect(row?.growsContainer == nil)
    }

    @Test("Every row that offers a size is a row that really can be made to fit")
    func theOfferMatchesTheMark() {
        let document = doc([shortColumn()])
        let expanded = Set(document.allLayers.filter(\.isOpenableGroup).map(\.id))
        for row in document.layerRows(expanded: expanded, selected: []) {
            #expect((row.outOfView?.growsContainer != nil)
                    == (document.containerFit(bringingIntoView: row.id) != nil),
                    "\(row.name)")
        }
    }
}
