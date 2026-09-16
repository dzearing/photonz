import CoreGraphics
import Foundation
import PhotonzCore
import PhotonzRender
import Testing

/// Telling a picture that is one flat colour from a picture that is not
/// (`FlatBitmap.swift`). It is what keeps a blank canvas's white background out
/// of an exported SVG as base64.
@Suite("A picture that is really one flat colour")
struct FlatBitmapTests {

    @Test func aBlankCanvasBackgroundReadsAsItsOwnWhite() throws {
        let white = try #require(SolidImage.make(size: CGSize(width: 1440, height: 1024),
                                                 hex: "#FFFFFF"))
        let found = try #require(FlatBitmap.color(of: white))
        #expect(found.hexString == "#FFFFFF")
        #expect(found.a == 1)
    }

    @Test func aCanvasOfAnyOtherColourReadsAsThatColour() throws {
        let blue = try #require(SolidImage.make(size: CGSize(width: 64, height: 48),
                                                hex: "#2E6BFF"))
        #expect(FlatBitmap.color(of: blue)?.hexString == "#2E6BFF")
    }

    @Test func aTranslucentFlatColourKeepsItsSeeThroughness() throws {
        let veil = try #require(SolidImage.make(size: CGSize(width: 40, height: 40),
                                                hex: "#00000099"))
        let found = try #require(FlatBitmap.color(of: veil))
        #expect(abs(found.a - 0.6) < 0.01)
    }

    @Test func aPhotographIsNotFlat() throws {
        #expect(FlatBitmap.color(of: Self.checkerboard(200, 160)) == nil)
    }

    /// The case the cheap first look cannot see: one pixel out of a million,
    /// nowhere near the sample grid. An eraser stroke on a blank canvas is
    /// exactly this, and it must keep its pixels.
    @Test func oneWrongPixelInTheMiddleIsEnoughToKeepThePixels() throws {
        let marked = try #require(Self.white(1000, 800, mark: CGRect(x: 517, y: 433,
                                                                    width: 1, height: 1)))
        #expect(FlatBitmap.color(of: marked) == nil)
    }

    /// Big enough that the walk runs in bands, with the odd pixel in the last
    /// one, so a band that is never read cannot pass as flat.
    @Test func aWrongPixelInTheLastBandIsFoundToo() throws {
        let marked = try #require(Self.white(2400, 2400, mark: CGRect(x: 1200, y: 2390,
                                                                     width: 1, height: 1)))
        #expect(FlatBitmap.color(of: marked) == nil)
        let plain = try #require(SolidImage.make(size: CGSize(width: 2400, height: 2400),
                                                 hex: "#FFFFFF"))
        #expect(FlatBitmap.color(of: plain)?.hexString == "#FFFFFF")
    }

    @Test func everyImageLayerInTheDocumentIsRead() throws {
        let store = ImageStore()
        let white = try #require(SolidImage.make(size: CGSize(width: 100, height: 100),
                                                 hex: "#FFFFFF"))
        let flatRef = store.register(white)
        let photoRef = store.register(Self.checkerboard(40, 30))
        let document = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100), layers: [
            Layer(name: "Background", content: .image(flatRef),
                  frame: CGRect(x: 0, y: 0, width: 100, height: 100)),
            Layer(name: "Photo", content: .image(photoRef),
                  frame: CGRect(x: 10, y: 10, width: 40, height: 30))
        ])
        let found = FlatBitmap.colors(in: document, store: store)
        #expect(found[flatRef.id]?.hexString == "#FFFFFF")
        #expect(found[photoRef.id] == nil)
    }

    // MARK: - Scenery

    /// A flat white bitmap with one pixel painted black at `mark`.
    static func white(_ width: Int, _ height: Int, mark: CGRect) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        context.fill(mark)
        return context.makeImage()
    }

    static func checkerboard(_ width: Int, _ height: Int) -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: nil, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for y in 0..<height / 10 {
            for x in 0..<width / 10 {
                let dark = (x + y).isMultiple(of: 2)
                context.setFillColor(CGColor(srgbRed: dark ? 0.1 : 0.9,
                                             green: dark ? 0.2 : 0.8,
                                             blue: dark ? 0.8 : 0.2, alpha: 1))
                context.fill(CGRect(x: x * 10, y: y * 10, width: 10, height: 10))
            }
        }
        return context.makeImage()!
    }
}
