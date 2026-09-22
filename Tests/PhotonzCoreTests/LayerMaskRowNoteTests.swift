import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// What the layers list says about a mask.
///
/// Cutting a layer to the shape of the one under it spends that lower layer:
/// it stops drawing and becomes the shape instead. Its row used to keep its
/// name, its thumbnail and its eye, so a rectangle that had vanished off the
/// canvas looked exactly as it always had and the only way to find out where it
/// went was to undo. Both rows now say it, and they name each other.
@Suite("A layer being used as a mask says so on its row")
struct LayerMaskRowNoteTests {

    private static func box(_ name: String) -> Layer {
        Layer(name: name,
              content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#0C0E14")),
              frame: CGRect(x: 0, y: 0, width: 40, height: 40))
    }

    /// A plate with a picture cut to its shape over it: the pair the task
    /// describes, bottom first the way the document stores them.
    private static func pair(_ matte: LayerMatte? = .shape) -> PhotonzDocument {
        let plate = box("Rectangle")
        var picture = box("Background")
        picture.style.matte = matte
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        doc.layers = [plate, picture]
        return doc
    }

    private static func notes(_ document: PhotonzDocument) -> [String: LayerMaskNote?] {
        var found: [String: LayerMaskNote?] = [:]
        for row in document.layerRows(expanded: document.openableGroupIDs, selected: []) {
            found[row.name] = row.maskNote
        }
        return found
    }

    // MARK: - The pair, read off the list

    @Test func theLayerBeingSpentSaysWhoIsUsingIt() {
        let note = Self.notes(Self.pair())["Rectangle"] ?? nil
        #expect(note?.role == .theMask)
        #expect(note?.text == "Mask for Background")
    }

    @Test func theLayerDoingTheCuttingSaysWhatItIsBorrowingFrom() {
        let note = Self.notes(Self.pair())["Background"] ?? nil
        #expect(note?.role == .wearingOne)
        #expect(note?.text == "Masked by Rectangle")
    }

    /// The point of naming both halves: neither row is a dead end.
    @Test func eitherRowLeadsToTheOther() {
        let found = Self.notes(Self.pair())
        #expect((found["Rectangle"] ?? nil)?.otherName == "Background")
        #expect((found["Background"] ?? nil)?.otherName == "Rectangle")
    }

    @Test func whichKindOfMaskItIsRidesWithTheNote() {
        let found = Self.notes(Self.pair(.brightness))
        #expect((found["Rectangle"] ?? nil)?.matte == .brightness)
        #expect((found["Background"] ?? nil)?.matte == .brightness)
    }

    // MARK: - Nothing at all on a row with no mask near it

    @Test func aDocumentWithNoMaskInItSaysNothing() {
        let found = Self.notes(Self.pair(nil))
        #expect((found["Rectangle"] ?? nil) == nil)
        #expect((found["Background"] ?? nil) == nil)
    }

    /// Acceptance, in one test: turning Masked by off puts both rows straight
    /// back to how they were.
    @Test func turningTheMaskOffPutsBothRowsBack() {
        var doc = Self.pair()
        #expect(Self.notes(doc).values.compactMap { $0 }.count == 2)
        doc.layers[1].style.matte = nil
        #expect(Self.notes(doc).values.compactMap { $0 }.count == 0)
    }

    /// A row further up the stack is somebody else's business.
    @Test func aLayerWithNothingToDoWithTheMaskIsUntouched() {
        var doc = Self.pair()
        doc.layers.append(Self.box("Arrow"))
        #expect((Self.notes(doc)["Arrow"] ?? nil) == nil)
    }

    @Test func theBottomLayerOfAStackHasNothingUnderItToBorrow() {
        var lonely = Self.box("Rectangle")
        lonely.style.matte = .shape
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        doc.layers = [lonely]
        #expect((Self.notes(doc)["Rectangle"] ?? nil) == nil)
    }

    // MARK: - It follows the picture, not the setting

    /// Hiding the layer that wears the mask puts the lower layer back in the
    /// picture, exactly as the renderer does, so neither row claims a mask is
    /// happening.
    @Test func hidingTheLayerWearingTheMaskTakesBothLinesOff() {
        var doc = Self.pair()
        doc.layers[1].isVisible = false
        let found = Self.notes(doc)
        #expect((found["Rectangle"] ?? nil) == nil)
        #expect((found["Background"] ?? nil) == nil)
    }

    /// A hidden layer is not a mask source either: a layer nobody can see must
    /// not be quietly cutting somebody else's shape out.
    @Test func hidingTheMaskItselfTakesBothLinesOff() {
        var doc = Self.pair()
        doc.layers[0].isVisible = false
        let found = Self.notes(doc)
        #expect((found["Rectangle"] ?? nil) == nil)
        #expect((found["Background"] ?? nil) == nil)
    }

