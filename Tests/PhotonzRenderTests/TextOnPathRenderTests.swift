import CoreGraphics
import Foundation
import PhotonzCore
@testable import PhotonzRender
import Testing

/// Words drawn along their curve (`TextRasterizer.rasterizeOnPath`): each
/// letter on the curve and turned to it, in the picture the canvas, playback
/// and an export all draw from.
@Suite("Text on a path is drawn along the curve")
struct TextOnPathRenderTests {

    /// A quarter circle of radius 300 about the box's top-left corner, from
    /// its right-hand end (300, 0) round to its bottom (0, 300).
    static func quarterCircle() -> PathContent {
        let k: CGFloat = 0.5522847498 * 300
        return PathContent(anchors: [
            PathAnchor(point: CGPoint(x: 300, y: 0), handleOut: CGPoint(x: 0, y: k), kind: .smooth),
            PathAnchor(point: CGPoint(x: 0, y: 300), handleIn: CGPoint(x: k, y: 0), kind: .smooth),
        ], fill: nil)
    }

    static func words(_ string: String = "Follow the curve along", size: CGFloat = 36) -> TextContent {
        var text = TextContent(string: string, fontSize: size, colorHex: "#FFFFFF", weight: .bold)
        text.onPath = TextOnPath(guide: quarterCircle())
        return text
    }

    /// How many pixels in `rect` (top-left coordinates) carry ink.
    static func ink(_ image: CGImage, in rect: CGRect) -> Int {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var count = 0
        let xs = max(0, Int(rect.minX))..<min(width, Int(rect.maxX))
        let ys = max(0, Int(rect.minY))..<min(height, Int(rect.maxY))
        for y in ys {
            for x in xs where data[(y * width + x) * 4 + 3] > 128 { count += 1 }
        }
        return count
    }

    @Test func everyLetterSitsOnTheCurveTurnedToIt() {
        let text = Self.words()
        let letters = TextRasterizer.pathLetters(text)
        #expect(letters.count == 22)
        let reading = TextOnPathReading(letters: letters.compactMap { $0 }, along: Self.quarterCircle())
        #expect(reading.letterCount >= 20)
        #expect(reading.worstTurnDegrees < 5)
        #expect(reading.worstBaselineDistance < 2)
    }

    @Test func thePictureReachesPastTheCurvesBox() throws {
        let text = Self.words()
        let reach = TextOnPath.reach(fontSize: 36)
        let image = try #require(TextRasterizer.rasterize(text, size: CGSize(width: 300, height: 300),
                                                          outlines: [], scale: 2))
        #expect(image.width == Int((300 + 2 * reach) * 2))
        #expect(image.height == Int((300 + 2 * reach) * 2))
    }

    @Test func theInkFollowsTheArcAndNotAStraightLine() throws {
        var document = PhotonzDocument(canvasSize: CGSize(width: 600, height: 600))
        document.layers = [Layer(name: "Title", content: .text(Self.words()),
                                 frame: CGRect(x: 100, y: 100, width: 300, height: 300))]
        let image = try #require(DocumentRenderer().render(document, store: ImageStore()))
        // The circle is about (100, 100). Letters stand on the outside of the
        // arc, so their ink is a little past radius 300: at 20 degrees round,
        // at 45 and at 70.
        for degrees in [20.0, 45.0, 70.0] {
            let angle = degrees * .pi / 180
            let x = 100 + 318 * cos(angle), y = 100 + 318 * sin(angle)
            let box = CGRect(x: x - 22, y: y - 22, width: 44, height: 44)
            #expect(Self.ink(image, in: box) > 40, "ink on the arc at \(degrees) degrees")
        }
        // ...and none where words set flat along the top of the box would be.
        #expect(Self.ink(image, in: CGRect(x: 100, y: 60, width: 200, height: 40)) == 0)
    }

    @Test func aStartPastTheEndLeavesNothingDrawn() throws {
        var text = Self.words()
        text.onPath?.startPercent = 100
        let letters = TextRasterizer.pathLetters(text)
        #expect(letters.allSatisfy { $0 == nil })
    }

    @Test func aBreakInTheWordsIsASpaceOnTheCurve() {
        let one = TextRasterizer.pathLetters(Self.words("Ship it faster"))
        let two = TextRasterizer.pathLetters(Self.words("Ship it\nfaster"))
        #expect(one == two)
    }
}
