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
