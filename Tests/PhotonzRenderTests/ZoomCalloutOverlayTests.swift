import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

@Suite("Zoom callout overlay")
struct ZoomCalloutOverlayTests {

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

    /// Samples the overlay at a canvas-space point.
    private func sample(_ overlay: (image: CGImage, origin: CGPoint),
                        canvasX: CGFloat, canvasY: CGFloat) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        pixel(overlay.image, x: Int(canvasX - overlay.origin.x), y: Int(canvasY - overlay.origin.y))
    }

    private var greenBorder: LayerStyle {
        var style = LayerStyle()
        style.borderWidth = 2
        style.borderColorHex = "#00FF00"
        return style
    }

    @Test func outlineStrokesSourceRect() {
        let overlay = ZoomCalloutOverlayRasterizer.rasterize(
            source: CGRect(x: 10, y: 10, width: 20, height: 20),
            callout: CGRect(x: 60, y: 10, width: 40, height: 40),
            style: greenBorder, magnification: 2)!

        // Stroke is centered on the source boundary; (20, 10) sits on the top edge.
        let edge = sample(overlay, canvasX: 20, canvasY: 10)
        #expect(edge.g > 200 && edge.a > 200, "source outline drawn in border color — got \(edge)")
        // The source interior stays clear so the magnified region isn't tinted.
        let interior = sample(overlay, canvasX: 20, canvasY: 20)
        #expect(interior.a < 16, "source interior is transparent — got \(interior)")
    }

    @Test func leaderLinesConnectSourceToCallout() {
        let overlay = ZoomCalloutOverlayRasterizer.rasterize(
            source: CGRect(x: 10, y: 10, width: 20, height: 20),
            callout: CGRect(x: 60, y: 10, width: 40, height: 40),
            style: greenBorder, magnification: 2)!

        // Geometry.leaderLines for these rects keeps (30,10)→(60,10) — a
        // horizontal segment. The stroke is thin (1pt) and straddles the pixel
        // grid, so scan the cross-section at its midpoint for the densest pixel.
        let onLeader = (8...12)
            .map { sample(overlay, canvasX: 45, canvasY: CGFloat($0)) }
            .max { $0.a < $1.a }!
        #expect(onLeader.a > 80 && onLeader.g > 80, "leader line drawn between the boxes — got \(onLeader)")
        // Well away from outline and leaders: clear.
        let offLeader = sample(overlay, canvasX: 45, canvasY: 45)
        #expect(offLeader.a < 16, "empty overlay space is transparent — got \(offLeader)")
    }

    @Test func originCoversStrokeOverhang() {
        let overlay = ZoomCalloutOverlayRasterizer.rasterize(
            source: CGRect(x: 10, y: 10, width: 20, height: 20),
            callout: CGRect(x: 60, y: 10, width: 40, height: 40),
            style: greenBorder, magnification: 2)!
        // The stroke straddles the source boundary, so the image must start
        // at or before source.minX - strokeWidth/2.
        #expect(overlay.origin.x <= 9 && overlay.origin.y <= 9)
        let canvasMaxX = overlay.origin.x + CGFloat(overlay.image.width)
        #expect(canvasMaxX >= 101, "image extends past the callout's right edge")
    }

    @Test func hairlineWhenStyleHasNoBorder() {
        var style = LayerStyle()
        style.borderColorHex = "#FF0000"
        style.borderWidth = 0
        let overlay = ZoomCalloutOverlayRasterizer.rasterize(
            source: CGRect(x: 10, y: 10, width: 20, height: 20),
            callout: CGRect(x: 60, y: 10, width: 40, height: 40),
            style: style, magnification: 2)
        // Border width 0 still yields a visible (1pt) source outline.
        #expect(overlay != nil)
        if let overlay {
            let edge = sample(overlay, canvasX: 20, canvasY: 10)
            #expect(edge.a > 80, "hairline outline still drawn — got \(edge)")
        }
    }

    @Test func opacityFadesOverlay() {
        var style = greenBorder
        style.opacity = 0.5
        let overlay = ZoomCalloutOverlayRasterizer.rasterize(
            source: CGRect(x: 10, y: 10, width: 20, height: 20),
            callout: CGRect(x: 60, y: 10, width: 40, height: 40),
            style: style, magnification: 2)!
        let edge = sample(overlay, canvasX: 20, canvasY: 10)
        #expect(edge.a > 80 && edge.a < 180, "outline alpha follows layer opacity — got \(edge)")
    }

    @Test func degenerateSourceReturnsNil() {
        let overlay = ZoomCalloutOverlayRasterizer.rasterize(
            source: CGRect(x: 10, y: 10, width: 0, height: 0),
            callout: CGRect(x: 60, y: 10, width: 40, height: 40),
            style: greenBorder, magnification: 2)
        #expect(overlay == nil)
    }
}
