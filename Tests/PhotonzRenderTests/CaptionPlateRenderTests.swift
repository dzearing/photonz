import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// A caption's plate and its lit word, measured off real pixels
/// (`CaptionLook.swift`, `docs/design/mocks/pages/video-captions.html`).
///
/// The mock's caption sits on a dark plate that hugs the words, not the whole
/// band, and the word being said is drawn yellow. Both are checked against
/// what the rasterizer actually drew.
@Suite("Caption plate and lit word")
struct CaptionPlateRenderTests {

    private let size = CGSize(width: 600, height: 80)

    private func pixels(_ text: TextContent) -> (bytes: [UInt8], width: Int, height: Int)? {
        guard let image = TextRasterizer.rasterize(text, size: size) else { return nil }
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (data, width, height)
    }

    private func caption(_ string: String) -> TextContent {
        TextContent(string: string, fontSize: 28, colorHex: "#FFFFFF", weight: .semibold,
                    alignment: .center, verticalAlignment: .bottom)
    }

    /// Columns holding any opaque pixel, left to right.
    private func inkedColumns(_ px: (bytes: [UInt8], width: Int, height: Int)) -> ClosedRange<Int>? {
        var first: Int?, last: Int?
        for x in 0..<px.width {
            for y in 0..<px.height where px.bytes[(y * px.width + x) * 4 + 3] > 200 {
                if first == nil { first = x }
                last = x
                break
            }
        }
        guard let first, let last else { return nil }
        return first...last
    }

    @Test func aPlateSitsBehindTheWordsAndHugsThem() throws {
        var text = caption("Capture the screen")
        let bare = try #require(pixels(text))
        text.plateHex = "#1A1433"
        let plated = try #require(pixels(text))
        let words = try #require(inkedColumns(bare))
        let plate = try #require(inkedColumns(plated))
        #expect(plate.lowerBound < words.lowerBound, "the plate runs past the first letter")
        #expect(plate.upperBound > words.upperBound, "and past the last")
        #expect(plate.lowerBound > 20, "but hugs the words rather than filling the band")
        #expect(plate.upperBound < Int(size.width) - 20)
        // Between the band's top and the words, where no letter is, the plate
        // colour shows: a dark, opaque pixel.
        let x = (plate.lowerBound + 3)
        let y = plated.height - 12
        let i = (y * plated.width + x) * 4
        #expect(plated.bytes[i + 3] > 240)
        #expect(plated.bytes[i] < 60 && plated.bytes[i + 2] < 90)
    }

    /// The colour of the pixel at a column, a little way above the box's
    /// floor where the plate shows and no letter is.
    private func colour(_ px: (bytes: [UInt8], width: Int, height: Int), x: Int, y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        let i = (y * px.width + x) * 4
        return (Int(px.bytes[i]), Int(px.bytes[i + 1]), Int(px.bytes[i + 2]), Int(px.bytes[i + 3]))
    }

    @Test func aLowerThirdPlateRunsFromVioletToLilac() throws {
        var text = caption("Capture the screen")
        text.alignment = .left
        text.plateHex = "#9A5CFFF0"
        text.plateEndHex = "#C56CFFDB"
        let px = try #require(pixels(text))
        let plate = try #require(inkedColumns(px))
        let y = px.height - 6
        let left = colour(px, x: plate.lowerBound + 2, y: y)
        let right = colour(px, x: plate.upperBound - 2, y: y)
        #expect(left.a > 200 && right.a > 180, "both ends are plate")
        #expect(left.b > left.g + 60 && right.b > right.g + 60, "violet, not grey")
        #expect(right.r > left.r + 20, "and warmer to the right, the mock's 120 degree run")
    }

    @Test func aLeftAlignedPlateKeepsItsAirInsideTheBox() throws {
        var text = caption("Capture the screen")
        text.alignment = .left
        let bare = try #require(pixels(text))
        text.plateHex = "#9A5CFFF0"
        let plated = try #require(pixels(text))
        let plate = try #require(inkedColumns(plated))
        // The words move in by the plate's air, so the plate starts on the
        // box's own edge instead of being cut off by it.
        #expect(plate.lowerBound <= 2, "the plate starts on the box's left edge")
        var words = plated
        for index in stride(from: 0, to: words.bytes.count, by: 4) {
            let r = words.bytes[index], b = words.bytes[index + 2]
            if !(r > 240 && b > 240) { words.bytes[index + 3] = 0 }
        }
        let letters = try #require(inkedColumns(words))
        let unplated = try #require(inkedColumns(bare))
        #expect(letters.lowerBound >= unplated.lowerBound + 8, "the words sit in from the plate's edge")
    }

    @Test func noPlateLeavesTextDrawnExactlyAsBefore() throws {
        let text = caption("Capture the screen")
        let a = try #require(pixels(text))
        var plain = text
        plain.plateHex = nil
        let b = try #require(pixels(plain))
        #expect(a.bytes == b.bytes)
    }

    @Test func theLitWordIsDrawnInItsColour() throws {
        var text = caption("Capture the screen")
        text.highlight = TextHighlight(location: 12, length: 6, colorHex: "#FFD76A")
        let px = try #require(pixels(text))
        var yellow = 0, white = 0
        for index in stride(from: 0, to: px.bytes.count, by: 4) where px.bytes[index + 3] > 250 {
            let r = px.bytes[index], g = px.bytes[index + 1], b = px.bytes[index + 2]
            if r > 240, g > 190, b < 140 { yellow += 1 }
            if r > 240, g > 240, b > 240 { white += 1 }
        }
        #expect(yellow > 40, "screen is yellow")
        #expect(white > 40, "the rest is still white")
    }

    @Test func aHighlightPastTheEndOfRetypedWordsDrawsNothingWrong() throws {
        var text = caption("Hi")
        text.highlight = TextHighlight(location: 12, length: 6, colorHex: "#FFD76A")
        #expect(pixels(text) != nil)
    }
}
