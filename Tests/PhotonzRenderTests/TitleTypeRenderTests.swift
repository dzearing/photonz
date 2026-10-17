import CoreGraphics
import CoreImage
import CoreText
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// Title type drawn the way Apple sets it (`video-titles-apple.html`): letter
/// spacing, line spacing, New York, the Display cut of SF Pro at title sizes,
/// and a ramp running through the letters.
@Suite("Title type, drawn")
struct TitleTypeRenderTests {

    // MARK: - Reading a picture

    /// Every pixel, premultiplied RGBA, top row first.
    private struct Pixels {
        let width: Int, height: Int
        let data: [UInt8]

        init(_ image: CGImage) {
            width = image.width
            height = image.height
            var data = [UInt8](repeating: 0, count: width * height * 4)
            let context = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8,
                                    bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            self.data = data
        }

        func alpha(_ x: Int, _ y: Int) -> UInt8 { data[(y * width + x) * 4 + 3] }

        /// The box the ink covers, top-left coordinates, or nil for none.
        var ink: CGRect? {
            var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
            for y in 0..<height {
                for x in 0..<width where alpha(x, y) > 40 {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
            guard maxX >= 0 else { return nil }
            return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        }

        /// The first row from the top holding ink at or below `from`.
        func firstInkRow(from: Int = 0) -> Int? {
            (from..<height).first { y in (0..<width).contains { alpha($0, y) > 40 } }
        }

        /// The first row with no ink at all at or below `from`.
        func firstBlankRow(from: Int) -> Int? {
            (from..<height).first { y in !(0..<width).contains { alpha($0, y) > 40 } }
        }

        /// The mean colour of solid ink in a band of columns, un-premultiplied.
        func meanInk(columns: Range<Int>) -> (r: Double, g: Double, b: Double) {
            var r = 0.0, g = 0.0, b = 0.0, n = 0.0
            for y in 0..<height {
                for x in columns where x >= 0 && x < width {
                    let i = (y * width + x) * 4
                    guard data[i + 3] > 230 else { continue }
                    r += Double(data[i]); g += Double(data[i + 1]); b += Double(data[i + 2]); n += 1
                }
            }
            guard n > 0 else { return (0, 0, 0) }
            return (r / n, g / n, b / n)
        }
    }

    private static func draw(_ text: TextContent, maxWidth: CGFloat = .greatestFiniteMagnitude) -> Pixels {
        let size = TextRasterizer.naturalSize(text, maxWidth: maxWidth)
        return Pixels(TextRasterizer.rasterize(text, size: size)!)
    }

    private static let redToBlue = Paint(hex: "#FF0000", kind: .linear,
                                         stops: [GradientStop(hex: "#FF0000", position: 0),
                                                 GradientStop(hex: "#0000FF", position: 1)],
                                         angle: 90)

    // MARK: - Letter spacing

    @Test func trackingPullsTheLettersApart() throws {
        var text = TextContent(string: "Redline", fontSize: 100)
        let natural = try #require(Self.draw(text).ink)
        text.tracking = 0.1
        let wide = try #require(Self.draw(text).ink)
        // Ten points after each of seven letters: six of them land between
        // letters, so the ink is sixty points wider.
        #expect(abs((wide.width - natural.width) - 60) <= 2, "\(wide.width - natural.width)")
        // And the box measured for the words grows by all seven.
        let grown = TextRasterizer.naturalSize(text).width
        text.tracking = nil
        #expect(abs(grown - TextRasterizer.naturalSize(text).width - 70) <= 1)
    }

    @Test func negativeTrackingTightensThem() throws {
        var text = TextContent(string: "Redline", fontSize: 184, weight: .semibold)
        let natural = try #require(Self.draw(text).ink)
        text.tracking = -0.028
        let tight = try #require(Self.draw(text).ink)
        #expect(abs((natural.width - tight.width) - 6 * 184 * 0.028) <= 2)
    }

    // MARK: - Line spacing

    @Test func lineHeightSetsTheDistanceBetweenLines() throws {
        var text = TextContent(string: "H\nH", fontSize: 100)
        text.lineHeight = 1.5
        let picture = Self.draw(text)
        let firstTop = try #require(picture.firstInkRow())
        let gap = try #require(picture.firstBlankRow(from: firstTop))
        let secondTop = try #require(picture.firstInkRow(from: gap))
        #expect(abs((secondTop - firstTop) - 150) <= 1, "\(secondTop - firstTop)")
        #expect(abs(TextRasterizer.naturalSize(text).height - (300 + 2 * TextRasterizer.frameInset)) <= 1)

        text.lineHeight = 1.0
        let tight = Self.draw(text)
        let top = try #require(tight.firstInkRow())
        let between = try #require(tight.firstBlankRow(from: top))
        let next = try #require(tight.firstInkRow(from: between))
        #expect(abs((next - top) - 100) <= 1)
    }

    @Test func tightLeadingNeverCutsTheLettersOff() throws {
        // 0.9 is tighter than SF's own ascent and descent: the ink of "Ågy"
        // reaches past its line box above and below, and is still drawn.
        var text = TextContent(string: "Ågy", fontSize: 100)
        let natural = try #require(Self.draw(text).ink)
        text.lineHeight = 0.9
        let picture = Self.draw(text)
        let tight = try #require(picture.ink)
        #expect(abs(tight.height - natural.height) <= 1, "the whole of every letter is drawn")
        #expect(tight.minY > 0 && Int(tight.maxY) < picture.height, "with room to spare inside the box")
    }

    @Test func theSameSettingMeasuresTheSameEverywhere() {
        // The box the panel stores, the field you type in and the frame drawn
        // all ask the same measurer.
        var text = TextContent(string: "Ship it\nfaster", fontSize: 120, weight: .semibold)
        text.tracking = -0.026
        text.lineHeight = 1.02
        let size = TextRasterizer.naturalSize(text)
        #expect(TextBlockMetrics.laidOutHeight(text, width: size.width - 2 * TextRasterizer.frameInset)
                <= size.height)
        // Two lines: their ink is in the picture.
        let picture = Self.draw(text)
        #expect((picture.ink?.height ?? 0) > 200)
    }

