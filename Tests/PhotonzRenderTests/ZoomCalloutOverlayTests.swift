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

    /// A lens switched to Magnify in the panel must draw a magnifier a person
    /// can SEE. A lens wears no ring, and this overlay is drawn entirely in the
    /// ring's colour and weight, so without the ring `LensConversion` now hands
    /// it, the outline and the leader lines come out a one-point black hairline.
    /// Drawn end to end here rather than trusted: the conversion's style, fed to
    /// the rasterizer that actually paints it.
    @Test func aLensSwitchedToMagnifyDrawsAnOutlineYouCanSee() throws {
        let lens = Layer(name: "Blur", content: .lens(LensContent(adjustment: .blur)),
                         frame: CGRect(x: 10, y: 10, width: 20, height: 20),
                         style: LensBuilder.defaultStyle)
        let magnifier = LensConversion.layer(lens, becoming: .magnify,
                                             canvas: CGSize(width: 200, height: 200))
        let callout = try #require(magnifier.zoomCallout)
        let overlay = try #require(ZoomCalloutOverlayRasterizer.rasterize(
            source: callout.sourceRect, callout: magnifier.frame,
            style: magnifier.style, magnification: callout.magnification,
            shape: callout.shape))

        // The callout red (#FF3B30) on the source's top edge, not black.
        let edge = sample(overlay, canvasX: 20, canvasY: 10)
        #expect(edge.r > 200 && edge.g < 120 && edge.a > 200,
                "source outline drawn in the callout's own red — got \(edge)")
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

    // MARK: The band between the leader lines

    /// Source (10…30, 40…60) left of a box (100…180, 0…100): the leader lines
    /// run from the source's right corners to the box's left corners, so the
    /// band is the trapezoid between them.
    private func banded(_ fill: CGFloat, shape: ZoomCalloutShape = .rectangle,
                        style: LayerStyle? = nil) -> (image: CGImage, origin: CGPoint)? {
        ZoomCalloutOverlayRasterizer.rasterize(
            source: CGRect(x: 10, y: 40, width: 20, height: 20),
            callout: CGRect(x: 100, y: 0, width: 80, height: 100),
            style: style ?? greenBorder, magnification: 4, shape: shape, fillOpacity: fill)
    }

    @Test func theBandIsTheLineColourAtItsFillOpacity() throws {
        let overlay = try #require(banded(0.1))
        let inside = sample(overlay, canvasX: 65, canvasY: 50)
        // Premultiplied: green at a tenth is 0.1 alpha with 0.1 green.
        #expect(abs(Int(inside.a) - 26) <= 2, "band alpha is a tenth — got \(inside)")
        #expect(abs(Int(inside.g) - 26) <= 2 && inside.r < 3 && inside.b < 3,
                "band is the line colour — got \(inside)")
        // Outside the two lines: nothing.
        let above = sample(overlay, canvasX: 65, canvasY: 15)
        #expect(above.a == 0, "nothing outside the lines — got \(above)")
    }

    @Test func theBandFollowsLayerOpacityToo() throws {
        var style = greenBorder
        style.opacity = 0.5
        let overlay = try #require(banded(0.4, style: style))
        let inside = sample(overlay, canvasX: 65, canvasY: 50)
        #expect(abs(Int(inside.a) - 51) <= 2, "a fifth: 0.4 fill on a half-faded layer — got \(inside)")
    }

    @Test func noneDrawsNoBand() throws {
        let overlay = try #require(banded(0))
        #expect(sample(overlay, canvasX: 65, canvasY: 50).a == 0)
    }

    /// The band never tints either picture: the source region and the box are
    /// cut out of it.
    @Test func theBandStopsAtBothShapes() throws {
        let overlay = try #require(banded(0.5))
        #expect(sample(overlay, canvasX: 20, canvasY: 50).a == 0, "source interior untinted")
        #expect(sample(overlay, canvasX: 104, canvasY: 50).a == 0, "box interior untinted")
        // A circle callout's band stops at the round edges too.
        let round = try #require(banded(0.5, shape: .circle))
        #expect(sample(round, canvasX: 20, canvasY: 50).a == 0, "round source untinted")
        #expect(sample(round, canvasX: 104, canvasY: 50).a == 0, "round box untinted")
        #expect(sample(round, canvasX: 65, canvasY: 50).a > 100, "round band drawn between them")
    }

    /// MEASURED: walking out from the middle of the band, square to a leader
    /// line, the tint stops within a pixel of where that line is.
    @Test func theBandsEdgeSitsOnTheLeaderLine() throws {
        var style = greenBorder
        style.borderWidth = 0.001   // a hairline, so the line itself barely paints
        for shape in [ZoomCalloutShape.rectangle, .circle] {
            let overlay = try #require(ZoomCalloutOverlayRasterizer.rasterize(
                source: CGRect(x: 10, y: 40, width: 20, height: 20),
                callout: CGRect(x: 100, y: 0, width: 100, height: 100),
                style: style, magnification: 5, shape: shape, fillOpacity: 0.5))
            let lines = Geometry.leaderLines(source: CGRect(x: 10, y: 40, width: 20, height: 20),
                                             calloutCorners: Geometry.corners(of: CGRect(x: 100, y: 0, width: 100, height: 100)),
                                             shape: shape)
            try #require(lines.count == 2)
            for line in lines {
                let mid = CGPoint(x: (line.from.x + line.to.x) / 2, y: (line.from.y + line.to.y) / 2)
                let dx = line.to.x - line.from.x, dy = line.to.y - line.from.y
                let length = hypot(dx, dy)
                // Normal pointing into the band (toward y = 50).
                var n = CGVector(dx: -dy / length, dy: dx / length)
                if (50 - mid.y) * n.dy < 0 { n = CGVector(dx: -n.dx, dy: -n.dy) }
                // Ten points in: band. Then walk out until the band stops,
                // ignoring the line's own ink, which is more opaque.
                let deep = sample(overlay, canvasX: mid.x + n.dx * 10, canvasY: mid.y + n.dy * 10)
                #expect(abs(Int(deep.a) - 128) <= 3, "\(shape) band at half — got \(deep)")
                var last: CGFloat = 10
                var t: CGFloat = 10
                while t > -6 {
                    let p = sample(overlay, canvasX: mid.x + n.dx * t, canvasY: mid.y + n.dy * t)
                    if p.a < 64 { break }
                    last = t
                    t -= 0.25
                }
                #expect(abs(last) <= 1.0, "\(shape) band's edge within a pixel of its line — stopped at \(last)")
            }
        }
    }
}
