import CoreGraphics

/// Picking a section of the right hand dock up and putting it somewhere else
/// in the column.
///
/// The whole thing is one rule: **a section moves aside when the pointer
/// passes its middle**, never when the section you are carrying first touches
/// it. Touching is where a drag begins, so swapping on touch rearranges the
/// column before you have decided anything, and then rearranges it back the
/// moment you drift a point the other way.
///
/// Everything here is measured down from the top of the column, in points, and
/// nothing here knows what a section IS: give it the spans the sections
/// currently occupy and it answers with a slot and a set of offsets.
public enum SectionReorderDrag {

    /// Where one section rests in the column when nothing is being dragged.
    public struct Span: Equatable, Sendable {
        /// The section's top edge, measured down from the top of the column.
        public var top: CGFloat
        /// How tall the section is, including anything drawn under it that
        /// travels with it (its divider).
        public var height: CGFloat

        public init(top: CGFloat, height: CGFloat) {
            self.top = top
            self.height = height
        }

        /// The line the pointer has to cross for this section to move aside.
        public var middle: CGFloat { top + height / 2 }
    }

    /// The slot the section being dragged is currently offering to land in.
    ///
    /// Read against the spans the sections rest in, NOT against where they are
    /// drawn mid-drag: the decision lines stay still while the sections slide,
    /// so a pointer held on one spot always gets the same answer and the
    /// column cannot flicker between two slots.
    ///
    /// - Parameters:
    ///   - dragging: which section is in the air, as an index into `spans`.
    ///   - pointerY: where the pointer is, down from the top of the column.
    ///   - spans: every section's resting span, in the order they are drawn.
    public static func target(dragging: Int, pointerY: CGFloat, spans: [Span]) -> Int {
        guard spans.indices.contains(dragging) else { return dragging }
        var slot = dragging
        // Down the column: each section below hands its slot over as the
        // pointer crosses its middle.
        while slot + 1 < spans.count, pointerY > spans[slot + 1].middle { slot += 1 }
        guard slot == dragging else { return slot }
        // Up the column. Only ever one of the two runs: the pointer cannot be
        // below one middle and above another at the same time.
        while slot - 1 >= 0, pointerY < spans[slot - 1].middle { slot -= 1 }
        return slot
    }

    /// How far section `index` should be drawn from where it rests, so the
    /// gap the dragged section will drop into is open.
    ///
    /// The dragged section itself always answers zero: it follows the pointer,
    /// which is the caller's business, not this one's.
    public static func offset(of index: Int, dragging: Int, target: Int, spans: [Span]) -> CGFloat {
        guard spans.indices.contains(dragging), spans.indices.contains(index),
              index != dragging, target != dragging else { return 0 }
        let step = spans[dragging].height
        if target > dragging { return (dragging + 1...target).contains(index) ? -step : 0 }
        return (target...dragging - 1).contains(index) ? step : 0
    }

    /// The order the column is left in once the section is let go.
    public static func reordered<T>(_ items: [T], moving: Int, to target: Int) -> [T] {
        guard items.indices.contains(moving), items.indices.contains(target),
              moving != target else { return items }
        var moved = items
        moved.insert(moved.remove(at: moving), at: target)
        return moved
    }
}
