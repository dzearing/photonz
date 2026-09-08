import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// A border round a ROUNDED rectangle follows the rounding.
///
/// Reported by the user on 2026-09-07: draw a box, add a border, pull the
/// corner radius, and nothing looks any rounder. The shape itself was curving
/// all along — the ring round it was not, so a hard square frame sat over a
/// rounded box with white showing in the corners, which reads as a slider that
/// does nothing. Every test here composites a real document and reads the
/// pixel diagonally out from a corner, which is the one place a square ring and
/// a round one differ.
@Suite("Rounded border rendering")
struct RoundedBorderRenderTests {

    private let canvas = CGSize(width: 260, height: 220)
    private let box = CGRect(x: 60, y: 50, width: 120, height: 100)
    private let radius: CGFloat = 30

    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &data, width: image.width, height: image.height,
                                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let i = (y * image.width + x) * 4
        guard i + 3 < data.count else { return (0, 0, 0, 0) }
        return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]), Int(data[i + 3]))
    }

    private func isGreen(_ p: (r: Int, g: Int, b: Int, a: Int)) -> Bool {
        p.a > 200 && p.g > 180 && p.r < 80 && p.b < 80
    }

    private func isClear(_ p: (r: Int, g: Int, b: Int, a: Int)) -> Bool { p.a < 40 }

    /// A rounded red box with no line of its own, wearing whatever rings the
    /// Effects list puts on it.
    private func roundedBox(_ effects: [LayerEffect], stroke: CGFloat = 0,
                            position: BorderPosition = .inside) -> Layer {
        var style = LayerStyle()
        style.effects = effects
        var annotation = AnnotationContent(shape: .rectangle, strokeWidth: stroke,
                                           colorHex: "#FF0000",
                                           start: .zero,
                                           end: CGPoint(x: box.width, y: box.height),
                                           cornerRadius: radius, fillColorHex: "#FF0000")
        annotation.strokePosition = position
        return Layer(name: "Box", content: .annotation(annotation), frame: box, style: style)
    }

    private func render(_ layers: [Layer], scale: CGFloat = 1) -> CGImage {
        var doc = PhotonzDocument(canvasSize: canvas)
        for layer in layers { doc.addLayer(layer) }
        let renderer = DocumentRenderer()
        return scale == 1
            ? renderer.render(doc, store: ImageStore())!
            : renderer.render(doc, store: ImageStore(), scale: scale)!
    }

    /// A point on the ring at the middle of the left edge, and the point
    /// diagonally out from the top-left corner. On a ring that follows a 30pt
    /// corner the first is painted and the second is empty; on a square frame
    /// both are painted.
    private func edgeAndCorner(_ image: CGImage, out: Int, scale: CGFloat = 1)
    -> (edge: (r: Int, g: Int, b: Int, a: Int), corner: (r: Int, g: Int, b: Int, a: Int)) {
        let s = { (v: CGFloat) in Int((v * scale).rounded()) }
        return (pixel(image, s(box.minX) - out, s(box.midY)),
                pixel(image, s(box.minX) - out, s(box.minY) - out))
    }

    @Test("An added outside border follows a rounded rectangle's corner")
    func outsideBorderRounds() {
        let image = render([roundedBox([.border(BorderEffect(width: 8, colorHex: "#00FF00",
                                                             position: .outside))])])
        let (edge, corner) = edgeAndCorner(image, out: 4)
        #expect(isGreen(edge))
        // Diagonally out from a corner that is round by 30, four points past the
        // box, there is nothing: a square frame would paint here.
        #expect(isClear(corner))
    }

    @Test("A centred border follows it too")
    func centredBorderRounds() {
        let image = render([roundedBox([.border(BorderEffect(width: 8, colorHex: "#00FF00",
                                                             position: .center))])])
        let (edge, corner) = edgeAndCorner(image, out: 2)
        #expect(isGreen(edge))
        #expect(isClear(corner))
    }

    @Test("An inside border follows it, and leaves the corner clear")
    func insideBorderRounds() {
        let image = render([roundedBox([.border(BorderEffect(width: 8, colorHex: "#00FF00",
                                                             position: .inside))])])
        // Four points IN from the middle of the left edge is the ring.
        #expect(isGreen(pixel(image, Int(box.minX) + 4, Int(box.midY))))
        // Four points in diagonally from the corner is outside a 30pt curve, so
        // it is empty rather than green.
        #expect(isClear(pixel(image, Int(box.minX) + 4, Int(box.minY) + 4)))
    }


    @Test("The ring keeps following the corner on a magnified render")
    func roundsAtEveryZoom() {
        let image = render([roundedBox([.border(BorderEffect(width: 8, colorHex: "#00FF00",
                                                             position: .outside))])],
                           scale: 2)
        let (edge, corner) = edgeAndCorner(image, out: 8, scale: 2)
        #expect(isGreen(edge))
        #expect(isClear(corner))
    }

    @Test("An added border is as thick at 2x as it is at 1x")
    func borderThicknessSurvivesZoom() {
        let image = render([roundedBox([.border(BorderEffect(width: 8, colorHex: "#00FF00",
                                                             position: .outside))])],
                           scale: 2)
        // 8 points is 16 pixels at 2x: painted 14 out, empty 18 out.
        #expect(isGreen(pixel(image, Int(box.minX * 2) - 14, Int(box.midY * 2))))
        #expect(isClear(pixel(image, Int(box.minX * 2) - 18, Int(box.midY * 2))))
    }

    @Test("A rounded rectangle inside a group is ringed round its own corner")
    func insideAGroup() {
        var child = roundedBox([.border(BorderEffect(width: 8, colorHex: "#00FF00",
                                                     position: .outside))])
        // Children are stored against the group's origin.
        child.frame = CGRect(origin: .zero, size: box.size)
        let group = Layer(name: "Group",
                          content: .group(GroupContent(children: [child])),
                          frame: box)
        let image = render([group])
        let (edge, corner) = edgeAndCorner(image, out: 4)
        #expect(isGreen(edge))
        #expect(isClear(corner))
    }

    @Test("A rectangle rounded by nothing but the old mask is still ringed round")
    func legacyMaskedRectangleStillRounds() {
        // A document written before the one Corner Radius row: no curve on the
        // shape, a radius on the layer style. It has to paint what it painted.
        var style = LayerStyle()
        style.cornerRadius = radius
        style.effects = [.border(BorderEffect(width: 8, colorHex: "#00FF00", position: .outside))]
        let layer = Layer(name: "Box",
                          content: .annotation(AnnotationContent(shape: .rectangle,
                                                                 strokeWidth: 0,
                                                                 colorHex: "#FF0000",
                                                                 start: .zero,
                                                                 end: CGPoint(x: box.width,
                                                                              y: box.height),
                                                                 fillColorHex: "#FF0000")),
                          frame: box, style: style)
        let (edge, corner) = edgeAndCorner(render([layer]), out: 4)
        #expect(isGreen(edge))
        #expect(isClear(corner))
    }

    @Test("A square rectangle keeps its square ring")
    func squareStaysSquare() {
        var style = LayerStyle()
        style.effects = [.border(BorderEffect(width: 8, colorHex: "#00FF00", position: .outside))]
        let layer = Layer(name: "Box",
                          content: .annotation(AnnotationContent(shape: .rectangle,
                                                                 strokeWidth: 0,
                                                                 colorHex: "#FF0000",
                                                                 start: .zero,
                                                                 end: CGPoint(x: box.width,
                                                                              y: box.height),
                                                                 fillColorHex: "#FF0000")),
                          frame: box, style: style)
        let (edge, corner) = edgeAndCorner(render([layer]), out: 4)
        #expect(isGreen(edge))
        #expect(isGreen(corner))
    }
}
