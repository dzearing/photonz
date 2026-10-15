import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// A curve drawn on whole units in an icon frame comes out of the file on
/// whole units, even where it bulges past its own points.
///
/// A path layer's box is the curve's box, so a curve that swings out past its
/// first point is placed at a fraction and its points are stated against that
/// fraction: `translate(13.88 6)` and `M5.12 0`, which add up to the whole
/// numbers the drawing is made of but say neither of them. Inside an icon
/// frame the writer places such a layer on the whole unit beside it and
/// shifts the path by the difference.
@Suite("A curve drawn on whole units exports on whole units")
struct SVGWholeUnitCurveTests {

    /// The curve the pen walk drew in a 24 frame: 19,6 down to a smooth point
    /// at 15,14 and on to 22,18, its handles four and two units long. The
    /// run in swings left of 15, so the box starts at 13.88.
    static func bulgingCurve() -> PathContent {
        PathContent(anchors: [
            PathAnchor(point: CGPoint(x: 19, y: 6)),
            PathAnchor(point: CGPoint(x: 15, y: 14), handleIn: CGPoint(x: -4, y: 2),
                       handleOut: CGPoint(x: 4, y: -2), kind: .smooth),
            PathAnchor(point: CGPoint(x: 22, y: 18))
        ], isClosed: false, paint: Paint(hex: "#000000"), strokeWidth: 2)
    }

    /// The layer the pen makes of it: boxed round where the curve goes.
    static func curveLayer(_ content: PathContent = bulgingCurve()) -> Layer {
        PathBuilder.layer(content, at: content.bounds.origin)
    }

    static func frame(_ children: [Layer], side: CGFloat = 24) -> Layer {
        Layer(name: "Icon",
              content: .group(GroupContent(children: children, isFrame: true)),
              frame: CGRect(x: 0, y: 0, width: side, height: side))
    }

    static func write(_ layers: [Layer], size: CGFloat = 24) -> String {
        SVGExport.write(PhotonzDocument(canvasSize: CGSize(width: size, height: size),
                                        layers: layers)).text
    }

    /// A number the way the file writes one: three decimals at most.
    static func num(_ value: CGFloat) -> String {
        var text = String(format: "%.3f", Double(value))
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    @Test func theCurveReallyIsPlacedAtAFraction() {
        // The case this suite exists for, checked so it cannot go quietly
        // whole on its own and leave the tests proving nothing.
        let layer = Self.curveLayer()
        #expect(layer.frame.minX != layer.frame.minX.rounded())
    }

    @Test func aBulgingCurveInAnIconFrameIsWholeThroughout() {
        let svg = Self.write([Self.frame([Self.curveLayer()])])
        #expect(SVGWholeUnits.fractionalCoordinates(in: svg).isEmpty,
                "off the grid: \(SVGWholeUnits.fractionalCoordinates(in: svg))")
        #expect(svg.contains("transform=\"translate(14 6)\""))
        #expect(svg.contains("d=\"M5 0 C5 0 -3 10 1 8 C5 6 8 12 8 12\""))
    }

    @Test func theCurveStillLandsWhereItWasDrawn() {
        // 14 + 5 = 19, the point the curve starts at on the frame.
        let svg = Self.write([Self.frame([Self.curveLayer()])])
        #expect(svg.contains("translate(14 6)"))
        #expect(svg.contains("M5 0 "))
    }

    @Test func theSameCurveOffAnIconFrameWritesTheFileItAlwaysDid() {
        let svg = Self.write([Self.curveLayer()])
        #expect(svg.contains("transform=\"translate(13.88 6)\""))
        #expect(svg.contains("d=\"M5.12 0 C5.12 0 -2.88 10 1.12 8 C5.12 6 8.12 12 8.12 12\""))
    }

    @Test func aCurveThatIsNotOnWholeUnitsIsLeftAsItIs() {
        var content = Self.bulgingCurve()
        content.anchors[0].point = CGPoint(x: 19.3, y: 6)
        let layer = Self.curveLayer(content)
        let svg = Self.write([Self.frame([layer])])
        #expect(!SVGWholeUnits.fractionalCoordinates(in: svg).isEmpty)
        #expect(svg.contains("translate(\(Self.num(layer.frame.minX)) 6)"), "\(svg)")
    }

    @Test func aStraightSidedShapeWritesTheFileItAlwaysDid() {
        let triangle = PathContent(anchors: [
            PathAnchor(point: CGPoint(x: 3, y: 4)),
            PathAnchor(point: CGPoint(x: 19, y: 4)),
            PathAnchor(point: CGPoint(x: 12, y: 17))
        ], isClosed: true, fill: Paint(hex: "#000000"))
        let svg = Self.write([Self.frame([Self.curveLayer(triangle)])])
        #expect(svg.contains("<path transform=\"translate(3 4)\" d=\"M0 0 L16 0 L9 13 L0 0 Z\""))
    }

    @Test func aTurnedCurveTurnsAboutTheSameMiddle() {
        var layer = Self.curveLayer()
        layer.transform.rotation = .pi / 2
        let svg = Self.write([Self.frame([layer])])
        // The middle of the box, stated in the shifted path's own space: the
        // same point on the frame it was before the shift.
        let shift = layer.frame.minX - 14
        let middle = "\(Self.num(layer.frame.width / 2 + shift))"
            + " \(Self.num(layer.frame.height / 2))"
        #expect(svg.contains("translate(14 6) rotate(90 \(middle))"))
        #expect(svg.contains("d=\"M5 0 C5 0 -3 10 1 8 C5 6 8 12 8 12\""))
    }

    @Test func anInsideLineIsCutByTheShiftedShapeToo() {
        var content = Self.bulgingCurve()
        content.isClosed = true
        content.strokePosition = .inside
        let svg = Self.write([Self.frame([Self.curveLayer(content)])])
        let paths = svg.components(separatedBy: " d=\"").dropFirst()
            .map { $0.prefix { $0 != "\"" } }
        #expect(paths.count >= 3, "\(svg)")
        #expect(Set(paths).count == 1, "every copy of the shape is the same shifted shape")
        #expect(paths.first?.hasPrefix("M5 0 ") == true)
    }

    @Test func aRingRoundTheCurveRidesTheShiftedShape() {
        var layer = Self.curveLayer()
        layer.style.effects = [.border(BorderEffect(width: 1, colorHex: "#FF0000"))]
        let svg = Self.write([Self.frame([layer])])
        let paths = svg.components(separatedBy: " d=\"").dropFirst()
            .map { $0.prefix { $0 != "\"" } }
        #expect(paths.count == 2, "\(svg)")
        #expect(paths.allSatisfy { $0.hasPrefix("M5 0 ") })
        #expect(svg.contains("<g transform=\"translate(14 6)\">"))
    }
}
