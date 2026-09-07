import CoreGraphics
import Foundation

/// A layer is made of PARTS, and every part works the same way.
///
/// The model, written down in `docs/design/shape-parts.md` before any of this
/// was built:
///
/// > A **part** is something a layer paints that can be absent. It has one
/// > switch, one colour, and settings that only exist while it is on.
/// >
/// > A **property** is something the layer always has, and has no switch:
/// > position, size, opacity, blur, corner radius, an arrow's head size.
///
/// Before this, a rectangle answered three different questions three different
/// ways. Its fill had a checkbox in the Color section, its outline had no
/// switch at all — so a box could not be drawn without a ring round it — and
/// its shadow had a switch inside a section of its own. Learning one taught you
/// nothing about the next. One model instead: learn to take the outline off and
/// you already know how to take the fill off, and how to add whatever part
/// arrives next.
public enum LayerPart: String, CaseIterable, Hashable, Sendable {
    /// What is inside the shape: a box's interior, a frame's surface.
    case fill
    /// The line round the layer, whichever way it is drawn. A shape strokes its
    /// own path and everything else gets a ring round its box, and that
    /// difference is nothing a person does differently, so it is one part with
    /// one name. See `OutlineWidth.swift`.
    case outline
    /// What the layer throws behind it.
    ///
    /// A shadow is no longer a row in Appearance: it is something you ADD, so
    /// it is an entry in the Effects list (`LayerEffects.swift`). It stays a
    /// part here because a shadow's colour is painted the same way every other
    /// part's is, and letting a colour go on a switched-off shadow has to give
    /// it one, exactly as it does on a switched-off outline.
    case shadow

    /// What the parts list calls this part.
    public var title: String {
        switch self {
        case .fill: return "Fill"
        case .outline: return "Outline"
        case .shadow: return "Shadow"
        }
    }

    /// The word in front of the part's name in a sentence about it: "1 of the 3
    /// selected layers has an outline". Written down beside the name so a
    /// sentence cannot end up saying "a outline".
    public var article: String {
        switch self {
        case .fill, .shadow: return "a"
        case .outline: return "an"
        }
    }

}

extension Layer {

    /// Which of this layer's colours the Outline part paints: a shape's own
    /// stroke, or the ring its styling draws round everything else.
    public var outlineSlot: ColorSlot { drawsItsOwnOutline ? .stroke : .border }

    /// Whether the line round this layer is there right now. The one test for
    /// both kinds of ring, so a switch cannot read one and set the other.
    ///
    /// A highlight is the reason this is not simply `outlineWidth > 0`: it
    /// carries a stroke width in its content that it never paints, so the only
    /// ring it can have is the one its styling draws.
    public var hasOutline: Bool {
        (drawsItsOwnOutline ? outlineWidth : style.borderWidth) > 0
    }

    /// Whether this layer's outline can be switched OFF.
    ///
    /// A box or an ellipse can live without one: it still has an inside. A
    /// line or an arrow IS its line — switching it off would leave nothing on
    /// the canvas at all, which is not a setting, it is a delete. So those
    /// carry no switch, and their colour is a property rather than a part.
    ///
    /// Anything that is not a shape at all — a picture, a frame, a label, a
    /// highlight — wears a ring its styling draws, and a ring is always
    /// something a layer can be without.
    public var outlineIsSwitchable: Bool { annotation?.outlineIsSwitchable ?? true }

    /// The width the outline comes back at when it is switched on and nothing
    /// remembers what it was before. A shape returns to the width a freshly
    /// drawn one wears; a ring round a picture comes back thin, because it is
    /// an edge rather than a stroke.
    public var startingOutlineWidth: CGFloat {
        drawsItsOwnOutline ? AnnotationContent.defaultStrokeWidth : 2
    }
}

