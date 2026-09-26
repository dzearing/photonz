import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// While a layer is dragged, the canvas floats a picture of it over the rest
/// of the document. That picture is the layer's box plus a margin, and the
/// margin has to hold everything the layer draws outside the box: its shadow
/// and blur, and, once it has been turned, the corners the turn swings out
/// past the upright box.
///
/// On 2026-09-26 the margin held only the shadow. A rectangle turned 45
/// degrees had its corners sliced off flat for the whole of a move, so the
/// thing under the pointer looked like an upright shape that had lost its
/// rotation, and it snapped back only when the mouse came up.
@Suite("Drag sprite padding")
struct DragSpritePaddingTests {

    private func rectangle(_ frame: CGRect, degrees: CGFloat = 0,
                           style: LayerStyle = LayerStyle()) -> Layer {
        Layer(name: "Rectangle", content: .annotation(AnnotationContent(shape: .rectangle)),
              frame: frame,
              transform: LayerTransform(rotation: LayerAngle.radians(fromDegrees: degrees)),
              style: style)
    }

    /// The upright box the sprite covers when `layer` is drawn in the middle
    /// of it with `padding` all round.
    private func spriteBox(_ layer: Layer, padding: CGFloat) -> CGRect {
        layer.localBounds.insetBy(dx: -padding, dy: -padding)
    }

    @Test("An upright layer with no effects needs only what it always had")
    func uprightNeedsNothingMore() {
        let layer = rectangle(CGRect(x: 120, y: 120, width: 200, height: 100))
        #expect(layer.dragSpritePadding == layer.reachPadding)
    }

    @Test("A turned rectangle's corners fit inside the sprite")
    func turnedCornersFit() {
        let layer = rectangle(CGRect(x: 120, y: 120, width: 200, height: 100), degrees: 45)
        let box = spriteBox(layer, padding: layer.dragSpritePadding)
        // 200 by 100 on a 45 degree slant spans about 212 by 212 about the
        // middle, so the sprite has to reach 56 points above and below the
        // box and 6 points either side.
        let turned = layer.frame.applying(layer.transform.affineTransform(
            around: CGPoint(x: layer.frame.midX, y: layer.frame.midY)))
        #expect(box.contains(turned.insetBy(dx: 0.5, dy: 0.5)),
                "sprite \(box) does not hold the turned drawing \(turned)")
        #expect(layer.dragSpritePadding >= 56)
    }

    @Test("Every angle round the circle fits, not just the one tried by hand")
    func everyAngleFits() {
        for degrees in stride(from: CGFloat(-180), through: 180, by: 15) {
            let layer = rectangle(CGRect(x: 0, y: 0, width: 300, height: 40), degrees: degrees)
            let box = spriteBox(layer, padding: layer.dragSpritePadding)
            #expect(box.contains(layer.turnedReach.insetBy(dx: 0.5, dy: 0.5)),
                    "at \(degrees) degrees the sprite \(box) cuts \(layer.turnedReach)")
        }
    }

    @Test("A turned layer's shadow still fits as well as its corners")
    func turnedShadowFits() {
        var style = LayerStyle()
        style.shadows = [ShadowStyle(radius: 10, offset: CGSize(width: 0, height: 12))]
        let layer = rectangle(CGRect(x: 0, y: 0, width: 200, height: 100), degrees: 30,
                              style: style)
        #expect(layer.dragSpritePadding >= layer.reachPadding)
        let box = spriteBox(layer, padding: layer.dragSpritePadding)
        #expect(box.contains(layer.turnedReach.insetBy(dx: 0.5, dy: 0.5)))
    }

    @Test("A group still makes room for what its pieces reach")
    func groupReach() {
        var style = LayerStyle()
        style.shadows = [ShadowStyle(radius: 20, offset: .zero)]
        let inner = rectangle(CGRect(x: 0, y: 0, width: 50, height: 50), style: style)
        let group = Layer(name: "Group", content: .group(GroupContent(children: [inner])),
                          frame: CGRect(x: 10, y: 10, width: 0, height: 0))
        let box = group.localBounds
        let reach = group.renderBounds
        let needed = max(box.minX - reach.minX, box.minY - reach.minY,
                         reach.maxX - box.maxX, reach.maxY - box.maxY)
        #expect(group.dragSpritePadding >= needed)
    }

    @Test("Padding is a whole number of points, so the sprite lands on pixels")
    func wholePoints() {
        let layer = rectangle(CGRect(x: 0, y: 0, width: 200, height: 100), degrees: 33)
        #expect(layer.dragSpritePadding == layer.dragSpritePadding.rounded(.up))
    }
}
