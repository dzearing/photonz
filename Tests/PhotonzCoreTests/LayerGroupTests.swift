import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Layers can hold layers. A group is a layer whose content is other layers,
/// and a child's frame is measured from its parent's top left, not the canvas
/// (`docs/design/ui-building.md`, "A layer's position is stored against its
/// parent"). Groups translate and never scale or rotate, so a layer's canvas
/// position is the sum of the origins from it up to the canvas — plain
/// addition.
@Suite("Layers can hold layers")
struct LayerGroupTests {

    private func leaf(_ name: String, _ frame: CGRect) -> Layer {
        Layer(name: name, content: .text(TextContent(string: name)), frame: frame)
    }

    /// Canvas 200×200. Bottom-up: Back (a loose layer), then a group "Button"
    /// anchored at (50, 60) holding Box at local (0, 0) and Label at local
    /// (8, 4). Box's canvas position is therefore (50, 60), Label's (58, 64).
    private func makeTree() -> PhotonzDocument {
        let box = leaf("Box", CGRect(x: 0, y: 0, width: 100, height: 40))
        let label = leaf("Label", CGRect(x: 8, y: 4, width: 60, height: 20))
        let group = Layer(name: "Button", content: .group(GroupContent(children: [box, label])),
                          frame: CGRect(x: 50, y: 60, width: 0, height: 0))
        return PhotonzDocument(canvasSize: CGSize(width: 200, height: 200),
                               layers: [leaf("Back", CGRect(x: 0, y: 0, width: 200, height: 200)), group])
    }

    private func id(_ doc: PhotonzDocument, _ name: String) -> UUID {
        doc.allLayers.first { $0.name == name }?.id ?? UUID()
    }

    // MARK: - Finding

    @Test func findsALayerLivingInsideAGroup() {
        let doc = makeTree()
        let label = doc.allLayers.first { $0.name == "Label" }
        #expect(label != nil)
        #expect(doc.layer(id: label?.id ?? UUID())?.name == "Label")
    }

