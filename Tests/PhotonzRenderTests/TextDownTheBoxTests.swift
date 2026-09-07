import CoreGraphics
import CoreText
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// Where the words sit DOWN a box, drawn rather than calculated.
///
/// A text box is stored a few points taller than the words in it, so the
/// antialiased edge of a glyph has somewhere to round into. All of that room
/// is at the bottom, because the words are drawn from the top edge down, and
/// every box a person sees has it taken off again (`Layer.withoutSlack`).
/// Share the STORED height out and the words go down the wrong box: centred
/// ones sit about two points low, and ones asked to sit on the floor hang
/// through it. Nobody can name two points; everybody can see a title sitting
/// low in a bar.
///
/// Reading it off a raster is the only honest way to check: the room above and
/// below the INK is never equal (a capital reaches higher than the line box
/// asks and only some words go below the baseline), so these move a box's
/// words instead. Draw the same words in the box they hug, draw them again in
/// a roomy box, and the only question is how far down they went — which is a
/// number with no typography in it at all.
@Suite("Words down the box")
struct TextDownTheBoxTests {

    /// The room a box carries beyond its words, all of it at the bottom.
    private static let slack = TextRasterizer.frameInset * 2

    /// Samples per point the rasters are read at. Ink lands on fractions of a
    /// point, and a whole-pixel answer cannot tell one point of error from
    /// three.
    private static let scale: CGFloat = 8

    private func rgba(_ image: CGImage) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: &data, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                      space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return data }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return data
    }

    /// How far the first ink in a raster sits below the top edge of its box,
    /// in document points.
    private func inkTop(_ text: TextContent, in box: CGSize) throws -> CGFloat {
        let scale = Self.scale
        let image = try #require(TextRasterizer.rasterize(text, size: box, scale: scale))
        let data = rgba(image)
        let rows = (0..<image.height).filter { y in
            (0..<image.width).contains { x in data[(y * image.width + x) * 4 + 3] > 8 }
        }
        return CGFloat(try #require(rows.first, "nothing was drawn")) / scale
    }

    /// The same for the last ink.
    private func inkBottom(_ text: TextContent, in box: CGSize) throws -> CGFloat {
        let scale = Self.scale
        let image = try #require(TextRasterizer.rasterize(text, size: box, scale: scale))
        let data = rgba(image)
        let rows = (0..<image.height).filter { y in
            (0..<image.width).contains { x in data[(y * image.width + x) * 4 + 3] > 8 }
        }
        return CGFloat(try #require(rows.last, "nothing was drawn") + 1) / scale
    }

    private func words(_ string: String, _ align: TextVerticalAlign?,
                       size: CGFloat = 15) -> TextContent {
        var text = TextContent(string: string)
        text.fontSize = size
        text.verticalAlignment = align
        return text
    }

    /// The box a person sees, given a stored one.
    private func seen(_ height: CGFloat) -> CGFloat { height - Self.slack }

    private static let samples: [(String, CGFloat, CGFloat)] =
        [("Title", 15, 96), ("Title", 24, 96), ("Words to the middle", 13, 48),
         ("Hg baseline", 15, 61), ("Two\nlines", 15, 120)]

    /// The one this task is named after. A label centred in a box goes down by
    /// exactly half the room that box has beyond it, so what is above the words
    /// and what is below them are the same.
    @Test(arguments: samples)
    func centredWordsGoDownHalfTheRoom(string: String, size: CGFloat, height: CGFloat) throws {
        let hugging = words(string, nil, size: size)
        let box = TextRasterizer.naturalSize(hugging)
        let roomy = CGSize(width: box.width, height: height)
        let moved = try inkTop(words(string, .middle, size: size), in: roomy)
            - inkTop(hugging, in: box)
        let half = (seen(height) - seen(box.height)) / 2
        #expect(abs(moved - half) <= 0.6,
                "\"\(string)\" at \(size) went down \(moved), not \(half)")
    }

    /// Words told to sit at the bottom go down ALL of it, and stop on the floor
    /// a person can see rather than hanging through it.
    @Test(arguments: samples)
    func wordsAtTheBottomLandOnTheFloorAPersonSees(string: String, size: CGFloat,
                                                  height: CGFloat) throws {
        let hugging = words(string, nil, size: size)
        let box = TextRasterizer.naturalSize(hugging)
        let roomy = CGSize(width: box.width, height: height)
        let text = words(string, .bottom, size: size)
        let moved = try inkTop(text, in: roomy) - inkTop(hugging, in: box)
        let all = seen(height) - seen(box.height)
        #expect(abs(moved - all) <= 0.6,
                "\"\(string)\" at \(size) went down \(moved), not \(all)")
        #expect(try inkBottom(text, in: roomy) <= seen(height),
                "\"\(string)\" draws past the bottom edge of the box a person sees")
    }

    /// A bar's shape, because that is what the error was seen in: a fifteen
    /// point title centred in a box forty eight tall.
    @Test func aCentredLabelSitsInTheMiddleOfABarShapedBox() throws {
        let hugging = words("Title", nil)
        let bar = CGSize(width: 320, height: 48)
        let moved = try inkTop(words("Title", .middle), in: bar)
            - inkTop(hugging, in: TextRasterizer.naturalSize(hugging))
        #expect(abs(moved - (seen(48) - seen(TextRasterizer.naturalSize(hugging).height)) / 2) <= 0.6,
                "the title went down \(moved)")
    }

    /// Nothing about words that start at the top changes, and a box exactly the
    /// size of its words has nowhere to move them whatever it was asked.
    @Test(arguments: [TextVerticalAlign.top, .middle, .bottom])
    func wordsInABoxTheirOwnSizeStartAtTheTop(align: TextVerticalAlign) throws {
        let text = words("Title", align)
        #expect(TextBlockMetrics.topInset(for: text, in: TextRasterizer.naturalSize(text)) == 0)
    }

    /// And a box too small for its words keeps them where they are: losing a
    /// line is worse than words hugging the top of a box that cannot hold them.
    @Test func wordsTallerThanTheirBoxStayAtTheTop() {
        let text = words("Four\nlines\nof\nwords", .middle)
        #expect(TextBlockMetrics.topInset(for: text, in: CGSize(width: 200, height: 30)) == 0)
    }
}
