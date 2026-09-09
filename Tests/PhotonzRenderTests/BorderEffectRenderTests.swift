import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// The rings somebody ADDED really land on the canvas.
///
/// A reach that makes room is only half of it; the other half is a pixel of the
/// right colour on the right side of the layer's edge. So every test here
/// composites a real document and reads points either side of the box.
@Suite("Border effect rendering")
struct BorderEffectRenderTests {

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

    /// A plain filled box with no stroke of its own, so the only lines in the
    /// picture are the ones the Effects list put there.
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

    @Test("An added border sits outside the edge and leaves the shape its size")
    func outsideBorder() {
        let image = render([filledBox([.border(BorderEffect(width: 8, colorHex: "#00FF00",
                                                            position: .outside))])])
        // Four points OUT is the middle of the ring, on all four sides.
        #expect(isGreen(pixel(image, Int(box.minX) - 4, Int(box.midY))))
        #expect(isGreen(pixel(image, Int(box.maxX) + 4, Int(box.midY))))
        #expect(isGreen(pixel(image, Int(box.midX), Int(box.minY) - 4)))
        #expect(isGreen(pixel(image, Int(box.midX), Int(box.maxY) + 4)))
        // Four points IN is still the shape: an outside ring eats nothing.
        let inside = pixel(image, Int(box.minX) + 4, Int(box.midY))
        #expect(inside.r > 180 && inside.g < 80)
        // And nothing reaches a width and a half out.
        #expect(pixel(image, Int(box.minX) - 12, Int(box.midY)).a < 20)
    }

    @Test("An outside border on a square box keeps its corners square")
    func squareCornersStaySquare() {
        // Found on the running probe, not in a test: an 11pt outside ring round
        // a sharp box came back with rounded outer corners, because pushing a
        // rounded rect out by d grows its radius by d and a radius of zero is
        // still a radius. A stroke round a square button has to stay square.
        let image = render([filledBox([.border(BorderEffect(width: 8, colorHex: "#00FF00",
                                                            position: .outside))])])
        // Two points in from the ring's very corner, on the diagonal: outside
        // any arc of radius 8, so this pixel exists only if the corner is
        // square.
        #expect(isGreen(pixel(image, Int(box.minX) - 6, Int(box.minY) - 6)))
        #expect(isGreen(pixel(image, Int(box.maxX) + 6, Int(box.maxY) + 6)))
    }

    @Test("An outside border on a ROUNDED box follows the corner it was given")
    func roundedCornersStayConcentric() {
        var style = LayerStyle()
        style.cornerRadius = 24
        style.effects = [.border(BorderEffect(width: 8, colorHex: "#00FF00", position: .outside))]
        let layer = Layer(name: "Box",
                          content: .annotation(AnnotationContent(shape: .rectangle, strokeWidth: 0,
                                                                 colorHex: "#FF0000", start: .zero,
                                                                 end: CGPoint(x: box.width,
                                                                              y: box.height),
                                                                 fillColorHex: "#FF0000")),
                          frame: box, style: style)
        let image = render([layer])
        // The ring is still there on the flat of the edge...
        #expect(isGreen(pixel(image, Int(box.minX) - 4, Int(box.midY))))
        // ...and the square corner of its box is empty, because the corner is
        // round.
        #expect(pixel(image, Int(box.minX) - 6, Int(box.minY) - 6).a < 20)
    }

    @Test("An added border can sit inside the edge instead")
    func insideBorder() {
        let image = render([filledBox([.border(BorderEffect(width: 8, colorHex: "#00FF00",
                                                            position: .inside))])])
        #expect(isGreen(pixel(image, Int(box.minX) + 4, Int(box.midY))))
        // Nothing at all outside the box.
        #expect(pixel(image, Int(box.minX) - 4, Int(box.midY)).a < 20)
        // The middle of the shape is untouched.
        let middle = pixel(image, Int(box.midX), Int(box.midY))
        #expect(middle.r > 180 && middle.g < 80)
    }

