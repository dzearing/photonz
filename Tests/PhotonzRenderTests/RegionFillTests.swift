import CoreGraphics
import Foundation
import PhotonzCore
import PhotonzRender
import Testing

/// Filling a marquee box leaves the layer the size of the pixels it now has:
/// it grows to take in paint that lands outside the old box and shrinks back
/// to what is actually drawn, the same rule a region delete already follows.
@Suite("A region fill sizes the layer to its pixels")
struct RegionFillTests {

    private let canvas = CGRect(x: 0, y: 0, width: 400, height: 300)

    /// An opaque bitmap, `w` by `h` pixels.
    private func solid(_ w: Int, _ h: Int, gray: CGFloat = 0.5) -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                bytesPerRow: w * 4, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: gray, green: gray, blue: gray, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: w, height: h))
        return context.makeImage()!
    }

    private func box(_ rect: CGRect) -> CGPath { CGPath(rect: rect, transform: nil) }

    /// The colour of one pixel, as four bytes.
    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> [UInt8] {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { raw in
            let context = CGContext(data: raw.baseAddress, width: image.width,
                                    height: image.height, bitsPerComponent: 8,
                                    bytesPerRow: image.width * 4, space: space,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        let at = (y * image.width + x) * 4
        return Array(bytes[at..<(at + 4)])
    }

    // MARK: A layer with nothing on it

    @Test func fillingABoxOnAnEmptyLayerMakesTheLayerThatBox() {
        let result = RegionFill.fill(image: nil, frame: .zero,
                                     path: box(CGRect(x: 100, y: 60, width: 80, height: 40)),
                                     hex: "#FF0000", pixelsPerPoint: 1, within: canvas)
        #expect(result?.frame == CGRect(x: 100, y: 60, width: 80, height: 40))
        #expect(result?.image.width == 80)
        #expect(result?.image.height == 40)
    }

    @Test func theEmptyLayerKeepsNoPixelsItCannotShow() {
        // 80 by 40 points of paint at one pixel a point is 80 by 40 pixels,
        // not a sheet the size of the picture.
        let result = RegionFill.fill(image: nil, frame: .zero,
                                     path: box(CGRect(x: 100, y: 60, width: 80, height: 40)),
                                     hex: "#FF0000", pixelsPerPoint: 1, within: canvas)
        #expect((result?.image.width ?? 0) * (result?.image.height ?? 0) == 80 * 40)
    }

    @Test func aRetinaDocumentMakesTwicePixelsPerPoint() {
        let result = RegionFill.fill(image: nil, frame: .zero,
                                     path: box(CGRect(x: 100, y: 60, width: 80, height: 40)),
                                     hex: "#FF0000", pixelsPerPoint: 2, within: canvas)
        #expect(result?.frame == CGRect(x: 100, y: 60, width: 80, height: 40))
        #expect(result?.image.width == 160)
        #expect(result?.image.height == 80)
    }

    @Test func paintThatRunsOffThePictureStopsAtTheEdge() {
        let result = RegionFill.fill(image: nil, frame: .zero,
                                     path: box(CGRect(x: 350, y: 250, width: 200, height: 200)),
                                     hex: "#FF0000", pixelsPerPoint: 1, within: canvas)
        #expect(result?.frame == CGRect(x: 350, y: 250, width: 50, height: 50))
    }

    @Test func aMarqueeEntirelyOffThePictureFillsNothing() {
        let result = RegionFill.fill(image: nil, frame: .zero,
                                     path: box(CGRect(x: 500, y: 500, width: 40, height: 40)),
                                     hex: "#FF0000", pixelsPerPoint: 1, within: canvas)
        #expect(result == nil)
    }

    // MARK: A layer that already has pixels

    @Test func fillingInsideTheBoxLeavesTheBoxAlone() {
        let frame = CGRect(x: 50, y: 50, width: 100, height: 100)
        let result = RegionFill.fill(image: solid(100, 100), frame: frame,
                                     path: box(CGRect(x: 60, y: 60, width: 20, height: 20)),
                                     hex: "#FF0000", pixelsPerPoint: 1, within: canvas)
        #expect(result?.frame == frame)
        #expect(result?.image.width == 100)
    }

    @Test func paintingOutsideTheBoxGrowsItToTakeThePaintIn() {
        let frame = CGRect(x: 50, y: 50, width: 100, height: 100)
        let result = RegionFill.fill(image: solid(100, 100), frame: frame,
                                     path: box(CGRect(x: 200, y: 50, width: 40, height: 40)),
                                     hex: "#FF0000", pixelsPerPoint: 1, within: canvas)
        // The old pixels run to x 150 and the new ones start at 200, so the
        // box spans both and stops at the far edge of the new paint.
        #expect(result?.frame == CGRect(x: 50, y: 50, width: 190, height: 100))
    }

    @Test func growingKeepsTheOldPixelsWhereTheyWere() {
        let frame = CGRect(x: 50, y: 50, width: 100, height: 100)
        let result = RegionFill.fill(image: solid(100, 100), frame: frame,
                                     path: box(CGRect(x: 200, y: 50, width: 40, height: 40)),
                                     hex: "#FF0000", pixelsPerPoint: 1, within: canvas)
        let image = try! #require(result?.image)
        // Top left is the old grey; the new paint sits 150 pixels along.
        #expect(pixel(image, 2, 2)[0] == 128)
        #expect(pixel(image, 160, 2) == [255, 0, 0, 255])
        // The gap between them is transparent, not a sheet of colour.
        #expect(pixel(image, 120, 2)[3] == 0)
    }

    @Test func fillingATransparentLayerTrimsToWhatWasPainted() {
        // A layer the size of the whole picture with nothing drawn on it: the
        // exact state a new layer used to be in.
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: 400, height: 300, bitsPerComponent: 8,
                                bytesPerRow: 400 * 4, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let transparent = context.makeImage()!
        let result = RegionFill.fill(image: transparent, frame: canvas,
                                     path: box(CGRect(x: 100, y: 60, width: 80, height: 40)),
                                     hex: "#FF0000", pixelsPerPoint: 1, within: canvas)
        #expect(result?.frame == CGRect(x: 100, y: 60, width: 80, height: 40))
    }

    @Test func aLayerOffTheEdgeOfThePictureKeepsThePixelsItAlreadyHas() {
        // Growing is bounded by the picture; the box a layer already has is
        // not, or a drag half off screen would lose pixels to a fill.
        let frame = CGRect(x: -40, y: 20, width: 100, height: 100)
        let result = RegionFill.fill(image: solid(100, 100), frame: frame,
                                     path: box(CGRect(x: 10, y: 20, width: 20, height: 20)),
                                     hex: "#FF0000", pixelsPerPoint: 1, within: canvas)
        #expect(result?.frame == frame)
    }
}
