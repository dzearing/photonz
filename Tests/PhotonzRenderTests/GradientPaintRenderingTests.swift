import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

@Suite("Gradient paint, drawn")
struct GradientPaintRenderingTests {

    /// Reads RGBA at (x, y) in top-left coordinates.
    private func pixel(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &data, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let offset = (y * width + x) * 4
        return (data[offset], data[offset + 1], data[offset + 2], data[offset + 3])
    }

    /// A ramp running pure red to pure blue, so which end a pixel came from is
    /// obvious from the channel that won.
    private func redToBlue(_ kind: Paint.Kind, angle: Double = 90,
                           center: CGPoint = CGPoint(x: 0.5, y: 0.5)) -> Paint {
        Paint(hex: "#FF0000", kind: kind,
              stops: [GradientStop(hex: "#FF0000", position: 0),
                      GradientStop(hex: "#0000FF", position: 1)],
              angle: angle, center: center)
    }

    private func box(fill: Paint?, stroke: Paint? = nil,
                     strokeWidth: CGFloat = 4) -> CGImage {
        var content = AnnotationContent(shape: .rectangle, strokeWidth: strokeWidth,
                                        colorHex: "#00FF00")
        content.start = CGPoint(x: 10, y: 10)
        content.end = CGPoint(x: 110, y: 90)
        content.fill = fill
        if let stroke { content.paint = stroke }
        return AnnotationRasterizer.rasterize(content, size: CGSize(width: 120, height: 100))!
    }

    // MARK: - The three gradient shapes

    @Test func aLinearFillRunsTheWayItIsAimed() {
        // 90 degrees is CSS's "to the right".
        let img = box(fill: redToBlue(.linear, angle: 90))
        let left = pixel(img, x: 20, y: 50)
        let right = pixel(img, x: 100, y: 50)
        #expect(left.r > 180 && left.b < 80, "the start of the ramp is at the left edge")
        #expect(right.b > 180 && right.r < 80, "the end of the ramp is at the right edge")
        let middle = pixel(img, x: 60, y: 50)
        #expect(middle.r > 60 && middle.b > 60, "the middle is a blend of both")
    }

    @Test func turningTheAngleTurnsTheRun() {
        // 180 degrees is "to the bottom".
        let img = box(fill: redToBlue(.linear, angle: 180))
        #expect(pixel(img, x: 60, y: 16).r > 180, "the ramp starts at the top")
        #expect(pixel(img, x: 60, y: 84).b > 180, "and finishes at the bottom")
    }

    @Test func aRadialFillSpreadsOutFromItsCentre() {
        let img = box(fill: redToBlue(.radial))
        #expect(pixel(img, x: 60, y: 50).r > 180, "the centre is the start of the ramp")
        let corner = pixel(img, x: 14, y: 14)
        #expect(corner.b > 140, "the far corner is the end of it")
    }

    @Test func movingTheCentreMovesTheRadialFill() {
        let img = box(fill: redToBlue(.radial, center: CGPoint(x: 0.1, y: 0.5)))
        #expect(pixel(img, x: 22, y: 50).r > 180, "the start follows the centre left")
        #expect(pixel(img, x: 100, y: 50).b > 140, "and the far side is the ramp's end")
    }

    @Test func anAngularFillSweepsAround() {
        let img = box(fill: redToBlue(.angular, angle: 0))
        // A sweep from the top, clockwise: just past 12 o'clock is the ramp's
        // start, just before it is the ramp's end.
        let justAfterTop = pixel(img, x: 64, y: 22)
        let justBeforeTop = pixel(img, x: 56, y: 22)
        #expect(justAfterTop.r > justAfterTop.b, "the sweep starts where it is aimed")
        #expect(justBeforeTop.b > justBeforeTop.r, "and comes back round to the far end")
    }

    // MARK: - Where a gradient is allowed to land

    @Test func aGradientFillStaysInsideTheShape() {
        let img = box(fill: redToBlue(.linear))
        #expect(pixel(img, x: 3, y: 3).a == 0, "outside the box stays transparent")
    }

    @Test func anEllipseGradientStaysInsideTheOval() {
        var content = AnnotationContent(shape: .ellipse, strokeWidth: 0, colorHex: "#00FF00")
        content.start = CGPoint(x: 10, y: 10)
        content.end = CGPoint(x: 110, y: 90)
        content.fill = redToBlue(.linear)
        let img = AnnotationRasterizer.rasterize(content, size: CGSize(width: 120, height: 100))!
        #expect(pixel(img, x: 60, y: 50).a > 200, "the oval is painted")
        #expect(pixel(img, x: 13, y: 13).a == 0, "the box corner outside it is not")
    }

