import CoreGraphics

/// How a layer's heading on the timing strip holds its name.
///
/// The column down the left stays one width, because the lanes and the ruler
/// start where it ends (and the video timeline's lanes start there too). So a
/// name that does not fit on one line takes a second, the way the Make a bell
/// swing mock wraps its long names, and the row grows to hold both. Only a name
/// two lines cannot hold is cut, in the middle, with the whole of it on the
/// tooltip.
public enum MotionStripHeading {
    /// The most lines a name is given before it is cut.
    public static let lineLimit = 2

    /// Lines the heading actually shows for a name that needs `needed`.
    public static func shownLines(forNeeded needed: Int) -> Int {
        min(lineLimit, max(1, needed))
    }

    /// Whether the name is cut, and so wants the tooltip carrying it whole.
    public static func isCut(neededLines: Int) -> Bool {
        neededLines > lineLimit
    }

    /// How tall the heading's row is: the row it always had, or as tall as its
    /// lines and a little air when they need more.
    public static func rowHeight(base: CGFloat, lines: Int, lineHeight: CGFloat) -> CGFloat {
        let shown = shownLines(forNeeded: lines)
        guard shown > 1 else { return base }
        return max(base, (CGFloat(shown) * lineHeight).rounded(.up) + 2)
    }
}
