import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Layers turn about X and Y and move in depth under one camera
/// (`layers-can-turn-about-x-and-y-and-move-in-depth`, `Space3D.swift`).
@Suite("2.5D: layers turned in space")
struct Space3DTests {

    static let canvas = CGSize(width: 1920, height: 1080)

    static func box(_ frame: CGRect, hex: String = "#FF0000", name: String = "Card") -> Layer {
        Layer(name: name,
              content: .annotation(AnnotationContent(shape: .rectangle, strokeWidth: 0, colorHex: hex,
                                                     start: .zero,
                                                     end: CGPoint(x: frame.width, y: frame.height),
                                                     fillColorHex: hex)),
              frame: frame)
    }

    static func close(_ a: CGPoint, _ b: CGPoint, within: CGFloat = 0.01) -> Bool {
        abs(a.x - b.x) <= within && abs(a.y - b.y) <= within
    }

    // MARK: Projection

    @Test("A flat layer at depth 0 lands exactly where it is stored, whatever the perspective")
    func flatIsUntouched() throws {
        for angle in [0.0, 20, 45, 90] {
            let projection = Projection3D(camera: SceneCamera(perspective: angle), canvas: Self.canvas)
            let box = CGRect(x: 100, y: 200, width: 300, height: 150)
            let quad = try #require(Space3D.quad(of: box, through: .identity, projection))
            #expect(Self.close(quad[0], CGPoint(x: 100, y: 200)))
            #expect(Self.close(quad[2], CGPoint(x: 400, y: 350)))
        }
    }

