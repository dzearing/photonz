import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Every transform handle answers the pointer before you click
/// (`every-transform-handle-answers-the-pointer-befor`, `HandleHover.swift`).
@Suite("Handle hover: the handle a press would take lights up")
struct HandleHoverTests {

    static func square(_ x: CGFloat, _ y: CGFloat, _ handle: ResizeHandle) -> HandleMark {
        HandleMark(center: CGPoint(x: x, y: y), shape: .square(8), role: .resize(handle))
    }

    static func dot(_ x: CGFloat, _ y: CGFloat, size: CGFloat = 10) -> HandleMark {
        HandleMark(center: CGPoint(x: x, y: y), shape: .circle(size), role: .grab)
    }

    static let knob = HandleMark(center: CGPoint(x: 150, y: 82), shape: .circle(10), role: .rotate)

    /// A box from (100, 100) to (200, 160): four corners, four edge squares,
    /// a knob above it, and a corner dot just inside the top left.
    static let marks: [HandleMark] = [
        square(100, 100, .topLeft), square(150, 100, .top), square(200, 100, .topRight),
        square(200, 130, .right), square(200, 160, .bottomRight), square(150, 160, .bottom),
        square(100, 160, .bottomLeft), square(100, 130, .left),
        knob, dot(110, 110, size: 7),
    ]

    @Test("No cue, nothing lit: the pointer over bare picture or a layer's body lights no handle")
    func nothingWithoutACue() {
        #expect(HandleHover.lit(cue: nil, at: CGPoint(x: 100, y: 100), among: Self.marks) == nil)
    }

    @Test("A resize cue lights the square of THAT handle, even along an edge far from it")
    func resizeLightsItsOwnSquare() {
        let corner = HandleHover.lit(cue: .resize(.topLeft), at: CGPoint(x: 101, y: 99), among: Self.marks)
        #expect(corner?.role == .resize(.topLeft))
        // Edge grab: the press takes the top edge anywhere along it, close to
        // the top-left corner too, and it is the top edge's square that lights,
        // never the corner the pointer happens to be nearer.
        let edge = HandleHover.lit(cue: .resize(.top), at: CGPoint(x: 112, y: 100), among: Self.marks)
        #expect(edge?.role == .resize(.top))
        #expect(edge?.center == CGPoint(x: 150, y: 100))
    }

    @Test("A rotate cue lights the knob")
    func rotateLightsTheKnob() {
        #expect(HandleHover.lit(cue: .rotate, at: CGPoint(x: 152, y: 84), among: Self.marks) == Self.knob)
    }

    @Test("A grab cue lights the nearest grab dot in reach, and nothing when none is near")
    func grabLightsTheDotUnderThePointer() {
        let lit = HandleHover.lit(cue: .grab, at: CGPoint(x: 112, y: 111), among: Self.marks)
        #expect(lit?.center == CGPoint(x: 110, y: 110))
        // A grab with no dot under it (a caption pill, a caliper's number):
        // the open hand says it, and no handle lights.
        #expect(HandleHover.lit(cue: .grab, at: CGPoint(x: 150, y: 130), among: Self.marks) == nil)
        // Two dots in reach: the nearer one.
        let ends = [Self.dot(10, 10), Self.dot(24, 10)]
        #expect(HandleHover.lit(cue: .grab, at: CGPoint(x: 19, y: 10), among: ends)?.center
            == CGPoint(x: 24, y: 10))
    }

    @Test("A grab cue never lights a resize square or the knob")
    func grabLightsOnlyGrabs() {
        // Between the corner square and the corner dot: the dot, never the square.
        #expect(HandleHover.lit(cue: .grab, at: CGPoint(x: 104, y: 104), among: Self.marks)?.role == .grab)
        let onlySquares = Array(Self.marks.prefix(8))
        #expect(HandleHover.lit(cue: .grab, at: CGPoint(x: 100, y: 100), among: onlySquares) == nil)
    }

    @Test("The lit handle is drawn a quarter larger, about the same middle")
    func litHandleGrows() {
        let square = HandleHover.litRect(for: Self.square(100, 100, .topLeft))
        #expect(square.width == 10)
        #expect(square.midX == 100 && square.midY == 100)
        let ring = HandleHover.litRect(for: Self.dot(0, 0, size: 8))
        #expect(ring.width == 10 && ring.height == 10)
        #expect(HandleHover.grow == 1.25)
    }

    @Test("Each 3D handle names the value its drag changes, in the panel's own words")
    func spaceHandlesSayWhatTheyChange() {
        #expect(SpaceHandle.swing.hoverLabel == "Rotation Y")
        #expect(SpaceHandle.tip.hoverLabel == "Rotation X")
        #expect(SpaceHandle.depth.hoverLabel == "Depth")
        // Each label is the start of the pill the drag then shows, so the
        // word under the resting pointer is the word under the moving one.
        for handle in SpaceHandle.allCases {
            #expect(SpaceDrag.readout(handle, LayerTurn3D()).hasPrefix(handle.hoverLabel))
        }
    }

    @Test("A walk reads each mark by a stable name")
    func marksHaveNames() {
        #expect(Self.square(0, 0, .topLeft).name == "resize-topLeft")
        #expect(Self.knob.name == "rotate")
        #expect(Self.dot(0, 0).name == "grab")
    }
}
