import CoreGraphics
import Foundation

/// A line of text under a probe point, read as one element.
///
/// `ElementBounds` finds an element from a pair of boundaries whose runs agree,
/// which is exactly the shape a button or a row has and exactly the shape text
/// does NOT: a glyph's top stops where the letter does, so a heading or a row
/// label reads as nothing there. Redliners measure text as often as buttons,
/// so a line of text gets its own reading, straight off the brightness field:
///
/// 1. The background behind the pointer is whatever brightness is commonest
///    around it (text is sparse, so the page wins the vote), and INK is any
///    pixel far enough from that.
/// 2. The ink nearest the pointer seeds a band. The band runs along the line
///    while the clean stretches between letters and words stay under the
///    visible gap, the same width `AlignmentCheck` uses to tell two items
///    apart, and grows up and down while any column in it still carries ink,
///    so an accent or a descender joins its line.
/// 3. What comes back has to look like words: taller than a hairline, shorter
///    than a panel, with daylight between at least two letters and not a solid
///    block. Anything else is quiet, so a switch or a divider never reads as a
///    line of text.
///
/// The box is the INK box: cap or ascender top to descender bottom, first to
/// last glyph. A screenshot carries no line height, and the ink box is what a
/// caliper laid across the letters by hand already says, so the two agree.
///
/// Runs on every mouse move, so it reads the brightness buffer directly and
/// touches only the pixels within reach of the line it is reading.
public enum TextLineBounds {

    /// The clean stretch, in IMAGE px, that ends a line: `AlignmentCheck`'s
    /// visible gap on the 2x captures this tool is pointed at. A word space is
    /// well under it, side-by-side items well over.
    public static let defaultGap: Double = 16

    /// How far a pixel's brightness must sit from the background (0...1) to be
    /// ink. The same floor `AlignmentCheck` uses for an element's own body:
    /// above a hairline divider's contrast, well under any glyph.
    public static let inkFloor: Double = 0.15

    /// The tallest thing that can still be one line of text, in visible gaps:
    /// 128 px on a 2x capture, room for a display heading. Taller than that is
    /// a picture or a panel, whatever gaps it has.
    public static let maxHeightInGaps: Double = 8

    /// Ink covering more of the box than this is a fill, not letters.
    private static let maxCoverage = 0.85

    /// A row whose ink runs unbroken across this much of the line is a rule
    /// (an underline, a divider hugging the baseline), not a row of letters,
    /// and it stops the band rather than joining it.
    private static let ruleFraction = 0.9

