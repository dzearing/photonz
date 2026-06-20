import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

@Suite("Annotation rendering")
struct AnnotationRenderingTests {

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

    /// White 100x100 base plus one full-canvas annotation layer.
    private func renderAnnotation(_ annotation: AnnotationContent,
                                  baseColor: (r: UInt8, g: UInt8, b: UInt8) = (255, 255, 255)) -> CGImage {
        let store = ImageStore()
        let base = store.register(solidImage(width: 100, height: 100,
                                             r: baseColor.r, g: baseColor.g, b: baseColor.b))
        var doc = PhotonzDocument.withBaseImage(base)
        doc.addLayer(Layer(name: "Annotation", content: .annotation(annotation),
                           frame: CGRect(x: 0, y: 0, width: 100, height: 100)))
        return DocumentRenderer().render(doc, store: store)!
    }

    private func isRed(_ p: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)) -> Bool {
        p.r > 200 && p.g < 80 && p.b < 80
    }

    private func isWhite(_ p: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)) -> Bool {
        p.r > 240 && p.g > 240 && p.b > 240
    }

    @Test func lineStrokesBetweenEndpoints() {
        let output = renderAnnotation(AnnotationContent(shape: .line, strokeWidth: 6, colorHex: "#FF0000",
                                                        start: CGPoint(x: 10, y: 50), end: CGPoint(x: 90, y: 50)))
        #expect(isRed(pixel(output, x: 50, y: 50)), "line midpoint should be stroked")
        #expect(isWhite(pixel(output, x: 50, y: 40)), "above the 6px line should be untouched")
        #expect(isWhite(pixel(output, x: 5, y: 50)), "before the start point should be untouched")
    }

    @Test func rectangleStrokesEdgesNotInterior() {
        let output = renderAnnotation(AnnotationContent(shape: .rectangle, strokeWidth: 4, colorHex: "#FF0000",
                                                        start: CGPoint(x: 20, y: 20), end: CGPoint(x: 80, y: 80)))
        #expect(isRed(pixel(output, x: 50, y: 21)), "top edge should be stroked")
        #expect(isRed(pixel(output, x: 21, y: 50)), "left edge should be stroked")
        #expect(isWhite(pixel(output, x: 50, y: 50)), "interior should stay empty")
        #expect(isWhite(pixel(output, x: 15, y: 50)), "outside the rect should stay empty")
        // The sharp corner is stroked when cornerRadius is 0.
        #expect(isRed(pixel(output, x: 21, y: 21)), "sharp rectangle strokes its corner")
    }

    @Test func roundedRectangleRoundsTheStrokeNotClipsItAway() {
        // The user's bug: rounding a rectangle made its border disappear at the
        // corners (a layer-level rounded clip ate the sharp stroke). With a
        // native corner radius the stroke follows the rounded corners: edges
        // stay stroked and the extreme corner is empty (rounded away), but the
        // border is NOT gone — it curves through the corner region.
        let output = renderAnnotation(AnnotationContent(shape: .rectangle, strokeWidth: 4, colorHex: "#FF0000",
                                                        start: CGPoint(x: 20, y: 20), end: CGPoint(x: 80, y: 80),
                                                        cornerRadius: 18))
        #expect(isRed(pixel(output, x: 50, y: 21)), "top edge still stroked after rounding")
        #expect(isRed(pixel(output, x: 21, y: 50)), "left edge still stroked after rounding")
        #expect(isWhite(pixel(output, x: 21, y: 21)), "the extreme corner is rounded away")
        // A point on the rounded corner arc (~45° in from the corner) is stroked,
        // proving the border curves through the corner rather than vanishing.
        #expect(isRed(pixel(output, x: 26, y: 26)), "the rounded corner arc is stroked")
        #expect(isWhite(pixel(output, x: 50, y: 50)), "interior stays empty")
    }

    @Test func ellipseStrokesPerimeterNotInterior() {
        let output = renderAnnotation(AnnotationContent(shape: .ellipse, strokeWidth: 4, colorHex: "#FF0000",
                                                        start: CGPoint(x: 20, y: 20), end: CGPoint(x: 80, y: 80)))
        #expect(isRed(pixel(output, x: 50, y: 22)), "top of the ellipse should be stroked")
        #expect(isRed(pixel(output, x: 22, y: 50)), "left of the ellipse should be stroked")
        #expect(isWhite(pixel(output, x: 50, y: 50)), "interior should stay empty")
        #expect(isWhite(pixel(output, x: 24, y: 24)), "the corner is outside the ellipse")
    }

    @Test func arrowHasHeadAtEndPoint() {
        let output = renderAnnotation(AnnotationContent(shape: .arrow, strokeWidth: 6, colorHex: "#FF0000",
                                                        start: CGPoint(x: 10, y: 50), end: CGPoint(x: 80, y: 50)))
        #expect(isRed(pixel(output, x: 40, y: 50)), "shaft should be stroked")
        // The bold head flares well wider than the 6px shaft near the end point:
        // with strokeWidth 6 the head spans x ~50...80 with half-width ~16.8, so
        // at x = 62 it comfortably covers y 44 and 56.
        #expect(isRed(pixel(output, x: 62, y: 44)), "upper wing of the arrowhead")
        #expect(isRed(pixel(output, x: 62, y: 56)), "lower wing of the arrowhead")
        #expect(isWhite(pixel(output, x: 40, y: 44)), "shaft should not flare mid-line")
        #expect(isWhite(pixel(output, x: 85, y: 50)), "nothing past the tip")
    }

    @Test func arrowheadScaleWidensTheRenderedHead() {
        // A bigger arrowheadScale must visibly widen the head: sample a point
        // off-axis near the tip that the small head misses but the big one fills.
        let small = renderAnnotation(AnnotationContent(shape: .arrow, strokeWidth: 4, colorHex: "#FF0000",
                                                       start: CGPoint(x: 10, y: 50), end: CGPoint(x: 80, y: 50),
                                                       arrowheadScale: 0.7))
        let big = renderAnnotation(AnnotationContent(shape: .arrow, strokeWidth: 4, colorHex: "#FF0000",
                                                     start: CGPoint(x: 10, y: 50), end: CGPoint(x: 80, y: 50),
                                                     arrowheadScale: 2.2))
        // x=40 is bare shaft for the small head (its head starts at ~x65) but
        // well inside the ×2.2 head (whose base reaches back to ~x32).
        #expect(isWhite(pixel(small, x: 40, y: 35)), "small arrowhead should not reach back to x=40")
        #expect(isRed(pixel(big, x: 40, y: 35)), "the ×2.2 arrowhead should cover (40, 35)")
    }

    @Test func highlightMultipliesInsteadOfCovering() {
        // Yellow highlight over a mid-gray base: multiply keeps r/g at base level
        // and crushes blue. An opaque cover would read pure yellow (r = 255).
        let output = renderAnnotation(AnnotationContent(shape: .highlight, strokeWidth: 0, colorHex: "#FFFF00",
                                                        start: CGPoint(x: 20, y: 20), end: CGPoint(x: 80, y: 80)),
                                      baseColor: (128, 128, 128))
        let inside = pixel(output, x: 50, y: 50)
        let outside = pixel(output, x: 10, y: 50)
        #expect(inside.r > 100 && inside.r < 160, "red channel should stay near the base value, not jump to 255")
        #expect(inside.g > 100 && inside.g < 160)
        #expect(inside.b < 40, "blue channel should be multiplied away")
        #expect(outside.r > 100 && outside.r < 160 && outside.b > 100, "outside the highlight the base is untouched")
    }

    @Test func highlightOverWhiteShowsItsColor() {
        let output = renderAnnotation(AnnotationContent(shape: .highlight, strokeWidth: 0, colorHex: "#FFFF00",
                                                        start: CGPoint(x: 20, y: 20), end: CGPoint(x: 80, y: 80)))
        let inside = pixel(output, x: 50, y: 50)
        #expect(inside.r > 240 && inside.g > 240 && inside.b < 40, "yellow over white reads yellow")
    }
}
