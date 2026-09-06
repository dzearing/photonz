import CoreGraphics
import Foundation

/// The numbers a component can offer as a knob, and how one is read off a layer
/// and written back onto it (`docs/design/ui-building.md`, step C6).
///
/// A layer has dozens of numbers on it — where it sits, how big it is, how faded
/// it is, how far its shadow falls — and offering all of them would rebuild the
/// twenty-four row Add menu that grouping the menu by kind exists to stop. Four
/// earn their place, and every one of them is a number a person already types
/// into the inspector for an ordinary layer: how round it is, how thick the line
/// round it is, how far apart a stack holds its contents, and how much room a
/// group keeps clear inside its edges.
///
/// The reason those four and not others: they are the numbers that make one
/// component look like a family rather than like one drawing. Position and size
/// are the copy's own already; a fade, a blur and a shadow are the copy's own
/// already too, part by part (`ComponentStyle.swift`). These four sit on a layer
/// INSIDE the original, where a copy has no other way to reach them at all.
///
/// Two of them, the gap and the room, are also offered on the original's OWN
/// outermost layer: a card built as one stack keeps its room there and nowhere
/// else, so without that a card is stuck with one roominess for every copy it
/// will ever have. `onTheComponentItself` is that shorter list, and the reason
/// it is shorter is written on it.

// MARK: - Which number

/// One of a layer's adjustable numbers. Named for what the inspector calls it,
/// because a knob is met in the same words the canvas control is.
public enum ComponentNumberSlot: String, CaseIterable, Hashable, Codable, Sendable {
    /// How round the corners are, whichever way this layer rounds.
    case cornerRadius
    /// How thick the line round this shape is.
    case thickness
    /// How far apart a stack or grid holds the things in it.
    case gap
    /// The room a group keeps clear inside its edges, all four sides of it.
    case padding

    /// Whether this number is four numbers. Only room is: a gap, a rounding
    /// and a thickness are one number each, and always were.
    ///
    /// Room used to be offered only while its four sides agreed, which read
    /// well until you noticed that almost nothing real is built that way. A
    /// button keeps less room above and below than beside; every starter
    /// component but the card does the same. So room carries its four sides,
    /// and a copy meets them in the control the canvas already uses for room.
    public var isFourSided: Bool { self == .padding }

    /// What the knob is called where a person meets it, and what a new knob is
    /// named before anybody renames it.
    public var title: String {
        switch self {
        case .cornerRadius: return "Corner radius"
        case .thickness: return "Thickness"
        case .gap: return "Gap"
        case .padding: return "Padding"
        }
    }

    /// The sentence under the pointer on a copy's row: what turning this
    /// actually changes.
    public var help: String {
        switch self {
        case .cornerRadius: return "How round the corners are."
        case .thickness: return "How thick the line round it is."
        case .gap: return "The space between one thing and the next."
        case .padding:
            return "The room kept clear inside the edges. "
                + "Type one number for all four sides, or open them to set each one."
        }
    }

    /// The numbers a component can offer on its OWN outermost edges, as opposed
    /// to on a layer inside it.
    ///
    /// Only the two that hold contents apart. A card's rounding and the line
    /// round it are deliberately absent, because a copy already owns those part
    /// by part the moment it is given one (`LayerStyle.following`), and two
    /// mechanisms writing one field is the two-sliders bug
    /// `CornerRadiusSelection.swift` exists to end. How much room a card keeps
    /// inside its edges has no such second way in, which is why it needs this
    /// one.
    public static let onTheComponentItself: [ComponentNumberSlot] = [.gap, .padding]
}

// MARK: - The two a layout holds

extension GroupLayout {

    /// What this layout reads for one number, or nil where it has none at all:
    /// nothing is being held apart in a group that arranges nothing.
    ///
    /// Room answers with its four sides even when they agree, so one shape of
    /// answer covers every group and nothing downstream has to ask which kind
    /// of room it is looking at.
    func knobValue(for slot: ComponentNumberSlot) -> ComponentPropertyValue? {
        switch slot {
        case .gap: return kind == nil ? nil : .number(usedGap)
        case .padding: return .room(usedPadding)
        case .cornerRadius, .thickness: return nil
        }
    }

    /// Writes one of them, each the way that number is written. An answer of
    /// the wrong shape for the slot is left alone rather than guessed at.
    mutating func setKnobValue(_ value: ComponentPropertyValue,
                               for slot: ComponentNumberSlot) {
        switch slot {
        case .gap:
            guard kind != nil, let number = value.numberValue else { return }
            gap = max(0, number)
            // Typing a gap is asking for that gap to be held, so a stack that
            // was sharing its leftover room stops, exactly as it does when the
            // number is typed into the inspector.
            spreadsGap = false
        case .padding:
            // One number over the closed field still means the same room all
            // round, which is what `asRoom` reads it as.
            guard let room = value.asRoom else { return }
            padding = room.used
        case .cornerRadius, .thickness:
            return
        }
    }
}

