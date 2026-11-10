import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// A line of text breaks in the same place at every render scale. The canvas
/// bakes a label at the zoom it is shown at, and the pixel width of that
/// picture is rounded; the words must still be laid out in the box they were
/// measured for, or a line that just fits wraps at some zooms and its last
/// word falls off the foot of the box (the pricing subtitle that ended at
/// "cancel" at 67% on a 2x screen).
@Suite("A line breaks in the same place at every scale")
struct TextBreaksAtEveryScaleTests {

    private let subtitle = "Simple plans that scale with you. No hidden fees, cancel anytime."

    private func line() -> TextContent {
        TextContent(string: subtitle, fontSize: 18, colorHex: "#000000", alignment: .center)
    }

    /// Scales whose pixel width rounds DOWN for `width` points, so the old
    /// pixels-over-scale box came out narrower than the measured one. Spread
    /// from a third to four times, the window zooms on 1x and 2x screens.
    private func roundingDownScales(for width: CGFloat) -> [CGFloat] {
        var scales: [CGFloat] = [0.6715, 1.343]
        var s: CGFloat = 0.34
        while s <= 4 {
            let exact = width * s
            if exact.rounded() < exact - 0.05 { scales.append(s) }
            s += 0.0173
        }
        return scales
    }

    /// The ink's extent, in pixels: columns and rows that hold any ink.
    private func ink(_ image: CGImage) -> (columns: Int, rows: Int) {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &data, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var minX = width, maxX = -1, minY = height, maxY = -1
        for row in 0..<height {
            for column in 0..<width where data[(row * width + column) * 4 + 3] > 40 {
                minX = min(minX, column); maxX = max(maxX, column)
                minY = min(minY, row); maxY = max(maxY, row)
            }
        }
        return maxX < minX ? (0, 0) : (maxX - minX + 1, maxY - minY + 1)
    }

    @Test("The measured line keeps every word at every scale that rounds its width down")
    func everyWordAtEveryScale() throws {
        let text = line()
        let size = TextRasterizer.naturalSize(text)
        let atOne = ink(try #require(TextRasterizer.rasterize(text, size: size, scale: 1)))
        let scales = roundingDownScales(for: size.width)
        #expect(scales.count > 20)
        for scale in scales {
            let image = try #require(TextRasterizer.rasterize(text, size: size, scale: scale))
            let shown = ink(image)
            // As wide as the line at 100%, give or take a couple of pixels of
            // antialiasing, and one line tall, never two.
            let widthInPoints = CGFloat(shown.columns) / scale
            #expect(abs(widthInPoints - CGFloat(atOne.columns)) <= 3 / scale + 1,
                    "scale \(scale): ink \(widthInPoints) pt wide, \(atOne.columns) pt at 100%")
            #expect(CGFloat(shown.rows) / scale < text.fontSize * 1.4,
                    "scale \(scale): ink \(CGFloat(shown.rows) / scale) pt tall, a second line")
        }
    }

    @Test("A line revealed piece by piece breaks where the still picture does")
    func revealBreaksTheSame() throws {
        let text = line()
        let size = TextRasterizer.naturalSize(text)
        // A word pushed onto a second line falls below the box and is never
        // drawn, so counting words is what shows a line broke.
        let words = try #require(TextRasterizer.revealPieces(text, size: size, scale: 1, unit: .word)).pieces.count
        #expect(words == 11)
        for scale in roundingDownScales(for: size.width) {
            let pieces = try #require(TextRasterizer.revealPieces(text, size: size, scale: scale, unit: .word))
            #expect(pieces.pieces.count == words, "scale \(scale): \(pieces.pieces.count) of \(words) words")
        }
    }

    @Test("At 100% the words sit where they always did")
    func unmovedAtOne() throws {
        let text = line()
        let size = TextRasterizer.naturalSize(text)
        let image = try #require(TextRasterizer.rasterize(text, size: size, scale: 1))
        #expect(image.width == Int(size.width.rounded()))
        #expect(image.height == Int(size.height.rounded()))
    }
}
