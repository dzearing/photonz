import CoreGraphics
import Foundation

/// What one geometry field has to show for a whole selection.
///
/// Four buttons that are all 120 wide have one width to show; four that are
/// not have no single number, and pretending otherwise (showing the last one
/// you clicked) is how you set three layers to a width you never meant to
/// type. So the field either shows the number they agree on or says out loud
/// that they differ.
public enum LayerGeometryReading: Hashable, Sendable {
    /// There is no number to show: no selected layer takes this field, and none
    /// of them has a number here worth reading either.
    case empty
    /// Every layer this field acts on has the same number.
    case agreed(CGFloat)
    /// They differ.
    case mixed

    /// The number to show, or nil when there is not one.
    public var number: CGFloat? {
        if case .agreed(let value) = self { return value }
        return nil
    }

    public var isMixed: Bool { self == .mixed }
}

/// The layers the Position & Size fields speak for, and what typing in one of
/// them does to all of them.
///
/// One layer or twenty, the fields mean the same thing: X is a left edge, W is
/// a width, and typing one sets it on everything selected. That is what makes
/// a row of buttons one width in a single move instead of four, and it is why
/// the numbers stay per-layer rather than describing the box around the
/// selection: "line these up on 24" is the thing people actually want, and a
/// group box that moves as a unit is what dragging already does.
///
/// A field acts only on the layers that accept it. An arrow has no typeable
/// width and a locked layer has no typeable anything, so both simply sit out
/// while the rest of the selection changes, and the field says how many layers
/// it is speaking for.
public struct LayerGeometrySelection: Hashable, Sendable {

    /// One selected layer: where it sits now, and which of its four numbers
    /// take typing.
    public struct Member: Hashable, Sendable {
        public let id: UUID
        /// The layer's frame in the space its numbers are shown in — its
        /// parent's, the same frame the single-layer fields show.
        public let frame: CGRect
        public let editing: LayerGeometryEditing

        public init(id: UUID, frame: CGRect, editing: LayerGeometryEditing) {
            self.id = id
            self.frame = frame
            self.editing = editing
        }
    }

    /// What the field shows in place of a number when the layers differ.
    public static let mixedText = "Mixed"

    public let members: [Member]

    public init(_ members: [Member]) {
        self.members = members
    }

    public var count: Int { members.count }

    public var isEmpty: Bool { members.isEmpty }

    /// Whether a lock is what is stopping the whole panel. True only when
    /// every picked layer is locked, because a lock on one of four layers
    /// still leaves a field that takes a number.
    public var isLocked: Bool {
        !members.isEmpty && members.allSatisfy(\.editing.isLocked)
    }

    /// The line under the fields: what the numbers mean, in words.
    ///
    /// With one layer picked that is where the layer sits on the picture; with
    /// several it has to say that a number lands on every one of them, and
    /// which edge each letter is, or "type 24 into X" reads as a guess.
    ///
    /// A locked selection gets neither, because both would be a lie: nothing
    /// here takes a number and no arrow key steps anything. It says the lock
    /// instead, in the same words the hover tip uses, so the reason is where
    /// the eye already is rather than one hover away.
    public var caption: String {
        if isLocked {
            guard count > 1 else { return LayerGeometryEditing.lockedReason }
            return "\(count) locked layers. Unlock them in the Layers list to "
                + "change their position or size."
        }
        guard count > 1 else {
            return "\(LayerGeometry.unitSuffix) from the top left. "
                + "Up or down arrow steps by 1, Shift by 10."
        }
        return "\(count) layers, all at once. X sets every left edge, Y every top edge, "
            + "W and H each layer's own size. Arrow steps them all by 1, Shift by 10."
    }

    /// The layers a given field actually changes.
    public func members(taking field: LayerGeometryField) -> [Member] {
        members.filter { $0.editing.allows(field) }
    }

    /// Whether the field takes typing at all: it does as soon as one selected
    /// layer accepts it.
    public func allows(_ field: LayerGeometryField) -> Bool {
        members.contains { $0.editing.allows(field) }
    }

    /// What the field shows.
    ///
    /// The layers that TAKE the field decide the number, because that is what
    /// typing there would change. When none of them takes it the field is not
    /// automatically blank: a number nobody can type is still a number worth
    /// reading, so a wrapped paragraph reports the height it turned out to be
    /// instead of leaving the one number you might want off the panel.
    public func reading(_ field: LayerGeometryField) -> LayerGeometryReading {
        let taking = members(taking: field)
        return reading(field, over: taking.isEmpty ? readable(field) : taking)
    }

    /// The layers a read-only number would speak for: all of them, or none.
    ///
    /// Half a selection is nobody. Pick a paragraph and an arrow and the height
    /// the paragraph came out to is not the selection's height, and a number
    /// standing quietly for one of two layers is the exact confusion the Mixed
    /// rule exists to prevent — so the field stays blank and the hover tip does
    /// the explaining.
    private func readable(_ field: LayerGeometryField) -> [Member] {
        let showing = members.filter { $0.editing.shows(field) }
        return showing.count == members.count ? showing : []
    }

    private func reading(_ field: LayerGeometryField,
                         over members: [Member]) -> LayerGeometryReading {
        guard let first = members.first else { return .empty }
        let value = LayerGeometry.displayValue(field, of: first.frame)
        for member in members.dropFirst()
        where LayerGeometry.displayValue(field, of: member.frame) != value {
            return .mixed
        }
        return .agreed(value)
    }

