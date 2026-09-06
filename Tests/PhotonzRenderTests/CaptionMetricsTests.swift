import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// `CaptionMetrics` is the ONE measurer for an arrow caption's bubble: the
/// rasterized pill and the on-canvas field you type in both size themselves
/// through it. These pin the metric to the pixels that actually land, so a
/// change to either side shows up here instead of as a bubble that resizes on
/// Return.
@Suite("Caption metrics")
struct CaptionMetricsTests {

    /// A leftward arrow (head at the left), so the caption pill hangs off the
    /// tail on the right, clear of the shaft's columns.
    private func captionedLayer(_ caption: String, fontSize: CGFloat = 20) -> Layer {
        var content = AnnotationContent(shape: .arrow, strokeWidth: 4, colorHex: "#FF3B30")
        content.caption = caption
        content.captionFontSize = fontSize
        return AnnotationBuilder.layer(content: content,
                                       from: CGPoint(x: 620, y: 120), to: CGPoint(x: 60, y: 120))
    }

    private func alphaMap(_ image: CGImage) -> (data: [UInt8], width: Int, height: Int) {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &data, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (data, width, height)
    }

    /// The drawn pill's box, in layer-local points: every column and row past
    /// the arrow's tail that carries ink. The border straddles the pill's edge,
    /// so the ink box is the metric plus one border width.
    private func drawnPillBox(_ content: AnnotationContent, image: CGImage,
                              clearOfX: CGFloat) -> CGRect? {
        let px = alphaMap(image)
        var minX = Int.max, maxX = Int.min, minY = Int.max, maxY = Int.min
        for y in 0..<px.height {
            for x in Int(clearOfX)..<px.width {
                let alpha = px.data[(y * px.width + x) * 4 + 3]
                guard alpha > 100 else { continue }
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard minX <= maxX else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    @Test("the pill that lands is the size CaptionMetrics reports",
          arguments: ["Ok", "Focus ring is 2px off",
                      "This caption is definitely longer than thirty characters"])
    func drawnPillMatchesTheMetric(caption: String) {
        let layer = captionedLayer(caption)
        guard let content = layer.annotation,
              let image = AnnotationRasterizer.rasterize(content, size: layer.frame.size) else {
            Issue.record("expected a rasterized captioned arrow")
            return
        }
        let metric = CaptionMetrics.pillSize(for: caption, in: content)
        // The tail sits at the layer's right end and the pill's near edge lands
        // ON it, so the scan starts half a border to the left of the tail —
        // where the pill's own straddling border begins — and everything
        // further left is the shaft.
        let tailX = content.start.x - content.captionBorderWidth / 2
        guard let box = drawnPillBox(content, image: image, clearOfX: tailX) else {
            Issue.record("expected pill ink past the arrow's tail")
            return
        }
        let border = content.captionBorderWidth
        #expect(abs(box.width - (metric.width + border)) <= 2,
                "drawn pill \(box.width)pt wide, metric says \(metric.width) (+\(border) border)")
        #expect(abs(box.height - (metric.height + border)) <= 2,
                "drawn pill \(box.height)pt tall, metric says \(metric.height) (+\(border) border)")
    }

    @Test func pillIsTheMeasuredTextPlusPaddingOnEverySide() {
        var content = AnnotationContent(shape: .arrow, strokeWidth: 4, colorHex: "#FF3B30")
        content.caption = "Hand off the spec"
        let text = CaptionMetrics.textSize(for: content.caption ?? "", fontSize: content.captionFontSize)
        let pill = CaptionMetrics.pillSize(for: content.caption ?? "", in: content)
        #expect(pill.width == text.width + 2 * content.captionPadding)
        #expect(pill.height == text.height + 2 * content.captionPadding)
    }

    /// A draft with a stray space commits trimmed, so the field must already be
    /// measuring the trimmed text: otherwise the bubble shrinks on Return.
    @Test func draftMeasuresTheTextItWillCommitAs() {
        var content = AnnotationContent(shape: .arrow, strokeWidth: 4, colorHex: "#FF3B30")
        content.caption = "Baseline off by 1"
        #expect(CaptionMetrics.committedText("  Baseline off by 1 ") == "Baseline off by 1")
        #expect(CaptionMetrics.pillSize(for: "  Baseline off by 1 ", in: content)
                == CaptionMetrics.pillSize(for: "Baseline off by 1", in: content))
    }

    /// Pasting two lines into the single-line field commits as one line, so the
    /// bubble must already be one line's worth wide.
    @Test func aPastedLineBreakMeasuresAsTheOneLineItCommitsAs() {
        var content = AnnotationContent(shape: .arrow, strokeWidth: 4, colorHex: "#FF3B30")
        content.caption = "Focus ring off"
        #expect(CaptionMetrics.pillSize(for: "Focus ring\noff", in: content)
                == CaptionMetrics.pillSize(for: "Focus ring off", in: content))
    }

    /// The field types its words exactly where the committed pill draws them:
    /// the inset centres the ink, so it sits PAST the padding by the slack the
    /// measured box carries, and past it further still on a widened pill.
    @Test func theFieldInsetsItsDraftToWhereTheCommittedWordsLand() {
        var content = AnnotationContent(shape: .arrow, strokeWidth: 4, colorHex: "#FF3B30")
        content.captionFontSize = 20
        for draft in ["Hand off the spec", "Hi", "1"] {
            let inset = CaptionMetrics.textInset(for: draft, in: content)
            let text = CaptionMetrics.textSize(for: draft, fontSize: content.captionFontSize)
            let pill = CaptionMetrics.pillSize(for: draft, in: content)
            // Centring the ink of the words leaves the same room on the right.
            let content1 = TextContent(string: draft, fontName: CaptionMetrics.fontName,
                                       fontSize: content.captionFontSize)
            let ink = TextRasterizer.inkOffset(content1)
            #expect(abs((inset + text.width / 2 + ink) - pill.width / 2) < 0.001,
                    "\(draft.debugDescription): inset \(inset) in a \(pill.width) pill")
            #expect(inset > content.captionPadding,
                    "\(draft.debugDescription): inset \(inset) vs padding \(content.captionPadding)")
        }
    }

    /// A draft measures the text it commits as, so its inset does too.
    @Test func theInsetIgnoresWhitespaceTheCommitWillTrim() {
        var content = AnnotationContent(shape: .arrow, strokeWidth: 4, colorHex: "#FF3B30")
        #expect(CaptionMetrics.textInset(for: "  Focus ring off ", in: content)
                == CaptionMetrics.textInset(for: "Focus ring off", in: content))
        content.captionFontSize = 32
        #expect(CaptionMetrics.textInset(for: "Focus ring off", in: content) > 0)
    }

    @Test func pillScalesWithTheCaptionFontSize() {
        var small = AnnotationContent(shape: .arrow, strokeWidth: 4, colorHex: "#FF3B30")
        small.captionFontSize = 14
        var large = small
        large.captionFontSize = 32
        let text = "Same words, bigger label"
        #expect(CaptionMetrics.pillSize(for: text, in: large).width
                > CaptionMetrics.pillSize(for: text, in: small).width)
    }
}
