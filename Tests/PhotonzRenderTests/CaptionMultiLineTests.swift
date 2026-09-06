import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// A caption that holds more than one line, measured off real pixels.
///
/// Return types a line into a caption (user request 2026-09-06), so the pill
/// has to be as wide as its longest line, tall enough for all of them, and it
/// has to CENTRE them: left-aligned lines in a capsule read as a paragraph
/// that lost its box. All of that is checked against drawn ink rather than
/// reasoned about, because all of it is visible before it is a number.
@Suite("Caption with more than one line")
struct CaptionMultiLineTests {

    private let background = CGColor(gray: 0.5, alpha: 1)

    private func content(_ caption: String, fontSize: CGFloat = 20) -> AnnotationContent {
        var content = AnnotationContent(shape: .arrow, strokeWidth: 4, colorHex: "#FF3B30")
        content.caption = caption
        content.captionFontSize = fontSize
        return content
    }

    /// Draws one caption pill on an opaque grey field, centred, and returns the
    /// pixels with the pill's measured size and where its centre landed.
    private func render(_ caption: String, fontSize: CGFloat = 20)
        -> (px: Pixels, pill: CGSize, center: CGPoint)? {
        let content = content(caption, fontSize: fontSize)
        let pill = CaptionMetrics.pillSize(for: caption, in: content)
        let width = Int((pill.width + 60).rounded(.up))
        let height = Int((pill.height + 60).rounded(.up))
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(background)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        let tone = content.captionChipColor
        let center = CGPoint(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
        PillRasterizer.draw(caption, at: center, chipSize: pill, fontSize: fontSize,
                            borderWidth: content.captionBorderWidth,
                            fill: CGColor(srgbRed: tone.r, green: tone.g, blue: tone.b,
                                          alpha: AnnotationContent.captionChipOpacity),
                            border: CGColor(srgbRed: 1, green: 0.23, blue: 0.19, alpha: 1),
                            textColorHex: AnnotationContent.captionTextColorHex,
                            cornerRadius: content.captionCornerRadius(pillHeight: pill.height),
                            in: context)
        guard let image = context.makeImage() else { return nil }
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let read = CGContext(data: &data, width: width, height: height,
                                   bitsPerComponent: 8, bytesPerRow: width * 4,
                                   space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        read.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (Pixels(data: data, width: width, height: height), pill, center)
    }

    private struct Pixels {
        let data: [UInt8]
        let width: Int
        let height: Int

        /// The white caption text, not the dark red chip and not the grey field.
        func isText(x: Int, y: Int) -> Bool {
            let i = (y * width + x) * 4
            let r = Int(data[i]), g = Int(data[i + 1]), b = Int(data[i + 2])
            return r > 180 && g > 180 && b > 180
        }

        /// The pill's own ink: red-dominant border and fill.
        func isInk(x: Int, y: Int) -> Bool {
            let i = (y * width + x) * 4
            let r = Int(data[i]), g = Int(data[i + 1]), b = Int(data[i + 2])
            return r > g + 25 && r > b + 25
        }

        func bounds(of predicate: (Int, Int) -> Bool) -> CGRect {
            var minX = width, maxX = -1, minY = height, maxY = -1
            for y in 0..<height {
                for x in 0..<width where predicate(x, y) {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
            guard maxX >= minX, maxY >= minY else { return .zero }
            return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        }

        /// One band per row of type: the runs of rows that carry any white.
        func textBands() -> [CGRect] {
            var bands: [CGRect] = []
            var top: Int?
            for y in 0...height {
                let inked = y < height && (0..<width).contains { isText(x: $0, y: y) }
                if inked, top == nil {
                    top = y
                } else if !inked, let start = top {
                    var minX = width, maxX = -1
                    for row in start..<y {
                        for x in 0..<width where isText(x: x, y: row) {
                            minX = min(minX, x); maxX = max(maxX, x)
                        }
                    }
                    bands.append(CGRect(x: minX, y: start, width: maxX - minX + 1,
                                        height: y - start))
                    top = nil
                }
            }
            return bands
        }
    }

    // MARK: The pill

    /// The pill is sized to the LONGEST line, not to every word laid end to
    /// end: breaking a label in two makes it narrower and taller.
    @Test func thePillIsAsWideAsItsLongestLine() {
        let flat = CaptionMetrics.pillSize(for: "Save the changes", in: content("Save the changes"))
        let split = CaptionMetrics.pillSize(for: "Save\nthe changes",
                                            in: content("Save\nthe changes"))
        let longest = CaptionMetrics.pillSize(for: "the changes", in: content("the changes"))
        #expect(abs(split.width - longest.width) < 1)
        #expect(split.width < flat.width)
        #expect(split.height > flat.height)
    }

    /// Each extra line adds the same height, so the lines inside are evenly
    /// spaced and the pill does not creep.
    @Test func everyExtraLineAddsTheSameHeight() {
        let heights = ["a", "a\nb", "a\nb\nc", "a\nb\nc\nd"].map {
            CaptionMetrics.pillSize(for: $0, in: content($0)).height
        }
        let steps = zip(heights.dropFirst(), heights).map { $0 - $1 }
        for step in steps {
            #expect(abs(step - steps[0]) < 1.5, "line steps were \(steps)")
        }
        #expect(steps[0] > 0)
    }

    /// What PhotonzCore reserves without measuring a glyph has to hold what the
    /// rasterizer really draws, at every line count and every caption size, or
    /// a tall pill clips at the edge of its own layer.
    @Test func theReservedBoxHoldsTheDrawnPillAtEveryLineCount() {
        for caption in ["a\nb", "Save\nthe changes", "one\ntwo\nthree\nfour",
                        "a\n\nb", "A much longer caption\nand a second line"] {
            for fontSize in [8.0, 10.0, 20.0, 48.0, 90.0] {
                let content = content(caption, fontSize: fontSize)
                let drawn = CaptionMetrics.pillSize(for: caption, in: content)
                let reserved = content.estimatedCaptionSize
                #expect(reserved.height >= drawn.height,
                        "\(caption.debugDescription) at \(fontSize)pt draws \(drawn.height) tall, reserved \(reserved.height)")
                #expect(reserved.width >= drawn.width,
                        "\(caption.debugDescription) at \(fontSize)pt draws \(drawn.width) wide, reserved \(reserved.width)")
            }
        }
    }

    // MARK: The drawn lines

    @Test func twoLinesDrawAsTwoRowsOfType() {
        guard let (px, pill, center) = render("Save\nthe changes") else {
            Issue.record("expected a rendered pill")
            return
        }
        let bands = px.textBands()
        #expect(bands.count == 2, "drew \(bands.count) rows of type")
        guard bands.count == 2 else { return }
        // Both rows sit inside the pill, with the padding kept above and below.
        let ink = px.bounds(of: { px.isInk(x: $0, y: $1) })
        #expect(ink.minY < bands[0].minY)
        #expect(ink.maxY > bands[1].maxY)
        #expect(abs(ink.height - pill.height) <= 3, "pill inked \(ink.height) for \(pill.height)")
        // Centred, not ragged left.
        for band in bands {
            #expect(abs(band.midX - center.x) <= 2,
                    "row at \(band.midX) is not centred on \(center.x)")
        }
        #expect(bands[1].midX != bands[0].midX)
    }

    @Test func fourLinesDrawEvenlySpacedAndCentred() {
        guard let (px, _, center) = render("one\ntwo\nthree\nfour") else {
            Issue.record("expected a rendered pill")
            return
        }
        let bands = px.textBands()
        #expect(bands.count == 4, "drew \(bands.count) rows of type")
        guard bands.count == 4 else { return }
        let steps = zip(bands.dropFirst(), bands).map { $0.midY - $1.midY }
        for step in steps {
            #expect(abs(step - steps[0]) <= 2, "row spacing was \(steps)")
        }
        for band in bands {
            #expect(abs(band.midX - center.x) <= 2,
                    "row at \(band.midX) is not centred on \(center.x)")
        }
    }

