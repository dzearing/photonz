import Foundation

/// What letting a colour go on a ROW in the layers list would do.
///
/// A saved text style could already be put down on a row; a colour could not.
/// Aiming a colour tile at the list did nothing and said nothing about why,
/// which is the one thing every other drop in the app was built not to do, and
/// the list took one kind of tile and refused the other with no visible reason.
///
/// It was left out because a row is not a colour well. A well is labelled with
/// the one thing it paints, so what letting go does is written on it; a row
/// carries only the layer's name, and a layer can have several colours (a
/// button has a fill, an edge and its words) or none at all (a picture, a plain
/// group). The rule the user chose on 2026-09-13 is the layer's MAIN colour,
/// named before you let go: whatever the inspector's Appearance list leads
/// with, falling through to the Border in the Effects list for a layer whose
/// only colour is a ring, and a refusal in words for a layer with no colour
/// anywhere.
///
/// This is a second drop TARGET, not a second set of rules. It works out the
/// same `ColorDrop.Target` a swatch works out and hands it to the same
/// `ColorDrop.answer`, so the sentence the list says is the sentence a swatch
/// would have said and what lands is the same thing.
public struct ColorRowDrop: Hashable, Sendable {
    /// Whether the row lights up, what letting go would do, and the one line
    /// that says so.
    public var answer: ColorDrop.Answer
    /// The layers the drop reaches, empty when nothing lands.
    public var layerIDs: [UUID]
    /// Which colour of those layers it paints, nil when nothing lands.
    public var slot: ColorSlot?
    /// The part to switch ON, for a drop landing on a part that is not there
    /// yet. Nil when the part is already on, and for a colour that is a
    /// property rather than a part.
    public var turnsOn: LayerPart?
    /// Which entry of a countable part the drop means, for the parts that can
    /// arrive more than once.
    public var index: Int

    public init(answer: ColorDrop.Answer, layerIDs: [UUID] = [], slot: ColorSlot? = nil,
                turnsOn: LayerPart? = nil, index: Int = 0) {
        self.answer = answer
        self.layerIDs = layerIDs
        self.slot = slot
        self.turnsOn = turnsOn
        self.index = index
    }
}

extension PhotonzDocument {

    /// What letting this colour go on this row would do, and which layers it
    /// would reach.
    ///
    /// - Parameters:
    ///   - paint: the colour in the air.
    ///   - bringing: the saved colour it arrived under, for a tile pulled off
    ///     the Library shelf. The drop points the part at the NAME where the
    ///     part can wear one, the same way the row's own menu does.
    ///   - id: the row under the pointer.
    ///   - picked: what is selected right now. Aiming at a row that is part of
    ///     the selection reaches every picked layer leading with the same part,
    ///     the way the text style row drop reaches every picked piece of text;
    ///     aiming at a row nobody picked reaches only that row, because the
    ///     pointer named it.
    ///   - stylesEnabled: whether saved colours are turned on at all.
    public func colorRowDrop(_ paint: Paint, bringing brought: ColorDrop.SavedColor? = nil,
                             onRow id: UUID, picked: Set<UUID> = [],
                             stylesEnabled: Bool = true) -> ColorRowDrop {
        guard let aimed = layer(id: id) else {
            // Not a refusal to explain away: somebody is carrying a colour and
            // has not found where it goes yet, so this is a signpost.
            let what = brought.map { " with \($0.name)" } ?? ""
            return ColorRowDrop(answer: ColorDrop.Answer(
                landing: nil, note: "Drop this on a layer to paint it\(what)."))
        }
        let subject = aimed.name.isEmpty ? "That" : aimed.name
        guard !aimed.isLocked else {
            // Named, and for the same reason the text style refusal names it:
            // the sentence has to say which of the two things is in the way,
            // and a padlock two rows up is not what somebody carrying a colour
            // is looking at.
            return ColorRowDrop(answer: ColorDrop.Answer(
                landing: nil, note: "\(subject) is locked, so it cannot be painted."))
        }
        guard let main = mainColor(of: aimed) else {
            return ColorRowDrop(answer: ColorDrop.Answer(
                landing: nil, note: "\(subject) has no colour to paint."))
        }
        let reached = crowd(around: id, slot: main.slot, picked: picked)
        let wearing = sharedPaint(layerIDs: reached, slot: main.slot)
        let worn = colorStyleSelection(layerIDs: reached, slot: main.slot).boundStyleID
        // A part nobody can see is being SWITCHED ON as well as painted, and
        // only when none of the layers it reaches has it: a crowd where some do
        // is a repaint for them and a switch for the rest, which `turnOnPart`
        // does in one move and the sentence calls a paint.
        let absent = reached.allSatisfy { layer(id: $0)?.colorHex(for: main.slot) == nil }
        var welcome = ColorDrop.StyleWelcome.neverWearsNames
        if stylesEnabled, let brought {
            welcome = colorStyles(for: main.slot).contains { $0.id == brought.id }
                ? .wearsIt : .notThisOne
        }
        let answer = ColorDrop.answer(
            dropping: paint, bringing: stylesEnabled ? brought : nil,
            on: ColorDrop.Target(part: main.title,
                                 wearing: wearing,
                                 styleName: worn.flatMap { colorStyle(id: $0)?.name },
                                 styleID: worn,
                                 reaches: reached.count,
                                 isAbsent: absent,
                                 acceptsGradient: main.slot.acceptsGradient,
                                 welcome: welcome))
        guard answer.lightsUp else { return ColorRowDrop(answer: answer) }
        return ColorRowDrop(answer: answer, layerIDs: reached, slot: main.slot,
                            turnsOn: absent ? main.part : nil, index: main.index)
    }

