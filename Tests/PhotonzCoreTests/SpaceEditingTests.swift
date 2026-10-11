import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Tilt, flip and push layers in depth from the canvas and the panel
/// (`tilt-flip-and-push-layers-in-depth-from-the-canv`, `SpaceEditing.swift`,
/// mock `video-depth.html`, design A: arcs on the turn knob).
@Suite("2.5D: turning a layer by hand")
struct SpaceEditingTests {

    // MARK: Fixtures

    /// Ten seconds, with a title on screen from 2s to 8s.
    static func withTitle() -> (PhotonzDocument, UUID) {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 1920, height: 1080))
        var title = Layer(name: "Hello",
                          content: .text(TextContent(string: "Hello", fontSize: 48)),
                          frame: CGRect(x: 100, y: 100, width: 400, height: 80))
        title.time = LayerTime(inMS: 2000, outMS: 8000)
        doc.layers = [title]
        doc.durationMS = 10_000
        return (doc, title.id)
    }

    /// A picture with no time at all.
    static func still() -> (PhotonzDocument, UUID, UUID) {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600))
        let a = Layer(name: "A", content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#FF0000")),
                      frame: CGRect(x: 10, y: 10, width: 100, height: 100))
        let b = Layer(name: "B", content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#00FF00")),
                      frame: CGRect(x: 200, y: 10, width: 100, height: 100))
        doc.layers = [a, b]
        return (doc, a.id, b.id)
    }

    // MARK: The handles

    /// A layer lying flat with its top edge at y 100 and its middle at y 200.
    static let flat = SpaceHandles(topMid: CGPoint(x: 300, y: 100), middle: CGPoint(x: 300, y: 200),
                                   pivot: CGPoint(x: 300, y: 200))

    @Test("The knob floats 18 points off the top edge, the same as the flat knob always has")
    func knobPlace() {
        #expect(Self.flat.knob == CGPoint(x: 300, y: 82))
        #expect(Self.flat.up == CGPoint(x: 0, y: -1))
    }

    @Test("A press on the knob itself stays the flat turn, even with the arcs out")
    func knobKeepsItsMiddle() {
        #expect(Self.flat.hit(at: Self.flat.knob, arcs: true, depth: true) == nil)
        #expect(Self.flat.hit(at: CGPoint(x: 303, y: 80), arcs: true, depth: true) == nil)
    }

    @Test("The flat arc's ends swing, the tall arc tips, the arrow pushes in depth")
    func eachHandleAnswers() {
        let h = Self.flat
        // The flat arc runs along the top edge through the knob.
        #expect(h.hit(at: CGPoint(x: 300 - 22, y: 80), arcs: true, depth: false) == .swing)
        #expect(h.hit(at: CGPoint(x: 300 + 22, y: 80), arcs: true, depth: false) == .swing)
        // The tall arc stands beside it.
        let side = h.tipArc.points(8)[4]
        #expect(h.hit(at: side, arcs: true, depth: false) == .tip)
        // The arrow leaves the pivot up and to the right.
        #expect(h.hit(at: CGPoint(x: 318, y: 182), arcs: false, depth: true) == .depth)
    }

    @Test("Hidden handles take no press")
    func hiddenTakesNothing() {
        let h = Self.flat
        #expect(h.hit(at: CGPoint(x: 278, y: 80), arcs: false, depth: false) == nil)
        #expect(h.hit(at: CGPoint(x: 318, y: 182), arcs: false, depth: false) == nil)
        // A press in the layer's middle is a move, never the arrow.
        #expect(h.hit(at: CGPoint(x: 300, y: 200), arcs: true, depth: true) == nil)
    }

    @Test("The arcs come out on the knob and stay while the hand is over the layer")
    func revealAndHold() {
        let h = Self.flat
        let drawn = CGRect(x: 100, y: 100, width: 400, height: 200)
        #expect(h.reveals(at: CGPoint(x: 305, y: 85)))
        #expect(!h.reveals(at: CGPoint(x: 300, y: 200)))
        #expect(h.holds(at: CGPoint(x: 300, y: 200), over: drawn))
        #expect(h.holds(at: CGPoint(x: 340, y: 60), over: drawn))
        #expect(!h.holds(at: CGPoint(x: 700, y: 500), over: drawn))
    }

    @Test("On a layer turned a quarter, the arcs turn with its top edge")
    func turnedLayer() {
        let h = SpaceHandles(topMid: CGPoint(x: 400, y: 200), middle: CGPoint(x: 300, y: 200),
                             pivot: CGPoint(x: 300, y: 200))
        #expect(h.knob == CGPoint(x: 418, y: 200))
        // The flat arc now runs up and down through the knob.
        #expect(h.hit(at: CGPoint(x: 420, y: 200 - 22), arcs: true, depth: false) == .swing)
    }

    // MARK: The drag

    @Test("Sideways on the flat arc swings: 150 points is 90 degrees")
    func swingDrag() {
        let turned = SpaceDrag.turned(LayerTurn3D(), by: .swing, delta: CGPoint(x: 150, y: 40),
                                      zoom: 1, snapped: false)
        #expect(turned.rotationY == 90)
        #expect(turned.rotationX == 0)
        #expect(SpaceDrag.readout(.swing, turned) == "Rotation Y 90°")
    }

    @Test("Up on the tall arc tips the top away; Shift steps in 15 degrees")
    func tipDrag() {
        let up = SpaceDrag.turned(LayerTurn3D(), by: .tip, delta: CGPoint(x: 0, y: -50),
                                  zoom: 1, snapped: false)
        #expect(up.rotationX == 30)
        let snapped = SpaceDrag.turned(LayerTurn3D(), by: .tip, delta: CGPoint(x: 0, y: -40),
                                       zoom: 1, snapped: true)
        #expect(snapped.rotationX == 30)
        let down = SpaceDrag.turned(LayerTurn3D(rotationX: 10), by: .tip, delta: CGPoint(x: 0, y: 20),
                                    zoom: 1, snapped: false)
        #expect(down.rotationX == -2)
    }

    @Test("A turn stops at a whole flip either way")
    func turnBounds() {
        let far = SpaceDrag.turned(LayerTurn3D(), by: .swing, delta: CGPoint(x: 5000, y: 0),
                                   zoom: 1, snapped: false)
        #expect(far.rotationY == 180)
    }

    @Test("Up the arrow pushes away, scaled by the zoom, and never past the camera")
    func depthDrag() {
        let away = SpaceDrag.turned(LayerTurn3D(), by: .depth, delta: CGPoint(x: 0, y: -40),
                                    zoom: 0.5, snapped: false)
        #expect(away.depth == -200)
        #expect(SpaceDrag.readout(.depth, away) == "Depth -200")
        let near = SpaceDrag.turned(LayerTurn3D(), by: .depth, delta: CGPoint(x: -400, y: 400),
                                    zoom: 1, snapped: false, nearest: 900)
        #expect(near.depth == 900)
    }

    // MARK: The document

    @Test("A value set on a layer with no keys is its own, and putting it back leaves no turn")
    func setOwnValue() {
        var (doc, a, _) = Self.still()
        doc.setSpaceValue(.rotationY, 40, layerIDs: [a], atDocumentTimeMS: 0)
        #expect(doc.layer(id: a)?.turn3D?.rotationY == 40)
        #expect(doc.isSeenInSpace)
        doc.setSpaceValue(.rotationY, 0, layerIDs: [a], atDocumentTimeMS: 0)
        #expect(doc.layer(id: a)?.turn3D == nil)
        #expect(!doc.isSeenInSpace)
    }

    @Test("Several picked layers take one value together, and Mixed is nil")
    func severalAtOnce() {
        var (doc, a, b) = Self.still()
        doc.setSpaceValue(.depth, -300, layerIDs: [a, b], atDocumentTimeMS: 0)
        #expect(doc.sharedSpaceValue(.depth, layerIDs: [a, b], atDocumentTimeMS: 0) == -300)
        doc.setSpaceValue(.depth, 50, layerIDs: [b], atDocumentTimeMS: 0)
        #expect(doc.sharedSpaceValue(.depth, layerIDs: [a, b], atDocumentTimeMS: 0) == nil)
    }

    @Test("A keyed value set from the canvas is a key at the playhead, and the flip plays between keys")
    func keyedFlip() throws {
        var (doc, id) = Self.withTitle()
        // Turn it 40 on Y, key it at 3s, then 180 at 4s: a flip over one second.
        doc.setSpaceValue(.rotationY, 40, layerIDs: [id], atDocumentTimeMS: 3000)
        let started = doc.startKeying(layerID: id, .motion(.rotationY), atDocumentTimeMS: 3000)
        #expect(started)
        doc.setSpaceTurn(LayerTurn3D(rotationY: 220), layerID: id, atDocumentTimeMS: 4000)
        #expect(doc.keyCount(layerID: id, .motion(.rotationY)) == 2)
        #expect(doc.spaceValue(.rotationY, layerID: id, atDocumentTimeMS: 3000) == 40)
        #expect(doc.spaceValue(.rotationY, layerID: id, atDocumentTimeMS: 4000) == 220)
        let half = try #require(doc.spaceValue(.rotationY, layerID: id, atDocumentTimeMS: 3500))
        #expect(half > 40 && half < 220)
        // The layer's own value is untouched by the key.
        #expect(doc.layer(id: id)?.turn3D?.rotationY == 40)
    }

    @Test("Reset 3D Rotation faces the camera again, keys and all, and keeps the depth")
    func resetRotation() {
        var (doc, id) = Self.withTitle()
        doc.setSpaceValue(.rotationX, 20, layerIDs: [id], atDocumentTimeMS: 3000)
        doc.setSpaceValue(.depth, -120, layerIDs: [id], atDocumentTimeMS: 3000)
        doc.startKeying(layerID: id, .motion(.rotationY), atDocumentTimeMS: 3000)
        #expect(doc.hasSpaceRotation(layerIDs: [id]))
        doc.resetSpaceRotation(layerIDs: [id])
        #expect(!doc.hasSpaceRotation(layerIDs: [id]))
        #expect(doc.layer(id: id)?.turn3D?.depth == -120)
        #expect(doc.keyCount(layerID: id, .motion(.rotationY)) == 0)
    }

    @Test("Bring Nearer and Send Further step 100 points from where it shows")
    func pushDepth() {
        var (doc, a, _) = Self.still()
        doc.pushDepth(by: PhotonzDocument.depthStep, layerIDs: [a], atDocumentTimeMS: 0)
        #expect(doc.layer(id: a)?.turn3D?.depth == 100)
        doc.pushDepth(by: -2 * PhotonzDocument.depthStep, layerIDs: [a], atDocumentTimeMS: 0)
        #expect(doc.layer(id: a)?.turn3D?.depth == -100)
    }

    @Test("The camera's values key on the document clock and reset to the camera every document starts with")
    func cameraKeys() throws {
        var (doc, _) = Self.withTitle()
        #expect(doc.cameraValue(.cameraPerspective, atDocumentTimeMS: 0) == SceneCamera.defaultPerspective)
        #expect(!doc.hasCameraChanges)
        doc.setCameraValue(.cameraDepth, 0, atDocumentTimeMS: 1000)
        doc.toggleCameraKey(.cameraDepth, atDocumentTimeMS: 1000)
        #expect(doc.cameraKeyDiamond(.cameraDepth, atDocumentTimeMS: 1000) == .onKey)
        doc.setCameraValue(.cameraDepth, 400, atDocumentTimeMS: 3000)
        #expect(doc.cameraKeyCount(.cameraDepth) == 2)
        #expect(doc.cameraKeyDiamond(.cameraDepth, atDocumentTimeMS: 2000) == .betweenKeys)
        let middle = try #require(doc.cameraValue(.cameraDepth, atDocumentTimeMS: 2000))
        #expect(middle > 0 && middle < 400)
        // The renderer sees the same push.
        #expect(doc.drawn(atTimeMS: 3000).camera?.depth == 400)
        #expect(doc.hasCameraChanges)
        doc.resetCamera()
        #expect(doc.camera == nil)
    }

    @Test("A camera value with no keys is the camera's own, and the last key going keeps its value")
    func cameraOwnValue() {
        var (doc, _) = Self.withTitle()
        doc.setCameraValue(.cameraPerspective, 60, atDocumentTimeMS: 0)
        #expect(doc.camera?.perspective == 60)
        doc.toggleCameraKey(.cameraX, atDocumentTimeMS: 500)
        doc.setCameraValue(.cameraX, 80, atDocumentTimeMS: 500)
        doc.toggleCameraKey(.cameraX, atDocumentTimeMS: 500)
        #expect(doc.cameraKeyCount(.cameraX) == 0)
        #expect(doc.camera?.x == 80)
    }
}
