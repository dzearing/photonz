import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// The eight resize squares and the corner dots of a layer turned in 3D are
/// drawn on the card the camera sees (`PhotonzDocument.drawnMap`). A press is
/// read in the same place, and a drag from one resizes the card along its own
/// plane, holding the opposite edge where it is drawn.
@Suite("Resize squares on a card turned in space")
struct TurnedCardHandlesTests {

    static let canvas = CGSize(width: 1120, height: 760)
    static let frame = CGRect(x: 300, y: 250, width: 340, height: 220)

    static func card(rotationY: Double = 40, rotationX: Double = 0) -> Layer {
        var layer = Space3DTests.box(frame)
        layer.turn3D = LayerTurn3D(rotationX: rotationX, rotationY: rotationY)
        return layer
    }

    static func document(_ layer: Layer) -> PhotonzDocument {
        PhotonzDocument(canvasSize: canvas, layers: [layer])
    }

    static func close(_ a: CGPoint, _ b: CGPoint, within: CGFloat) -> Bool {
        abs(a.x - b.x) <= within && abs(a.y - b.y) <= within
    }

    @Test("A point where a square is drawn on the turned card goes back to that square")
    func drawnPointGoesBack() throws {
        let layer = Self.card()
        let document = Self.document(layer)
        let map = try #require(document.drawnMap(of: layer.id))
        for handle in ResizeHandle.allCases {
            let flat = Handles.point(for: handle, in: Self.frame)
            let drawn = try #require(map.apply(flat))
            let back = try #require(document.handleSpacePoint(fromDrawn: drawn, of: layer.id))
            #expect(Self.close(back, flat, within: 0.01), "\(handle)")
        }
    }

    @Test("A layer drawn flat has no plane to go back through")
    func flatLayerHasNone() {
        let layer = Space3DTests.box(Self.frame)
        #expect(Self.document(layer).handleSpacePoint(fromDrawn: CGPoint(x: 300, y: 250), of: layer.id) == nil)
    }

    @Test("The pointer over a drawn square cues that square, and over the flat spot it cues nothing")
    func cueReadsTheDrawnSquare() throws {
        let layer = Self.card()
        let document = Self.document(layer)
        let map = try #require(document.drawnMap(of: layer.id))
        for handle in ResizeHandle.allCases {
            let drawn = try #require(map.apply(Handles.point(for: handle, in: Self.frame)))
            let local = try #require(document.handleSpacePoint(fromDrawn: drawn, of: layer.id))
            let cue = CanvasPointer.cue(at: drawn, layer: layer, frame: Self.frame, zoom: 1,
                                        captionsEnabled: false, offersRotation: true,
                                        handleSpace: local)
            #expect(cue == .resize(handle), "\(handle)")
        }
        // Where the flat card's top right corner would be, the swung card is
        // not: nothing is drawn there, so nothing is promised.
        let empty = CGPoint(x: Self.frame.maxX, y: Self.frame.minY)
        let local = try #require(document.handleSpacePoint(fromDrawn: empty, of: layer.id))
        let cue = CanvasPointer.cue(at: empty, layer: layer, frame: Self.frame, zoom: 1,
                                    captionsEnabled: false, offersRotation: true,
                                    handleSpace: local)
        #expect(cue != .resize(.topRight))
    }

    @Test("A card seen in space offers no flat knob: its knob is the one drawn off the edge the camera sees")
    func noFlatKnobInSpace() throws {
        let layer = Self.card()
        let document = Self.document(layer)
        let knob = try #require(layer.rotateKnobPoint(zoom: 1))
        let local = try #require(document.handleSpacePoint(fromDrawn: knob, of: layer.id))
        let cue = CanvasPointer.cue(at: knob, layer: layer, frame: Self.frame, zoom: 1,
                                    captionsEnabled: false, offersRotation: true,
                                    handleSpace: local)
        #expect(cue != .rotate)
    }

    /// The plain resize a corner drag makes, in the start frame's own space.
    static func corner(_ handle: ResizeHandle) -> (CGPoint) -> CGRect {
        { local in Handles.resize(frame, dragging: handle, to: local, preserveAspect: false) }
    }

    static func drawn(_ point: CGPoint, of layer: Layer, framed box: CGRect) -> CGPoint? {
        var moved = layer
        moved.frame = box
        return document(moved).drawnMap(of: layer.id)?.apply(point)
    }