    // MARK: - New York

    @Test func newYorkDrawsAsNewYork() {
        let font = TextRasterizer.font(for: TextContent(string: "Field", fontName: "New York", fontSize: 128))
        #expect((CTFontCopyPostScriptName(font) as String).contains("NewYork"))
        let medium = TextRasterizer.font(for: TextContent(string: "Field", fontName: "New York",
                                                          fontSize: 128, weight: .medium))
        #expect((CTFontCopyPostScriptName(medium) as String) == ".NewYork-Medium",
                "the mock's New York Medium, not a grade of it")
        // Not a fallback: the serif is not Helvetica's shape.
        let helvetica = TextContent(string: "Field notes", fontName: "Helvetica", fontSize: 128)
        var serif = helvetica
        serif.fontName = "New York"
        #expect(TextRasterizer.naturalSize(serif).width != TextRasterizer.naturalSize(helvetica).width)
    }

    // MARK: - SF Pro's Display cut

    /// The optical size SF is drawn at, from the font's own variation axis.
    private static func opticalSize(_ font: CTFont) -> Double {
        let axes = CTFontCopyVariation(font) as? [NSNumber: NSNumber] ?? [:]
        return axes[NSNumber(value: 0x6F70737A)]?.doubleValue ?? -1   // 'opsz'
    }

    @Test func sfAtTitleSizesIsTheDisplayCut() throws {
        let title = TextContent(string: "Redline", fontSize: 184, weight: .semibold)
        let ours = TextRasterizer.font(for: title)
        let system = try #require(CTFontCreateUIFontForLanguage(.system, 184, nil))
        #expect(Self.opticalSize(ours) == Self.opticalSize(system))
        #expect(Self.opticalSize(ours) >= 20, "the Display cut starts at 20 points")
        #expect(Self.opticalSize(TextRasterizer.font(for: TextContent(string: "a", fontSize: 13))) < 20,
                "small type keeps the Text cut")

