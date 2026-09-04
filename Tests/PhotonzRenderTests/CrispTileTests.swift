import CoreGraphics
import CoreImage
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// A zoomed-in canvas asks for a tile: the same picture with the pixels the
/// zoom is about to spend, so placed words stay as sharp as the draft.
@Suite("Crisp tile")
struct CrispTileTests {

    private func pixels(_ image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    /// Share of pixels at an in-between luminance: how smeared the edges are.
    private func softness(_ image: CGImage) -> Double {
        let data = pixels(image)
        var mid = 0
        for i in stride(from: 0, to: data.count, by: 4) {
            let l = Double(data[i]) * 0.3 + Double(data[i + 1]) * 0.59 + Double(data[i + 2]) * 0.11
            if l > 40 && l < 215 { mid += 1 }
        }
        return Double(mid) / Double(image.width * image.height)
    }

    /// Share of neighbouring pixel pairs that swing hard from one to the next.
    /// A sharp edge makes that jump in a single step; a picture blown up four
    /// times spreads the same jump over four gentle ones, so this collapses.
    private func hardEdges(_ image: CGImage) -> Double {
        let data = pixels(image)
        let w = image.width, h = image.height
        var hard = 0
        for y in 0..<h {
            for x in 1..<w {
                let i = (y * w + x) * 4, j = (y * w + x - 1) * 4
                let a = Double(data[i]) * 0.3 + Double(data[i + 1]) * 0.59 + Double(data[i + 2]) * 0.11
                let b = Double(data[j]) * 0.3 + Double(data[j + 1]) * 0.59 + Double(data[j + 2]) * 0.11
                if abs(a - b) > 90 { hard += 1 }
            }
        }
        return Double(hard) / Double(h * (w - 1))
    }

    private func labelDocument() -> PhotonzDocument {
        var text = TextContent(string: "Padding 16", fontSize: 18)
        text.colorHex = "#101014"
        let size = TextRasterizer.naturalSize(text)
        let layer = Layer(name: "Label", content: .text(text),
                          frame: CGRect(x: 20, y: 20, width: size.width, height: size.height))
        return PhotonzDocument(canvasSize: CGSize(width: 400, height: 200), layers: [layer])
    }

    @Test func aTileAtOneToOneIsTheCompositeItself() throws {
        let doc = labelDocument()
        let store = ImageStore()
        let renderer = DocumentRenderer()
        let full = try #require(renderer.render(doc, store: store))
        let tile = try #require(renderer.renderTile(doc, store: store,
                                                    region: CGRect(origin: .zero, size: doc.canvasSize),
                                                    scale: 1))
        #expect(tile.image.width == full.width)
        #expect(tile.image.height == full.height)
        #expect(tile.region == CGRect(origin: .zero, size: doc.canvasSize))
        #expect(pixels(tile.image) == pixels(full))
    }

    @Test func askingForMorePixelsGetsThem() throws {
        let doc = labelDocument()
        let tile = try #require(DocumentRenderer().renderTile(
            doc, store: ImageStore(),
            region: CGRect(x: 0, y: 0, width: 200, height: 100), scale: 3))
        #expect(tile.image.width == 600)
        #expect(tile.image.height == 300)
        #expect(tile.region == CGRect(x: 0, y: 0, width: 200, height: 100))
        #expect(tile.scale == 3)
    }

    @Test func placedWordsStaySharpWhereBlowingThemUpWouldNot() throws {
        let doc = labelDocument()
        let store = ImageStore()
        let renderer = DocumentRenderer()
        let region = CGRect(x: 10, y: 10, width: 200, height: 60)

        let crisp = try #require(renderer.renderTile(doc, store: store, region: region, scale: 4))

        // What the canvas shows today: the document-sized composite stretched.
        let full = try #require(renderer.render(doc, store: store))
        let cut = try #require(full.cropping(to: region))
        let blown = CIImage(cgImage: cut).transformed(by: CGAffineTransform(scaleX: 4, y: 4))
        let soft = try #require(CIContext().createCGImage(blown, from: blown.extent))

        #expect(softness(crisp.image) < softness(soft) / 2)
    }

    @Test func aTileOnlyCoversTheCanvas() throws {
        let doc = labelDocument()
        let tile = try #require(DocumentRenderer().renderTile(
            doc, store: ImageStore(),
            region: CGRect(x: 300, y: 150, width: 400, height: 400), scale: 2))
        #expect(tile.region == CGRect(x: 300, y: 150, width: 100, height: 50))
        #expect(tile.image.width == 200)
        #expect(tile.image.height == 100)
    }

    @Test func nothingToShowDrawsNothing() {
        let doc = labelDocument()
        let renderer = DocumentRenderer()
        let store = ImageStore()
        #expect(renderer.renderTile(doc, store: store,
                                    region: CGRect(x: 900, y: 900, width: 50, height: 50),
                                    scale: 2) == nil)
        #expect(renderer.renderTile(doc, store: store,
                                    region: CGRect(origin: .zero, size: doc.canvasSize),
                                    scale: 0) == nil)
    }

    /// A label sitting inside a frame with its own background and rounded
    /// corners gets the same treatment: nothing about being inside a group
    /// sends it back to the soft path.
    @Test func aLabelInsideAFrameIsSharpToo() throws {
        var text = TextContent(string: "Continue", fontSize: 15)
        text.colorHex = "#FFFFFF"
        let size = TextRasterizer.naturalSize(text)
        let label = Layer(name: "Label", content: .text(text),
                          frame: CGRect(x: 12, y: 8, width: size.width, height: size.height))
        var group = GroupContent(children: [label])
        group.isFrame = true
        group.backgroundHex = "#2255CC"
        var button = Layer(name: "Button", content: .group(group),
                           frame: CGRect(x: 30, y: 30, width: size.width + 24, height: size.height + 16))
        button.style.cornerRadius = 8
        let doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 200), layers: [button])

        let renderer = DocumentRenderer()
        let store = ImageStore()
        let region = CGRect(x: 20, y: 20, width: 200, height: 80)
        let crisp = try #require(renderer.renderTile(doc, store: store, region: region, scale: 4))
        let full = try #require(renderer.render(doc, store: store))
        let cut = try #require(full.cropping(to: region))
        let blown = CIImage(cgImage: cut).transformed(by: CGAffineTransform(scaleX: 4, y: 4))
        let soft = try #require(CIContext().createCGImage(blown, from: blown.extent))
        // A blue button is not dark-on-white, so judge it by how hard its
        // edges and its white label swing from pixel to pixel.
        #expect(hardEdges(crisp.image) > hardEdges(soft) * 2)
    }

    /// How much sharper a tile is than the same patch of the composite blown
    /// up: the ratio the crisp path exists to move.
    private func sharpening(_ doc: PhotonzDocument, region: CGRect, scale: CGFloat,
                            store: ImageStore = ImageStore()) throws -> Double {
        let renderer = DocumentRenderer()
        let crisp = try #require(renderer.renderTile(doc, store: store, region: region, scale: scale))
        let full = try #require(renderer.render(doc, store: store))
        let cut = try #require(full.cropping(to: region))
        let blown = CIImage(cgImage: cut).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let soft = try #require(CIContext().createCGImage(blown, from: blown.extent))
        return hardEdges(crisp.image) / max(hardEdges(soft), 0.000001)
    }

    /// The number on a measurement is the thing a redliner zooms in to READ,
    /// so it is the last thing that should go soft when they do.
    @Test func aMeasurementChipStaysSharpWhenYouZoomIn() throws {
        let content = MeasureContent(start: .zero, end: CGPoint(x: 160, y: 0), mode: .horizontal)
        let caliper = MeasureBuilder.layer(content: content,
                                           from: CGPoint(x: 60, y: 120), to: CGPoint(x: 220, y: 120))
        let doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 200), layers: [caliper])
        #expect(try sharpening(doc, region: caliper.frame.insetBy(dx: -4, dy: -4), scale: 4) > 2)
    }

    /// And so is the caption you hung off an arrow to say what it points at.
    @Test func anArrowCaptionStaysSharpWhenYouZoomIn() throws {
        var content = AnnotationContent(shape: .arrow, strokeWidth: 4, colorHex: "#FF3B30")
        content.caption = "Save"
        let arrow = AnnotationBuilder.layer(content: content,
                                            from: CGPoint(x: 260, y: 90), to: CGPoint(x: 100, y: 90))
        let doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 200), layers: [arrow])
        #expect(try sharpening(doc, region: arrow.frame.insetBy(dx: -4, dy: -4), scale: 4) > 2)
    }

    /// A shape's own stroke comes from geometry too, so it can be drawn at the
    /// zoom's resolution rather than blown up to it.
    @Test func aShapeStrokeStaysSharpWhenYouZoomIn() throws {
        let doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 200),
                                  layers: [strokedBox()])
        let region = strokedBox().frame.insetBy(dx: -4, dy: -4)
        #expect(try sharpening(doc, region: region, scale: 4) > 2)
    }

    /// The border the layer's STYLE draws is a different thing from the shape's
    /// own stroke: Core Image draws it around the already-magnified box, so it
    /// was sharp before this and has to stay sharp after it.
    @Test func aLayerBorderStaysSharpWhenYouZoomIn() throws {
        var box = strokedBox()
        box.style.borderWidth = 2
        box.style.borderColorHex = "#101014"
        let doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 200), layers: [box])
        #expect(try sharpening(doc, region: box.frame.insetBy(dx: -4, dy: -4), scale: 4) > 2)
    }

    private func strokedBox() -> Layer {
        var content = AnnotationContent(shape: .rectangle, strokeWidth: 3, colorHex: "#34C759")
        content.cornerRadius = 6
        return AnnotationBuilder.layer(content: content,
                                       from: CGPoint(x: 40, y: 40), to: CGPoint(x: 240, y: 140))
    }

    /// A shape so big it fills the canvas would ask for a bitmap tens of times
    /// the size of the document. It falls back to the way it draws today rather
    /// than spending that, and the tile still comes back.
    @Test func aCanvasSizedShapeDoesNotAskForAnEnormousRaster() throws {
        let content = AnnotationContent(shape: .arrow, strokeWidth: 16, colorHex: "#FF3B30",
                                        start: CGPoint(x: 100, y: 100),
                                        end: CGPoint(x: 3800, y: 2800))
        let arrow = Layer(name: "Arrow", content: .annotation(content),
                          frame: CGRect(x: 0, y: 0, width: 4000, height: 3000))
        let doc = PhotonzDocument(canvasSize: CGSize(width: 4000, height: 3000), layers: [arrow])
        let tile = try #require(DocumentRenderer().renderTile(
            doc, store: ImageStore(),
            region: CGRect(x: 500, y: 400, width: 200, height: 150), scale: 8))
        #expect(tile.image.width == 1600)
        #expect(tile.image.height == 1200)
    }
}
