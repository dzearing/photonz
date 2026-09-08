import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// A glow really lands on the canvas: a coloured halo OUTSIDE the layer, or a
/// lit band INSIDE its edge.
///
/// Reach that makes room is only half of it; the other half is a pixel of the
/// right colour on the right side of the layer's edge. So every test here
/// composites a real document and reads points either side of the box.
@Suite("Glow rendering")
struct GlowRenderTests {

    private let canvas = CGSize(width: 240, height: 200)
    private let box = CGRect(x: 60, y: 50, width: 100, height: 80)

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
        p.a > 180 && p.g > 150 && p.r < 90 && p.b < 90
    }

    private func isBlue(_ p: (r: Int, g: Int, b: Int, a: Int)) -> Bool {
        p.a > 180 && p.b > 150 && p.r < 90 && p.g < 90
    }

    private func isRed(_ p: (r: Int, g: Int, b: Int, a: Int)) -> Bool {
        p.a > 180 && p.r > 150 && p.g < 90 && p.b < 90
    }

    /// A plain filled red box with no stroke of its own, so the only colour
    /// anywhere else in the picture is the glow's.
    private func filledBox(_ effects: [LayerEffect]) -> Layer {
        var style = LayerStyle()
        style.effects = effects
        return Layer(name: "Box",
                     content: .annotation(AnnotationContent(shape: .rectangle,
                                                            strokeWidth: 0,
                                                            colorHex: "#FF0000",
                                                            start: .zero,
                                                            end: CGPoint(x: box.width,
                                                                         y: box.height),
                                                            fillColorHex: "#FF0000")),
                     frame: box, style: style)
    }

    private func render(_ layers: [Layer]) -> CGImage {
        var doc = PhotonzDocument(canvasSize: canvas)
        for layer in layers { doc.addLayer(layer) }
        return DocumentRenderer().render(doc, store: ImageStore())!
    }

    @Test("An outer glow throws a coloured halo past the layer's edge")
    func outerGlow() {
        let image = render([filledBox([.glow(GlowEffect(colorHex: "#00FF00", radius: 1,
                                                        size: 8, opacity: 1, kind: .outer))])])
        // Four points OUT, on all four sides.
        #expect(isGreen(pixel(image, Int(box.minX) - 4, Int(box.midY))))
        #expect(isGreen(pixel(image, Int(box.maxX) + 4, Int(box.midY))))
        #expect(isGreen(pixel(image, Int(box.midX), Int(box.minY) - 4)))
        #expect(isGreen(pixel(image, Int(box.midX), Int(box.maxY) + 4)))
        // The shape keeps its own colour: a glow goes BEHIND the layer.
        #expect(isRed(pixel(image, Int(box.midX), Int(box.midY))))
        #expect(isRed(pixel(image, Int(box.minX) + 4, Int(box.midY))))
        // And it stops: nothing a long way out.
        #expect(pixel(image, Int(box.minX) - 20, Int(box.midY)).a < 20)
    }

    @Test("An inner glow lights the edge from inside and puts nothing outside")
    func innerGlow() {
        let image = render([filledBox([.glow(GlowEffect(colorHex: "#00FF00", radius: 1,
                                                        size: 6, opacity: 1, kind: .inner))])])
        // Three points IN is inside the lit band.
        #expect(isGreen(pixel(image, Int(box.minX) + 3, Int(box.midY))))
        #expect(isGreen(pixel(image, Int(box.maxX) - 3, Int(box.midY))))
        // The middle of the shape is untouched.
        #expect(isRed(pixel(image, Int(box.midX), Int(box.midY))))
        // An inner glow never puts a pixel outside its layer.
        #expect(pixel(image, Int(box.minX) - 3, Int(box.midY)).a < 20)
        #expect(pixel(image, Int(box.midX), Int(box.maxY) + 3).a < 20)
    }

    @Test("Two glows paint in list order, so the top row is nearest the eye")
    func twoGlowsPaintInOrder() {
        let image = render([filledBox([
            .glow(GlowEffect(colorHex: "#0000FF", radius: 1, size: 6, opacity: 1, kind: .outer)),
            .glow(GlowEffect(colorHex: "#00FF00", radius: 1, size: 16, opacity: 1, kind: .outer)),
        ])])
        // Where the two overlap, the one at the TOP of the list wins.
        #expect(isBlue(pixel(image, Int(box.minX) - 3, Int(box.midY))))
        // Past the tight one, the wide one below it shows through.
        #expect(isGreen(pixel(image, Int(box.minX) - 12, Int(box.midY))))
    }

    @Test("A switched-off glow paints nothing at all")
    func offPaintsNothing() {
        let image = render([filledBox([.glow(GlowEffect(colorHex: "#00FF00", radius: 1,
                                                        size: 8, opacity: 1, kind: .outer,
                                                        isOn: false))])])
        #expect(pixel(image, Int(box.minX) - 4, Int(box.midY)).a < 20)
        #expect(isRed(pixel(image, Int(box.midX), Int(box.midY))))
    }

    @Test("A glow sits over the shadow the same layer throws")
    func glowSitsOverTheShadow() {
        // A shadow is thrown FURTHEST back, so a halo round the same shape is
        // in front of it rather than buried under it.
        let image = render([filledBox([
            .glow(GlowEffect(colorHex: "#00FF00", radius: 1, size: 8, opacity: 1, kind: .outer)),
            .shadow(ShadowStyle(radius: 1, offset: .zero, spread: 16,
                                colorHex: "#0000FF", opacity: 1)),
        ])])
        #expect(isGreen(pixel(image, Int(box.minX) - 4, Int(box.midY))))
        #expect(isBlue(pixel(image, Int(box.minX) - 12, Int(box.midY))))
    }

    @Test("An outer glow survives being drawn inside a group")
    func glowInsideAGroup() {
        // A group renders into a buffer sized by what its children can reach,
        // so a halo that made no room for itself would come back clipped.
        var child = filledBox([.glow(GlowEffect(colorHex: "#00FF00", radius: 1, size: 8,
                                                opacity: 1, kind: .outer))])
        child.frame = CGRect(origin: .zero, size: box.size)
        let group = Layer(name: "Group",
                          content: .group(GroupContent(children: [child])),
                          frame: CGRect(origin: box.origin, size: box.size))
        let image = render([group])
        #expect(isGreen(pixel(image, Int(box.minX) - 4, Int(box.midY))))
        #expect(isRed(pixel(image, Int(box.midX), Int(box.midY))))
    }
}
