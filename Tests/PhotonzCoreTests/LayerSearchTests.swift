import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Finding one layer in a list too long to scroll: what a typed query matches,
/// and what the layers panel shows while one is typed.
struct LayerSearchTests {

    /// A piece of text the way Separate makes one: an automatic name, so the
    /// row wears the words it holds.
    private var textCount = 0
    private mutating func text(_ words: String) -> Layer {
        textCount += 1
        return Layer(name: "Text \(textCount)", content: .text(TextContent(string: words)),
                     frame: CGRect(x: 0, y: 0, width: 10, height: 10))
    }

    private func named(_ name: String) -> Layer {
        Layer(name: name, content: .text(TextContent(string: "something else")),
              frame: CGRect(x: 0, y: 0, width: 10, height: 10))
    }

    private func group(_ name: String, _ children: [Layer]) -> Layer {
        Layer(name: name, content: .group(GroupContent(children: children)),
              frame: CGRect(origin: .zero, size: .zero))
    }

    private func doc(_ layers: [Layer]) -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 200, height: 200), layers: layers)
    }

    // MARK: - What a query matches

    @Test func aQueryMatchesAnywhereInTheName() {
        #expect(LayerSearch.matches(name: "Save Changes", query: "chan"))
        #expect(LayerSearch.matches(name: "Save Changes", query: "Save"))
        #expect(!LayerSearch.matches(name: "Save Changes", query: "cancel"))
    }

    @Test func caseAndAccentsDoNotCount() {
        #expect(LayerSearch.matches(name: "Save Changes", query: "SAVE"))
        #expect(LayerSearch.matches(name: "Café latte", query: "cafe"))
        #expect(LayerSearch.matches(name: "Cafe latte", query: "café"))
    }

    @Test func everyWordHasToAppearButTheOrderDoesNot() {
        #expect(LayerSearch.matches(name: "Save Changes", query: "save ch"))
        #expect(LayerSearch.matches(name: "Save Changes", query: "changes save"))
        #expect(!LayerSearch.matches(name: "Save Changes", query: "save now"))
    }

    @Test func anEmptyQueryIsNotASearch() {
        #expect(LayerSearch.normalized("") == "")
        #expect(LayerSearch.normalized("   ") == "")
        #expect(LayerSearch.normalized("  save  ") == "save")
        // Everything matches nothing-typed, which is what lets the panel ask
        // one question rather than two.
        #expect(LayerSearch.matches(name: "anything", query: ""))
    }

    // MARK: - The rows a search gives back

    @Test mutating func aSearchLooksInsideShutGroupsToo() {
        let document = doc([
            group("Card", [text("Save Changes"), text("Cancel")]),
            text("Heading"),
        ])
        // Nothing is open, so the ordinary list is two rows.
        #expect(document.layerRows(expanded: [], selected: []).count == 2)
        let found = document.layerRows(matching: "save", selected: [])
        #expect(found.map(\.name) == ["Save Changes"])
    }

    @Test mutating func everyResultIsAPlainRowAtTheLeftEdge() throws {
        let document = doc([
            group("Card", [text("Save Changes")]),
        ])
        let found = document.layerRows(matching: "save", selected: [])
        try #require(found.count == 1)
        #expect(found[0].row.depth == 0)
        #expect(found[0].row.parentID == nil)
        #expect(!found[0].row.isGroup)
        #expect(!found[0].row.isExpanded)
    }

    @Test mutating func aGroupWhoseOwnNameMatchesComesBackWithoutItsContents() {
        let document = doc([
            group("Card", [text("Save Changes"), text("Cancel")]),
        ])
        let found = document.layerRows(matching: "card", selected: [])
        #expect(found.map(\.name) == ["Card"])
    }

    @Test mutating func resultsStayInPanelOrderTopmostFirst() {
        let document = doc([text("Save one"), text("Save two"), text("Save three")])
        // Panel order is top down, which is the reverse of the stored order.
        let found = document.layerRows(matching: "save", selected: [])
        #expect(found.map(\.name) == ["Save three", "Save two", "Save one"])
    }

    @Test mutating func aPieceOfTextIsFoundByTheWordsItHoldsWhenNobodyNamedIt() {
        let document = doc([text("Save Changes")])
        #expect(document.layerRows(matching: "save", selected: []).count == 1)
        // ...and not when the list is showing stored names instead.
        #expect(document.layerRows(matching: "save", selected: [],
                                   saysItsWords: false).isEmpty)
    }

    @Test func aNameTypedByHandWinsOverTheWords() {
        let document = doc([named("Primary button")])
        #expect(document.layerRows(matching: "primary", selected: []).count == 1)
        #expect(document.layerRows(matching: "something", selected: []).isEmpty)
    }

    @Test mutating func aResultCarriesItsSelection() throws {
        let document = doc([text("Save Changes")])
        let id = try #require(document.allLayers.first).id
        #expect(document.layerRows(matching: "save", selected: [id]).first?.isSelected == true)
    }

    @Test mutating func nothingTypedGivesBackNothingRatherThanEverything() {
        // The panel asks this only while a query is typed, so an empty one is a
        // programming mistake rather than a state: it must not quietly flatten
        // the whole tree into a search result.
        let document = doc([group("Card", [text("Save")])])
        #expect(document.layerRows(matching: "  ", selected: []).isEmpty)
    }

    @Test mutating func aSearchThatFindsNothingFindsNothing() {
        let document = doc([text("Save Changes")])
        #expect(document.layerRows(matching: "cancel", selected: []).isEmpty)
    }

    /// A result is drawn flat and away from its neighbours, and that is the
    /// ONLY thing a search takes off a row. What the row IS travels with it:
    /// a piece of sound still carries the waveform mark in the slot where a
    /// thumbnail would be, and a cut clip still says how many pieces it is in.
    @Test mutating func aResultIsStillTheRowItWas() {
        let sound = Layer.sound(SoundRef(durationMS: 4000), name: "Voice over",
                                time: LayerTime(inMS: 0, outMS: 4000,
                                                sourceInMS: 0, sourceLengthMS: 4000))
        var clip = ClipPiecesTests.clipLayer()
        clip.name = "Screen recording"
        var pieces = clip.clipPieces!
        let split = pieces.split(atMS: 4000)
        #expect(split)
        clip.setClipPieces(pieces)
        let document = doc([sound, clip])
        #expect(document.layerRows(matching: "voice", selected: []).first?.isSound == true)
        #expect(document.layerRows(matching: "recording", selected: [])
            .first?.piecesNote?.text == "2 pieces")
    }
}
