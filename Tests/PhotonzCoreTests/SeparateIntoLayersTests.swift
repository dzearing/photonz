import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// The document half of Separate into Layers: the picture's bitmap is replaced
/// by the repaired one and the pieces are stacked over it, in ONE mutation and
/// so in one undo step (`docs/design/separate-into-layers.md`).
@Suite("Separating a picture into layers")
struct SeparateIntoLayersTests {

    private func capture() -> (document: PhotonzDocument, id: UUID, ref: ImageRef) {
        let ref = ImageRef(pixelSize: CGSize(width: 400, height: 300))
        let document = PhotonzDocument.withBaseImage(ref)
        return (document, document.layers[0].id, ref)
    }

    private func piece(_ rect: CGRect, _ name: String) -> PhotonzDocument.SeparatedPiece {
        PhotonzDocument.SeparatedPiece(frame: rect,
                                       ref: ImageRef(pixelSize: rect.size),
                                       name: name)
    }

    @Test func thePictureIsRepairedAndThePiecesSitOverIt() {
        var (document, id, original) = capture()
        let patched = ImageRef(pixelSize: CGSize(width: 400, height: 300))
        let made = document.separateIntoLayers(id: id, patched: patched, pieces: [
            piece(CGRect(x: 10, y: 20, width: 80, height: 18), "Text 1"),
            piece(CGRect(x: 10, y: 60, width: 120, height: 18), "Text 2"),
        ])
        #expect(made.count == 2)
        // Two things, not three: the picture and the pieces. No repair layer.
        #expect(document.layers.count == 3)
        #expect(document.layers[0].id == id)
        #expect(document.layers[0].imageRef == patched)
        #expect(document.layers[0].imageRef != original)
        #expect(document.layers.map(\.name) == ["Background", "Text 1", "Text 2"])
        #expect(document.layers[1].frame == CGRect(x: 10, y: 20, width: 80, height: 18))
    }