/// One of the colours a part row paints, and exactly which of the picked layers
/// takes it.
///
/// Nearly every row has one: the Fill row paints every picked layer's inside.
/// The Outline row has TWO the moment a shape and a picture are picked
/// together, because a shape strokes its own path and a picture wears a ring
/// its styling draws. That difference is nothing a person does differently, so
/// it stays one row — and this is what lets one row hold both without either
/// colour reaching a layer it has no business on.
///
/// The layers are named rather than worked out from the slot, and that is the
/// point: a highlight has a stroke colour too, but it is the WASH the highlight
/// is made of, not a line round anything. Painting the Outline row by slot
/// alone repainted it.
public struct PartColor: Hashable, Sendable {
    public let slot: ColorSlot
    /// The picked layers this colour reaches, in draw order.
    public let layerIDs: [UUID]

    public init(slot: ColorSlot, layerIDs: [UUID]) {
        self.slot = slot
        self.layerIDs = layerIDs
    }
}

/// One row of the parts list, and exactly which of the picked layers it speaks
/// for.
///
/// The row is computed here rather than in the panel so that what a row SAYS
/// and what it DOES can never drift apart: the switch, the colour and the width
/// all read their reach off the same value.
public struct LayerPartRow: Hashable, Sendable, Identifiable {
    /// The part this row switches on and off. Nil for a colour that is a
    /// property rather than a part — a line's ink, a letter's ink — which has
    /// no switch because it can never be absent.
    public let part: LayerPart?
    /// The colours this row paints, and which picked layers take each one.
    /// Empty for the shadow, whose colour is not one of the layer's slots.
    public let colors: [PartColor]
    /// What the row is called on screen.
    public let title: String
    /// The picked layers this row's switch reaches. Empty means no switch.
    public let switchIDs: [UUID]
    /// How many of those have this part right now.
    public let onCount: Int
    /// The picked layers this row's width setting reaches. Empty means the row
    /// has no width.
    public let widthIDs: [UUID]
    /// How many layers are picked altogether, so a row can say what it is
    /// leaving out.
    public let selectionCount: Int
    /// Where this entry sits in a countable part's list, nearest the eye first.
    /// Nil for a part a layer can only have one of, which is every row that was
    /// here before the list could grow.
    public let index: Int?

    public init(part: LayerPart?, colors: [PartColor], title: String,
                switchIDs: [UUID], onCount: Int, widthIDs: [UUID],
                selectionCount: Int, index: Int? = nil) {
        self.part = part
        self.colors = colors
        self.title = title
        self.switchIDs = switchIDs
        self.onCount = onCount
        self.widthIDs = widthIDs
        self.selectionCount = selectionCount
        self.index = index
    }

    // Nothing in Appearance is added and nothing in it is removed, so no row
    // here carries a cross or a grip. That is the whole difference between this
    // panel and the Effects list under it (`LayerEffects.swift`).

    /// The colour this row leads with: the one its name field, its saved
    /// colours menu and its picker speak for. Nil for the shadow.
    public var slot: ColorSlot? { colors.first?.slot }

    /// True when this ONE row paints two kinds of line at once, because a
    /// shape and a picture are picked together. The width row reads it, since
    /// a shape's stroke and a picture's ring are set two different ways
    /// underneath even though nothing a person does differs.
    public var mixesLineKinds: Bool { colors.count > 1 }

    /// Stable enough to key a list on, and stable ACROSS selections: the
    /// Outline row is called `outline` whether it is speaking for a shape's
    /// stroke, a picture's ring or both. It used to be `outline.stroke` on a
    /// box and `outline.border` on a picture, so the settings drawer someone
    /// had just opened folded itself away the moment they clicked the other
    /// kind of layer.
    public var id: String {
        if let part {
            guard let index else { return part.rawValue }
            return "\(part.rawValue).\(index)"
        }
        return "color.\(slot?.rawValue ?? "none")"
    }

    /// Whether this row shows a switch at all.
    public var hasSwitch: Bool { !switchIDs.isEmpty }

    /// On only when every layer the switch reaches already has this part, so
    /// three boxes where two are outlined read as off and one click outlines
    /// the third rather than stripping the other two.
    public var isOn: Bool { !switchIDs.isEmpty && onCount == switchIDs.count }

    /// Whether the row has settings of its own to unfold. The fill has none —
    /// a gradient is a kind of colour, not a setting — so its row shows no
    /// chevron rather than opening an empty drawer.
    public var hasSettings: Bool { part == .shadow || !widthIDs.isEmpty }

