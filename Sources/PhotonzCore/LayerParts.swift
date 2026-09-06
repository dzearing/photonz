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
    case shadow

    /// What the parts list calls this part.
    public var title: String {
        switch self {
        case .fill: return "Fill"
        case .outline: return "Outline"
        case .shadow: return "Shadow"
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
    /// line, an arrow or a highlight IS its line — switching it off would leave
    /// nothing on the canvas at all, which is not a setting, it is a delete. So
    /// those carry no switch, and their colour is a property rather than a
    /// part.
    public var outlineIsSwitchable: Bool {
        guard drawsItsOwnOutline, let annotation else { return true }
        switch annotation.shape {
        case .rectangle, .ellipse: return true
        default: return false
        }
    }

    /// The width the outline comes back at when it is switched on and nothing
    /// remembers what it was before. A shape returns to the width a freshly
    /// drawn one wears; a ring round a picture comes back thin, because it is
    /// an edge rather than a stroke.
    public var startingOutlineWidth: CGFloat {
        drawsItsOwnOutline ? AnnotationContent.defaultStrokeWidth : 2
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
    /// The colour this row paints. Nil for the shadow, whose colour is not one
    /// of the layer's slots.
    public let slot: ColorSlot?
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

    public init(part: LayerPart?, slot: ColorSlot?, title: String,
                switchIDs: [UUID], onCount: Int, widthIDs: [UUID],
                selectionCount: Int) {
        self.part = part
        self.slot = slot
        self.title = title
        self.switchIDs = switchIDs
        self.onCount = onCount
        self.widthIDs = widthIDs
        self.selectionCount = selectionCount
    }

    /// Stable enough to key a list on: two rows in one selection never share a
    /// part and a slot.
    public var id: String { "\(part?.rawValue ?? "color").\(slot?.rawValue ?? "none")" }

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

    /// What the row says out loud when it is leaving a picked layer out. Nil
    /// when it reaches all of them, because a sentence saying "this does what
    /// it looks like it does" is a sentence in the way.
    public var reachNote: String? {
        let reach = max(switchIDs.count, widthIDs.count)
        guard reach > 0, reach < selectionCount else { return nil }
        return "Applies to \(reach) of the \(selectionCount) selected layers."
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
                part: .fill, slot: .fill, title: LayerPart.fill.title,
                switchIDs: fillable.map(\.id),
                onCount: fillable.filter { $0.colorHex(for: .fill) != nil }.count,
                widthIDs: [], selectionCount: count))
        }

        // The shape's own line. Named Outline where switching it off leaves
        // something behind, and Color where the line IS the shape: calling an
        // arrow's colour its outline is a small lie, and the row under it would
        // then be an outline you cannot remove.
        let inked = picked.filter { $0.colorSlots.contains(.stroke) }
        if !inked.isEmpty {
            let switchable = inked.filter { $0.outlineIsSwitchable }
            rows.append(LayerPartRow(
                part: switchable.isEmpty ? nil : .outline,
                slot: .stroke,
                title: switchable.isEmpty ? "Color" : LayerPart.outline.title,
                switchIDs: switchable.map(\.id),
                onCount: switchable.filter(\.hasOutline).count,
                widthIDs: inked.filter(\.drawsItsOwnOutline).map(\.id),
                selectionCount: count))
        }

        // A letter's ink. Always there, so no switch.
        let lettered = picked.filter { $0.colorSlots.contains(.text) }
        if !lettered.isEmpty {
            rows.append(LayerPartRow(
                part: nil, slot: .text, title: ColorSlot.text.selectionTitle,
                switchIDs: [], onCount: 0, widthIDs: [], selectionCount: count))
        }

        // The ring round everything that does not stroke its own path: a
        // picture, a frame, a label, a group, a highlight. It used to be called
        // Border and to live under Effects with its colour two sections away.
        // It is the same part as a shape's outline and wears the same name.
        let ringed = picked.filter { !$0.drawsItsOwnOutline }
        if !ringed.isEmpty {
            rows.append(LayerPartRow(
                part: .outline, slot: .border, title: LayerPart.outline.title,
                switchIDs: ringed.map(\.id),
                onCount: ringed.filter(\.hasOutline).count,
                widthIDs: ringed.map(\.id), selectionCount: count))
        }

        // What the layer throws behind it. Every layer can have one.
        rows.append(LayerPartRow(
            part: .shadow, slot: nil, title: LayerPart.shadow.title,
            switchIDs: picked.map(\.id),
            onCount: picked.filter { $0.style.shadow != nil }.count,
            widthIDs: [], selectionCount: count))

        return rows
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
