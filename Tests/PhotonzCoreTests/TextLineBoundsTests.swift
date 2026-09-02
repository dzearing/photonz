import CoreGraphics
import Foundation
import PhotonzCore
import Testing

private typealias Capture = PaintedCapture

/// A line of stand-in text: words of `glyphs` strokes separated by a word
/// space, on one baseline. Returns the ink box the line should read as.
@discardableResult
private func line(_ c: inout Capture, x: Int, y: Int, words: [Int], space: Int = 5,
                  tone: UInt8 = 40, height: Int = 14) -> CGRect {
    var cursor = x
    for (i, glyphs) in words.enumerated() {
        c.text(x: cursor, y: y, glyphs: glyphs, tone: tone, height: height)
        cursor += glyphs * 8 - 4
        if i < words.count - 1 { cursor += space }
    }
    return CGRect(x: x, y: y, width: cursor - x, height: height)
}

private func expectRect(_ rect: CGRect?, _ expected: CGRect, slack: CGFloat = 0,
                        sourceLocation: SourceLocation = #_sourceLocation) {
    guard let rect else {
        Issue.record("expected \(expected), got nothing", sourceLocation: sourceLocation)
        return
    }
    let matches = abs(rect.minX - expected.minX) <= slack
        && abs(rect.minY - expected.minY) <= slack
        && abs(rect.width - expected.width) <= slack * 2
        && abs(rect.height - expected.height) <= slack * 2
    if !matches {
        Issue.record("expected \(expected), got \(rect)", sourceLocation: sourceLocation)
    }
}

/// These scenes are 1x: a word space is 5 px and the visible gap 8, the
/// numbers `AlignmentCheck.visibleGap` names for an unscaled capture.
private let gap = 8.0
private let minElement = 10.0

private func read(_ c: Capture, _ x: Int, _ y: Int) -> CGRect? {
    TextLineBounds.detect(at: CGPoint(x: x, y: y), in: c.luma, gap: gap, minElement: minElement)
}

@Suite("TextLineBounds: a line of text reads as one element")
struct TextLineBoundsTests {

    @Test func aLineReadsItsInkBox() {
        var c = Capture(w: 400, h: 200)
        let label = line(&c, x: 100, y: 100, words: [5, 3, 6])
        expectRect(read(c, 150, 107), label)
    }

    @Test func aWordSpaceDoesNotSplitTheLine() {
        // The pointer sits in the space between the first two words: the
        // whole line answers, not the word on either side and not nothing.
        var c = Capture(w: 400, h: 200)
        let label = line(&c, x: 100, y: 100, words: [5, 3, 6])
        expectRect(read(c, 138, 107), label)
        // And from the last word.
        expectRect(read(c, 200, 107), label)
    }

    @Test func aVisibleGapEndsTheLine() {
        // Two labels on one baseline, a visible gap apart, are two lines.
        var c = Capture(w: 500, h: 200)
        let first = line(&c, x: 100, y: 100, words: [5, 3])
        let second = line(&c, x: Int(first.maxX) + 30, y: 100, words: [4, 4])
        expectRect(read(c, 120, 107), first)
        expectRect(read(c, Int(second.midX), 107), second)
    }

    @Test func stackedLinesStaySeparate() {
        // A paragraph's leading is a few clean rows; the line under the
        // pointer answers alone.
        var c = Capture(w: 400, h: 300)
        let first = line(&c, x: 100, y: 100, words: [5, 3, 6])
        let second = line(&c, x: 100, y: 122, words: [4, 7])
        expectRect(read(c, 150, 107), first)
        expectRect(read(c, 150, 129), second)
    }

    @Test func anAccentStaysWithItsLine() {
        // A dot or an accent sits a pixel or two above a letter. It belongs to
        // the line, so the line's top is the accent's top.
        var c = Capture(w: 400, h: 200)
        let label = line(&c, x: 100, y: 100, words: [5, 3])
        c.fill(CGRect(x: 108, y: 95, width: 4, height: 3), 40)
        expectRect(read(c, 120, 107), CGRect(x: 100, y: 95, width: label.width, height: 19))
    }

    @Test func lightTextOnADarkFillReads() {
        var c = Capture(w: 400, h: 200)
        c.fill(CGRect(x: 0, y: 0, width: 400, height: 200), 30)
        let label = line(&c, x: 100, y: 100, words: [5, 3, 6], tone: 250)
        expectRect(read(c, 150, 107), label)
    }

    @Test func aPointerOffTheLineReadsNothing() {
        var c = Capture(w: 400, h: 200)
        let label = line(&c, x: 100, y: 100, words: [5, 3, 6])
        #expect(read(c, 150, 88) == nil)
        #expect(read(c, 150, 126) == nil)
        #expect(read(c, Int(label.maxX) + 30, 107) == nil)
    }

    @Test func flatBackgroundReadsNothing() {
        let c = Capture(w: 400, h: 200)
        #expect(read(c, 150, 107) == nil)
    }

