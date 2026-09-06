import CoreGraphics

/// The arithmetic behind the grab bar under a bounded panel area — the layers
/// list, the Library shelf.
///
/// The bar sets a CEILING: how tall that area may get before it scrolls on its
/// own, so the sections under it stay in view. The area is then drawn at its
/// content height or that ceiling, whichever is smaller, which is what keeps a
/// short list from leaving a patch of empty glass under itself.
///
/// That pairing is what made the bar dead. A ceiling above the content is a
/// number nothing reads: dragging moved it and the area stayed exactly where it
/// was, while the pointer promised a resize the whole time. So the two rules
/// here are the ones the bar has to obey:
///
/// - There is only something to drag while the content is taller than the
///   area's floor. Under that, the area is already showing everything it has
///   and no ceiling can change it, so no bar is drawn at all.
/// - A drag can never leave the content behind. It travels between the floor
///   and the content's own height, so every point of it moves the area under
///   the pointer, one for one.
///
/// Pulling all the way to the bottom means "let it grow", not "stop here": the
/// ceiling stored is the highest one allowed rather than today's content, so a
/// list that gains a row afterwards still gains the room for it.
public enum PanelAreaResize {
    /// How near two heights have to be to count as the same one. Layout
    /// arrives as measured floating point, so nothing here compares exactly.
    public static let tolerance: CGFloat = 0.5

    /// The tallest the area can usefully be: its own content, or the hard
    /// ceiling the panel allows, whichever comes first. Past this there is
    /// nothing left to show.
    public static func ceiling(contentHeight: CGFloat, maxAllowedHeight: CGFloat) -> CGFloat {
        min(max(0, contentHeight), max(0, maxAllowedHeight))
    }

    /// Whether a grab bar belongs under this area at all: only once the
    /// content is taller than the floor, since below that every ceiling draws
    /// the same picture.
    public static func isResizable(contentHeight: CGFloat,
                                   minHeight: CGFloat,
                                   maxAllowedHeight: CGFloat) -> Bool {
        ceiling(contentHeight: contentHeight, maxAllowedHeight: maxAllowedHeight)
            > minHeight + tolerance
    }

    /// The height the area is actually given: its content, capped.
    public static func height(contentHeight: CGFloat, ceiling cap: CGFloat) -> CGFloat {
        min(max(0, contentHeight), max(0, cap))
    }

    /// Where a drag leaves the area, given the height it started at and how
    /// far the pointer has travelled down. Never below the floor, never past
    /// the content: both ends stop where a further pull would change nothing.
    public static func draggedHeight(base: CGFloat,
                                     translation: CGFloat,
                                     contentHeight: CGFloat,
                                     minHeight: CGFloat,
                                     maxAllowedHeight: CGFloat) -> CGFloat {
        let top = ceiling(contentHeight: contentHeight, maxAllowedHeight: maxAllowedHeight)
        return min(top, max(min(minHeight, top), base + translation))
    }

    /// The ceiling to remember after that drag.
    ///
    /// Anywhere short of the bottom it is the height itself. AT the bottom it
    /// is the highest ceiling the panel allows instead: a person who pulls the
    /// area open as far as it goes is asking for as much room as it needs, and
    /// storing today's content height would quietly stop the next row they add
    /// from getting any.
    public static func storedCeiling(base: CGFloat,
                                     translation: CGFloat,
                                     contentHeight: CGFloat,
                                     minHeight: CGFloat,
                                     maxAllowedHeight: CGFloat) -> CGFloat {
        let top = ceiling(contentHeight: contentHeight, maxAllowedHeight: maxAllowedHeight)
        let height = draggedHeight(base: base, translation: translation,
                                   contentHeight: contentHeight,
                                   minHeight: minHeight,
                                   maxAllowedHeight: maxAllowedHeight)
        return height >= top - tolerance ? max(0, maxAllowedHeight) : height
    }
}
