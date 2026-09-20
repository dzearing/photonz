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
/// Inside the margin are the two shapes that make glyphs of different shapes
/// look the same size, which is the thing a set is actually judged on. A boxy
/// glyph fills the square, 18 wide in a 24 unit artboard; a round one fills the
/// circle, which is the one that fits the live area, 20 across. The circle is
/// deliberately the BIGGER of the two: a circle drawn to the same width as a
/// square encloses a fifth less ink and reads as shrunken beside it. Those two
/// carry nearly all of the effect, so the frame stops there — the wide and tall
/// rectangles a full keyline set also has were left off on purpose, as four
/// outlines stacked in one small square is more to look past than it is
/// worth. (Decided by the user on 2026-09-15: "Just the square and the
/// circle".)
///
/// ## None of it draws a border round anything
///
/// The margin is handed over as two rectangles to WASH the band between, and
/// the square as four hairlines that run off the edges of the frame, because
/// the selection outline owns the traced border: it is the one mark on the
/// canvas that draws a hard line round the exact edge of a thing, and that is
/// how you know what your next gesture will act on. The first version of this
/// traced the live area as a dashed rectangle, and a new icon frame arrives
/// selected, so the first thing anybody saw was two dashed rectangles a few
/// points apart meaning completely different things. See UX-PATTERNS D16 rule
/// 3 and task `an-icon-frame-s-guides-stop-looking-like-a-secon`. The circle
/// is exempt by its shape: nothing reads a circle as a selection.
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

    /// The square a boxy glyph fills, in artboard units. Smaller than the live
    /// area on purpose: see the note above about why the circle is the bigger
    /// of the two.
    public static let keylineSquareSide: CGFloat = 18

    /// The margin between a frame's edge and its live area, on every side, in
    /// document points. A twelfth of the frame, on whole points.
    public static func margin(forSide side: CGFloat) -> CGFloat {
        guard side.isFinite, side > 0 else { return 0 }
        return (side * (artboardSide - liveAreaSide) / (2 * artboardSide)).rounded()
    }

    /// The gap between a frame's edge and its square keyline, on every side, in
    /// document points. Rounded for the same reason the margin is.
    public static func squareInset(forSide side: CGFloat) -> CGFloat {
        guard side.isFinite, side > 0 else { return 0 }
        return (side * (artboardSide - keylineSquareSide) / (2 * artboardSide)).rounded()
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
        let live = box.insetBy(dx: margin, dy: margin)
        // A square that rounded onto the live area is that guide drawn twice,
        // which happens on the very smallest frames; there the margin and the
        // circle are the whole story.
        let inset = squareInset(forSide: box.width)
        let square = inset > margin ? box.insetBy(dx: inset, dy: inset) : nil
        return IconKeylineGuides(frame: box,
                                 liveArea: live,
                                 squareKeyline: square,
                                 centerX: box.midX, centerY: box.midY)
    }
}

/// One hairline a guide draws, in canvas coordinates.
///
/// A line rather than a rectangle on purpose: a guide is not allowed to trace
/// a hard border round the edge of anything, because that is the selection
/// outline's one job (UX-PATTERNS D16 rule 3). Where a guide has to mark an
/// area out it does it with a wash over what is outside, or with hairlines
/// that run off the edges of the frame and so never close.
public struct IconKeylineLine: Hashable, Sendable {
    public var from: CGPoint
    public var to: CGPoint

    public init(from: CGPoint, to: CGPoint) {
        self.from = from
        self.to = to
    }
}

/// One icon frame's guides, in canvas coordinates.
public struct IconKeylineGuides: Hashable, Sendable {
    /// The whole icon frame. The margin is marked by washing the band between
    /// this and the live area, so both rectangles are needed to draw it, and
    /// every hairline below runs from one edge of this to the other.
    public var frame: CGRect
    /// The square every glyph in a set keeps its drawing inside.
    public var liveArea: CGRect
    /// The square a boxy glyph fills, or nil on a frame with no room for one
    /// inside the margin.
    public var squareKeyline: CGRect?
    /// The vertical line down the middle of the frame.
    public var centerX: CGFloat
    /// The horizontal line across the middle of the frame.
    public var centerY: CGFloat

    /// The circle a round glyph fills: the one that fits the live area exactly,
    /// touching it at the middle of all four sides. It is named rather than
    /// inferred because it is what a person drawing a round glyph aims at, and
    /// because tying it to the live area is what keeps the two tangent at every
    /// frame size instead of drifting apart as the margin rounds.
    public var circleKeyline: CGRect { liveArea }

    /// The two lines through the middle of the frame, edge to edge. They run
    /// the whole frame rather than the live area: the middle of the icon is
    /// the middle of the icon, and a line that stopped at the margin would be
    /// describing the live area a second time.
    public var centerGuideLines: [IconKeylineLine] {
        [IconKeylineLine(from: CGPoint(x: centerX, y: frame.minY),
                         to: CGPoint(x: centerX, y: frame.maxY)),
         IconKeylineLine(from: CGPoint(x: frame.minX, y: centerY),
                         to: CGPoint(x: frame.maxX, y: centerY))]
    }

    /// The square a boxy glyph fills, marked the way a guide is allowed to
    /// mark an area: four hairlines sitting on its edges and running out to
    /// the edges of the frame. Left, right, top, bottom; empty on a frame with
    /// no room for a square.
    ///
    /// This is what an icon keyline sheet has always looked like, and it is
    /// also the reason the square can never be mistaken for a selection: the
    /// lines cross and carry on past, so there is no closed rectangle anywhere
    /// on the frame but the one round the thing you have picked.
    public var squareGuideLines: [IconKeylineLine] {
        guard let square = squareKeyline else { return [] }
        return [IconKeylineLine(from: CGPoint(x: square.minX, y: frame.minY),
                                to: CGPoint(x: square.minX, y: frame.maxY)),
                IconKeylineLine(from: CGPoint(x: square.maxX, y: frame.minY),
                                to: CGPoint(x: square.maxX, y: frame.maxY)),
                IconKeylineLine(from: CGPoint(x: frame.minX, y: square.minY),
                                to: CGPoint(x: frame.maxX, y: square.minY)),
                IconKeylineLine(from: CGPoint(x: frame.minX, y: square.maxY),
                                to: CGPoint(x: frame.maxX, y: square.maxY))]
    }

    public init(frame: CGRect, liveArea: CGRect, squareKeyline: CGRect? = nil,
                centerX: CGFloat, centerY: CGFloat) {
        self.frame = frame
        self.liveArea = liveArea
        self.squareKeyline = squareKeyline
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
