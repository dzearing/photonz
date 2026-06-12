import CoreGraphics
import Foundation
import Testing
import PhotonzCore

@Suite("LayerTransform")
struct LayerTransformTests {

    private func apply(_ t: LayerTransform, to p: CGPoint, around c: CGPoint) -> CGPoint {
        p.applying(t.affineTransform(around: c))
    }

    private func expectClose(_ p: CGPoint, _ x: CGFloat, _ y: CGFloat,
                             sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(abs(p.x - x) < 1e-9 && abs(p.y - y) < 1e-9,
                "expected (\(x), \(y)), got (\(p.x), \(p.y))", sourceLocation: sourceLocation)
    }

    @Test func identityLeavesPointsAlone() {
        let p = apply(.identity, to: CGPoint(x: 13, y: 37), around: CGPoint(x: 50, y: 50))
        expectClose(p, 13, 37)
    }

    @Test func isIdentityFlags() {
        #expect(LayerTransform.identity.isIdentity)
        #expect(!LayerTransform(rotation: 0.1).isIdentity)
        #expect(!LayerTransform(skewX: 0.1).isIdentity)
        #expect(!LayerTransform(skewY: 0.1).isIdentity)
        #expect(!LayerTransform(flipHorizontal: true).isIdentity)
        #expect(!LayerTransform(flipVertical: true).isIdentity)
    }

    @Test func quarterTurnIsClockwiseInTopLeftSpace() {
        // Top-center of a 100x100 box rotates to right-center (clockwise on screen).
        let t = LayerTransform(rotation: .pi / 2)
        let p = apply(t, to: CGPoint(x: 50, y: 0), around: CGPoint(x: 50, y: 50))
        expectClose(p, 100, 50)
    }

    @Test func flipHorizontalMirrorsAroundCenter() {
        let t = LayerTransform(flipHorizontal: true)
        let p = apply(t, to: CGPoint(x: 0, y: 10), around: CGPoint(x: 50, y: 50))
        expectClose(p, 100, 10)
    }

    @Test func flipVerticalMirrorsAroundCenter() {
        let t = LayerTransform(flipVertical: true)
        let p = apply(t, to: CGPoint(x: 10, y: 0), around: CGPoint(x: 50, y: 50))
        expectClose(p, 10, 100)
    }

    @Test func positiveSkewXShiftsLowerPointsRight() {
        // tan(π/4) = 1: a point 50 below center shifts right by 50.
        let t = LayerTransform(skewX: .pi / 4)
        let p = apply(t, to: CGPoint(x: 50, y: 100), around: CGPoint(x: 50, y: 50))
        expectClose(p, 100, 100)
    }

    @Test func positiveSkewYShiftsRightPointsDown() {
        let t = LayerTransform(skewY: .pi / 4)
        let p = apply(t, to: CGPoint(x: 100, y: 50), around: CGPoint(x: 50, y: 50))
        expectClose(p, 100, 100)
    }

    @Test func flipAppliesBeforeRotation() {
        // Left-center flips to right-center, then a clockwise quarter turn
        // takes it to bottom-center. (Rotate-then-flip would land at top-center.)
        let t = LayerTransform(rotation: .pi / 2, flipHorizontal: true)
        let p = apply(t, to: CGPoint(x: 0, y: 50), around: CGPoint(x: 50, y: 50))
        expectClose(p, 50, 100)
    }

    @Test func codableRoundTrip() throws {
        let t = LayerTransform(rotation: 0.3, skewX: 0.1, skewY: -0.2,
                               flipHorizontal: true, flipVertical: false)
        let data = try JSONEncoder().encode(t)
        let back = try JSONDecoder().decode(LayerTransform.self, from: data)
        #expect(back == t)
    }

    @Test func layerDefaultsToIdentityTransform() {
        let layer = Layer(name: "L", content: .text(TextContent(string: "x")),
                          frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(layer.transform.isIdentity)
    }
}
