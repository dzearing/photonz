import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// Turning a shape into a path does not change the picture.
///
/// The whole promise of the command is that the instant after, nothing moved:
/// same outline, same fill, same edge, same effects. That is a claim about
/// PIXELS, so every test in here composites the document twice — once as the
/// shape and once as the path it became — and compares the two bitmaps byte for
/// byte rather than looking at them (`ShapeToPath.swift`).
@Suite("Turn Into Path keeps the picture")
struct TurnIntoPathRenderTests {

    private let canvas = CGSize(width: 300, height: 240)
    private let box = CGRect(x: 50, y: 40, width: 200, height: 140)

    // MARK: Helpers

    private func rgba(_ image: CGImage) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &data, width: image.width, height: image.height,
                                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return data
    }

    private func render(_ layer: Layer) -> CGImage {
        var document = PhotonzDocument(canvasSize: canvas)
        document.addLayer(layer)
        return DocumentRenderer().render(document, store: ImageStore())!
    }

    /// The worst any one colour channel differs between the shape and the path
    /// it became, and how many bytes differ at all.
    @discardableResult
    private func difference(_ layer: Layer) throws -> (worst: Int, differing: Int, total: Int) {
        let turned = try #require(layer.turnedIntoPath())
        let before = rgba(render(layer))
        let after = rgba(render(turned))
        #expect(before.count == after.count)
        var worst = 0, differing = 0
        for i in 0..<min(before.count, after.count) {
            let d = abs(Int(before[i]) - Int(after[i]))
            if d > 0 { differing += 1 }
            worst = max(worst, d)
        }
        return (worst, differing, before.count)
    }

    /// The same picture. Either byte for byte, or off by the last BIT on a
    /// handful of edge samples.
    ///
    /// The tolerance is not a hedge, it is what two different ways of drawing
    /// the same curve cost. A rounded box's fill is filled straight through
    /// Core Graphics; the ring inside it is the shape filled and then the band
    /// taken back off, so along a curve the two round the last step of coverage
    /// differently now and then. One part in 255 on tens of samples out of
    /// nearly three hundred thousand is below anything a screen can show, and
    /// every straight edge in the same picture still matches exactly.
    private func expectSamePicture(_ layer: Layer, softEdgeBytes: Int = 0,
                                   sourceLocation: SourceLocation = #_sourceLocation) throws {
        let diff = try difference(layer)
        #expect(diff.differing <= softEdgeBytes, "\(diff.differing) bytes differ, worst \(diff.worst)",
                sourceLocation: sourceLocation)
        #expect(diff.worst <= (softEdgeBytes == 0 ? 0 : 2),
                "worst channel difference \(diff.worst)", sourceLocation: sourceLocation)
    }

    private func boxLayer(radius: CGFloat = 0, stroke: CGFloat = 4,
                          position: BorderPosition = .inside,
                          fill: String? = "#3478F6") -> Layer {
        var shape = AnnotationContent(shape: .rectangle, strokeWidth: stroke,
                                      colorHex: "#FF3B30",
                                      start: .zero,
                                      end: CGPoint(x: box.width, y: box.height),
                                      fillColorHex: fill)
        shape.cornerRadius = radius
        shape.strokePosition = position
        return Layer(name: "Rectangle", content: .annotation(shape), frame: box)
    }

    private func ovalLayer(_ size: CGSize, stroke: CGFloat = 4,
                           position: BorderPosition = .inside) -> Layer {
        var shape = AnnotationContent(shape: .ellipse, strokeWidth: stroke, colorHex: "#FF3B30",
                                      start: .zero, end: CGPoint(x: size.width, y: size.height),
                                      fillColorHex: "#34C759")
        shape.strokePosition = position
        return Layer(name: "Ellipse", content: .annotation(shape),
                     frame: CGRect(origin: box.origin, size: size))
    }

    // MARK: - A box

    @Test("A plain box is the same picture, byte for byte")
    func plainBox() throws {
        try expectSamePicture(boxLayer())
    }

    @Test("A rounded box is the same picture")
    func roundedBox() throws {
        try expectSamePicture(boxLayer(radius: 24), softEdgeBytes: 8)
    }

    @Test("...and so is one rounded a different amount at each corner")
    func perCornerBox() throws {
        var shape = AnnotationContent(shape: .rectangle, strokeWidth: 5, colorHex: "#FF3B30",
                                      start: .zero,
                                      end: CGPoint(x: box.width, y: box.height),
                                      fillColorHex: "#3478F6")
        shape.cornerRadii = CornerRadii(topLeft: 36, topRight: 0, bottomRight: 14, bottomLeft: 0)
        try expectSamePicture(Layer(name: "Card", content: .annotation(shape), frame: box),
                              softEdgeBytes: 8)
    }

    @Test("A box with no fill keeps its hollow middle")
    func hollowBox() throws {
        try expectSamePicture(boxLayer(radius: 18, fill: nil), softEdgeBytes: 24)
    }

    @Test("A box whose edge is centred, and one whose edge is outside")
    func theOtherTwoEdgePositions() throws {
        try expectSamePicture(boxLayer(radius: 20, position: .center), softEdgeBytes: 24)
        try expectSamePicture(boxLayer(radius: 20, position: .outside), softEdgeBytes: 24)
    }

    @Test("A box with no edge at all, which is an ordinary filled icon")
    func fillOnly() throws {
        try expectSamePicture(boxLayer(radius: 30, stroke: 0))
    }

    // MARK: - An oval

    @Test("A circle is the same picture")
    func circle() throws {
        try expectSamePicture(ovalLayer(CGSize(width: 140, height: 140)), softEdgeBytes: 40)
    }

    @Test("A wide oval with no edge round it is the same picture, byte for byte")
    func wideOvalFillOnly() throws {
        try expectSamePicture(ovalLayer(CGSize(width: 200, height: 100), stroke: 0))
    }

    @Test("A wide oval's ring moves by a fraction of a pixel, and the reason is worth knowing")
    func wideOvalRing() throws {
        // An oval's ring is drawn today as a second oval INSET IN ITS BOX, and
        // that is only the same thing as a line a fixed distance inside the
        // curve when the oval is a circle. A ring round a path is the real
        // offset, so on a 2:1 oval the two part company along the flanks — by
        // well under a pixel, but by enough to see in a byte comparison. The
        // path's is the correct one; the oval's own is the approximation, and
        // putting that right is filed separately.
        let diff = try difference(ovalLayer(CGSize(width: 200, height: 100)))
        // Only the ring itself moves: about a pixel's worth of edge round a
        // 480 point perimeter, and nothing in the fill or anywhere else.
        #expect(diff.differing < 5_000)
        #expect(diff.worst < 80)
    }

    // MARK: - A line

    @Test("A line lands in exactly the same place with the same weight")
    func line() throws {
        let shape = AnnotationContent(shape: .line, strokeWidth: 7, colorHex: "#FF3B30",
                                      start: .zero, end: .zero)
        let layer = AnnotationBuilder.layer(content: shape, from: CGPoint(x: 60, y: 60),
                                            to: CGPoint(x: 220, y: 170))
        try expectSamePicture(layer)
    }

    @Test("An even-weighted line too, and a level one")
    func moreLines() throws {
        for width in [4.0, 10.0] as [CGFloat] {
            let shape = AnnotationContent(shape: .line, strokeWidth: width, colorHex: "#FF3B30",
                                          start: .zero, end: .zero)
            try expectSamePicture(AnnotationBuilder.layer(content: shape,
                                                          from: CGPoint(x: 60, y: 120),
                                                          to: CGPoint(x: 240, y: 120)))
        }
    }

    // MARK: - Everything it was wearing

    @Test("A shadow, a blur and an opacity all land where they did")
    func effectsSurvive() throws {
        var layer = boxLayer(radius: 22)
        layer.style.effects.append(.shadow(ShadowStyle(radius: 10,
                                                       offset: CGSize(width: 4, height: 6),
                                                       colorHex: "#000000")))
        layer.style.opacity = 0.55
        try expectSamePicture(layer, softEdgeBytes: 24)
    }

    @Test("A second border, standing off the edge, still stands off the same edge")
    func aSecondRing() throws {
        var layer = boxLayer(radius: 22)
        var extra = BorderEffect(width: 3, colorHex: "#FFCC00", position: .outside, offset: 6)
        extra.follows = .box
        layer.style.effects.insert(.border(extra), at: 0)
        try expectSamePicture(layer, softEdgeBytes: 40)
    }

    @Test("A gradient edge stays a gradient edge")
    func gradientRing() throws {
        var layer = boxLayer(radius: 22)
        for index in layer.style.effects.indices {
            guard case .border(var border) = layer.style.effects[index] else { continue }
            border.paint = Paint(hex: "#FF3B30", kind: .linear,
                                 stops: [GradientStop(hex: "#FF3B30", position: 0),
                                         GradientStop(hex: "#5856D6", position: 1)])
            layer.style.effects[index] = .border(border)
        }
        try expectSamePicture(layer, softEdgeBytes: 24)
    }

    // MARK: - The curve is really a curve

    @Test("The rounded corner is a real quarter circle, measured on the pixels")
    func theCornerIsRound() throws {
        // A big radius so the curve is many pixels across, and no fill, so the
        // only ink in the corner is the edge itself.
        let layer = boxLayer(radius: 60, stroke: 6, fill: nil)
        let turned = try #require(layer.turnedIntoPath())
        let data = rgba(render(turned))
        let width = Int(canvas.width)
        func alpha(_ x: Int, _ y: Int) -> Int { Int(data[(y * width + x) * 4 + 3]) }
        // The top-left corner turns about (box.minX + 60, box.minY + 60). The
        // edge is centred on a radius of 60 - 3 for an inside line, so a point
        // that far out on the 45 degree diagonal has to be ink, and one well
        // inside it has to be clear.
        let centre = CGPoint(x: box.minX + 60, y: box.minY + 60)
        let radius: CGFloat = 60 - 3
        let diagonal = CGFloat(2).squareRoot() / 2
        let onCurve = CGPoint(x: centre.x - radius * diagonal, y: centre.y - radius * diagonal)
        #expect(alpha(Int(onCurve.x.rounded()), Int(onCurve.y.rounded())) > 200)
        let wellInside = CGPoint(x: centre.x - (radius - 12) * diagonal,
                                 y: centre.y - (radius - 12) * diagonal)
        #expect(alpha(Int(wellInside.x.rounded()), Int(wellInside.y.rounded())) < 20)
        // ...and the corner of the box itself, outside the curve, is empty:
        // the curve really cut the corner off rather than being drawn over it.
        #expect(alpha(Int(box.minX) + 4, Int(box.minY) + 4) < 20)
    }

    @Test("A circle really is round after the turn: sampled all the way round")
    func theCircleIsRound() throws {
        let size = CGSize(width: 160, height: 160)
        let layer = ovalLayer(size, stroke: 6)
        let turned = try #require(layer.turnedIntoPath())
        let data = rgba(render(turned))
        let width = Int(canvas.width)
        func alpha(_ x: Int, _ y: Int) -> Int { Int(data[(y * width + x) * 4 + 3]) }
        let centre = CGPoint(x: box.minX + 80, y: box.minY + 80)
        // The edge rides a radius of 80 - 3 (an inside line), so every point on
        // that circle is ink and every point six points further out is canvas.
        for step in 0..<64 {
            let angle = CGFloat(step) / 64 * 2 * .pi
            let on = CGPoint(x: centre.x + cos(angle) * 77, y: centre.y + sin(angle) * 77)
            #expect(alpha(Int(on.x.rounded()), Int(on.y.rounded())) > 150)
            let out = CGPoint(x: centre.x + cos(angle) * 87, y: centre.y + sin(angle) * 87)
            #expect(alpha(Int(out.x.rounded()), Int(out.y.rounded())) < 20)
        }
    }
}
