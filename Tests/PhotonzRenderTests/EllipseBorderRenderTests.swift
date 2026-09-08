import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// A ring you add to an oval is an oval.
///
/// Every ring used to be a rounded rectangle drawn round the layer's box, so a
/// border on an ellipse came out as a black SQUARE round a red oval (reported
/// on the probe, 2026-09-08). A layer that draws a shape of its own has its
/// ring follow that shape; a picture, a label, a frame or a group has no path
/// of its own, so those keep the ring round their box.
@Suite("Ellipse border rendering")
struct EllipseBorderRenderTests {

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
        p.a > 200 && p.g > 180 && p.r < 80 && p.b < 80
    }

    private func isBlue(_ p: (r: Int, g: Int, b: Int, a: Int)) -> Bool {
        p.a > 200 && p.b > 180 && p.r < 80 && p.g < 80
    }

    private func isClear(_ p: (r: Int, g: Int, b: Int, a: Int)) -> Bool { p.a < 20 }

    /// A filled oval with no line of its own, so the only rings in the picture
    /// are the ones the Effects list put there.
    private func filledEllipse(_ effects: [LayerEffect]) -> Layer {
        var style = LayerStyle()
        style.effects = effects
        return Layer(name: "Oval",
                     content: .annotation(AnnotationContent(shape: .ellipse,
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

    @Test("An outside border on an ellipse is an oval ring, not a square one")
    func outsideBorderFollowsTheOval() {
        let image = render([filledEllipse([.border(BorderEffect(width: 8, colorHex: "#00FF00",
                                                                position: .outside))])])
        // The ring is there on all four sides, four points out from the box.
        #expect(isGreen(pixel(image, Int(box.minX) - 4, Int(box.midY))))
        #expect(isGreen(pixel(image, Int(box.maxX) + 4, Int(box.midY))))
        #expect(isGreen(pixel(image, Int(box.midX), Int(box.minY) - 4)))
        #expect(isGreen(pixel(image, Int(box.midX), Int(box.maxY) + 4)))
        // And the CORNERS of the box are empty: an oval has none.
        #expect(isClear(pixel(image, Int(box.minX) - 4, Int(box.minY) - 4)))
        #expect(isClear(pixel(image, Int(box.maxX) + 4, Int(box.minY) - 4)))
        #expect(isClear(pixel(image, Int(box.minX) - 4, Int(box.maxY) + 4)))
        #expect(isClear(pixel(image, Int(box.maxX) + 4, Int(box.maxY) + 4)))
        // The oval itself is untouched.
        let middle = pixel(image, Int(box.midX), Int(box.midY))
        #expect(middle.r > 180 && middle.g < 80)
    }

    @Test("An inside border on an ellipse hugs the oval from within")
    func insideBorderFollowsTheOval() {
        let image = render([filledEllipse([.border(BorderEffect(width: 8, colorHex: "#00FF00",
                                                                position: .inside))])])
        // Four points in from the box's edge, on the flat of the oval.
        #expect(isGreen(pixel(image, Int(box.minX) + 4, Int(box.midY))))
        #expect(isGreen(pixel(image, Int(box.midX), Int(box.minY) + 4)))
        // The box's inner corner is outside the oval altogether, so it is empty
        // rather than the corner of a square frame.
        #expect(isClear(pixel(image, Int(box.minX) + 2, Int(box.minY) + 2)))
        // Nothing spills outside the box.
        #expect(isClear(pixel(image, Int(box.minX) - 4, Int(box.midY))))
    }

    @Test("A centred border on an ellipse straddles the oval's edge")
    func centredBorderFollowsTheOval() {
        let image = render([filledEllipse([.border(BorderEffect(width: 8, colorHex: "#00FF00",
                                                                position: .center))])])
        // Half in, half out, on the flat of the left edge.
        #expect(isGreen(pixel(image, Int(box.minX) - 2, Int(box.midY))))
        #expect(isGreen(pixel(image, Int(box.minX) + 2, Int(box.midY))))
        // Still nothing in the corner.
        #expect(isClear(pixel(image, Int(box.minX) - 2, Int(box.minY) - 2)))
    }

    @Test("Two borders on one ellipse both follow it, top of the list on top")
    func twoRingsBothFollowTheOval() {
        let image = render([filledEllipse([
            .border(BorderEffect(width: 6, colorHex: "#00FF00", position: .outside)),
            .border(BorderEffect(width: 6, colorHex: "#0000FF", position: .inside))
        ])])
        #expect(isGreen(pixel(image, Int(box.minX) - 3, Int(box.midY))))
        #expect(isBlue(pixel(image, Int(box.minX) + 3, Int(box.midY))))
        // Neither of them squares off the corner.
        #expect(isClear(pixel(image, Int(box.minX) - 3, Int(box.minY) - 3)))

        // Two outside rings in the same place: the one nearer the top of the
        // list still paints over the other.
        let narrowOnTop = render([filledEllipse([
            .border(BorderEffect(width: 4, colorHex: "#0000FF", position: .outside)),
            .border(BorderEffect(width: 10, colorHex: "#00FF00", position: .outside))
        ])])
        #expect(isBlue(pixel(narrowOnTop, Int(box.minX) - 2, Int(box.midY))))
        #expect(isGreen(pixel(narrowOnTop, Int(box.minX) - 8, Int(box.midY))))
    }

    @Test("A border covers the oval's own outline instead of leaving a seam")
    func aBorderLandsOnTheShapesOwnLine() {
        // The point of drawing the ring as a stroke: an added border at the
        // same width and the same position lands on exactly the pixels the
        // shape's own outline drew, so nothing of the red line below shows
        // round the green one on top. This is what lets one line round a shape
        // be drawn either way (`OutlineWidth.swift`).
        var style = LayerStyle()
        style.effects = [.border(BorderEffect(width: 8, colorHex: "#00FF00", position: .inside))]
        let layer = Layer(name: "Oval",
                          content: .annotation(AnnotationContent(shape: .ellipse, strokeWidth: 8,
                                                                 colorHex: "#FF0000", start: .zero,
                                                                 end: CGPoint(x: box.width,
                                                                              y: box.height))),
                          frame: box, style: style)
        let image = render([layer])
        // Round the whole oval, at eight points of the compass, nothing red is
        // left showing.
        for step in 0..<8 {
            let angle = Double(step) * .pi / 4
            let x = Int((box.midX + cos(angle) * box.width / 2).rounded())
            let y = Int((box.midY + sin(angle) * box.height / 2).rounded())
            for dx in -1...1 {
                for dy in -1...1 {
                    let p = pixel(image, x + dx, y + dy)
                    #expect(p.r < 140 || p.g > 100, "red seam at \(x + dx), \(y + dy)")
                }
            }
        }
    }

    @Test("An oval too big to bake at full size still gets its ring")
    func aHugeOvalStillRings() {
        // Past the ceiling the ring is drawn smaller and blown up, the way a
        // layer's own content is. It must still be an oval, still be on the
        // edge, and still leave the corners of the box empty.
        let canvas = CGSize(width: 4500, height: 4000)
        let big = CGRect(x: 20, y: 20, width: 4400, height: 3900)   // over 16 megapixels
        var style = LayerStyle()
        style.effects = [.border(BorderEffect(width: 40, colorHex: "#00FF00", position: .inside))]
        var doc = PhotonzDocument(canvasSize: canvas)
        doc.addLayer(Layer(name: "Oval",
                           content: .annotation(AnnotationContent(shape: .ellipse, strokeWidth: 0,
                                                                  colorHex: "#FF0000", start: .zero,
                                                                  end: CGPoint(x: big.width,
                                                                               y: big.height),
                                                                  fillColorHex: "#FF0000")),
                           frame: big, style: style))
        let image = DocumentRenderer().render(doc, store: ImageStore())!
        #expect(isGreen(pixel(image, Int(big.minX) + 20, Int(big.midY))))
        #expect(isGreen(pixel(image, Int(big.midX), Int(big.minY) + 20)))
        #expect(isClear(pixel(image, Int(big.minX) + 8, Int(big.minY) + 8)))
    }

    @Test("A border on a picture still rings its box")
    func aPictureKeepsItsSquareRing() {
        // A photograph has no path of its own, so the ring round it is the one
        // it always was: a rectangle, corners and all.
        var style = LayerStyle()
        style.effects = [.border(BorderEffect(width: 8, colorHex: "#00FF00", position: .outside))]
        let store = ImageStore()
        let ref = store.register(SolidImage.make(size: box.size, hex: "#FF0000")!)
        let layer = Layer(name: "Shot", content: .image(ref), frame: box, style: style)
        var doc = PhotonzDocument(canvasSize: canvas)
        doc.addLayer(layer)
        let image = DocumentRenderer().render(doc, store: store)!
        #expect(isGreen(pixel(image, Int(box.minX) - 4, Int(box.midY))))
        #expect(isGreen(pixel(image, Int(box.minX) - 4, Int(box.minY) - 4)))
    }
}
