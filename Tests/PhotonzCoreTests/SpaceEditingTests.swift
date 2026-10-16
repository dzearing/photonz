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

    @Test("A picked layer wears both arcs and the depth arrow at once, with nothing to hover")
    func pickedLayerWearsAll() {
        // The user, 2026-10-13: the grippers show when the layer is picked,
        // not only while the pointer rests on the knob.
        #expect(SpaceHandles.showing(holding: nil) == SpaceHandles.Showing(arcs: true, depth: true))
        // Swinging or tipping keeps everything out; pushing in depth puts
        // the arcs away so only the arrow in hand is drawn.
        #expect(SpaceHandles.showing(holding: .swing) == SpaceHandles.Showing(arcs: true, depth: true))
        #expect(SpaceHandles.showing(holding: .tip) == SpaceHandles.Showing(arcs: true, depth: true))
        #expect(SpaceHandles.showing(holding: .depth) == SpaceHandles.Showing(arcs: false, depth: true))
    }

    /// A small chip, 44 by 22, flat: top edge at y 100, middle at y 111.
    static let chip = SpaceHandles(topMid: CGPoint(x: 300, y: 100), middle: CGPoint(x: 300, y: 111),
                                   pivot: CGPoint(x: 300, y: 111))

    @Test("On a small layer the depth arrow reaches its top right corner, and the corner keeps it")
    func boxKeepsItsCorner() {
        let corner = CGPoint(x: 322, y: 100)
        // Without the box in the argument the arrow would take the corner...
        #expect(Self.chip.hit(at: corner, arcs: true, depth: true) == .depth)
        // ...but the resize square is drawn right there, so it keeps it.
        #expect(Self.chip.hit(at: corner, arcs: true, depth: true, boxReach: 0) == nil)
        // A press on the arrow's head, clear of the box, still pushes.
        let head = Self.chip.depthArrow.head
        #expect(Self.chip.hit(at: head, arcs: true, depth: true, boxReach: nil) == .depth)
        // Where the arrow is nearer than the box mark in reach, the arrow wins.
        let onShaft = CGPoint(x: 318, y: 93)
        #expect(Self.chip.hit(at: onShaft, arcs: true, depth: true, boxReach: 6) == .depth)
        // A tie goes to the box: a resize has no other way in on the canvas.
        #expect(Self.chip.hit(at: onShaft, arcs: true, depth: true,
                              boxReach: Self.chip.reach(of: .depth, at: onShaft)) == nil)
    }

    /// A small square, 40 across, flat: top edge at y 100, middle at y 120.
    static let square = SpaceHandles(topMid: CGPoint(x: 300, y: 100), middle: CGPoint(x: 300, y: 120),
                                     pivot: CGPoint(x: 300, y: 120))

    @Test("On a small layer's body the depth arrow takes only a press on its drawing")
    func bodyKeepsPressesOffTheArrow() {
        let h = Self.square
        // Fourteen right and six up from the middle: inside the box, about
        // six points off the drawn shaft. The press that moves the layer.
        let besideShaft = CGPoint(x: 314, y: 114)
        #expect(h.reach(of: .depth, at: besideShaft) > SpaceHandles.drawnReach)
        #expect(h.reach(of: .depth, at: besideShaft) <= SpaceHandles.grabReach)
        // Off the body the generous slack still catches it...
        #expect(h.hit(at: besideShaft, arcs: true, depth: true) == .depth)
        // ...on the body it is the layer's.
        #expect(h.hit(at: besideShaft, arcs: true, depth: true, onBody: true) == nil)
        // A press on the drawn shaft still pushes in depth, body or not.
        let onShaft = CGPoint(x: 312, y: 108)
        #expect(h.hit(at: onShaft, arcs: true, depth: true, onBody: true) == .depth)
        // So does one past the box on the arrow's slack, where the body ends.
        let pastHead = CGPoint(x: 332, y: 88)
        #expect(h.hit(at: pastHead, arcs: true, depth: true, onBody: false) == .depth)
    }

    @Test("A key ring under the 3D handles keeps the press nearer to it than to them")
    func markKeepsWhatItIsNearer() {
        let h = Self.square
        // The ring sits on the middle, where the pivot is, with the playhead
        // on its key. Its upper right edge is in the arrow's slack...
        let ringEdge = CGPoint(x: 302.5, y: 117.5)
        #expect(h.hit(at: ringEdge, arcs: true, depth: true) == .depth)
        // ...but nearer the ring, so the ring keeps it.
        let toRing = hypot(ringEdge.x - 300, ringEdge.y - 120)
        #expect(h.hit(at: ringEdge, arcs: true, depth: true, markReach: toRing) == nil)
        // Up the shaft, nearer the arrow than the ring, the arrow still pushes.
        let shaft = CGPoint(x: 309, y: 111)
        #expect(h.hit(at: shaft, arcs: true, depth: true,
                      markReach: hypot(shaft.x - 300, shaft.y - 120)) == .depth)
    }

    @Test("On a layer about 76 wide the tall arc passes its top right corner, and the corner keeps it")
    func tallArcYieldsToCorner() {
        let h = SpaceHandles(topMid: CGPoint(x: 300, y: 100), middle: CGPoint(x: 300, y: 130),
                             pivot: CGPoint(x: 300, y: 130))
        let corner = CGPoint(x: 338, y: 100)
        #expect(h.hit(at: corner, arcs: true, depth: false) == .tip)
        #expect(h.hit(at: corner, arcs: true, depth: false, boxReach: 0) == nil)
        // The arc's upper end, well clear of the box, still tips.
        #expect(h.hit(at: h.tipArc.end, arcs: true, depth: false, boxReach: nil) == .tip)
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

    // MARK: A tilt keys like a move

    @Test("On a layer whose place is keyed, a tilt is a key at the playhead, the way a move is")
    func tiltKeysWhereThePlaceIsKeyed() throws {
        var (doc, id) = Self.withTitle()
        // The track's diamond keys where it is, its size, angle and opacity.
        let keyed = doc.toggleTransformKey(layerID: id, atDocumentTimeMS: 3000)
        #expect(keyed)
        doc.setSpaceTurn(LayerTurn3D(rotationY: 90), layerID: id, atDocumentTimeMS: 3000)
        #expect(doc.keyCount(layerID: id, .motion(.rotationY)) == 1)
        #expect(doc.keyDiamond(layerID: id, .motion(.rotationY), atDocumentTimeMS: 3000) == .onKey)
        // A second later the arc swings it back: a second key, and a swing.
        doc.setSpaceTurn(LayerTurn3D(rotationY: 0), layerID: id, atDocumentTimeMS: 4000)
        #expect(doc.keyCount(layerID: id, .motion(.rotationY)) == 2)
        #expect(doc.spaceValue(.rotationY, layerID: id, atDocumentTimeMS: 3000) == 90)
        #expect(doc.spaceValue(.rotationY, layerID: id, atDocumentTimeMS: 4000) == 0)
        let half = try #require(doc.spaceValue(.rotationY, layerID: id, atDocumentTimeMS: 3500))
        #expect(half > 0 && half < 90)
        // The layer's own value never moved: the keys hold the tilt.
        #expect(doc.layer(id: id)?.turn3D == nil)
    }

    @Test("A tilt between the place's keys holds the old tilt at the keys either side, as a reframe does")
    func tiltBetweenPlaceKeysAnchors() {
        var (doc, id) = Self.withTitle()
        doc.setSpaceValue(.rotationX, 10, layerIDs: [id], atDocumentTimeMS: 2000)
        _ = doc.startKeying(layerID: id, .motion(.position), atDocumentTimeMS: 3000)
        _ = doc.setKeyedValue(.point(CGPoint(x: 300, y: 100)), layerID: id, .motion(.position),
                              atDocumentTimeMS: 5000)
        doc.setSpaceValue(.rotationX, 40, layerIDs: [id], atDocumentTimeMS: 4000)
        #expect(doc.keyCount(layerID: id, .motion(.rotationX)) == 3)
        #expect(doc.spaceValue(.rotationX, layerID: id, atDocumentTimeMS: 3000) == 10)
        #expect(doc.spaceValue(.rotationX, layerID: id, atDocumentTimeMS: 4000) == 40)
        #expect(doc.spaceValue(.rotationX, layerID: id, atDocumentTimeMS: 5000) == 10)
        #expect(doc.layer(id: id)?.turn3D?.rotationX == 10)
    }

    @Test("A 3D value keyed makes the others key too: Depth typed while Rotation Y is keyed")
    func oneSpaceKeyKeysTheRest() {
        var (doc, id) = Self.withTitle()
        _ = doc.startKeying(layerID: id, .motion(.rotationY), atDocumentTimeMS: 3000)
        doc.setSpaceValue(.depth, -300, layerIDs: [id], atDocumentTimeMS: 3000)
        #expect(doc.keyCount(layerID: id, .motion(.depth)) == 1)
        #expect(doc.spaceValue(.depth, layerID: id, atDocumentTimeMS: 3000) == -300)
        doc.pushDepth(by: 100, layerIDs: [id], atDocumentTimeMS: 3500)
        #expect(doc.keyCount(layerID: id, .motion(.depth)) == 2)
        #expect(doc.spaceValue(.depth, layerID: id, atDocumentTimeMS: 3500) == -200)
    }

    @Test("A layer with nothing keyed takes a tilt as its own value, as a move with no keys does")
    func tiltWithNothingKeyedIsItsOwn() {
        var (doc, id) = Self.withTitle()
        doc.setSpaceTurn(LayerTurn3D(rotationY: 30), layerID: id, atDocumentTimeMS: 3000)
        #expect(doc.keyCount(layerID: id, .motion(.rotationY)) == 0)
        #expect(doc.layer(id: id)?.turn3D?.rotationY == 30)
    }

    @Test("On a layer with any key, even a fade, a tilt keys itself (the user's answer, 2026-10-13)")
    func tiltOnAFadingLayerKeys() {
        var (doc, id) = Self.withTitle()
        _ = doc.startKeying(layerID: id, .motion(.opacity), atDocumentTimeMS: 3000)
        doc.setSpaceTurn(LayerTurn3D(rotationY: 30), layerID: id, atDocumentTimeMS: 3000)
        #expect(doc.keyCount(layerID: id, .motion(.rotationY)) == 1)
        #expect(doc.spaceValue(.rotationY, layerID: id, atDocumentTimeMS: 3000) == 30)
    }

    @Test("How tilted a layer is drawn: its near edge over its far edge, 1 for a flat layer")
    func drawnTilt() {
        var (doc, id) = Self.withTitle()
        #expect(doc.drawnTilt(of: id, atDocumentTimeMS: 3000) == 1)
        let keyed = doc.toggleTransformKey(layerID: id, atDocumentTimeMS: 3000)
        #expect(keyed)
        doc.setSpaceValue(.rotationY, 60, layerIDs: [id], atDocumentTimeMS: 3000)
        doc.setSpaceValue(.rotationY, 0, layerIDs: [id], atDocumentTimeMS: 4000)
        #expect(doc.drawnTilt(of: id, atDocumentTimeMS: 3000) > 1.1)
        #expect(doc.drawnTilt(of: id, atDocumentTimeMS: 3500) > 1.01)
        #expect(abs(doc.drawnTilt(of: id, atDocumentTimeMS: 4000) - 1) < 0.001)
        // Pushed straight back it is smaller, not tilted.
        doc.setSpaceValue(.depth, -400, layerIDs: [id], atDocumentTimeMS: 4000)
        #expect(abs(doc.drawnTilt(of: id, atDocumentTimeMS: 4000) - 1) < 0.001)
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
