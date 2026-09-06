import CoreGraphics
import Foundation
import PhotonzCore

/// The ONE measurer for an arrow caption's bubble.
///
/// The pill the rasterizer bakes into the layer and the field you type the
/// caption in both size themselves through here, so the bubble on screen while
/// you type is the pill that lands when you press Return. Two measurers drift:
/// the field used to lay its draft out at the zoomed point size, and SF tracks
/// letters differently at different point sizes than the document size the
/// pill is rasterized at, so a long caption's far edge jumped by a dozen
/// pixels on commit.
public enum CaptionMetrics {

    /// The family every caption is set in.
    public static let fontName = "SF Pro"

    /// The text a draft actually commits as — the commit rule itself
    /// (`ArrowCaptionEntry.caption`): the lines kept, the edges trimmed. The
    /// field measures the string it will become, not the one on screen, so a
    /// stray space or a trailing Return cannot shrink the bubble on commit.
    public static func committedText(_ draft: String) -> String {
        ArrowCaptionEntry.caption(from: draft) ?? ""
    }

    /// The laid-out text block inside the pill, in document points. A caption
    /// never wraps: it is measured unconstrained, so it is as wide as its
    /// longest line and as tall as the lines the person typed.
    public static func textSize(for draft: String, fontSize: CGFloat) -> CGSize {
        TextRasterizer.naturalSize(PillRasterizer.content(committedText(draft),
                                                          fontSize: fontSize))
    }

    /// The pill `draft` renders in, in document points: the measured text plus
    /// the caption's padding on every side.
    public static func pillSize(for draft: String, in annotation: AnnotationContent) -> CGSize {
        annotation.captionPillSize(
            forTextSize: textSize(for: draft, fontSize: annotation.captionFontSize))
    }

    /// How far in from the pill's left edge the words start, in document
    /// points. The field you type a caption in insets its draft by exactly
    /// this, so pressing Return does not slide the words.
    ///
    /// It is NOT simply the padding. The committed pill centres the ink of the
    /// words in the whole pill, which differs from the padding twice over: a
    /// short caption's pill is widened to stay a badge, and the box the words
    /// are measured into carries its slack on their right
    /// (`TextRasterizer.inkOffset`).
    public static func textInset(for draft: String, in annotation: AnnotationContent) -> CGFloat {
        let words = committedText(draft)
        let text = textSize(for: words, fontSize: annotation.captionFontSize)
        let pill = annotation.captionPillSize(forTextSize: text)
        let content = PillRasterizer.content(words, fontSize: annotation.captionFontSize)
        return (pill.width - text.width) / 2 - TextRasterizer.inkOffset(content)
    }
}
