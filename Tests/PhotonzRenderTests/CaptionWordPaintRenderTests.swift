import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// The word being said, drawn on its own over the rest of its caption
/// (`CaptionWordStyle.swift`): bigger mid-pop, on a pill, glowing, underlined,
/// with the words either side dimmed or waiting. Measured off real pixels.
@Suite("Caption word paint")
struct CaptionWordPaintRenderTests {

    private let size = CGSize(width: 600, height: 120)

    private struct Pixels {
        var bytes: [UInt8]
        var width: Int
        var height: Int

        func alpha(_ x: Int, _ y: Int) -> UInt8 { bytes[(y * width + x) * 4 + 3] }

        /// Columns holding any solid pixel, left to right.
        var inkedColumns: ClosedRange<Int>? {
            var first: Int?, last: Int?
            for x in 0..<width {
                for y in 0..<height where alpha(x, y) > 200 {
                    if first == nil { first = x }
                    last = x
                    break
                }
            }
            guard let first, let last else { return nil }
            return first...last
        }

        /// Runs of at least `wide` empty columns between the first ink and
        /// the last: the gaps between the words.
        func gaps(wide: Int = 4) -> Int {
            guard let inked = inkedColumns else { return 0 }
            var runs = 0, empty = 0
            for x in inked {
                let any = (0..<height).contains { alpha(x, $0) > 40 }
                if any {
                    if empty >= wide { runs += 1 }
                    empty = 0
                } else {
                    empty += 1
                }
            }
            return runs
        }

        /// Rows holding any solid pixel, top to bottom.
        var inkedRows: ClosedRange<Int>? {
            var first: Int?, last: Int?
            for y in 0..<height {
                for x in 0..<width where alpha(x, y) > 200 {
                    if first == nil { first = y }
                    last = y
                    break
                }
            }
            guard let first, let last else { return nil }
            return first...last
        }

        func count(_ match: (UInt8, UInt8, UInt8, UInt8) -> Bool) -> Int {
            var total = 0
            for index in stride(from: 0, to: bytes.count, by: 4)
            where match(bytes[index], bytes[index + 1], bytes[index + 2], bytes[index + 3]) {
                total += 1
            }
            return total
        }
    }

    private func pixels(_ text: TextContent) -> Pixels? {
        guard let image = TextRasterizer.rasterize(text, size: size) else { return nil }
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return Pixels(bytes: data, width: width, height: height)
    }

    /// "Capture the Screen", with "Screen" being said.
    private func caption(_ paint: CaptionWordPaint?) -> TextContent {
        var text = TextContent(string: "Capture the Screen", fontSize: 32, colorHex: "#FFFFFF",
                               weight: .semibold, alignment: .center, verticalAlignment: .bottom)
        text.wordPaint = paint
        return text
    }

    private let screen = CaptionActiveWord.Span(location: 12, length: 6)
    private let capture = CaptionActiveWord.Span(location: 0, length: 7)

    @Test func aGrownWordIsDrawnBiggerThanTheRest() throws {
        let still = try #require(pixels(caption(CaptionWordPaint(word: screen, drawnAlone: true))))
        let grown = try #require(pixels(caption(CaptionWordPaint(word: screen, scale: 1.4, drawnAlone: true))))
        let stillColumns = try #require(still.inkedColumns)
        let grownColumns = try #require(grown.inkedColumns)
        #expect(grownColumns.count > stillColumns.count + 16, "the line is wider by the grown word")
        let stillRows = try #require(still.inkedRows)
        let grownRows = try #require(grown.inkedRows)
        #expect(grownRows.lowerBound < stillRows.lowerBound, "and stands taller")
    }

    @Test func aWordDrawnAloneAtItsOwnSizeLooksLikeTheLine() throws {
        let plain = try #require(pixels(caption(nil)))
        let alone = try #require(pixels(caption(CaptionWordPaint(word: screen, drawnAlone: true))))
        #expect(plain.inkedColumns == alone.inkedColumns)
        let plainRows = try #require(plain.inkedRows)
        let aloneRows = try #require(alone.inkedRows)
        #expect(plainRows.count == aloneRows.count, "the same line")
        #expect(aloneRows.upperBound < plainRows.upperBound, "lifted, so a grown word has room below")
    }

    @Test func aGrownWordTakesItsPlateWithIt() throws {
        var still = caption(CaptionWordPaint(word: screen, drawnAlone: true))
        still.plateHex = "#FF0000"
        var grown = caption(CaptionWordPaint(word: screen, scale: 1.4, drawnAlone: true))
        grown.plateHex = "#FF0000"
        let red: (UInt8, UInt8, UInt8, UInt8) -> Bool = { r, g, b, a in a > 240 && r > 240 && g < 20 && b < 20 }
        let a = try #require(pixels(still)), b = try #require(pixels(grown))
        #expect(b.count(red) > a.count(red), "the plate grows round the bigger word")
    }

