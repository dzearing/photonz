import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// The SHAPE a caption pill draws, measured off real pixels.
///
/// A caption is a badge: a horizontal capsule with two semicircular caps. When
/// the label is very short the pill used to be taller than it was wide, which
/// reads as a lozenge standing on end, and with an unclamped corner radius the
/// two caps overlapped and the outline met at a point on each side. Both are
/// measured here rather than reasoned about, because both were visible to the
/// user before they were visible in a number.
@Suite("Caption pill shape")
struct CaptionPillShapeTests {

    private let background = CGColor(gray: 0.5, alpha: 1)

    /// Draws one caption pill on an opaque grey field and returns the raster
    /// plus the pill's measured size, so a test can compare drawn ink against
    /// the size that was asked for.
    private func render(_ caption: String, fontSize: CGFloat = 20)
        -> (px: (data: [UInt8], width: Int, height: Int), pill: CGSize)? {
        var content = AnnotationContent(shape: .arrow, strokeWidth: 4, colorHex: "#FF3B30")
        content.caption = caption
        content.captionFontSize = fontSize
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
        // The rasterizers draw in flipped (top-left) space; the pill is centered
        // so the flip does not move it, but the shadow direction depends on it.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        let tone = content.captionChipColor
        PillRasterizer.draw(caption, at: CGPoint(x: CGFloat(width) / 2, y: CGFloat(height) / 2),
                            chipSize: pill, fontSize: fontSize,
                            borderWidth: content.captionBorderWidth,
                            fill: CGColor(srgbRed: tone.r, green: tone.g, blue: tone.b,
                                          alpha: AnnotationContent.captionChipOpacity),
                            border: CGColor(srgbRed: 1, green: 0.23, blue: 0.19, alpha: 1),
                            textColorHex: AnnotationContent.captionTextColorHex,
                            in: context)
        guard let image = context.makeImage() else { return nil }
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let read = CGContext(data: &data, width: width, height: height,
                                   bitsPerComponent: 8, bytesPerRow: width * 4,
                                   space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        read.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ((data, width, height), pill)
    }

    /// The pill's own ink, not the grey field and not its soft shadow: the red
    /// border and the dark red fill are both strongly red-dominant, the grey is
    /// not, and the shadow only darkens grey toward black.
    private func isInk(_ px: (data: [UInt8], width: Int, height: Int), x: Int, y: Int) -> Bool {
        let i = (y * px.width + x) * 4
        let r = Int(px.data[i]), g = Int(px.data[i + 1]), b = Int(px.data[i + 2])
        return r > g + 25 && r > b + 25
    }

    /// The bounding box of the pill's ink, in pixels.
    private func inkBounds(_ px: (data: [UInt8], width: Int, height: Int)) -> CGRect {
        var minX = px.width, maxX = -1, minY = px.height, maxY = -1
        for y in 0..<px.height {
            for x in 0..<px.width where isInk(px, x: x, y: y) {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return .zero }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// How many rows of ink stand in one column: at a pill's leftmost column
    /// this is the flat tangent of a semicircular cap (several pixels tall); at
    /// a pointed oval's tip it is one or two.
    private func inkRows(_ px: (data: [UInt8], width: Int, height: Int), column: Int) -> Int {
        (0..<px.height).reduce(0) { $0 + (isInk(px, x: column, y: $1) ? 1 : 0) }
    }

    @Test func anEmptyCaptionStillDrawsAPillLyingOnItsSide() {
        guard let (px, pill) = render("") else {
            Issue.record("expected a rendered pill")
            return
        }
        #expect(pill.width >= pill.height * 1.2)
        let ink = inkBounds(px)
        #expect(ink.width > ink.height)
    }

    @Test func aOneCharacterCaptionDrawsAPillLyingOnItsSide() {
        guard let (px, pill) = render("1") else {
            Issue.record("expected a rendered pill")
            return
        }
        #expect(pill.width >= pill.height * 1.2)
        let ink = inkBounds(px)
        #expect(ink.width > ink.height)
    }

    @Test func aLongCaptionIsStillJustItsTextPlusPadding() {
        var content = AnnotationContent(shape: .arrow, strokeWidth: 4, colorHex: "#FF3B30")
        content.captionFontSize = 20
        let caption = "A much longer caption"
        let text = CaptionMetrics.textSize(for: caption, fontSize: content.captionFontSize)
        let pill = CaptionMetrics.pillSize(for: caption, in: content)
        #expect(pill.width == text.width + 2 * content.captionPadding)
        #expect(pill.height == text.height + 2 * content.captionPadding)
        guard let (px, _) = render(caption) else {
            Issue.record("expected a rendered pill")
            return
        }
        let ink = inkBounds(px)
        #expect(ink.width > ink.height)
    }

    /// No caption draws with a point on its side, at any of the sizes the app
    /// offers: the ink at the pill's leftmost and rightmost columns is a cap
    /// several pixels tall, not a tip.
    @Test func noCaptionEverDrawsAPointOnItsSide() {
        for caption in ["", "i", "1", "Hi", "A much longer caption"] {
            for fontSize in [10.0, 20.0, 48.0] {
                guard let (px, _) = render(caption, fontSize: fontSize) else {
                    Issue.record("expected a rendered pill for \(caption.debugDescription)")
                    continue
                }
                let ink = inkBounds(px)
                let left = inkRows(px, column: Int(ink.minX))
                let right = inkRows(px, column: Int(ink.maxX) - 1)
                #expect(left >= 4, "\(caption.debugDescription) at \(fontSize) has a left point")
                #expect(right >= 4, "\(caption.debugDescription) at \(fontSize) has a right point")
            }
        }
    }

    /// The rule the shape rests on, held for every size a pill could ever be
    /// asked to draw at — including the ones an adjustable corner radius could
    /// hand it. A radius over half the SHORT side is what makes the two caps
    /// overlap and meet at a point.
    @Test func theCornerRadiusNeverExceedsHalfTheShortSide() {
        for width in stride(from: 1.0, through: 120.0, by: 7.0) {
            for height in stride(from: 1.0, through: 120.0, by: 7.0) {
                let size = CGSize(width: width, height: height)
                let radius = PillRasterizer.cornerRadius(for: size)
                #expect(radius <= min(width, height) / 2 + 0.0001)
            }
        }
    }

    /// How far the glyphs' ink center sits from the pill's, in pixels.
    /// Negative is to the left.
    private func glyphOffCenter(_ caption: String) -> CGFloat? {
        guard let (px, _) = render(caption) else { return nil }
        // The white glyphs are the only light thing on the raster.
        var minX = px.width, maxX = -1
        for y in 0..<px.height {
            for x in 0..<px.width {
                let i = (y * px.width + x) * 4
                if px.data[i] > 200, px.data[i + 1] > 200, px.data[i + 2] > 200 {
                    minX = min(minX, x); maxX = max(maxX, x)
                }
            }
        }
        guard maxX >= minX else { return nil }
        return CGFloat(minX + maxX) / 2 - (inkBounds(px).midX - 0.5)
    }

    /// The words stay in the middle of the widened pill rather than sliding to
    /// one end: a short caption's glyphs sit in their (widened) pill exactly
    /// the way a long caption's sit in their (text-sized) one.
    ///
    /// Both are about two points left of true center, because the measured text
    /// box carries the last glyph's trailing space. That predates the widening
    /// and is tracked separately; what matters here is that widening does not
    /// add to it.
    @Test func theTextStaysCentredInAWidenedPill() {
        guard let widened = glyphOffCenter("H"),
              let natural = glyphOffCenter("A much longer caption") else {
            Issue.record("expected glyphs on both pills")
            return
        }
        #expect(abs(widened - natural) <= 1)
        #expect(abs(widened) <= 3)
    }
}
