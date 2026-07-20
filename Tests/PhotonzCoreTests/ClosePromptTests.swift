import CoreGraphics
import Testing
@testable import PhotonzCore

/// The window-close decision: prompt exactly when closing would lose work —
/// the current document differs from the last saved/opened baseline.
struct ClosePromptTests {

    private func baseDocument() -> PhotonzDocument {
        PhotonzDocument.withBaseImage(ImageRef(pixelSize: CGSize(width: 100, height: 80)), pixelScale: 1)
    }

    @Test func noDocumentNeverPrompts() {
        #expect(ClosePrompt.needsSavePrompt(current: nil, savedBaseline: nil) == false)
        #expect(ClosePrompt.needsSavePrompt(current: nil, savedBaseline: baseDocument()) == false)
    }

    @Test func unchangedDocumentDoesNotPrompt() {
        let doc = baseDocument()
        #expect(ClosePrompt.needsSavePrompt(current: doc, savedBaseline: doc) == false)
    }

    @Test func editedDocumentPrompts() {
        let doc = baseDocument()
        var history = History(document: doc)
        history.perform { $0.addLayer(Layer(name: "Line", content: .annotation(AnnotationContent(shape: .line)), frame: CGRect(x: 0, y: 0, width: 10, height: 10))) }
        #expect(ClosePrompt.needsSavePrompt(current: history.current, savedBaseline: doc))
    }

    @Test func undoBackToBaselineIsCleanAgain() {
        let doc = baseDocument()
        var history = History(document: doc)
        history.perform { $0.addLayer(Layer(name: "Line", content: .annotation(AnnotationContent(shape: .line)), frame: CGRect(x: 0, y: 0, width: 10, height: 10))) }
        history.undo()
        #expect(ClosePrompt.needsSavePrompt(current: history.current, savedBaseline: doc) == false)
    }

    @Test func saveUpdatesBaselineSoFurtherCloseIsClean() {
        let doc = baseDocument()
        var history = History(document: doc)
        history.perform { $0.addLayer(Layer(name: "Line", content: .annotation(AnnotationContent(shape: .line)), frame: CGRect(x: 0, y: 0, width: 10, height: 10))) }
        let saved = history.current // markSaved() adopts the current document
        #expect(ClosePrompt.needsSavePrompt(current: history.current, savedBaseline: saved) == false)
    }

    @Test func documentWithNoBaselinePrompts() {
        // A document that was never saved/opened-from-disk (nil baseline) has
        // content worth protecting.
        #expect(ClosePrompt.needsSavePrompt(current: baseDocument(), savedBaseline: nil))
    }
}
