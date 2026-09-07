import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Room is only offered where something can spend it.
///
/// A control drawn by hand is a box and a word sitting on top of it, grouped.
/// The group arranges nothing, it is the size of what is in it, and NOTHING in
/// it reaches the group's own edges — the box is just another piece sitting
/// where it was drawn. So room at those edges is air: turning it up grows an
/// invisible box and slides the drawing across and down, and the button a
/// person is looking at comes out exactly the size it was.
///
/// That is what this suite is about. Room stays offered wherever it lands on
/// something — a stack or a grid holds every piece in from its edges, and a
/// piece stretched to the group's own edges IS those edges, which is what a
/// button's fill is. Where neither is true the row is simply not offered, and
/// it comes back the moment the author names a surface, with every copy's
/// answer still on it.
@Suite("Room is offered where something can spend it")
struct ComponentRoomOfferTests {

    // MARK: - Building blocks

    private func box(_ name: String, _ frame: CGRect,
                     placement: LayerPlacement? = nil) -> Layer {
        Layer(name: name, content: .image(ImageRef(pixelSize: frame.size)),
              frame: frame, placement: placement)
    }

    private func text(_ name: String, _ string: String, _ frame: CGRect,
                      placement: LayerPlacement? = nil) -> Layer {
        Layer(name: name, content: .text(TextContent(string: string)),
              frame: frame, placement: placement)
    }

    /// A button drawn by hand: a box 360 by 120 with a word on it, grouped and
    /// given 16 of room. `surface` marks the box as the thing painted to the
    /// group's own edges, which is the one difference between the two halves of
    /// this suite.
    private func drawnButton(surface: Bool) -> (doc: PhotonzDocument, main: UUID,
                                                componentID: UUID) {
        var doc = PhotonzDocument(
            canvasSize: CGSize(width: 1440, height: 1024),
            layers: [box("Rectangle", CGRect(x: 240, y: 180, width: 360, height: 120),
                         placement: surface ? .fill : nil),
                     text("Text", "Save", CGRect(x: 300, y: 220, width: 60, height: 24))])
        let main = doc.groupLayers(ids: Set(doc.layers.map(\.id)), name: "Save button")!
        doc.updateGroupLayout(id: main.id) { $0.padding = GroupPadding(16) }
        let componentID = doc.makeComponent(id: main.id)!
        return (doc, main.id, componentID)
    }

    private func slots(_ doc: PhotonzDocument, _ componentID: UUID,
                       on layer: UUID) -> [ComponentNumberSlot] {
        doc.componentPropertyCandidates(componentID: componentID)
            .first { $0.layerID == layer }?.numberSlots ?? []
    }

    // MARK: - A drawing nothing reaches the edges of

    /// The bug: a button drawn by hand offered a room knob that could not do
    /// anything with the answer.
    @Test("A drawing with nothing at its edges is not offered room")
    func aDrawingWithNothingAtItsEdgesIsNotOfferedRoom() {
        let c = drawnButton(surface: false)
        #expect(slots(c.doc, c.componentID, on: c.main).contains(.padding) == false)
        #expect(c.doc.layer(id: c.main)?.knobValue(for: .padding) == nil)
    }

    /// Naming the box as the surface brings the row straight back: now the room
    /// has something to paint it.
    @Test("Room is offered the moment a piece reaches the group's own edges")
    func roomIsOfferedOnceAPieceReachesTheEdges() {
        let c = drawnButton(surface: true)
        #expect(slots(c.doc, c.componentID, on: c.main).contains(.padding))
    }

    /// A stack spends room whatever is in it: every piece is held in from the
    /// edges by the flow itself.
    @Test("A stack is always offered room")
    func aStackIsAlwaysOfferedRoom() {
        var doc = PhotonzDocument(
            canvasSize: CGSize(width: 800, height: 600),
            layers: [text("Label", "Save", CGRect(x: 20, y: 20, width: 60, height: 20)),
                     text("Badge", "3", CGRect(x: 20, y: 60, width: 20, height: 20))])
        let main = doc.groupLayers(ids: Set(doc.layers.map(\.id)), name: "Row")!
        doc.setGroupLayout(id: main.id, kind: .stack)
        let componentID = doc.makeComponent(id: main.id)!
        #expect(slots(doc, componentID, on: main.id).contains(.padding))
    }

    // MARK: - What more room does where it IS offered

    /// The other half of the complaint: where room IS offered, turning it up
    /// makes the copy roomier and leaves it where it was put.
    @Test("More room on a copy makes it roomier and does not move it")
    func moreRoomMakesACopyRoomierWithoutMovingIt() {
        var c = drawnButton(surface: true)
        let property = c.doc.addComponentProperty(componentID: c.componentID,
                                                  target: c.main, kind: .number,
                                                  numberSlot: .padding)!
        let copy = c.doc.insertComponentInstance(of: c.componentID,
                                                 at: CGPoint(x: 200, y: 700))!
        c.doc.syncComponentInstances()
        let before = c.doc.layer(id: copy)!.localBounds
        c.doc.setInstanceOverride(instance: copy, property: property,
                                  value: .room(GroupPadding(48)))
        c.doc.syncComponentInstances()
        let after = c.doc.layer(id: copy)!.localBounds
        // Where it was placed, still.
        #expect(after.origin == before.origin)
        // Roomier: 32 more room on every side is 64 more across and down.
        #expect(after.width == before.width + 64)
        #expect(after.height == before.height + 64)
    }

    /// A drawing with a size of its own, whose only stretchy piece is the
    /// surface, is offered nothing either: the surface is painted to the box's
    /// own edges and the box is a number somebody typed, so the room has
    /// nowhere to go on either side.
    @Test("A fixed-size drawing whose only stretchy piece is the surface is not offered room")
    func aFixedDrawingWithOnlyASurfaceIsNotOfferedRoom() {
        var c = drawnButton(surface: true)
        c.doc.updateGroupLayout(id: c.main) { $0.width = 360; $0.height = 120 }
        #expect(slots(c.doc, c.componentID, on: c.main).contains(.padding) == false)
    }

    /// Give that same fixed drawing a piece stretched ONE way and the room is
    /// offered again: a hairline across a bar stands off both ends by it.
    @Test("A piece stretched one way answers to room at any size")
    func aPieceStretchedOneWayAnswersToRoom() {
        var c = drawnButton(surface: true)
        c.doc.updateGroupLayout(id: c.main) { $0.width = 360; $0.height = 120 }
        let label = c.doc.layer(id: c.main)!.children.first { $0.name == "Text" }!.id
        c.doc.updateLayer(id: label) { $0.placement = LayerPlacement(horizontal: .stretch) }
        #expect(slots(c.doc, c.componentID, on: c.main).contains(.padding))
    }
}
