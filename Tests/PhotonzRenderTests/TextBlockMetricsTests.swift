import AppKit
import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import PhotonzCore
@testable import PhotonzRender

/// Typing a label and placing it have to be one shape.
///
/// The field you type in and the picture that lands are laid out by two
/// different engines — AppKit's while you type, CoreText's when it renders —
/// and they only agree if they are handed the same face and the same width.
/// They used not to be: the field asked for the font at (size x zoom), which
/// SF spaces differently than the document size, so the box drifted by a few
/// percent per step of zoom and a long label broke at a different word.
@Suite struct TextBlockMetricsTests {

    private static let samples = [
        "",
        "OK",
        "Primary button",
        "Tap here to continue to the next screen and then confirm the details before you finish",
        "Save and continue to review the specification handoff notes for engineering",
        "Wrapping label that is deliberately long enough to break across several lines in a narrow box",
    ]

    private static let zooms: [CGFloat] = [0.25, 0.5, 0.75, 1, 1.5, 2, 3]

    /// The lines the renderer draws inside a box of `size`.
    private func rendered(_ text: TextContent, in size: CGSize) -> [String] {
        let framesetter = CTFramesetterCreateWithAttributedString(TextRasterizer.measuringString(text))
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0),
                                             CGPath(rect: CGRect(origin: .zero, size: size), transform: nil), nil)
        let lines = CTFrameGetLines(frame) as? [CTLine] ?? []
        let string = text.string as NSString
        return lines.map {
            let range = CTLineGetStringRange($0)
            return string.substring(with: NSRange(location: range.location, length: range.length))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// The lines the inline editor lays the draft out as, at `zoom`: the same
    /// two steps `CanvasNSView` takes — the document-size face scaled by the
    /// zoom, in a container as wide as the committed frame.
    private func drafted(_ text: TextContent, frame: CGSize, zoom: CGFloat) -> [String] {
        var transform = AffineTransform()
        transform.scale(zoom)
        let descriptor = (TextRasterizer.faceDescriptor(for: text) as NSFontDescriptor)
            .withSize(text.fontSize)
        guard let font = NSFont(descriptor: descriptor, textTransform: transform) else {
            Issue.record("no draft face for \(text.fontName)")
            return []
        }
        let storage = NSTextStorage(string: text.string, attributes: [.font: font])
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: frame.width * zoom,
                                                     height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        layout.ensureLayout(for: container)
        var lines: [String] = []
        var glyph = 0
        let string = text.string as NSString
        while glyph < layout.numberOfGlyphs {
            var effective = NSRange()
            _ = layout.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: &effective)
            let characters = layout.characterRange(forGlyphRange: effective, actualGlyphRange: nil)
            lines.append(string.substring(with: characters)
                .trimmingCharacters(in: .whitespacesAndNewlines))
            glyph = NSMaxRange(effective)
        }
        return lines
    }

    @MainActor
    @Test(arguments: [false, true]) func aDraftBreaksAtTheSameWordsAsThePlacedLabel(hugging: Bool) {
        var failures: [String] = []
        for weight in TextWeight.allCases {
            for fontSize in [CGFloat(11), 14, 24, 48] {
                for string in Self.samples where !string.isEmpty {
                    let text = TextContent(string: string, fontSize: fontSize, weight: weight)
                    let frame = TextBlockMetrics.frameSize(for: text, maxWidth: 720,
                                                          hugsShortWords: hugging)
                    let placed = rendered(text, in: frame)
                    for zoom in Self.zooms where drafted(text, frame: frame, zoom: zoom) != placed {
                        failures.append("\(weight)/\(fontSize)pt at \(zoom)x")
                    }
                }
            }
        }
        let report = failures.prefix(6).joined(separator: ", ")
        #expect(failures.isEmpty, "\(failures.count) drafts wrap somewhere else: \(report)")
    }

    /// Nothing the measurement counted may fall out the bottom of the box it
    /// sized, at any font in the picker.
    @Test(arguments: [false, true]) func aMeasuredFrameHoldsEveryLineItNeeds(hugging: Bool) {
        var failures: [String] = []
        for family in TextStyles.fonts {
            for fontSize in [CGFloat(11), 14, 24, 48] {
                for string in Self.samples {
                    let text = TextContent(string: string, fontName: family, fontSize: fontSize)
                    let frame = TextBlockMetrics.frameSize(for: text, maxWidth: 720,
                                                          hugsShortWords: hugging)
                    let placed = rendered(text, in: frame)
                    let joined = placed.joined(separator: " ")
                    let wanted = string.split(separator: " ").joined(separator: " ")
                    if joined != wanted {
                        failures.append("\(family)/\(fontSize)pt dropped words in \(frame.width)x\(frame.height)")
                    }
                }
            }
        }
        let report = failures.prefix(6).joined(separator: ", ")
        #expect(failures.isEmpty, "\(failures.count) boxes clipped their text: \(report)")
    }

    // MARK: The wrap cap

    @Test func aNewBlockWrapsAtSixtyPercentOfTheCanvas() {
        let width = TextBlockMetrics.wrapWidth(origin: CGPoint(x: 0, y: 0),
                                               in: CGSize(width: 1000, height: 800))
        #expect(width == 600)
    }

    @Test func aBlockStartedNearTheRightEdgeWrapsAtTheEdge() {
        let width = TextBlockMetrics.wrapWidth(origin: CGPoint(x: 800, y: 0),
                                               in: CGSize(width: 1000, height: 800))
        #expect(width == 200)
    }

    @Test func aBlockStartedPastTheEdgeStillGetsTheMinimumWidth() {
        let width = TextBlockMetrics.wrapWidth(origin: CGPoint(x: 995, y: 0),
                                               in: CGSize(width: 1000, height: 800))
        #expect(width == TextRasterizer.minimumTextWidth)
    }

    @Test func theRendererAndTheTypedFieldFloorTextAtTheSameWidth() {
        // One number, in one place: the canvas drag and the W field both stop
        // here, so a width you type and a width you drag agree.
        #expect(TextRasterizer.minimumTextWidth == TextMeasurement.minimumWidth)
    }

    // MARK: A short label is as wide as its word

    @Test func aShortLabelIsAsWideAsItsWord() {
        let text = TextContent(string: "OK", fontSize: 14)
        let box = TextBlockMetrics.frameSize(for: text, maxWidth: 600, hugsShortWords: true)
        // Exactly the width the same word gets inside a starter component,
        // which measures with no floor at all.
        #expect(box.width == TextRasterizer.naturalSize(text).width)
        #expect(box.width < TextRasterizer.minimumTextWidth)
    }

    @Test func withoutTheHuggingRuleAShortLabelStillGetsTheOldFloor() {
        let text = TextContent(string: "OK", fontSize: 14)
        #expect(TextBlockMetrics.frameSize(for: text, maxWidth: 600).width
                == TextRasterizer.minimumTextWidth)
    }

    @Test func aLabelWiderThanTheFloorIsUnaffectedByTheRule() {
        let text = TextContent(string: "Primary button", fontSize: 14)
        #expect(TextBlockMetrics.frameSize(for: text, maxWidth: 600, hugsShortWords: true)
                == TextBlockMetrics.frameSize(for: text, maxWidth: 600))
    }

    @Test func anEmptyFieldIsStillOneLineTall() {
        let text = TextContent(string: "", fontSize: 14)
        let hugging = TextBlockMetrics.frameSize(for: text, maxWidth: 600, hugsShortWords: true)
        #expect(hugging.height == TextBlockMetrics.frameSize(for: text, maxWidth: 600).height)
        #expect(hugging.width > 0)
    }

    @Test func aShortLabelThatHugsItsWordKeepsHuggingWhenItIsReworded() {
        let word = TextContent(string: "OK", fontSize: 14)
        let box = TextBlockMetrics.frameSize(for: word, maxWidth: 600, hugsShortWords: true)
        let room = TextBlockMetrics.roomyBox(for: word,
                                             frame: CGRect(origin: .zero, size: box))
        #expect(room.width == nil)
        #expect(room.height == nil)
        // Re-worded, it is as wide as the new words and still on one line.
        let longer = TextContent(string: "Save changes", fontSize: 14)
        let reworded = TextBlockMetrics.frameSize(for: longer, maxWidth: 600,
                                                  roomyWidth: room.width,
                                                  roomyHeight: room.height,
                                                  hugsShortWords: true)
        #expect(reworded.width == TextRasterizer.naturalSize(longer).width)
        #expect(reworded.height == box.height)
    }

    @Test func aShortLabelSomebodyMadeWiderKeepsTheWidthItWasGiven() {
        let word = TextContent(string: "OK", fontSize: 14)
        let frame = CGRect(x: 0, y: 0, width: TextRasterizer.minimumTextWidth, height: 22)
        let room = TextBlockMetrics.roomyBox(for: word, frame: frame)
        #expect(room.width == TextRasterizer.minimumTextWidth)
        let reworded = TextBlockMetrics.frameSize(for: word, maxWidth: 600,
                                                  roomyWidth: room.width,
                                                  hugsShortWords: true)
        #expect(reworded.width == TextRasterizer.minimumTextWidth)
    }

    @Test func aWrappedParagraphWhoseLongestLineNearlyFillsItIsStillRoomy() {
        let text = TextContent(string: Self.samples[3], fontSize: 14)
        let frame = CGRect(x: 0, y: 0, width: 240,
                           height: TextBlockMetrics.laidOutHeight(TextContent(string: Self.samples[3],
                                                                              fontSize: 14),
                                                                  width: 240))
        // The words need far more than 240 on one line, so this width was
        // chosen: re-wording it re-wraps in place instead of snapping out to
        // one long line.
        #expect(TextBlockMetrics.roomyBox(for: text, frame: frame).width == 240)
    }

    // MARK: Boxes with room to spare

    @Test func aBoxThatHugsItsWordsReportsNoRoom() {
        let text = TextContent(string: "Primary button")
        let hugged = TextBlockMetrics.frameSize(for: text, maxWidth: 720)
        let room = TextBlockMetrics.roomyBox(for: text, frame: CGRect(origin: .zero, size: hugged))
        #expect(room.width == nil)
        #expect(room.height == nil)
    }

    @Test func aStretchedBoxKeepsTheRoomItWasGiven() {
        let text = TextContent(string: "Primary button")
        let frame = CGRect(x: 0, y: 0, width: 500, height: 200)
        let room = TextBlockMetrics.roomyBox(for: text, frame: frame)
        #expect(room.width == 500)
        #expect(room.height == 200)
        let size = TextBlockMetrics.frameSize(for: text, maxWidth: 720,
                                             roomyWidth: room.width, roomyHeight: room.height)
        #expect(size == CGSize(width: 500, height: 200))
    }

    // MARK: Where the first line sits

    @Test func textThatStartsAtTheTopHasNoOffset() {
        let text = TextContent(string: "Primary button", verticalAlignment: .top)
        #expect(TextBlockMetrics.topInset(for: text, in: CGSize(width: 500, height: 200)) == 0)
    }

    @Test func textWithNoPlacementStartsAtTheTop() {
        let text = TextContent(string: "Primary button")
        #expect(TextBlockMetrics.topInset(for: text, in: CGSize(width: 500, height: 200)) == 0)
    }

    @Test func centredTextSitsHalfTheSlackDown() {
        let text = TextContent(string: "Primary button", verticalAlignment: .middle)
        let box = CGSize(width: 500, height: 200)
        let inset = TextBlockMetrics.topInset(for: text, in: box)
        let needed = TextBlockMetrics.laidOutHeight(text, width: box.width)
        #expect(abs(inset - (box.height - needed) / 2) <= 0.5)
    }

    @Test func bottomTextSitsOnTheFloorOfItsBox() {
        let text = TextContent(string: "Primary button", verticalAlignment: .bottom)
        let box = CGSize(width: 500, height: 200)
        let inset = TextBlockMetrics.topInset(for: text, in: box)
        let needed = TextBlockMetrics.laidOutHeight(text, width: box.width)
        #expect(inset == box.height - needed)
    }

    @Test func textTallerThanItsBoxStaysAtTheTop() {
        let text = TextContent(string: Self.samples[3], fontSize: 48, verticalAlignment: .middle)
        #expect(TextBlockMetrics.topInset(for: text, in: CGSize(width: 200, height: 40)) == 0)
    }
}
