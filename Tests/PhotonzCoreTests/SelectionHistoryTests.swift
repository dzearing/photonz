import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Undo puts a marquee back the way it puts everything else back: the region
/// rides along in the same stack as the picture, so one ⌘Z always steps back
/// over whatever you did last, whether that was paint or a selection.
@Suite("Selection history")
struct SelectionHistoryTests {

    private func makeHistory() -> History {
        History(document: PhotonzDocument(canvasSize: CGSize(width: 100, height: 100)))
    }

    private func region(_ x: CGFloat, _ y: CGFloat) -> SelectionSnapshot {
        SelectionSnapshot(region: SelectionRegion.rect(CGRect(x: x, y: y, width: 10, height: 10)),
                          targetsPixels: true)
    }

    @Test func startsWithNoSelection() {
        let history = makeHistory()
        #expect(history.selection == SelectionSnapshot())
        #expect(!history.canUndo)
    }

    @Test func drawingASelectionIsUndoable() {
        var history = makeHistory()
        let before = history.selection
        history.syncSelection(region(0, 0))
        history.recordSelectionChange(from: before)
        #expect(history.canUndo)

        let picture = history.current
        history.undo()
        #expect(history.selection.region == nil)
        #expect(history.current == picture) // the picture never moved
    }

    @Test func redoPutsTheSelectionBack() {
        var history = makeHistory()
        let before = history.selection
        history.syncSelection(region(0, 0))
        history.recordSelectionChange(from: before)
        history.undo()
        history.redo()
        #expect(history.selection == region(0, 0))
    }

    @Test func clearingASelectionIsUndoable() {
        var history = makeHistory()
        history.syncSelection(region(0, 0))
        let drawn = history.selection
        history.syncSelection(SelectionSnapshot())
        history.recordSelectionChange(from: drawn)

        history.undo()
        #expect(history.selection == drawn)
    }

    @Test func aSelectionThatDidNotChangeIsNotAStep() {
        var history = makeHistory()
        history.syncSelection(region(0, 0))
        history.recordSelectionChange(from: region(0, 0))
        #expect(!history.canUndo)
    }

    @Test func syncingWithoutRecordingIsNotAStep() {
        var history = makeHistory()
        history.syncSelection(region(0, 0))
        #expect(!history.canUndo)
        #expect(history.selection == region(0, 0))
    }

    @Test func aPictureEditCarriesTheMarqueeThatWasOnScreen() {
        var history = makeHistory()
        history.syncSelection(region(0, 0))
        history.perform { $0.resize(to: CGSize(width: 50, height: 50)) }
        // The edit leaves the marquee alone...
        #expect(history.selection == region(0, 0))
        history.syncSelection(SelectionSnapshot()) // ...and the command then drops it
        history.undo()
        // ...so stepping back over the edit brings it with it.
        #expect(history.selection == region(0, 0))
        #expect(history.current.canvasSize == CGSize(width: 100, height: 100))
    }

    @Test func selectionStepsAndPictureStepsInterleave() {
        var history = makeHistory()
        history.syncSelection(region(0, 0))
        history.recordSelectionChange(from: SelectionSnapshot())
        history.perform { $0.resize(to: CGSize(width: 50, height: 50)) }

        history.undo() // the picture edit, marquee untouched
        #expect(history.current.canvasSize == CGSize(width: 100, height: 100))
        #expect(history.selection == region(0, 0))

        history.undo() // the selection, picture untouched
        #expect(history.current.canvasSize == CGSize(width: 100, height: 100))
        #expect(history.selection.region == nil)

        history.redo()
        #expect(history.selection == region(0, 0))
        history.redo()
        #expect(history.current.canvasSize == CGSize(width: 50, height: 50))
    }

    @Test func recordingASelectionClearsTheRedoStack() {
        var history = makeHistory()
        history.perform { $0.resize(to: CGSize(width: 50, height: 50)) }
        history.undo()
        #expect(history.canRedo)
        history.syncSelection(region(0, 0))
        history.recordSelectionChange(from: SelectionSnapshot())
        #expect(!history.canRedo)
    }

    // MARK: - A burst of nudges is one step

    @Test func aRunOfNudgesRecordsOneStep() {
        var history = makeHistory()
        history.syncSelection(region(0, 0))
        history.recordSelectionChange(from: SelectionSnapshot())
        var previous = history.selection
        for step in 1...5 {
            history.syncSelection(region(CGFloat(step), 0))
            history.recordSelectionChange(from: previous, run: "nudge")
            previous = history.selection
        }
        history.undo()
        #expect(history.selection == region(0, 0)) // back to where the run began
        history.redo()
        #expect(history.selection == region(5, 0)) // and forward to where it ended
    }

    @Test func aPictureEditEndsTheRun() {
        var history = makeHistory()
        history.syncSelection(region(0, 0))
        history.recordSelectionChange(from: SelectionSnapshot(), run: "nudge")
        history.perform { $0.resize(to: CGSize(width: 50, height: 50)) }
        let afterEdit = history.selection
        history.syncSelection(region(1, 0))
        history.recordSelectionChange(from: afterEdit, run: "nudge")

        history.undo()
        #expect(history.selection == region(0, 0))
        history.undo()
        #expect(history.current.canvasSize == CGSize(width: 100, height: 100))
    }

    @Test func aDifferentRunStartsItsOwnStep() {
        var history = makeHistory()
        history.syncSelection(region(0, 0))
        history.recordSelectionChange(from: SelectionSnapshot(), run: "nudge")
        history.syncSelection(region(1, 0))
        history.recordSelectionChange(from: region(0, 0), run: "typed")
        history.undo()
        #expect(history.selection == region(0, 0))
    }

    @Test func anUnnamedChangeIsAlwaysItsOwnStep() {
        var history = makeHistory()
        history.syncSelection(region(0, 0))
        history.recordSelectionChange(from: SelectionSnapshot())
        history.syncSelection(region(1, 0))
        history.recordSelectionChange(from: region(0, 0))
        history.undo()
        #expect(history.selection == region(0, 0))
    }

    @Test func undoEndsTheRunSoTheNextNudgeStandsAlone() {
        var history = makeHistory()
        history.syncSelection(region(0, 0))
        history.recordSelectionChange(from: SelectionSnapshot(), run: "nudge")
        history.undo()
        history.syncSelection(region(9, 9))
        history.recordSelectionChange(from: SelectionSnapshot(), run: "nudge")
        history.undo()
        #expect(history.selection.region == nil)
    }
}