    /// Whether this field takes no typing at all: the number in it, if it has
    /// one, was worked out for you.
    ///
    /// The panel draws these differently, because a number you cannot type
    /// should not wear the box a number you can type wears. That question is
    /// answered here, beside the rules that decide it, rather than in the view
    /// re-deriving it and drifting.
    ///
    /// A field with nothing to show still counts: an arrow's width is blank
    /// AND untypeable, and an empty box you can click into is the same lie as
    /// a full one. Nothing selected is neither, it is an empty panel.
    public func isReadOnly(_ field: LayerGeometryField) -> Bool {
        !isEmpty && !allows(field)
    }

    /// What to say the moment someone clicks a number they cannot type.
    ///
    /// The same sentence the hover tip carries, put where a click can reach
    /// it. A tip arrives only after a hover delay, so until now a click on one
    /// of these was answered by silence, and silence reads as broken rather
    /// than as fixed. Nil for a field that does take typing, because a click
    /// there already means something.
    public func explanation(for field: LayerGeometryField) -> String? {
        guard isReadOnly(field) else { return nil }
        return fixedReason(for: field) ?? field.title
    }

    /// A plain sentence explaining why a field takes nothing, for the hover
    /// tip. Nil when it takes something. With several layers picked the first
    /// reason in the selection stands for all of them: they are all sitting
    /// out, and a stack of four sentences in a tooltip is not more useful than
    /// one.
    public func fixedReason(for field: LayerGeometryField) -> String? {
        guard !allows(field) else { return nil }
        return members.compactMap { $0.editing.fixedReason(for: field) }.first
    }

    /// What to add to the hover tip: how much of the selection the field
    /// reaches, and where it stops. A width that skips the arrow in the
    /// selection says so instead of looking broken, and a width that will not
    /// go below 80 says so BEFORE you type 12 and watch it become 80. Nil when
    /// the field acts on everything picked and stops nowhere in particular.
    public func note(for field: LayerGeometryField) -> String? {
        let taking = members(taking: field)
        guard !taking.isEmpty else { return nil }
        var parts: [String] = []
        if taking.count < count {
            parts.append("Applies to \(taking.count) of the \(count) selected layers.")
        }
        if let floor = floor(for: field) {
            parts.append("Will not go below \(Int(floor)) \(LayerGeometry.unitSuffix).")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// The floor the field stops at across the selection, when it is a floor
    /// worth saying out loud. One point is not: every layer has it and nobody
    /// types a width of zero on purpose. The largest floor among the layers
    /// the field reaches stands for them, because that is the first place a
    /// number typed into the box stops changing anything.
    private func floor(for field: LayerGeometryField) -> CGFloat? {
        let floors = members(taking: field).compactMap { $0.editing.minimum(for: field) }
        guard let highest = floors.max(), highest > LayerGeometry.minimumSide else { return nil }
        return highest
    }

    /// Every layer's new frame after `value` is typed into `field`. Layers the
    /// field does not act on, and layers already at that number, are left out,
    /// so an edit that changes nothing produces no moves at all.
    public func applying(_ value: CGFloat, to field: LayerGeometryField) -> [UUID: CGRect] {
        moves(for: field) { frame, member in
            LayerGeometry.applying(value, to: field, of: frame,
                                   notBelow: member.editing.minimum(for: field))
        }
    }

    /// What the field will read once `value` lands: the number the layers
    /// actually take, which is not always the number that was typed. A text
    /// box will not go below its floor, so typing 12 into W leaves 80 on
    /// screen, and the field has to say 80 rather than sit there showing a
    /// width nothing has. Mixed when one number lands differently on two
    /// layers, for exactly the same reason the field reads Mixed at rest.
    public func landing(_ value: CGFloat, in field: LayerGeometryField) -> LayerGeometryReading {
        let taking = members(taking: field)
        guard let first = taking.first else { return .empty }
        func landed(_ member: Member) -> CGFloat {
            let frame = LayerGeometry.applying(value, to: field, of: member.frame,
                                               notBelow: member.editing.minimum(for: field))
            return LayerGeometry.displayValue(field, of: frame)
        }
        let number = landed(first)
        for member in taking.dropFirst() where landed(member) != number { return .mixed }
        return .agreed(number)
    }

    /// Every layer's new frame after one arrow-key press. Each layer steps
    /// from its OWN number, so a selection that is spread out stays spread out
    /// and only moves together — which is what a nudge means.
    public func stepping(_ field: LayerGeometryField, direction: Int,
                         coarse: Bool) -> [UUID: CGRect] {
        moves(for: field) { frame, member in
            let stepped = LayerGeometry.stepped(LayerGeometry.value(field, of: frame),
                                                direction: direction, coarse: coarse)
            return LayerGeometry.applying(stepped, to: field, of: frame,
                                          notBelow: member.editing.minimum(for: field))
        }
    }

    private func moves(for field: LayerGeometryField,
                       _ transform: (CGRect, Member) -> CGRect) -> [UUID: CGRect] {
        var moves: [UUID: CGRect] = [:]
        for member in members(taking: field) {
            let frame = transform(member.frame, member)
            if frame != member.frame { moves[member.id] = frame }
        }
        return moves
    }
}
