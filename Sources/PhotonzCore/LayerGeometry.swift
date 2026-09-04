import CoreGraphics
import Foundation

/// One typed geometry number in the inspector: where a layer sits and how big
/// it is. Four fields, labelled the way every design tool labels them, so
/// nobody has to learn a new vocabulary to make two buttons the same width.
public enum LayerGeometryField: String, CaseIterable, Hashable, Sendable {
    case x
    case y
    case width
    case height

    /// The one- or two-letter label beside the field.
    public var label: String {
        switch self {
        case .x: "X"
        case .y: "Y"
        case .width: "W"
        case .height: "H"
        }
    }

    /// The same field in words, for the hover tip: a letter says which box to
    /// type in, not what the number means.
    public var title: String {
        switch self {
        case .x: "Distance from the left edge of the canvas"
        case .y: "Distance from the top edge of the canvas"
        case .width: "Width"
        case .height: "Height"
        }
    }

    /// Whether this field changes the layer's size (rather than its position).
    public var isSize: Bool { self == .width || self == .height }
}

/// Reading and writing a layer's frame as four typed numbers.
///
/// Everything here is in document points, the same units the measure readouts
/// call "px", so a number measured with the caliper can be typed straight into
/// a field. The document model's origin is top left, so X grows right and Y
/// grows down, and a typed size grows to the right and downward — the same
/// direction the canvas size fields grow.
public enum LayerGeometry {

    /// The unit word beside the numbers. Deliberately the measure readouts'
    /// suffix, so the two surfaces never disagree about what a number means.
    public static var unitSuffix: String { MeasureUnit.pixels.suffix }

    /// The smallest a typed width or height may make a layer: below one point
    /// there is nothing left to see or grab. Some layers stop sooner than this
    /// — a text box floors where its drag does — which is
    /// `LayerGeometryEditing.minimum(for:)`.
    public static let minimumSide: CGFloat = 1

    /// A ceiling on a typed size, so a slipped keystroke ("29600000") cannot
    /// ask the renderer for a surface no machine can allocate.
    public static let maximumSide: CGFloat = 100_000

    /// What one arrow-key press changes the number by. The same 1 and 10 the
    /// canvas nudges a layer by (`Nudge`), so a field and the canvas answer an
    /// arrow key the same way.
    public static let step: CGFloat = 1

    /// What Shift plus an arrow key changes it by.
    public static let coarseStep: CGFloat = 10

    /// The exact number behind a field.
    public static func value(_ field: LayerGeometryField, of frame: CGRect) -> CGFloat {
        switch field {
        case .x: frame.minX
        case .y: frame.minY
        case .width: frame.width
        case .height: frame.height
        }
    }

    /// The number the field actually shows: whole points. A frame that came
    /// from a drag carries fractions nobody typed, and showing 296 while
    /// holding 295.5 would make the next arrow-key press look broken, so the
    /// display, the stepping and the typing all agree on the rounded value.
    public static func displayValue(_ field: LayerGeometryField, of frame: CGRect) -> CGFloat {
        value(field, of: frame).rounded()
    }

    /// The frame after `value` is typed into `field`.
    ///
    /// Position is free to go negative (a layer may hang off the canvas the
    /// same way a drag can put it there). Size is clamped into a range that
    /// still renders. A value that is not a real number leaves the frame
    /// untouched, so a half-typed "-" or "1e" never moves anything.
    ///
    /// `notBelow` is the layer's own floor, for the layers that stop before
    /// one point: pass `LayerGeometryEditing.minimum(for:)` and a typed width
    /// stops exactly where dragging that layer's edge stops. Nil means the
    /// ordinary floor.
    public static func applying(_ value: CGFloat, to field: LayerGeometryField,
                                of frame: CGRect, notBelow floor: CGFloat? = nil) -> CGRect {
        guard value.isFinite else { return frame }
        var result = frame
        switch field {
        case .x: result.origin.x = value
        case .y: result.origin.y = value
        case .width: result.size.width = clampedSide(value, notBelow: floor)
        case .height: result.size.height = clampedSide(value, notBelow: floor)
        }
        return result
    }

    /// The number one arrow-key press produces: whole steps from the whole
    /// number on screen, so holding the key walks 296, 297, 298 rather than
    /// drifting on a fraction the field never showed.
    public static func stepped(_ value: CGFloat, direction: Int, coarse: Bool) -> CGFloat {
        guard value.isFinite, direction != 0 else { return value }
        let amount = coarse ? coarseStep : step
        return value.rounded() + CGFloat(direction.signum()) * amount
    }