    /// A caption with no Return in it draws exactly where it always did: the
    /// single line ink centring is untouched by any of this.
    @Test func aSingleLineCaptionStillDrawsOneCentredRow() {
        guard let (px, _, center) = render("Save the changes") else {
            Issue.record("expected a rendered pill")
            return
        }
        let bands = px.textBands()
        #expect(bands.count == 1)
        guard let band = bands.first else { return }
        #expect(abs(band.midX - center.x) <= 2)
    }

    /// A four line pill has straight sides. Rounding it by half its own height
    /// draws an egg standing on end, which is what the badge floor stops a
    /// short caption doing and has to stop a tall one doing too.
    @Test func aTallPillHasStraightSidesRatherThanBeingAnEgg() {
        guard let (px, pill, _) = render("one\ntwo\nthree\nfour") else {
            Issue.record("expected a rendered pill")
            return
        }
        let ink = px.bounds(of: { px.isInk(x: $0, y: $1) })
        let column = Int(ink.minX) + 1
        let rows = (0..<px.height).reduce(0) { $0 + (px.isInk(x: column, y: $1) ? 1 : 0) }
        #expect(CGFloat(rows) > pill.height / 3,
                "the left edge stands \(rows) tall in a pill of \(pill.height)")
    }

    // MARK: The text that lands

    /// The pill measures the string it will COMMIT as, so the lines it is sized
    /// for are the lines that land.
    @Test func committedTextKeepsItsLines() {
        #expect(CaptionMetrics.committedText("two\nlines") == "two\nlines")
        #expect(CaptionMetrics.committedText("\nSave\n") == "Save")
    }
}