    /// Reordering changes the mask the way it changes the composite, so the
    /// lines follow the drag.
    @Test func movingALayerUnderneathMovesTheLine() {
        var doc = Self.pair()
        doc.layers.insert(Self.box("Beach plate"), at: 0)
        #expect((Self.notes(doc)["Rectangle"] ?? nil)?.role == .theMask)
        #expect((Self.notes(doc)["Beach plate"] ?? nil) == nil)
        doc.layers.swapAt(0, 1)
        #expect((Self.notes(doc)["Beach plate"] ?? nil)?.role == .theMask)
        #expect((Self.notes(doc)["Rectangle"] ?? nil) == nil)
    }

    /// A mask is a fact about siblings: inside a group it is the group's own
    /// contents that pair up, and the layer outside is untouched.
    @Test func aMaskInsideAGroupPairsUpInsideThatGroup() {
        let outside = Self.box("Outside")
        let inside = Self.box("Inside")
        var top = Self.box("Top")
        top.style.matte = .shape
        var group = Self.box("Card")
        group.content = .group(GroupContent(children: [inside, top]))
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        doc.layers = [outside, group]
        let found = Self.notes(doc)
        #expect((found["Inside"] ?? nil)?.text == "Mask for Top")
        #expect((found["Top"] ?? nil)?.text == "Masked by Inside")
        #expect((found["Outside"] ?? nil) == nil)
        #expect((found["Card"] ?? nil) == nil)
    }

    /// Three deep, the middle layer is both: it is spent as the top one's mask
    /// AND it wears one of its own. Spent wins, because a layer that is not in
    /// the picture at all is the more surprising of the two truths and its own
    /// Masked by is changing no pixel.
    @Test func aLayerThatIsBothHalvesSaysItIsBeingSpent() {
        var middle = Self.box("Middle")
        middle.style.matte = .shape
        var top = Self.box("Top")
        top.style.matte = .shape
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        doc.layers = [Self.box("Bottom"), middle, top]
        let found = Self.notes(doc)
        #expect((found["Bottom"] ?? nil)?.text == "Mask for Middle")
        #expect((found["Middle"] ?? nil)?.text == "Mask for Top")
        #expect((found["Top"] ?? nil)?.text == "Masked by Middle")
    }

    // MARK: - What the words say

    /// The meaning is in the first two words, which is what a narrow row keeps
    /// when it cuts a long name off.
    @Test func theLineLeadsWithWhatItMeans() {
        let found = Self.notes(Self.pair())
        #expect((found["Rectangle"] ?? nil)?.text.hasPrefix("Mask for") == true)
        #expect((found["Background"] ?? nil)?.text.hasPrefix("Masked by") == true)
    }

    /// The hover carries what the row has no room for: what happened to the
    /// picture, and where the control that undoes it lives.
    @Test func theHoverSaysWhereThePixelsWentAndHowToGetThemBack() {
        let spent = (Self.notes(Self.pair())["Rectangle"] ?? nil)?.help ?? ""
        #expect(spent.contains("Background"))
        #expect(spent.contains("shape"))
        #expect(spent.contains("Masked by"))
        let wearing = (Self.notes(Self.pair(.brightness))["Background"] ?? nil)?.help ?? ""
        #expect(wearing.contains("brightness"))
        #expect(wearing.contains("Rectangle"))
    }

    // MARK: - It rides with the row wherever the row is shown

    @Test func aSearchResultKeepsTheLine() {
        let rows = Self.pair().layerRows(matching: "rect", selected: [])
        #expect(rows.count == 1)
        #expect(rows.first?.maskNote?.text == "Mask for Background")
    }

    /// The list's own words, not the stored name: a piece of text nobody has
    /// renamed says what it holds, and the other half of the pair has to call
    /// it that too.
    @Test func theOtherHalfIsNamedTheWayTheListNamesIt() {
        var words = Layer(name: "Text 3",
                          content: .text(TextContent(string: "Sign up")),
                          frame: CGRect(x: 0, y: 0, width: 40, height: 20))
        words.isVisible = true
        var picture = Self.box("Background")
        picture.style.matte = .shape
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        doc.layers = [words, picture]
        let saidItsWords = doc.layerRows(expanded: [], selected: [])
        #expect(saidItsWords.first(where: { $0.name == "Background" })?.maskNote?.text
                == "Masked by Sign up")
        let stored = doc.layerRows(expanded: [], selected: [], saysItsWords: false)
        #expect(stored.first(where: { $0.name == "Background" })?.maskNote?.text
                == "Masked by Text 3")
    }
}
