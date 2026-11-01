import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Skew & distort (`skew-distort-reshapes-the-picture-from-the-selec`,
/// prototype `selection-transform.html`): the chip's middle mode reshapes the
/// picture itself. Each corner's offset is stored as a share of the width and
/// height in the layer's own unturned plane, so turning, resizing and 3D all
/// act on the reshaped picture.
@Suite("Layer reshape: skew and distort")
struct LayerReshapeTests {

    static let box = CGRect(x: 100, y: 50, width: 200, height: 100)

    static func near(_ a: CGPoint, _ b: CGPoint, _ tolerance: CGFloat = 1e-6) -> Bool {
        hypot(a.x - b.x, a.y - b.y) <= tolerance
    }

    // MARK: The stored shape

    @Test("No reshape puts the corners on the box")
    func noneIsTheBox() {
        let r = LayerReshape()
        #expect(r.isNone)
        let c = r.corners(of: Self.box)
        #expect(c == [CGPoint(x: 100, y: 50), CGPoint(x: 300, y: 50),
                      CGPoint(x: 300, y: 150), CGPoint(x: 100, y: 150)])
        #expect(r.outerBox(of: Self.box) == Self.box)
    }

    @Test("Offsets are shares of the width and height, so a resize keeps the shape")
    func offsetsAreShares() {
        let r = LayerReshape(offsets: [CGPoint(x: 0.1, y: 0), .zero, CGPoint(x: 0, y: 0.2), .zero])
        #expect(!r.isNone)
        let c = r.corners(of: Self.box)
        #expect(Self.near(c[0], CGPoint(x: 120, y: 50)))
        #expect(Self.near(c[2], CGPoint(x: 300, y: 170)))
        let bigger = r.corners(of: CGRect(x: 100, y: 50, width: 400, height: 200))
        #expect(Self.near(bigger[0], CGPoint(x: 140, y: 50)))
        #expect(Self.near(bigger[2], CGPoint(x: 500, y: 290)))
    }

    @Test("The flat box round a reshaped picture holds every reshaped corner")
    func outerBoxHoldsTheCorners() {
        let r = LayerReshape(offsets: [CGPoint(x: -0.1, y: -0.2), .zero, CGPoint(x: 0.25, y: 0), .zero])
        let outer = r.outerBox(of: Self.box)
        #expect(Self.near(outer.origin, CGPoint(x: 80, y: 30)))
        #expect(abs(outer.width - 270) < 1e-6)
        #expect(abs(outer.height - 120) < 1e-6)
        // And back: the frame that box was drawn round.
        let frame = r.frame(forOuterBox: outer)
        #expect(Self.near(frame.origin, Self.box.origin))
        #expect(abs(frame.width - Self.box.width) < 1e-6 && abs(frame.height - Self.box.height) < 1e-6)
    }

    @Test("A frame read back from a resized outer box keeps the shape on that box")
    func frameFromResizedOuterBox() {
        let r = LayerReshape(offsets: [CGPoint(x: 0.2, y: 0), CGPoint(x: 0.1, y: 0), .zero, .zero])
        let outer = CGRect(x: 0, y: 0, width: 300, height: 90)
        let frame = r.frame(forOuterBox: outer)
        let back = r.outerBox(of: frame)
        #expect(Self.near(back.origin, outer.origin, 1e-6))
        #expect(abs(back.width - 300) < 1e-6 && abs(back.height - 90) < 1e-6)
    }

    @Test("The map from the box onto the reshape sends each corner home")
    func mapSendsCornersHome() throws {
        let r = LayerReshape(offsets: [CGPoint(x: 0.1, y: 0.05), CGPoint(x: -0.05, y: 0),
                                       CGPoint(x: 0, y: 0.1), CGPoint(x: 0.02, y: -0.03)])
        let map = try #require(r.map(of: Self.box))
        let boxCorners = LayerReshape().corners(of: Self.box)
        for (a, b) in zip(boxCorners, r.corners(of: Self.box)) {
            #expect(Self.near(try #require(map.apply(a)), b, 1e-6))
        }
    }

    @Test("It reads and writes as eight numbers, and an old layer reads as none")
    func codable() throws {
        let r = LayerReshape(offsets: [CGPoint(x: 0.1, y: 0), .zero, CGPoint(x: 0, y: -0.2), .zero])
        let data = try JSONEncoder().encode(r)
        let back = try JSONDecoder().decode(LayerReshape.self, from: data)
        #expect(back == r)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.hasPrefix("["))

        var layer = Layer(name: "Shot", content: .image(ImageRef(pixelSize: CGSize(width: 200, height: 100))),
                          frame: Self.box)
        let plain = try JSONEncoder().encode(layer)
        #expect(!(String(data: plain, encoding: .utf8) ?? "").contains("reshape"))
        #expect(try JSONDecoder().decode(Layer.self, from: plain).reshape == nil)
        layer.reshape = r
        let round = try JSONDecoder().decode(Layer.self, from: try JSONEncoder().encode(layer))
        #expect(round.reshape == r)
    }

    @Test("A broken list of offsets reads as none rather than failing the document")
    func brokenReadsAsNone() throws {
        let back = try JSONDecoder().decode(LayerReshape.self, from: Data("[0.1, 0.2]".utf8))
        #expect(back.isNone)
    }

    // MARK: The layer

    @Test("The layer's reshaped corners ride its turn")
    func layerCornersRideTheTurn() {
        var layer = Layer(name: "Shot", content: .image(ImageRef(pixelSize: CGSize(width: 200, height: 100))), frame: Self.box)
        layer.reshape = LayerReshape(offsets: [CGPoint(x: 0.1, y: 0), .zero, .zero, .zero])
        #expect(Self.near(layer.reshapedCorners[0], CGPoint(x: 120, y: 50)))
        layer.transform.rotation = .pi / 2
        // A quarter turn about the middle (200, 100): (120, 50) goes to (250, 20).
        #expect(Self.near(layer.reshapedCorners[0], CGPoint(x: 250, y: 20), 1e-6))
    }

    @Test("A click lands on the reshaped picture, not the box it came from")
    func clickOnTheReshape() {
        var layer = Layer(name: "Shot", content: .image(ImageRef(pixelSize: CGSize(width: 200, height: 100))), frame: Self.box)
        // The top left corner pulled well up and left: (60, 10).
        layer.reshape = LayerReshape(offsets: [CGPoint(x: -0.2, y: -0.4), .zero, .zero, .zero])
        #expect(layer.contains(canvasPoint: CGPoint(x: 75, y: 25)))
        // The top right of the box is still in, the space under the pulled
        // corner's new slope is not.
        #expect(layer.contains(canvasPoint: CGPoint(x: 290, y: 60)))
        #expect(!layer.contains(canvasPoint: CGPoint(x: 70, y: 140)))
    }

    // MARK: What a drag does

    @Test("Distort moves one corner by the drag, as a share of the size")
    func distortMovesOneCorner() {
        let r = ReshapeDrag.distorted(LayerReshape(), corner: 2, by: CGPoint(x: 20, y: -10),
                                      size: Self.box.size, keystone: false)
        #expect(Self.near(r.offsets[2], CGPoint(x: 0.1, y: -0.1)))
        #expect(r.offsets[0] == .zero && r.offsets[1] == .zero && r.offsets[3] == .zero)
    }

    @Test("Keystone mirrors the corner across the same edge")
    func keystoneMirrors() {
        let r = ReshapeDrag.distorted(LayerReshape(), corner: 0, by: CGPoint(x: 20, y: 10),
                                      size: Self.box.size, keystone: true)
        #expect(Self.near(r.offsets[0], CGPoint(x: 0.1, y: 0.1)))
        // Top right comes in by the same amount, at the same height.
        #expect(Self.near(r.offsets[1], CGPoint(x: -0.1, y: 0.1)))
        let c = r.corners(of: Self.box)
        #expect(abs((c[0].x - Self.box.minX) - (Self.box.maxX - c[1].x)) < 1e-6)
        let bottom = ReshapeDrag.distorted(LayerReshape(), corner: 3, by: CGPoint(x: -10, y: 0),
                                           size: Self.box.size, keystone: true)
        #expect(Self.near(bottom.offsets[2], CGPoint(x: 0.05, y: 0)))
    }

    @Test("Skew on a top or bottom pill slides that edge along itself")
    func skewTopEdge() {
        let r = ReshapeDrag.skewed(LayerReshape(), edge: .top, by: CGPoint(x: 40, y: 25),
                                   size: Self.box.size)
        #expect(Self.near(r.offsets[0], CGPoint(x: 0.2, y: 0)))
        #expect(Self.near(r.offsets[1], CGPoint(x: 0.2, y: 0)))
        #expect(r.offsets[2] == .zero && r.offsets[3] == .zero)
        // The edge stays level: only along itself.
        let c = r.corners(of: Self.box)
        #expect(c[0].y == c[1].y)
    }

    @Test("Skew on a side pill slides that side up or down")
    func skewSide() {
        let r = ReshapeDrag.skewed(LayerReshape(), edge: .right, by: CGPoint(x: 30, y: -20),
                                   size: Self.box.size)
        #expect(Self.near(r.offsets[1], CGPoint(x: 0, y: -0.2)))
        #expect(Self.near(r.offsets[2], CGPoint(x: 0, y: -0.2)))
        #expect(r.offsets[0] == .zero && r.offsets[3] == .zero)
    }

    @Test("A skew starts from the shape already there")
    func skewBuildsOnTheShape() {
        let start = LayerReshape(offsets: [CGPoint(x: 0.1, y: 0.1), .zero, .zero, .zero])
        let r = ReshapeDrag.skewed(start, edge: .bottom, by: CGPoint(x: -20, y: 0), size: Self.box.size)
        #expect(Self.near(r.offsets[0], CGPoint(x: 0.1, y: 0.1)))
        #expect(Self.near(r.offsets[2], CGPoint(x: -0.1, y: 0)))
        #expect(Self.near(r.offsets[3], CGPoint(x: -0.1, y: 0)))
    }

    @Test("The skew's angle is the slant of the side it tips")
    func skewAngle() {
        // 100 across the 100 high box tips the sides 45 degrees.
        #expect(abs(ReshapeDrag.skewDegrees(edge: .top, by: CGPoint(x: 100, y: 0), size: Self.box.size) - 45) < 1e-6)
        #expect(abs(ReshapeDrag.skewDegrees(edge: .left, by: CGPoint(x: 0, y: -200), size: Self.box.size) + 45) < 1e-6)
    }

    // MARK: The chip and the tag

    @Test("The chip offers Size, Skew & distort, 3D in that order")
    func chipOrder() {
        #expect(TransformMode.offered == [.size, .reshape, .space])
        #expect(TransformMode.reshape.title == "Skew & distort")
    }

    @Test("Resting on a grip in Skew & distort says what it does, briefly")
    func tagWords() {
        #expect(SelectionTag.does(.corner(.topLeft), mode: .reshape) == "Distort · ⇧ keystone")
        #expect(SelectionTag.does(.edge(.top), mode: .reshape) == "Skew along this edge")
        #expect(SelectionTag.does(.knob, mode: .reshape) == "Turn · double-click for 0°")
        #expect(SelectionTag.resting(mode: .reshape, size: CGSize(width: 300, height: 210), rotation: 0,
                                     turn: nil, name: "Screenshot") == "Skew & distort · Screenshot")
        let long = SelectionTag.resting(mode: .reshape, size: .zero, rotation: 0, turn: nil,
                                        name: "A very long layer name that goes on and on")
        #expect(long.count <= 30)
        #expect(long.hasPrefix("Skew & distort · "))
        #expect(SelectionTag.reshaping(.edge(.top), skew: 12.4, keystone: false) == "Skew 12°")
        #expect(SelectionTag.reshaping(.corner(.topLeft), skew: 0, keystone: false) == "Distort")
        #expect(SelectionTag.reshaping(.corner(.topLeft), skew: 0, keystone: true) == "Keystone")
    }
}
