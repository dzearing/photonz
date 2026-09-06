import Foundation
import CoreGraphics
import Testing
@testable import PhotonzCore

/// Step C5: a copy dropped from the Library follows its original
/// (`docs/design/ui-building.md`, "A component is a subtree with a name, an
/// instance is a layer that points at it").
struct ComponentInstanceTests {

    private func box(_ name: String, _ rect: CGRect) -> Layer {
        Layer(name: name, content: .annotation(AnnotationContent(shape: .rectangle,
                                                                 start: .zero,
                                                                 end: CGPoint(x: rect.width, y: rect.height))),
              frame: rect)
    }

    /// A document holding one component made of two pieces, sitting at 10,10
    /// and 60 x 70 overall.
    private func withComponent() -> (PhotonzDocument, UUID, UUID) {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600),
                                  layers: [box("Box", CGRect(x: 10, y: 10, width: 60, height: 30)),
                                           box("Label", CGRect(x: 20, y: 50, width: 40, height: 30))])
        let group = doc.groupLayers(ids: Set(doc.layers.map(\.id)), name: "Setting")!
        let componentID = doc.makeComponent(id: group.id)!
        return (doc, group.id, componentID)
    }

    // MARK: - Placing one

    @Test func droppingAComponentPlacesALinkedCopy() {
        var (doc, _, componentID) = withComponent()
        let placed = doc.insertComponentInstance(of: componentID, at: CGPoint(x: 400, y: 300))
        #expect(placed != nil)
        let copy = doc.layer(id: placed!)!
        #expect(copy.instanceOf == componentID)
        #expect(copy.isComponentInstance)
        // ...and it is not a main: the shelf must not list it a second time.
        #expect(!copy.isMainComponent)
        #expect(doc.mainComponents.count == 1)
    }

    @Test func aCopyHoldsWhatTheOriginalHolds() {
        var (doc, _, componentID) = withComponent()
        let placed = doc.insertComponentInstance(of: componentID, at: CGPoint(x: 400, y: 300))!
        let copy = doc.layer(id: placed)!
        #expect(copy.children.map(\.name) == ["Box", "Label"])
        // Grouping re-based the pieces against the group's own origin, and the
        // copy holds those same numbers: not one of them has to change for the
        // subtree to sit somewhere else.
        #expect(copy.children.map(\.frame) == [CGRect(x: 0, y: 0, width: 60, height: 30),
                                               CGRect(x: 10, y: 40, width: 40, height: 30)])
    }

    /// Two layers in one document may never share an id, or `layer(id:)` picks
    /// whichever it meets first and an edit lands in the wrong place.
    @Test func aCopyMintsItsOwnIdsAllTheWayDown() {
        var (doc, main, componentID) = withComponent()
        let placed = doc.insertComponentInstance(of: componentID, at: CGPoint(x: 400, y: 300))!
        let originalIDs = Set(doc.layer(id: main)!.selfAndDescendants.map(\.id))
        let copyIDs = Set(doc.layer(id: placed)!.selfAndDescendants.map(\.id))
        #expect(originalIDs.isDisjoint(with: copyIDs))
        #expect(Set(doc.allLayers.map(\.id)).count == doc.allLayers.count)
    }

    @Test func aCopyLandsCentredOnWhereItWasDropped() {
        var (doc, _, componentID) = withComponent()
        let drop = CGPoint(x: 400, y: 300)
        let placed = doc.insertComponentInstance(of: componentID, at: drop)!
        let bounds = doc.canvasBounds(of: placed)!
        #expect(abs(bounds.midX - drop.x) < 0.001)
        #expect(abs(bounds.midY - drop.y) < 0.001)
        // The same size as the original, since nothing scales.
        #expect(bounds.size == doc.canvasBounds(of: doc.mainComponents[0].id)!.size)
    }

    @Test func aCopyTakesTheOriginalsName() {
        var (doc, _, componentID) = withComponent()
        let placed = doc.insertComponentInstance(of: componentID, at: CGPoint(x: 400, y: 300))!
        #expect(doc.layer(id: placed)!.name == "Setting")
    }

    @Test func aCopyOfNothingIsNotPlaced() {
        var (doc, _, _) = withComponent()
        #expect(doc.insertComponentInstance(of: UUID(), at: .zero) == nil)
    }

    /// A copy dropped on a screen joins that screen, the same rule a shape
    /// drawn on it follows, or dragging the screen would leave the copy behind.
    @Test func aCopyDroppedOnAFrameJoinsIt() {
        var (doc, _, componentID) = withComponent()
        let frame = doc.addFrame(name: "Phone", origin: CGPoint(x: 300, y: 100),
                                 size: CGSize(width: 390, height: 400))
        let placed = doc.insertComponentInstance(of: componentID, at: CGPoint(x: 400, y: 300))!
        #expect(doc.parentID(of: placed) == frame.id)
        // ...and it did not move on screen when it joined.
        let bounds = doc.canvasBounds(of: placed)!
        #expect(abs(bounds.midX - 400) < 0.001)
        #expect(abs(bounds.midY - 300) < 0.001)
    }

    // MARK: - Following the original

    @Test func editingTheOriginalUpdatesEveryCopy() {
        var (doc, main, componentID) = withComponent()
        let a = doc.insertComponentInstance(of: componentID, at: CGPoint(x: 200, y: 200))!
        let b = doc.insertComponentInstance(of: componentID, at: CGPoint(x: 500, y: 200))!
        let child = doc.layer(id: main)!.children[1].id
        doc.updateLayer(id: child) { $0.name = "Caption" }
        let report = doc.syncComponentInstances()
        #expect(report.updatedInstances == 2)
        #expect(report.componentIDs == [componentID])
        #expect(doc.layer(id: a)!.children.map(\.name) == ["Box", "Caption"])
        #expect(doc.layer(id: b)!.children.map(\.name) == ["Box", "Caption"])
    }

    @Test func aCopyDoesNotMoveWhenTheOriginalChanges() {
        var (doc, main, componentID) = withComponent()
        let a = doc.insertComponentInstance(of: componentID, at: CGPoint(x: 200, y: 200))!
        let before = doc.layer(id: a)!.frame.origin
        doc.updateLayer(id: doc.layer(id: main)!.children[0].id) { $0.name = "Surface" }
        doc.syncComponentInstances()
        #expect(doc.layer(id: a)!.frame.origin == before)
    }

    /// Sync runs after every edit, so it has to be a no-op when nothing about
    /// a component moved — otherwise every edit in the app records a change.
    @Test func syncingTwiceChangesNothing() {
        var (doc, main, componentID) = withComponent()
        _ = doc.insertComponentInstance(of: componentID, at: CGPoint(x: 200, y: 200))!
        doc.updateLayer(id: doc.layer(id: main)!.children[0].id) { $0.name = "Surface" }
        _ = doc.syncComponentInstances()
        let settled = doc
        let report = doc.syncComponentInstances()
        #expect(report.updatedInstances == 0)
        #expect(doc == settled)
    }

    /// Placing a copy is not "the original changed", so the notice must not
    /// claim a copy was updated the moment it is dropped.
    @Test func placingACopyReportsNoUpdate() {
        var (doc, _, componentID) = withComponent()
        _ = doc.insertComponentInstance(of: componentID, at: CGPoint(x: 200, y: 200))
        #expect(doc.syncComponentInstances().updatedInstances == 0)
    }

    @Test func movingACopyReportsNoUpdate() {
        var (doc, _, componentID) = withComponent()
        let a = doc.insertComponentInstance(of: componentID, at: CGPoint(x: 200, y: 200))!
        doc.updateLayer(id: a) { $0.frame.origin = CGPoint(x: 33, y: 44) }
        #expect(doc.syncComponentInstances().updatedInstances == 0)
    }

    /// Duplicating a copy re-mints every id under it without one pixel moving,
    /// so the notice must not claim a copy followed an edit.
    @Test func duplicatingACopyReportsNoUpdate() {
        var (doc, _, componentID) = withComponent()
        let a = doc.insertComponentInstance(of: componentID, at: CGPoint(x: 200, y: 200))!
        var history = History(document: doc)
        let report = history.perform { $0.duplicateLayer(id: a, offsetBy: CGPoint(x: 16, y: 16)) }
        #expect(report.componentSync.updatedInstances == 0)
        #expect(history.current.instances(of: componentID).count == 2)
    }

    // MARK: - Copies of copies, and copies inside components

    @Test func duplicatingACopyKeepsItLinked() {
        var (doc, _, componentID) = withComponent()
        let a = doc.insertComponentInstance(of: componentID, at: CGPoint(x: 200, y: 200))!
        let copy = doc.duplicateLayer(id: a, offsetBy: CGPoint(x: 20, y: 20))!
        #expect(copy.instanceOf == componentID)
        #expect(copy.id != a)
        doc.syncComponentInstances()
        #expect(doc.instances(of: componentID).count == 2)
    }

    @Test func aCopyNestedInsideAnotherComponentAlsoFollows() {
        var (doc, main, inner) = withComponent()
        // A card holding a copy of the setting, promoted to its own component.
        let nested = doc.insertComponentInstance(of: inner, at: CGPoint(x: 500, y: 400))!
        let backing = box("Backing", CGRect(x: 400, y: 300, width: 300, height: 200))
        doc.addLayer(backing)
        let card = doc.groupLayers(ids: [nested, backing.id], name: "Card")!
        let outer = doc.makeComponent(id: card.id)!
        let placed = doc.insertComponentInstance(of: outer, at: CGPoint(x: 200, y: 500))!

        // Now edit the innermost original and watch it reach two levels down.
        doc.updateLayer(id: doc.layer(id: main)!.children[1].id) { $0.name = "Caption" }
        let report = doc.syncComponentInstances()
        #expect(report.updatedInstances >= 2)

        let deep = doc.layer(id: placed)!.selfAndDescendants
        #expect(deep.contains { $0.name == "Caption" })
        #expect(!deep.contains { $0.name == "Label" })
        // ...and the copy that lives inside the outer original followed too.
        #expect(doc.layer(id: nested)!.children.map(\.name) == ["Box", "Caption"])
    }

    /// A component that held a copy of itself would draw forever, so the model
    /// refuses to make one rather than trusting the interface never to ask.
    @Test func aComponentCannotHoldACopyOfItself() {
        var (doc, main, componentID) = withComponent()
        #expect(!doc.canInsertInstance(of: componentID, intoGroup: main))
        #expect(doc.insertComponentInstance(of: componentID, at: CGPoint(x: 30, y: 30),
                                            inside: main) == nil)
    }

    @Test func aComponentCannotHoldACopyOfSomethingThatHoldsIt() {
        var (doc, _, inner) = withComponent()
        let nested = doc.insertComponentInstance(of: inner, at: CGPoint(x: 500, y: 400))!
        let card = doc.groupLayers(ids: [nested], name: "Card")!
        let outer = doc.makeComponent(id: card.id)!
        // The setting is inside the card, so the card may not go inside the setting.
        #expect(!doc.canInsertInstance(of: outer, intoGroup: doc.mainComponent(componentID: inner)!.id))
    }

    // MARK: - Losing the original

    /// Deleting the original must never wipe the copies: they keep exactly
    /// what they were drawing, as ordinary groups.
    @Test func deletingTheOriginalLeavesTheCopiesAsOrdinaryGroups() {
        var (doc, main, componentID) = withComponent()
        let a = doc.insertComponentInstance(of: componentID, at: CGPoint(x: 200, y: 200))!
        doc.removeLayers(ids: [main])
        doc.syncComponentInstances()
        let orphan = doc.layer(id: a)!
        #expect(orphan.instanceOf == nil)
        #expect(orphan.isGroup)
        #expect(orphan.children.map(\.name) == ["Box", "Label"])
    }

    // MARK: - How a copy behaves as one object

    /// A copy is one thing: a click picks the whole copy, never the piece
    /// under the pointer, because a piece you could select is a piece you
    /// could edit and lose the next time the original changes.
    @Test func aClickInsideACopyPicksTheWholeCopy() {
        var (doc, _, componentID) = withComponent()
        let a = doc.insertComponentInstance(of: componentID, at: CGPoint(x: 400, y: 300))!
        let bounds = doc.canvasBounds(of: a)!
        let inside = CGPoint(x: bounds.minX + 20, y: bounds.minY + 15)
        #expect(doc.hitTest(inside)?.id == a)
        #expect(doc.descendTarget(at: inside, inside: nil) == nil)
    }

    @Test func aCopyHasNoTwistOpenInTheLayersList() {
        var (doc, _, componentID) = withComponent()
        let a = doc.insertComponentInstance(of: componentID, at: CGPoint(x: 400, y: 300))!
        let row = doc.panelRows(expanded: [a]).first { $0.id == a }!
        #expect(!row.isGroup)
        #expect(!row.isExpanded)
        // Nothing under it either: an opened copy would show pieces you cannot keep.
        #expect(!doc.panelRows(expanded: [a]).contains { $0.parentID == a })
    }

    @Test func aCopyIsNotOneOfTheGroupsThatCanBeOpened() {
        var (doc, _, componentID) = withComponent()
        let a = doc.insertComponentInstance(of: componentID, at: CGPoint(x: 400, y: 300))!
        #expect(!doc.openableGroupIDs.contains(a))
    }

    @Test func nothingCanBeDroppedInsideACopy() {
        var (doc, _, componentID) = withComponent()
        let a = doc.insertComponentInstance(of: componentID, at: CGPoint(x: 400, y: 300))!
        let loose = box("Loose", CGRect(x: 0, y: 0, width: 10, height: 10))
        doc.addLayer(loose)
        #expect(!doc.canDrop(ids: [loose.id], .inside(a)))
    }

    // MARK: - What the shelf says

    @Test func theShelfCountsTheCopies() {
        var (doc, _, componentID) = withComponent()
        #expect(doc.componentLibraryEntries.first?.detail == ComponentNaming.mainDetail)
        _ = doc.insertComponentInstance(of: componentID, at: CGPoint(x: 200, y: 200))
        #expect(doc.componentLibraryEntries.first?.detail == "1 copy")
        _ = doc.insertComponentInstance(of: componentID, at: CGPoint(x: 300, y: 200))
        #expect(doc.componentLibraryEntries.first?.detail == "2 copies")
    }

    // MARK: - On disk

    @Test func aCopyRoundTripsThroughTheFile() throws {
        var (doc, _, componentID) = withComponent()
        let a = doc.insertComponentInstance(of: componentID, at: CGPoint(x: 400, y: 300))!
        let data = try JSONEncoder().encode(doc)
        let back = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        #expect(back == doc)
        #expect(back.layer(id: a)?.instanceOf == componentID)
    }

    /// A group that is not a copy writes no copy key, so a document saved
    /// before this step is byte for byte what it was.
    @Test func anOrdinaryGroupWritesNoCopyKey() throws {
        let (doc, _, _) = withComponent()
        let json = String(data: try JSONEncoder().encode(doc), encoding: .utf8)!
        #expect(!json.contains("instanceOf"))
    }

    // MARK: - Through the undo history

    @Test func oneEditOfTheOriginalIsOneUndoStep() {
        var (doc, main, componentID) = withComponent()
        let a = doc.insertComponentInstance(of: componentID, at: CGPoint(x: 200, y: 200))!
        let b = doc.insertComponentInstance(of: componentID, at: CGPoint(x: 500, y: 200))!
        var history = History(document: doc)
        let child = doc.layer(id: main)!.children[1].id
        let report = history.perform { $0.updateLayer(id: child) { $0.name = "Caption" } }
        #expect(report.componentSync.updatedInstances == 2)
        #expect(history.current.layer(id: a)!.children.map(\.name) == ["Box", "Caption"])
        history.undo()
        #expect(history.current.layer(id: a)!.children.map(\.name) == ["Box", "Label"])
        #expect(history.current.layer(id: b)!.children.map(\.name) == ["Box", "Label"])
        #expect(!history.canUndo)
    }

    /// Every edit runs through the same sync, so an edit that has nothing to do
    /// with components must still record nothing when it changes nothing.
    @Test func anEditThatChangesNothingIsStillNotRecorded() {
        let (doc, _, _) = withComponent()
        var history = History(document: doc)
        history.perform { _ in }
        #expect(!history.canUndo)
    }
}