    @Test func anOutlineTakesAGradientToo() {
        let img = box(fill: nil, stroke: redToBlue(.linear, angle: 90), strokeWidth: 10)
        let leftEdge = pixel(img, x: 12, y: 50)
        let rightEdge = pixel(img, x: 108, y: 50)
        #expect(leftEdge.r > 150 && leftEdge.b < 110, "the outline starts the ramp on the left")
        #expect(rightEdge.b > 150 && rightEdge.r < 110, "and finishes it on the right")
        #expect(pixel(img, x: 60, y: 50).a == 0, "the inside of an unfilled box is untouched")
    }

    // MARK: - A ramp with no ramp in it

    @Test func aGradientTypeWithNoStopsStillDrawsTheFlatColor() {
        var paint = Paint(hex: "#0000FF")
        paint.kind = .linear      // set without ever seeding a ramp
        let img = box(fill: paint)
        let interior = pixel(img, x: 60, y: 50)
        #expect(interior.b > 200 && interior.r < 80)
    }

    // MARK: - A screen's surface

    @Test func aFrameSurfaceTakesAGradient() {
        var frame = Layer.frameLayer(name: "Screen", origin: .zero,
                                     size: CGSize(width: 120, height: 100))
        frame.setPaint(redToBlue(.linear, angle: 90), for: .fill)
        var document = PhotonzDocument(canvasSize: CGSize(width: 120, height: 100))
        document.layers = [frame]
        let image = DocumentRenderer().render(document, store: ImageStore())!
        #expect(pixel(image, x: 8, y: 50).r > 180, "the surface starts the ramp on the left")
        #expect(pixel(image, x: 112, y: 50).b > 180, "and finishes it on the right")
    }

    @Test func aFlatFrameSurfaceIsUnchanged() {
        var frame = Layer.frameLayer(name: "Screen", origin: .zero,
                                     size: CGSize(width: 120, height: 100),
                                     backgroundHex: "#123456")
        frame.style.opacity = 1
        var document = PhotonzDocument(canvasSize: CGSize(width: 120, height: 100))
        document.layers = [frame]
        let image = DocumentRenderer().render(document, store: ImageStore())!
        let px = pixel(image, x: 60, y: 50)
        #expect(px.r == 0x12 && px.g == 0x34 && px.b == 0x56)
    }
}

@Suite("A document that holds a gradient")
struct GradientDocumentIOTests {

    private func box(fill: Paint?) -> Layer {
        var content = AnnotationContent(shape: .rectangle, strokeWidth: 2, colorHex: "#112233",
                                        start: .zero, end: CGPoint(x: 100, y: 80))
        content.fill = fill
        return AnnotationBuilder.layer(content: content, from: .zero, to: CGPoint(x: 100, y: 80))
    }

    private func saveAndReopen(_ document: PhotonzDocument) throws -> PhotonzDocument {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gradient-\(UUID().uuidString).photonz")
        defer { try? FileManager.default.removeItem(at: url) }
        try PackageIO.write(document, store: ImageStore(), to: url)
        return try PackageIO.read(from: url, into: ImageStore())
    }

    @Test func aSavedGradientComesBackTheSame() throws {
        var gradient = Paint(hex: "#3366FF")
        gradient.becoming(.angular)
        gradient.angle = 42
        gradient.center = CGPoint(x: 0.2, y: 0.8)
        var frame = Layer.frameLayer(name: "Screen", origin: .zero,
                                     size: CGSize(width: 320, height: 200))
        var linear = Paint(hex: "#101820")
        linear.becoming(.linear)
        frame.setPaint(linear, for: .fill)

        var document = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300))
        document.layers = [box(fill: gradient), frame]

        let back = try saveAndReopen(document)
        #expect(back.layers.first?.annotation?.fill == gradient)
        #expect(back.layers.last?.group?.background == linear)
    }

    @Test func aDocumentWithNoGradientInItIsWrittenExactlyAsItAlwaysWas() throws {
        var document = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300))
        document.layers = [box(fill: Paint(hex: "#ABCDEF"))]
        let json = String(decoding: try JSONEncoder().encode(document), as: UTF8.self)
        #expect(json.contains("\"fillColorHex\":\"#ABCDEF\""))
        #expect(!json.contains("\"stops\""))

        let back = try saveAndReopen(document)
        #expect(back.layers.first?.annotation?.fillColorHex == "#ABCDEF")
        #expect(back.layers.first?.annotation?.fill?.isGradient == false)
    }
}