    @Test func aHairlineReadsNothing() {
        // A divider is ink, but it is one or two rows tall and has no letters.
        var c = Capture(w: 400, h: 200)
        c.rule(y: 100, x0: 40, x1: 360, tone: 200, thickness: 1)
        c.rule(y: 150, x0: 40, x1: 360, tone: 120, thickness: 2)
        #expect(read(c, 150, 100) == nil)
        #expect(read(c, 150, 151) == nil)
    }

    @Test func aSolidBlockReadsNothing() {
        // A filled pill or bar has no gaps between letters. Not text.
        var c = Capture(w: 400, h: 200)
        c.fill(CGRect(x: 100, y: 90, width: 84, height: 24), 60)
        #expect(read(c, 140, 102) == nil)
    }

    @Test func aRuleUnderTheLineIsNotPartOfIt() {
        // An underline or a divider hugging the baseline reads as a rule and
        // stops the band, so the line's height is the letters' height.
        var c = Capture(w: 400, h: 200)
        let label = line(&c, x: 100, y: 100, words: [5, 3, 6])
        c.rule(y: 115, x0: 100, x1: Int(label.maxX), tone: 40, thickness: 1)
        expectRect(read(c, 150, 107), label)
    }

    @Test func aTallBlockIsNotALine() {
        // Something taller than any line of text, even with gaps in it, is a
        // picture or a panel rather than words.
        var c = Capture(w: 400, h: 400)
        for i in 0..<6 {
            c.fill(CGRect(x: 100 + i * 12, y: 50, width: 6, height: 200), 40)
        }
        #expect(read(c, 130, 150) == nil)
    }
}

@Suite("ElementBounds offers a text line as a rung")
struct ElementBoundsTextRungTests {

    private func ladder(_ c: Capture, _ x: Int, _ y: Int) -> [CGRect] {
        ElementBounds.candidates(at: CGPoint(x: x, y: y), in: c.map, luma: c.luma,
                                 minElement: minElement, textGap: gap)
    }

    @Test func aHeadingOnThePageIsAnElement() {
        // Nothing borders a heading, so the pair rule reads nothing here today.
        var c = Capture(w: 500, h: 300)
        let heading = line(&c, x: 60, y: 40, words: [7], height: 24)
        let rungs = ladder(c, 90, 52)
        #expect(rungs.count == 1)
        expectRect(rungs.first, heading)
    }

    @Test func aRowLabelIsTheFirstRungAndTheRowTheNext() {
        // The settings-row scene from ElementBoundsTests, with a label in the
        // middle row. Over the label the ladder starts at the label; `]`
        // climbs to the row, then the card, as before.
        var c = Capture(w: 700, h: 400)
        let card = CGRect(x: 40, y: 40, width: 620, height: 264)
        c.box(card, border: 200, width: 1)
        c.rule(y: 128, x0: 70, x1: 630, tone: 220)
        c.rule(y: 216, x0: 70, x1: 630, tone: 220)
        let label = line(&c, x: 90, y: 165, words: [6, 2, 5])
        let rungs = ladder(c, 110, 172)
        #expect(rungs.count >= 2)
        expectRect(rungs.first, label)
        if rungs.count >= 2 {
            let row = CGRect(x: 70, y: 128, width: 560, height: 88)
            let slack: CGFloat = 3
            #expect(abs(rungs[1].minX - row.minX) <= slack && abs(rungs[1].minY - row.minY) <= slack
                    && abs(rungs[1].width - row.width) <= slack * 2
                    && abs(rungs[1].height - row.height) <= slack * 2,
                    "second rung should be the row, got \(rungs[1])")
        }
        // Off the label, in the row's blank half, the row itself is first.
        expectRect(ladder(c, 400, 172).first, CGRect(x: 70, y: 128, width: 560, height: 88),
                   slack: 3)
    }

    @Test func aButtonLabelStaysTheButton() {
        // A control hugs its label and centers it. Pointing at the words in a
        // button means the button: the pick may not flicker between a word
        // and its button as the pointer crosses the letters.
        var c = Capture(w: 400, h: 300)
        let button = CGRect(x: 60, y: 50, width: 200, height: 60)
        c.box(button, border: 90)
        // 8 glyphs are 60 px wide; centered in a 200 px button.
        line(&c, x: 130, y: 73, words: [8])
        let over = ladder(c, 150, 80)
        expectRect(over.first, button, slack: 3)
        expectRect(ladder(c, 90, 80).first, button, slack: 3)
    }

    @Test func aCaliperAcrossALabelKnowsTheLabel() {
        // Distance mode: feet on the two ends of a label. The label comes
        // back as the caliper's subject so its number stays off the words.
        var c = Capture(w: 500, h: 300)
        let label = line(&c, x: 100, y: 100, words: [5, 3, 6])
        let y = label.midY
        let subjects = ElementBounds.subjects(from: CGPoint(x: label.minX, y: y),
                                              to: CGPoint(x: label.maxX, y: y),
                                              mode: .horizontal, in: c.map, luma: c.luma,
                                              minElement: minElement, textGap: gap)
        #expect(subjects.contains { $0 == label }, "subjects: \(subjects)")
    }
}