    /// True while some of the layers this row's switch reaches have the part
    /// and the rest do not.
    ///
    /// Off is a true answer — none of them have it — so a row where one box is
    /// outlined and the other is not may not borrow it. A Mac switch has no
    /// third position, so the row says the word beside the switch instead and
    /// the switch is drawn one step quieter while it has no position to show
    /// (`UX-PATTERNS.md` section 4). A row with no switch has nothing to
    /// disagree about.
    public var isMixed: Bool { onCount > 0 && onCount < switchIDs.count }

    /// What the row says out loud when it is leaving a picked layer out, or
    /// when the layers it reaches disagree. Nil when it reaches all of them and
    /// they agree, because a sentence saying "this does what it looks like it
    /// does" is a sentence in the way.
    ///
    /// Both halves can be true at once — an arrow has no inside, so a Fill row
    /// over two boxes and an arrow skips one layer AND speaks for two that
    /// disagree — and each is a different question, so each gets its own
    /// sentence rather than one of them being dropped.
    public var reachNote: String? {
        let reach = max(switchIDs.count, widthIDs.count)
        let skips = reach > 0 && reach < selectionCount
        var lines: [String] = []
        if skips {
            lines.append("Applies to \(reach) of the \(selectionCount) selected layers.")
        }
        if isMixed, let part {
            let of = skips ? "\(onCount) of those"
                : "\(onCount) of the \(selectionCount) selected layers"
            let verb = onCount == 1 ? "has" : "have"
            let noun = "\(part.article) \(part.title.lowercased())"
            lines.append("\(of) \(verb) \(noun). Switching this on gives the rest one too.")
        }
        return lines.isEmpty ? nil : lines.joined(separator: " ")
    }
}

extension PhotonzDocument {

