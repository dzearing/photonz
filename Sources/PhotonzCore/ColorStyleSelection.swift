import Foundation

/// What one color row has to show when it is speaking for more than one layer.
///
/// Three boxes that all wear Accent have one thing to say. Three that wear
/// different things have none, and picking one of the three to print would be a
/// row claiming a style two of the layers under it are not wearing — which is
/// also how you unlink a style you never meant to touch. So the row either says
/// what they agree on or says out loud that they differ.
public enum ColorStyleReading: Hashable, Sendable {
    /// No picked layer has a color in this slot, so there is nothing to show.
    case empty
    /// They are all painted the same color, and none of them wears a style.
    case color(String)
    /// Every one of them wears this style.
    case style(UUID)
    /// They differ: different colors, different styles, or some styled and
    /// some not.
    case mixed
}

/// The layers one color row speaks for, and what picking a style in it does to
/// all of them.
///
/// One layer or twenty, the row means the same thing: this is the Fill, and
/// setting it sets it on everything picked. That is what turns "set these three
/// boxes to Accent" into one move instead of three, and it is why the row keeps
/// naming the style rather than describing some average color.
///
/// A layer sits out when the row cannot honestly reach it: a box with its fill
/// switched off has a fill slot and no fill color, and painting it would switch
/// the fill on behind the person's back; a locked layer must not be repainted
/// by a command aimed at the layers on top of it. The row says how many of the
/// picked layers it is speaking for whenever that is not all of them.
public struct ColorStyleSelection: Hashable, Sendable {

    /// One picked layer's color in this slot: what it is painted, and the
    /// style painting it when a style is.
    public struct Member: Hashable, Sendable {
        public let id: UUID
        public let colorHex: String
        public let styleID: UUID?

        public init(id: UUID, colorHex: String, styleID: UUID? = nil) {
            self.id = id
            self.colorHex = colorHex
            self.styleID = styleID
        }
    }

    /// What the row shows in place of a color when the layers differ.
    public static let mixedText = "Mixed"

    public let slot: ColorSlot
    public let members: [Member]
    /// How many layers are picked altogether, including the ones this slot
    /// skips, so the row can say what it does and does not reach.
    public let selectionCount: Int
    /// How many of the picked layers have this kind of color AT ALL, locked
    /// ones counted. A text block simply has no fill, and a Fill row that
    /// announced it was skipping it would be three lines of small print on any
    /// selection holding two kinds of layer. What is worth saying out loud is a
    /// layer the row COULD have reached and did not.
    public let capableCount: Int

    public init(slot: ColorSlot, members: [Member], selectionCount: Int,
                capableCount: Int? = nil) {
        self.slot = slot
        self.members = members
        self.selectionCount = selectionCount
        self.capableCount = capableCount ?? selectionCount
    }

    public var count: Int { members.count }

    public var isEmpty: Bool { members.isEmpty }

    /// The layers a pick in this row paints, in the order they were given.
    public var layerIDs: [UUID] { members.map(\.id) }

    public var reading: ColorStyleReading {
        guard let first = members.first else { return .empty }
        if let styleID = first.styleID {
            for member in members.dropFirst() where member.styleID != styleID { return .mixed }
            return .style(styleID)
        }
        for member in members.dropFirst() where member.styleID != nil { return .mixed }
        for member in members.dropFirst()
        where !ColorStyleSelection.sameColor(member.colorHex, first.colorHex) {
            return .mixed
        }
        return .color(first.colorHex)
    }

    /// The style every picked color already wears, when there is one.
    public var boundStyleID: UUID? {
        if case .style(let id) = reading { return id }
        return nil
    }

    /// Whether Unlink has anything to let go of: true as soon as one picked
    /// color comes from a style.
    public var wearsAnyStyle: Bool { members.contains { $0.styleID != nil } }

    /// The color "Save as Style" would keep: the one they all wear, and only
    /// while none of them already wears a style. Nil means the button is not
    /// offered, because there is no single color to give a name to.
    public var savableColorHex: String? {
        if case .color(let hex) = reading { return hex }
        return nil
    }

    /// What the row says out loud when it is leaving a layer out that it could
    /// have reached: a locked one, or a box whose fill is switched off, since
    /// painting that one would switch its fill on behind the person's back.
    ///
    /// Nil when the only layers it does not reach are layers that have no such
    /// color in the first place. A Fill row over a box and a caption is doing
    /// exactly what it looks like it is doing.
    public var note: String? {
        guard count > 0, count < capableCount else { return nil }
        return "Applies to \(count) of the \(selectionCount) selected layers."
    }

