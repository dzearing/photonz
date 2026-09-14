import CoreGraphics
import Foundation

/// The space an icon has to live inside, drawn on an icon frame
/// (`next-icon-frames`).
///
/// What makes a set of icons look like a set is not that the glyphs are alike —
/// a cloud and an arrow are not alike — but that every one of them keeps its
/// drawing inside the same margin and lines up on the same handful of lines. An
/// icon frame with nothing drawn on it is a blank square, so there is no way to
/// tell while you are drawing whether what you made sits where the rest of the
/// set sits. This is the margin and those lines.
///
/// ## The rule
///
/// One margin, a twelfth of the frame on every side, which is the 20 by 20 live
/// area inside a 24 unit artboard that interface iconography has been drawn to
/// since Material wrote it down. It is rounded to whole points, because an icon
/// grid IS pixels: a guide sitting half on one is the smear this feature exists
/// to help somebody avoid. The two center lines cross in the middle.
///
/// ## What it deliberately is not
///
/// It is **not a third kind of grid**. This app already has two things a person
/// could call one — the canvas grid (a spacing, a view preference, drawn over
/// everything) and a screen's columns (a count and a gutter, saved with the
/// document, the only one that pulls at a drag) — and the surest way to keep
/// those apart is that each keeps its own word and its own place. So there is
/// nothing here to set: the frame's SIZE already says everything the margin
/// needs, and a frame that is icon sized draws its own the moment it exists.
///
/// It is also **chrome, never content**: the canvas draws it, the renderer
/// knows nothing about it, so it can never reach an export, a copied picture or
/// an SVG. See docs/design/mocks/shared/UX-PATTERNS.md D16, "A guide draws over
/// your work, and never gets into the picture".
public enum IconKeylines {

    /// The artboard interface iconography is described in terms of, and the
    /// square inside it every glyph in a set keeps its drawing within.
    public static let artboardSide: CGFloat = 24
    public static let liveAreaSide: CGFloat = 20

    /// The margin between a frame's edge and its live area, on every side, in
    /// document points. A twelfth of the frame, on whole points.
    public static func margin(forSide side: CGFloat) -> CGFloat {
        guard side.isFinite, side > 0 else { return 0 }
        return (side * (artboardSide - liveAreaSide) / (2 * artboardSide)).rounded()
    }

    /// Everything drawn on a frame sitting here on the canvas, or nil for a
    /// frame that is not an icon.
    ///
    /// Nil covers three cases that all mean the same thing on screen — nothing
    /// drawn: a frame that is not the shape and size an icon is drawn at, a
    /// frame too small for a margin anybody could see, and a size that is not a
    /// number.
    public static func guides(in box: CGRect) -> IconKeylineGuides? {
        guard box.width.isFinite, box.height.isFinite,
              box.minX.isFinite, box.minY.isFinite,
              IconPreviews.isIconSize(box.size) else { return nil }
        let margin = margin(forSide: box.width)
        // A live area exactly on the frame's edge is the frame's own hairline
        // drawn a second time, not a margin.
        guard margin >= 1 else { return nil }
        return IconKeylineGuides(liveArea: box.insetBy(dx: margin, dy: margin),
                                 centerX: box.midX, centerY: box.midY)
    }
}

/// One icon frame's guides, in canvas coordinates.
public struct IconKeylineGuides: Hashable, Sendable {
    /// The square every glyph in a set keeps its drawing inside.
    public var liveArea: CGRect
    /// The vertical line down the middle of the frame.
    public var centerX: CGFloat
    /// The horizontal line across the middle of the frame.
    public var centerY: CGFloat

    public init(liveArea: CGRect, centerX: CGFloat, centerY: CGFloat) {
        self.liveArea = liveArea
        self.centerX = centerX
        self.centerY = centerY
    }
}

extension PhotonzDocument {
    /// Whether anything in this document is a frame the size an icon is drawn
    /// at. A document of screenshots answers no without the canvas drawing,
    /// measuring or reserving anything.
    public var hasIconFrames: Bool {
        hasFrames && frames.contains { IconPreviews.isIconSize($0.frame.size) }
    }
}
