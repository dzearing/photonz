import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A container that cuts off what does not fit says so in the layers list.
///
/// Drag a label a little too far out of a card that clips and it simply
/// vanishes: the canvas stops drawing it, the row goes on looking like every
/// other row, and undo is the only way back. Every row now carries the one
/// fact that was missing — whether the box it lives in is cutting it off, and
/// which box that is.
@Suite("Out of view")
struct OutOfViewMarkTests {

    private func leaf(_ name: String, _ frame: CGRect) -> Layer {
        Layer(name: name, content: .annotation(AnnotationContent(shape: .rectangle)), frame: frame)
    }

    /// A card 100×100 at the canvas origin, holding whatever it is given.
    private func card(_ name: String = "Card", clips: Bool, _ children: [Layer],
                      at origin: CGPoint = .zero, size: CGFloat = 100) -> Layer {
        var content = GroupContent(children: children, clipsContents: clips)
        content.layout = .free(width: size, height: size)
        return Layer(name: name, content: .group(content),
                     frame: CGRect(origin: origin, size: .zero))
    }

    /// A screen 100×100, which has cut off what leaves it since screens landed.
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

    private func rows(_ document: PhotonzDocument,
                      open names: [String] = [],
                      marks: Bool = true) -> [String: LayerRowDisplay] {
        let expanded = Set(names.map { id(document, $0) })
        let list = document.layerRows(expanded: expanded, selected: [], marksOutOfView: marks)
        return Dictionary(uniqueKeysWithValues: list.map { ($0.name, $0) })
    }

    // MARK: - The mark itself

    @Test("A layer pushed right out of a clipping card is marked, and the card is named")
    func aCutAwayChildIsMarked() {
        let document = doc([card(clips: true, [leaf("Label", CGRect(x: 0, y: 200,
                                                                   width: 60, height: 20))])])
        let row = rows(document, open: ["Card"])["Label"]
        #expect(row?.outOfView?.container == "Card")
        #expect(row?.outOfView?.hiddenInside == 0)
    }

    @Test("A layer still inside the card is not marked")
    func aChildInsideIsNotMarked() {
        let document = doc([card(clips: true, [leaf("Label", CGRect(x: 10, y: 10,
                                                                    width: 60, height: 20))])])
        #expect(rows(document, open: ["Card"])["Label"]?.outOfView == nil)
    }

    @Test("A layer hanging half out is not marked: some of it is still on screen")
    func aHalfwayChildIsNotMarked() {
        let document = doc([card(clips: true, [leaf("Label", CGRect(x: 60, y: 10,
                                                                    width: 80, height: 20))])])
        #expect(rows(document, open: ["Card"])["Label"]?.outOfView == nil)
    }

    @Test("Nothing is marked while the container is not cutting anything off")
    func aCardThatDoesNotClipMarksNothing() {
        let document = doc([card(clips: false, [leaf("Label", CGRect(x: 0, y: 200,
                                                                     width: 60, height: 20))])])
        #expect(rows(document, open: ["Card"])["Label"]?.outOfView == nil)
        #expect(rows(document, open: ["Card"])["Card"]?.outOfView == nil)
    }

    @Test("A screen cuts off the same way, and is named the same way")
    func aScreenMarksItsOwnChildren() {
        let document = doc([screen([leaf("Label", CGRect(x: 0, y: 300, width: 60, height: 20))])])
        #expect(rows(document, open: ["Screen"])["Label"]?.outOfView?.container == "Screen")

        let open = doc([screen([leaf("Label", CGRect(x: 0, y: 300, width: 60, height: 20))],
                               clips: false)])
        #expect(rows(open, open: ["Screen"])["Label"]?.outOfView == nil)
    }

    @Test("The container itself is never marked by its own box")
    func theContainerIsNotMarked() {
        let document = doc([card(clips: true, [leaf("Label", CGRect(x: 0, y: 200,
                                                                    width: 60, height: 20))])])
        #expect(rows(document, open: ["Card"])["Card"]?.outOfView == nil)
    }