    /// What the row has to say out loud before a color is picked, when some of
    /// the layers it speaks for are wearing a style: painting them by hand
    /// takes them off it. Said BEFORE the click rather than after, because a
    /// style that quietly stopped being worn is one nobody notices until an
    /// edit to it fails to reach a layer.
    ///
    /// Nil when no style is involved, and nil when they ALL wear one: that row
    /// keeps its plain swatch and its Unlink button and has no well to warn
    /// about.
    public var unlinkNote: String? {
        guard reading == .mixed else { return nil }
        let styled = members.filter { $0.styleID != nil }.count
        guard styled > 0 else { return nil }
        return "A color picked here takes \(styled) of them off their style."
    }

    /// Hex is written uppercase everywhere the app makes one, but a document
    /// read from disk or a pasted color can arrive either way, and two rows
    /// saying Mixed over the identical blue would be a lie.
    private static func sameColor(_ lhs: String, _ rhs: String) -> Bool {
        lhs.caseInsensitiveCompare(rhs) == .orderedSame
    }
}

/// What the switch on a color row reads and does.
///
/// Some colors can simply not be there: a box's inside can be switched off, and
/// a frame can have no surface at all. Those rows carry a checkbox beside the
/// label, and the checkbox has to speak for the whole selection the same way
/// the color beside it does. It is on only when EVERY picked layer that could
/// have that color has one, so three boxes where two are filled read as off and
/// one click fills the third rather than emptying the other two.
///
/// A slot nothing picked can switch (an outline, a letter) is simply not
/// offered one, which is what `isOffered` says.
public struct ColorSwitch: Hashable, Sendable {
    public let slot: ColorSlot
    /// The picked layers that have this slot at all, locked ones left out.
    public let layerIDs: [UUID]
    /// Of those, how many have a color in it right now.
    public let onCount: Int

    public init(slot: ColorSlot, layerIDs: [UUID], onCount: Int) {
        self.slot = slot
        self.layerIDs = layerIDs
        self.onCount = onCount
    }

    /// Whether this row shows a checkbox at all.
    public var isOffered: Bool { slot.isSwitchable && !layerIDs.isEmpty }

    /// On only when every layer it speaks for already has this color.
    public var isOn: Bool { !layerIDs.isEmpty && onCount == layerIDs.count }
}

extension ColorSlot {
    /// Whether this color can be absent. A box's inside and a frame's surface
    /// can; an outline and a letter's ink are always painted something.
    public var isSwitchable: Bool { self == .fill }
}

extension ColorSlot {
    /// What a row calls this slot when it is speaking for several layers at
    /// once. The per-kind sections can call a shape's ink and a text block's
    /// ink both "Color" because only one of them is ever on screen; a
    /// selection holding both would show two rows with the same name.
    public var selectionTitle: String {
        switch self {
        case .fill: return "Fill"
        case .stroke: return "Outline"
        case .text: return "Text"
        }
    }
}

extension PhotonzDocument {

    /// What one color row shows for a set of picked layers. Layers keep the
    /// order they are given, which is the order the panel lists them in.
    public func colorStyleSelection(layerIDs: [UUID], slot: ColorSlot) -> ColorStyleSelection {
        let members = layerIDs.compactMap { id -> ColorStyleSelection.Member? in
            guard let layer = layer(id: id), !layer.isLocked,
                  let hex = layer.colorHex(for: slot) else { return nil }
            return ColorStyleSelection.Member(id: id, colorHex: hex,
                                              styleID: layer.colorStyleID(for: slot))
        }
        let capable = layerIDs.filter { layer(id: $0)?.colorSlots.contains(slot) == true }
        return ColorStyleSelection(slot: slot, members: members,
                                   selectionCount: layerIDs.count,
                                   capableCount: capable.count)
    }

    /// The rows a set of picked layers gets, in the order the inspector shows
    /// them: every slot at least one of them actually has a color in.
    public func colorStyleSlots(layerIDs: [UUID]) -> [ColorSlot] {
        ColorSlot.allCases.filter { !colorStyleSelection(layerIDs: layerIDs, slot: $0).isEmpty }
    }

    /// The rows the Color section shows for a set of picked layers: every slot
    /// at least one of them HAS, whether or not there is a color in it today.
    ///
    /// Wider than `colorStyleSlots` by exactly one case, and it matters: a box
    /// with its fill switched off has a fill slot and no fill color, and the
    /// row is the only way back to a fill. Dropping the row because the color
    /// is absent would mean switching a fill off removed the switch.
    public func colorRowSlots(layerIDs: [UUID]) -> [ColorSlot] {
        let slots = layerIDs.reduce(into: Set<ColorSlot>()) { found, id in
            guard let layer = layer(id: id), !layer.isLocked else { return }
            found.formUnion(layer.colorSlots)
        }
        return ColorSlot.allCases.filter { slots.contains($0) }
    }