    @Test func findingIsUnchangedForAFlatDocument() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 10, height: 10))
        let a = leaf("A", CGRect(x: 1, y: 1, width: 2, height: 2))
        doc.addLayer(a)
        #expect(doc.layer(id: a.id)?.name == "A")
        #expect(doc.index(of: a.id) == 0)
    }

    @Test func pathNamesWhereALayerSitsInTheTree() {
        let doc = makeTree()
        #expect(doc.path(of: id(doc, "Back")) == [0])
        #expect(doc.path(of: id(doc, "Button")) == [1])
        #expect(doc.path(of: id(doc, "Box")) == [1, 0])
        #expect(doc.path(of: id(doc, "Label")) == [1, 1])
        #expect(doc.path(of: UUID()) == nil)
    }

    @Test func parentOfAChildIsItsGroupAndOfATopLevelLayerIsNothing() {
        let doc = makeTree()
        #expect(doc.parentID(of: id(doc, "Label")) == id(doc, "Button"))
        #expect(doc.parentID(of: id(doc, "Back")) == nil)
    }

    // MARK: - The coordinate rule

    @Test func aChildsPositionIsKeptAgainstItsParent() {
        let doc = makeTree()
        // Stored numbers are parent-relative...
        #expect(doc.layer(id: id(doc, "Label"))?.frame.origin == CGPoint(x: 8, y: 4))
        // ...and canvas space is the sum up the chain.
        #expect(doc.canvasFrame(of: id(doc, "Label")) == CGRect(x: 58, y: 64, width: 60, height: 20))
        #expect(doc.canvasFrame(of: id(doc, "Box")) == CGRect(x: 50, y: 60, width: 100, height: 40))
    }

    @Test func movingTheParentMovesEverythingInsideIt() {
        var doc = makeTree()
        doc.updateLayer(id: id(doc, "Button")) { $0.frame.origin.x += 10; $0.frame.origin.y += 5 }
        // Not one number per child changed: the children's stored frames are untouched.
        #expect(doc.layer(id: id(doc, "Label"))?.frame.origin == CGPoint(x: 8, y: 4))
        #expect(doc.canvasFrame(of: id(doc, "Label")) == CGRect(x: 68, y: 69, width: 60, height: 20))
        #expect(doc.canvasFrame(of: id(doc, "Box")) == CGRect(x: 60, y: 65, width: 100, height: 40))
    }

    @Test func theSameTreeCanSitInTwoPlacesAtOnce() {
        var doc = makeTree()
        let button = doc.layer(id: id(doc, "Button"))
        var second = button?.reidentified() ?? leaf("x", .zero)
        second.frame.origin = CGPoint(x: 0, y: 0)
        doc.addLayer(second)
        // Identical insides, two different places on the canvas, and no number
        // inside either copy had to be rewritten.
        #expect(second.children.map(\.frame) == button?.children.map(\.frame))
        #expect(doc.canvasFrame(of: second.children[1].id) == CGRect(x: 8, y: 4, width: 60, height: 20))
        #expect(doc.canvasFrame(of: id(doc, "Label")) == CGRect(x: 58, y: 64, width: 60, height: 20))
    }

    @Test func aGroupsBoxIsDerivedFromItsChildrenNotStored() {
        let doc = makeTree()
        // Box spans local (0,0)-(100,40), Label (8,4)-(68,24) → union (0,0)-(100,40).
        #expect(doc.canvasBounds(of: id(doc, "Button")) == CGRect(x: 50, y: 60, width: 100, height: 40))
    }

    @Test func aChildStickingOutToTheLeftDoesNotMoveTheGroup() {
        var doc = makeTree()
        // The origin is set once and then holds still: drawing a child at a
        // negative X gives that child a negative number, it does not re-anchor
        // the group and silently rewrite its siblings.
        doc.addLayer(leaf("Badge", CGRect(x: -20, y: -10, width: 10, height: 10)),
                     toGroup: id(doc, "Button"))
        #expect(doc.layer(id: id(doc, "Button"))?.frame.origin == CGPoint(x: 50, y: 60))
        #expect(doc.layer(id: id(doc, "Label"))?.frame.origin == CGPoint(x: 8, y: 4))
        #expect(doc.canvasBounds(of: id(doc, "Button")) == CGRect(x: 30, y: 50, width: 120, height: 50))
    }

    // MARK: - Adding

    @Test func addingIntoAGroupPutsTheLayerInsideIt() {
        var doc = makeTree()
        let icon = leaf("Icon", CGRect(x: 70, y: 8, width: 16, height: 16))
        let added = doc.addLayer(icon, toGroup: id(doc, "Button"))
        #expect(added)
        #expect(doc.layers.count == 2)
        #expect(doc.layer(id: id(doc, "Button"))?.children.map(\.name) == ["Box", "Label", "Icon"])
        #expect(doc.canvasFrame(of: icon.id) == CGRect(x: 120, y: 68, width: 16, height: 16))
    }

    @Test func addingIntoAGroupHonoursTheIndex() {
        var doc = makeTree()
        let added = doc.addLayer(leaf("Icon", .zero), toGroup: id(doc, "Button"), at: 0)
        #expect(added)
        #expect(doc.layer(id: id(doc, "Button"))?.children.map(\.name) == ["Icon", "Box", "Label"])
    }

    @Test func addingIntoSomethingThatIsNotAGroupDoesNothing() {
        var doc = makeTree()
        let added = doc.addLayer(leaf("Icon", .zero), toGroup: id(doc, "Back"))
        #expect(added == false)
        #expect(doc.allLayers.contains { $0.name == "Icon" } == false)
    }

    @Test func aGroupCannotBeMovedInsideItself() {
        var doc = makeTree()
        let button = id(doc, "Button")
        let intoItself = doc.moveLayer(id: button, toGroup: button)
        #expect(intoItself == false)
        // Nor inside one of its own descendants, which would make a cycle.
        let intoChild = doc.moveLayer(id: button, toGroup: id(doc, "Box"))
        #expect(intoChild == false)
    }

    // MARK: - Reparenting

    @Test func movingALayerIntoAGroupKeepsItWhereItWasOnScreen() {
        var doc = makeTree()
        let loose = leaf("Loose", CGRect(x: 120, y: 100, width: 30, height: 30))
        doc.addLayer(loose)
        let moved = doc.moveLayer(id: loose.id, toGroup: id(doc, "Button"))
        #expect(moved)
        // Stored against its new parent...
        #expect(doc.layer(id: loose.id)?.frame.origin == CGPoint(x: 70, y: 40))
        // ...and not a pixel moved on the canvas.
        #expect(doc.canvasFrame(of: loose.id) == CGRect(x: 120, y: 100, width: 30, height: 30))
    }

    @Test func movingALayerOutOfAGroupKeepsItWhereItWasOnScreen() {
        var doc = makeTree()
        let label = id(doc, "Label")
        let moved = doc.moveLayer(id: label, toGroup: nil)
        #expect(moved)
        #expect(doc.layer(id: label)?.frame == CGRect(x: 58, y: 64, width: 60, height: 20))
        #expect(doc.parentID(of: label) == nil)
        #expect(doc.layer(id: id(doc, "Button"))?.children.map(\.name) == ["Box"])
    }

    // MARK: - Removing

    @Test func removingReachesInsideAGroup() {
        var doc = makeTree()
        let removed = doc.removeLayer(id: id(doc, "Label"))
        #expect(removed?.name == "Label")
        #expect(doc.layer(id: id(doc, "Label")) == nil)
        #expect(doc.layer(id: id(doc, "Button"))?.children.map(\.name) == ["Box"])
    }

    @Test func removingAGroupTakesItsChildrenWithIt() {
        var doc = makeTree()
        let box = id(doc, "Box")
        doc.removeLayer(id: id(doc, "Button"))
        #expect(doc.layers.map(\.name) == ["Back"])
        #expect(doc.layer(id: box) == nil)
    }

    @Test func batchRemoveReachesInsideAGroup() {
        var doc = makeTree()
        doc.removeLayers(ids: [id(doc, "Label"), id(doc, "Back")])
        #expect(doc.layers.map(\.name) == ["Button"])
        #expect(doc.layer(id: id(doc, "Button"))?.children.map(\.name) == ["Box"])
    }

    // MARK: - Reordering

    @Test func reorderingHappensAmongSiblings() {
        var doc = makeTree()
        doc.moveLayer(id: id(doc, "Label"), to: 0)
        #expect(doc.layer(id: id(doc, "Button"))?.children.map(\.name) == ["Label", "Box"])
        // The top level is untouched.
        #expect(doc.layers.map(\.name) == ["Back", "Button"])
    }

    @Test func restackingAChildStaysInsideItsGroup() {
        var doc = makeTree()
        let restacked = doc.restackLayers(ids: [id(doc, "Box")], .toFront)
        #expect(restacked)
        #expect(doc.layer(id: id(doc, "Button"))?.children.map(\.name) == ["Label", "Box"])
        #expect(doc.layers.map(\.name) == ["Back", "Button"])
    }

    @Test func restackingAChildThatIsAlreadyOnTopChangesNothing() {
        var doc = makeTree()
        let restacked = doc.restackLayers(ids: [id(doc, "Label")], .forward)
        #expect(restacked == false)
    }

    @Test func restackingSortsEachParentsOwnList() {
        var doc = makeTree()
        // A selection spanning two levels restacks within each list, not across.
        let restacked = doc.restackLayers(ids: [id(doc, "Box"), id(doc, "Back")], .toFront)
        #expect(restacked)
        #expect(doc.layer(id: id(doc, "Button"))?.children.map(\.name) == ["Label", "Box"])
        // "Back" is locked-free here, so it rises above Button at the top level.
        #expect(doc.layers.map(\.name) == ["Button", "Back"])
    }

    // MARK: - Duplicating

    @Test func duplicatingReachesInsideAGroup() {
        var doc = makeTree()
        let copies = doc.duplicateLayers(ids: [id(doc, "Label")])
        #expect(copies.map(\.name) == ["Label copy"])
        #expect(doc.layer(id: id(doc, "Button"))?.children.map(\.name) == ["Box", "Label", "Label copy"])
        #expect(doc.parentID(of: copies[0].id) == id(doc, "Button"))
    }

    @Test func duplicatingAGroupMintsFreshIdsAllTheWayDown() {
        var doc = makeTree()
        let original = doc.layer(id: id(doc, "Button"))
        let copy = doc.duplicateLayer(id: id(doc, "Button"))
        let originalIDs = Set((original?.children ?? []).map(\.id))
        let copyIDs = Set((copy?.children ?? []).map(\.id))
        #expect(copyIDs.count == 2)
        #expect(copyIDs.isDisjoint(with: originalIDs))
        // Every id in the document is still unique, so layer(id:) is unambiguous.
        let all = doc.allLayers.map(\.id)
        #expect(Set(all).count == all.count)
        // The copy's insides are placed identically inside it.
        #expect(copy?.children.map(\.frame) == original?.children.map(\.frame))
    }

    @Test func duplicatingAGroupOffsetsTheGroupOnceNotEveryChild() {
        var doc = makeTree()
        let copy = doc.duplicateLayer(id: id(doc, "Button"), offsetBy: CGPoint(x: 10, y: 10))
        #expect(copy?.frame.origin == CGPoint(x: 60, y: 70))
        #expect(copy?.children.map(\.frame.origin) == [CGPoint(x: 0, y: 0), CGPoint(x: 8, y: 4)])
        #expect(doc.canvasFrame(of: copy?.children[1].id ?? UUID())
                == CGRect(x: 68, y: 74, width: 60, height: 20))
    }

    // MARK: - Hit testing

    @Test func hitTestingDescendsToTheLayerUnderThePoint() {
        let doc = makeTree()
        // (60, 70) is inside Box but outside Label (Label starts at canvas 58,64
        // and is 60×20, so 60,70 is inside Label too — pick a Box-only point).
        #expect(doc.hitTest(CGPoint(x: 130, y: 90))?.name == "Box")
        #expect(doc.hitTest(CGPoint(x: 100, y: 70))?.name == "Label")
    }

    @Test func hitTestingMissesTheEmptySpaceBetweenAGroupsChildren() {
        var doc = makeTree()
        doc.removeLayer(id: id(doc, "Back"))
        // Inside the group's derived box but on none of its children.
        doc.updateLayer(id: id(doc, "Box")) { $0.frame = CGRect(x: 0, y: 0, width: 10, height: 10) }
        #expect(doc.hitTest(CGPoint(x: 130, y: 90)) == nil)
    }

    @Test func hitTestingSkipsAHiddenOrLockedGroupWhole() {
        var doc = makeTree()
        doc.updateLayer(id: id(doc, "Button")) { $0.isVisible = false }
        #expect(doc.hitTest(CGPoint(x: 100, y: 70))?.name == "Back")
        doc.updateLayer(id: id(doc, "Button")) { $0.isVisible = true; $0.isLocked = true }
        #expect(doc.hitTest(CGPoint(x: 100, y: 70))?.name == "Back")
    }

    @Test func hitTestPathReportsTheWholeChainSoACallerCanPickTheGroup() {
        let doc = makeTree()
        #expect(doc.hitTestPath(CGPoint(x: 100, y: 70)) == [1, 1])
    }

    @Test func marqueeGrabsAGroupWholeAndNeverAChildOnItsOwn() {
        let doc = makeTree()
        let grabbed = doc.layerIDs(fullyInside: CGRect(x: 40, y: 50, width: 130, height: 70))
        #expect(grabbed == [id(doc, "Button")])
    }

    @Test func marqueeSkipsAGroupThatOnlyPartlyFits() {
        let doc = makeTree()
        #expect(doc.layerIDs(fullyInside: CGRect(x: 40, y: 50, width: 60, height: 70)).isEmpty)
    }

    // MARK: - Grouping and ungrouping

    @Test func groupingAnchorsAtTheTopLeftOfWhatWasSelectedAndRewritesItOnce() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 200, height: 200))
        let a = leaf("A", CGRect(x: 30, y: 40, width: 20, height: 20))
        let b = leaf("B", CGRect(x: 60, y: 100, width: 20, height: 20))
        doc.addLayer(a)
        doc.addLayer(b)
        let group = doc.groupLayers(ids: [a.id, b.id], name: "Button")
        #expect(group?.frame.origin == CGPoint(x: 30, y: 40))
        #expect(doc.layers.map(\.name) == ["Button"])
        #expect(doc.layer(id: a.id)?.frame.origin == CGPoint(x: 0, y: 0))
        #expect(doc.layer(id: b.id)?.frame.origin == CGPoint(x: 30, y: 60))
        // Nothing moved on screen.
        #expect(doc.canvasFrame(of: b.id) == CGRect(x: 60, y: 100, width: 20, height: 20))
    }

    @Test func groupingKeepsTheStackingSlotOfTheTopmostMember() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 200, height: 200))
        let names = ["A", "B", "C", "D"]
        let made = names.map { leaf($0, CGRect(x: 0, y: 0, width: 10, height: 10)) }
        made.forEach { doc.addLayer($0) }
        _ = doc.groupLayers(ids: [made[0].id, made[2].id], name: "G")
        #expect(doc.layers.map(\.name) == ["B", "G", "D"])
    }

    @Test func groupingLeavesLockedLayersAlone() {
        var doc = makeTree()
        doc.updateLayer(id: id(doc, "Back")) { $0.isLocked = true }
        let group = doc.groupLayers(ids: [id(doc, "Back")], name: "G")
        #expect(group == nil)
        #expect(doc.layers.map(\.name) == ["Back", "Button"])
    }

    @Test func groupingOnlyEverTakesLayersThatShareAParent() {
        var doc = makeTree()
        // "Back" is top level, "Label" lives in Button. The member nearest the
        // canvas decides the list, and the one inside the group is left in it
        // rather than being yanked out.
        let group = doc.groupLayers(ids: [id(doc, "Back"), id(doc, "Label")], name: "G")
        #expect(group != nil)
        #expect(doc.layers.map(\.name) == ["G", "Button"])
        #expect(doc.parentID(of: id(doc, "Label")) == id(doc, "Button"))
    }

    @Test func ungroupingPutsTheChildrenBackWhereTheyWere() {
        var doc = makeTree()
        let boxID = id(doc, "Box"), labelID = id(doc, "Label")
        let freed = doc.ungroupLayer(id: id(doc, "Button"))
        #expect(freed == [boxID, labelID])
        #expect(doc.layers.map(\.name) == ["Back", "Box", "Label"])
        #expect(doc.layer(id: labelID)?.frame == CGRect(x: 58, y: 64, width: 60, height: 20))
        #expect(doc.layer(id: boxID)?.frame == CGRect(x: 50, y: 60, width: 100, height: 40))
    }

    @Test func groupingThenUngroupingIsARoundTrip() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 200, height: 200))
        let a = leaf("A", CGRect(x: 30, y: 40, width: 20, height: 20))
        let b = leaf("B", CGRect(x: 60, y: 100, width: 20, height: 20))
        doc.addLayer(a)
        doc.addLayer(b)
        let before = doc.layers
        let group = doc.groupLayers(ids: [a.id, b.id], name: "G")
        _ = doc.ungroupLayer(id: group?.id ?? UUID())
        #expect(doc.layers == before)
    }

    // MARK: - Flattening (what today's callers keep running on)

    @Test func flatteningHandsBackCanvasSpaceLeaves() {
        let doc = makeTree()
        let flat = doc.flattenedLayers
        #expect(flat.map(\.name) == ["Back", "Box", "Label"])
        #expect(flat[2].frame == CGRect(x: 58, y: 64, width: 60, height: 20))
    }

    @Test func flatteningIsTheSameArrayForAFlatDocument() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 10, height: 10))
        doc.addLayer(leaf("A", CGRect(x: 1, y: 1, width: 2, height: 2)))
        doc.addLayer(leaf("B", CGRect(x: 3, y: 3, width: 2, height: 2)))
        #expect(doc.flattenedLayers == doc.layers)
    }

    @Test func flatteningCarriesTheGroupsVisibilityLockAndOpacityDown() {
        var doc = makeTree()
        doc.updateLayer(id: id(doc, "Button")) {
            $0.isVisible = false
            $0.isLocked = true
            $0.style.opacity = 0.5
        }
        doc.updateLayer(id: id(doc, "Label")) { $0.style.opacity = 0.5 }
        let flat = doc.flattenedLayers
        let label = flat.first { $0.name == "Label" }
        #expect(label?.isVisible == false)
        #expect(label?.isLocked == true)
        #expect(label?.style.opacity == 0.25)
    }

    @Test func flatteningKeepsChildIdsSoSelectionStillResolves() {
        let doc = makeTree()
        #expect(doc.flattenedLayers.contains { $0.id == id(doc, "Label") })
    }

    // MARK: - Canvas operations

    @Test func croppingTheCanvasShiftsAGroupOnceNotEveryChild() {
        var doc = makeTree()
        doc.crop(to: CGRect(x: 20, y: 20, width: 150, height: 150))
        #expect(doc.layer(id: id(doc, "Button"))?.frame.origin == CGPoint(x: 30, y: 40))
        #expect(doc.layer(id: id(doc, "Label"))?.frame.origin == CGPoint(x: 8, y: 4))
    }

    @Test func croppingDropsAGroupThatFallsEntirelyOutside() {
        var doc = makeTree()
        doc.crop(to: CGRect(x: 0, y: 0, width: 40, height: 40))
        #expect(doc.layers.map(\.name) == ["Back"])
    }

    @Test func resizingTheCanvasScalesInsideAGroupToo() {
        var doc = makeTree()
        doc.resize(to: CGSize(width: 400, height: 400))
        #expect(doc.layer(id: id(doc, "Button"))?.frame.origin == CGPoint(x: 100, y: 120))
        #expect(doc.layer(id: id(doc, "Label"))?.frame == CGRect(x: 16, y: 8, width: 120, height: 40))
    }

    // MARK: - Save and open

    @Test func aDocumentWithGroupsSurvivesSaveAndOpenUnchanged() throws {
        let doc = makeTree()
        let data = try JSONEncoder().encode(doc)
        let back = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        #expect(back == doc)
        #expect(back.canvasFrame(of: id(back, "Label")) == CGRect(x: 58, y: 64, width: 60, height: 20))
    }

    @Test func aPictureSavedBeforeGroupsExistedStillOpens() throws {
        // A depth-one tree is exactly what every document on disk today is:
        // no `group` case appears in the payload and nothing about decoding a
        // flat stack changed.
        let json = """
        {"canvasSize":[100,80],
         "layers":[{"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","name":"Background",
                    "content":{"text":{"_0":{"string":"hi","fontSize":12,"colorHex":"#000000",
                                             "fontName":"Helvetica","weight":"regular"}}},
                    "frame":[[0,0],[100,80]],
                    "transform":{"rotation":0,"skewX":0,"skewY":0,
                                 "flipHorizontal":false,"flipVertical":false},
                    "style":{"opacity":1,"blurRadius":0,"cornerRadius":0,"borderWidth":0,
                             "borderColorHex":"#000000","blendMode":"normal"},
                    "isVisible":true,"isLocked":true}]}
        """
        let back = try JSONDecoder().decode(PhotonzDocument.self, from: Data(json.utf8))
        #expect(back.layers.count == 1)
        #expect(back.layers[0].name == "Background")
        #expect(back.layers[0].frame == CGRect(x: 0, y: 0, width: 100, height: 80))
        #expect(back.layers[0].isGroup == false)
        #expect(back.flattenedLayers == back.layers)
        #expect(back.pixelScale == 1)
    }

    @Test func aFlatDocumentIsWrittenToDiskExactlyAsItAlwaysWas() throws {
        // Groups add a case, not a wrapper: nothing about the payload of a
        // document without groups changed, so yesterday's app can still read
        // what today's writes.
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 80))
        doc.addLayer(leaf("A", CGRect(x: 1, y: 2, width: 3, height: 4)))
        let json = String(decoding: try JSONEncoder().encode(doc), as: UTF8.self)
        #expect(json.contains("group") == false)
        #expect(json.contains("children") == false)
    }
}