    // MARK: - Nesting

    @Test("The container named is the nearest one, the one you would go and open")
    func theNearestContainerIsNamed() {
        let inner = card("Inner", clips: true,
                         [leaf("Label", CGRect(x: 0, y: 200, width: 10, height: 10))],
                         at: CGPoint(x: 0, y: 0), size: 40)
        let document = doc([screen([inner])])
        let row = rows(document, open: ["Screen", "Inner"])["Label"]
        #expect(row?.outOfView?.container == "Inner")
    }

    @Test("A layer inside a container that is itself cut away is marked too")
    func aChildOfACutAwayGroupIsMarked() {
        let inner = card("Inner", clips: false,
                         [leaf("Label", CGRect(x: 0, y: 0, width: 10, height: 10))],
                         at: CGPoint(x: 0, y: 300), size: 40)
        let document = doc([screen([inner])])
        let list = rows(document, open: ["Screen", "Inner"])
        #expect(list["Inner"]?.outOfView?.container == "Screen")
        #expect(list["Label"]?.outOfView?.container == "Screen")
    }

    // MARK: - A shut group speaks for what it is hiding

    @Test("A shut container says how many layers inside it are out of view")
    func aShutContainerCountsWhatItHides() {
        let document = doc([card(clips: true, [
            leaf("Gone", CGRect(x: 0, y: 200, width: 10, height: 10)),
            leaf("Also gone", CGRect(x: 0, y: 300, width: 10, height: 10)),
            leaf("Here", CGRect(x: 10, y: 10, width: 10, height: 10))])])
        let row = rows(document)["Card"]
        #expect(row?.outOfView?.hiddenInside == 2)
        #expect(row?.outOfView?.container == nil)
    }

    @Test("An open container says nothing: its own rows carry the marks")
    func anOpenContainerLeavesItToItsRows() {
        let document = doc([card(clips: true, [leaf("Gone", CGRect(x: 0, y: 200,
                                                                    width: 10, height: 10))])])
        #expect(rows(document, open: ["Card"])["Card"]?.outOfView == nil)
    }

    @Test("A shut container hiding nothing says nothing")
    func aShutContainerHidingNothingIsQuiet() {
        let document = doc([card(clips: true, [leaf("Here", CGRect(x: 10, y: 10,
                                                                    width: 10, height: 10))])])
        #expect(rows(document)["Card"]?.outOfView == nil)
    }

    @Test("A group already cut away counts once, not once per layer inside it")
    func aCutAwayGroupCountsOnce() {
        let inner = card("Inner", clips: false, [
            leaf("A", CGRect(x: 0, y: 0, width: 10, height: 10)),
            leaf("B", CGRect(x: 0, y: 20, width: 10, height: 10))],
                         at: CGPoint(x: 0, y: 300), size: 40)
        let document = doc([screen([inner])])
        #expect(rows(document)["Screen"]?.outOfView?.hiddenInside == 1)
    }

    // MARK: - The flag

    @Test("With the marks turned off nothing anywhere is marked")
    func theMarksCanBeTurnedOff() {
        let document = doc([card(clips: true, [leaf("Label", CGRect(x: 0, y: 200,
                                                                     width: 60, height: 20))])])
        #expect(rows(document, open: ["Card"], marks: false).values.allSatisfy { $0.outOfView == nil })
        #expect(rows(document, marks: false)["Card"]?.outOfView == nil)
    }

    // MARK: - You can still type it back into view

    @Test("A cut-away layer still shows a position you can type")
    func aCutAwayLayerKeepsATypeablePosition() throws {
        let document = doc([card(clips: true, [leaf("Label", CGRect(x: 0, y: 200,
                                                                    width: 60, height: 20))])])
        let label = document.layer(id: id(document, "Label"))
        let container = document.layer(id: id(document, "Card"))
        let editing = LayerGeometryEditing(layer: try #require(label), in: container)
        #expect(editing.canMove)
    }
}
