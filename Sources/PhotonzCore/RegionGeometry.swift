import CoreGraphics

/// The selection box as four typed numbers.
///
/// The Position & Size fields normally speak for the picked layers. While a
/// selection tool has the arrow keys they speak for the MARQUEE instead, and
/// this is what they show and what typing in them does — because a panel that
/// goes on reporting a layer's numbers while the keys are walking the marquee
/// is describing something the keyboard is not touching.
///
/// Which of the two the panel is reading is `Nudge.target`, the same rule the
/// arrow keys use, so the numbers and the keys can never disagree about whose
/// they are.
///
/// Everything here is the box, not the outline: a marquee round a button reads
/// its exact size, and typing a width scales the outline to it. There is no
/// Mixed and nothing is read-only, because there is exactly one selection.
public struct RegionGeometry: Hashable, Sendable {

    /// The selection's bounding box, in document points, top-left origin.
    public let bounds: CGRect

    public init(bounds: CGRect) {
        self.bounds = bounds
    }

    /// What a field shows: the box's own number, rounded to whole points the
    /// same way a layer's is, so the digits and the arrow keys agree.
    public func reading(_ field: LayerGeometryField) -> LayerGeometryReading {
        .agreed(LayerGeometry.displayValue(field, of: bounds))
    }

    /// The line under the fields.
    ///
    /// Its whole job is saying whose numbers these are. The section swapped
    /// from a layer to the marquee the moment a selection tool came out, and
    /// the person looking at it did not ask for that in so many words, so the
    /// panel says it rather than leaving them to work it out from the digits.
    public var caption: String {
        "The selection box, not the layer under it, "
            + "\(LayerGeometry.unitSuffix) from the top left. "
            + "Up or down arrow steps by 1, Shift by 10."
    }

    /// The hover tip for one field. The layer wording with the selection named
    /// in it, so a tip read out of context still says what it is describing.
    public static func help(_ field: LayerGeometryField) -> String {
        switch field {
        case .x: "Distance from the left edge of the canvas to the selection"
        case .y: "Distance from the top edge of the canvas to the selection"
        case .width: "Width of the selection"
        case .height: "Height of the selection"
        }
    }

    /// The box after `value` is typed into `field`, or nil when nothing would
    /// move: a number equal to what is already there, or one that is not a
    /// number at all, leaves the selection exactly as it was.
    ///
    /// Position is free to go negative, and a size stops at the same floor a
    /// layer's does, both for the same reason they do there: the marquee may
    /// hang off the picture, and there is nothing left to see below a point.
    public func applying(_ value: CGFloat, to field: LayerGeometryField) -> CGRect? {
        changed(LayerGeometry.applying(value, to: field, of: bounds))
    }

    /// The box after one arrow-key press, counted from the whole number on
    /// screen so holding the key walks 296, 297, 298 rather than drifting on a
    /// fraction the field never showed. Nil when the press changes nothing,
    /// which is what a Down at the floor does.
    public func stepping(_ field: LayerGeometryField, direction: Int,
                         coarse: Bool) -> CGRect? {
        let stepped = LayerGeometry.stepped(LayerGeometry.value(field, of: bounds),
                                            direction: direction, coarse: coarse)
        return applying(stepped, to: field)
    }

    private func changed(_ box: CGRect) -> CGRect? { box == bounds ? nil : box }
}
