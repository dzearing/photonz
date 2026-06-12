import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

@Suite("Zoom callout rendering")
struct ZoomCalloutRenderingTests {

    private func solidImage(width: Int, height: Int, r: UInt8, g: UInt8, b: UInt8) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255,
                                     blue: CGFloat(b) / 255, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// Four-quadrant CGImage (top-left coords): TL red, TR green, BL blue, BR white.
    private func quadrantImage(size: Int) -> CGImage {
        let context = CGContext(data: nil, width: size, height: size,
                                bitsPerComponent: 8, bytesPerRow: size * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let half = size / 2
        // CGContext is bottom-left origin, so "top-left quadrant" fills the upper half.
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: half, width: half, height: half))
        context.setFillColor(CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1))
        context.fill(CGRect(x: half, y: half, width: half, height: half))
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: half, height: half))
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: half, y: 0, width: half, height: half))
        return context.makeImage()!
    }

    /// Reads the RGBA value at (x, y) in top-left coordinates.
    private func pixel(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let width = image.width
        let height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &data, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let offset = (y * width + x) * 4
        return (data[offset], data[offset + 1], data[offset + 2], data[offset + 3])
    }

    private func calloutLayer(source: CGRect, magnification: CGFloat,
                              frame: CGRect? = nil, style: LayerStyle = LayerStyle(),
                              shape: ZoomCalloutShape = .rectangle) -> Layer {
        let frame = frame ?? CGRect(x: 0, y: 0,
                                    width: source.width * magnification,
                                    height: source.height * magnification)
        return Layer(name: "Zoom",
                     content: .zoomCallout(ZoomCalloutContent(sourceRect: source, magnification: magnification,
                                                              shape: shape)),
                     frame: frame, style: style)
    }

    @Test func magnifiesSourceRegionIntoFrame() {
        let store = ImageStore()
        // 100×100 quadrant base: source box sits inside the green TR quadrant.
        let base = store.register(quadrantImage(size: 100))
        var doc = PhotonzDocument.withBaseImage(base)
        doc.canvasSize = CGSize(width: 200, height: 200)

        // Source 60..80 × 10..30 (green), callout placed at (100, 100) at 3×.
        doc.addLayer(calloutLayer(source: CGRect(x: 60, y: 10, width: 20, height: 20),
                                  magnification: 3,
                                  frame: CGRect(x: 100, y: 100, width: 60, height: 60)))

        let output = DocumentRenderer().render(doc, store: store)!
        let inside = pixel(output, x: 130, y: 130)
        #expect(inside.g > 240 && inside.r < 16 && inside.b < 16,
                "callout center shows magnified green source — got \(inside)")
        // Outside the callout and base image the canvas stays clear.
        let outside = pixel(output, x: 180, y: 50)
        #expect(outside.a < 16, "canvas outside callout stays clear — got \(outside)")
    }

    @Test func magnificationMapsPixelsProportionally() {
        let store = ImageStore()
        let base = store.register(quadrantImage(size: 100))
        var doc = PhotonzDocument.withBaseImage(base)
        doc.canvasSize = CGSize(width: 300, height: 300)

        // Source spans all four quadrants: 30..70 in both axes, magnified 4×.
        doc.addLayer(calloutLayer(source: CGRect(x: 30, y: 30, width: 40, height: 40),
                                  magnification: 4,
                                  frame: CGRect(x: 120, y: 120, width: 160, height: 160)))

        let output = DocumentRenderer().render(doc, store: store)!
        // Each quadrant of the source should land in the matching quadrant of the callout.
        let tl = pixel(output, x: 160, y: 160)
        let tr = pixel(output, x: 240, y: 160)
        let bl = pixel(output, x: 160, y: 240)
        let br = pixel(output, x: 240, y: 240)
        #expect(tl.r > 240 && tl.g < 16, "top-left of callout is red — got \(tl)")
        #expect(tr.g > 240 && tr.r < 16, "top-right of callout is green — got \(tr)")
        #expect(bl.b > 240 && bl.r < 16, "bottom-left of callout is blue — got \(bl)")
        #expect(br.r > 240 && br.g > 240 && br.b > 240, "bottom-right of callout is white — got \(br)")
    }

    @Test func calloutSeesLayersBeneathIt() {
        let store = ImageStore()
        let base = store.register(solidImage(width: 100, height: 100, r: 255, g: 0, b: 0))
        let patch = store.register(solidImage(width: 20, height: 20, r: 0, g: 0, b: 255))

        var doc = PhotonzDocument.withBaseImage(base)
        doc.canvasSize = CGSize(width: 200, height: 200)
        // Blue patch covering the source region, below the callout.
        doc.addLayer(Layer(name: "Patch", content: .image(patch),
                           frame: CGRect(x: 10, y: 10, width: 20, height: 20)))
        doc.addLayer(calloutLayer(source: CGRect(x: 10, y: 10, width: 20, height: 20),
                                  magnification: 2,
                                  frame: CGRect(x: 120, y: 120, width: 40, height: 40)))

        let output = DocumentRenderer().render(doc, store: store)!
        let p = pixel(output, x: 140, y: 140)
        #expect(p.b > 240 && p.r < 16, "callout magnifies the patch, not just the base — got \(p)")
    }

    @Test func calloutIgnoresLayersAboveIt() {
        let store = ImageStore()
        let base = store.register(solidImage(width: 100, height: 100, r: 255, g: 0, b: 0))
        let cover = store.register(solidImage(width: 20, height: 20, r: 0, g: 255, b: 0))

        var doc = PhotonzDocument.withBaseImage(base)
        doc.canvasSize = CGSize(width: 200, height: 200)
        doc.addLayer(calloutLayer(source: CGRect(x: 10, y: 10, width: 20, height: 20),
                                  magnification: 2,
                                  frame: CGRect(x: 120, y: 120, width: 40, height: 40)))
        // Green cover painted over the source region, but ABOVE the callout layer.
        doc.addLayer(Layer(name: "Cover", content: .image(cover),
                           frame: CGRect(x: 10, y: 10, width: 20, height: 20)))

        let output = DocumentRenderer().render(doc, store: store)!
        let p = pixel(output, x: 140, y: 140)
        #expect(p.r > 240 && p.g < 16, "callout shows the backdrop below it (red), not the cover above — got \(p)")
    }

    @Test func sourcePixelChangeReRendersInCallout() {
        // Liveness: same document, the layer under the source moves between renders.
        let store = ImageStore()
        let base = store.register(solidImage(width: 100, height: 100, r: 255, g: 0, b: 0))
        let patch = store.register(solidImage(width: 20, height: 20, r: 0, g: 0, b: 255))

        var doc = PhotonzDocument.withBaseImage(base)
        doc.canvasSize = CGSize(width: 200, height: 200)
        let patchLayer = Layer(name: "Patch", content: .image(patch),
                               frame: CGRect(x: 60, y: 60, width: 20, height: 20))
        doc.addLayer(patchLayer)
        doc.addLayer(calloutLayer(source: CGRect(x: 10, y: 10, width: 20, height: 20),
                                  magnification: 2,
                                  frame: CGRect(x: 120, y: 120, width: 40, height: 40)))

        let renderer = DocumentRenderer()
        let before = renderer.render(doc, store: store)!
        let beforePixel = pixel(before, x: 140, y: 140)
        #expect(beforePixel.r > 240, "patch is away from the source; callout shows red — got \(beforePixel)")

        // Move the patch under the source region; the callout must pick it up.
        doc.updateLayer(id: patchLayer.id) { $0.frame = CGRect(x: 10, y: 10, width: 20, height: 20) }
        let after = renderer.render(doc, store: store)!
        let afterPixel = pixel(after, x: 140, y: 140)
        #expect(afterPixel.b > 240 && afterPixel.r < 16,
                "callout re-renders the moved patch — got \(afterPixel)")
    }

    @Test func styleBorderAndCornerRadiusApply() {
        let store = ImageStore()
        let base = store.register(solidImage(width: 100, height: 100, r: 255, g: 0, b: 0))
        var doc = PhotonzDocument.withBaseImage(base)
        doc.canvasSize = CGSize(width: 200, height: 200)

        var style = LayerStyle()
        style.borderWidth = 4
        style.borderColorHex = "#00FF00"
        style.cornerRadius = 12
        doc.addLayer(calloutLayer(source: CGRect(x: 10, y: 10, width: 30, height: 30),
                                  magnification: 2,
                                  frame: CGRect(x: 120, y: 120, width: 60, height: 60),
                                  style: style))

        let output = DocumentRenderer().render(doc, store: store)!
        let edge = pixel(output, x: 150, y: 121)
        #expect(edge.g > 200 && edge.r < 64, "border strokes the callout edge — got \(edge)")
        let center = pixel(output, x: 150, y: 150)
        #expect(center.r > 240, "callout interior still shows magnified source — got \(center)")
        // Sample the bottom-right corner: the top-left one hosts the leader
        // lines' endpoint caps, which legitimately carry alpha.
        let corner = pixel(output, x: 179, y: 179)
        #expect(corner.a < 64, "corner radius clips the callout corner — got \(corner)")
    }

    @Test func sourceOutlineAndLeaderLinesCompositeOntoCanvas() {
        let store = ImageStore()
        let base = store.register(solidImage(width: 100, height: 100, r: 255, g: 0, b: 0))
        var doc = PhotonzDocument.withBaseImage(base)
        doc.canvasSize = CGSize(width: 200, height: 200)

        var style = LayerStyle()
        style.borderWidth = 2
        style.borderColorHex = "#00FF00"
        doc.addLayer(calloutLayer(source: CGRect(x: 10, y: 10, width: 20, height: 20),
                                  magnification: 2,
                                  frame: CGRect(x: 120, y: 120, width: 40, height: 40),
                                  style: style))

        let output = DocumentRenderer().render(doc, store: store)!
        // Source outline: top edge of the source box, over the red base.
        let outline = pixel(output, x: 20, y: 10)
        #expect(outline.g > 180 && outline.r < 80, "source box outlined in border color — got \(outline)")
        // Leader line: the diagonal (30,30)→(120,120) passes through (75,75).
        let leader = pixel(output, x: 75, y: 75)
        #expect(leader.g > 90, "leader line tints the canvas between boxes — got \(leader)")
    }

    @Test func circleShapeClipsBoxCorners() {
        let store = ImageStore()
        let base = store.register(solidImage(width: 100, height: 100, r: 255, g: 0, b: 0))
        var doc = PhotonzDocument.withBaseImage(base)
        doc.canvasSize = CGSize(width: 200, height: 200)

        doc.addLayer(calloutLayer(source: CGRect(x: 10, y: 10, width: 30, height: 30),
                                  magnification: 2,
                                  frame: CGRect(x: 120, y: 120, width: 60, height: 60),
                                  shape: .circle))

        let output = DocumentRenderer().render(doc, store: store)!
        let center = pixel(output, x: 150, y: 150)
        #expect(center.r > 240, "circle interior shows the magnified source — got \(center)")
        // All four box corners fall outside the inscribed circle.
        for (x, y) in [(123, 123), (177, 123), (123, 177), (177, 177)] {
            let corner = pixel(output, x: x, y: y)
            #expect(corner.a < 64, "circle clips the box corner (\(x),\(y)) — got \(corner)")
        }
    }

    @Test func circleShapeOutlinesSourceAsCircle() {
        let store = ImageStore()
        let base = store.register(solidImage(width: 100, height: 100, r: 255, g: 0, b: 0))
        var doc = PhotonzDocument.withBaseImage(base)
        doc.canvasSize = CGSize(width: 200, height: 200)

        var style = LayerStyle()
        style.borderWidth = 2
        style.borderColorHex = "#00FF00"
        doc.addLayer(calloutLayer(source: CGRect(x: 10, y: 10, width: 30, height: 30),
                                  magnification: 2,
                                  frame: CGRect(x: 120, y: 120, width: 60, height: 60),
                                  style: style, shape: .circle))

        let output = DocumentRenderer().render(doc, store: store)!
        // Top-center of the source box lies on the circle: stroked.
        let topCenter = pixel(output, x: 25, y: 10)
        #expect(topCenter.g > 180, "source circle stroked at its top — got \(topCenter)")
        // The box corner is off the circle: red base shows through.
        let corner = pixel(output, x: 11, y: 11)
        #expect(corner.r > 200 && corner.g < 100, "source corner left unstroked — got \(corner)")
    }

    @Test func sourceRectClampedToCanvasDoesNotCrash() {
        let store = ImageStore()
        let base = store.register(solidImage(width: 50, height: 50, r: 255, g: 0, b: 0))
        var doc = PhotonzDocument.withBaseImage(base)

        // Source hangs off the canvas edge; render must survive and stay sane.
        doc.addLayer(calloutLayer(source: CGRect(x: 40, y: 40, width: 30, height: 30),
                                  magnification: 2,
                                  frame: CGRect(x: 0, y: 0, width: 20, height: 20)))
        let output = DocumentRenderer().render(doc, store: store)
        #expect(output != nil)
    }

    @Test func emptySourceRectRendersNothing() {
        let store = ImageStore()
        let base = store.register(solidImage(width: 50, height: 50, r: 255, g: 0, b: 0))
        var doc = PhotonzDocument.withBaseImage(base)
        doc.addLayer(calloutLayer(source: CGRect(x: 10, y: 10, width: 0, height: 0),
                                  magnification: 2,
                                  frame: CGRect(x: 20, y: 20, width: 10, height: 10)))
        let output = DocumentRenderer().render(doc, store: store)
        #expect(output != nil, "degenerate callout is skipped, not fatal")
    }
}
