import Foundation
import CoreGraphics
import Testing
@testable import PhotonzCore

/// Typing over a piece inside a copy (`docs/design/ui-building.md`, step C6).
///
/// A copy takes its contents from its original every time the document is put
/// back in step, so anything written straight onto one of those pieces is
/// thrown away on the next edit. These tests pin the two answers that are
/// allowed instead: the edit lands on the copy's own knob and stays, or it is
/// refused with a reason a person can act on.
struct ComponentPieceEditingTests {

    private func box(_ name: String, _ rect: CGRect) -> Layer {
        Layer(name: name, content: .annotation(AnnotationContent(shape: .rectangle,
                                                                 start: .zero,
                                                                 end: CGPoint(x: rect.width, y: rect.height))),
              frame: rect)
    }

    private func text(_ name: String, _ string: String, _ rect: CGRect) -> Layer {
        Layer(name: name, content: .text(TextContent(string: string)), frame: rect)
    }

    /// A component "Button" holding a box and a "Label" that says "Button",
    /// with one copy of it placed on the canvas.
    private func withCopy(exposingWording: Bool = true)
    -> (doc: PhotonzDocument, componentID: UUID, main: UUID, labelID: UUID,
        boxID: UUID, copy: UUID, piece: UUID) {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600),
                                  layers: [box("Box", CGRect(x: 10, y: 10, width: 120, height: 40)),
                                           text("Label", "Button", CGRect(x: 30, y: 20, width: 60, height: 20))])
        let boxID = doc.layers[0].id
        let labelID = doc.layers[1].id
        let main = doc.groupLayers(ids: [boxID, labelID], name: "Button")!
        let componentID = doc.makeComponent(id: main.id)!
        if exposingWording {
            _ = doc.addComponentProperty(componentID: componentID, target: labelID, kind: .text)
        }
        let copy = doc.insertComponentInstance(of: componentID, at: CGPoint(x: 400, y: 300))!
        let piece = ComponentIdentity.derived(instance: copy, source: labelID)
        return (doc, componentID, main.id, labelID, boxID, copy, piece)
    }

    // MARK: - Which copy a piece belongs to

    /// A piece knows the copy it is part of, the original that copy follows,
    /// and which layer of the original it is a picture of.
    @Test func aPieceKnowsWhereItCameFrom() {
        let c = withCopy()
        let piece = c.doc.componentPiece(of: c.piece)
        #expect(piece?.instance == c.copy)
        #expect(piece?.componentID == c.componentID)
        #expect(piece?.source == c.labelID)
        #expect(piece?.isNested == false)
    }

    /// A layer that is not inside a copy is not a piece, so nothing about
    /// ordinary editing changes.
    @Test func anOrdinaryLayerIsNotAPiece() {
        let c = withCopy()
        #expect(c.doc.componentPiece(of: c.labelID) == nil)
        #expect(c.doc.componentPiece(of: c.copy) == nil)
        #expect(c.doc.wordingEdit(of: c.labelID) == .ordinary)
    }

    // MARK: - The edit is routed

    @Test func typingOverAPieceWithAKnobLandsOnThatKnob() {
        let c = withCopy()
        guard case .knob(let piece, let property) = c.doc.wordingEdit(of: c.piece) else {
            Issue.record("a label with a wording knob should route to it")
            return
        }
        #expect(piece.instance == c.copy)
        #expect(property.kind == .text)
        #expect(property.target == c.labelID)
    }

    /// The whole point: the words survive the next time the copy is put back
    /// in step with its original, which is what threw them away before.
    @Test func routedWordsSurviveTheNextSync() {
        var c = withCopy()
        let landed = c.doc.setPieceWording(of: c.piece, to: "Save")
        #expect(landed)
        _ = c.doc.syncComponentInstances()
        let piece = c.doc.layer(id: c.piece)
        #expect(piece?.text?.string == "Save")
        // ...and it is stored as the copy's own answer, not written into the
        // picture, so it is one value a person can put back.
        #expect(c.doc.instanceOverrides(instance: c.copy).count == 1)
    }

    /// Writing straight onto the piece is what used to happen, and is exactly
    /// what the sync undoes. This test exists so nobody re-introduces it.
    @Test func writingStraightOntoAPieceIsThrownAway() {
        var c = withCopy()
        c.doc.updateLayer(id: c.piece) { $0.content = .text(TextContent(string: "Save")) }
        _ = c.doc.syncComponentInstances()
        #expect(c.doc.layer(id: c.piece)?.text?.string == "Button")
    }

    /// Emptying the field puts the piece back to what the original says rather
    /// than deleting a piece that cannot be deleted.
    @Test func emptyingAPieceFollowsTheOriginalAgain() {
        var c = withCopy()
        let landed = c.doc.setPieceWording(of: c.piece, to: "Save")
        #expect(landed)
        let reverted = c.doc.clearPieceWording(of: c.piece)
        #expect(reverted)
        _ = c.doc.syncComponentInstances()
        #expect(c.doc.layer(id: c.piece)?.text?.string == "Button")
        #expect(c.doc.instanceOverrides(instance: c.copy).isEmpty)
    }

    /// Editing the original still reaches every copy, and a copy that has
    /// answered a knob keeps its own answer.
    @Test func theOriginalStillLeadsAndAnAnswerIsKept() {
        var c = withCopy()
        let second = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 600, y: 300))!
        let landed = c.doc.setPieceWording(of: c.piece, to: "Save")
        #expect(landed)
        c.doc.updateLayer(id: c.boxID) { $0.frame = CGRect(x: 10, y: 10, width: 200, height: 40) }
        c.doc.updateLayer(id: c.labelID) { $0.content = .text(TextContent(string: "Press")) }
        _ = c.doc.syncComponentInstances()
        let othersLabel = ComponentIdentity.derived(instance: second, source: c.labelID)
        #expect(c.doc.layer(id: othersLabel)?.text?.string == "Press")
        #expect(c.doc.layer(id: c.piece)?.text?.string == "Save")
        let otherBox = ComponentIdentity.derived(instance: second, source: c.boxID)
        #expect(c.doc.layer(id: otherBox)?.frame.width == 200)
    }

    // MARK: - The edit is refused, with a reason

    @Test func aPieceWithNoKnobIsRefusedAndOffersToExposeOne() {
        let c = withCopy(exposingWording: false)
        guard case .refused(let refusal) = c.doc.wordingEdit(of: c.piece) else {
            Issue.record("a label with no wording knob cannot be typed over")
            return
        }
        #expect(refusal.remedy == .exposeWording)
        #expect(refusal.component == "Button")
        #expect(refusal.pieceName == "Label")
        #expect(!refusal.detail.isEmpty)
        #expect(!refusal.title.isEmpty)
    }

    /// A piece that could never take a wording knob has only one way out, and
    /// the message says that one rather than offering a knob that is refused.
    @Test func aPieceThatCannotTakeAKnobOffersDetachInstead() {
        let c = withCopy(exposingWording: false)
        let boxPiece = ComponentIdentity.derived(instance: c.copy, source: c.boxID)
        guard case .refused(let refusal) = c.doc.wordingEdit(of: boxPiece) else {
            Issue.record("a box has no wording, so there is nothing to type")
            return
        }
        #expect(refusal.remedy == .detach)
    }

    @Test func aLockedCopyRefusesAndSaysToUnlockIt() {
        var c = withCopy()
        c.doc.updateLayer(id: c.copy) { $0.isLocked = true }
        guard case .refused(let refusal) = c.doc.wordingEdit(of: c.piece) else {
            Issue.record("a locked copy takes no edits at all")
            return
        }
        #expect(refusal.remedy == .unlock)
    }

    /// A copy inside another copy is rebuilt by the OUTER copy's sync, which
    /// would throw away an answer given to the inner one. It is refused.
    @Test func aPieceInsideANestedCopyIsRefused() {
        var c = withCopy()
        // A second component that holds a copy of the first.
        let inner = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 100, y: 400))!
        let shell = c.doc.groupLayers(ids: [inner], name: "Row")!
        let shellComponent = c.doc.makeComponent(id: shell.id)!
        let outer = c.doc.insertComponentInstance(of: shellComponent, at: CGPoint(x: 500, y: 500))!
        let nestedCopy = ComponentIdentity.derived(instance: outer, source: inner)
        let nestedPiece = ComponentIdentity.derived(instance: nestedCopy, source: c.labelID)
        #expect(c.doc.componentPiece(of: nestedPiece)?.isNested == true)
        guard case .refused(let refusal) = c.doc.wordingEdit(of: nestedPiece) else {
            Issue.record("a piece two copies deep cannot keep an answer")
            return
        }
        #expect(refusal.remedy == .detach)
    }

    @Test func aRefusedPieceTakesNoWords() {
        var c = withCopy(exposingWording: false)
        let landed = c.doc.setPieceWording(of: c.piece, to: "Save")
        #expect(!landed)
        _ = c.doc.syncComponentInstances()
        #expect(c.doc.layer(id: c.piece)?.text?.string == "Button")
    }

    // MARK: - Exposing a knob from the copy

    /// The way out of a refusal: the piece you were typing on becomes
    /// adjustable, on the original, and the copy can answer it straight away.
    @Test func exposingAKnobFromAPieceMakesItTypeable() {
        var c = withCopy(exposingWording: false)
        #expect(c.doc.canExposePieceWording(of: c.piece))
        let property = c.doc.exposePieceWording(of: c.piece)
        #expect(property != nil)
        #expect(c.doc.componentProperties(of: c.componentID).map(\.target) == [c.labelID])
        guard case .knob = c.doc.wordingEdit(of: c.piece) else {
            Issue.record("the piece should be typeable the moment its knob exists")
            return
        }
        let landed = c.doc.setPieceWording(of: c.piece, to: "Save")
        #expect(landed)
        _ = c.doc.syncComponentInstances()
        #expect(c.doc.layer(id: c.piece)?.text?.string == "Save")
    }

    @Test func aPieceWithNoWordingCannotExposeOne() {
        var c = withCopy(exposingWording: false)
        let boxPiece = ComponentIdentity.derived(instance: c.copy, source: c.boxID)
        #expect(!c.doc.canExposePieceWording(of: boxPiece))
        let exposed = c.doc.exposePieceWording(of: boxPiece)
        #expect(exposed == nil)
    }

    // MARK: - A starter arrives ready

    /// The reported case, end to end: a Button dragged off the shelf is typed
    /// over and keeps what was typed.
    @Test func aStarterButtonIsTypeableTheMomentItLands() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600), layers: [])
        // The first drop puts the original on the canvas; the second is a copy
        // of it, which is the thing the report was about.
        _ = doc.insertStarterComponent(.button, at: CGPoint(x: 200, y: 300))
        let copy = doc.insertStarterComponent(.button, at: CGPoint(x: 400, y: 300))!
        let componentID = StarterComponent.button.componentID
        let main = doc.mainComponent(componentID: componentID)!
        let label = main.children.first { $0.name == "Label" }!
        let piece = ComponentIdentity.derived(instance: copy, source: label.id)
        guard case .knob(_, let property) = doc.wordingEdit(of: piece) else {
            Issue.record("a starter button arrives with a wording knob on its label")
            return
        }
        #expect(property.name == "Label")
        let landed = doc.setPieceWording(of: piece, to: "Save")
        #expect(landed)
        _ = doc.syncComponentInstances()
        #expect(doc.layer(id: piece)?.text?.string == "Save")
    }

    /// Everything else about a piece is the original's too: moved, recolored
    /// or restyled, it is put straight back on the next sync. This is why the
    /// panel offers a piece nothing but the copy's knobs.
    @Test func movingAPieceIsThrownAwayToo() {
        var c = withCopy()
        let before = c.doc.layer(id: c.piece)!.frame
        c.doc.updateLayer(id: c.piece) { $0.frame = $0.frame.offsetBy(dx: 40, dy: 0) }
        _ = c.doc.syncComponentInstances()
        #expect(c.doc.layer(id: c.piece)?.frame == before)
    }
}
