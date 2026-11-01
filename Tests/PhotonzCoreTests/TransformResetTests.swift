import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Reset each transform mode on its own (`reset-each-transform-mode-on-its-own-with-a-dot`,
/// prototype `selection-transform.html`, `changed()` and `resetStage()`):
/// right-clicking a mode on the selection chip resets Size, Skew & distort or
/// 3D without touching the other two, and a changed mode wears a dot.
@Suite("Transform reset, one mode at a time")
struct TransformResetTests {

    static let ref = ImageRef(id: UUID(), pixelSize: CGSize(width: 800, height: 500))

    /// A picture at its own size, a shape, on a still picture.
    static func still() -> (PhotonzDocument, UUID, UUID) {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 2000, height: 1500))
        let picture = Layer(name: "Shot", content: .image(ref),
                            frame: CGRect(x: 100, y: 100, width: 800, height: 500))
        let shape = Layer(name: "Box", content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#FF0000")),
                          frame: CGRect(x: 10, y: 10, width: 100, height: 100))
        doc.layers = [picture, shape]
        return (doc, picture.id, shape.id)
    }

    static let skewed = LayerReshape(offsets: [CGPoint(x: 0.1, y: 0), CGPoint(x: 0.1, y: 0), .zero, .zero])

    // MARK: What counts as changed

    @Test("A picture fresh at its own size has nothing to reset in any mode")
    func freshIsUnchanged() {
        let (doc, picture, shape) = Self.still()
        for mode in TransformMode.offered {
            #expect(!doc.hasTransformChange(TransformReset(mode), layerID: picture))
            #expect(!doc.hasTransformChange(TransformReset(mode), layerID: shape))
        }
        #expect(!doc.hasTransformChange(.all, layerID: picture))
    }

    @Test("Size is changed by a new size or a turn; a picture's own size is its pixels")
    func sizeChanged() {
        var (doc, picture, shape) = Self.still()
        doc.updateLayer(id: picture) { $0.frame.size = CGSize(width: 400, height: 250) }
        #expect(doc.hasTransformChange(.size, layerID: picture))
        #expect(!doc.hasTransformChange(.reshape, layerID: picture))
        #expect(!doc.hasTransformChange(.space, layerID: picture))
        // A shape has no size of its own to go back to: only its turn counts.
        doc.updateLayer(id: shape) { $0.frame.size = CGSize(width: 300, height: 40) }
        #expect(!doc.hasTransformChange(.size, layerID: shape))
        doc.updateLayer(id: shape) { $0.transform.rotation = 0.3 }
        #expect(doc.hasTransformChange(.size, layerID: shape))
    }

    @Test("Half a point either way is still the picture's own size")
    func sizeTolerance() {
        var (doc, picture, _) = Self.still()
        doc.updateLayer(id: picture) { $0.frame.size = CGSize(width: 800.3, height: 499.8) }
        #expect(!doc.hasTransformChange(.size, layerID: picture))
    }

    @Test("Skew & distort is changed by a reshape or an old slant, and nothing else")
    func reshapeChanged() {
        var (doc, picture, shape) = Self.still()
        doc.updateLayer(id: picture) { $0.reshape = Self.skewed }
        #expect(doc.hasTransformChange(.reshape, layerID: picture))
        #expect(!doc.hasTransformChange(.size, layerID: picture))
        doc.updateLayer(id: shape) { $0.transform.skewX = 0.2 }
        #expect(doc.hasTransformChange(.reshape, layerID: shape))
    }

    @Test("3D is changed by a tip, a swing or a depth, or a key on any of them")
    func spaceChanged() {
        var (doc, picture, shape) = Self.still()
        doc.updateLayer(id: picture) { $0.turn3D = LayerTurn3D(depth: -120) }
        #expect(doc.hasTransformChange(.space, layerID: picture))
        doc.updateLayer(id: shape) { $0.turn3D = LayerTurn3D(rotationY: 25) }
        #expect(doc.hasTransformChange(.space, layerID: shape))
        #expect(!doc.hasTransformChange(.size, layerID: shape))
    }

    @Test("A flip is not a change of size, shape or depth")
    func flipIsNotAReset() {
        var (doc, picture, _) = Self.still()
        doc.updateLayer(id: picture) { $0.transform.flipHorizontal = true }
        #expect(!doc.hasTransformChange(.all, layerID: picture))
    }

    // MARK: What each reset puts back

    @Test("Reset Size: the picture's own size and no turn, about the same middle")
    func resetSize() {
        var (doc, picture, _) = Self.still()
        doc.updateLayer(id: picture) {
            $0.frame = CGRect(x: 300, y: 300, width: 400, height: 100)
            $0.transform.rotation = 0.5
            $0.reshape = Self.skewed
            $0.turn3D = LayerTurn3D(rotationX: 10, depth: 50)
            $0.transform.flipVertical = true
        }
        doc.resetTransform(.size, layerIDs: [picture])
        let layer = doc.layer(id: picture)
        #expect(layer?.frame == CGRect(x: 100, y: 100, width: 800, height: 500))
        #expect(layer?.transform.rotation == 0)
        // The other modes and the flip stay.
        #expect(layer?.reshape == Self.skewed)
        #expect(layer?.turn3D?.rotationX == 10)
        #expect(layer?.turn3D?.depth == 50)
        #expect(layer?.transform.flipVertical == true)
        #expect(!doc.hasTransformChange(.size, layerID: picture))
    }

    @Test("Reset Size on a shape keeps its size and takes away the turn")
    func resetSizeOnAShape() {
        var (doc, _, shape) = Self.still()
        doc.updateLayer(id: shape) {
            $0.frame.size = CGSize(width: 300, height: 40)
            $0.transform.rotation = 0.4
        }
        doc.resetTransform(.size, layerIDs: [shape])
        #expect(doc.layer(id: shape)?.frame.size == CGSize(width: 300, height: 40))
        #expect(doc.layer(id: shape)?.transform.rotation == 0)
    }

    @Test("Reset Skew & Distort puts the picture back to its box and leaves size and 3D")
    func resetReshape() {
        var (doc, picture, _) = Self.still()
        doc.updateLayer(id: picture) {
            $0.reshape = Self.skewed
            $0.transform.skewY = 0.1
            $0.transform.rotation = 0.5
            $0.turn3D = LayerTurn3D(rotationY: 30)
        }
        doc.resetTransform(.reshape, layerIDs: [picture])
        let layer = doc.layer(id: picture)
        #expect(layer?.reshape == nil)
        #expect(layer?.transform.skewY == 0)
        #expect(layer?.transform.rotation == 0.5)
        #expect(layer?.turn3D?.rotationY == 30)
    }

    @Test("Reset 3D faces the camera at depth 0, keys and all, and leaves size and shape")
    func resetSpace() {
        var (doc, picture, _) = Self.still()
        doc.updateLayer(id: picture) {
            $0.turn3D = LayerTurn3D(rotationX: 10, rotationY: 20, depth: -150)
            $0.reshape = Self.skewed
            $0.transform.rotation = 0.2
        }
        doc.resetTransform(.space, layerIDs: [picture])
        let layer = doc.layer(id: picture)
        #expect(layer?.turn3D == nil)
        #expect(layer?.reshape == Self.skewed)
        #expect(layer?.transform.rotation == 0.2)
        #expect(!doc.hasTransformChange(.space, layerID: picture))
    }

    @Test("Reset 3D on a video takes the tip, swing and depth keys too")
    func resetSpaceKeys() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 1920, height: 1080))
        var title = Layer(name: "Hello", content: .text(TextContent(string: "Hello", fontSize: 48)),
                          frame: CGRect(x: 100, y: 100, width: 400, height: 80))
        title.time = LayerTime(inMS: 2000, outMS: 8000)
        doc.layers = [title]
        doc.durationMS = 10_000
        let id = title.id
        doc.setSpaceValue(.depth, -120, layerIDs: [id], atDocumentTimeMS: 3000)
        doc.startKeying(layerID: id, .motion(.depth), atDocumentTimeMS: 3000)
        doc.startKeying(layerID: id, .motion(.rotationY), atDocumentTimeMS: 3000)
        #expect(doc.hasTransformChange(.space, layerID: id))
        doc.resetTransform(.space, layerIDs: [id])
        #expect(doc.keyCount(layerID: id, .motion(.depth)) == 0)
        #expect(doc.keyCount(layerID: id, .motion(.rotationY)) == 0)
        #expect(!doc.hasTransformChange(.space, layerID: id))
    }

    @Test("Reset All puts back every mode and nothing else")
    func resetAll() {
        var (doc, picture, _) = Self.still()
        doc.updateLayer(id: picture) {
            $0.frame = CGRect(x: 300, y: 300, width: 400, height: 100)
            $0.transform.rotation = 0.5
            $0.reshape = Self.skewed
            $0.turn3D = LayerTurn3D(rotationX: 10, depth: 50)
            $0.name = "Kept"
        }
        doc.resetTransform(.all, layerIDs: [picture])
        for mode in TransformMode.offered { #expect(!doc.hasTransformChange(TransformReset(mode), layerID: picture)) }
        #expect(doc.layer(id: picture)?.name == "Kept")
    }

    @Test("A locked layer is never reset")
    func lockedStays() {
        var (doc, picture, _) = Self.still()
        doc.updateLayer(id: picture) {
            $0.transform.rotation = 0.5
            $0.isLocked = true
        }
        doc.resetTransform(.size, layerIDs: [picture])
        #expect(doc.layer(id: picture)?.transform.rotation == 0.5)
    }

    // MARK: The words

    @Test("The menu names each reset the way the chip names its mode")
    func titles() {
        #expect(TransformReset.size.title == "Reset Size")
        #expect(TransformReset.reshape.title == "Reset Skew & Distort")
        #expect(TransformReset.space.title == "Reset 3D")
        #expect(TransformReset.all.title == "Reset All")
        #expect(TransformReset(.reshape) == .reshape)
        #expect(TransformReset.all.modes == TransformMode.offered)
    }
}
