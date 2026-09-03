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

    public init(slot: ColorSlot, members: [Member], selectionCount: Int) {
        self.slot = slot
        self.members = members
        self.selectionCount = selectionCount
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

    /// What to add to the row's hover tip when it speaks for only part of the
    /// selection, so a Fill row that quietly skips the arrow says so instead of
    /// looking broken. Nil when it reaches everything picked.
    public var note: String? {
        guard count > 0, count < selectionCount else { return nil }
        return "Applies to \(count) of the \(selectionCount) selected layers."
    }

    /// Hex is written uppercase everywhere the app makes one, but a document
    /// read from disk or a pasted color can arrive either way, and two rows
    /// saying Mixed over the identical blue would be a lie.
    private static func sameColor(_ lhs: String, _ rhs: String) -> Bool {
        lhs.caseInsensitiveCompare(rhs) == .orderedSame
    }
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
        return ColorStyleSelection(slot: slot, members: members, selectionCount: layerIDs.count)
    }

    /// The rows a set of picked layers gets, in the order the inspector shows
    /// them: every slot at least one of them actually has a color in.
    public func colorStyleSlots(layerIDs: [UUID]) -> [ColorSlot] {
        ColorSlot.allCases.filter { !colorStyleSelection(layerIDs: layerIDs, slot: $0).isEmpty }
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
        let styleID = addColorStyle(name: name, colorHex: hex)
        bindColorStyle(layerIDs: layerIDs, slot: slot, styleID: styleID)
        return styleID
    }
}
