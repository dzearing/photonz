import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// A line round a layer really is drawn outside it.
///
/// Reach is only half the promise: the other half is that the pixels are on the
/// canvas where the reach said they would be. So every test here composites a
/// real document and reads the colour at a point, one side or the other of the
/// layer's own edge. `docs/design/shape-parts.md`, "How the list grows".
@Suite("Border position rendering")
struct BorderPositionRenderTests {

    private let canvas = CGSize(width: 240, height: 200)
    /// The box every shape in here wears, in document points.
    private let box = CGRect(x: 60, y: 50, width: 100, height: 80)

    private func rgba(_ image: CGImage) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &data, width: image.width, height: image.height,
                                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return data
    }

    /// The pixel at a point in TOP-LEFT document coordinates, which is the
    /// space the box above is stated in.
    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        let data = rgba(image)
        let i = (y * image.width + x) * 4
        guard i + 3 < data.count else { return (0, 0, 0, 0) }
        return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]), Int(data[i + 3]))
    }

    private func isInk(_ p: (r: Int, g: Int, b: Int, a: Int)) -> Bool {
        p.a > 200 && p.r > 180 && p.g < 80 && p.b < 80
    }

    private func shapeLayer(_ shape: AnnotationShape, width: CGFloat,
                            position: BorderPosition, fill: String? = nil) -> Layer {
        var content = AnnotationContent(shape: shape, strokeWidth: width, colorHex: "#FF0000",
                                        start: .zero,
                                        end: CGPoint(x: box.width, y: box.height),
                                        fillColorHex: fill)
        content.strokePosition = position
        return Layer(name: "Box", content: .annotation(content), frame: box)
    }

    private func render(_ layers: [Layer], store: ImageStore = ImageStore()) -> CGImage {
        var doc = PhotonzDocument(canvasSize: canvas)
        for layer in layers { doc.addLayer(layer) }
        return DocumentRenderer().render(doc, store: store)!
    }

    // MARK: A shape's own stroke

    @Test("Inside draws exactly where it always drew: ink just in, clear just out")
    func rectangleInside() {
        let image = render([shapeLayer(.rectangle, width: 8, position: .inside)])
        // Two points in from the left edge is inside the 8pt line.
        #expect(isInk(pixel(image, Int(box.minX) + 2, Int(box.midY))))
        // Two points OUT is untouched canvas, as it has always been.
        #expect(pixel(image, Int(box.minX) - 2, Int(box.midY)).a < 20)
        // And the middle of the box is empty: no fill was asked for.
        #expect(pixel(image, Int(box.midX), Int(box.midY)).a < 20)
    }

    @Test("Outside puts the whole line past the edge and leaves the box alone")
    func rectangleOutside() {
        let image = render([shapeLayer(.rectangle, width: 8, position: .outside)])
        // Four points OUT is now the middle of the line.
        #expect(isInk(pixel(image, Int(box.minX) - 4, Int(box.midY))))
        #expect(isInk(pixel(image, Int(box.maxX) + 4, Int(box.midY))))
        #expect(isInk(pixel(image, Int(box.midX), Int(box.minY) - 4)))
        #expect(isInk(pixel(image, Int(box.midX), Int(box.maxY) + 4)))
        // Four points IN is now empty: the line stopped eating the shape.
        #expect(pixel(image, Int(box.minX) + 4, Int(box.midY)).a < 20)
        // And nothing reaches a whole width and a half out.
        #expect(pixel(image, Int(box.minX) - 12, Int(box.midY)).a < 20)
    }

    @Test("Centred straddles the edge: ink on both sides of it")
    func rectangleCentred() {
        let image = render([shapeLayer(.rectangle, width: 8, position: .center)])
        #expect(isInk(pixel(image, Int(box.minX) - 2, Int(box.midY))))
        #expect(isInk(pixel(image, Int(box.minX) + 2, Int(box.midY))))
        // Half a width plus slack out is past the line.
        #expect(pixel(image, Int(box.minX) - 8, Int(box.midY)).a < 20)
    }

    @Test("An ellipse puts its line outside too")
    func ellipseOutside() {
        let image = render([shapeLayer(.ellipse, width: 8, position: .outside)])
        // The top of an ellipse touches the middle of its box's top edge.
        #expect(isInk(pixel(image, Int(box.midX), Int(box.minY) - 4)))
        #expect(pixel(image, Int(box.midX), Int(box.minY) + 4).a < 20)
    }

    @Test("An outside line and the fill meet with no canvas showing between them")
    func fillMeetsAnOutsideLine() {
        let image = render([shapeLayer(.rectangle, width: 8, position: .outside,
                                       fill: "#0000FF")])
        // Just inside the edge is fill, not a hairline of canvas.
        let inside = pixel(image, Int(box.minX) + 1, Int(box.midY))
        #expect(inside.a > 200 && inside.b > 180)
        // Just outside it is the line.
        #expect(isInk(pixel(image, Int(box.minX) - 1, Int(box.midY))))
    }

    @Test("Zooming in does not clip the outside line")
    func outsideSurvivesMagnification() {
        var doc = PhotonzDocument(canvasSize: canvas)
        doc.addLayer(shapeLayer(.rectangle, width: 8, position: .outside))
        let store = ImageStore()
        let image = DocumentRenderer().render(doc, store: store, scale: 3)!
        #expect(image.width == Int(canvas.width * 3))
        // Four points out, in a picture drawn at three pixels to the point.
        #expect(isInk(pixel(image, Int((box.minX - 4) * 3), Int(box.midY * 3))))
    }

    // MARK: The ring round everything else

    @Test("A picture's ring sits outside its edge when it is told to")
    func pictureRingOutside() {
        let store = ImageStore()
        let context = CGContext(data: nil, width: 100, height: 80, bitsPerComponent: 8,
                                bytesPerRow: 400, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 80))
        let ref = store.register(context.makeImage()!)

        var shot = Layer(name: "Shot", content: .image(ref), frame: box)
        shot.style.borderWidth = 6
        shot.style.borderColorHex = "#FF0000"
        shot.style.borderPosition = .outside
        let image = render([shot], store: store)

        // Three points OUT is the ring.
        #expect(isInk(pixel(image, Int(box.minX) - 3, Int(box.midY))))
        // Three points IN is still the picture, not the ring eating into it.
        let inside = pixel(image, Int(box.minX) + 3, Int(box.midY))
        #expect(inside.b > 180 && inside.r < 80)
    }

    @Test("A group's ring is drawn outside the group, past what it holds")
    func groupRingOutside() {
        var child = shapeLayer(.rectangle, width: 4, position: .inside, fill: "#0000FF")
        child.frame = CGRect(x: 10, y: 10, width: 80, height: 60)
        var group = Layer(name: "Card", content: .group(GroupContent(children: [child])),
                          frame: CGRect(x: 50, y: 40, width: 0, height: 0))
        group.style.borderWidth = 6
        group.style.borderColorHex = "#FF0000"
        group.style.borderPosition = .outside

        let image = render([group])
        // A group's box already carries its own origin.
        let outer = group.localBounds
        #expect(isInk(pixel(image, Int(outer.minX) - 3, Int(outer.midY))))
        #expect(pixel(image, Int(outer.minX) - 9, Int(outer.midY)).a < 20)
    }

    @Test("A group does not clip a child whose line sits outside it")
    func groupDoesNotClipAnOutsideChild() {
        var child = shapeLayer(.rectangle, width: 8, position: .outside)
        child.frame = CGRect(x: 0, y: 0, width: 80, height: 60)
        let group = Layer(name: "Card", content: .group(GroupContent(children: [child])),
                          frame: CGRect(x: 70, y: 60, width: 0, height: 0))
        let image = render([group])
        // The child's own top-left corner sits exactly on the group's box, so
        // its outside line is the thing a group buffer would cut off.
        #expect(isInk(pixel(image, 70 - 4, 60 + 30)))
    }

    @Test("A screen that clips its contents still draws its own ring outside itself")
    func clippingFrameRingOutside() {
        var screen = Layer(name: "Screen",
                           content: .group(GroupContent(children: [], isFrame: true,
                                                        clipsContents: true,
                                                        backgroundHex: "#0000FF")),
                           frame: box)
        screen.style.borderWidth = 6
        screen.style.borderColorHex = "#FF0000"
        screen.style.borderPosition = .outside
        let image = render([screen])
        // The ring is the container's own, laid on after the clip, so clipping
        // never cuts it off.
        #expect(isInk(pixel(image, Int(box.minX) - 3, Int(box.midY))))
        // ...and the surface it clips to is untouched by it.
        let inside = pixel(image, Int(box.minX) + 3, Int(box.midY))
        #expect(inside.b > 180 && inside.r < 80)
    }

    @Test("The layers panel thumbnail still shows a line that sits outside the layer")
    func thumbnailKeepsAnOutsideLine() {
        var doc = PhotonzDocument(canvasSize: canvas)
        // Outline only, so the line is the whole of what the tile has to show.
        let outlined = shapeLayer(.rectangle, width: 10, position: .outside)
        doc.addLayer(outlined)
        let store = ImageStore()
        let tile = DocumentRenderer().thumbnail(for: outlined.id, in: doc, store: store,
                                                maxDimension: 64)!
        let pixels = rgba(tile)
        let inked = stride(from: 0, to: pixels.count, by: 4).filter { pixels[$0 + 3] > 40 }
        #expect(!inked.isEmpty)
    }

    // MARK: Nothing that was already right moved

    @Test("A layer with no line composites exactly the pixels it did before")
    func noLineIsUntouched() {
        var plain = shapeLayer(.rectangle, width: 0, position: .inside, fill: "#0000FF")
        plain.style.borderWidth = 0
        let image = render([plain])
        #expect(pixel(image, Int(box.midX), Int(box.midY)).b > 180)
        #expect(pixel(image, Int(box.minX) - 2, Int(box.midY)).a < 20)
    }
}