    @Test("A corner dragged on a swung card lands under the pointer, and the opposite corner stays put",
          arguments: [(40.0, 0.0), (-55, 0), (30, 25)])
    func cornerFollowsThePointer(rotationY: Double, rotationX: Double) throws {
        let layer = Self.card(rotationY: rotationY, rotationX: rotationX)
        let document = Self.document(layer)
        let map = try #require(document.drawnMap(of: layer.id))
        let anchorBefore = try #require(map.apply(Handles.point(for: .topLeft, in: Self.frame)))
        let startCorner = try #require(map.apply(CGPoint(x: Self.frame.maxX, y: Self.frame.maxY)))
        let pointer = CGPoint(x: startCorner.x + 60, y: startCorner.y + 45)
        let resized = try #require(document.spaceResizedFrame(
            of: layer.id, start: Self.frame, handle: .bottomRight, pointer: pointer,
            resize: Self.corner(.bottomRight)))
        // Bigger, by about the drag, along the card's own plane.
        #expect(resized.width > Self.frame.width && resized.height > Self.frame.height)
        let anchorAfter = try #require(Self.drawn(Handles.point(for: .topLeft, in: resized),
                                                  of: layer, framed: resized))
        #expect(Self.close(anchorAfter, anchorBefore, within: 0.5))
        let cornerAfter = try #require(Self.drawn(CGPoint(x: resized.maxX, y: resized.maxY),
                                                  of: layer, framed: resized))
        #expect(Self.close(cornerAfter, pointer, within: 0.5))
    }

    @Test("Back on the press point the card is the size it started")
    func noMoveNoChange() throws {
        let layer = Self.card()
        let document = Self.document(layer)
        let map = try #require(document.drawnMap(of: layer.id))
        let pointer = try #require(map.apply(Handles.point(for: .right, in: Self.frame)))
        let resized = try #require(document.spaceResizedFrame(
            of: layer.id, start: Self.frame, handle: .right, pointer: pointer,
            resize: Self.corner(.right)))
        #expect(abs(resized.minX - Self.frame.minX) < 0.01 && abs(resized.width - Self.frame.width) < 0.01)
        #expect(resized.minY == Self.frame.minY && resized.height == Self.frame.height)
    }

    @Test("A layer drawn flat has no plane resize: the flat one stands")
    func flatHasNoPlaneResize() {
        let layer = Space3DTests.box(Self.frame)
        #expect(Self.document(layer).spaceResizedFrame(
            of: layer.id, start: Self.frame, handle: .right, pointer: CGPoint(x: 700, y: 360),
            resize: Self.corner(.right)) == nil)
    }

    @Test("A piece inside a group is resized in canvas space, wherever the group sits")
    func nestedPiece() throws {
        var child = Space3DTests.box(CGRect(x: 40, y: 30, width: 200, height: 120))
        child.turn3D = LayerTurn3D(rotationY: 35)
        let group = Layer(name: "Group", content: .group(GroupContent(children: [child])),
                          frame: CGRect(x: 200, y: 150, width: 0, height: 0))
        let document = PhotonzDocument(canvasSize: Self.canvas, layers: [group])
        let canvasFrame = try #require(document.canvasBounds(of: child.id))
        let map = try #require(document.drawnMap(of: child.id))
        let anchorBefore = try #require(map.apply(Handles.point(for: .left, in: canvasFrame)))
        let edge = try #require(map.apply(Handles.point(for: .right, in: canvasFrame)))
        let resized = try #require(document.spaceResizedFrame(
            of: child.id, start: canvasFrame, handle: .right,
            pointer: CGPoint(x: edge.x + 40, y: edge.y),
            resize: { Handles.resize(canvasFrame, dragging: .right, to: $0, preserveAspect: false) }))
        #expect(resized.width > canvasFrame.width)
        var moved = document
        moved.updateLayer(id: child.id) { $0.frame = resized.offsetBy(dx: -200, dy: -150) }
        let anchorAfter = try #require(moved.drawnMap(of: child.id)?
            .apply(Handles.point(for: .left, in: resized)))
        #expect(Self.close(anchorAfter, anchorBefore, within: 0.5))
    }
}
