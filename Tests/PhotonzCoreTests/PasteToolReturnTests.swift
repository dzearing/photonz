import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Pasting used to leave you holding whatever tool you had, so the obvious
/// next move — dragging the thing you just pasted — drew a rectangle instead.
/// A paste now hands you the pointer, and undoing that paste hands the tool
/// you were using back, so neither half is a surprise.
@Suite("A paste hands you the pointer, and undo gives your tool back")
struct PasteToolReturnTests {

    private let pasted = UUID()
    private let second = UUID()

    // MARK: - What a paste remembers

    @Test func pastingWhileDrawingRemembersTheToolItTookAway() {
        let memory = PasteToolReturn.after(pasting: pasted, holding: .rectangle, carrying: nil)
        #expect(memory == PasteToolReturn(layer: pasted, previous: .rectangle))
    }

    @Test func pastingWithThePointerAlreadyInHandRemembersNothing() {
        #expect(PasteToolReturn.after(pasting: pasted, holding: .select, carrying: nil) == nil)
    }

    /// Crop is a mode with a pending rectangle, and the paste threw that
    /// rectangle away. Coming back to a half-finished crop on undo would be a
    /// bigger surprise than the one this is here to prevent.
    @Test func pastingOutOfCropModeRemembersNothing() {
        #expect(PasteToolReturn.after(pasting: pasted, holding: .crop, carrying: nil) == nil)
    }

    @Test func aRunOfPastesKeepsTheToolTheFirstOneTookAway() {
        let first = PasteToolReturn.after(pasting: pasted, holding: .rectangle, carrying: nil)
        let after = PasteToolReturn.after(pasting: second, holding: .select, carrying: first)
        #expect(after == first)
        #expect(after?.layer == pasted, "the run ends at the FIRST paste, so that is the layer to watch")
    }

    @Test func pastingAgainAfterAnUndoStartsAFreshMemory() {
        let returned = PasteToolReturn(layer: pasted, previous: .rectangle, isReturned: true)
        let after = PasteToolReturn.after(pasting: second, holding: .rectangle, carrying: returned)
        #expect(after == PasteToolReturn(layer: second, previous: .rectangle))
    }

    // MARK: - Undo

    @Test func undoingThePasteGivesTheToolBack() {
        let memory = PasteToolReturn(layer: pasted, previous: .rectangle)
        #expect(memory.toolAfterUndo(pastedLayerGone: true, holding: .select) == .rectangle)
    }

    @Test func undoingSomethingElseLeavesThePointerInHand() {
        let memory = PasteToolReturn(layer: pasted, previous: .rectangle)
        #expect(memory.toolAfterUndo(pastedLayerGone: false, holding: .select) == nil)
    }

    @Test func aToolPickedByHandIsNeverTakenAway() {
        let memory = PasteToolReturn(layer: pasted, previous: .rectangle)
        #expect(memory.toolAfterUndo(pastedLayerGone: true, holding: .ellipse) == nil)
    }

    @Test func theToolComesBackOnlyOnce() {
        let memory = PasteToolReturn(layer: pasted, previous: .rectangle, isReturned: true)
        #expect(memory.toolAfterUndo(pastedLayerGone: true, holding: .select) == nil)
    }

    @Test func givingTheToolBackIsRecorded() {
        var memory = PasteToolReturn(layer: pasted, previous: .rectangle)
        memory.markReturned()
        #expect(memory.isReturned)
    }

    // MARK: - Redo

    @Test func redoingThePasteTakesThePointerBackUp() {
        let memory = PasteToolReturn(layer: pasted, previous: .rectangle, isReturned: true)
        #expect(memory.toolAfterRedo(pastedLayerBack: true, holding: .rectangle) == .select)
    }

    @Test func redoingWithoutTheLayerComingBackChangesNothing() {
        let memory = PasteToolReturn(layer: pasted, previous: .rectangle, isReturned: true)
        #expect(memory.toolAfterRedo(pastedLayerBack: false, holding: .rectangle) == nil)
    }

    @Test func aRedoWithThePointerAlreadyInHandChangesNothing() {
        let memory = PasteToolReturn(layer: pasted, previous: .rectangle, isReturned: true)
        #expect(memory.toolAfterRedo(pastedLayerBack: true, holding: .select) == nil)
    }

    @Test func redoOnlyMattersAfterAnUndoGaveTheToolBack() {
        let memory = PasteToolReturn(layer: pasted, previous: .rectangle)
        #expect(memory.toolAfterRedo(pastedLayerBack: true, holding: .rectangle) == nil)
    }

    // MARK: - The whole round trip

    @Test func pasteTwiceThenUndoTwiceLandsBackOnTheToolYouStartedWith() {
        var memory = PasteToolReturn.after(pasting: pasted, holding: .rectangle, carrying: nil)
        memory = PasteToolReturn.after(pasting: second, holding: .select, carrying: memory)
        // Undoing the second paste: the first copy is still standing, so the
        // pointer stays in hand to move it.
        #expect(memory?.toolAfterUndo(pastedLayerGone: false, holding: .select) == nil)
        // Undoing the first takes the last copy away, and the rectangle tool
        // comes back with it.
        #expect(memory?.toolAfterUndo(pastedLayerGone: true, holding: .select) == .rectangle)
    }
}
