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
        let hugged = TextRasterizer.naturalSize(text, maxWidth: frame.width,
                                                minWidth: TextRasterizer.minimumTextWidth)
        return (frame.width > hugged.width + 0.5 ? frame.width : nil,
                frame.height > hugged.height + 0.5 ? frame.height : nil)
    }

    /// The frame `text` lands in, in document points: it hugs the words,
    /// wrapping no wider than `maxWidth`, unless the box already has room it
    /// should keep (`roomyWidth` / `roomyHeight` from `roomyBox`).
    public static func frameSize(for text: TextContent, maxWidth: CGFloat,
                                 roomyWidth: CGFloat? = nil,
                                 roomyHeight: CGFloat? = nil) -> CGSize {
        var size = TextRasterizer.naturalSize(text, maxWidth: roomyWidth ?? maxWidth,
                                              minWidth: TextRasterizer.minimumTextWidth)
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
