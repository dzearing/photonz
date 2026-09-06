import CoreGraphics
import CoreText
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// Words that stay on one line are drawn on one line, and give way with an
/// ellipsis where the box runs out (`docs/design/ui-building.md`, "A title
/// stays on one line").
@Suite("Words that stay on one line give way with an ellipsis")
struct OneLineTextRenderTests {

    private func title(_ string: String, oneLine: Bool = true) -> TextContent {
        var text = TextContent(string: string, fontSize: 15, colorHex: "#FFFFFF",
                               weight: .semibold, alignment: .center)
        text.staysOnOneLine = oneLine ? true : nil
        return text
    }

    /// The rows of the image that hold any ink at all.
    private func inkedRows(_ image: CGImage) -> Range<Int> {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &data, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var low = height, high = -1
        for row in 0..<height {
            for column in 0..<width where data[(row * width + column) * 4 + 3] > 60 {
                low = min(low, row); high = max(high, row)
                break
            }
        }
        return high < low ? 0..<0 : low..<(high + 1)
    }

    @Test("A title too long for its box ends in an ellipsis")
    func aLongTitleEndsInAnEllipsis() {
        let long = title("A very long navigation bar title indeed")
        let cut = TextRasterizer.truncating(long, toFit: 160)
        #expect(cut.string != long.string)
        #expect(cut.string.hasSuffix("…"))
        #expect(!cut.string.hasSuffix(" …"))
        #expect(TextRasterizer.naturalSize(cut).width <= 160)
    }

    @Test("A title that fits is left exactly as it was")
    func aTitleThatFitsIsUntouched() {
        let short = title("Inbox")
        #expect(TextRasterizer.truncating(short, toFit: 160) == short)
    }

    @Test("Words that may wrap are never cut short")
    func wrappingWordsAreNeverCut() {
        let paragraph = title("A very long navigation bar title indeed", oneLine: false)
        #expect(TextRasterizer.truncating(paragraph, toFit: 60) == paragraph)
    }

    @Test("A box far too narrow for even one word still shows the ellipsis")
    func aBoxTooNarrowForAWord() {
        let cut = TextRasterizer.truncating(title("Extraordinary"), toFit: 12)
        #expect(cut.string.hasSuffix("…"))
    }

    @Test("Measuring one line ignores the room it is measured against")
    func measuringIgnoresTheRoom() {
        let long = title("A very long navigation bar title indeed")
        #expect(TextRasterizer.naturalSize(long, maxWidth: 60)
                == TextRasterizer.naturalSize(long))
    }

    @Test("A long title drawn in a bar-height box stays on one line")
    func itDrawsOnOneLine() throws {
        let long = title("A very long navigation bar title indeed")
        let box = CGSize(width: 252, height: 22)
        let oneLine = try #require(TextRasterizer.rasterize(long, size: box))
        let rows = inkedRows(oneLine)
        #expect(!rows.isEmpty)
        // One line of 15 point type is about 18 tall; two would not fit in 22
        // at all, so anything taller than a line means the second one is being
        // drawn (and cut off) rather than the words giving way.
        #expect(rows.count <= 19)
        // And the ink reaches the right-hand end of the box, because that is
        // where the ellipsis sits.
        let wrapping = try #require(TextRasterizer.rasterize(title("Inbox"), size: box))
        #expect(inkedColumns(oneLine).upperBound > inkedColumns(wrapping).upperBound)
    }

    private func inkedColumns(_ image: CGImage) -> Range<Int> {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &data, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var low = width, high = -1
        for column in 0..<width {
            for row in 0..<height where data[(row * width + column) * 4 + 3] > 60 {
                low = min(low, column); high = max(high, column)
                break
            }
        }
        return high < low ? 0..<0 : low..<(high + 1)
    }
}
