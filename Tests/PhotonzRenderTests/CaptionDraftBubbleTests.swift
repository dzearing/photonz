import CoreGraphics
import PhotonzCore
import Testing
@testable import PhotonzRender

/// The bubble behind an open arrow caption is drawn by the code that draws the
/// committed chip, words left out: the field's own text view types the words.
/// Before this the bubble was a stand-in (one flat fill, an edge, a shadow) and
/// a chip's finish (its gradient, rim, highlight, accent stripe) appeared only
/// once the field closed, so a look picked while typing never looked like the
/// label that landed (the user, 2026-11-21).
@Suite("The bubble behind an open caption")
struct CaptionDraftBubbleTests {

    private func pixels(_ image: CGImage) -> [UInt8] {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &data, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return data
    }

    @Test("is the committed chip less its words, in every chip style", arguments: ChipStyle.allCases)
    func plateIsThePillLessItsWords(style: ChipStyle) throws {
        let words = "Save button"
        var content = AnnotationContent(shape: .arrow, strokeWidth: 4, colorHex: "#2F7CF6")
        content.caption = words
        content.applyChipStyle(style)
        let scale: CGFloat = 2
        let chip = CaptionMetrics.pillSize(for: words, in: content)
        let pill = try #require(AnnotationRasterizer.captionPill(content, scale: scale))
        let plate = try #require(AnnotationRasterizer.captionPlate(content, chipSize: chip, scale: scale))
        #expect(plate.size == pill.size)
        #expect(plate.image.width == pill.image.width)
        #expect(plate.image.height == pill.image.height)

        // Where the words go: the chip, less its padding top and bottom.
        let box = CGRect(x: (pill.size.width - chip.width) / 2,
                         y: (pill.size.height - chip.height) / 2 + content.captionPadding / 2,
                         width: chip.width, height: chip.height - content.captionPadding)
        let a = pixels(pill.image), b = pixels(plate.image)
        let width = pill.image.width
        var inWords = 0, outside = 0
        for index in stride(from: 0, to: a.count, by: 4) {
            var differs = false
            for channel in 0..<4 where abs(Int(a[index + channel]) - Int(b[index + channel])) > 2 {
                differs = true
            }
            guard differs else { continue }
            let pixel = index / 4
            let point = CGPoint(x: (CGFloat(pixel % width) + 0.5) / scale,
                                y: (CGFloat(pixel / width) + 0.5) / scale)
            if box.contains(point) { inWords += 1 } else { outside += 1 }
        }
        #expect(inWords > 50, "the committed chip's words should be missing from the plate")
        #expect(outside == 0, "\(outside) pixels outside the words differ: the plate is not the chip it stands in for")
    }

    /// A fresh arrow's field is empty, and its bubble is already the chip the
    /// caption is about to land in.
    @Test func anEmptyCaptionStillHasAPlate() throws {
        var content = AnnotationContent(shape: .arrow, strokeWidth: 4, colorHex: "#2F7CF6")
        content.applyChipStyle(.paper)
        let chip = CGSize(width: 120, height: 30)
        let plate = try #require(AnnotationRasterizer.captionPlate(content, chipSize: chip, scale: 1))
        let slack = content.captionShadowSlack
        #expect(plate.size == CGSize(width: chip.width + 2 * slack, height: chip.height + 2 * slack))
        let data = pixels(plate.image)
        let centre = (plate.image.height / 2 * plate.image.width + plate.image.width / 2) * 4
        #expect(data[centre + 3] > 200, "the middle of the plate is painted")
    }
}
