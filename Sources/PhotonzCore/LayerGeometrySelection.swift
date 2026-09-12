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

    /// What a number you can TYPE shows: the number, or the word for "they
    /// differ", or nothing at all, because an empty box is room to type in.
    public var draftText: String {
        switch self {
        case .empty: return ""
        case .mixed: return LayerGeometrySelection.mixedText
        case .agreed(let value): return String(Int(value.rounded()))
        }
    }

    /// What a number you can only READ shows. The same digits and the same
    /// word, so a locked layer's numbers line up with the ones beside them,
    /// but nothing becomes a mark rather than nothing: a readout has no box
    /// left to stand in for it, so an arrow's blank width would otherwise
    /// leave a W alone on the row with a gap after it.
    public var readoutText: String {
        switch self {
        case .empty: return LayerGeometrySelection.blankText
        default: return draftText
        }
    }

    /// The same two, with the field's own unit mark on the digits.
    ///
    /// Four of the five numbers in the section are lengths in the same unit
    /// and say so once, in the caption. The angle is the odd one out, so it
    /// carries its degree sign: a bare 45 sitting under a W of 296 reads as
    /// one more length, and the whole point of the row is that it is not.
    /// Mixed and the blank mark are words rather than numbers, so neither
    /// takes a unit.
    public func draftText(for field: LayerGeometryField) -> String {
        marked(draftText, field)
    }

    public func readoutText(for field: LayerGeometryField) -> String {
        marked(readoutText, field)
    }

    private func marked(_ text: String, _ field: LayerGeometryField) -> String {
        guard case .agreed = self else { return text }
        return text + field.displaySuffix
    }
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
        /// The box a person SEES, in the space its numbers are shown in — its
        /// parent's, the same frame the single-layer fields show. For a text
        /// layer that is the words, not the stored box: the empty room a
        /// measured text box carries on its far edges is `slack`, and a W of
        /// 104 for a hundred points of words is a number nobody can act on.
        public let frame: CGRect
        /// What this layer's stored box carries beyond `frame`, put straight
        /// back on whatever a typed number produces (`Layer.boxSlack`). Zero
        /// for everything but text.
        public let slack: CGSize
        /// The angle this layer is turned to, in DEGREES, positive clockwise.
        /// It is not in `frame` and never could be: it lives on the layer's
        /// transform, and the panel is handed it in the unit a person types
        /// so nothing downstream has to know about radians.
        public let angle: CGFloat
        public let editing: LayerGeometryEditing

        public init(id: UUID, frame: CGRect, editing: LayerGeometryEditing,
                    slack: CGSize = .zero, angle: CGFloat = 0) {
            self.id = id
            self.frame = frame
            self.slack = slack
            self.angle = angle
            self.editing = editing
        }

        /// The number this field shows for this layer: whole points off the
        /// box, or whole degrees off the angle.
        func displayNumber(_ field: LayerGeometryField) -> CGFloat {
            field.isFrameNumber ? LayerGeometry.displayValue(field, of: frame)
                                : LayerAngle.display(angle)
        }

        /// `box` turned back into the box to store.
        func stored(_ box: CGRect) -> CGRect {
            guard slack != .zero else { return box }
            return CGRect(x: box.minX, y: box.minY,
                          width: box.width + slack.width, height: box.height + slack.height)
        }
    }

    /// What the field shows in place of a number when the layers differ. One
    /// word for the whole app, so no two controls can spell it differently.
    public static let mixedText = MixedValue.text

    /// What a number you cannot type shows when there is no number to show.
    /// An en dash, the mark a table uses for "nothing here", so the column
    /// still reads as a column. Only readouts use it: a box you can type in
    /// says nothing by staying empty.
    public static let blankText = "\u{2013}"

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
        // A layer with nothing painted on it has no numbers at all, so the
        // line says that rather than promising numbers somebody else worked
        // out. It comes first: a lock on a layer with no pixels is not what is
        // stopping you typing a width into it.
        if !members.isEmpty, members.allSatisfy(\.editing.hasNoBox) {
            return count > 1 ? Self.nothingOnThemYet : LayerGeometryEditing.nothingOnItReason
        }
        if isLocked {
            // The hover tip for X already says everything a locked layer has to
            // say, including the half a stack or a grid owns rather than the
            // lock, so the caption is that same sentence rather than a second
            // wording of it.
            guard count > 1 else {
                return members[0].editing.fixedReason(for: .x) ?? LayerGeometryEditing.lockedReason
            }
            guard !members.allSatisfy(\.editing.containerOwnsPosition) else {
                return "\(count) locked layers, all inside something that decides where they sit. "
                    + "Unlocking them in the Layers list gives back their size and angle, "
                    + "not their position."
            }
            return "\(count) locked layers. Unlock them in the Layers list to "
                + "change their position, size or angle."
        }
        // Only the numbers that actually take typing are described. A section
        // whose W and H are plain text because a stack decided them has no
        // arrow key to promise, and a caption that promises one anyway is the
        // panel describing a control that is not there.
        let typeable = LayerGeometryField.allCases.filter { allows($0) }
        guard count > 1 else {
            // The angle is the one number here that is not a length, so the
            // line says its unit as soon as there is an angle on show. Where
            // there is not — a group, an arrow — it says nothing about
            // degrees, because there is nothing on the row to explain.
            let where_ = reading(.rotation) == .empty
                ? "\(LayerGeometry.unitSuffix) from the top left."
                : "\(LayerGeometry.unitSuffix) from the top left, A in degrees clockwise."
            // Nothing picked is not a panel full of numbers somebody else
            // decided, it is an empty panel, so it keeps the plain caption.
            guard !typeable.isEmpty || isEmpty else { return "\(where_) \(Self.workedOutForYou)" }
            guard !typeable.isEmpty,
                  typeable.count < LayerGeometryField.allCases.count else {
                return "\(where_) Up or down arrow steps by 1, Shift by 10."
            }
            return "\(where_) Up or down arrow steps \(Self.letters(typeable)) by 1, Shift by 10."
        }
        let head = "\(count) layers, all at once."
        guard !typeable.isEmpty else { return "\(head) \(Self.workedOutForThem)" }
        guard typeable.count < LayerGeometryField.allCases.count else {
            return "\(head) X sets every left edge, Y every top edge, "
                + "W and H each layer's own size, A each layer's own angle. "
                + "Arrow steps them all by 1, Shift by 10."
        }
        return "\(head) \(Self.letters(typeable)) land on every one of them. "
            + "Arrow steps them by 1, Shift by 10."
    }

    /// The same for several layers picked at once, all of them still empty.
    static let nothingOnThemYet = "There is nothing on any of these layers yet, so they have no position or size. Paint or fill something and each box will be whatever you put there."

    /// What the line says when NONE of the four takes a number and no lock is
    /// the reason. There is no keyboard to describe, so it points at the thing
    /// that does answer: clicking one of them.
    static let workedOutForYou = "These numbers are worked out for you. Click one to see what decides it."
    static let workedOutForThem = "These numbers are worked out for them. Click one to see what decides it."

    /// The field letters as a person would read them out: "W", "W and H",
    /// "X, Y and W".
    private static func letters(_ fields: [LayerGeometryField]) -> String {
        let labels = fields.map(\.label)
        guard let last = labels.last else { return "" }
        guard labels.count > 1 else { return last }
        return labels.dropLast().joined(separator: ", ") + " and " + last
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
        let value = first.displayNumber(field)
        for member in members.dropFirst() where member.displayNumber(field) != value {
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

    /// What to say after a number was typed into `field` and the picked layers
    /// would not take it.
    ///
    /// The read-back half of this landed first: the box comes back to the size
    /// they kept rather than showing what was asked for. On its own that reads
    /// as a box that ignored you, so the line under the section carries the
    /// reason. `landed` is what the field read once the change had been made.
    ///
    /// Nil in every case where there is nothing to say, and that is most of
    /// them: they took the number, the number was the one they already had, a
    /// position (nothing clamps where a layer sits), or the report is about a
    /// moment that has passed because the numbers have moved on since.
    ///
    /// Nil too when nothing with a NAME refused it. Every layer has a floor of
    /// one point that nobody set, and a sentence about it would send a person
    /// looking for a control that does not exist. A rule that refuses a typed
    /// number owes the panel its own name (`LayerGeometryEditing.limitReason`);
    /// where a new rule cannot give one, the fix is to give it one rather than
    /// to write a vaguer sentence here.
    ///
    /// Worked out afresh from the pair every time rather than held as words,
    /// so taking the rule off takes the sentence with it instead of leaving it
    /// explaining a rule that is gone.
    public func refusal(asking value: CGFloat, for field: LayerGeometryField,
                        landedOn landed: LayerGeometryReading) -> String? {
        guard !isEmpty, field.isSize, value.isFinite else { return nil }
        guard landed != .agreed(value.rounded()) else { return nil }
        guard reading(field) == landed else { return nil }
        // With several picked the first reason stands for all of them, the same
        // way `fixedReason` settles it: they are all being held by something,
        // and a stack of sentences in one line is not more useful than one.
        return members(taking: field)
            .compactMap { $0.editing.limitReason(for: field, asking: value) }
            .first
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
        if let ceiling = ceiling(for: field) {
            parts.append("Will not go past \(Int(ceiling)) \(LayerGeometry.unitSuffix).")
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

    /// The other end, said the same way. The LOWEST ceiling among the layers
    /// the field reaches stands for them, because that is the first place a
    /// number typed into the box stops changing anything on the way up.
    private func ceiling(for field: LayerGeometryField) -> CGFloat? {
        members(taking: field).compactMap { $0.editing.maximum(for: field) }.min()
    }

    /// Every layer's new frame after `value` is typed into `field`. Layers the
    /// field does not act on, and layers already at that number, are left out,
    /// so an edit that changes nothing produces no moves at all.
    public func applying(_ value: CGFloat, to field: LayerGeometryField) -> [UUID: CGRect] {
        // A is not a number about the box, so it moves nothing here: it goes
        // through `turning(to:)` instead, and the panel routes it there.
        guard field.isFrameNumber else { return [:] }
        return moves(for: field) { frame, member in
            LayerGeometry.applying(value, to: field, of: frame,
                                   notBelow: member.editing.minimum(for: field),
                                   notAbove: member.editing.maximum(for: field))
        }
    }

    // There is deliberately no "what will this land on" here. The field shows
    // what the layers ARE once a number has landed, read from the document
    // afterwards (`GeometryReadBackTests`), because a landing worked out in
    // advance only knows the floors this type knows about: a group held to a
    // smallest width by its own flow refused a typed 50 and kept 160, and the
    // box went on showing a 50 that nothing on the canvas had.

    /// Every layer's new frame after one arrow-key press. Each layer steps
    /// from its OWN number, so a selection that is spread out stays spread out
    /// and only moves together — which is what a nudge means.
    public func stepping(_ field: LayerGeometryField, direction: Int,
                         coarse: Bool) -> [UUID: CGRect] {
        guard field.isFrameNumber else { return [:] }
        return moves(for: field) { frame, member in
            let stepped = LayerGeometry.stepped(LayerGeometry.value(field, of: frame),
                                                direction: direction, coarse: coarse)
            return LayerGeometry.applying(stepped, to: field, of: frame,
                                          notBelow: member.editing.minimum(for: field),
                                          notAbove: member.editing.maximum(for: field))
        }
    }

    /// Every layer's new ANGLE, in degrees, after `value` is typed into A.
    ///
    /// The angle is not in the box, so it cannot ride along with the frames:
    /// this is the second half of `applying(_:to:)`, and the panel calls
    /// whichever of the two the field belongs to. Layers that do not turn are
    /// left out, and so is a layer already at that angle, so typing the number
    /// that is already on screen records no undo step. 45 typed at a layer
    /// sitting on 405 is the same turn and changes nothing.
    ///
    /// What comes back is said the shortest way, so a knob swung round twice
    /// is tidied to the angle you can see the moment you type over it.
    public func turning(to value: CGFloat) -> [UUID: CGFloat] {
        guard value.isFinite else { return [:] }
        let wanted = LayerAngle.normalized(value)
        var turns: [UUID: CGFloat] = [:]
        for member in members(taking: .rotation) where !LayerAngle.isSameTurn(member.angle, wanted) {
            turns[member.id] = wanted
        }
        return turns
    }

    /// Every layer's new angle after one arrow-key press. Each layer steps
    /// from its OWN angle, the same rule the other four follow, so a row of
    /// shapes at different angles all tilt one more degree and stay different.
    public func steppingRotation(direction: Int, coarse: Bool) -> [UUID: CGFloat] {
        var turns: [UUID: CGFloat] = [:]
        for member in members(taking: .rotation) {
            let stepped = LayerAngle.normalized(
                LayerGeometry.stepped(LayerAngle.display(member.angle),
                                      direction: direction, coarse: coarse))
            if !LayerAngle.isSameTurn(member.angle, stepped) { turns[member.id] = stepped }
        }
        return turns
    }

    /// The new boxes to STORE. A member is left out when the box a person sees
    /// does not move, so an edit that changes nothing produces no moves — and
    /// what comes back carries the slack again, because that is the box the
    /// words are drawn in.
    private func moves(for field: LayerGeometryField,
                       _ transform: (CGRect, Member) -> CGRect) -> [UUID: CGRect] {
        var moves: [UUID: CGRect] = [:]
        for member in members(taking: field) {
            let frame = transform(member.frame, member)
            if frame != member.frame { moves[member.id] = member.stored(frame) }
        }
        return moves
    }
}