    /// The parts list for a set of picked layers, in the order the panel shows
    /// it: Fill, Outline, Text, then Shadow.
    ///
    /// Every row speaks for the whole selection the way the Color rows always
    /// have: picking a second layer widens what a row answers for and never
    /// moves it. That is why the parts do not become one section each — a
    /// heading that comes and goes with the selection is a panel that
    /// rearranges itself while you use it.
    public func layerPartRows(layerIDs: [UUID]) -> [LayerPartRow] {
        let picked = layerIDs.compactMap { layer(id: $0) }.filter { !$0.isLocked }
        guard !picked.isEmpty else { return [] }
        let count = layerIDs.count
        var rows: [LayerPartRow] = []

        // Fill: the inside of a box or an ellipse, the surface of a frame.
        let fillable = picked.filter { $0.colorSlots.contains(.fill) }
        if !fillable.isEmpty {
            rows.append(LayerPartRow(
                part: .fill, colors: [PartColor(slot: .fill, layerIDs: fillable.map(\.id))],
                title: LayerPart.fill.title,
                switchIDs: fillable.map(\.id),
                onCount: fillable.filter { $0.colorHex(for: .fill) != nil }.count,
                widthIDs: [], selectionCount: count))
        }

        // Who has a line round them at all, and which of the two ways it is
        // drawn. A shape strokes its own path; everything else — a picture, a
        // frame, a label, a group, a highlight — wears a ring its styling
        // draws. One part, two ways of painting it.
        let inked = picked.filter { $0.colorSlots.contains(.stroke) }
        let stroked = inked.filter(\.drawsItsOwnOutline)
        let ringed = picked.filter { !$0.drawsItsOwnOutline }
        // A row called Outline needs at least one line somebody can take off.
        // Two arrows and nothing else have no such line: an arrow IS its line,
        // and a row offering to remove it would be a delete wearing a switch.
        let outlined = stroked.contains(where: \.outlineIsSwitchable) || !ringed.isEmpty

        // A colour that is a property rather than a part: a highlight's wash,
        // and a lone arrow's or line's ink. No switch, because the layer IS
        // it, and no width, because a line's thickness lives in the shape's
        // own settings beside its ending and its head size.
        //
        // A highlight keeps this row even next to a box, because its stroke
        // colour is the wash it paints and not a line round anything. It never
        // draws the stroke width it carries.
        let plainInk = outlined ? inked.filter { !$0.drawsItsOwnOutline } : inked
        if !plainInk.isEmpty {
            rows.append(LayerPartRow(
                part: nil, colors: [PartColor(slot: .stroke, layerIDs: plainInk.map(\.id))],
                title: ColorSlot.stroke.title,
                switchIDs: [], onCount: 0, widthIDs: [], selectionCount: count))
        }

        // ONE Outline row, however many kinds of line are picked.
        //
        // It used to be two whenever a shape and anything else were picked
        // together: the stroke row and the ring row, one above the other, both
        // called Outline, each with a switch that reached half the selection
        // (reported 2026-09-07). They are the same idea to a person, so this
        // is one row that knows which colour each picked layer actually wears.
        if outlined {
            var colors: [PartColor] = []
            if !stroked.isEmpty {
                colors.append(PartColor(slot: .stroke, layerIDs: stroked.map(\.id)))
            }
            if !ringed.isEmpty {
                colors.append(PartColor(slot: .border, layerIDs: ringed.map(\.id)))
            }
            // Everything but a line and an arrow, in draw order, so the switch
            // reads the same way twice running.
            let switched = picked.filter { !$0.drawsItsOwnOutline || $0.outlineIsSwitchable }
            rows.append(LayerPartRow(
                part: .outline, colors: colors, title: LayerPart.outline.title,
                switchIDs: switched.map(\.id),
                onCount: switched.filter(\.hasOutline).count,
                // The width reaches every picked layer, arrows included: they
                // cannot lose their line but they can be made thicker, and one
                // Width over a box, an arrow and a screenshot is what the one
                // row promises.
                widthIDs: picked.map(\.id), selectionCount: count))
        }

        // A letter's ink. Always there, so no switch.
        let lettered = picked.filter { $0.colorSlots.contains(.text) }
        if !lettered.isEmpty {
            rows.append(LayerPartRow(
                part: nil, colors: [PartColor(slot: .text, layerIDs: lettered.map(\.id))],
                title: ColorSlot.text.selectionTitle,
                switchIDs: [], onCount: 0, widthIDs: [], selectionCount: count))
        }

        // The shadow is NOT here. It is not something a shape simply has, it
        // is something you added, so it is an entry in the Effects list below
        // (`LayerEffects.swift`) along with the blur. That is the split the
        // user settled on 2026-09-07: Appearance is what it IS, Effects is
        // what you ADD.

        return rows
    }

    /// The row on screen that paints one kind of colour, or nil when no picked
    /// layer wears it.
    ///
    /// A row used to be addressable by the kind of colour alone, because that
    /// is all a row was. Now each one knows WHICH picked layers take each of
    /// its colours, so anything that names a colour by kind — a menu command,
    /// a scripted step — has to come back through here to reach the row a
    /// person is looking at. The first row wins, which is why a highlight's
    /// wash is found on its own row rather than on the Outline row under it.
    public func layerPartRow(layerIDs: [UUID], slot: ColorSlot) -> LayerPartRow? {
        layerPartRows(layerIDs: layerIDs).first { row in
            row.colors.contains { $0.slot == slot }
        }
    }

