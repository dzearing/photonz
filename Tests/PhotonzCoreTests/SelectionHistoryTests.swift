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

    /// A picture-sized layer of the kind a rubber band sweeps up.
    private func sweptLayer(_ name: String) -> Layer {
        let frame = CGRect(x: 100, y: 100, width: 200, height: 200)
        let annotation = AnnotationContent(shape: .rectangle, start: .zero,
                                           end: CGPoint(x: frame.width, y: frame.height))
        return Layer(name: name, content: .annotation(annotation), frame: frame)
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

    // MARK: - A sweep that deletes what it caught

    /// Sweeping a band round two pictures and pressing ⌫ removes both and
    /// drops the band. The band goes because it no longer describes anything,
    /// so it has to ride WITH the delete: one ⌘Z brings the pictures back and
    /// hands the outline back with them.
    ///
    /// Recorded the other way round (the clear as a step of its own, on top of
    /// the delete) the first press gave back only the outline and left the two
    /// pictures deleted, which reads as undo refusing to bring your work back
    /// (reported 2026-09-08, `deleteLayers`). `bandThenClearAsItsOwnStepBuriesTheDelete`
    /// below is that shape, kept so the cost of getting it wrong is written down.
    @Test func aSweepDeleteHandsBackThePicturesAndTheBandInOnePress() {
        var history = History(document: PhotonzDocument(canvasSize: CGSize(width: 1200, height: 800),
                                                        layers: [sweptLayer("left"), sweptLayer("right")]))
        let band = region(80, 80)
        history.syncSelection(band) // the band the sweep left on screen
        let ids = Set(history.current.layers.map(\.id))

        history.perform { $0.removeLayers(ids: ids) }
        history.syncSelection(SelectionSnapshot()) // the delete consumed it: no step of its own
        #expect(history.current.layers.isEmpty)
        #expect(history.selection.region == nil)

        history.undo()
        #expect(history.current.layers.map(\.name) == ["left", "right"])
        #expect(history.selection == band)
    }

    @Test func bandThenClearAsItsOwnStepBuriesTheDelete() {
        var history = History(document: PhotonzDocument(canvasSize: CGSize(width: 1200, height: 800),
                                                        layers: [sweptLayer("left"), sweptLayer("right")]))
        let band = region(80, 80)
        history.syncSelection(band)
        let ids = Set(history.current.layers.map(\.id))

        history.perform { $0.removeLayers(ids: ids) }
        history.syncSelection(SelectionSnapshot())
        history.recordSelectionChange(from: band) // the mistake: a second step

        history.undo()
        #expect(history.selection == band)          // the outline is back...
        #expect(history.current.layers.isEmpty)     // ...and the pictures are still gone
        history.undo()
        #expect(history.current.layers.count == 2)  // only the second press reaches them
    }

    // MARK: - A sweep that stacks what it caught

    /// Sweeping a band round two pictures and pressing Stack Selection makes
    /// them one stack and drops the band. Same rule as the delete above: the
    /// band no longer describes anything, so it rides WITH the stack and one
    /// ⌘Z takes the stack apart and hands the outline back with it.
    ///
    /// Recorded the other way round the first press left the stack standing
    /// and gave back only the outline, which reads as undo doing nothing at
    /// all (reported 2026-09-08, `stackSelection`).
    @Test func aStackMadeFromABandComesApartInOnePress() {
        var history = History(document: PhotonzDocument(canvasSize: CGSize(width: 1200, height: 800),
                                                        layers: [sweptLayer("left"), sweptLayer("right")]))
        let band = region(80, 80)
        history.syncSelection(band) // the band the sweep left on screen
        let ids = Set(history.current.layers.map(\.id))

        history.perform { _ = $0.stackSelection(ids: ids, kind: .stack) }
        history.syncSelection(SelectionSnapshot()) // the stack consumed it: no step of its own
        #expect(history.current.layers.count == 1)
        #expect(history.current.layers[0].isGroup)
        #expect(history.selection.region == nil)

        history.undo()
        #expect(history.current.layers.map(\.name) == ["left", "right"])
        #expect(history.selection == band)
    }

    @Test func aStackFromABandRedoesInOnePressToo() {
        var history = History(document: PhotonzDocument(canvasSize: CGSize(width: 1200, height: 800),
                                                        layers: [sweptLayer("left"), sweptLayer("right")]))
        history.syncSelection(region(80, 80))
        let ids = Set(history.current.layers.map(\.id))
        history.perform { _ = $0.stackSelection(ids: ids, kind: .stack) }
        history.syncSelection(SelectionSnapshot())

        history.undo()
        history.redo()
        #expect(history.current.layers.count == 1)
        #expect(history.selection.region == nil)
    }

    @Test func aSweepDeleteRedoesInOnePressToo() {
        var history = History(document: PhotonzDocument(canvasSize: CGSize(width: 1200, height: 800),
                                                        layers: [sweptLayer("left"), sweptLayer("right")]))
        history.syncSelection(region(80, 80))
        let ids = Set(history.current.layers.map(\.id))
        history.perform { $0.removeLayers(ids: ids) }
        history.syncSelection(SelectionSnapshot())

        history.undo()
        history.redo()
        #expect(history.current.layers.isEmpty)
        #expect(history.selection.region == nil)
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
