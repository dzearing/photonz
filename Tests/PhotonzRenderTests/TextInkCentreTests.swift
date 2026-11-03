import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// Words centred in a control are centred by what a person sees: the ink of
/// the words across, the band from a capital's top to the line it stands on
/// down. Centring the measured box put a badge's "3" and a button's "Button"
/// about two points left of and above the middle of their shape (the eval,
/// 2026-11-02: measured off the drawn sheet, 1.5 left and 2 up on a badge).
@Suite("Text ink centre")
struct TextInkCentreTests {

    /// The ink's box in a drawing, in document points from its top left.
    private func inkBox(_ image: CGImage, scale: CGFloat) -> CGRect? {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &data, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var minX = Int.max, maxX = -1, minY = Int.max, maxY = -1
        for y in 0..<height { for x in 0..<width where data[(y * width + x) * 4 + 3] > 127 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        guard maxX >= 0 else { return nil }
        // The bitmap's rows are stored top first.
        return CGRect(x: CGFloat(minX) / scale, y: CGFloat(minY) / scale,
                      width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxY - minY + 1) / scale)
    }

    @Test("Moving the box by the offset puts the words' ink across, and a capital's band down, in its middle",
          arguments: [("3", CGFloat(13), TextWeight.semibold), ("Button", 15, .semibold), ("Placeholder", 15, .regular),
                      ("12", 11, .bold)])
    func offsetCentresTheInk(words: String, size: CGFloat, weight: TextWeight) throws {
        let text = TextContent(string: words, fontSize: size, colorHex: "#FFFFFF", weight: weight)
        let box = TextRasterizer.naturalSize(text)
        let offset = TextRasterizer.inkCentreOffset(text)
        let scale: CGFloat = 4
        let drawn = try #require(TextRasterizer.rasterize(text, size: box, scale: scale))
        let ink = try #require(inkBox(drawn, scale: scale))
        #expect(abs(ink.midX - (box.width / 2 + offset.dx)) <= 0.5, "across: ink \(ink.midX), box \(box.width / 2), offset \(offset.dx)")

        var capital = text
        capital.string = "H"
        let capitalDrawn = try #require(TextRasterizer.rasterize(capital, size: TextRasterizer.naturalSize(capital), scale: scale))
        let band = try #require(inkBox(capitalDrawn, scale: scale))
        #expect(abs(band.midY - (box.height / 2 + offset.dy)) <= 0.5, "down: capital band \(band.midY), box \(box.height / 2), offset \(offset.dy)")
    }

    @Test("Ink that sits off the middle is measured as off it, so the fix is not a no-op")
    func numeralSitsOffTheMiddle() {
        let offset = TextRasterizer.inkCentreOffset(TextContent(string: "3", fontSize: 13, colorHex: "#FFFFFF", weight: .semibold))
        #expect(abs(offset.dx) >= 0.5 || abs(offset.dy) >= 0.5, "\(offset)")
    }

    @Test("Nothing to centre reports no offset: empty words, more than one line")
    func nothingToCentre() {
        #expect(TextRasterizer.inkCentreOffset(TextContent(string: "", fontSize: 13)) == .zero)
        #expect(TextRasterizer.inkCentreOffset(TextContent(string: "One\nTwo", fontSize: 13)) == .zero)
    }
}