// MARK: - Reading and writing one number on one layer

extension Layer {

    /// Whether rounding this layer means anything. A rectangle curves the
    /// outline it draws; a picture, a group or a screen has its corners masked
    /// off. A line, an arrow, a label, a measurement and a zoom callout have no
    /// corners either way, so rounding them is a knob that would do nothing.
    var hasRoundableCorners: Bool {
        switch content {
        case .annotation(let annotation): return annotation.shape == .rectangle
        case .image, .collage, .group: return true
        case .text, .measure, .zoomCallout: return false
        }
    }

    /// How round this layer is right now, reading whichever number is actually
    /// rounding it.
    ///
    /// A rectangle's own curve normally speaks for it. The exception is a
    /// rectangle rounded by the old Effects mask and nothing else: reading
    /// nought there would deny what is plainly on the canvas.
    /// `style` is passed in so a caller previewing a drag reads what is on
    /// screen rather than what is on disk.
    func roundedCornerRadius(style: LayerStyle) -> CGFloat {
        guard roundsItsOwnOutline else { return style.cornerRadius }
        let own = annotation?.cornerRadius ?? 0
        return own > 0 ? own : style.cornerRadius
    }

    /// How round this layer is, as it stands.
    var roundedCornerRadius: CGFloat { roundedCornerRadius(style: style) }

    /// Rounds this layer the way it rounds: a rectangle by curving its own
    /// outline, everything else by masking its picture. The other number goes to
    /// nought, because two radii fighting over one rectangle is the thing the
    /// one Corner Radius row exists to end (`CornerRadiusSelection.swift`).
    mutating func setRoundedCorners(_ radius: CGFloat) {
        let radius = max(0, radius)
        guard roundsItsOwnOutline, var annotation else {
            style.cornerRadius = radius
            return
        }
        annotation.cornerRadius = radius
        content = .annotation(annotation)
        style.cornerRadius = 0
    }

    /// Sets the one line round this shape, folding away any border ring the old
    /// Effects slider left on it, colour and all, so it ends up wearing one ring
    /// instead of two (`OutlineWidth.swift`).
    mutating func setOutlineWidth(_ width: CGFloat) {
        guard drawsItsOwnOutline, var annotation else { return }
        let color = outlineColorHex
        annotation.strokeWidth = max(0, width)
        annotation.colorHex = color
        content = .annotation(annotation)
        style.borderWidth = 0
    }

    /// What this layer reads for one number, or nil where it has no such number
    /// at all. Nil is what keeps a knob honest: a label has no gap, so it is
    /// never offered one, and a group whose four sides disagree has no ONE room
    /// to show, so it is not offered room either.
    func knobValue(for slot: ComponentNumberSlot) -> ComponentPropertyValue? {
        switch slot {
        case .cornerRadius:
            return hasRoundableCorners ? .number(roundedCornerRadius) : nil
        case .thickness:
            return drawsItsOwnOutline ? .number(outlineWidth) : nil
        case .gap, .padding:
            // Only something that arranges its contents holds them apart, and
            // only a group that has been given a layout keeps room at its
            // edges, so the layout answers for both.
            return group?.layout?.knobValue(for: slot)
        }
    }

    /// The one number this layer reads for a slot, where that slot IS one
    /// number. Room is four, so it answers nil here and is read as room.
    func number(for slot: ComponentNumberSlot) -> CGFloat? {
        knobValue(for: slot)?.numberValue
    }

    /// The room this layer keeps inside its edges, all four sides.
    func room(for slot: ComponentNumberSlot) -> GroupPadding? {
        knobValue(for: slot)?.roomValue
    }

    /// Writes one number onto this layer, each the way that number is written.
    mutating func setKnobValue(_ value: ComponentPropertyValue,
                               for slot: ComponentNumberSlot) {
        switch slot {
        case .cornerRadius:
            guard let number = value.numberValue else { return }
            setRoundedCorners(max(0, number))
        case .thickness:
            guard let number = value.numberValue else { return }
            setOutlineWidth(max(0, number))
        case .gap, .padding:
            guard var layout = group?.layout else { return }
            layout.setKnobValue(value, for: slot)
            setGroupLayout(layout)
        }
    }

    /// The numbers of this layer that could become knobs: the ones it has.
    var knobNumberSlots: [ComponentNumberSlot] {
        ComponentNumberSlot.allCases.filter { knobValue(for: $0) != nil }
    }
}
