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

    // MARK: - Text inside a box comes out inside that box

    /// A box that holds pieces arrives as a GROUP: its own body at the bottom,
    /// what sat on it above. That is what makes moving the button carry its
    /// label. See `docs/design/separate-into-layers.md`, "Which piece sits in
    /// which".
    private func box(_ rect: CGRect, _ name: String, body: String = "Picture",
                     children: [PhotonzDocument.SeparatedPiece] = [])
        -> PhotonzDocument.SeparatedPiece {
        PhotonzDocument.SeparatedPiece(frame: rect, ref: ImageRef(pixelSize: rect.size),
                                       name: name, bodyName: body, children: children)
    }

    @Test func aLabelInsideAButtonComesOutInsideThatButton() throws {
        var (document, id, _) = capture()
        let button = CGRect(x: 100, y: 200, width: 248, height: 60)
        let label = CGRect(x: 140, y: 220, width: 170, height: 25)
        document.separateIntoLayers(
            id: id, patched: ImageRef(pixelSize: CGSize(width: 400, height: 300)),
            pieces: [box(button, "Box 1", children: [piece(label, "Text 1")])])
        #expect(document.layers.map(\.name) == ["Background", "Box 1"])
        let group = try #require(document.layers.last)
        #expect(group.isGroup)
        #expect(group.children.map(\.name) == ["Picture", "Text 1"])
        // The box's own body first, so the words stay ON it rather than under it.
        #expect(group.children[0].frame == CGRect(x: 0, y: 0, width: 248, height: 60))
        #expect(group.children[1].frame == CGRect(x: 40, y: 20, width: 170, height: 25))
        #expect(group.localBounds == button)
    }

    @Test func movingTheBoxTakesItsContentsWithIt() throws {
        var (document, id, _) = capture()
        let button = CGRect(x: 100, y: 200, width: 248, height: 60)
        let made = document.separateIntoLayers(
            id: id, patched: ImageRef(pixelSize: CGSize(width: 400, height: 300)),
            pieces: [box(button, "Box 1",
                         children: [piece(CGRect(x: 140, y: 220, width: 170, height: 25), "Text 1")])])
        let groupID = try #require(made.first)
        document.updateLayer(id: groupID) { $0.frame.origin.x += 50 }
        let group = try #require(document.layer(id: groupID))
        // One move, both pieces: the label is stored against the group, so it
        // never has to be moved separately and can never be left behind.
        #expect(group.localBounds == button.offsetBy(dx: 50, dy: 0))
        #expect(group.children[1].frame == CGRect(x: 40, y: 20, width: 170, height: 25))
    }

    @Test func aBoxReadAsAShapeStillHoldsWhatSatOnIt() throws {
        var (document, id, _) = capture()
        let button = CGRect(x: 10, y: 10, width: 200, height: 50)
        document.separateIntoLayers(
            id: id, patched: ImageRef(pixelSize: CGSize(width: 400, height: 300)),
            pieces: [PhotonzDocument.SeparatedPiece(
                frame: button,
                content: .shape(fill: RGBA(r: 0, g: 0.5, b: 1), radii: CornerRadii(8),
                                borderWidth: 0, borderColor: nil),
                name: "Box 1", bodyName: "Fill",
                children: [piece(CGRect(x: 40, y: 25, width: 100, height: 20), "Text 1")])])
        let group = try #require(document.layers.last)
        #expect(group.children.map(\.name) == ["Fill", "Text 1"])
        guard case .annotation(let shape) = group.children[0].content else {
            Issue.record("the shape inside the group is not a shape any more")
            return
        }
        #expect(shape.cornerRadii == CornerRadii(8))
    }

    @Test func nestingGoesAsDeepAsTheScreenDoes() throws {
        var (document, id, _) = capture()
        let card = CGRect(x: 20, y: 20, width: 300, height: 200)
        let row = CGRect(x: 40, y: 60, width: 260, height: 50)
        let label = CGRect(x: 60, y: 75, width: 120, height: 20)
        document.separateIntoLayers(
            id: id, patched: ImageRef(pixelSize: CGSize(width: 400, height: 300)),
            pieces: [box(card, "Box 1",
                         children: [box(row, "Box 2", children: [piece(label, "Text 1")])])])
        let group = try #require(document.layers.last)
        let inner = try #require(group.children.last)
        #expect(inner.name == "Box 2")
        #expect(inner.children.map(\.name) == ["Picture", "Text 1"])
        // Three deep, and every frame is against the thing that holds it.
        #expect(inner.frame == CGRect(x: 20, y: 40, width: 0, height: 0))
        #expect(inner.children[1].frame == CGRect(x: 20, y: 15, width: 120, height: 20))
        #expect(group.localBounds == card)
    }

    @Test func aPieceWithNoParentStaysAtTheTop() {
        var (document, id, _) = capture()
        document.separateIntoLayers(
            id: id, patched: ImageRef(pixelSize: CGSize(width: 400, height: 300)),
            pieces: [piece(CGRect(x: 10, y: 10, width: 80, height: 20), "Text 1"),
                     box(CGRect(x: 100, y: 200, width: 200, height: 50), "Box 1",
                         children: [piece(CGRect(x: 120, y: 215, width: 100, height: 20), "Text 2")])])
        // The heading is nobody's child, so it is a row of its own rather than
        // being pushed into a group that does not fit it.
        #expect(document.layers.map(\.name) == ["Background", "Text 1", "Box 1"])
        #expect(document.layers[1].isGroup == false)
    }

    @Test func aWholeTreeIsStillOneUndoStep() {
        let (document, id, _) = capture()
        var history = History(document: document)
        history.perform {
            $0.separateIntoLayers(
                id: id, patched: ImageRef(pixelSize: CGSize(width: 400, height: 300)),
                pieces: (1...4).map { n in
                    self.box(CGRect(x: 10, y: 60 * n, width: 200, height: 50), "Box \(n)",
                             children: [self.piece(CGRect(x: 20, y: 60 * n + 15, width: 100, height: 20),
                                                   "Text \(n)")])
                })
        }
        #expect(history.current.layers.count == 5)
        history.undo()
        #expect(history.current.layers.count == 1)
        #expect(history.current.layers[0].name == "Background")
    }
}

