import CoreGraphics
import Foundation
import PhotonzCore
import Testing

@Suite("Transform drag (rotate knob, ⌥-corner skew)")
struct TransformDragTests {
    let frame = CGRect(x: 100, y: 100, width: 200, height: 100)

    // MARK: Pointer angle

    @Test func pointerAngleIsZeroToTheRightAndGrowsClockwise() {
        let c = CGPoint(x: 0, y: 0)
        #expect(TransformDrag.pointerAngle(CGPoint(x: 10, y: 0), around: c) == 0)
        // Below the center (y-down screen space) is +90°: clockwise-positive,
        // matching LayerTransform's rotation convention.
        #expect(abs(TransformDrag.pointerAngle(CGPoint(x: 0, y: 10), around: c) - .pi / 2) < 1e-9)
    }

    // MARK: Rotation

    @Test func rotationFollowsThePointerDelta() {
        let r = TransformDrag.rotation(from: 0.2, grabAngle: 0.5, currentAngle: 1.0, snapped: false)
        #expect(abs(r - 0.7) < 1e-9)
    }

    @Test func shiftSnapsRotationToFifteenDegrees() {
        let step = CGFloat.pi / 12
        let r = TransformDrag.rotation(from: 0, grabAngle: 0, currentAngle: step * 1.4, snapped: true)
        #expect(abs(r - step) < 1e-9)
        let r2 = TransformDrag.rotation(from: 0, grabAngle: 0, currentAngle: step * 1.6, snapped: true)
        #expect(abs(r2 - step * 2) < 1e-9)
    }

    // MARK: Skew — the dragged corner follows the pointer

    /// Where `corner` of `frame` lands after `transform`.
    private func transformedCorner(_ corner: ResizeHandle, _ transform: LayerTransform) -> CGPoint {
        let p = Handles.point(for: corner, in: frame)
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return p.applying(transform.affineTransform(around: center))
    }

    private func expectCornerFollows(_ corner: ResizeHandle, delta: CGPoint,
                                     from start: LayerTransform = .identity) {
        let skewed = TransformDrag.skewed(start, corner: corner, by: delta,
                                          frameSize: frame.size)
        let before = transformedCorner(corner, start)
        let after = transformedCorner(corner, skewed)
        #expect(abs(after.x - before.x - delta.x) < 1e-6,
                "\(corner) x: moved \(after.x - before.x), wanted \(delta.x)")
        #expect(abs(after.y - before.y - delta.y) < 1e-6,
                "\(corner) y: moved \(after.y - before.y), wanted \(delta.y)")
    }

    @Test func horizontalDragOnEachCornerFollowsThePointer() {
        for corner in [ResizeHandle.topLeft, .topRight, .bottomLeft, .bottomRight] {
            expectCornerFollows(corner, delta: CGPoint(x: 24, y: 0))
        }
    }

    @Test func verticalDragOnEachCornerFollowsThePointer() {
        for corner in [ResizeHandle.topLeft, .topRight, .bottomLeft, .bottomRight] {
            expectCornerFollows(corner, delta: CGPoint(x: 0, y: -18))
        }
    }

    @Test func diagonalDragSetsBothSkews() {
        let skewed = TransformDrag.skewed(.identity, corner: .bottomRight,
                                          by: CGPoint(x: 30, y: 12), frameSize: frame.size)
        #expect(skewed.skewX != 0)
        #expect(skewed.skewY != 0)
        expectCornerFollows(.bottomRight, delta: CGPoint(x: 30, y: 12))
    }

    @Test func skewComposesWithExistingSkew() {
        let first = TransformDrag.skewed(.identity, corner: .topRight,
                                         by: CGPoint(x: 20, y: 0), frameSize: frame.size)
        expectCornerFollows(.topRight, delta: CGPoint(x: 15, y: 0), from: first)
    }

    @Test func skewAccountsForExistingRotation() {
        let rotated = LayerTransform(rotation: .pi / 2)
        expectCornerFollows(.topRight, delta: CGPoint(x: 20, y: 10), from: rotated)
    }

    @Test func skewOnEdgeHandlesAndEmptyFramesIsANoOp() {
        let viaEdge = TransformDrag.skewed(.identity, corner: .top,
                                           by: CGPoint(x: 20, y: 0), frameSize: frame.size)
        #expect(viaEdge == .identity)
        let degenerate = TransformDrag.skewed(.identity, corner: .topRight,
                                              by: CGPoint(x: 20, y: 0), frameSize: .zero)
        #expect(degenerate == .identity)
    }

    // MARK: Transformed outline corners (for the canvas chrome)

    @Test func transformedCornersMapTheFrameThroughTheTransform() {
        let layer = Layer(name: "L", content: .image(ImageRef(pixelSize: frame.size)),
                          frame: frame, transform: LayerTransform(rotation: .pi))
        let corners = layer.transformedCorners
        // 180° turn swaps opposite corners.
        #expect(abs(corners[0].x - frame.maxX) < 1e-9 && abs(corners[0].y - frame.maxY) < 1e-9)
        #expect(abs(corners[2].x - frame.minX) < 1e-9 && abs(corners[2].y - frame.minY) < 1e-9)
    }

    @Test func identityTransformedCornersAreTheFrameCorners() {
        let layer = Layer(name: "L", content: .image(ImageRef(pixelSize: frame.size)), frame: frame)
        let corners = layer.transformedCorners
        #expect(corners == [CGPoint(x: frame.minX, y: frame.minY),
                            CGPoint(x: frame.maxX, y: frame.minY),
                            CGPoint(x: frame.maxX, y: frame.maxY),
                            CGPoint(x: frame.minX, y: frame.maxY)])
    }
}
