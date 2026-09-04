import CoreGraphics
import CoreText
import Foundation
import PhotonzCore

/// The ONE measurer for a text block's box.
///
/// The frame the renderer bakes a label into and the field you type that label
/// in both size themselves through here, so the words on screen while you type
/// are the words that land when you press Return. Two measurers drift: the
/// field used to lay its draft out with its own layout engine at the zoomed
/// point size while the renderer measured at the document size, so the box you
/// typed in was a few percent off the box you got and a long label broke at a
/// different word.
///
/// The companion for arrow captions is `CaptionMetrics`; this is the same idea
/// for a block of text, which also has to agree on where it wraps.
public enum TextBlockMetrics {

    /// The widest a NEW block placed at `origin` may grow before it wraps, in
    /// document points: 60% of the canvas, never past the right edge, never
    /// below the minimum width. A block being re-edited uses the room it
    /// already has instead (`roomyBox`).
    public static func wrapWidth(origin: CGPoint, in documentSize: CGSize) -> CGFloat {
        let toEdge = documentSize.width - origin.x
        let cap = documentSize.width * 0.6
        return max(min(toEdge, cap), TextRasterizer.minimumTextWidth)
    }

    /// The room a stored box has beyond the words in it — a paragraph, or a
    /// label somebody stretched across what holds it. Re-wording such a box
    /// re-wraps in place instead of collapsing back around the words and
    /// pulling centred text off centre. `nil` on an axis means the box hugs its
    /// words there and should keep hugging them.
    public static func roomyBox(for text: TextContent,
                                frame: CGRect) -> (width: CGFloat?, height: CGFloat?) {
        // Across, there is exactly one box that hugs: the one as wide as the
        // words on ONE line. Wider and somebody stretched it; narrower and
        // somebody dragged it in to wrap. Either way the width was chosen and
        // is kept. Comparing against the words wrapped at the box's own width
        // instead asks whether the box is wider than itself, which said
        // "hugging" for a paragraph whose longest line happened to fill it and
        // snapped it out to one enormous line the moment it was re-worded.
        let oneLine = TextRasterizer.naturalSize(text)
        let hugs = abs(frame.width - oneLine.width) <= 0.5
        // Down, the words are measured at the width the box HAS, because that
        // is what decides how many lines they take.
        let wrapped = TextRasterizer.naturalSize(text, maxWidth: frame.width)
        return (hugs ? nil : frame.width,
                frame.height > wrapped.height + 0.5 ? frame.height : nil)
    }

    /// The frame `text` lands in, in document points: it hugs the words,
    /// wrapping no wider than `maxWidth`, unless the box already has room it
    /// should keep (`roomyWidth` / `roomyHeight` from `roomyBox`).
    ///
    /// `hugsShortWords` decides what happens to words narrower than the
    /// minimum width. The minimum is how narrow a box can be DRAGGED or typed
    /// down to, and that is a fact about a paragraph: below it a block of text
    /// is a sliver of a column many lines tall rather than something you can
    /// read. A label nobody has narrowed is not a paragraph, so applying the
    /// floor to it is what made typing OK on the canvas give an eighty point
    /// box with the word sitting in its left third, while the same word inside
    /// a starter component hugged its letters. With this on, a box that has
    /// never been narrowed is exactly as wide as what it says; with it off,
    /// every typed box is at least the minimum, as it always was.
    public static func frameSize(for text: TextContent, maxWidth: CGFloat,
                                 roomyWidth: CGFloat? = nil,
                                 roomyHeight: CGFloat? = nil,
                                 hugsShortWords: Bool = false) -> CGSize {
        var size = TextRasterizer.naturalSize(
            text, maxWidth: roomyWidth ?? maxWidth,
            minWidth: hugsShortWords ? 0 : TextRasterizer.minimumTextWidth)
        if let roomyWidth { size.width = roomyWidth }
        if let roomyHeight { size.height = max(size.height, roomyHeight) }
        return size
    }

    /// How far below the frame's top edge the first line sits, in document
    /// points. Zero for text that starts at the top, which is every block that
    /// hugs its words; only a box with room to spare can push its lines down.
    /// The field types the draft at this same offset, so nothing slides
    /// vertically on Return.
    public static func topInset(for text: TextContent, in frameSize: CGSize) -> CGFloat {
        guard text.verticalAlignment != nil, text.usedVerticalAlignment != .top,
              !text.string.isEmpty else { return 0 }
        let needed = laidOutHeight(text, width: frameSize.width)
        guard needed < frameSize.height else { return 0 }
        let slack = frameSize.height - needed
        return text.usedVerticalAlignment == .middle ? slack - (slack / 2).rounded() : slack
    }

    /// The height the lines of `text` need inside a box `width` wide, with the
    /// one point of slack the frame they are handed to needs (the suggestion
    /// and the frame round differently, and the cost of being one short is a
    /// dropped line).
    static func laidOutHeight(_ text: TextContent, width: CGFloat) -> CGFloat {
        let attributed = TextRasterizer.measuringString(text)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRange(location: 0, length: 0), nil,
            CGSize(width: width, height: CGFloat.greatestFiniteMagnitude), nil)
        return ceil(suggested.height) + 1
    }
}
