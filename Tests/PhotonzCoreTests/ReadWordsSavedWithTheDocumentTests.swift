import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// What a reading found is saved with the document, so opening a separated
/// file is free and a row keeps the name you saw last time
/// (`ReadWords.swift`).
@Suite("What a reading found is saved with the document")
struct ReadWordsSavedWithTheDocumentTests {

    private func picture(_ n: Int) -> ImageRef {
        ImageRef(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000\(String(format: "%02d", n))")!,
                 pixelSize: CGSize(width: 40, height: 12))
    }

    private func run(named name: String, _ ref: ImageRef) -> Layer {
        var layer = Layer(name: name, content: .image(ref),
                          frame: CGRect(x: 0, y: 0, width: 40, height: 12))
        layer.isARunOfText = true
        return layer
    }

    private func document(_ layers: [Layer]) -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 400, height: 300), layers: layers)
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private func roundTrip(_ doc: PhotonzDocument) throws -> PhotonzDocument {
        try JSONDecoder().decode(PhotonzDocument.self, from: encoder.encode(doc))
    }

    // MARK: - The file

    @Test func aDocumentNothingHasBeenReadOffIsTheFileItAlwaysWas() throws {
        let doc = document([run(named: "Text 1", picture(1))])
        let written = try #require(String(data: try encoder.encode(doc), encoding: .utf8))
        #expect(!written.contains("readWords"))
        #expect(try roundTrip(doc).readWords.isEmpty)
    }

    @Test func whatWasReadComesBackWithTheFile() throws {
        var doc = document([run(named: "Text 1", picture(1)),
                            run(named: "Text 2", picture(2))])
        doc.readWords.remember("Save Changes", for: picture(1))
        doc.readWords.remember("Launch at login", for: picture(2))
        let opened = try roundTrip(doc)
        #expect(opened.readWords[picture(1)] == "Save Changes")
        #expect(opened.readWords[picture(2)] == "Launch at login")
        #expect(opened == doc)
    }

    @Test func aPictureWithNoWordsInItIsAnAnswerAndIsSavedAsOne() throws {
        // The switch and the icon that came back with nothing are exactly what
        // must not be asked again on every open for the rest of the file's life.
        var doc = document([run(named: "Text 1", picture(1))])
        doc.readWords.remember("", for: picture(1))
        let opened = try roundTrip(doc)
        #expect(opened.readWords[picture(1)] == "")
        #expect(opened.readWords.hasBeenRead(picture(1)))
        #expect(!opened.readWords.hasBeenRead(picture(2)))
    }

    @Test func whatIsSavedIsWordsAndTheBitmapTheyCameOffAndNothingElse() throws {
        var doc = document([run(named: "Text 1", picture(1))])
        doc.readWords.remember("Save Changes", for: picture(1))
        let written = try #require(try JSONSerialization.jsonObject(
            with: try encoder.encode(doc)) as? [String: Any])
        let entries = try #require(written["readWords"] as? [[String: Any]])
        #expect(entries.count == 1)
        // An entry says which picture and what it said. Nothing in it is pixels,
        // which the document model is not allowed to carry.
        #expect(Set(entries[0].keys) == ["image", "words"])
        #expect(entries[0]["words"] as? String == "Save Changes")
        let image = try #require(entries[0]["image"] as? [String: Any])
        #expect(Set(image.keys) == ["id", "pixelSize"])
    }

    @Test func theSameReadingsSaveAsTheSameBytesTwice() throws {
        var doc = document([])
        for n in 1...12 { doc.readWords.remember("word \(n)", for: picture(n)) }
        var again = document([])
        for n in (1...12).reversed() { again.readWords.remember("word \(n)", for: picture(n)) }
        #expect(try encoder.encode(doc) == encoder.encode(again))
    }

    // MARK: - It is not an edit

    @Test func filingAReadingSpendsNoUndoStepAndSurvivesUndo() {
        var history = History(document: document([run(named: "Text 1", picture(1))]))
        history.perform { $0.layers.append(self.run(named: "Text 2", self.picture(2))) }
        #expect(history.canUndo)
        let steps = history.canRedo
        history.applyOutsideHistory { $0.readWords.remember("Save Changes", for: self.picture(1)) }
        #expect(history.current.readWords[picture(1)] == "Save Changes")
        #expect(history.canRedo == steps)
        // And stepping back over the edit the reading landed during does not
        // take the reading with it: it was never part of what was done.
        history.undo()
        #expect(history.current.readWords[picture(1)] == "Save Changes")
        #expect(!history.canUndo)
    }

    // MARK: - The name in the list

    @Test func aRowKeepsTheNameTheReadingGaveItAcrossASaveAndAnOpen() throws {
        var doc = document([run(named: "Text 57", picture(1))])
        doc.readWords.remember("Recommended", for: picture(1))
        let opened = try roundTrip(doc)
        #expect(opened.layers[0].displayName(readWords: opened.readWords.byPicture) == "Recommended")
        // ...and the list built from the saved document says it too, with no
        // reading having happened in between.
        let rows = opened.layerRows(expanded: [], selected: [],
                                    readWords: opened.readWords.byPicture)
        #expect(rows.map(\.name) == ["Recommended"])
    }

    @Test func aNameSomebodyTypedStillWinsAfterASaveAndAnOpen() throws {
        var doc = document([run(named: "Text 57", picture(1))])
        doc.readWords.remember("Recommended", for: picture(1))
        doc.renameLayer(id: doc.layers[0].id, to: "Chosen plan",
                        readWords: doc.readWords.byPicture)
        let opened = try roundTrip(doc)
        #expect(opened.layers[0].displayName(readWords: opened.readWords.byPicture) == "Chosen plan")
    }

    @Test func pressingReturnOnTheRowUntouchedDoesNotPinTheWordsAsAName() throws {
        // The field opens filled with what the row says, which is now what the
        // SAVED reading says. Pressing Return on it is not a rename.
        var doc = document([run(named: "Text 57", picture(1))])
        doc.readWords.remember("Recommended", for: picture(1))
        doc.renameLayer(id: doc.layers[0].id, to: "Recommended",
                        readWords: doc.readWords.byPicture)
        #expect(doc.layers[0].name == "Text 57")
    }
}