    /// The number in a field's text, or nil when there is no number in it.
    ///
    /// Forgiving about the things a person actually does — spaces around the
    /// number, a leading plus, a pasted unit word ("296 px"), the minus sign a
    /// word processor substitutes — and strict about everything else. A field
    /// holding anything that is not plainly one number changes nothing and
    /// snaps back to what the layer really is, which beats guessing what a
    /// comma in "1,296" was supposed to mean.
    public static func parse(_ text: String) -> CGFloat? {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if cleaned.hasSuffix(unitSuffix) {
            cleaned = String(cleaned.dropLast(unitSuffix.count))
                .trimmingCharacters(in: .whitespaces)
        }
        cleaned = cleaned.replacingOccurrences(of: "\u{2212}", with: "-") // a typographic minus
        if cleaned.hasPrefix("+") { cleaned = String(cleaned.dropFirst()) }
        guard !cleaned.isEmpty else { return nil }
        // Digits, at most one dot, an optional leading minus. Nothing else, so
        // "1e9", "296,5" and "wide" all read as no number at all.
        var body = Substring(cleaned)
        if body.hasPrefix("-") { body = body.dropFirst() }
        guard !body.isEmpty, body.allSatisfy({ $0.isNumber || $0 == "." }),
              body.filter({ $0 == "." }).count <= 1, body.contains(where: \.isNumber) else {
            return nil
        }
        guard let value = Double(cleaned), value.isFinite else { return nil }
        return CGFloat(value)
    }

    private static func clampedSide(_ value: CGFloat, notBelow floor: CGFloat? = nil) -> CGFloat {
        min(max(value, max(floor ?? minimumSide, minimumSide)), maximumSide)
    }
}

/// Which of a layer's four numbers accept typing, and why the others do not.
///
/// The rule is that a field is typeable exactly where the canvas already lets
/// you drag the same thing. Every layer can be moved, so X and Y are open
/// unless the layer is locked. Size is another matter: an arrow's box is
/// padding around a shaft rather than the shape you drew, and a measurement is
/// edited by its feet, so neither takes a typed width — a number that never
/// matched what is on screen is worse than no number at all. Text takes a
/// width, which is its wrap width, but its height follows the re-wrap.
///
/// A field that takes nothing is not always a field with nothing to say:
/// `shows(_:)` is the second question, and it is how a wrapped paragraph
/// reports the height it turned out to be.
public struct LayerGeometryEditing: Hashable, Sendable {

    /// Why a piece inside a group that closes around its contents has no typed
    /// position: the room around it is the group's Padding.
    public static let huggedReason = "The group this is in is as big as what is inside it, so the room around this is the group's Padding in the Layout section."

    /// Why nothing on a locked layer can be typed.
    public static let lockedReason = "This layer is locked. Unlock it in the Layers list to change its position or size."

    /// Why a shape drawn end to end has no typeable size.
    public static let endpointReason = "Drag this shape's ends on the canvas to change its size."

    /// Why a copy of a component has no typeable size: it is the size of the
    /// original it follows, and a stretched copy would snap straight back.
    public static let instanceSizeReason = "A copy is the size of the original. Resize the original component and every copy follows."

    /// Why a measurement has no typeable size.
    public static let measurementReason = "Drag this measurement's ends on the canvas to change what it measures."

    /// Why text has no typeable height.
    public static let textHeightReason = "Height follows the text. Change the width to re-wrap it, or the font size in the Text section."

    /// The same field on a piece of text told to fill the box holding it: its
    /// height stopped being the text's answer the moment something else took
    /// it over, so the tip points at the control that owns it now.
    public static let filledHeightReason = "This is stretched to fill the height of what holds it. Change that container's height, or pick a different Vertical in the Layout section."

    /// Why a layer in a stack has no typeable position: the stack decides it,
    /// and a typed number would be put straight back. Says what to do instead.
    public static let stackedReason = "The stack this is in decides where it sits. Change the group's Gap or Direction in the Layout section, or drag this past its neighbours to reorder them."

    /// The same for a grid.
    public static let griddedReason = "The grid this is in decides where it sits. Change the group's Columns or gaps in the Layout section, or drag this past its neighbours to reorder them."

    public let canMove: Bool
    public let canSetWidth: Bool
    public let canSetHeight: Bool