    /// The line of text under `point`, or nil when what is there is not one.
    ///
    /// `gap` is the clean stretch that ends a line, `minElement` the smallest
    /// width worth offering (the line may be half as tall as that: a caption
    /// is short), and `maxRadius` how far along the line the reading walks
    /// from the pointer before giving up on each side.
    public static func detect(at point: CGPoint, in luma: LumaField,
                              gap: Double = defaultGap,
                              minElement: Double = ElementBounds.defaultMinElement,
                              maxRadius: Double = ElementBounds.defaultMaxRadius) -> CGRect? {
        guard !luma.isEmpty, gap >= 1, maxRadius > 0 else { return nil }
        let w = luma.width, h = luma.height
        let px = Int(point.x.rounded()), py = Int(point.y.rounded())
        guard px >= 0, py >= 0, px < w, py < h else { return nil }
        let gapPx = max(1, Int(gap.rounded()))
        // How far above or below the letters the pointer may sit and still be
        // pointing at them, and how many clean rows an accent may float above
        // its letter.
        let slack = max(1, gapPx / 4)
        let verticalGap = max(2, gapPx / 8)
        let maxHeight = max(gapPx, Int((maxHeightInGaps * gap).rounded()))
        let reach = max(1, Int(maxRadius.rounded()))
        let threshold = Int((inkFloor * 255).rounded())

        return luma.samples.withUnsafeBufferPointer { s -> CGRect? in
            // 1. Background: the commonest brightness in a window wide enough
            // to hold more page than letters even under a display heading.
            // Every other pixel each way is plenty for a vote.
            var histogram = [Int](repeating: 0, count: 256)
            let bx0 = max(0, px - 6 * gapPx), bx1 = min(w - 1, px + 6 * gapPx)
            let by0 = max(0, py - 3 * gapPx / 2), by1 = min(h - 1, py + 3 * gapPx / 2)
            for y in stride(from: by0, through: by1, by: 2) {
                let base = y * w
                for x in stride(from: bx0, through: bx1, by: 2) { histogram[Int(s[base + x])] += 1 }
            }
            var background = 0, votes = -1
            for value in 0..<256 where histogram[value] > votes {
                background = value
                votes = histogram[value]
            }
            @inline(__always) func ink(_ x: Int, _ y: Int) -> Bool {
                abs(Int(s[y * w + x]) - background) >= threshold
            }

            // 2. Seed on the ink nearest the pointer.
            var top = Int.max, bottom = -1, left = Int.max, right = -1
            for y in max(0, py - slack)...min(h - 1, py + slack) {
                for x in max(0, px - gapPx)...min(w - 1, px + gapPx) where ink(x, y) {
                    top = min(top, y)
                    bottom = max(bottom, y)
                    left = min(left, x)
                    right = max(right, x)
                }
            }
            guard bottom >= 0 else { return nil }

            func columnInked(_ x: Int) -> Bool {
                for y in top...bottom where ink(x, y) { return true }
                return false
            }
            /// Whether row `y` carries ink inside the line's extent, and the
            /// longest unbroken stretch of it.
            func rowInk(_ y: Int) -> (any: Bool, longest: Int) {
                var any = false, longest = 0, run = 0
                for x in left...right {
                    if ink(x, y) {
                        any = true
                        run += 1
                        if run > longest { longest = run }
                    } else {
                        run = 0
                    }
                }
                return (any, longest)
            }
            func isRule(_ row: (any: Bool, longest: Int)) -> Bool {
                let width = right - left + 1
                return width >= 2 * gapPx && Double(row.longest) >= ruleFraction * Double(width)
            }

            // Along the line, then up and down, until nothing changes: the
            // first pass only knows the letters under the pointer, and an
            // ascender two words along can raise the band, which can widen it.
            var tooTall = false
            for _ in 0..<4 {
                let before = (top, bottom, left, right)
                var clean = 0
                var x = left
                while x > 0, left - x < reach {
                    x -= 1
                    if columnInked(x) {
                        left = x
                        clean = 0
                    } else {
                        clean += 1
                        if clean >= gapPx { break }
                    }
                }
                clean = 0
                x = right
                while x < w - 1, x - right < reach {
                    x += 1
                    if columnInked(x) {
                        right = x
                        clean = 0
                    } else {
                        clean += 1
                        if clean >= gapPx { break }
                    }
                }
                clean = 0
                var y = top
                while y > 0 {
                    y -= 1
                    let row = rowInk(y)
                    if row.any {
                        if isRule(row) { break }
                        top = y
                        clean = 0
                        if bottom - top + 1 > maxHeight { tooTall = true; break }
                    } else {
                        clean += 1
                        if clean > verticalGap { break }
                    }
                }
                clean = 0
                y = bottom
                while y < h - 1 {
                    y += 1
                    let row = rowInk(y)
                    if row.any {
                        if isRule(row) { break }
                        bottom = y
                        clean = 0
                        if bottom - top + 1 > maxHeight { tooTall = true; break }
                    } else {
                        clean += 1
                        if clean > verticalGap { break }
                    }
                }
                if tooTall { return nil }
                if before == (top, bottom, left, right) { break }
            }

            // 3. Does it look like words?
            let width = right - left + 1, height = bottom - top + 1
            guard Double(width) >= minElement, Double(height) >= minElement / 2 else { return nil }
            var inked = 0
            var daylight = false
            for x in left...right {
                var column = 0
                for y in top...bottom where ink(x, y) { column += 1 }
                if column == 0 { daylight = true }
                inked += column
            }
            guard daylight, Double(inked) <= maxCoverage * Double(width * height) else { return nil }
            let rect = CGRect(x: left, y: top, width: width, height: height)
            guard rect.insetBy(dx: CGFloat(-slack), dy: CGFloat(-slack)).contains(point) else {
                return nil
            }
            return rect
        }
    }
}
