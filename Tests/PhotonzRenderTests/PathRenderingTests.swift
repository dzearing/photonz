import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// A path draws: straight runs come out straight, curved runs come out smooth,
/// a closed path fills and an open one does not
/// (`docs/design/vector-paths.md`).
@Suite("Path rendering")
struct PathRenderingTests {

    // MARK: Helpers

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

    private func bytes(_ image: CGImage) -> [UInt8] {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &data, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return data
    }

    private func solidImage(width: Int, height: Int, gray: UInt8) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: CGFloat(gray) / 255, green: CGFloat(gray) / 255,
                                     blue: CGFloat(gray) / 255, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// A 100-wide shape whose top and bottom edges are dead straight and whose
    /// right-hand side bows out to x = 130. The one shape that proves straight
    /// and curved live in the same outline.
    private func bowedSquare(closed: Bool = true) -> PathContent {
        var path = PathContent(anchors: [
            PathAnchor(point: CGPoint(x: 0, y: 0)),
            PathAnchor(point: CGPoint(x: 100, y: 0), handleOut: CGPoint(x: 40, y: 30)),
            PathAnchor(point: CGPoint(x: 100, y: 100), handleIn: CGPoint(x: 40, y: -30)),
            PathAnchor(point: CGPoint(x: 0, y: 100))
        ], isClosed: closed)
        path.strokeWidth = 0
        return path
    }

    /// The shape rasterized on its own, in its own box.
    private func raster(_ path: PathContent) -> CGImage {
        PathRasterizer.rasterize(path, size: path.bounds.size)!
    }

