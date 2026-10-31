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

    /// Whether the draft is laid out as SEVERAL LINES, which is a question
    /// about the text on screen and not about the text that will commit.
    ///
    /// The two differ by exactly one keystroke and that is the whole point:
    /// press Return after a word and the field holds "Hello\n" while
    /// `committedText` still says "Hello". The bubble follows the committed
    /// text, so a bare Return cannot make it grow a line it is about to throw
    /// away; the LAYOUT follows the draft, so the caret waits on the new line
    /// where the next character will land rather than at the bubble's left
    /// edge. Asking this question of the committed text is what used to drop
    /// the caret left and then jump the first character into the middle.
    public static func draftIsMultiLine(_ draft: String) -> Bool {
        draft.contains(where: \.isNewline)
    }

    /// The laid-out text block inside the pill, in document points. A caption
    /// never wraps: it is measured unconstrained, so it is as wide as its
    /// longest line and as tall as the lines the person typed.
    public static func textSize(for draft: String, fontSize: CGFloat,
                                fontName: String = fontName, weight: TextWeight = .regular) -> CGSize {
        TextRasterizer.naturalSize(PillRasterizer.content(committedText(draft),
                                                          fontSize: fontSize, fontName: fontName,
                                                          weight: weight))
    }

    /// The words of `annotation`'s chip as they are measured and drawn: its
    /// style's family, weight and size.
    public static func textSize(for draft: String, in annotation: AnnotationContent) -> CGSize {
        textSize(for: draft, fontSize: annotation.captionTypeSize,
                 fontName: annotation.captionFontName, weight: annotation.captionFontWeight)
    }

    /// The pill `draft` renders in, in document points: the measured text plus
    /// the caption's padding on every side.
    public static func pillSize(for draft: String, in annotation: AnnotationContent) -> CGSize {
        annotation.captionPillSize(
            forTextSize: textSize(for: draft, in: annotation))
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
        let text = textSize(for: words, in: annotation)
        let pill = annotation.captionPillSize(forTextSize: text)
        let content = PillRasterizer.content(words, fontSize: annotation.captionTypeSize,
                                             fontName: annotation.captionFontName,
                                             weight: annotation.captionFontWeight)
        // A marker or accent at the chip's front moves the words over by half
        // the room it takes: they are centred in what is left.
        return (pill.width - text.width) / 2 + annotation.captionLeadWidth / 2
            - TextRasterizer.inkOffset(content)
    }
}
