import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Grouping from the interface: what ⌘G and ⇧⌘G are allowed to do, and how a
/// click on the canvas resolves once layers can nest. The rule the whole thing
/// hangs on: a click picks the OUTERMOST thing you are not already inside, so a
/// group is one object until you deliberately go into it
/// (`docs/design/ui-building.md`, "The two canvas gestures").
@Suite("Group and ungroup what you selected")
struct LayerGroupingTests {

    private func leaf(_ name: String, _ frame: CGRect) -> Layer {
        // An image leaf hits anywhere inside its frame, which keeps the
        // hit-test cases about the tree rather than about stroke slop.
        Layer(name: name, content: .image(ImageRef(pixelSize: frame.size)), frame: frame)
    }

    private func id(_ doc: PhotonzDocument, _ name: String) -> UUID {
        doc.allLayers.first { $0.name == name }?.id ?? UUID()
    }

    /// Canvas 400×400, bottom-up:
    /// - "Back", a loose 400×400 layer (unlocked, so it takes clicks).
    /// - "Card", a group at (100, 100) holding "Box" at local (0, 0) 120×80
    ///   and, inside it, a nested group "Badge" at local (10, 10) holding
    ///   "Dot" at local (0, 0) 20×20.
    ///
    /// So on the canvas: Box covers (100, 100)–(220, 180) and Dot covers
    /// (110, 110)–(130, 130).
    private func makeTree() -> PhotonzDocument {
        let dot = leaf("Dot", CGRect(x: 0, y: 0, width: 20, height: 20))
        let badge = Layer(name: "Badge", content: .group(GroupContent(children: [dot])),
                          frame: CGRect(x: 10, y: 10, width: 0, height: 0))
        let box = leaf("Box", CGRect(x: 0, y: 0, width: 120, height: 80))
        let card = Layer(name: "Card", content: .group(GroupContent(children: [box, badge])),
                         frame: CGRect(x: 100, y: 100, width: 0, height: 0))
        return PhotonzDocument(canvasSize: CGSize(width: 400, height: 400),
                               layers: [leaf("Back", CGRect(x: 0, y: 0, width: 400, height: 400)), card])
    }

    // MARK: - What ⌘G is allowed to do