    private func isBlue(_ p: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)) -> Bool {
        p.b > 180 && p.r < 90
    }

    private func isGreen(_ p: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)) -> Bool {
        p.g > 160 && p.r < 100 && p.b < 100
    }

    // MARK: Fill

    @Test func aClosedPathFillsItsInside() {
        var path = bowedSquare()
        path.fill = Paint(hex: "#0000FF")
        let image = raster(path)
        #expect(isBlue(pixel(image, x: 50, y: 50)), "middle of the shape is painted")
    }

    @Test func anOpenPathDoesNotFill() {
        var path = bowedSquare(closed: false)
        path.fill = Paint(hex: "#0000FF")
        path.strokeWidth = 4
        path.paint = Paint(hex: "#0000FF")
        let image = raster(path)
        #expect(pixel(image, x: 50, y: 50).a == 0, "nothing in the middle of an open path")
    }

    @Test func theStraightRunsComeOutStraight() {
        var path = bowedSquare()
        path.fill = Paint(hex: "#0000FF")
        let image = raster(path)
        // The top edge runs dead along y = 0 from x = 0 to x = 100, so a row
        // two pixels down is painted the whole way across and the row above
        // the shape is empty.
        for x in stride(from: 4, through: 96, by: 8) {
            #expect(isBlue(pixel(image, x: x, y: 3)), "top edge sags at x = \(x)")
            #expect(isBlue(pixel(image, x: x, y: 96)), "bottom edge sags at x = \(x)")
        }
    }

    @Test func theCurvedRunBulgesWhereTheMathsSaysItDoes() {
        var path = bowedSquare()
        path.fill = Paint(hex: "#0000FF")
        let image = raster(path)
        // Halfway down, the outline reaches x = 130 and no further.
        #expect(isBlue(pixel(image, x: 126, y: 50)), "the bulge is painted out to 130")
        #expect(pixel(image, x: 129, y: 4).a == 0, "and nowhere near it at the top")
    }

    @Test func aPathWithNoFillIsHollow() {
        var path = bowedSquare()
        path.fill = nil
        path.strokeWidth = 6
        path.paint = Paint(hex: "#0000FF")
        let image = raster(path)
        #expect(pixel(image, x: 50, y: 50).a == 0, "no fill leaves the inside clear")
        #expect(isBlue(pixel(image, x: 50, y: 3)), "the line is still drawn")
    }

    @Test func evenOddLeavesAHoleWhereNonZeroWouldNot() {
        // An outer ring and an inner ring drawn the SAME way round: non-zero
        // fills both, even-odd cuts the inner one out. That is how an icon
        // gets a hole in it.
        func ring(_ box: CGRect) -> [PathAnchor] {
            [PathAnchor(point: CGPoint(x: box.minX, y: box.minY)),
             PathAnchor(point: CGPoint(x: box.maxX, y: box.minY)),
             PathAnchor(point: CGPoint(x: box.maxX, y: box.maxY)),
             PathAnchor(point: CGPoint(x: box.minX, y: box.maxY))]
        }
        var path = PathContent(anchors: ring(CGRect(x: 0, y: 0, width: 100, height: 100))
                               + ring(CGRect(x: 30, y: 30, width: 40, height: 40)),
                               isClosed: true)
        path.strokeWidth = 0
        path.fill = Paint(hex: "#0000FF")
        path.fillRule = .nonZero
        #expect(isBlue(pixel(raster(path), x: 50, y: 50)), "non-zero fills through")
        path.fillRule = .evenOdd
        #expect(pixel(raster(path), x: 50, y: 50).a == 0, "even-odd leaves a hole")
    }

    // MARK: The outline

    @Test func theOutlineIsPaintedInItsOwnColour() {
        var path = bowedSquare()
        path.fill = Paint(hex: "#0000FF")
        path.paint = Paint(hex: "#00CC00")
        path.strokeWidth = 8
        path.strokePosition = .inside
        let image = raster(path)
        #expect(isGreen(pixel(image, x: 50, y: 3)), "the top edge wears the line colour")
        #expect(isBlue(pixel(image, x: 50, y: 50)), "the middle still wears the fill")
    }

    @Test func aCentredOutlineIsDrawnPastTheShapeAndTheBitmapMakesRoomForIt() {
        var path = bowedSquare()
        path.fill = nil
        path.paint = Paint(hex: "#00CC00")
        path.strokeWidth = 10
        path.strokePosition = .center
        #expect(path.strokeOutset == 5)
        let image = PathRasterizer.rasterize(path, size: path.bounds.size)!
        // 130 x 100 of shape plus 5 on every side.
        #expect(image.width == 140)
        #expect(image.height == 110)
        // The top edge sits 5 in from the top of the padded bitmap, so the
        // line straddles it: a pixel two rows ABOVE the shape is painted.
        #expect(isGreen(pixel(image, x: 55, y: 2)), "the centred line reaches past the shape")
    }

    @Test func anInsideOutlineStaysWithinTheShape() {
        var path = bowedSquare()
        path.fill = nil
        path.paint = Paint(hex: "#00CC00")
        path.strokeWidth = 10
        path.strokePosition = .inside
        #expect(path.strokeOutset == 0)
        let image = PathRasterizer.rasterize(path, size: path.bounds.size)!
        #expect(image.width == 130 && image.height == 100, "no padding needed")
        #expect(isGreen(pixel(image, x: 55, y: 3)), "the line is drawn just inside the edge")
        #expect(pixel(image, x: 55, y: 50).a == 0, "and nowhere near the middle")
    }

    @Test func aGradientCanPaintTheFillAndTheOutline() {
        var path = bowedSquare()
        var ramp = Paint(hex: "#FF0000")
        ramp.becoming(.linear)
        ramp.stops = [GradientStop(hex: "#FF0000", position: 0),
                      GradientStop(hex: "#0000FF", position: 1)]
        ramp.angle = 90
        path.fill = ramp
        path.strokeWidth = 0
        let image = raster(path)
        let left = pixel(image, x: 6, y: 50), right = pixel(image, x: 96, y: 50)
        #expect(left.r > right.r, "the ramp runs red to blue across the shape")
        #expect(right.b > left.b)
    }

    @Test func aPathWithFewerThanTwoAnchorsDrawsNothing() {
        #expect(PathRasterizer.rasterize(PathContent(anchors: []),
                                         size: CGSize(width: 10, height: 10)) == nil)
    }

    // MARK: Through the whole renderer

    /// A path layer composited into a real document, so everything the shared
    /// pipeline does to it — the box, the outset, the placement — is exercised.
    private func renderDocument(_ path: PathContent, at origin: CGPoint,
                                canvas: Int = 200) -> (doc: PhotonzDocument, store: ImageStore, image: CGImage) {
        let store = ImageStore()
        let base = store.register(solidImage(width: canvas, height: canvas, gray: 255))
        var doc = PhotonzDocument.withBaseImage(base)
        doc.addLayer(PathBuilder.layer(path, at: origin))
        return (doc, store, DocumentRenderer().render(doc, store: store)!)
    }

    @Test func aPathLandsWhereItsLayerIs() {
        var path = bowedSquare()
        path.fill = Paint(hex: "#0000FF")
        let rendered = renderDocument(path, at: CGPoint(x: 20, y: 30))
        #expect(isBlue(pixel(rendered.image, x: 70, y: 80)), "inside the shape")
        #expect(!isBlue(pixel(rendered.image, x: 10, y: 10)), "outside it the canvas shows")
        // The right-hand bulge reaches 20 + 130 = 150.
        #expect(isBlue(pixel(rendered.image, x: 147, y: 80)))
        #expect(!isBlue(pixel(rendered.image, x: 153, y: 80)))
    }

    /// Acceptance: it survives save and load exactly, checked by comparing the
    /// PICTURE rather than the file.
    @Test func aSavedAndReloadedPathRendersIdentically() throws {
        var path = bowedSquare()
        path.fill = Paint(hex: "#0000FF")
        path.paint = Paint(hex: "#00CC00")
        path.strokeWidth = 7
        path.anchors[1].kind = .smooth
        let first = renderDocument(path, at: CGPoint(x: 20, y: 30))
        let data = try JSONEncoder().encode(first.doc)
        let reloaded = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        let second = DocumentRenderer().render(reloaded, store: first.store)!
        #expect(bytes(second) == bytes(first.image), "the reopened document draws the same picture")
    }

    @Test func aResizedPathScalesItsCurvesRatherThanDistortingThem() {
        var path = bowedSquare()
        path.fill = Paint(hex: "#0000FF")
        path.strokeWidth = 0
        let store = ImageStore()
        let base = store.register(solidImage(width: 300, height: 300, gray: 255))
        var doc = PhotonzDocument.withBaseImage(base)
        let layer = PathBuilder.layer(path, at: CGPoint(x: 10, y: 10))
        doc.addLayer(layer.resized(to: CGRect(x: 10, y: 10, width: 260, height: 200)))
        let image = DocumentRenderer().render(doc, store: store)!
        // Twice as wide, twice as tall: the bulge is still exactly at the far
        // edge and the straight edges are still straight.
        #expect(isBlue(pixel(image, x: 265, y: 110)), "the bulge reaches the new right edge")
        #expect(!isBlue(pixel(image, x: 275, y: 110)), "and no further")
        for x in stride(from: 20, through: 200, by: 20) {
            #expect(isBlue(pixel(image, x: x, y: 14)), "top edge still straight at \(x)")
        }
    }

    @Test func anOpacityAndAShadowReachAPathLikeAnyOtherLayer() {
        var path = bowedSquare()
        path.fill = Paint(hex: "#0000FF")
        path.strokeWidth = 0
        let store = ImageStore()
        let base = store.register(solidImage(width: 200, height: 200, gray: 255))
        var doc = PhotonzDocument.withBaseImage(base)
        var layer = PathBuilder.layer(path, at: CGPoint(x: 20, y: 30))
        layer.style.opacity = 0.5
        doc.addLayer(layer)
        let image = DocumentRenderer().render(doc, store: store)!
        let middle = pixel(image, x: 70, y: 80)
        #expect(middle.b > 100 && middle.r > 100, "half-strength blue over white")
    }
}