    /// What the checkbox on a color row reads for a set of picked layers.
    public func colorSwitch(layerIDs: [UUID], slot: ColorSlot) -> ColorSwitch {
        let capable = layerIDs.filter { id in
            guard let layer = layer(id: id), !layer.isLocked else { return false }
            return layer.colorSlots.contains(slot)
        }
        let on = capable.filter { layer(id: $0)?.colorHex(for: slot) != nil }.count
        return ColorSwitch(slot: slot, layerIDs: capable, onCount: on)
    }

    /// The checkbox on a color row, over the whole selection: switch three
    /// boxes' insides on at once, in one step one undo puts back.
    ///
    /// Switching ON gives a layer that has no color there its own starting
    /// point rather than one shared color, because the switch is about whether
    /// the color EXISTS: a box takes its own outline color, the way toggling a
    /// single box's fill always has, and a frame takes the surface a new frame
    /// starts with. A layer that already has the color is left exactly as it
    /// is. Switching OFF clears the color and lets go of any style painting
    /// it, since a slot with nothing in it cannot be wearing a name.
    ///
    /// Returns how many layers actually changed, so a caller can tell a no-op
    /// from an edit.
    @discardableResult
    public mutating func setColorEnabled(layerIDs: [UUID], slot: ColorSlot,
                                         on: Bool) -> Int {
        guard slot.isSwitchable else { return 0 }
        var changed = 0
        for id in colorSwitch(layerIDs: layerIDs, slot: slot).layerIDs {
            guard let layer = layer(id: id) else { continue }
            let has = layer.colorHex(for: slot) != nil
            guard has != on else { continue }
            let seed = on ? layer.startingColorHex(for: slot) : nil
            guard !on || seed != nil else { continue }
            updateLayer(id: id) {
                $0.unbindColorStyle(for: slot)
                $0.setColorHex(seed, for: slot)
            }
            changed += 1
        }
        return changed
    }

    /// Points several layers' slot at one style, painting them all. Returns how
    /// many took it, so a caller can tell a no-op from a change. Layers without
    /// that slot are simply skipped.
    @discardableResult
    public mutating func bindColorStyle(layerIDs: [UUID], slot: ColorSlot,
                                        styleID: UUID) -> Int {
        var painted = 0
        for id in layerIDs where bindColorStyle(layerID: id, slot: slot, styleID: styleID) {
            painted += 1
        }
        return painted
    }

    /// Paints several layers' slot ONE color of its own: pick three boxes,
    /// choose a color once, undo once. Returns how many took it.
    ///
    /// It reaches exactly the layers the row speaks for. A locked layer and a
    /// box with its fill switched off sit out here for the same reason they sit
    /// out of what the row reads, so what a row says and what a pick in it does
    /// can never drift apart, and painting can never switch a fill on behind
    /// somebody's back.
    ///
    /// A layer wearing a style in that slot is taken off it. A color chosen by
    /// hand is the layer's own; leaving the binding on would mean the next edit
    /// to that style silently repainted a color somebody picked.
    @discardableResult
    public mutating func setColorHex(layerIDs: [UUID], slot: ColorSlot, hex: String) -> Int {
        let targets = colorStyleSelection(layerIDs: layerIDs, slot: slot).layerIDs
        for id in targets {
            updateLayer(id: id) {
                $0.unbindColorStyle(for: slot)
                $0.setColorHex(hex, for: slot)
            }
        }
        return targets.count
    }

    /// Lets several layers' slot go back to being a color of its own. Nothing
    /// is repainted: each layer keeps exactly what it is wearing.
    public mutating func unbindColorStyle(layerIDs: [UUID], slot: ColorSlot) {
        for id in layerIDs { unbindColorStyle(layerID: id, slot: slot) }
    }

    /// Saves the color several layers already share as a named style and points
    /// every one of them at it. Nil when they do not share one, because a style
    /// made from the first layer's color would silently repaint the rest.
    @discardableResult
    public mutating func saveColorStyle(from layerIDs: [UUID], slot: ColorSlot,
                                        name: String? = nil) -> UUID? {
        guard let hex = colorStyleSelection(layerIDs: layerIDs, slot: slot).savableColorHex,
              !layerIDs.isEmpty else { return nil }
        // Saved FROM a slot, so it is saved FOR that kind of part: a color
        // kept off an outline is offered on outlines and on text, not as
        // something to fill a box with. The Library is where that is widened.
        let styleID = addColorStyle(name: name, colorHex: hex, roles: [slot.styleRole])
        bindColorStyle(layerIDs: layerIDs, slot: slot, styleID: styleID)
        return styleID
    }
}