    @Test func thePiecesGoDirectlyOverThePictureAndNotOverEverything() {
        var (document, id, _) = capture()
        let mark = Layer(name: "Arrow", content: .image(ImageRef(pixelSize: .init(width: 4, height: 4))),
                         frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        document.layers.append(mark)
        document.separateIntoLayers(id: id, patched: ImageRef(pixelSize: CGSize(width: 400, height: 300)),
                                    pieces: [piece(CGRect(x: 10, y: 20, width: 80, height: 18), "Text 1")])
        // A mark somebody drew over the screenshot stays over it.
        #expect(document.layers.map(\.name) == ["Background", "Text 1", "Arrow"])
    }

    @Test func theWholeThingIsOneUndoStep() {
        let (document, id, _) = capture()
        var history = History(document: document)
        let before = history.current
        history.perform {
            $0.separateIntoLayers(id: id,
                                  patched: ImageRef(pixelSize: CGSize(width: 400, height: 300)),
                                  pieces: (1...9).map { piece(CGRect(x: 10, y: 20 * $0, width: 80, height: 18),
                                                              "Text \($0)") })
        }
        #expect(history.current.layers.count == 10)
        #expect(history.canUndo)
        history.undo()
        // One press, and the screenshot is back exactly as it was — the layers
        // and the repaired picture together.
        #expect(history.current == before)
        #expect(!history.canUndo)
    }

    @Test func aLayerThatIsNotAPictureIsLeftAlone() {
        var document = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300))
        let shape = Layer(name: "Label", content: .text(TextContent(string: "Hello")),
                          frame: CGRect(x: 0, y: 0, width: 100, height: 40))
        document.layers.append(shape)
        let made = document.separateIntoLayers(id: shape.id,
                                               patched: ImageRef(pixelSize: CGSize(width: 4, height: 4)),
                                               pieces: [piece(CGRect(x: 0, y: 0, width: 10, height: 10), "Text 1")])
        #expect(made.isEmpty)
        #expect(document.layers.count == 1)
        #expect(document.layers[0].content == shape.content)
    }

    @Test func aPictureWithNothingFoundInItStillGetsItsRepair() {
        // Nothing was taken out, so nothing is stacked — but the call is still
        // well formed, and the picture is simply itself.
        var (document, id, _) = capture()
        let patched = ImageRef(pixelSize: CGSize(width: 400, height: 300))
        #expect(document.separateIntoLayers(id: id, patched: patched, pieces: []).isEmpty)
        #expect(document.layers.count == 1)
        #expect(document.layers[0].imageRef == patched)
    }

    // MARK: - A box that came out as a real shape

    @Test func aBoxReadAsAShapeArrivesAsOneYouCanResizeAndRepaint() throws {
        var (document, id, _) = capture()
        let blue = RGBA(r: 10.0 / 255, g: 132.0 / 255, b: 1)
        document.separateIntoLayers(
            id: id, patched: ImageRef(pixelSize: CGSize(width: 400, height: 300)),
            pieces: [PhotonzDocument.SeparatedPiece(
                frame: CGRect(x: 30, y: 40, width: 124, height: 30),
                content: .shape(fill: blue, radii: CornerRadii(7), borderWidth: 0,
                                borderColor: nil),
                name: "Box 1")])
        let box = try #require(document.layers.last)
        #expect(box.name == "Box 1")
        // A real rectangle, not a picture of one: it has a fill you can change
        // and a rounding you can type a number into, and resizing it redraws
        // rather than stretching pixels.
        guard case .annotation(let shape) = box.content else {
            Issue.record("a box read as a shape did not arrive as one")
            return
        }
        #expect(shape.shape == .rectangle)
        #expect(shape.fillColorHex == "#0A84FF")
        #expect(shape.cornerRadii == CornerRadii(7))
        #expect(box.imageRef == nil)
        #expect(box.frame == CGRect(x: 30, y: 40, width: 124, height: 30))
    }

    @Test func aBoxWithAPlainEdgeArrivesWearingIt() throws {
        var (document, id, _) = capture()
        document.separateIntoLayers(
            id: id, patched: ImageRef(pixelSize: CGSize(width: 400, height: 300)),
            pieces: [PhotonzDocument.SeparatedPiece(
                frame: CGRect(x: 10, y: 10, width: 100, height: 40),
                content: .shape(fill: RGBA(r: 1, g: 1, b: 1), radii: CornerRadii(5),
                                borderWidth: 1,
                                borderColor: RGBA(r: 0.8, g: 0.8, b: 0.85)),
                name: "Box 1")])
        let box = try #require(document.layers.last)
        // The edge is an effect, the way every other edge in the app is
        // (`OutlineRetirement.swift`), and it is painted what it was painted.
        #expect(box.style.borderEffectIndex != nil)
        #expect(box.style.borderColorHex == "#CCCCD9")
        #expect(box.style.borderWidth == 1)
    }

    @Test func theCornerRadiusRowReadsTheRoundingABoxCameWith() throws {
        var (document, id, _) = capture()
        document.separateIntoLayers(
            id: id, patched: ImageRef(pixelSize: CGSize(width: 400, height: 300)),
            pieces: [PhotonzDocument.SeparatedPiece(
                frame: CGRect(x: 20, y: 20, width: 248, height: 60),
                content: .shape(fill: RGBA(r: 0, g: 0.5, b: 1), radii: CornerRadii(14),
                                borderWidth: 0, borderColor: nil),
                name: "Box 1")])
        let box = try #require(document.layers.last)
        let reading = document.cornerRadiusSelection(layerIDs: [box.id],
                                                     readingWhatShows: true).reading
        print("RADIUS ROW reads \(String(describing: reading.value)), mixed \(reading.isMixed)")
        #expect(reading.value == 14)
        #expect(!reading.isMixed)
    }

    @Test func aBoxWithNoEdgeArrivesWithoutOne() throws {
        var (document, id, _) = capture()
        document.separateIntoLayers(
            id: id, patched: ImageRef(pixelSize: CGSize(width: 400, height: 300)),
            pieces: [PhotonzDocument.SeparatedPiece(
                frame: CGRect(x: 10, y: 10, width: 100, height: 40),
                content: .shape(fill: RGBA(r: 1, g: 0, b: 0), radii: .none,
                                borderWidth: 0, borderColor: nil),
                name: "Box 1")])
        let box = try #require(document.layers.last)
        #expect(box.style.borderEffectIndex == nil)
    }

    @Test func aPictureInsideAGroupSeparatesIntoThatGroup() {
        var document = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300))
        let shot = Layer(name: "Shot", content: .image(ImageRef(pixelSize: CGSize(width: 200, height: 100))),
                         frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        let group = Layer(name: "Card", content: .group(GroupContent(children: [shot])),
                          frame: CGRect(x: 50, y: 50, width: 200, height: 100))
        document.layers.append(group)
        document.separateIntoLayers(id: shot.id,
                                    patched: ImageRef(pixelSize: CGSize(width: 200, height: 100)),
                                    pieces: [piece(CGRect(x: 10, y: 10, width: 60, height: 18), "Text 1")])
        #expect(document.layers.count == 1)
        #expect(document.layers[0].children.map(\.name) == ["Shot", "Text 1"])
        // The piece's box is in the picture's OWN sibling space, so it lands
        // beside it inside the group rather than 50 points off it.
        #expect(document.layers[0].children[1].frame == CGRect(x: 10, y: 10, width: 60, height: 18))
    }
}
