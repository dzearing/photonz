import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// New Layer via Cut: the piece goes on a layer of its own directly over the
/// picture it came out of, that picture keeps its box and gets the repaired
/// bitmap, and the two happen in ONE step so one undo puts back all of it.
@Suite("Cutting a piece onto its own layer")
struct NewLayerViaCutTests {

    private func capture() -> (document: PhotonzDocument, id: UUID, ref: ImageRef) {
        let ref = ImageRef(pixelSize: CGSize(width: 400, height: 300))
        let document = PhotonzDocument.withBaseImage(ref)
        return (document, document.layers[0].id, ref)
    }

    private let pieceRef = ImageRef(pixelSize: CGSize(width: 80, height: 18))

    @Test func thePieceSitsOverThePictureAndThePictureIsRepaired() {
        var (document, id, original) = capture()
        let patched = ImageRef(pixelSize: CGSize(width: 400, height: 300))
        let box = CGRect(x: 10, y: 20, width: 80, height: 18)
        let made = document.cutRegionToLayer(id: id, patched: patched, piece: pieceRef,
                                             pieceFrame: box, name: "Background 2")
        #expect(made != nil)
        #expect(document.layers.count == 2)
        #expect(document.layers[0].id == id)
        // The picture it came out of keeps its box. Nothing was removed from
        // it: the space was FILLED, so there is nothing to tighten to.
        #expect(document.layers[0].frame == CGRect(x: 0, y: 0, width: 400, height: 300))
        #expect(document.layers[0].imageRef == patched)
        #expect(document.layers[0].imageRef != original)
        // And the piece is the size of the piece, not the size of the picture.
        #expect(document.layers[1].frame == box)
        #expect(document.layers[1].imageRef == pieceRef)
        #expect(document.layers.map(\.name) == ["Background", "Background 2"])
    }

    /// Directly OVER the picture, not on top of everything: an arrow somebody
    /// drew over the screenshot stays over the piece as well.
    @Test func thePieceGoesDirectlyOverThePictureAndNotOverEverything() {
        var (document, id, _) = capture()
        document.layers.append(Layer(name: "Arrow",
                                     content: .image(ImageRef(pixelSize: .init(width: 4, height: 4))),
                                     frame: CGRect(x: 0, y: 0, width: 40, height: 40)))
        document.cutRegionToLayer(id: id, patched: ImageRef(pixelSize: CGSize(width: 400, height: 300)),
                                  piece: pieceRef, pieceFrame: CGRect(x: 10, y: 20, width: 80, height: 18),
                                  name: "Piece")
        #expect(document.layers.map(\.name) == ["Background", "Piece", "Arrow"])
    }

    /// A picture inside a group cuts into that group, so the piece does not
    /// leap out of the group it came from.
    @Test func aPictureInsideAGroupCutsInsideThatGroup() {
        var document = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300))
        let picture = Layer(name: "Shot",
                            content: .image(ImageRef(pixelSize: CGSize(width: 200, height: 100))),
                            frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        let group = Layer(name: "Group", content: .group(GroupContent(children: [picture])),
                          frame: CGRect(x: 30, y: 40, width: 0, height: 0))
        document.layers.append(group)
        document.cutRegionToLayer(id: picture.id,
                                  patched: ImageRef(pixelSize: CGSize(width: 200, height: 100)),
                                  piece: pieceRef, pieceFrame: CGRect(x: 10, y: 20, width: 80, height: 18),
                                  name: "Piece")
        let children = document.layers[0].group?.children ?? []
        #expect(children.map(\.name) == ["Shot", "Piece"])
    }

    @Test func theWholeThingIsOneUndoStep() {
        let (document, id, _) = capture()
        var history = History(document: document)
        let before = history.current
        history.perform {
            $0.cutRegionToLayer(id: id, patched: ImageRef(pixelSize: CGSize(width: 400, height: 300)),
                                piece: pieceRef, pieceFrame: CGRect(x: 10, y: 20, width: 80, height: 18),
                                name: "Piece")
        }
        #expect(history.current.layers.count == 2)
        history.undo()
        // One press puts back the piece, the hole and the fill together.
        #expect(history.current == before)
        #expect(!history.canUndo)
    }

    @Test func somethingThatIsNotAPictureIsLeftAlone() {
        var document = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300))
        var annotation = AnnotationContent(shape: .rectangle, start: .zero,
                                           end: CGPoint(x: 50, y: 50))
        annotation.fillColorHex = "#FF0000"
        let shape = Layer(name: "Rectangle", content: .annotation(annotation),
                          frame: CGRect(x: 0, y: 0, width: 50, height: 50))
        document.layers.append(shape)
        let made = document.cutRegionToLayer(id: shape.id,
                                             patched: ImageRef(pixelSize: CGSize(width: 10, height: 10)),
                                             piece: pieceRef, pieceFrame: .zero, name: "Piece")
        #expect(made == nil)
        #expect(document.layers.count == 1)
    }
}

