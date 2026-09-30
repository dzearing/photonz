import CoreGraphics

/// How a row of worded segments uses the room it is given, most generous
/// first: equal columns, then the system's own width for each word with the
/// rest shared out, then each word with a tighter margin, and only when even
/// that would cut a word short, a dropdown of the same choices.
///
/// The tighter step exists because the system control pads every word by
/// about 18pt, and two rows that had always fit their words did not fit that
/// padding: the colour picker's Shades | Related | Document | Recent and a
/// Mixed Arrangement's Free | Stack | Grid (133pt asked at the small size,
/// 113pt given beside the word Mixed). Both became dropdowns on 2026-09-29,
/// the Mixed one empty.
public enum SegmentRoom: Equatable, Sendable {
    case equal
    case proportional
    case tight
    case tooNarrow

    /// The room either side of a word in a tight row, in points: 5pt a side.
    /// Photographed in the app on 2026-09-30, every word whole at the small size.
    public static let tightMargin: CGFloat = 10

    /// Which layout a row gets, given the widths it asks for each way.
    public static func layout(available: CGFloat, equal: CGFloat, systemFit: CGFloat,
                              tight: CGFloat) -> SegmentRoom {
        if available >= equal { return .equal }
        if available >= systemFit { return .proportional }
        if available >= tight { return .tight }
        return .tooNarrow
    }

    /// The least a tight row takes: every word, a margin each, and the
    /// control's own edge (`chrome`).
    public static func tightWidth(words: [CGFloat], chrome: CGFloat) -> CGFloat {
        words.reduce(0, +) + CGFloat(words.count) * tightMargin + chrome
    }

    /// Each segment's width in a tight row filling `available`: its word and
    /// margin, plus an even share of whatever is left over.
    public static func tightWidths(words: [CGFloat], available: CGFloat, chrome: CGFloat) -> [CGFloat] {
        guard !words.isEmpty else { return [] }
        let spare = max(0, available - tightWidth(words: words, chrome: chrome)) / CGFloat(words.count)
        return words.map { $0 + tightMargin + spare }
    }
}