    /// Lands a colour let go on a row: ONE mutation, so one undo puts all of
    /// it back however many layers it reached and whether or not it had to
    /// switch a part on along the way.
    ///
    /// It takes the very reading the row answered the pointer with, so nothing
    /// can slip past a refusal and land anyway, and a row that stayed dark
    /// paints nothing. Returns how many layers took it.
    @discardableResult
    public mutating func paint(_ drop: ColorRowDrop) -> Int {
        guard let landing = drop.answer.landing, let slot = drop.slot,
              !drop.layerIDs.isEmpty else { return 0 }
        let ids = drop.layerIDs
        // A part that is not there is being given BOTH its presence and its
        // colour, which is one move rather than a switch followed by a repaint
        // of whatever came back.
        let painted = drop.turnsOn.map {
            turnOnPart($0, layerIDs: ids, paint: landing.paint, index: drop.index)
        } ?? setPaint(layerIDs: ids, slot: slot, paint: landing.paint)
        // A colour that arrived under a NAME points the part at the name, the
        // same way the row's own menu does. After the paint, because painting
        // by hand is what takes a slot OFF a name.
        if let brings = landing.brings {
            _ = bindColorStyle(layerIDs: ids, slot: slot, styleID: brings.id)
        }
        return painted
    }

    /// The one colour a layer leads with: the first row of its Appearance list,
    /// which is Fill for a box or a frame, Line for an arrow or a line, Text
    /// for words, Caliper for a measurement.
    ///
    /// A layer with no parts list at all — a picture, a plain group — still has
    /// a colour when it wears a ring, and that ring is an entry in the Effects
    /// list rather than a part (`OutlineRetirement.swift`), so it is the
    /// fallback rather than a row. Nil is a layer with no colour anywhere, and
    /// the only case that refuses.
    private func mainColor(of layer: Layer)
    -> (slot: ColorSlot, title: String, part: LayerPart?, index: Int)? {
        if let row = layerPartRows(layerIDs: [layer.id]).first, let slot = row.slot {
            return (slot, row.title, row.part, row.index ?? 0)
        }
        guard layer.colorSlots.contains(.border) else { return nil }
        return (.border, ColorSlot.border.selectionTitle, nil, 0)
    }

    /// The layers one drop reaches: the row on its own, or every picked layer
    /// leading with the same part when the row is one of the picked.
    ///
    /// A crowd holds only the layers the drop can actually reach. Picking a box
    /// and a piece of text and aiming at the box paints the boxes: words lead
    /// with Text rather than Fill, and painting a layer's SECOND colour because
    /// something else in the selection leads with it is not what the sentence
    /// promised.
    private func crowd(around id: UUID, slot: ColorSlot, picked: Set<UUID>) -> [UUID] {
        guard picked.contains(id) else { return [id] }
        let together = allLayers
            .filter { picked.contains($0.id) && !$0.isLocked }
            .filter { mainColor(of: $0)?.slot == slot }
            .map(\.id)
        return together.count > 1 ? together : [id]
    }
}
