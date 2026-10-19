import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

@Suite("History")
struct HistoryTests {

    private func makeHistory() -> History {
        History(document: PhotonzDocument(canvasSize: CGSize(width: 100, height: 100)))
    }

    @Test func performRecordsUndoableStep() {
        var history = makeHistory()
        history.perform { $0.resize(to: CGSize(width: 50, height: 50)) }
        #expect(history.current.canvasSize == CGSize(width: 50, height: 50))
        #expect(history.canUndo)

        history.undo()
        #expect(history.current.canvasSize == CGSize(width: 100, height: 100))
        #expect(!history.canUndo)
        #expect(history.canRedo)

        history.redo()
        #expect(history.current.canvasSize == CGSize(width: 50, height: 50))
    }

    @Test func noOpEditsAreNotRecorded() {
        var history = makeHistory()
        history.perform { _ in }
        #expect(!history.canUndo)
    }

    @Test func newEditClearsRedoStack() {
        var history = makeHistory()
        history.perform { $0.resize(to: CGSize(width: 50, height: 50)) }
        history.undo()
        history.perform { $0.resize(to: CGSize(width: 25, height: 25)) }
        #expect(!history.canRedo)
        #expect(history.current.canvasSize == CGSize(width: 25, height: 25))
    }

    @Test func undoLimitDropsOldestSnapshots() {
        var history = History(document: PhotonzDocument(canvasSize: CGSize(width: 1, height: 1)), limit: 3)
        for i in 2...10 {
            history.perform { $0.canvasSize = CGSize(width: CGFloat(i), height: 1) }
        }
        var undos = 0
        while history.canUndo {
            history.undo()
            undos += 1
        }
        #expect(undos == 3)
        #expect(history.current.canvasSize.width == 7)
    }
}

/// One command an agent runs is one undo step, however many edits it lands
/// (`docs/design/agent-mcp.md`, slice 2): History folds them together.
@Suite("History: folding a command's edits into one step")
struct HistorySquashTests {

    private func makeHistory() -> History {
        History(document: PhotonzDocument(canvasSize: CGSize(width: 100, height: 100)))
    }

    @Test("Two edits after a mark undo together, back to the state at the mark")
    func twoEditsBecomeOne() {
        var history = makeHistory()
        history.perform { $0.resize(to: CGSize(width: 90, height: 90)) }
        let mark = history.mark
        history.perform { $0.resize(to: CGSize(width: 50, height: 50)) }
        history.perform { $0.resize(to: CGSize(width: 25, height: 25)) }
        #expect(history.squash(since: mark) == 1)
        history.undo()
        #expect(history.current.canvasSize == CGSize(width: 90, height: 90))
        history.redo()
        #expect(history.current.canvasSize == CGSize(width: 25, height: 25))
        history.undo()
        history.undo()
        #expect(history.current.canvasSize == CGSize(width: 100, height: 100))
        #expect(!history.canUndo)
    }

    @Test("One edit, or none, is left as it is")
    func oneOrNoneIsUntouched() {
        var history = makeHistory()
        let before = history.mark
        #expect(history.squash(since: before) == 0)
        history.perform { $0.resize(to: CGSize(width: 50, height: 50)) }
        #expect(history.squash(since: before) == 0)
        history.undo()
        #expect(history.current.canvasSize == CGSize(width: 100, height: 100))
    }

    @Test("A selection step recorded along the way folds in too")
    func selectionStepsFold() {
        var history = makeHistory()
        let mark = history.mark
        let was = history.selection
        history.syncSelection(SelectionSnapshot())
        history.perform { $0.resize(to: CGSize(width: 50, height: 50)) }
        var moved = history.selection
        moved.targetsPixels = true
        history.syncSelection(moved)
        history.recordSelectionChange(from: was)
        #expect(history.squash(since: mark) == 1)
        history.undo()
        #expect(history.current.canvasSize == CGSize(width: 100, height: 100))
        #expect(!history.canUndo)
    }

    @Test("An undo since the mark leaves the stack alone")
    func undoSinceTheMarkIsLeftAlone() {
        var history = makeHistory()
        history.perform { $0.resize(to: CGSize(width: 90, height: 90)) }
        let mark = history.mark
        history.perform { $0.resize(to: CGSize(width: 50, height: 50)) }
        history.undo()
        history.perform { $0.resize(to: CGSize(width: 25, height: 25)) }
        history.perform { $0.resize(to: CGSize(width: 20, height: 20)) }
        #expect(history.squash(since: mark) == 0)
    }

    @Test("Edits that pushed the oldest steps off the stack still fold into one")
    func foldsPastTheLimit() {
        var history = History(document: PhotonzDocument(canvasSize: CGSize(width: 1, height: 1)), limit: 3)
        let mark = history.mark
        for i in 2...6 { history.perform { $0.resize(to: CGSize(width: i, height: i)) } }
        history.squash(since: mark)
        history.undo()
        #expect(!history.canUndo)
        #expect(history.current.canvasSize.width < 6)
    }
}
