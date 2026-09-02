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
    /// (`ArrowCaptionEntry.caption`): newlines collapsed, edges trimmed. The
    /// field measures the string it will become, not the one on screen, so a
    /// stray space or a pasted line break cannot shrink the bubble on Return.
    public static func committedText(_ draft: String) -> String {
        ArrowCaptionEntry.caption(from: draft) ?? ""
    }

    /// The laid-out text block inside the pill, in document points. A caption
    /// is always one line: it is measured unconstrained and never wraps.
    public static func textSize(for draft: String, fontSize: CGFloat) -> CGSize {
        TextRasterizer.naturalSize(TextContent(string: committedText(draft),
                                               fontName: fontName, fontSize: fontSize))
    }

    /// The pill `draft` renders in, in document points: the measured text plus
    /// the caption's padding on every side.
    public static func pillSize(for draft: String, in annotation: AnnotationContent) -> CGSize {
        annotation.captionPillSize(
            forTextSize: textSize(for: draft, fontSize: annotation.captionFontSize))
    }
}