/// The other half of what a big separation costs: a hundred and forty pieces
/// arriving in a list that shows five rows at a time. `gatheredAs` puts them in
/// one group so the list is one row longer rather than a hundred and forty.
@Suite("A separation that arrives gathered")
struct SeparateGatheredTests {

    private func capture() -> (document: PhotonzDocument, id: UUID) {
        let document = PhotonzDocument.withBaseImage(ImageRef(pixelSize: CGSize(width: 400, height: 300)))
        return (document, document.layers[0].id)
    }

    private func piece(_ y: CGFloat, _ name: String) -> PhotonzDocument.SeparatedPiece {
        let rect = CGRect(x: 10, y: y, width: 80, height: 18)
        return PhotonzDocument.SeparatedPiece(frame: rect, ref: ImageRef(pixelSize: rect.size), name: name)
    }

    private func patch() -> ImageRef { ImageRef(pixelSize: CGSize(width: 400, height: 300)) }

    @Test func gatheringLeavesOneRowBesideThePicture() {
        var (document, id) = capture()
        let pieces = (1...5).map { piece(CGFloat($0) * 20, "Text \($0)") }
        _ = document.separateIntoLayers(id: id, patched: patch(), pieces: pieces,
                                        gatheredAs: "Background pieces")
        #expect(document.layers.map(\.name) == ["Background", "Background pieces"])
        #expect(document.layers[1].children.map(\.name) == ["Text 1", "Text 2", "Text 3", "Text 4", "Text 5"])
    }

