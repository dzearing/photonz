import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A separated run of text is still a PICTURE of words, so the words are not in
/// the document to read off. They are read off the pixels and kept beside the
/// document, and these are the rules for what a row does with them.
///
/// The document is never touched by any of this: a name that came from a
/// reading is worked out as the list is drawn, exactly as a text layer's own
/// words are (`Layer.displayName`).
@Suite("A separated run says the words that were read off it")
struct SeparatedRowWordsTests {

    private func ref(_ n: Int) -> ImageRef {
        ImageRef(id: UUID(uuidString: "0000000\(n)-0000-0000-0000-000000000000")!,
                 pixelSize: CGSize(width: 80, height: 20))
    }

    private func run(named name: String, _ ref: ImageRef) -> Layer {
        var layer = Layer(name: name, content: .image(ref),
                          frame: CGRect(x: 0, y: 0, width: 80, height: 20))
        layer.isARunOfText = true
        return layer
    }

    private func doc(_ layers: [Layer]) -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 400, height: 400), layers: layers)
    }

    // MARK: - What a row says

    @Test("A run the app numbered wears the words that were read off it")
    func aReadRunSaysItsWords() {
        let picture = ref(1)
        let layer = run(named: "Text 57", picture)
        #expect(layer.displayName(readWords: [picture: "Recommended"]) == "Recommended")
    }

    @Test("A run nobody has read yet says the name the app gave it")
    func anUnreadRunKeepsItsNumber() {
        let layer = run(named: "Text 57", ref(1))
        #expect(layer.displayName(readWords: [:]) == "Text 57")
        // A reading that came back empty is not a name either.
        #expect(layer.displayName(readWords: [ref(1): "   "]) == "Text 57")
    }

    @Test("A name somebody typed is theirs, whatever was read off the picture")
    func aHandNameIsNeverTakenAway() {
        let picture = ref(1)
        let layer = run(named: "Primary button label", picture)
        #expect(layer.displayName(readWords: [picture: "Save Changes"]) == "Primary button label")
    }

    @Test("Words too long for a row are cut the same way a text layer's are")
    func longWordsAreShortened() {
        let picture = ref(1)
        let long = "Choose how often this document checks for a newer version"
        let name = run(named: "Text 2", picture).displayName(readWords: [picture: long])
        #expect(name.count <= LayerNaming.wordsLimit + 1)
        #expect(name.hasSuffix("\u{2026}"))
    }

    @Test("Reading a run into real text leaves the words in charge, not the reading")
    func typedWordsWinOnceTheyAreReal() {
        // Turn into Text puts the words IN the layer. From then on the row
        // follows what is typed there, so a stale reading cannot pin it.
        let picture = ref(1)
        var layer = run(named: "Text 9", picture)
        layer.content = .text(TextContent(string: "Done"))
        #expect(layer.displayName(readWords: [picture: "Save Changes"]) == "Done")
    }

    @Test("A picture that is not a run of text is left alone")
    func anOrdinaryPictureIsNotRenamed() {
        // Nothing reads an ordinary photograph, but a name is a promise: only a
        // run the separation lifted off a screenshot wears words it was read.
        let picture = ref(2)
        var layer = run(named: "Image", picture)
        layer.isARunOfText = nil
        #expect(layer.displayName(readWords: [picture: "Wednesday"]) == "Image")
    }

    @Test("Two runs cut from the same picture say the same words")
    func theWordsBelongToTheBitmap() {
        // Held against the BITMAP rather than the layer, like the separation
        // note beside it, so undoing and separating again finds the reading
        // still there rather than reading every run a second time.
        let picture = ref(1)
        let copy = run(named: "Text 58", picture)
        #expect(copy.displayName(readWords: [picture: "Recommended"]) == "Recommended")
    }

    // MARK: - The list and the find field

    @Test("The layers list shows what was read")
    func theListSaysTheWords() {
        let one = ref(1), two = ref(2)
        let document = doc([run(named: "Text 1", one), run(named: "Text 2", two)])
        let rows = document.layerRows(expanded: [], selected: [],
                                      readWords: [one: "Recommended", two: "Decision"])
        #expect(rows.map(\.name) == ["Decision", "Recommended"])
    }

    @Test("Typing a word you can see on the canvas reaches the piece holding it")
    func findingAWordReachesTheRun() {
        let one = ref(1), two = ref(2)
        let document = doc([run(named: "Text 1", one), run(named: "Text 2", two)])
        let hits = document.layerRows(matching: "recommend", selected: [],
                                      readWords: [one: "Recommended", two: "Decision"])
        #expect(hits.map(\.name) == ["Recommended"])
        // And the number the app gave it still finds it, for anybody who has
        // been reading the list that way.
        #expect(document.layerRows(matching: "Text 2", selected: [],
                                   readWords: [one: "Recommended"]).count == 1)
    }

    // MARK: - Renaming

    @Test("Opening the rename field on a read row and pressing Return changes nothing")
    func returningOnTheWordsIsNotARename() {
        let picture = ref(1)
        var document = doc([run(named: "Text 57", picture)])
        let id = document.layers[0].id
        document.renameLayer(id: id, to: "Recommended", readWords: [picture: "Recommended"])
        #expect(document.layer(id: id)?.name == "Text 57")
        // A name of their own is theirs from then on, words or no words.
        document.renameLayer(id: id, to: "Chosen plan", readWords: [picture: "Recommended"])
        #expect(document.layer(id: id)?.name == "Chosen plan")
        #expect(document.layer(id: id)?
            .displayName(readWords: [picture: "Recommended"]) == "Chosen plan")
    }

    @Test("With the words switched off a row says exactly what it is stored as")
    func theFlagOffIsTheOldList() {
        let one = ref(1)
        let document = doc([run(named: "Text 1", one)])
        let rows = document.layerRows(expanded: [], selected: [], saysItsWords: false,
                                      readWords: [one: "Recommended"])
        #expect(rows.map(\.name) == ["Text 1"])
    }
}
