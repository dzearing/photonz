import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// Where each word of a label is drawn, so a double click on one word of a
/// caption can open that word and nothing else (`TextRasterizer.wordRects`).
///
/// Checked against the raster itself: every drop of ink the words leave lies
/// inside the boxes the words were said to be in, and each box has ink in it.
@Suite("Where each word is drawn")
struct TextWordRectsTests {

    private static let scale: CGFloat = 4

    /// Every inked point of `text` drawn in `size`, in document points, top-left
    /// origin.
    private func ink(_ text: TextContent, size: CGSize) -> [CGPoint] {
        guard let image = TextRasterizer.rasterize(text, size: size, scale: Self.scale),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return [] }
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        guard let context = CGContext(data: &data, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return [] }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        var points: [CGPoint] = []
        for y in 0..<image.height {
            for x in 0..<image.width where data[(y * image.width + x) * 4 + 3] > 96 {
                points.append(CGPoint(x: (CGFloat(x) + 0.5) / Self.scale, y: (CGFloat(y) + 0.5) / Self.scale))
            }
        }
        return points
    }

    private func caption(_ string: String) -> TextContent {
        TextContent(string: string, fontSize: 40, colorHex: "#FFFFFF", weight: .semibold,
                    alignment: .center, verticalAlignment: .bottom)
    }

    @Test func everyWordsInkIsInsideItsBox() {
        let text = caption("The transport bar appears")
        let size = CGSize(width: 900, height: 120)
        let rects = TextRasterizer.wordRects(text, size: size)
        #expect(rects.count == 4)
        let boxes = rects.compactMap { $0 }
        #expect(boxes.count == 4)
        for (a, b) in zip(boxes, boxes.dropFirst()) { #expect(a.maxX <= b.minX + 0.5) }
        let inked = ink(text, size: size)
        #expect(!inked.isEmpty)
        let slack: CGFloat = 3
        let stray = inked.filter { point in !boxes.contains { $0.insetBy(dx: -slack, dy: -slack).contains(point) } }
        #expect(stray.isEmpty, "\(stray.count) inked points outside every word's box")
        for box in boxes { #expect(inked.contains { box.contains($0) }) }
    }

    @Test func aWordOnTheSecondLineIsBelowTheFirst() {
        let text = caption("one two three four five six seven eight nine ten")
        let size = CGSize(width: 320, height: 200)
        let rects = TextRasterizer.wordRects(text, size: size).compactMap { $0 }
        #expect(rects.count == 10)
        #expect((rects.last?.minY ?? 0) > (rects.first?.maxY ?? .infinity) - 1)
    }
}
