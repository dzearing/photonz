import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Renaming a layer killed the app outright for a day (2026-09-17), and the
/// reason was not the rename.
///
/// The app keeps its undo stack in one property and reads the document back
/// out of that same property. Recording an edit used to hand the caller's
/// closure to a *mutating* call on the stack, which holds that property
/// exclusively for as long as the closure runs, so the first closure that
/// wanted to look at the document while making its edit — rename, which needs
/// the words read off a picture so pressing Return on an untouched field is
/// not a rename — read the property that was already being written and Swift
/// stopped the process dead.
///
/// The fix is that working an edit out and recording it are two acts. While
/// the edit is being worked out the stack is only being READ, so anything the
/// closure wants to read alongside it is free to. These tests hold that shape
/// in place: the first one is the crash itself, and it does not fail politely
/// if it comes back — the test run aborts, which is exactly what the app did.
@Suite("An edit can read the document while it is being made")
struct HistoryEditReadsTheDocumentTests {

    /// Stands in for EditorState: the stack lives in a property, the document
    /// is read back out of that same property, and an edit goes through both.
    private final class Editor {
        var history: History

        init(_ document: PhotonzDocument) { history = History(document: document) }

        var document: PhotonzDocument { history.current }

        /// The shape `EditorState.perform` uses, and the only safe one for a
        /// closure that reads `document`.
        @discardableResult
        func perform(_ mutate: (inout PhotonzDocument) -> Void) -> EditReport {
            let prepared = history.preparing(mutate)
            return history.record(prepared)
        }

        /// The same two acts for a change from outside the document.
        @discardableResult
        func applyOutsideHistory(_ update: (inout PhotonzDocument) -> Void) -> Bool {
            guard let change = history.preparingOutsideHistory(update) else { return false }
            history.record(change)
            return true
        }
    }

    private func document() -> PhotonzDocument {
        var document = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300))
        document.addLayer(Layer(name: "Rectangle",
                                content: .image(ImageRef(pixelSize: CGSize(width: 10, height: 10))),
                                frame: CGRect(x: 0, y: 0, width: 10, height: 10)))
        return document
    }

    @Test("Renaming a layer while reading the document does not abort")
    func renameReadsTheDocumentMidEdit() {
        let editor = Editor(document())
        let id = editor.document.layers[0].id
        var sawTheOldName: String?

        editor.perform { doc in
            // The live read that used to be a crash: same property the stack
            // is in, while the edit that stack is recording runs.
            sawTheOldName = editor.document.layer(id: id)?.name
            doc.renameLayer(id: id, to: "Header")
        }

        #expect(sawTheOldName == "Rectangle")
        #expect(editor.document.layer(id: id)?.name == "Header")
        #expect(editor.history.canUndo)

        editor.history.undo()
        #expect(editor.document.layer(id: id)?.name == "Rectangle")
    }

    @Test("A change from outside the document can read it too")
    func outsideChangeReadsTheDocumentMidEdit() {
        let editor = Editor(document())
        let id = editor.document.layers[0].id
        var canvasSeen: CGSize?

        let moved = editor.applyOutsideHistory { doc in
            canvasSeen = editor.document.canvasSize
            doc.updateLayer(id: id) { $0.name = "Read" }
        }

        #expect(moved)
        #expect(canvasSeen == CGSize(width: 400, height: 300))
        #expect(editor.document.layer(id: id)?.name == "Read")
        #expect(!editor.history.canUndo)
    }

    @Test("Working an edit out leaves the stack alone until it is recorded")
    func preparingRecordsNothing() {
        var history = History(document: document())
        let prepared = history.preparing { $0.resize(to: CGSize(width: 50, height: 50)) }

        #expect(history.current.canvasSize == CGSize(width: 400, height: 300))
        #expect(!history.canUndo)

        history.record(prepared)
        #expect(history.current.canvasSize == CGSize(width: 50, height: 50))
        #expect(history.canUndo)
    }

    @Test("The two acts record exactly what perform records")
    func twoActsMatchPerform() {
        let start = document()
        var inOne = History(document: start)
        var inTwo = History(document: start)

        inOne.perform { $0.resize(to: CGSize(width: 50, height: 50)) }
        inTwo.record(inTwo.preparing { $0.resize(to: CGSize(width: 50, height: 50)) })
        #expect(inOne.current == inTwo.current)
        #expect(inOne.canUndo == inTwo.canUndo)

        // An edit that changes nothing is not a step either way.
        inOne.perform { _ in }
        inTwo.record(inTwo.preparing { _ in })
        inOne.undo()
        inTwo.undo()
        #expect(inOne.current == inTwo.current)
        #expect(!inOne.canUndo)
        #expect(!inTwo.canUndo)
    }

    @Test("A change from outside that changes nothing is not applied")
    func outsideChangeThatMovesNothing() {
        let history = History(document: document())
        #expect(history.preparingOutsideHistory { _ in } == nil)
    }
}