        // Drawn beside the system's own 184 point semibold: the same picture.
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(
            CTFontCopyFontDescriptor(system),
            [kCTFontTraitsAttribute: [kCTFontWeightTrait: TextWeight.semibold.fontWeightTrait]] as CFDictionary)
        let reference = CTFontCreateWithFontDescriptor(descriptor, 184, nil)
        let ourLine = CTLineCreateWithAttributedString(TextRasterizer.attributedString(title))
        let referenceLine = CTLineCreateWithAttributedString(NSAttributedString(
            string: title.string, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): reference]))
        #expect(CTLineGetTypographicBounds(ourLine, nil, nil, nil)
                == CTLineGetTypographicBounds(referenceLine, nil, nil, nil))
        // ...which the Text cut forced onto the same size is not.
        let text = CTFontCreateCopyWithAttributes(
            reference, 184, nil,
            CTFontDescriptorCreateWithAttributes([kCTFontVariationAttribute: [0x6F70737A: 17]] as CFDictionary))
        let textLine = CTLineCreateWithAttributedString(NSAttributedString(
            string: title.string, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): text]))
        #expect(CTLineGetTypographicBounds(textLine, nil, nil, nil)
                != CTLineGetTypographicBounds(ourLine, nil, nil, nil))
    }

    // MARK: - A ramp through the letters

    private static func ramped(length: Double? = nil, shift: Double? = nil) -> TextContent {
        var text = TextContent(string: "MMMMMM", fontSize: 100, colorHex: redToBlue.hex, weight: .bold)
        text.fill = redToBlue
        text.fillLength = length
        text.fillShift = shift
        return text
    }

    @Test func aGradientRunsThroughTheWords() throws {
        let picture = Self.draw(Self.ramped())
        let ink = try #require(picture.ink)
        let band = Int(ink.width * 0.12)
        let left = picture.meanInk(columns: Int(ink.minX)..<Int(ink.minX) + band)
        let right = picture.meanInk(columns: Int(ink.maxX) - band..<Int(ink.maxX))
        #expect(left.r > 180 && left.b < 80, "the first letter is the ramp's start \(left)")
        #expect(right.b > 180 && right.r < 80, "the last letter is its end \(right)")
    }

    @Test func aFlatColourStillDrawsFlat() throws {
        var text = Self.ramped()
        text.colorHex = "#00FF00"   // recoloured flat: the ramp is not drawn
        let picture = Self.draw(text)
        let ink = try #require(picture.ink)
        let mean = picture.meanInk(columns: Int(ink.minX)..<Int(ink.maxX))
        #expect(mean.g > 200 && mean.r < 30 && mean.b < 30)
    }

    @Test func slidingTheRampMovesTheColoursAcrossTheWords() throws {
        let start = Self.draw(Self.ramped(length: 2, shift: 0))
        let end = Self.draw(Self.ramped(length: 2, shift: 1))
        let ink = try #require(start.ink)
        let band = Int(ink.width * 0.12)
        let leftColumns = Int(ink.minX)..<Int(ink.minX) + band
        let rightColumns = Int(ink.maxX) - band..<Int(ink.maxX)
        // A ramp twice the words' length: at nought they show its red half,
        // at one its blue half.
        #expect(start.meanInk(columns: leftColumns).r > 200)
        #expect(start.meanInk(columns: rightColumns).r > start.meanInk(columns: rightColumns).b)
        #expect(end.meanInk(columns: rightColumns).b > 200)
        #expect(end.meanInk(columns: leftColumns).b > end.meanInk(columns: leftColumns).r)
    }

    @Test func eachLineCarriesItsOwnRamp() throws {
        var text = Self.ramped()
        text.string = "MMMMMM\nMM"
        text.alignment = .center
        let picture = Self.draw(text)
        let ink = try #require(picture.ink)
        // The short second line runs red to blue across its own two letters,
        // the way each line of a CSS `background-clip: text` title does.
        let gap = try #require(picture.firstBlankRow(from: Int(ink.minY)))
        let secondLineTop = try #require(picture.firstInkRow(from: gap))
        let rows = Pixels(TextRasterizer.rasterize(text, size: TextRasterizer.naturalSize(text))!)
        var left = (r: 0.0, b: 0.0), right = (r: 0.0, b: 0.0)
        var lineInk = (minX: Int.max, maxX: -1)
        for y in secondLineTop..<rows.height {
            for x in 0..<rows.width where rows.alpha(x, y) > 230 {
                lineInk.minX = min(lineInk.minX, x); lineInk.maxX = max(lineInk.maxX, x)
            }
        }
        let band = (lineInk.maxX - lineInk.minX) / 6
        for y in secondLineTop..<rows.height {
            for x in lineInk.minX..<(lineInk.minX + band) where rows.alpha(x, y) > 230 {
                let i = (y * rows.width + x) * 4
                left.r += Double(rows.data[i]); left.b += Double(rows.data[i + 2])
            }
            for x in (lineInk.maxX - band)...lineInk.maxX where rows.alpha(x, y) > 230 {
                let i = (y * rows.width + x) * 4
                right.r += Double(rows.data[i]); right.b += Double(rows.data[i + 2])
            }
        }
        #expect(left.r > left.b * 2, "the short line starts red")
        #expect(right.b > right.r * 2, "and ends blue")
    }

    @Test func revealPiecesWearTheRampToo() throws {
        let text = Self.ramped()
        let size = TextRasterizer.naturalSize(text)
        let pieces = try #require(TextRasterizer.revealPieces(text, size: size, unit: .letter))
        #expect(pieces.pieces.count == 6)
        let context = CIContext()
        func mean(_ piece: TextRevealPieces.Piece) throws -> (r: Double, g: Double, b: Double) {
            let image = try #require(context.createCGImage(piece.image, from: piece.image.extent))
            let pixels = Pixels(image)
            return pixels.meanInk(columns: 0..<pixels.width)
        }
        let ordered = pieces.pieces.sorted { $0.box.minX < $1.box.minX }
        let first = try mean(try #require(ordered.first))
        let last = try mean(try #require(ordered.last))
        #expect(first.r > first.b, "the first letter arrives red \(first)")
        #expect(last.b > last.r, "the last arrives blue \(last)")
    }

    @Test func spacingCarriesIntoRevealPieces() throws {
        var text = TextContent(string: "Redline", fontSize: 100)
        let plain = try #require(TextRasterizer.revealPieces(text, size: TextRasterizer.naturalSize(text),
                                                             unit: .letter))
        text.tracking = 0.2
        let spaced = try #require(TextRasterizer.revealPieces(text, size: TextRasterizer.naturalSize(text),
                                                              unit: .letter))
        func span(_ pieces: TextRevealPieces) -> CGFloat {
            let boxes = pieces.pieces.map(\.box)
            return (boxes.map(\.maxX).max() ?? 0) - (boxes.map(\.minX).min() ?? 0)
        }
        #expect(span(spaced) - span(plain) > 100, "six gaps of twenty points")
    }
}