    @Test("Two borders with different positions both draw, on one shape")
    func innerAndOuterTogether() {
        let image = render([filledBox([
            .border(BorderEffect(width: 6, colorHex: "#00FF00", position: .outside)),
            .border(BorderEffect(width: 6, colorHex: "#0000FF", position: .inside))
        ])])
        #expect(isGreen(pixel(image, Int(box.minX) - 3, Int(box.midY))))
        #expect(isBlue(pixel(image, Int(box.minX) + 3, Int(box.midY))))
    }

    @Test("The border nearer the top of the list paints over the one below it")
    func listOrderIsPaintOrder() {
        // Two outside rings, the wide one and a narrow one in the same place.
        // Top of the list is nearest the eye, so whichever is first wins where
        // they overlap.
        let narrowOnTop = render([filledBox([
            .border(BorderEffect(width: 4, colorHex: "#0000FF", position: .outside)),
            .border(BorderEffect(width: 10, colorHex: "#00FF00", position: .outside))
        ])])
        #expect(isBlue(pixel(narrowOnTop, Int(box.minX) - 2, Int(box.midY))))
        #expect(isGreen(pixel(narrowOnTop, Int(box.minX) - 8, Int(box.midY))))

        let wideOnTop = render([filledBox([
            .border(BorderEffect(width: 10, colorHex: "#00FF00", position: .outside)),
            .border(BorderEffect(width: 4, colorHex: "#0000FF", position: .outside))
        ])])
        #expect(isGreen(pixel(wideOnTop, Int(box.minX) - 2, Int(box.midY))))
        #expect(isGreen(pixel(wideOnTop, Int(box.minX) - 8, Int(box.midY))))
    }

    @Test("A border switched off draws nothing at all")
    func offDrawsNothing() {
        let image = render([filledBox([.border(BorderEffect(width: 8, colorHex: "#00FF00",
                                                            position: .outside, isOn: false))])])
        #expect(pixel(image, Int(box.minX) - 4, Int(box.midY)).a < 20)
    }

    @Test("A drop shadow is cast from the shape wearing its borders")
    func shadowFollowsTheOuterRing() {
        // The ring is 8pt outside; a hard shadow 20pt down must therefore have
        // ink 20pt below the RING's outer edge, not the box's.
        let image = render([filledBox([
            .border(BorderEffect(width: 8, colorHex: "#00FF00", position: .outside)),
            .shadow(ShadowStyle(radius: 0, offset: CGSize(width: 0, height: 20),
                                colorHex: "#000000", opacity: 1))
        ])])
        let below = pixel(image, Int(box.midX), Int(box.maxY) + 8 + 16)
        #expect(below.a > 200 && below.r < 60 && below.g < 60 && below.b < 60)
    }

    // MARK: Standing off the edge

    @Test("An outside border with an offset stands clear of the shape, with a gap")
    func outsideOffsetStandsOff() {
        // Six thick, ten out: ink from ten to sixteen past the edge, clear air
        // between the shape and the ring. That gap is the whole point of the
        // offset — it is what makes a second ring read as a ring rather than as
        // a thicker first one.
        let image = render([filledBox([.border(BorderEffect(width: 6, colorHex: "#00FF00",
                                                            position: .outside, offset: 10))])])
        #expect(isGreen(pixel(image, Int(box.minX) - 13, Int(box.midY))))
        #expect(isGreen(pixel(image, Int(box.maxX) + 13, Int(box.midY))))
        #expect(isGreen(pixel(image, Int(box.midX), Int(box.minY) - 13)))
        // The gap is empty...
        #expect(pixel(image, Int(box.minX) - 5, Int(box.midY)).a < 20)
        // ...nothing reaches past the ring...
        #expect(pixel(image, Int(box.minX) - 20, Int(box.midY)).a < 20)
        // ...and the shape itself is untouched.
        let inside = pixel(image, Int(box.minX) + 4, Int(box.midY))
        #expect(inside.r > 180 && inside.g < 80)
    }

