import Foundation
import CoreGraphics
import Testing
@testable import PhotonzCore

/// Step C4: promoting a group to a main component, and the shelf finding it
/// (`docs/design/ui-building.md`, "A component is a subtree with a name").
struct ComponentTests {

    private func box(_ name: String, _ rect: CGRect) -> Layer {
        Layer(name: name, content: .annotation(AnnotationContent(shape: .rectangle,
                                                                 start: .zero,
                                                                 end: CGPoint(x: rect.width, y: rect.height))),
              frame: rect)
    }

    private func grouped(_ name: String = "Group") -> (PhotonzDocument, UUID) {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400),
                                  layers: [box("Box", CGRect(x: 10, y: 10, width: 60, height: 30)),
                                           box("Label", CGRect(x: 20, y: 50, width: 40, height: 12))])
        let ids = Set(doc.layers.map(\.id))
        let group = doc.groupLayers(ids: ids, name: name)!
        return (doc, group.id)
    }

    // MARK: - What the row is allowed to do

    @Test func onlyAGroupCanBecomeAComponent() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100),
                                  layers: [box("Box", CGRect(x: 0, y: 0, width: 10, height: 10))])
        #expect(!doc.canMakeComponent(ids: Set(doc.layers.map(\.id))))
        #expect(doc.makeComponent(id: doc.layers[0].id) == nil)
    }

    @Test func aGroupCanBecomeAComponent() {
        let (doc, group) = grouped()
        #expect(doc.canMakeComponent(ids: [group]))
    }

    @Test func nothingSelectedCannotBecomeAComponent() {
        let (doc, _) = grouped()
        #expect(!doc.canMakeComponent(ids: []))
    }

    /// Two groups at once would beg the question of which name the shelf takes,
    /// so the row asks for one thing.
    @Test func twoGroupsAtOnceCannotBecomeAComponent() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400),
                                  layers: [box("A", CGRect(x: 0, y: 0, width: 10, height: 10)),
                                           box("B", CGRect(x: 20, y: 0, width: 10, height: 10)),
                                           box("C", CGRect(x: 40, y: 0, width: 10, height: 10)),
                                           box("D", CGRect(x: 60, y: 0, width: 10, height: 10))])
        let first = doc.groupLayers(ids: [doc.layers[0].id, doc.layers[1].id], name: "One")!.id
        let second = doc.groupLayers(ids: [doc.layers[0].id, doc.layers[1].id], name: "Two")!.id
        #expect(doc.canMakeComponent(ids: [first, second]) == false)
    }

    @Test func aLockedGroupCannotBecomeAComponent() {
        var (doc, group) = grouped()
        doc.updateLayer(id: group) { $0.isLocked = true }
        #expect(!doc.canMakeComponent(ids: [group]))
    }

    @Test func aMainCannotBePromotedTwice() {
        var (doc, group) = grouped()
        _ = doc.makeComponent(id: group, name: "Setting")
        #expect(!doc.canMakeComponent(ids: [group]))
    }

    /// A component inside a component is a nesting rule this version does not
    /// have an answer for, so the row is dead rather than making one that later
    /// work would have to unpick.
    @Test func aGroupHoldingAMainCannotBecomeAComponent() {
        var (doc, inner) = grouped()
        _ = doc.makeComponent(id: inner, name: "Setting")
        let outer = doc.groupLayers(ids: [inner], name: "Outer")
        #expect(outer == nil || !doc.canMakeComponent(ids: [outer!.id]))
    }

    @Test func aGroupInsideAMainCannotBecomeAComponent() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400),
                                  layers: [box("A", CGRect(x: 0, y: 0, width: 10, height: 10)),
                                           box("B", CGRect(x: 20, y: 0, width: 10, height: 10)),
                                           box("C", CGRect(x: 40, y: 0, width: 10, height: 10))])
        let inner = doc.groupLayers(ids: [doc.layers[0].id, doc.layers[1].id], name: "Inner")!.id
        let outer = doc.groupLayers(ids: [inner, doc.layers.last!.id], name: "Outer")!.id
        _ = doc.makeComponent(id: outer, name: "Setting")
        #expect(!doc.canMakeComponent(ids: [inner]))
    }

    // MARK: - Promoting

    @Test func promotingMarksTheGroupAndKeepsItsContents() {
        var (doc, group) = grouped()
        let before = doc.layer(id: group)!.children.map(\.id)
        let componentID = doc.makeComponent(id: group, name: "Setting")
        #expect(componentID != nil)
        let main = doc.layer(id: group)!
        #expect(main.isMainComponent)
        #expect(main.componentID == componentID)
        #expect(main.name == "Setting")
        #expect(main.children.map(\.id) == before)
    }

    @Test func promotingLeavesTheLayerWhereItWas() {
        var (doc, group) = grouped()
        let bounds = doc.canvasBounds(of: group)
        _ = doc.makeComponent(id: group, name: "Setting")
        #expect(doc.canvasBounds(of: group) == bounds)
    }

    /// No name given means the group keeps the one it has, unless that name is
    /// the auto one the grouping command minted, which says nothing.
    @Test func promotingAnUnnamedGroupGivesItAComponentName() {
        var (doc, group) = grouped("Group")
        _ = doc.makeComponent(id: group)
        #expect(doc.layer(id: group)!.name == "Component")
    }

    @Test func promotingKeepsANameSomeoneChose() {
        var (doc, group) = grouped("Card")
        _ = doc.makeComponent(id: group)
        #expect(doc.layer(id: group)!.name == "Card")
    }

    @Test func aSecondComponentGetsAFreeName() {
        var (doc, group) = grouped("Group")
        _ = doc.makeComponent(id: group)
        #expect(doc.layer(id: group)!.name == "Component")
        #expect(doc.freshComponentName() == "Component 2")
    }

    // MARK: - Finding it again

    @Test func theShelfListsTheComponent() {
        var (doc, group) = grouped()
        let componentID = doc.makeComponent(id: group, name: "Setting")!
        let entries = doc.componentLibraryEntries
        #expect(entries.count == 1)
        #expect(entries[0].id == componentID.uuidString)
        #expect(entries[0].name == "Setting")
        #expect(entries[0].scope == .components)
        #expect(entries[0].detail == "main")
    }

    @Test func theShelfIsEmptyWithoutComponents() {
        let (doc, _) = grouped()
        #expect(doc.componentLibraryEntries.isEmpty)
    }

    @Test func theShelfFindsAComponentNestedInAFrame() {
        var (doc, group) = grouped()
        let frame = doc.frameSelection(ids: [group], name: "Screen")
        #expect(frame != nil)
        _ = doc.makeComponent(id: group, name: "Setting")
        #expect(doc.componentLibraryEntries.map(\.name) == ["Setting"])
    }

    @Test func aComponentCanBeLookedUpByItsID() {
        var (doc, group) = grouped()
        let componentID = doc.makeComponent(id: group, name: "Setting")!
        #expect(doc.mainComponent(componentID: componentID)?.id == group)
        #expect(doc.mainComponent(componentID: UUID()) == nil)
    }

    // MARK: - One name, both places

    @Test func renamingTheLayerRenamesTheShelfEntry() {
        var (doc, group) = grouped()
        _ = doc.makeComponent(id: group, name: "Setting")
        doc.updateLayer(id: group) { $0.name = "Setting Row" }
        #expect(doc.componentLibraryEntries.map(\.name) == ["Setting Row"])
    }

    @Test func renamingThroughTheComponentRenamesTheLayer() {
        var (doc, group) = grouped()
        let componentID = doc.makeComponent(id: group, name: "Setting")!
        doc.renameComponent(componentID: componentID, to: "  Setting Row  ")
        #expect(doc.layer(id: group)!.name == "Setting Row")
    }

    /// A blank name would leave a nameless tile on the shelf, so it is refused
    /// rather than accepted and drawn as nothing.
    @Test func aBlankNameIsRefused() {
        var (doc, group) = grouped()
        let componentID = doc.makeComponent(id: group, name: "Setting")!
        doc.renameComponent(componentID: componentID, to: "   ")
        #expect(doc.layer(id: group)!.name == "Setting")
    }

    // MARK: - Copies are their own component

    @Test func duplicatingAMainMakesASecondComponent() {
        var (doc, group) = grouped()
        let componentID = doc.makeComponent(id: group, name: "Setting")!
        let copy = doc.layer(id: group)!.duplicated(offsetBy: CGPoint(x: 10, y: 10))
        doc.layers.append(copy)
        #expect(copy.componentID != nil)
        #expect(copy.componentID != componentID)
        #expect(doc.componentLibraryEntries.count == 2)
    }

    // MARK: - On disk

    @Test func anOrdinaryGroupEncodesWithoutComponentKeys() throws {
        let (doc, _) = grouped()
        let data = try JSONEncoder().encode(doc)
        #expect(!String(decoding: data, as: UTF8.self).contains("componentID"))
    }

    @Test func aComponentSurvivesARoundTrip() throws {
        var (doc, group) = grouped()
        let componentID = doc.makeComponent(id: group, name: "Setting")!
        let back = try JSONDecoder().decode(PhotonzDocument.self,
                                            from: JSONEncoder().encode(doc))
        #expect(back.mainComponent(componentID: componentID)?.name == "Setting")
        #expect(back.componentLibraryEntries.count == 1)
    }
}
