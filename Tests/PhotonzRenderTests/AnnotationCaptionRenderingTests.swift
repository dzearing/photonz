import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

@Suite("Annotation caption rendering")
struct AnnotationCaptionRenderingTests {

    /// A leftward arrow (head at the left), so the caption pill hangs off the
    /// tail on the right. Built through the real builder so frame reservation
    /// and layer-local coordinates match production.
    private func captionedLayer(caption: String? = "Save") -> Layer {
        var content = AnnotationContent(shape: .arrow, strokeWidth: 4, colorHex: "#FF3B30")
        content.caption = caption
        return AnnotationBuilder.layer(content: content,
                                       from: CGPoint(x: 220, y: 80), to: CGPoint(x: 60, y: 80))
    }

    private func pixels(_ image: CGImage) -> (data: [UInt8], width: Int, height: Int) {
        let width = image.width
        let height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &data, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (data, width, height)
    }

    private func sample(_ px: (data: [UInt8], width: Int, height: Int),
                        x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let i = (y * px.width + x) * 4
        return (px.data[i], px.data[i + 1], px.data[i + 2], px.data[i + 3])
    }

    /// The pill's real (rasterizer-measured) chip size for a content's caption.
    private func realChipSize(_ content: AnnotationContent) -> CGSize {
        let text = TextContent(string: content.caption ?? "", fontName: "SF Pro",
                               fontSize: content.captionFontSize)
        let size = TextRasterizer.naturalSize(text)
        return CGSize(width: size.width + 2 * content.captionPadding,
                      height: size.height + 2 * content.captionPadding)
    }

    @Test func captionDrawsAChipTonePillAtTheAnchor() {
        let layer = captionedLayer()
        guard let content = layer.annotation,
              let image = AnnotationRasterizer.rasterize(content, size: layer.frame.size) else {
            Issue.record("expected a rasterized captioned arrow")
            return
        }
        let anchor = content.captionAnchor()
        let chip = realChipSize(content)
        let px = pixels(image)
        // The padding band between the pill's top edge and the glyph ascenders
        // is pure fill: the dark red chip tone (#8C201A at 0.92 alpha).
        let p = sample(px, x: Int(anchor.x), y: Int(anchor.y - chip.height / 2) + 4)
        #expect(p.a > 200)
        #expect(p.r > 100 && p.r < 160)
        #expect(p.g < 60)
        #expect(p.b < 60)
    }

    @Test func captionTextRendersInsideThePill() {
        let layer = captionedLayer()
        guard let content = layer.annotation,
              let image = AnnotationRasterizer.rasterize(content, size: layer.frame.size) else {
            Issue.record("expected a rasterized captioned arrow")
            return
        }
        let anchor = content.captionAnchor()
        let chip = realChipSize(content)
        let px = pixels(image)
        var lightPixels = 0
        for y in Int(anchor.y - chip.height / 2)...Int(anchor.y + chip.height / 2) {
            for x in Int(anchor.x - chip.width / 2)...Int(anchor.x + chip.width / 2) {
                let p = sample(px, x: x, y: y)
                if p.r > 180, p.g > 180, p.b > 180 { lightPixels += 1 }
            }
        }
        #expect(lightPixels > 10)
    }

    @Test func pillCastsAShadowBelowItself() {
        let layer = captionedLayer()
        guard let content = layer.annotation,
              let image = AnnotationRasterizer.rasterize(content, size: layer.frame.size) else {
            Issue.record("expected a rasterized captioned arrow")
            return
        }
        let anchor = content.captionAnchor()
        let chip = realChipSize(content)
        let px = pixels(image)
        // Alpha in a band below the pill (past the border stroke) should beat
        // the mirror band above it: the shadow offsets downward.
        func bandAlpha(fromY: Int, toY: Int) -> Int {
            var total = 0
            for y in fromY...toY {
                for x in Int(anchor.x - chip.width / 4)...Int(anchor.x + chip.width / 4) {
                    total += Int(sample(px, x: x, y: y).a)
                }
            }
            return total
        }
        let top = Int(anchor.y - chip.height / 2)
        let bottom = Int(anchor.y + chip.height / 2)
        let below = bandAlpha(fromY: bottom + 5, toY: bottom + 9)
        let above = bandAlpha(fromY: top - 9, toY: top - 5)
        #expect(below > above)
        #expect(below > 0)
    }

    @Test func captionlessArrowDrawsNothingAtTheAnchor() {
        var content = AnnotationContent(shape: .arrow, strokeWidth: 4, colorHex: "#FF3B30")
        content.caption = nil
        let layer = AnnotationBuilder.layer(content: content,
                                            from: CGPoint(x: 220, y: 80), to: CGPoint(x: 60, y: 80))
        guard let raster = layer.annotation,
              let image = AnnotationRasterizer.rasterize(raster, size: layer.frame.size) else {
            Issue.record("expected a rasterized arrow")
            return
        }
        // The tail-side edge of the frame stays empty: no pill, no shadow.
        let px = pixels(image)
        let p = sample(px, x: px.width - 3, y: px.height / 2)
        #expect(p.a == 0)
    }
}