    @Test func groupingNeedsTwoLayers() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        let a = leaf("A", CGRect(x: 0, y: 0, width: 10, height: 10))
        let b = leaf("B", CGRect(x: 20, y: 20, width: 10, height: 10))
        doc.addLayer(a)
        doc.addLayer(b)
        #expect(doc.canGroup(ids: []) == false)
        #expect(doc.canGroup(ids: [a.id]) == false)
        #expect(doc.canGroup(ids: [a.id, b.id]))
    }

    @Test func aLockedLayerNeverCountsTowardGrouping() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        var background = leaf("Background", CGRect(x: 0, y: 0, width: 100, height: 100))
        background.isLocked = true
        let a = leaf("A", CGRect(x: 0, y: 0, width: 10, height: 10))
        doc.addLayer(background)
        doc.addLayer(a)
        // Select All then ⌘G: only one layer can actually join, so the row greys.
        #expect(doc.canGroup(ids: [background.id, a.id]) == false)
    }

    @Test func twoChildrenOfOneGroupCanBeGroupedAgain() {
        var doc = makeTree()
        let extra = leaf("Extra", CGRect(x: 40, y: 0, width: 20, height: 20))
        let added = doc.addLayer(extra, toGroup: id(doc, "Card"))
        #expect(added)
        #expect(doc.canGroup(ids: [id(doc, "Box"), extra.id]))
    }

    @Test func aSelectionSpreadOverTwoParentsGroupsOnlyOneOfThem() {
        // The anchor (nearest the canvas) decides the list; nothing gets
        // yanked out of a group it lives in, so a selection that leaves only
        // one member in the anchor's list cannot group.
        let doc = makeTree()
        #expect(doc.canGroup(ids: [id(doc, "Back"), id(doc, "Dot")]) == false)
    }

    @Test func groupingLeavesEverythingWhereItWasOnScreen() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400))
        let box = leaf("Box", CGRect(x: 100, y: 100, width: 120, height: 80))
        let label = leaf("Label", CGRect(x: 110, y: 190, width: 60, height: 20))
        doc.addLayer(box)
        doc.addLayer(label)
        let group = doc.groupLayers(ids: [box.id, label.id])
        #expect(group != nil)
        #expect(doc.canvasFrame(of: box.id) == CGRect(x: 100, y: 100, width: 120, height: 80))
        #expect(doc.canvasFrame(of: label.id) == CGRect(x: 110, y: 190, width: 60, height: 20))
        #expect(doc.canvasBounds(of: group?.id ?? UUID())
                == CGRect(x: 100, y: 100, width: 120, height: 110))
    }

    // MARK: - What ⇧⌘G is allowed to do

    @Test func ungroupingNeedsAGroupInTheSelection() {
        let doc = makeTree()
        #expect(doc.canUngroup(ids: []) == false)
        #expect(doc.canUngroup(ids: [id(doc, "Back")]) == false)
        #expect(doc.canUngroup(ids: [id(doc, "Card")]))
        // A mixed selection still offers it: the groups in it come apart.
        #expect(doc.canUngroup(ids: [id(doc, "Back"), id(doc, "Card")]))
    }

    @Test func aLockedGroupDoesNotUngroup() {
        var doc = makeTree()
        doc.updateLayer(id: id(doc, "Card")) { $0.isLocked = true }
        #expect(doc.canUngroup(ids: [id(doc, "Card")]) == false)
    }

    @Test func ungroupingPutsThePiecesBackWhereTheyWere() {
        var doc = makeTree()
        let boxBefore = doc.canvasFrame(of: id(doc, "Box"))
        let dotBefore = doc.canvasFrame(of: id(doc, "Dot"))
        let freed = doc.ungroupLayers(ids: [id(doc, "Card")])
        #expect(Set(freed) == Set([id(doc, "Box"), id(doc, "Badge")]))
        #expect(doc.canvasFrame(of: id(doc, "Box")) == boxBefore)
        // The nested group came out whole, with its own contents untouched.
        #expect(doc.canvasFrame(of: id(doc, "Dot")) == dotBefore)
        #expect(doc.parentID(of: id(doc, "Box")) == nil)
        #expect(doc.layer(id: id(doc, "Card")) == nil)
    }

    @Test func ungroupingKeepsTheGroupsSlotInTheStack() {
        var doc = makeTree()
        doc.ungroupLayers(ids: [id(doc, "Card")])
        // Back was underneath the group and stays underneath its contents.
        #expect(doc.layers.map(\.name) == ["Back", "Box", "Badge"])
    }

    @Test func ungroupingSeveralGroupsIsOneMutation() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400))
        let a = leaf("A", CGRect(x: 0, y: 0, width: 10, height: 10))
        let b = leaf("B", CGRect(x: 20, y: 0, width: 10, height: 10))
        let c = leaf("C", CGRect(x: 40, y: 0, width: 10, height: 10))
        let d = leaf("D", CGRect(x: 60, y: 0, width: 10, height: 10))
        for layer in [a, b, c, d] { doc.addLayer(layer) }
        let first = doc.groupLayers(ids: [a.id, b.id])
        let second = doc.groupLayers(ids: [c.id, d.id])
        let freed = doc.ungroupLayers(ids: [first?.id ?? UUID(), second?.id ?? UUID()])
        #expect(Set(freed) == Set([a.id, b.id, c.id, d.id]))
        #expect(doc.layers.map(\.name) == ["A", "B", "C", "D"])
    }

    @Test func ungroupingIgnoresLayersThatAreNotGroups() {
        var doc = makeTree()
        let freed = doc.ungroupLayers(ids: [id(doc, "Back")])
        #expect(freed.isEmpty)
        #expect(doc.layers.map(\.name) == ["Back", "Card"])
    }

    // MARK: - Naming

    @Test func eachNewGroupGetsItsOwnName() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400))
        let names = (0..<3).map { i -> String in
            let a = leaf("a\(i)", CGRect(x: 0, y: CGFloat(i) * 30, width: 10, height: 10))
            let b = leaf("b\(i)", CGRect(x: 20, y: CGFloat(i) * 30, width: 10, height: 10))
            doc.addLayer(a)
            doc.addLayer(b)
            return doc.groupLayers(ids: [a.id, b.id], name: doc.freshGroupName())?.name ?? ""
        }
        #expect(names == ["Group", "Group 2", "Group 3"])
    }

    @Test func afreshNameSkipsNamesAlreadyTaken() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400))
        doc.addLayer(Layer(name: "Group", content: .group(GroupContent()), frame: .zero))
        doc.addLayer(Layer(name: "Group 2", content: .group(GroupContent()), frame: .zero))
        #expect(doc.freshGroupName() == "Group 3")
    }

    // MARK: - A click picks the outermost thing you are not inside

    @Test func aClickOnAGroupsContentsPicksTheWholeGroup() {
        let doc = makeTree()
        let hit = doc.selectionTarget(at: CGPoint(x: 150, y: 150), inside: nil)
        #expect(hit?.id == id(doc, "Card"))
        #expect(hit?.context == nil)
    }

    @Test func aClickOnALooseLayerPicksItAsItAlwaysDid() {
        let doc = makeTree()
        #expect(doc.selectionTarget(at: CGPoint(x: 350, y: 350), inside: nil)?.id == id(doc, "Back"))
    }

    @Test func aClickOnEmptyCanvasPicksNothing() {
        var doc = makeTree()
        doc.removeLayer(id: id(doc, "Back"))
        #expect(doc.selectionTarget(at: CGPoint(x: 350, y: 350), inside: nil) == nil)
    }

    @Test func insideAGroupAClickPicksTheChildUnderThePointer() {
        let doc = makeTree()
        let card = id(doc, "Card")
        let hit = doc.selectionTarget(at: CGPoint(x: 150, y: 150), inside: card)
        #expect(hit?.id == id(doc, "Box"))
        #expect(hit?.context == card)
    }

    @Test func insideAGroupAClickOnANestedGroupPicksThatGroupWhole() {
        let doc = makeTree()
        // (115, 115) is inside Dot, two levels down. From Card, one level down
        // is Badge, and that is what gets picked.
        let hit = doc.selectionTarget(at: CGPoint(x: 115, y: 115), inside: id(doc, "Card"))
        #expect(hit?.id == id(doc, "Badge"))
    }

    @Test func clickingOutsideTheGroupYouAreInLeavesIt() {
        let doc = makeTree()
        let hit = doc.selectionTarget(at: CGPoint(x: 350, y: 350), inside: id(doc, "Card"))
        #expect(hit?.id == id(doc, "Back"))
        #expect(hit?.context == nil)
    }

    @Test func aStaleContextIsForgotten() {
        var doc = makeTree()
        let card = id(doc, "Card")
        doc.ungroupLayers(ids: [card])
        // The group is gone; a click still resolves, from the top.
        let hit = doc.selectionTarget(at: CGPoint(x: 150, y: 150), inside: card)
        #expect(hit?.id == id(doc, "Box"))
        #expect(hit?.context == nil)
    }

    // MARK: - Double click goes one level deeper

    @Test func doubleClickOnAGroupSelectsThePieceUnderThePointer() {
        let doc = makeTree()
        let step = doc.descendTarget(at: CGPoint(x: 150, y: 150), inside: nil)
        #expect(step?.id == id(doc, "Box"))
        #expect(step?.context == id(doc, "Card"))
    }

    @Test func doubleClickInsideAGroupGoesDeeperStill() {
        let doc = makeTree()
        let step = doc.descendTarget(at: CGPoint(x: 115, y: 115), inside: id(doc, "Card"))
        #expect(step?.id == id(doc, "Dot"))
        #expect(step?.context == id(doc, "Badge"))
    }

    @Test func doubleClickOnALeafHasNowhereToGo() {
        let doc = makeTree()
        // Nothing to descend into: Back is a loose layer, Box is already the
        // deepest thing under the pointer once you are inside Card.
        #expect(doc.descendTarget(at: CGPoint(x: 350, y: 350), inside: nil) == nil)
        #expect(doc.descendTarget(at: CGPoint(x: 150, y: 150), inside: id(doc, "Card")) == nil)
    }

    // MARK: - Canvas-space layers, for everything that draws

    @Test func aCanvasSpaceLayerCarriesItsFrameOnTheCanvas() {
        let doc = makeTree()
        #expect(doc.canvasLayer(id: id(doc, "Dot"))?.frame
                == CGRect(x: 110, y: 110, width: 20, height: 20))
        // A group reports the box it actually occupies, since its stored size
        // is unused.
        #expect(doc.canvasLayer(id: id(doc, "Card"))?.frame
                == CGRect(x: 100, y: 100, width: 120, height: 80))
    }

    @Test func aTopLevelLayerIsUnchangedInCanvasSpace() {
        let doc = makeTree()
        let back = id(doc, "Back")
        #expect(doc.canvasLayer(id: back)?.frame == doc.layer(id: back)?.frame)
    }

    @Test func aCanvasSpaceFrameConvertsBackToWhatIsStored() {
        let doc = makeTree()
        let dot = id(doc, "Dot")
        let moved = CGRect(x: 200, y: 300, width: 20, height: 20)
        #expect(doc.parentSpaceFrame(moved, of: dot) == CGRect(x: 90, y: 190, width: 20, height: 20))
        // Round trip: what the canvas shows converts back to what is stored.
        let stored = doc.layer(id: dot)?.frame
        #expect(doc.parentSpaceFrame(doc.canvasLayer(id: dot)?.frame ?? .zero, of: dot) == stored)
    }

    @Test func movingAGroupOnTheCanvasMovesEverythingInside() {
        var doc = makeTree()
        let card = id(doc, "Card")
        let box = doc.canvasFrame(of: id(doc, "Box"))
        let dot = doc.canvasFrame(of: id(doc, "Dot"))
        doc.moveLayer(id: card, toCanvasOrigin: CGPoint(x: 150, y: 220))
        #expect(doc.canvasFrame(of: id(doc, "Box"))
                == box?.offsetBy(dx: 50, dy: 120))
        #expect(doc.canvasFrame(of: id(doc, "Dot"))
                == dot?.offsetBy(dx: 50, dy: 120))
        #expect(doc.canvasBounds(of: card)?.origin == CGPoint(x: 150, y: 220))
    }
}
