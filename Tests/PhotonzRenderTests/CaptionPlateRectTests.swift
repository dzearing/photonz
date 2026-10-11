import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// Where a caption's plate is drawn, as a rect the canvas can hang the
/// Lower-third tag on (`video-captions.html` `.l3badge`), checked against the
/// pixels the rasterizer actually drew.
@Suite("Caption plate rect")
struct CaptionPlateRectTests {

    private let size = CGSize(width: 600, height: 120)

    private func lowerThird(_ string: String) -> TextContent {
        var text = TextContent(string: string, fontSize: 28, colorHex: "#FFFFFF", weight: .bold,
                               alignment: .left, verticalAlignment: .bottom)
        text.plateHex = CaptionLook.lowerThirdPlate
        text.plateEndHex = CaptionLook.lowerThirdPlateEnd
        return text
    }

    /// The opaque pixels' bounds, top-left origin.
    private func inked(_ text: TextContent) throws -> CGRect {
        let image = try #require(TextRasterizer.rasterize(text, size: size))
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = try #require(CGContext(data: &data, width: width, height: height, bitsPerComponent: 8,
                                             bytesPerRow: width * 4,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where data[(y * width + x) * 4 + 3] > 128 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    @Test func thePlateRectIsWhereThePlateIsDrawn() throws {
        let text = lowerThird("Capture the screen")
        let plate = try #require(TextRasterizer.plateRect(text, size: size))
        let drawn = try inked(text)
        #expect(abs(plate.minX - drawn.minX) <= 1.5, "left edge \(plate.minX) vs drawn \(drawn.minX)")
        #expect(abs(plate.minY - drawn.minY) <= 1.5, "top edge \(plate.minY) vs drawn \(drawn.minY)")
        #expect(abs(plate.maxX - drawn.maxX) <= 1.5, "right edge \(plate.maxX) vs drawn \(drawn.maxX)")
        #expect(abs(plate.maxY - drawn.maxY) <= 1.5, "foot \(plate.maxY) vs drawn \(drawn.maxY)")
    }

    @Test func aLowerThirdPlateStartsOnTheBoxLeftEdgeAndHugsTheWords() throws {
        let plate = try #require(TextRasterizer.plateRect(lowerThird("Hi there"), size: size))
        #expect(abs(plate.minX) < 0.5, "the plate starts on the box's left edge")
        #expect(plate.maxX < size.width / 2, "and hugs two short words")
        #expect(plate.maxY <= size.height && plate.minY > size.height / 2, "low in a bottom-aligned box")
    }

    @Test func twoLinesRaiseThePlateTop() throws {
        let one = try #require(TextRasterizer.plateRect(lowerThird("Short"), size: size))
        let two = try #require(TextRasterizer.plateRect(
            lowerThird("A caption long enough that it has to run onto a second line here"), size: size))
        #expect(two.minY < one.minY - 20)
    }

    @Test func noPlateNoRect() {
        var bare = lowerThird("Capture the screen")
        bare.plateHex = nil
        #expect(TextRasterizer.plateRect(bare, size: size) == nil)
        #expect(TextRasterizer.plateRect(lowerThird(""), size: size) == nil)
        #expect(TextRasterizer.plateRect(lowerThird("Hi"), size: .zero) == nil)
    }
}
