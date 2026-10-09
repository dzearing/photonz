import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A component let go in Edit Original's space.
///
/// Found on 2026-10-09: with the Button's original open, a Button dragged off
/// the shelf landed loose on the page beside the drawing, a Card beside it did
/// the same, and Done folded both into the original. Every copy in the document
/// turned into a big box holding a Card and a copy of itself. The space holds
/// only the component, so what is let go there joins the drawing it lands on,
/// a copy of the component itself is refused, and the bare page beside the
/// drawing takes nothing.
struct EditingSpaceDropTests {

    /// A document holding a starter Badge and a starter Card, with the space
    /// for the Badge open.
    private func badgeSpace() -> (space: PhotonzDocument, drawing: UUID, room: CGRect) {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 1200, height: 900), pixelScale: 1)
        doc.insertStarterComponent(.badge, at: CGPoint(x: 300, y: 300))
        doc.insertStarterComponent(.card, at: CGPoint(x: 800, y: 300))
        guard let space = doc.editingSpace(forComponent: StarterComponent.badge.componentID),
              let drawing = space.layers.first,
              let room = space.canvasBounds(of: drawing.id)
        else { preconditionFailure("no space") }
        return (space, drawing.id, room)
    }

    private let badge = StarterComponent.badge.componentID
    private let card = StarterComponent.card.componentID

    @Test func aCopyOfTheComponentItselfIsRefusedOnItsDrawing() {
        let s = badgeSpace()
        let on = CGPoint(x: s.room.midX, y: s.room.midY)
        #expect(s.space.editingSpaceDrop(of: badge, at: on, editing: badge) == .holdsItself)
    }

    @Test func aCopyOfTheComponentItselfIsRefusedBesideItsDrawingToo() {
        let s = badgeSpace()
        let beside = CGPoint(x: s.room.maxX + 200, y: s.room.maxY + 200)
        #expect(s.space.editingSpaceDrop(of: badge, at: beside, editing: badge) == .holdsItself)
    }

    @Test func anotherComponentOnTheDrawingJoinsThatDrawing() {
        let s = badgeSpace()
        let on = CGPoint(x: s.room.midX, y: s.room.midY)
        #expect(s.space.editingSpaceDrop(of: card, at: on, editing: badge) == .into(s.drawing))
    }

    @Test func anotherComponentOnTheBarePageIsRefused() {
        let s = badgeSpace()
        let beside = CGPoint(x: s.room.maxX + 200, y: s.room.midY)
        #expect(s.space.editingSpaceDrop(of: card, at: beside, editing: badge) == .beside)
    }

    /// A starter this document has not taken yet arrives whole, so it has no
    /// original to reason about, and still may not land loose.
    @Test func aStarterNotYetTakenFollowsTheSameRule() {
        let s = badgeSpace()
        let button = StarterComponent.button.componentID
        let beside = CGPoint(x: s.room.maxX + 200, y: s.room.midY)
        let on = CGPoint(x: s.room.midX, y: s.room.midY)
        #expect(s.space.editingSpaceDrop(of: button, at: beside, editing: badge) == .beside)
        #expect(s.space.editingSpaceDrop(of: button, at: on, editing: badge) == .into(s.drawing))
    }

    /// A component that already holds a copy of the one being edited would
    /// hold itself once it went in, so it is refused for the same reason.
    @Test func aComponentHoldingACopyOfTheEditedOneIsRefused() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 1200, height: 900), pixelScale: 1)
        guard let badgeCopy = doc.insertStarterComponent(.badge, at: CGPoint(x: 300, y: 300)),
              let group = doc.groupLayers(ids: [badgeCopy], name: "Holder"),
              let holder = doc.makeComponent(id: group.id)
        else { Issue.record("could not build the holder"); return }
        doc.parkOriginals()
        guard let space = doc.editingSpace(forComponent: badge),
              let drawing = space.layers.first,
              let room = space.canvasBounds(of: drawing.id)
        else { Issue.record("no space"); return }
        let on = CGPoint(x: room.midX, y: room.midY)
        #expect(space.editingSpaceDrop(of: holder, at: on, editing: badge) == .holdsItself)
    }

    /// What the canvas says under the pointer: nothing for a drop that lands,
    /// and the reason, short, for one that does not.
    @Test func aRefusedDragSaysWhyInAFewWords() {
        #expect(EditingSpaceDrop.into(UUID()).note(component: "Button") == nil)
        #expect(EditingSpaceDrop.holdsItself.note(component: "Button") == "Cannot go inside itself")
        #expect(EditingSpaceDrop.beside.note(component: "Button") == "Drop it onto Button")
        #expect(EditingSpaceDrop.beside.note(component: nil) == "Drop it onto the drawing")
    }

    /// The drop the answer allows, made with the context it names, lands
    /// inside the drawing, and Done writes it back without growing anything
    /// else.
    @Test func aDropOnTheDrawingLandsInsideItAndComesBackInsideIt() {
        var s = badgeSpace()
        let on = CGPoint(x: s.room.midX, y: s.room.midY)
        guard case .into(let context) = s.space.editingSpaceDrop(of: card, at: on, editing: badge),
              let placed = s.space.insertComponentInstance(of: card, at: on, inside: context)
        else { Issue.record("not placed"); return }
        #expect(s.space.parentID(of: placed) == s.drawing)
        #expect(s.space.layers.count == 1)
    }

    /// A copy of the component itself left loose on the page by any other road
    /// (a paste, say) never folds into the original: that is the drawing that
    /// draws forever.
    @Test func aLooseCopyOfItselfIsLeftOutOnDone() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 1200, height: 900), pixelScale: 1)
        doc.insertStarterComponent(.badge, at: CGPoint(x: 300, y: 300))
        guard var space = doc.editingSpace(forComponent: badge),
              let room = space.canvasBounds(of: space.layers[0].id)
        else { Issue.record("no space"); return }
        let before = doc.mainComponent(componentID: badge)
        space.insertComponentInstance(of: badge, at: CGPoint(x: room.maxX + 200, y: room.maxY + 200))
        #expect(space.layers.count == 2)
        doc.returnFromEditingSpace(space, componentID: badge)
        let after = doc.mainComponent(componentID: badge)
        #expect(after?.children.count == before?.children.count)
        #expect(after?.localBounds.size == before?.localBounds.size)
        #expect(!(after?.selfAndDescendants.contains { $0.instanceOf == badge } ?? true))
    }
}
