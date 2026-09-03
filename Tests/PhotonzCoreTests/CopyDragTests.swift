import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Holding Option while you drag a layer leaves the original where it was and
/// carries a copy away. That is one mutation, not two: the copy is made and
/// placed together, so one Command Z puts the picture back exactly as it was.
@Suite("Option-drag leaves a copy behind")
struct CopyDragTests {

    private func leaf(_ name: String, _ frame: CGRect, locked: Bool = false) -> Layer {
        var layer = Layer(name: name, content: .image(ImageRef(pixelSize: frame.size)),
                          frame: frame)
        layer.isLocked = locked
        return layer
    }

    private func id(_ doc: PhotonzDocument, _ name: String) -> UUID {
        doc.allLayers.first { $0.name == name }?.id ?? UUID()
    }

    /// Three loose boxes on a 400×400 canvas.
    private func makeFlat() -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 400, height: 400),
                        layers: [leaf("A", CGRect(x: 10, y: 10, width: 100, height: 50)),
                                 leaf("B", CGRect(x: 200, y: 30, width: 60, height: 60)),
                                 leaf("C", CGRect(x: 40, y: 300, width: 80, height: 20))])
    }

    // MARK: One layer

    @Test func theOriginalStaysAndTheCopyLandsWhereItWasDropped() {
        var doc = makeFlat()
        let a = id(doc, "A")
        let made = doc.duplicateLayers(movingCopiesTo: [a: CGPoint(x: 150, y: 220)])
        #expect(made.count == 1)
        #expect(doc.layer(id: a)?.frame == CGRect(x: 10, y: 10, width: 100, height: 50))
        #expect(doc.canvasBounds(of: made[0]) == CGRect(x: 150, y: 220, width: 100, height: 50))
        #expect(doc.layers.count == 4)
    }

    @Test func theCopySitsDirectlyAboveWhatItCameFrom() {
        var doc = makeFlat()
        let a = id(doc, "A")
        let made = doc.duplicateLayers(movingCopiesTo: [a: CGPoint(x: 150, y: 220)])
        #expect(doc.layers.map(\.id) == [a, made[0], id(doc, "B"), id(doc, "C")])
    }

    @Test func theCopyIsNamedTheWayDuplicateNamesIt() {
        var doc = makeFlat()
        let made = doc.duplicateLayers(movingCopiesTo: [id(doc, "A"): CGPoint(x: 150, y: 220)])
        #expect(doc.layer(id: made[0])?.name == "A copy")
    }

    @Test func nothingHappensWithNothingToCopy() {
        var doc = makeFlat()
        let before = doc
        #expect(doc.duplicateLayers(movingCopiesTo: [:]).isEmpty)
        #expect(doc == before)
    }

    @Test func anIdThatIsNotThereIsIgnored() {
        var doc = makeFlat()
        let before = doc
        #expect(doc.duplicateLayers(movingCopiesTo: [UUID(): .zero]).isEmpty)
        #expect(doc == before)
    }

    // MARK: A whole selection

    @Test func everyLayerPickedIsCopiedAndEveryOriginalStaysPut() {
        var doc = makeFlat()
        let a = id(doc, "A"), b = id(doc, "B")
        let made = doc.duplicateLayers(movingCopiesTo: [a: CGPoint(x: 10, y: 110),
                                                        b: CGPoint(x: 200, y: 130)])
        #expect(made.count == 2)
        #expect(doc.layer(id: a)?.frame == CGRect(x: 10, y: 10, width: 100, height: 50))
        #expect(doc.layer(id: b)?.frame == CGRect(x: 200, y: 30, width: 60, height: 60))
        let boxes = Set(made.compactMap { doc.canvasBounds(of: $0) })
        #expect(boxes == [CGRect(x: 10, y: 110, width: 100, height: 50),
                          CGRect(x: 200, y: 130, width: 60, height: 60)])
    }

    @Test func theCopiesKeepTheStackingOrderTheirOriginalsHad() {
        var doc = makeFlat()
        let a = id(doc, "A"), b = id(doc, "B"), c = id(doc, "C")
        let made = doc.duplicateLayers(movingCopiesTo: [a: CGPoint(x: 0, y: 0),
                                                        c: CGPoint(x: 0, y: 100)])
        let order = doc.layers.map(\.id)
        #expect(order.count == 5)
        #expect(order[0] == a)
        #expect(made.contains(order[1]))
        #expect(order[2] == b)
        #expect(order[3] == c)
        #expect(made.contains(order[4]))
    }

    // MARK: Inside a group

    @Test func aCopyMadeInsideAGroupStaysInThatGroup() {
        var doc = PhotonzDocument(
            canvasSize: CGSize(width: 400, height: 400),
            layers: [leaf("loose", CGRect(x: 0, y: 0, width: 10, height: 10)),
                     Layer(name: "Card",
                           content: .group(GroupContent(children: [
                               leaf("label", CGRect(x: 5, y: 5, width: 40, height: 20))])),
                           frame: CGRect(x: 100, y: 100, width: 0, height: 0))])
        let label = id(doc, "label")
        let card = id(doc, "Card")
        // The label sits at canvas (105, 105); the copy is dropped 60pt to its right.
        let made = doc.duplicateLayers(movingCopiesTo: [label: CGPoint(x: 165, y: 105)])
        #expect(made.count == 1)
        #expect(doc.parentID(of: made[0]) == card)
        #expect(doc.canvasBounds(of: made[0]) == CGRect(x: 165, y: 105, width: 40, height: 20))
        #expect(doc.canvasBounds(of: label) == CGRect(x: 105, y: 105, width: 40, height: 20))
    }

    @Test func copyingAWholeGroupCarriesEverythingInsideIt() {
        var doc = PhotonzDocument(
            canvasSize: CGSize(width: 400, height: 400),
            layers: [Layer(name: "Card",
                           content: .group(GroupContent(children: [
                               leaf("label", CGRect(x: 5, y: 5, width: 40, height: 20))])),
                           frame: CGRect(x: 100, y: 100, width: 0, height: 0))])
        let card = id(doc, "Card")
        // The group's box on canvas is its child's: (105, 105) 40x20.
        let made = doc.duplicateLayers(movingCopiesTo: [card: CGPoint(x: 200, y: 200)])
        #expect(made.count == 1)
        let copy = doc.layer(id: made[0])
        #expect(copy?.children.count == 1)
        #expect(copy?.children.first?.name == "label")
        #expect(copy?.children.first?.id != id(doc, "label"))
        #expect(doc.canvasBounds(of: made[0]) == CGRect(x: 200, y: 200, width: 40, height: 20))
        // The original group and its child did not move.
        #expect(doc.canvasBounds(of: card) == CGRect(x: 105, y: 105, width: 40, height: 20))
    }

    @Test func aGroupAndSomethingInsideItCopyOnceNotTwice() {
        var doc = PhotonzDocument(
            canvasSize: CGSize(width: 400, height: 400),
            layers: [Layer(name: "Card",
                           content: .group(GroupContent(children: [
                               leaf("label", CGRect(x: 5, y: 5, width: 40, height: 20))])),
                           frame: CGRect(x: 100, y: 100, width: 0, height: 0))])
        let card = id(doc, "Card")
        let label = id(doc, "label")
        let made = doc.duplicateLayers(movingCopiesTo: [card: CGPoint(x: 200, y: 200),
                                                        label: CGPoint(x: 0, y: 0)])
        // The group takes its child with it: the child is not copied a second
        // time and left loose inside the original.
        #expect(made.count == 1)
        #expect(doc.layer(id: card)?.children.count == 1)
    }

    // MARK: One undo step

    @Test func theCopyAndItsMoveAreOneUndoStep() {
        let doc = makeFlat()
        var history = History(document: doc)
        let a = id(doc, "A")
        history.perform { $0.duplicateLayers(movingCopiesTo: [a: CGPoint(x: 150, y: 220)]) }
        #expect(history.current.layers.count == 4)
        history.undo()
        #expect(history.current == doc)
        #expect(!history.canUndo)
    }

    @Test func aWholeSelectionCopiedIsStillOneUndoStep() {
        let doc = makeFlat()
        var history = History(document: doc)
        let a = id(doc, "A"), b = id(doc, "B")
        history.perform { $0.duplicateLayers(movingCopiesTo: [a: CGPoint(x: 10, y: 110),
                                                              b: CGPoint(x: 200, y: 130)]) }
        #expect(history.current.layers.count == 5)
        history.undo()
        #expect(history.current == doc)
        #expect(!history.canUndo)
    }

    // MARK: A copy of a component still follows its original

    @Test func aCopyOfAnInstanceStillFollowsTheSameOriginal() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400),
                                  layers: [leaf("button", CGRect(x: 0, y: 0, width: 80, height: 30))])
        let group = doc.groupLayers(ids: [id(doc, "button")], name: "Button")
        #expect(group != nil)
        guard let group, let componentID = doc.makeComponent(id: group.id) else { return }
        let placed = doc.insertComponentInstance(of: componentID, at: CGPoint(x: 10, y: 200))
        #expect(placed != nil)
        guard let placed else { return }
        let made = doc.duplicateLayers(movingCopiesTo: [placed: CGPoint(x: 150, y: 200)])
        #expect(made.count == 1)
        #expect(doc.layer(id: made[0])?.instanceOf == componentID)
        #expect(doc.layer(id: made[0])?.isComponentInstance == true)
        #expect(doc.canvasBounds(of: made[0])?.origin == CGPoint(x: 150, y: 200))
        // ...and it did not quietly become a second original.
        #expect(doc.mainComponents.count == 1)
    }
}
