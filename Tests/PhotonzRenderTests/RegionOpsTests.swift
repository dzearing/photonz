import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

@Suite("Region ops (fill/erase/extract)")
struct RegionOpsTests {

    /// A solid-color image (top-left coordinate probes below).
    private func image(width: Int, height: Int, color: CGColor) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(color)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// RGBA at (x, y) in TOP-LEFT coordinates, un-premultiplied 0–255.
    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        var buf = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &buf, width: 1, height: 1,
                                bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // Draw so the wanted pixel lands in the 1×1 context: CG is bottom-left,
        // top-left (x, y) is bottom-left (x, h-1-y).
        context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y),
                                       width: image.width, height: image.height))
        let a = Int(buf[3])
        guard a > 0 else { return (0, 0, 0, 0) }
        // Un-premultiply so color checks read in source terms.
        return (Int(buf[0]) * 255 / a, Int(buf[1]) * 255 / a, Int(buf[2]) * 255 / a, a)
    }

    private let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)

    private func near(_ value: Int, _ target: Int, tol: Int = 2) -> Bool {
        abs(value - target) <= tol
    }

    // MARK: Fill

    @Test func fillPaintsInsideThePathOnly() throws {
        let base = image(width: 20, height: 20, color: white)
        let path = CGPath(rect: CGRect(x: 4, y: 6, width: 8, height: 8), transform: nil)
        let filled = try #require(RegionOps.filled(base, path: path, hex: "#FF0000"))
        #expect(filled.width == 20 && filled.height == 20)
        let inside = pixel(filled, 8, 10)
        #expect(near(inside.r, 255) && near(inside.g, 0) && near(inside.b, 0) && inside.a == 255)
        let outside = pixel(filled, 2, 2)
        #expect(near(outside.r, 255) && near(outside.g, 255) && near(outside.b, 255))
    }

    @Test func fillIsInTopLeftCoordinates() throws {
        // Fill a region near the TOP edge; the top pixel changes, the bottom
        // doesn't — catches a vertical flip.
        let base = image(width: 10, height: 10, color: white)
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: 10, height: 3), transform: nil)
        let filled = try #require(RegionOps.filled(base, path: path, hex: "#0000FF"))
        #expect(near(pixel(filled, 5, 1).b, 255) && near(pixel(filled, 5, 1).r, 0))
        #expect(near(pixel(filled, 5, 8).r, 255) && near(pixel(filled, 5, 8).b, 255)) // still white
    }

    @Test func fillHonorsEvenOddHoles() throws {
        // A donut region: outer rect minus inner rect (two subpaths, even-odd).
        let donut = CGMutablePath()
        donut.addRect(CGRect(x: 2, y: 2, width: 12, height: 12))
        donut.addRect(CGRect(x: 6, y: 6, width: 4, height: 4))
        let base = image(width: 16, height: 16, color: white)
        let filled = try #require(RegionOps.filled(base, path: donut, hex: "#00FF00"))
        #expect(near(pixel(filled, 4, 8).g, 255) && near(pixel(filled, 4, 8).r, 0))  // ring
        #expect(near(pixel(filled, 8, 8).r, 255) && near(pixel(filled, 8, 8).g, 255)) // hole stays white
    }

    @Test func fillClipsPathsThatOverhangTheImage() throws {
        let base = image(width: 10, height: 10, color: white)
        let path = CGPath(rect: CGRect(x: -5, y: -5, width: 10, height: 10), transform: nil)
        let filled = try #require(RegionOps.filled(base, path: path, hex: "#FF0000"))
        #expect(near(pixel(filled, 2, 2).r, 255) && near(pixel(filled, 2, 2).g, 0))
        #expect(near(pixel(filled, 8, 8).g, 255)) // untouched corner
    }

    // MARK: Erase

    @Test func eraseClearsInsideToTransparent() throws {
        let base = image(width: 20, height: 20, color: white)
        let path = CGPath(ellipseIn: CGRect(x: 4, y: 4, width: 12, height: 12), transform: nil)
        let erased = try #require(RegionOps.erased(base, path: path))
        #expect(pixel(erased, 10, 10).a == 0)                    // ellipse center gone
        #expect(pixel(erased, 1, 1).a == 255)                    // corner intact
        // Inside the bounds but fully outside the ellipse (clear of the
        // antialiased clip edge).
        #expect(pixel(erased, 4, 4).a == 255)
    }

    // MARK: Extract

    @Test func extractCropsToBoundsWithTransparentOutside() throws {
        let base = image(width: 20, height: 20, color: white)
        let path = CGPath(ellipseIn: CGRect(x: 4, y: 6, width: 10, height: 10), transform: nil)
        let extracted = try #require(RegionOps.extracted(base, path: path))
        #expect(extracted.width == 10 && extracted.height == 10)
        // Center of the ellipse (bounds-local coords) keeps the source pixels…
        let center = pixel(extracted, 5, 5)
        #expect(near(center.r, 255) && center.a == 255)
        // …the bounds corner outside the ellipse is transparent.
        #expect(pixel(extracted, 0, 0).a == 0)
    }

    @Test func extractOfAnOffCanvasPathClampsToTheImage() throws {
        let base = image(width: 10, height: 10, color: white)
        let path = CGPath(rect: CGRect(x: 6, y: 6, width: 10, height: 10), transform: nil)
        let extracted = try #require(RegionOps.extracted(base, path: path))
        #expect(extracted.width == 4 && extracted.height == 4)
        #expect(pixel(extracted, 1, 1).a == 255)
    }

    @Test func extractWithNoOverlapYieldsNil() {
        let base = image(width: 10, height: 10, color: white)
        let path = CGPath(rect: CGRect(x: 20, y: 20, width: 5, height: 5), transform: nil)
        #expect(RegionOps.extracted(base, path: path) == nil)
    }
}