    /// Gives a part BOTH its presence and a colour in one move, for a colour
    /// let go of on a row whose switch is off.
    ///
    /// A row that is off shows its name and its switch and nothing else, which
    /// is the point of the switch: off looks off. The cost was that a colour
    /// carried over from another row had nowhere to land, so giving a bare box
    /// a red edge meant finding the switch, flipping it, and then repainting
    /// whatever came back (reported 2026-09-07). Letting go of a colour says
    /// both things at once — give this part to these layers, and paint it this
    /// — so it is one edit, and one undo puts all of it back.
    ///
    /// Every named layer ends up wearing the colour, including the ones that
    /// already had the part. That is what a row where some of them are outlined
    /// and some are not already promises: its switch resolves to ON for all of
    /// them rather than stripping the ones that have it.
    ///
    /// A layer that already has the part KEEPS the width it was tuned to; only
    /// the ones gaining it take a width, `restoring` first and the width a
    /// fresh one wears otherwise. Returns how many layers changed.
    @discardableResult
    public mutating func turnOnPart(_ part: LayerPart, layerIDs: [UUID], paint: Paint,
                                    restoring: [UUID: CGFloat] = [:],
                                    index: Int = 0) -> Int {
        var changed = 0
        for id in layerIDs {
            guard let layer = layer(id: id), !layer.isLocked else { continue }
            switch part {
            case .fill:
                guard layer.colorSlots.contains(.fill) else { continue }
                updateLayer(id: id) {
                    $0.unbindColorStyle(for: .fill)
                    // The colour that landed, not the one the switch would have
                    // seeded: somebody chose this one by letting go of it.
                    $0.setPaint(paint, for: .fill)
                }
            case .outline:
                let width = max(1, restoring[id] ?? layer.startingOutlineWidth)
                updateLayer(id: id) { target in
                    // The width goes on FIRST: a layer with no ring has no
                    // border colour at all, so painting before widening would
                    // paint nothing. An arrow has no width to switch — it IS
                    // its line — and simply takes the colour.
                    if !target.hasOutline, target.outlineIsSwitchable {
                        if target.drawsItsOwnOutline {
                            target.setOutlineWidth(width)
                        } else {
                            target.style.borderWidth = width
                        }
                    }
                    let slot = target.outlineSlot
                    target.unbindColorStyle(for: slot)
                    target.setPaint(paint, for: slot)
                }
            case .shadow:
                updateLayer(id: id) { target in
                    // A layer that already throws one keeps the shadow it
                    // tuned and only changes colour, exactly as its own switch
                    // promises. Letting a colour go over a switched-off entry
                    // switches it back on, because that is what the person just
                    // said they wanted.
                    if target.style.shadow(at: index) != nil {
                        target.style.updateShadow(at: index) {
                            $0.colorHex = paint.hex
                            $0.isOn = true
                        }
                    } else {
                        var shadow = ShadowStyle()
                        shadow.colorHex = paint.hex
                        target.style.shadows.append(shadow)
                    }
                }
            }
            changed += 1
        }
        return changed
    }

    /// Switches the line round a set of layers on or off, whichever ring each
    /// one draws. Returns how many changed, so a caller can tell a no-op from
    /// an edit.
    ///
    /// Off is a width of zero, which the rasterizer has always understood as no
    /// line at all, so nothing about how an existing document draws changes:
    /// this only gives the panel a way to say it. The colour is left exactly
    /// where it was, so switching back on brings the same ring back rather than
    /// a black one.
    ///
    /// `restoring` is what each layer's line comes back at, for a panel that
    /// remembers the width it took away. Anything not named there comes back at
    /// the width a fresh one wears.
    @discardableResult
    public mutating func setOutlineEnabled(layerIDs: [UUID], on: Bool,
                                           restoring: [UUID: CGFloat] = [:]) -> Int {
        var changed = 0
        for id in layerIDs {
            guard let layer = layer(id: id), !layer.isLocked,
                  layer.outlineIsSwitchable, layer.hasOutline != on else { continue }
            let width = on ? max(1, restoring[id] ?? layer.startingOutlineWidth) : 0
            updateLayer(id: id) { target in
                if target.drawsItsOwnOutline {
                    target.setOutlineWidth(width)
                } else {
                    target.style.borderWidth = width
                }
            }
            changed += 1
        }
        return changed
    }
}

// MARK: - A part's colour and the shadow's one setting

extension PhotonzDocument {

    /// The Kind popup: the same shadow, thrown behind the layer or cast into
    /// it. Everything else about it survives, because it is one effect drawn in
    /// a different place rather than a different effect.
    @discardableResult
    public mutating func setShadowKind(layerIDs: [UUID], at index: Int, to kind: ShadowKind) -> Int {
        var changed = 0
        for id in layerIDs {
            guard let layer = layer(id: id), !layer.isLocked,
                  let shadow = layer.style.shadow(at: index), shadow.kind != kind else { continue }
            updateLayer(id: id) { $0.style.updateShadow(at: index) { $0.kind = kind } }
            changed += 1
        }
        return changed
    }
}
