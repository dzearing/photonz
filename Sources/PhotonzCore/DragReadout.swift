import CoreGraphics
import Foundation

/// The small pill the canvas carries under whatever is being dragged, and the
/// rules behind it: what it says, and where it goes.
///
/// The numbers used to live in the right hand panel, which followed a drag in
/// flight. The panel's Position & Size section is now something you ask for
/// rather than something that is always open, so the live half of that reading
/// had nowhere to go. This is the better home for it anyway: it is where the
/// eye already is, so the reading does not cost a glance across the window.
///
/// Two decisions worth keeping. The pill says the reading the drag is
/// CHANGING — where for a move, how big for everything else — because four
/// numbers under a moving box is a table, and the half you are not changing is
/// noise you have to read past. And it is anchored to the BOX rather than the
/// pointer, so one rule covers a sweep (which has no layer under it) and a
/// whole selection dragged at once (which has no single layer), and so the
/// reading sits still relative to the thing it describes.
public enum DragReadout {

    /// Which reading a pill carries.
    public enum Subject: Equatable, Hashable, Sendable {
        case position(CGPoint)
        case size(CGSize)
        /// How round a corner is being pulled, by the knob inside it.
        case radius(CGFloat)
        /// A layer turned or pushed in space by one of its 3D handles: the
        /// one value that handle changes (`SpaceDrag.readout`).
        case space(SpaceHandle, LayerTurn3D)
    }

    /// What is being dragged, for the one rule that picks the reading.
    public enum Kind: Equatable, Hashable, Sendable {
        /// A layer, or a whole selection, moved across the canvas.
        case move
        /// A handle pulled on one layer.
        case resize
        /// A selection box swept out over the picture.
        case sweep
        /// A point or a lever pulled on a path.
        case reshape
    }

    /// The reading a drag of this kind wants, off the box it is standing on.
    public static func subject(_ kind: Kind, box: CGRect) -> Subject {
        switch kind {
        case .move: .position(box.origin)
        case .resize, .sweep, .reshape: .size(box.size)
        }
    }

    /// The words on the pill.
    ///
    /// No unit word. Every number here is in the one space the document
    /// measures in (`DocumentUnit`), there is no second unit it could be, and a
    /// pill riding under a moving box is read at a glance rather than copied
    /// into a spec — which is the job the caliper readouts do, and they say the
    /// unit. "580 × 448" is also the form every tool that draws writes a size
    /// in, so it needs no teaching.
    ///
    /// `lengths` is what the picture counts in, so a pill on an icon says the
    /// numbers the panel will read when the button comes up.
    public static func text(_ subject: Subject, in lengths: LengthUnit = .point) -> String {
        func length(_ value: CGFloat) -> String {
            lengths.isPoint ? whole(value) : lengths.spell(lengths.reading(value))
        }
        return switch subject {
        case .position(let point): "\(length(point.x)), \(length(point.y))"
        case .size(let size): "\(length(size.width)) × \(length(size.height))"
        // Named, because one bare number under a shape could be anything.
        // Half points stay, since a radius of 1.5 is an ordinary one on an
        // icon grid.
        case .radius(let radius): "Radius \(lengths.isPoint ? halves(radius) : length(radius))"
        case .space(let handle, let turn): SpaceDrag.readout(handle, turn)
        }
    }

    /// The pill for a hand on a layer whose changes key themselves: the
    /// diamond and the playhead time, then the size pill's words (`sizeTag`),
    /// so where the change lands is read without looking down at the strip
    /// (`picture-keys.html`, "Showing that a change will key"). Hundredths,
    /// as the strip writes a key's time, because whole seconds cannot tell
    /// two keys apart.
    public static func keyed(_ words: String, atMS ms: Int) -> String {
        "\(keyMark) \(KeyLap.timecode(ms: ms)) · \(words)"
    }

    /// The diamond a keyed reading starts with: the strip's key, in type.
    public static let keyMark = "◆"

    /// The size pill's words for one layer: its size, and any turn the way
    /// the tag at rest writes one (`SelectionTag.resting`), so the label
    /// under the layer keeps one voice from rest to drag. It is what a hand
    /// on a keyed layer reads, whether it moves, pulls or turns it: the mock
    /// draws the size pill for all three.
    public static func sizeTag(_ size: CGSize, rotation degrees: Double,
                               in lengths: LengthUnit = .point) -> String {
        var words = text(.size(size), in: lengths)
        let turned = degrees.rounded()
        if turned != 0, turned.truncatingRemainder(dividingBy: 360) != 0 {
            words += " · \(whole(CGFloat(turned)))°"
        }
        return words
    }

    /// Where the pill goes, in the same space `box` and `bounds` are in: the
    /// canvas view's own, top-left origin, y growing downward.
    ///
    /// Centred under the box and clear of it by `gap`. Under rather than over
    /// because a frame already wears its name above its top left corner, and
    /// two labels on one edge is a pile.
    ///
    /// Three placements are tried in order, and the order is the promise the
    /// pill makes: below the box, above it, and — only when the box is bigger
    /// than the window and there is no outside left — inside the bottom of the
    /// window. That last one is the single case where the pill sits over what
    /// it describes, and the alternative is a reading nobody can see.
    public static func plate(for box: CGRect, size: CGSize,
                             in bounds: CGRect, gap: CGFloat) -> CGRect {
        let x = clamped(box.midX - size.width / 2,
                        low: bounds.minX, high: bounds.maxX - size.width)
        let below = box.maxY + gap
        let above = box.minY - gap - size.height
        let y: CGFloat
        if below + size.height <= bounds.maxY {
            y = below
        } else if above >= bounds.minY {
            y = above
        } else {
            y = clamped(below, low: bounds.minY, high: bounds.maxY - size.height)
        }
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// To the nearest half, written without a trailing ".0".
    private static func halves(_ value: CGFloat) -> String {
        let doubled = Int((max(0, value) * 2).rounded())
        return doubled % 2 == 0 ? "\(doubled / 2)" : "\(doubled / 2).5"
    }

    /// Whole numbers, and never the "-0" that rounding a small negative gives.
    private static func whole(_ value: CGFloat) -> String {
        let rounded = Int(value.rounded())
        return rounded == 0 ? "0" : "\(rounded)"
    }

    private static func clamped(_ value: CGFloat, low: CGFloat, high: CGFloat) -> CGFloat {
        guard high > low else { return low }
        return min(max(value, low), high)
    }
}