    @Test("Moving toward the viewer by half the eye distance draws it twice the size about the middle")
    func depthMagnifies() throws {
        let projection = Projection3D(camera: nil, canvas: Self.canvas)
        // 45 degrees top to bottom: the eye is (1080 / 2) / tan(22.5) away.
        #expect(abs(projection.eyeDistance - 540 / tan(22.5 * .pi / 180)) < 1e-6)
        let turn = LayerTurn3D(depth: projection.eyeDistance / 2)
        let box = CGRect(x: 860, y: 440, width: 200, height: 200)
        let quad = try #require(Space3D.quad(of: box, through: turn.affine(pivot: CGPoint(x: 960, y: 540)),
                                             projection))
        #expect(Self.close(quad[0], CGPoint(x: 760, y: 340)))
        #expect(Self.close(quad[2], CGPoint(x: 1160, y: 740)))
    }

    @Test("With perspective off, depth changes nothing and a turn only foreshortens")
    func noPerspective() throws {
        let projection = Projection3D(camera: SceneCamera(perspective: 0), canvas: Self.canvas)
        #expect(!projection.hasPerspective)
        let box = CGRect(x: 0, y: 0, width: 200, height: 100)
        let turn = LayerTurn3D(rotationY: 60, depth: 500).affine(pivot: CGPoint(x: 100, y: 50))
        let quad = try #require(Space3D.quad(of: box, through: turn, projection))
        // cos 60 = 0.5: half as wide, the same height, no smaller far edge.
        #expect(Self.close(quad[0], CGPoint(x: 50, y: 0)))
        #expect(Self.close(quad[1], CGPoint(x: 150, y: 0)))
        #expect(Self.close(quad[2], CGPoint(x: 150, y: 100)))
    }

    @Test("Swung on Y, the edge that goes away is shorter than the one that comes near")
    func perspectiveForeshortens() throws {
        let projection = Projection3D(camera: nil, canvas: Self.canvas)
        let box = CGRect(x: 760, y: 340, width: 400, height: 400)
        let turn = LayerTurn3D(rotationY: 40).affine(pivot: CGPoint(x: 960, y: 540))
        let quad = try #require(Space3D.quad(of: box, through: turn, projection))
        let left = quad[3].y - quad[0].y
        let right = quad[2].y - quad[1].y
        // Positive swings the right edge away.
        #expect(right < left)
        #expect(left > 400)
        #expect(right < 400)
    }

    @Test("Tipped on X, positive takes the top edge away")
    func tipTakesTheTopAway() throws {
        let projection = Projection3D(camera: nil, canvas: Self.canvas)
        let box = CGRect(x: 760, y: 340, width: 400, height: 400)
        let quad = try #require(Space3D.quad(of: box, through: LayerTurn3D(rotationX: 30)
            .affine(pivot: CGPoint(x: 960, y: 540)), projection))
        let top = quad[1].x - quad[0].x
        let bottom = quad[2].x - quad[3].x
        #expect(top < bottom)
    }

    @Test("Pivot depth turns a face about a point behind it, like a cube's middle")
    func pivotDepth() {
        let pivot = CGPoint(x: 960, y: 540)
        // A face 400 wide turned 90 degrees about a point 200 behind it ends
        // up as the cube's right side: its middle 200 to the right, 200 back.
        let turn = LayerTurn3D(rotationY: 90, pivotDepth: -200).affine(pivot: pivot)
        let middle = turn.apply(Point3D(pivot))
        #expect(abs(middle.x - 1160) < 1e-6)
        #expect(abs(middle.z - -200) < 1e-6)
    }

    @Test("A camera moved right moves the picture left, and pushed in makes it bigger")
    func cameraMoves() throws {
        let box = CGRect(x: 960, y: 540, width: 100, height: 100)
        let moved = Projection3D(camera: SceneCamera(x: 50), canvas: Self.canvas)
        let quad = try #require(Space3D.quad(of: box, through: .identity, moved))
        #expect(Self.close(quad[0], CGPoint(x: 910, y: 540)))
        let base = Projection3D(camera: nil, canvas: Self.canvas)
        let pushed = Projection3D(camera: SceneCamera(depth: base.eyeDistance / 2), canvas: Self.canvas)
        let near = try #require(Space3D.quad(of: box, through: .identity, pushed))
        #expect(Self.close(near[2], CGPoint(x: 960 + 200, y: 540 + 200)))
    }

    @Test("Something at the eye or behind it is not drawn")
    func behindTheEye() {
        let projection = Projection3D(camera: nil, canvas: Self.canvas)
        let turn = LayerTurn3D(depth: projection.eyeDistance + 10).affine(pivot: CGPoint(x: 960, y: 540))
        #expect(Space3D.quad(of: CGRect(x: 900, y: 500, width: 100, height: 100), through: turn,
                             projection) == nil)
    }

    // MARK: The map and the back face

    @Test("The plane map sends the box's corners onto the quad and back")
    func homographyRoundTrips() throws {
        let box = CGRect(x: 100, y: 100, width: 300, height: 200)
        let quad = [CGPoint(x: 120, y: 90), CGPoint(x: 380, y: 130), CGPoint(x: 360, y: 280),
                    CGPoint(x: 90, y: 310)]
        let map = try #require(Homography(box: box, to: quad))
        let corners = [CGPoint(x: 100, y: 100), CGPoint(x: 400, y: 100), CGPoint(x: 400, y: 300),
                       CGPoint(x: 100, y: 300)]
        for (corner, target) in zip(corners, quad) {
            let landed = try #require(map.apply(corner))
            #expect(Self.close(landed, target, within: 1e-6))
        }
        let inverse = try #require(map.inverted)
        let inside = CGPoint(x: 250, y: 170)
        let there = try #require(map.apply(inside))
        let back = try #require(inverse.apply(there))
        #expect(Self.close(back, inside, within: 1e-6))
    }

    @Test("A card faces the viewer until it is swung past a quarter turn, and its back faces away")
    func backFace() throws {
        let projection = Projection3D(camera: nil, canvas: Self.canvas)
        let box = CGRect(x: 760, y: 340, width: 400, height: 400)
        let pivot = CGPoint(x: 960, y: 540)
        func faces(_ degrees: Double) throws -> Bool {
            let quad = try #require(Space3D.quad(of: box, through: LayerTurn3D(rotationY: degrees)
                .affine(pivot: pivot), projection))
            return Space3D.facesViewer(quad)
        }
        #expect(try faces(0))
        #expect(try faces(80))
        #expect(try !faces(100))
        #expect(try !faces(180))
        #expect(try faces(-80))
    }

    // MARK: Order

    @Test("A group keeping its contents in space draws the furthest first, ties in stack order")
    func depthOrder() {
        var near = Self.box(CGRect(x: 0, y: 0, width: 10, height: 10), name: "Near")
        near.turn3D = LayerTurn3D(depth: 100)
        var far = Self.box(CGRect(x: 0, y: 0, width: 10, height: 10), name: "Far")
        far.turn3D = LayerTurn3D(depth: -100)
        let flatA = Self.box(CGRect(x: 0, y: 0, width: 10, height: 10), name: "A")
        let flatB = Self.box(CGRect(x: 0, y: 0, width: 10, height: 10), name: "B")
        let order = PhotonzDocument.depthOrder(of: [near, flatA, far, flatB], offset: .zero,
                                               inherited: .identity)
        #expect(order == [2, 1, 3, 0])
    }

    // MARK: Keys

    @Test("Rotation Y, Rotation X, Depth and Pivot depth key and ease like any other value")
    func keyed() throws {
        var card = Self.box(CGRect(x: 760, y: 340, width: 400, height: 400))
        card.time = LayerTime(inMS: 0, outMS: 2000)
        var document = PhotonzDocument(canvasSize: Self.canvas, layers: [card])
        document.durationMS = 2000
        let id = card.id
        #expect(card.keyableProperties.contains(.motion(.rotationY)))
        #expect(card.keyableProperties.contains(.motion(.depth)))
        document.startKeying(layerID: id, .motion(.rotationY), atDocumentTimeMS: 0)
        document.setKeyedValue(.number(180), layerID: id, .motion(.rotationY), atDocumentTimeMS: 1000)
        document.startKeying(layerID: id, .motion(.depth), atDocumentTimeMS: 0)
        document.setKeyedValue(.number(-400), layerID: id, .motion(.depth), atDocumentTimeMS: 1000)
        func turn(at ms: Int) -> LayerTurn3D? {
            document.drawn(atTimeMS: ms).layer(id: id)?.turn3D
        }
        #expect(turn(at: 0)?.isFlat != false)
        let half = try #require(turn(at: 500))
        #expect(half.rotationY > 10 && half.rotationY < 170)
        #expect(half.depth < 0 && half.depth > -400)
        let end = try #require(turn(at: 1000))
        #expect(abs(end.rotationY - 180) < 1e-6)
        #expect(abs(end.depth - -400) < 1e-6)
        // The stored layer is the one you drew: nothing is baked in.
        #expect(document.layer(id: id)?.turn3D == nil)
    }

    @Test("A motion on Rotation Y follows its curve: ease in and out is slow at both ends")
    func eased() {
        let motion = LayerMotion(property: .rotationY, from: .number(0), to: .number(180),
                                 timing: MotionTiming(startMS: 0, durationMS: 1000),
                                 curve: .easeInOut, repeats: .once)
        guard case let .number(early) = motion.value(atMS: 100, cycleMS: 1000),
              case let .number(middle) = motion.value(atMS: 500, cycleMS: 1000) else {
            Issue.record("not a number")
            return
        }
        #expect(early < 18)
        #expect(abs(middle - EasingCurve.easeInOut.value(at: 0.5) * 180) < 1e-6)
        let layer = MotionProperty.rotationY.applied(.number(45), to: Self.box(.zero), authored: Self.box(.zero))
        #expect(layer.turn3D?.rotationY == 45)
    }

    @Test("The camera's keys move it on the document's clock")
    func cameraKeys() {
        var document = PhotonzDocument(canvasSize: Self.canvas, layers: [Self.box(CGRect(x: 0, y: 0, width: 10, height: 10))])
        document.durationMS = 4000
        document.camera = SceneCamera(motions: [
            LayerMotion(property: .cameraDepth, from: .number(0), to: .number(200),
                        timing: MotionTiming(startMS: 0, durationMS: 4000), curve: .linear, repeats: .once),
        ])
        #expect(document.hasMotion)
        #expect(document.drawn(atTimeMS: 2000).camera?.depth == 100)
        #expect(abs((document.drawn(atTimeMS: 4000).camera?.depth ?? 0) - 200) < 0.1)
        #expect(document.camera?.depth == 0)
    }

    // MARK: Old documents and the file

    @Test("A document nobody turned writes no 3D keys and reads back the same")
    func oldDocumentsRoundTrip() throws {
        let document = PhotonzDocument(canvasSize: Self.canvas, layers: [Self.box(CGRect(x: 1, y: 2, width: 3, height: 4))])
        let data = try JSONEncoder().encode(document)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(!text.contains("turn3D"))
        #expect(!text.contains("camera"))
        #expect(!text.contains("keeps3D"))
        let back = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        #expect(back == document)
        #expect(back.camera == nil)
        #expect(!back.isSeenInSpace)
    }

    @Test("A turned layer, a group keeping 3D and a camera round trip, writing only what is set")
    func turnedRoundTrips() throws {
        var card = Self.box(CGRect(x: 1, y: 2, width: 3, height: 4))
        card.turn3D = LayerTurn3D(rotationY: 30, showsBackFace: false)
        var group = Layer(name: "Cube", content: .group(GroupContent(children: [card])), frame: .zero)
        if case .group(var content) = group.content {
            content.keeps3D = true
            group.content = .group(content)
        }
        var document = PhotonzDocument(canvasSize: Self.canvas, layers: [group])
        document.camera = SceneCamera(perspective: 30, x: 12, focus: CameraFocus(depth: -50, amount: 3))
        let data = try JSONEncoder().encode(document)
        let back = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        #expect(back == document)
        let turn = try JSONEncoder().encode(LayerTurn3D(rotationY: 30))
        #expect(String(data: turn, encoding: .utf8) == "{\"rotationY\":30}")
    }

    @Test("A document drawn bigger turns the same and pushes as far, in its own units")
    func magnified() {
        var card = Self.box(CGRect(x: 10, y: 10, width: 100, height: 100))
        card.turn3D = LayerTurn3D(rotationY: 30, depth: 50, pivotDepth: -20)
        var document = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300), layers: [card])
        document.camera = SceneCamera(depth: 10, x: 5, y: 6)
        let big = document.magnified(by: 2)
        #expect(big.layers[0].turn3D == LayerTurn3D(rotationY: 30, depth: 100, pivotDepth: -40))
        #expect(big.camera?.depth == 20 && big.camera?.x == 10 && big.camera?.y == 12)
        #expect(big.camera?.perspective == SceneCamera.defaultPerspective)
    }

    // MARK: Where it is drawn and where it is clicked

    @Test("The outline follows the projected corners, and the click lands where the card is drawn")
    func clickAndOutline() throws {
        var card = Self.box(CGRect(x: 760, y: 340, width: 400, height: 400))
        card.turn3D = LayerTurn3D(rotationY: 60)
        let document = PhotonzDocument(canvasSize: Self.canvas, layers: [card])
        #expect(document.isSeenInSpace)
        let quad = try #require(document.drawnQuad(of: card.id))
        let expected = try #require(Space3D.quad(of: card.frame, through: card.spaceAffine() ?? .identity,
                                                 document.projection))
        for (a, b) in zip(quad, expected) { #expect(Self.close(a, b)) }
        // Swung 60 degrees, the card is much narrower than its box: a point
        // inside the box near its right edge is empty canvas now...
        #expect(document.hitTest(CGPoint(x: 1140, y: 540)) == nil)
        // ...and the middle still lands on it.
        #expect(document.hitTest(CGPoint(x: 960, y: 540))?.id == card.id)
        // So does a point just inside its drawn right edge.
        let rightEdge = (quad[1].x + quad[2].x) / 2
        #expect(document.hitTest(CGPoint(x: rightEdge - 4, y: 540))?.id == card.id)
    }

    @Test("A card that hides its back is not drawn and not clicked once it has turned away")
    func hiddenBackIsNotClicked() {
        var card = Self.box(CGRect(x: 760, y: 340, width: 400, height: 400))
        card.turn3D = LayerTurn3D(rotationY: 150, showsBackFace: false)
        let document = PhotonzDocument(canvasSize: Self.canvas, layers: [card])
        #expect(document.hitTest(CGPoint(x: 960, y: 540)) == nil)
        card.turn3D?.showsBackFace = nil
        #expect(PhotonzDocument(canvasSize: Self.canvas, layers: [card]).hitTest(CGPoint(x: 960, y: 540))?.id == card.id)
    }

    @Test("A flattened group turns as one card, and a child's own tilt rides on it")
    func flattenedGroup() throws {
        var child = Self.box(CGRect(x: 0, y: 0, width: 400, height: 400))
        child.turn3D = LayerTurn3D(rotationX: 20)
        var group = Layer(name: "Card", content: .group(GroupContent(children: [child])),
                          frame: CGRect(x: 760, y: 340, width: 0, height: 0))
        group.turn3D = LayerTurn3D(rotationY: 50)
        // A shadow gives it a card of its own: it cannot draw straight through.
        group.style.shadows = [ShadowStyle()]
        let document = PhotonzDocument(canvasSize: Self.canvas, layers: [group])
        #expect(!group.drawsStraightThrough)
        let chain = try #require(document.spaceChain(of: child.id))
        #expect(chain.steps.count == 2)
        let quad = try #require(document.drawnQuad(of: child.id))
        // Swung right edge away by the group: the right edge is shorter.
        #expect(quad[2].y - quad[1].y < quad[3].y - quad[0].y)
        // The click finds the child through both.
        let middle = CGPoint(x: (quad[0].x + quad[2].x) / 2, y: (quad[0].y + quad[2].y) / 2)
        #expect(document.hitTest(middle)?.id == child.id)
    }

    @Test("A group keeping its contents in space turns them with it and clicks the nearest")
    func keptGroup() throws {
        var front = Self.box(CGRect(x: 0, y: 0, width: 400, height: 400), name: "Front")
        front.turn3D = LayerTurn3D(pivotDepth: -200)
        var side = Self.box(CGRect(x: 0, y: 0, width: 400, height: 400), name: "Side")
        side.turn3D = LayerTurn3D(rotationY: 90, pivotDepth: -200)
        var content = GroupContent(children: [front, side])
        content.keeps3D = true
        var cube = Layer(name: "Cube", content: .group(content), frame: CGRect(x: 760, y: 340, width: 0, height: 0))
        cube.turn3D = LayerTurn3D(rotationY: -45)
        let document = PhotonzDocument(canvasSize: Self.canvas, layers: [cube])
        #expect(cube.keepsItsContentsInSpace)
        // Turned 45 degrees, both faces show, and each is carried by the
        // cube's turn and its own.
        let frontQuad = try #require(document.drawnQuad(of: front.id))
        let sideQuad = try #require(document.drawnQuad(of: side.id))
        #expect(Space3D.facesViewer(frontQuad))
        #expect(Space3D.facesViewer(sideQuad))
        // The two faces meet at the cube's front edge, in the middle.
        #expect(Self.close(frontQuad[1], sideQuad[0], within: 0.5))
        #expect(document.hitTest(CGPoint(x: (frontQuad[0].x + frontQuad[1].x) / 2,
                                         y: (frontQuad[0].y + frontQuad[3].y) / 2))?.id == front.id)
        #expect(document.hitTest(CGPoint(x: (sideQuad[0].x + sideQuad[1].x) / 2,
                                         y: (sideQuad[0].y + sideQuad[3].y) / 2))?.id == side.id)
    }

    @Test("Nothing turned and the camera left alone: nothing about clicking changes")
    func flatDocumentsClickAsBefore() {
        var turned = Self.box(CGRect(x: 100, y: 100, width: 200, height: 100))
        turned.transform = LayerTransform(rotation: .pi / 4)
        let document = PhotonzDocument(canvasSize: Self.canvas, layers: [turned])
        #expect(!document.isSeenInSpace)
        #expect(document.drawnQuad(of: turned.id) == nil)
        #expect(document.hitTest(CGPoint(x: 200, y: 150))?.id == turned.id)
    }
}