    @Test("An inside border with an offset moves that far further in")
    func insideOffsetMovesIn() {
        let image = render([filledBox([.border(BorderEffect(width: 6, colorHex: "#00FF00",
                                                            position: .inside, offset: 10))])])
        // Ink from ten to sixteen INSIDE the edge...
        #expect(isGreen(pixel(image, Int(box.minX) + 13, Int(box.midY))))
        #expect(isGreen(pixel(image, Int(box.maxX) - 13, Int(box.midY))))
        // ...the band nearest the edge is the shape again...
        let atEdge = pixel(image, Int(box.minX) + 4, Int(box.midY))
        #expect(atEdge.r > 180 && atEdge.g < 80)
        // ...and nothing at all escapes the box.
        #expect(pixel(image, Int(box.minX) - 4, Int(box.midY)).a < 20)
    }

    @Test("A tight ring and an offset ring draw as two separate rings")
    func twoRingsWithAGapBetween() {
        let image = render([filledBox([
            .border(BorderEffect(width: 4, colorHex: "#00FF00", position: .outside)),
            .border(BorderEffect(width: 4, colorHex: "#0000FF", position: .outside, offset: 10))
        ])])
        // The tight one hugs the edge...
        #expect(isGreen(pixel(image, Int(box.minX) - 2, Int(box.midY))))
        // ...a gap...
        #expect(pixel(image, Int(box.minX) - 7, Int(box.midY)).a < 20)
        // ...then the one standing off it, in its own colour.
        #expect(isBlue(pixel(image, Int(box.minX) - 12, Int(box.midY))))
        #expect(pixel(image, Int(box.minX) - 20, Int(box.midY)).a < 20)
    }

    @Test("A centred border ignores an offset, because it has no side to stand off")
    func centreIgnoresTheOffset() {
        let image = render([filledBox([.border(BorderEffect(width: 8, colorHex: "#00FF00",
                                                            position: .center, offset: 20))])])
        // Straddling the edge exactly as it would with no offset at all.
        #expect(isGreen(pixel(image, Int(box.minX) - 2, Int(box.midY))))
        #expect(isGreen(pixel(image, Int(box.minX) + 2, Int(box.midY))))
        #expect(pixel(image, Int(box.minX) - 22, Int(box.midY)).a < 20)
    }

    @Test("An offset ring round a rounded box stays parallel to it")
    func offsetCornersStayRound() {
        var style = LayerStyle()
        style.cornerRadius = 24
        style.effects = [.border(BorderEffect(width: 8, colorHex: "#00FF00",
                                              position: .outside, offset: 10))]
        let layer = Layer(name: "Box",
                          content: .annotation(AnnotationContent(shape: .rectangle, strokeWidth: 0,
                                                                 colorHex: "#FF0000", start: .zero,
                                                                 end: CGPoint(x: box.width,
                                                                              y: box.height),
                                                                 fillColorHex: "#FF0000")),
                          frame: box, style: style)
        let image = render([layer])
        // On the flat of the edge the ring is where the offset put it...
        #expect(isGreen(pixel(image, Int(box.minX) - 14, Int(box.midY))))
        // ...the corner has grown with the ring, so the arc runs through here...
        #expect(isGreen(pixel(image, Int(box.minX) - 3, Int(box.minY) - 3)))
        // ...and the square corner of the ring's own box is empty, which it
        // would not be if the offset had squared the corner off.
        #expect(pixel(image, Int(box.minX) - 16, Int(box.minY) - 16).a < 20)
    }

    @Test("A shape wearing an offset ring is not clipped at its own frame")
    func nothingClipsTheOffsetRing() {
        // The reach has to grow with the offset or the far side of the ring is
        // cut off at the layer's box. Thirty out and four thick: ink at
        // thirty-two, nothing at thirty-eight.
        let image = render([filledBox([.border(BorderEffect(width: 4, colorHex: "#00FF00",
                                                            position: .outside, offset: 30))])])
        #expect(isGreen(pixel(image, Int(box.minX) - 32, Int(box.midY))))
        #expect(isGreen(pixel(image, Int(box.midX), Int(box.minY) - 32)))
        #expect(pixel(image, Int(box.minX) - 38, Int(box.midY)).a < 20)
    }
}