/// The words the app says when a cut lands on something it cannot take a piece
/// out of, and when the fill behind a piece was a guess.
@Suite("What New Layer via Cut says for itself")
struct NewLayerViaCutWordsTests {

    private func textLayer() -> Layer {
        Layer(name: "Label", content: .text(TextContent(string: "Hello")),
              frame: CGRect(x: 0, y: 0, width: 40, height: 20))
    }

    /// The way out differs from the other three keys and the sentence has to
    /// say so: clearing the marquee makes ⌘J DUPLICATE the layer. It does not
    /// cut anything, so "clear the marquee to cut the whole layer" would be a
    /// lie.
    @Test func refusingToCutToALayerNamesItsOwnWayOut() {
        let refusal = RegionSliceRefusal.refusal(for: textLayer(), action: .cutToLayer)
        #expect(refusal?.reason == .canBecomeAPicture)
        #expect(refusal?.title == "Cannot cut a piece onto its own layer")
        #expect(refusal?.detail.contains("cut the whole layer") == false)
        #expect(refusal?.offersTurnIntoPicture == true)
    }

    @Test func aPictureCanAlwaysHaveAPieceCutOntoItsOwnLayer() {
        let picture = Layer(name: "Shot",
                            content: .image(ImageRef(pixelSize: CGSize(width: 10, height: 10))),
                            frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(RegionSliceRefusal.refusal(for: picture, action: .cutToLayer) == nil)
    }

    /// The pill only ever speaks about a fill the app could not justify. A cut
    /// whose surroundings read cleanly changed the canvas in front of you and
    /// does not need announcing.
    @Test func theNoticeSaysWhichKindOfFillWentIn() {
        let guessed = CopyConfirmation(subject: .cutToOwnLayer(.guessed), shownAt: Date())
        #expect(guessed.title == "Cut to its own layer")
        #expect(guessed.detail.lowercased().contains("guess"))

        let cleared = CopyConfirmation(subject: .cutToOwnLayer(.cleared), shownAt: Date())
        #expect(cleared.title == "Cut to its own layer")
        #expect(cleared.detail != guessed.detail)
        #expect(cleared.detail.lowercased().contains("empty"))

        let matched = CopyConfirmation(subject: .cutToOwnLayer(.matched), shownAt: Date())
        #expect(matched.detail != guessed.detail)
    }

    /// No em dashes anywhere a person reads, the app's standing rule.
    @Test func theWordsCarryNoEmDashes() {
        for heal in [PatchHeal.matched, .guessed, .cleared] {
            let notice = CopyConfirmation(subject: .cutToOwnLayer(heal), shownAt: Date())
            #expect(!notice.detail.contains("—"))
            #expect(!notice.title.contains("—"))
        }
        let refusal = RegionSliceRefusal(action: .cutToLayer, reason: .notPixels)
        #expect(!refusal.detail.contains("—"))
    }
}
