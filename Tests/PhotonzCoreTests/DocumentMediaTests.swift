import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// What the Library's Media shelf holds: the pictures THIS document uses, one
/// tile per picture however many times it is drawn (`docs/design/modes.md` §6).
struct DocumentMediaTests {

    private func ref(_ width: CGFloat = 100, _ height: CGFloat = 60) -> ImageRef {
        ImageRef(pixelSize: CGSize(width: width, height: height))
    }

    private func picture(_ name: String, _ image: ImageRef, locked: Bool = false) -> Layer {
        Layer(name: name, content: .image(image),
              frame: CGRect(origin: .zero, size: image.pixelSize), isLocked: locked)
    }

    private func text(_ name: String) -> Layer {
        Layer(name: name, content: .text(TextContent(string: "hello")),
              frame: CGRect(x: 0, y: 0, width: 10, height: 10))
    }

    private func group(_ name: String, _ children: [Layer]) -> Layer {
        Layer(name: name, content: .group(GroupContent(children: children)),
              frame: CGRect(origin: .zero, size: .zero))
    }

    private func doc(_ layers: [Layer]) -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 400, height: 300), layers: layers)
    }

    // MARK: - What is on the shelf at all

    @Test func aDocumentWithNothingPlacedHasAnEmptyShelf() {
        #expect(DocumentMedia.items(in: doc([])).isEmpty)
        #expect(DocumentMedia.items(in: doc([text("Title")])).isEmpty)
    }

    /// The canvas a document is drawn on is not something you place INTO it,
    /// so File ▸ New (a locked white picture at the bottom of the stack) opens
    /// on an empty shelf rather than on a white tile.
    @Test func theCanvasTheDocumentIsDrawnOnIsNotOnTheShelf() {
        let canvas = ref(400, 300)
        #expect(DocumentMedia.items(in: doc([picture("Background", canvas, locked: true)])).isEmpty)
    }

    /// A picture CAN be dropped underneath the Background, because a drop on a
    /// row of the layers list lands where the line said. The canvas does not
    /// stop being the canvas because something slid under it.
    @Test func aPictureDroppedUnderTheCanvasDoesNotMakeTheCanvasATile() {
        let canvas = ref(400, 300)
        let hero = ref()
        let items = DocumentMedia.items(in: doc([picture("Hero banner", hero),
                                                 picture("Background", canvas, locked: true)]))
        #expect(items.map(\.name) == ["Hero banner"])
    }

    /// ...and an unlocked picture at the bottom IS one: it was put there.
    @Test func anUnlockedPictureAtTheBottomIsOnTheShelf() {
        let items = DocumentMedia.items(in: doc([picture("Hero banner", ref())]))
        #expect(items.map(\.name) == ["Hero banner"])
    }

    @Test func aPlacedPictureIsOnTheShelf() {
        let canvas = ref(400, 300)
        let hero = ref()
        let items = DocumentMedia.items(in: doc([picture("Background", canvas, locked: true),
                                                 picture("Hero banner", hero)]))
        #expect(items.map(\.id) == [hero.id])
        #expect(items.map(\.name) == ["Hero banner"])
        #expect(items.map(\.uses) == [1])
    }

    @Test func aPictureInsideAGroupIsOnTheShelf() {
        let hero = ref()
        let items = DocumentMedia.items(in: doc([group("Card", [picture("Hero banner", hero)])]))
        #expect(items.map(\.id) == [hero.id])
    }

    // MARK: - One tile per picture, however many layers draw it

    /// "Three placements of one bell are three layer rows and one Library
    /// tile" (`docs/design/modes.md` §6).
    @Test func threePlacementsOfOnePictureAreOneTile() {
        let bell = ref()
        let items = DocumentMedia.items(in: doc([picture("Bell", bell),
                                                 picture("Bell 2", bell),
                                                 picture("Bell 3", bell)]))
        #expect(items.count == 1)
        #expect(items[0].uses == 3)
    }

    /// The tile keeps the name of the FIRST one placed, so placing a second
    /// copy does not rename the tile under your hand.
    @Test func theTileWearsTheNameOfTheFirstOnePlaced() {
        let bell = ref()
        let items = DocumentMedia.items(in: doc([picture("Bell", bell), picture("Bell 2", bell)]))
        #expect(items.map(\.name) == ["Bell"])
    }

    /// ...even when the copy is dropped UNDERNEATH the original, which a drop
    /// on a row of the layers list can do.
    @Test func aCopyDroppedBelowTheOriginalStillDoesNotRenameTheTile() {
        let bell = ref()
        let items = DocumentMedia.items(in: doc([picture("Bell 2", bell), picture("Bell", bell)]))
        #expect(items.map(\.name) == ["Bell"])
        #expect(items.map(\.uses) == [2])
    }

    /// Every one of them renamed by hand: nothing says which came first, so
    /// the bottom-most wears the tile rather than the tile going nameless.
    @Test func namesNobodyNumberedFallBackToTheBottomMost() {
        let bell = ref()
        let items = DocumentMedia.items(in: doc([picture("Underneath", bell),
                                                 picture("On top", bell)]))
        #expect(items.map(\.name) == ["Underneath"])
    }

    @Test func aNumberedCopyIsToldFromANameThatMerelyStartsTheSame() {
        #expect(DocumentMedia.isNumberedCopy("Bell 2", of: "Bell"))
        #expect(DocumentMedia.isNumberedCopy("Bell 17", of: "Bell"))
        #expect(!DocumentMedia.isNumberedCopy("Bell", of: "Bell"))
        #expect(!DocumentMedia.isNumberedCopy("Bell tower", of: "Bell"))
        #expect(!DocumentMedia.isNumberedCopy("Bells 2", of: "Bell"))
    }

    /// Newest first, which is the order the layers panel reads the stack in:
    /// the thing you just put down is the first tile.
    @Test func theNewestPictureIsTheFirstTile() {
        let first = ref(10, 10)
        let second = ref(20, 20)
        let items = DocumentMedia.items(in: doc([picture("First", first), picture("Second", second)]))
        #expect(items.map(\.id) == [second.id, first.id])
    }

    // MARK: - What a tile says about itself

    @Test func theDetailLineCountsTheUses() {
        let bell = ref()
        #expect(DocumentMediaItem(image: bell, name: "Bell", uses: 1).detail == "used once")
        #expect(DocumentMediaItem(image: bell, name: "Bell", uses: 3).detail == "used 3 times")
    }

    @Test func entriesCarryTheNameAndTheDetailSearchReads() {
        let bell = ref()
        let entries = DocumentMedia.entries(in: doc([picture("Bell", bell), picture("Bell 2", bell)]))
        #expect(entries.map(\.id) == [bell.id.uuidString])
        #expect(entries.map(\.scope) == [.media])
        #expect(entries.map(\.name) == ["Bell"])
        #expect(entries.map(\.detail) == ["used 2 times"])
        #expect(LibrarySearch.filter(entries, query: "bell").count == 1)
        #expect(LibrarySearch.filter(entries, query: "twice").isEmpty)
    }

    // MARK: - Finding the one a tile was picked

    @Test func anItemIsFoundByTheIdItsTileCarries() {
        let bell = ref()
        let document = doc([picture("Bell", bell)])
        #expect(DocumentMedia.item(id: bell.id.uuidString, in: document)?.name == "Bell")
        #expect(DocumentMedia.item(id: "not a uuid", in: document) == nil)
        #expect(DocumentMedia.item(id: UUID().uuidString, in: document) == nil)
    }

    // MARK: - Putting one down again

    /// A tile hands over the name it is captioned with, not a file path, so a
    /// caption with a dot in it keeps its tail. It still steps aside from a
    /// name already in use.
    @Test func placingATileAgainKeepsItsNameAndTakesTheNextFreeNumber() {
        #expect(PlacedImageNaming.layerName(named: "Screenshot 16.22.12", taken: [])
            == "Screenshot 16.22.12")
        #expect(PlacedImageNaming.layerName(named: "Bell", taken: ["Bell"]) == "Bell 2")
        #expect(PlacedImageNaming.layerName(named: "  ", taken: []) == PlacedImageNaming.clipboardName)
    }

    // MARK: - Collages

    /// A collage's photos are pictures this document uses too, so they are on
    /// the shelf and can be placed again.
    @Test func aCollagesPhotosAreOnTheShelf() {
        let left = ref(10, 10)
        let right = ref(20, 20)
        let collage = Collage.layer(content: CollageContent(slots: [CollageSlot(imageRef: left),
                                                                    CollageSlot(imageRef: right),
                                                                    CollageSlot()]),
                                    frame: CGRect(x: 0, y: 0, width: 200, height: 100),
                                    name: "Collage")
        let items = DocumentMedia.items(in: doc([collage]))
        #expect(items.map(\.id) == [left.id, right.id])
        #expect(items.map(\.name) == ["Collage 1", "Collage 2"])
    }

    @Test func aCollageWithOnePhotoNamesItAfterTheLayer() {
        let only = ref()
        let collage = Collage.layer(content: CollageContent(slots: [CollageSlot(imageRef: only),
                                                                    CollageSlot()]),
                                    frame: CGRect(x: 0, y: 0, width: 200, height: 100),
                                    name: "Collage")
        #expect(DocumentMedia.items(in: doc([collage])).map(\.name) == ["Collage"])
    }
}