    @Test func thePiecesComeBackInTheOrderTheyWereHandedOver() throws {
        var (document, id) = capture()
        let pieces = (1...5).map { piece(CGFloat($0) * 20, "Text \($0)") }
        let made = document.separateIntoLayers(id: id, patched: patch(), pieces: pieces,
                                               gatheredAs: "Background pieces")
        #expect(made.count == 5)
        #expect(made.map { document.layer(id: $0)?.name } == ["Text 1", "Text 2", "Text 3", "Text 4", "Text 5"])
        // ...and every one of them is inside the gathering group, so the list
        // shows them only once its twist is opened.
        let group = try #require(document.layers.last)
        #expect(made.allSatisfy { document.parentID(of: $0) == group.id })
    }

    @Test func aPieceKeepsItsPlaceOnTheCanvas() throws {
        var (document, id) = capture()
        let made = document.separateIntoLayers(id: id, patched: patch(),
                                               pieces: [piece(120, "Text 1")],
                                               gatheredAs: "Background pieces")
        let piece = try #require(made.first)
        // Inside a group everything is stored against the group's corner, so
        // the frame on the layer is not the frame on the canvas: what has to
        // hold is where it LANDS.
        #expect(document.canvasLayer(id: piece)?.frame == CGRect(x: 10, y: 120, width: 80, height: 18))
    }

    @Test func notGatheringIsExactlyWhatItAlwaysWas() {
        var (document, id) = capture()
        _ = document.separateIntoLayers(id: id, patched: patch(),
                                        pieces: [piece(20, "Text 1"), piece(40, "Text 2")])
        #expect(document.layers.map(\.name) == ["Background", "Text 1", "Text 2"])
    }

    @Test func nothingToGatherGathersNothing() {
        var (document, id) = capture()
        #expect(document.separateIntoLayers(id: id, patched: patch(), pieces: [],
                                            gatheredAs: "Background pieces").isEmpty)
        #expect(document.layers.map(\.name) == ["Background"])
    }

    /// The price of gathering, written down rather than argued about: the one
    /// thing a fresh separation is good for is clicking a piece on the canvas
    /// and dragging it, and a group in the way takes that.
    @Test func aClickOnTheCanvasPicksTheWholeGroupRatherThanThePieceUnderIt() throws {
        var (document, id) = capture()
        let made = document.separateIntoLayers(id: id, patched: patch(),
                                               pieces: [piece(120, "Text 1")],
                                               gatheredAs: "Background pieces")
        let group = try #require(document.layers.last)
        let inThePiece = CGPoint(x: 50, y: 129)
        let picked = try #require(document.selectionTarget(at: inThePiece, inside: nil))
        #expect(picked.id == group.id)
        #expect(picked.id != made.first)
        // ...and once you have double clicked in, the piece itself answers.
        #expect(document.selectionTarget(at: inThePiece, inside: group.id)?.id == made.first)
    }

    /// The same click with the pieces loose, which is what it does today.
    @Test func loosePiecesArePickedByOneClick() throws {
        var (document, id) = capture()
        let made = document.separateIntoLayers(id: id, patched: patch(),
                                               pieces: [piece(120, "Text 1")])
        #expect(document.selectionTarget(at: CGPoint(x: 50, y: 129), inside: nil)?.id == made.first)
    }

    @Test func theGatheringGroupSitsDirectlyOverThePictureAndNotOverEverything() {
        var (document, id) = capture()
        document.layers.append(Layer(name: "Arrow",
                                     content: .image(ImageRef(pixelSize: .init(width: 4, height: 4))),
                                     frame: CGRect(x: 0, y: 0, width: 40, height: 40)))
        _ = document.separateIntoLayers(id: id, patched: patch(), pieces: [piece(20, "Text 1")],
                                        gatheredAs: "Background pieces")
        #expect(document.layers.map(\.name) == ["Background", "Background pieces", "Arrow"])
    }
}