    /// Whether a lock is what is stopping this layer. It is the one state that
    /// takes all four numbers away at once and for a single reason, which is
    /// why the panel can say it in one line under the fields instead of making
    /// you hover a dead box to find out.
    public let isLocked: Bool

    /// Whether the layer's box is the thing you see. It is for nearly
    /// everything, and it is not for a line, an arrow or a caliper: those are
    /// drawn between two points and their box is padding around the stroke, so
    /// its width was never a number about the shape.
    private let frameIsTheShape: Bool

    /// The narrowest a typed width may make this layer, and the shortest a
    /// typed height may. A text box stops at the width its drag stops at, so
    /// the two ways of setting a width land in the same place; everything else
    /// stops at one point, which is where its drag stops.
    public let minimumWidth: CGFloat
    public let minimumHeight: CGFloat

    private let widthReason: String?
    private let heightReason: String?
    private let moveReason: String?

    /// `container` is the group this layer sits in, when it has one. It only
    /// matters when that group arranges itself: a stack or a grid decides
    /// where its contents sit, so typing a position there would be undone
    /// before you saw it, and the field says who owns it instead.
    public init(layer: Layer, in container: Layer? = nil) {
        // Text is the one content with a floor of its own: below it a caption
        // is an unreadable sliver, so the canvas refuses to drag one narrower
        // and the field refuses to type one.
        minimumWidth = layer.resizeWidthOnly ? TextMeasurement.minimumWidth
                                             : LayerGeometry.minimumSide
        minimumHeight = LayerGeometry.minimumSide
        frameIsTheShape = !layer.hasEndpointHandles
        isLocked = layer.isLocked
        if layer.isLocked {
            canMove = false
            canSetWidth = false
            canSetHeight = false
            widthReason = Self.lockedReason
            heightReason = Self.lockedReason
            moveReason = Self.lockedReason
            return
        }
        // A container that arranges its contents, or that closes around them,
        // owns where they sit; one that was given a size on both axes and
        // arranges nothing leaves them exactly where you put them.
        if let layout = container?.group?.layout,
           layout.arranges || layout.hugsWidth || layout.hugsHeight {
            canMove = false
            moveReason = switch layout.kind {
            case .grid: Self.griddedReason
            case .stack: Self.stackedReason
            case nil: Self.huggedReason
            }
        } else {
            canMove = true
            moveReason = nil
        }
        if layer.allowsFrameResize {
            canSetWidth = true
            canSetHeight = !layer.resizeWidthOnly
            widthReason = nil
            heightReason = layer.resizeWidthOnly
                ? (layer.heightIsFilled(in: container) ? Self.filledHeightReason
                                                       : Self.textHeightReason)
                : nil
        } else {
            canSetWidth = false
            canSetHeight = false
            let reason: String
            if layer.isGroup { reason = Self.instanceSizeReason }
            else if layer.measure != nil { reason = Self.measurementReason }
            else { reason = Self.endpointReason }
            widthReason = reason
            heightReason = reason
        }
    }

    /// Whether this field takes a typed number.
    public func allows(_ field: LayerGeometryField) -> Bool {
        switch field {
        case .x, .y: canMove
        case .width: canSetWidth
        case .height: canSetHeight
        }
    }

    /// Whether this field's number is worth showing when it cannot be typed.
    ///
    /// A number you cannot change is still a number you may want to read: how
    /// tall a paragraph came out once it wrapped, where the stack put a row,
    /// how big the original a copy follows is. It is only worth showing when
    /// the box really is what you see, which is why a line, an arrow or a
    /// caliper still shows no size — its box is padding around a stroke, and a
    /// width that never matched the shape you drew is worse than a blank.
    public func shows(_ field: LayerGeometryField) -> Bool {
        switch field {
        case .x, .y: return true
        case .width, .height: return frameIsTheShape
        }
    }

    /// The floor this field stops at, or nil for a field with no floor: a
    /// position may go anywhere, including off the canvas.
    public func minimum(for field: LayerGeometryField) -> CGFloat? {
        switch field {
        case .x, .y: nil
        case .width: minimumWidth
        case .height: minimumHeight
        }
    }

    /// A plain sentence explaining why a field does not take a number, for the
    /// hover tip. Nil when the field is editable.
    public func fixedReason(for field: LayerGeometryField) -> String? {
        guard !allows(field) else { return nil }
        switch field {
        case .x, .y: return moveReason
        case .width: return widthReason
        case .height: return heightReason
        }
    }
}