    @Test func wordsStillToComeCanWaitOffScreen() throws {
        let full = try #require(pixels(caption(CaptionWordPaint(word: capture))))
        let waiting = try #require(pixels(caption(CaptionWordPaint(word: capture, coming: .hidden))))
        let fullColumns = try #require(full.inkedColumns)
        let waitingColumns = try #require(waiting.inkedColumns)
        #expect(waitingColumns.upperBound < fullColumns.upperBound - 100, "only Capture shows")
    }

    @Test func dimWordsAreFainterThanTheOneBeingSaid() throws {
        let full = try #require(pixels(caption(CaptionWordPaint(word: screen))))
        let dim = try #require(pixels(caption(CaptionWordPaint(word: screen, said: .dim))))
        let solid: (UInt8, UInt8, UInt8, UInt8) -> Bool = { _, _, _, a in a > 240 }
        #expect(dim.count(solid) < full.count(solid) / 2, "Capture the fades")
        #expect(dim.inkedColumns != nil)
    }

    @Test func theCurrentWordCanSitOnAPillInItsOwnColour() throws {
        let px = try #require(pixels(caption(CaptionWordPaint(word: screen, colorHex: "#000000",
                                                              pillHex: "#FF7AB6", drawnAlone: true))))
        let pink = px.count { r, g, b, a in a > 240 && r > 230 && g > 100 && g < 150 && b > 160 && b < 200 }
        #expect(pink > 400, "a pink pill behind screen")
        let black = px.count { r, g, b, a in a > 240 && r < 30 && g < 30 && b < 30 }
        #expect(black > 60, "screen itself in black on it")
    }

    @Test func theCurrentWordsGlowSpreadsPastItsLetters() throws {
        let bare = try #require(pixels(caption(CaptionWordPaint(word: screen, drawnAlone: true))))
        let glowing = try #require(pixels(caption(CaptionWordPaint(word: screen, glowHex: "#FF4FD8",
                                                                   drawnAlone: true))))
        let faint: (UInt8, UInt8, UInt8, UInt8) -> Bool = { _, _, _, a in a > 10 && a < 200 }
        #expect(glowing.count(faint) > bare.count(faint) * 2, "a halo round screen")
    }

    @Test func anUnderlineSweepsUnderTheWord() throws {
        let none = try #require(pixels(caption(CaptionWordPaint(word: screen, drawnAlone: true))))
        let half = try #require(pixels(caption(CaptionWordPaint(word: screen, underline: 0.5, drawnAlone: true))))
        let full = try #require(pixels(caption(CaptionWordPaint(word: screen, underline: 1, drawnAlone: true))))
        let solid: (UInt8, UInt8, UInt8, UInt8) -> Bool = { _, _, _, a in a > 240 }
        #expect(half.count(solid) > none.count(solid))
        #expect(full.count(solid) > half.count(solid))
    }

    @Test func aGrownWordNeverRunsIntoItsNeighbours() throws {
        func line(_ scale: CGFloat) -> TextContent {
            var text = TextContent(string: "Tap Screen now", fontSize: 32, colorHex: "#FFFFFF",
                                   weight: .semibold, alignment: .center, verticalAlignment: .bottom)
            text.wordPaint = CaptionWordPaint(word: CaptionActiveWord.Span(location: 4, length: 6),
                                              scale: scale, drawnAlone: true)
            return text
        }
        let still = try #require(pixels(line(1)))
        let grown = try #require(pixels(line(1.5)))
        #expect(still.gaps() == 2)
        #expect(grown.gaps() == 2, "both spaces still there with the middle word half as big again")
    }
}

extension CaptionWordPaintRenderTests {
    @Test func theWholeTextsOutlineGoesRoundTheCurrentWordToo() throws {
        func drawn(_ paint: CaptionWordPaint) -> Int {
            var text = TextContent(string: "Capture the Screen", fontSize: 32, colorHex: "#FFD76A",
                                   weight: .bold, alignment: .center, verticalAlignment: .bottom)
            text.wordPaint = paint
            guard let image = TextRasterizer.rasterize(
                text, size: CGSize(width: 600, height: 120),
                outlines: [TextRasterizer.TextOutline(width: 3, colorHex: "#FF0000")]) else { return 0 }
            let width = image.width, height = image.height
            var data = [UInt8](repeating: 0, count: width * height * 4)
            guard let context = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return 0 }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            var red = 0
            for i in stride(from: 0, to: data.count, by: 4)
            where data[i + 3] > 240 && data[i] > 240 && data[i + 1] < 30 { red += 1 }
            return red
        }
        let span = CaptionActiveWord.Span(location: 12, length: 6)
        let inLine = drawn(CaptionWordPaint(word: span))
        let alone = drawn(CaptionWordPaint(word: span, drawnAlone: true))
        #expect(alone > inLine * 9 / 10, "the red edge round Screen is still there when it is drawn alone")
    }
}
