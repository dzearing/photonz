import CoreGraphics
import Foundation

/// Where the one line a drop target says goes while something is in the air
/// over it.
///
/// A ring round a swatch can only ever say yes. The other half of what
/// somebody carrying a colour needs to hear is the no and its reason — this is
/// where it came from, it is already this colour, that name is kept for other
/// parts — and the crowd the drop would reach, which no ring can carry either.
/// So the target says a sentence, and the sentence needs somewhere to sit.
///
/// The one rule this exists to keep is that the words never sit ON the thing
/// they are about (UX-PATTERNS D14, a callout never covers its subject): a
/// swatch hidden under its own explanation is a swatch you cannot watch light
/// up, and the light is the promise the words are explaining.
///
/// Left first, because nearly every colour in the app lives on the right hand
/// panel and the whole canvas is free beside it. The other three sides are
/// what a target at the window's edge falls back to, in the order that keeps
/// the words nearest the thing.
public enum DropNotePlacement {

    /// How far the words stand off the thing they are about. Close enough to
    /// read as one thing, far enough that the ring round the target is not
    /// touched.
    public static let gap: CGFloat = 10

    /// How close to the window's own edge the words may come.
    public static let margin: CGFloat = 8

    /// How wide the words are allowed to get before they wrap. A sentence
    /// drawn as one long banner across the canvas stops being a note about a
    /// swatch and starts being a headline.
    public static let maxWidth: CGFloat = 240

    /// Which side of the target the words are on.
    public enum Side: Hashable, Sendable {
        case left, right, above, below
    }

    /// Where a `size` box of words goes beside `anchor`, inside `bounds`.
    ///
    /// `clearing` is what the words must stand off, which is not always the
    /// thing they are about. A colour swatch is 18pt wide at the right hand
    /// edge of a panel, and words that only cleared the swatch would lie
    /// across the panel's own rows: the label saying which row this is, the
    /// switch beside it. So the swatch is the anchor — the words line up with
    /// the MIDDLE of it, which is what makes them read as belonging to it —
    /// and the whole panel is what they stand clear of. Where the two are the
    /// same thing, as they are for a swatch floating on the canvas, leave it
    /// out.
    ///
    /// All of them are in the window's own top-left-origin space. The answer
    /// is the box's top-left corner, already held inside the window on the
    /// axis it is free to move on.
    public static func place(note size: CGSize, beside anchor: CGRect,
                             clearing: CGRect? = nil, in bounds: CGRect) -> CGPoint {
        placement(note: size, beside: anchor, clearing: clearing, in: bounds).origin
    }

    /// The same answer, with the side it ended up on, for anyone who wants to
    /// point a tail at the target.
    public static func placement(note size: CGSize, beside anchor: CGRect,
                                 clearing: CGRect? = nil,
                                 in bounds: CGRect) -> (origin: CGPoint, side: Side) {
        // The anchor is always part of what the words stand off: a keep-clear
        // rect that somehow missed the very thing being dropped on would put
        // the words straight on top of it.
        let clear = clearing.map { $0.union(anchor) } ?? anchor
        for side in [Side.left, .right, .above, .below]
        where fits(side, size, clear, bounds) {
            return (origin(side, size, anchor, clear, bounds), side)
        }
        // Nowhere fits: a window too small for the words is not a case the app
        // can satisfy, and refusing to answer would drop the sentence
        // entirely. The first choice stands, still clear of the target on its
        // own axis, so the worst case is words running off the edge rather
        // than words over the swatch.
        return (origin(.left, size, anchor, clear, bounds), .left)
    }

    /// Whether the words land inside the window on this side. Only the axis
    /// the side is chosen for is checked: the other one is clamped by
    /// `origin`, which can always find room on it.
    private static func fits(_ side: Side, _ size: CGSize,
                             _ clear: CGRect, _ bounds: CGRect) -> Bool {
        switch side {
        case .left: clear.minX - gap - size.width >= bounds.minX + margin
        case .right: clear.maxX + gap + size.width <= bounds.maxX - margin
        case .above: clear.minY - gap - size.height >= bounds.minY + margin
        case .below: clear.maxY + gap + size.height <= bounds.maxY - margin
        }
    }

    /// How far along the side the words sit comes from `clear`; where they sit
    /// ACROSS it comes from `anchor`, so a sentence pushed out past a whole
    /// panel still lines up with the one swatch it is about.
    private static func origin(_ side: Side, _ size: CGSize, _ anchor: CGRect,
                               _ clear: CGRect, _ bounds: CGRect) -> CGPoint {
        switch side {
        case .left:
            CGPoint(x: clear.minX - gap - size.width,
                    y: clamp(anchor.midY - size.height / 2,
                             low: bounds.minY + margin, high: bounds.maxY - margin - size.height))
        case .right:
            CGPoint(x: clear.maxX + gap,
                    y: clamp(anchor.midY - size.height / 2,
                             low: bounds.minY + margin, high: bounds.maxY - margin - size.height))
        case .above:
            CGPoint(x: clamp(anchor.midX - size.width / 2,
                             low: bounds.minX + margin, high: bounds.maxX - margin - size.width),
                    y: clear.minY - gap - size.height)
        case .below:
            CGPoint(x: clamp(anchor.midX - size.width / 2,
                             low: bounds.minX + margin, high: bounds.maxX - margin - size.width),
                    y: clear.maxY + gap)
        }
    }

    /// Held between the two edges, and where they have crossed — a window
    /// narrower than the words — the low one wins, so the sentence starts
    /// where it can be read from rather than ending where it cannot.
    private static func clamp(_ value: CGFloat, low: CGFloat, high: CGFloat) -> CGFloat {
        guard high > low else { return low }
        return min(max(value, low), high)
    }
}
