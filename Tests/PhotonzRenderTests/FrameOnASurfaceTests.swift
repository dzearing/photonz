import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import PhotonzCore
@testable import PhotonzRender
import Testing

/// A frame of a recording the canvas is shown is drawn onto a GPU surface and
/// kept there (`FrameOnASurface`), rather than read back into a bitmap that
/// every composite then uploads to the GPU again. On the 6 minute reference
/// edit those two copies were three quarters of every composite's time on the
/// render thread (2026-11-18). The surface has to draw exactly the picture the
/// bitmap drew: same pixels, same way up, same colours.
@Suite("A recording's frame kept on a surface")
struct FrameOnASurfaceTests {

    static let size = CGSize(width: 320, height: 200)
    static let displayP3 = CGColorSpace(name: CGColorSpace.displayP3)!

    /// A picture with a different colour in every corner, sitting off the
    /// origin the way a turned or shrunk frame does.
    static func scene(at origin: CGPoint = CGPoint(x: 7, y: 11)) -> CIImage {
        let gradient = CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: origin.x, y: origin.y),
            "inputPoint1": CIVector(x: origin.x + size.width, y: origin.y + size.height),
            "inputColor0": CIColor(red: 0.9, green: 0.2, blue: 0.1),
            "inputColor1": CIColor(red: 0.1, green: 0.3, blue: 0.95),
        ])?.outputImage ?? CIImage(color: .red)
        // A light band across the top, so the way up shows.
        let band = CIImage(color: CIColor(red: 0.2, green: 0.95, blue: 0.3))
            .cropped(to: CGRect(x: origin.x, y: origin.y + size.height - 40, width: size.width, height: 40))
        return band.composited(over: gradient).cropped(to: CGRect(origin: origin, size: size))
    }

    static func document(_ ref: ImageRef) -> PhotonzDocument {
        var doc = PhotonzDocument(canvasSize: size)
        doc.layers = [Layer(name: "Clip", content: .image(ref), frame: CGRect(origin: .zero, size: size))]
        return doc
    }

    /// RGBA bytes of a CGImage drawn into an sRGB bitmap: what anything that
    /// reads the picture's pixels sees.
    static func bytes(_ image: CGImage) -> [UInt8] {
        let width = image.width, height = image.height
        var out = [UInt8](repeating: 0, count: width * height * 4)
        out.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return out
    }

    static func largestDifference(_ a: [UInt8], _ b: [UInt8]) -> Int {
        guard a.count == b.count else { return 255 }
        var worst = 0
        for i in a.indices where i % 4 != 3 { worst = max(worst, abs(Int(a[i]) - Int(b[i]))) }
        return worst
    }

    @Test("The picture made on a surface is the one read back would be, in the colours asked for")
    func thePictureIsTheSame() throws {
        let context = CIContext(options: [.cacheIntermediates: false])
        let image = Self.scene()
        let extent = image.extent.integral
        let old = try #require(context.createCGImage(image, from: extent, format: .RGBA8,
                                                     colorSpace: Self.displayP3))
        let new = try #require(FrameOnASurface.draw(image, from: extent, colorSpace: Self.displayP3,
                                                    context: context))
        #expect(new.image.width == Int(Self.size.width) && new.image.height == Int(Self.size.height))
        #expect(CVPixelBufferGetWidth(new.surface) == new.image.width)
        #expect(CVPixelBufferGetHeight(new.surface) == new.image.height)
        #expect(new.image.colorSpace?.name == Self.displayP3.name)
        #expect(Self.largestDifference(Self.bytes(old), Self.bytes(new.image)) <= 1)
        // The right way up: the light green band is along the top.
        let drawn = Self.bytes(new.image)
        let topGreen: Int = Int(drawn[(10 * 320 + 160) * 4 + 1])
        let bottomGreen: Int = Int(drawn[(190 * 320 + 160) * 4 + 1])
        #expect(topGreen > 200 && bottomGreen < 150, "top \(topGreen), bottom \(bottomGreen)")
    }

    @Test("A frame read off its surface composites exactly as its read-back picture did")
    func itCompositesTheSame() throws {
        let context = CIContext(options: [.cacheIntermediates: false])
        let image = Self.scene()
        let extent = image.extent.integral
        let old = try #require(context.createCGImage(image, from: extent, format: .RGBA8,
                                                     colorSpace: Self.displayP3))
        let new = try #require(FrameOnASurface.draw(image, from: extent, colorSpace: Self.displayP3,
                                                    context: context))
        let ref = ImageRef(pixelSize: Self.size)
        let doc = Self.document(ref)
        let plain = ImageStore()
        plain.register(old, as: ref)
        let onSurface = ImageStore()
        onSurface.register(new.image, as: ref, surface: new.surface)
        #expect(onSurface.surface(for: ref, standingFor: new.image) === new.surface)

        // The canvas's composite, in the window's colours, and an export's.
        let space = Self.displayP3
        let before = try #require(DocumentRenderer().renderInteractive(doc, store: plain, colorSpace: space))
        let after = try #require(DocumentRenderer().renderInteractive(doc, store: onSurface, colorSpace: space))
        #expect(Self.largestDifference(Self.bytes(before), Self.bytes(after)) <= 1)
        let exportedBefore = try #require(DocumentRenderer().render(doc, store: plain))
        let exportedAfter = try #require(DocumentRenderer().render(doc, store: onSurface))
        #expect(Self.largestDifference(Self.bytes(exportedBefore), Self.bytes(exportedAfter)) <= 1)
    }

    @Test("Every frame gets a surface of its own, so a frame already shown is never drawn over")
    func everyFrameHasItsOwnSurface() throws {
        let context = CIContext(options: [.cacheIntermediates: false])
        let first = try #require(FrameOnASurface.draw(CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8)),
                                                      from: CGRect(x: 0, y: 0, width: 8, height: 8),
                                                      colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, context: context))
        let second = try #require(FrameOnASurface.draw(CIImage(color: .blue).cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8)),
                                                       from: CGRect(x: 0, y: 0, width: 8, height: 8),
                                                       colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, context: context))
        #expect(first.surface !== second.surface)
        let red = Self.bytes(first.image), blue = Self.bytes(second.image)
        #expect(red[0] > 200 && red[2] < 50, "\(red.prefix(4))")
        #expect(blue[2] > 200 && blue[0] < 50, "\(blue.prefix(4))")
    }

    @Test("Nothing to draw makes no surface")
    func nothingToDraw() {
        let context = CIContext(options: [.cacheIntermediates: false])
        #expect(FrameOnASurface.draw(CIImage.empty(), from: .zero,
                                     colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, context: context) == nil)
    }

    /// A picture with soft see-through edges, the way a shape's or a title's
    /// raster is.
    static func seeThrough(width: Int, height: Int) -> CGImage? {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(srgbRed: 0.9, green: 0.3, blue: 0.1, alpha: 0.6))
        context.fillEllipse(in: CGRect(x: 4, y: 6, width: width - 10, height: height - 14))
        context.setFillColor(CGColor(srgbRed: 0.1, green: 0.8, blue: 0.4, alpha: 1))
        context.fill(CGRect(x: 0, y: height - 12, width: width / 2, height: 12))
        return context.makeImage()
    }

    @Test("A raster kept on a surface draws exactly as its bitmap did, see-through edges and all")
    func aRasterKeptOnASurfaceDrawsTheSame() throws {
        let cg = try #require(Self.seeThrough(width: 300, height: 180))
        let kept = try #require(FrameOnASurface.keep(cg))
        #expect(kept.extent == CGRect(x: 0, y: 0, width: 300, height: 180))
        let context = CIContext(options: [.cacheIntermediates: false])
        let under = CIImage(color: CIColor(red: 0.1, green: 0.2, blue: 0.9)).cropped(to: kept.extent)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let before = try #require(context.createCGImage(CIImage(cgImage: cg).composited(over: under),
                                                        from: kept.extent, format: .RGBA8, colorSpace: space))
        let after = try #require(context.createCGImage(kept.composited(over: under),
                                                       from: kept.extent, format: .RGBA8, colorSpace: space))
        #expect(Self.largestDifference(Self.bytes(before), Self.bytes(after)) == 0)
        // On its own, too: the see-through pixels stay see-through.
        let alone = try #require(context.createCGImage(kept, from: kept.extent, format: .RGBA8, colorSpace: space))
        #expect(Self.largestDifference(Self.bytes(cg), Self.bytes(alone)) == 0)
        let corner = Self.bytes(alone)[(179 * 300 + 299) * 4 + 3]
        #expect(corner == 0)
    }

    @Test("A picture that is not plain 8 bit colour is not kept on a surface")
    func onlyPlainColourIsKept() throws {
        let gray = try #require(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue)?.makeImage())
        #expect(FrameOnASurface.keep(gray) == nil)
    }

    @Test("A moving background and a title draw the same whether their rasters are kept on a surface or not")
    func theRendererDrawsTheSame() throws {
        // The reference edit's background: a full-frame live gradient, whose
        // mask is a raster far past the size kept on a surface, under a
        // rounded, bordered box with words in it.
        let size = CGSize(width: 1280, height: 800)
        var fill = Paint(hex: "#14123A", kind: .live,
                         stops: [GradientStop(hex: "#14123A", position: 0),
                                 GradientStop(hex: "#3B2C8F", position: 0.5),
                                 GradientStop(hex: "#0E5A7A", position: 1)],
                         live: LiveBackdrop(look: .liquidGradient, speed: 60))
        fill.drift = 0
        var ground = AnnotationContent(shape: .rectangle, strokeWidth: 0, colorHex: fill.hex,
                                       start: .zero, end: CGPoint(x: size.width, y: size.height))
        ground.fill = fill
        var background = Layer(name: "Moving Background", content: .annotation(ground),
                               frame: CGRect(origin: .zero, size: size))
        background.time = LayerTime(inMS: 0, outMS: 10_000, sourceInMS: 0)
        var card = AnnotationContent(shape: .rectangle, strokeWidth: 6, colorHex: "#FFFFFF",
                                     start: .zero, end: CGPoint(x: 900, y: 500))
        card.fill = Paint(hex: "#FF8800CC")
        var box = Layer(name: "Card", content: .annotation(card), frame: CGRect(x: 160, y: 120, width: 900, height: 500))
        box.style.cornerRadius = 40
        box.time = LayerTime(inMS: 0, outMS: 10_000, sourceInMS: 0)
        var words = Layer(name: "Title", content: .text(TextContent(string: "Long edits stay fast", fontSize: 96)),
                          frame: CGRect(x: 200, y: 300, width: 860, height: 140))
        words.time = LayerTime(inMS: 0, outMS: 10_000, sourceInMS: 0)
        var doc = PhotonzDocument(canvasSize: size, layers: [background, box, words])
        doc.durationMS = 10_000

        let kept = DocumentRenderer()
        let plain = DocumentRenderer()
        plain.keepsBigRastersOnASurface = false
        for ms in [0, 1_500, 4_000] {
            let moment = doc.drawn(atTimeMS: ms)
            // Twice each, so the second is drawn from the rasters kept.
            for _ in 0..<2 {
                let a = try #require(kept.render(moment, store: ImageStore()))
                let b = try #require(plain.render(moment, store: ImageStore()))
                #expect(Self.largestDifference(Self.bytes(a), Self.bytes(b)) == 0, "at \(ms) ms")
                let c = try #require(kept.renderInteractive(moment, store: ImageStore()))
                let d = try #require(plain.renderInteractive(moment, store: ImageStore()))
                #expect(Self.largestDifference(Self.bytes(c), Self.bytes(d)) == 0, "at \(ms) ms, on the canvas")
            }
        }
    }
}
