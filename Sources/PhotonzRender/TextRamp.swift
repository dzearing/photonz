import CoreGraphics
import CoreText
import Foundation
import PhotonzCore

/// Words filled with a ramp instead of one colour (`TextContent.fill`), the way
/// a CSS title is with `background-clip: text`: each line wears its own ramp,
/// sized to that line, so a second, shorter line runs through every colour
/// too (`video-titles-apple.html`, 07 Launch and 08 Gradient Word).
///
/// The letters are poured through as outlines rather than drawn as text, so
/// the ramp can be clipped to them; at title sizes an outline and a drawn
/// glyph are the same picture.
extension TextRasterizer {

    /// The box a line's ramp runs across, in the frame's own y-up points: as
    /// wide as the line's words (with the spacing after its last letter, as
    /// CSS gives a line's box) and as tall as its line, `base` being where the
    /// frame's path starts.
    static func rampLineBox(_ line: CTLine, origin: CGPoint, base: CGPoint) -> CGRect {
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let full = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        let width = max(1, full - CGFloat(CTLineGetTrailingWhitespaceWidth(line)))
        let range = CTLineGetStringRange(line)
        let start = CTLineGetOffsetForStringIndex(line, range.location, nil)
        return CGRect(x: base.x + origin.x + start, y: base.y + origin.y - descent,
                      width: width, height: ascent + descent)
    }

    /// The outlines of `count` glyphs of `run` from `from`, placed on a line
    /// whose origin is `origin` (already in the frame's own points).
    static func glyphOutlines(_ run: CTRun, from: Int = 0, count: Int? = nil,
                              at origin: CGPoint, into path: CGMutablePath) {
        let total = CTRunGetGlyphCount(run)
        let length = min(count ?? total, total - from)
        guard length > 0,
              let font = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName as String]
        else { return }
        // The dictionary hands the run's font back untyped: checked to be a
        // CTFont before it is read as one.
        let value = font as CFTypeRef
        guard CFGetTypeID(value) == CTFontGetTypeID() else { return }
        let ctFont = unsafeBitCast(value, to: CTFont.self)
        var glyphs = [CGGlyph](repeating: 0, count: length)
        var positions = [CGPoint](repeating: .zero, count: length)
        CTRunGetGlyphs(run, CFRange(location: from, length: length), &glyphs)
        CTRunGetPositions(run, CFRange(location: from, length: length), &positions)
        for index in 0..<length {
            guard let outline = CTFontCreatePathForGlyph(ctFont, glyphs[index], nil) else { continue }
            path.addPath(outline, transform: CGAffineTransform(translationX: origin.x + positions[index].x,
                                                               y: origin.y + positions[index].y))
        }
    }

    /// Every line of `frame`, its letters filled with `ramp`.
    static func drawRamped(_ frame: CTFrame, text: TextContent, ramp: Paint, base: CGPoint,
                           in context: CGContext) {
        guard let lines = CTFrameGetLines(frame) as? [CTLine], !lines.isEmpty else { return }
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        for (line, origin) in zip(lines, origins) {
            let place = CGPoint(x: base.x + origin.x, y: base.y + origin.y)
            let outlines = CGMutablePath()
            for run in (CTLineGetGlyphRuns(line) as? [CTRun]) ?? [] {
                glyphOutlines(run, at: place, into: outlines)
            }
            guard !outlines.isEmpty else { continue }
            let box = text.fillBox(forLine: rampLineBox(line, origin: origin, base: base))
            GradientPainter.fill(path: outlines, with: ramp, across: box, in: context)
        }
    }
}
