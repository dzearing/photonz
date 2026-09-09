// The small controls and words the panel's sections share: the unit word, style sliders, the selection menu and the notes that say who a row speaks for.

import PhotonzCore
import SwiftUI

/// How a style row writes a length. One place, so Blur and Size and Distance
/// cannot drift apart, and it says the app's one unit word rather than a word
/// of its own: a 24 here and a 24 on the caliper are the same distance.
func points(_ value: Double) -> String { DocumentUnit.text(CGFloat(value)) }

/// The revert arrow belongs to ONE layer's override of its component, so it is
/// offered only when the section is speaking for one layer. Over a selection
/// there is no single copy for it to answer for.
func soleLayerID(_ ids: [UUID]) -> UUID? { ids.count == 1 ? ids.first : nil }

/// What a style section says out loud before anything is dragged, and after:
/// how many layers it is talking to, and anything it is quietly skipping.
func selectionCaption(_ count: Int, _ lead: String = "A slider here") -> String? {
    guard count > 1 else { return nil }
    return "\(count) layers. \(lead) changes every one of them, in one step."
}

/// The small print under a style section: what it skips, where the picked
/// layers differ, and how many it speaks for. Said only when there is
/// something to say — over one layer every row means what it always meant, and
/// a sentence explaining that is a sentence in the way.
struct SelectionStyleNotes: View {
    let notes: [String?]
    let caption: String?

    var body: some View {
        let lines = (notes + [caption]).compactMap { $0 }
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// A labeled style slider wired to EditorState's preview/commit gesture
/// pattern, over every layer the row speaks for: dragging previews without
/// recording undo; release commits ONE step, however many layers it reached.
struct LayerStyleSlider: View {
    @Environment(EditorState.self) private var editorState
    /// The layers one pull on this slider changes.
    let layerIDs: [UUID]
    let label: String
    /// What the layers say: one number when they agree, Mixed when they do not.
    let reading: StyleReading<Double>
    let range: ClosedRange<Double>
    /// How the number is written when they agree.
    let format: (Double) -> String
    /// The part of the look this slider sets, when it is one a copy of a
    /// component can own. It puts the way back on the row itself, which is
    /// where the person who just dragged it is looking.
    var field: LayerStyleField? = nil
    let apply: (inout LayerStyle, Double) -> Void

    /// Where the knob sits. Over layers that differ this is the first picked
    /// layer's number, and it is a starting point rather than a claim: the
    /// readout beside it says Mixed.
    private var knob: Double {
        min(max(reading.value ?? range.lowerBound, range.lowerBound), range.upperBound)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.caption).foregroundStyle(.secondary)
                if let field, let only = soleLayerID(layerIDs) {
                    InstanceStyleRevert(layerID: only, field: field)
                }
                Spacer()
                let showing = reading.isMixed ? LayerStyleSelection.mixedText : format(knob)
                Text(showing)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(MixedLook.style(reading.isMixed, otherwise: .secondary))
                    .panelReadout(showing)
            }
            Slider(value: Binding(
                get: { knob },
                set: { v in editorState.previewLayerStyle(ids: layerIDs) { apply(&$0, v) } }),
                   in: range) { editing in
                if !editing { editorState.commitLayerStyle(ids: layerIDs) }
            }
            .controlSize(.small)
            .disabled(layerIDs.isEmpty)
            // Named so a walk can move it: a press lands in the middle of the
            // track, which is what putting the knob there by hand does. Without
            // this, everything in Effects could be photographed and never used.
            .playtestControl("Slider", detail: label)
        }
        // The row lends its word to whatever sits on it, so the revert arrow on
        // a Blur row reads as Blur's and not as the Border row's.
        .playtestField(label)
    }
}

/// A shape-settings slider over every picked shape: dragging previews without
/// recording undo; release commits ONE step, however many shapes it reached.
///
/// While the shapes differ the readout says Mixed and the knob sits at the
/// first picked shape's number, so the position is a starting point rather
/// than a claim. The moment the knob moves they agree, and it says so.
struct ShapeSlider: View {
    let layerIDs: [UUID]
    let label: String
    let reading: StyleReading<CGFloat>
    let range: ClosedRange<CGFloat>
    let format: (CGFloat) -> String
    /// How this row rounds the number it sends. Thicknesses and radii are
    /// whole points; an arrowhead multiplier is not.
    var round: (CGFloat) -> CGFloat = { $0.rounded() }
    let preview: ([UUID], CGFloat) -> Void
    let commit: ([UUID], CGFloat) -> Void

    /// Where the knob is while the hand is on it, so it moves smoothly even
    /// though what it sends is rounded.
    @State private var draft: CGFloat?

    private var knob: CGFloat {
        min(max(draft ?? reading.value ?? range.lowerBound, range.lowerBound), range.upperBound)
    }

    /// Mixed only until the drag starts: once it has, they all wear the number
    /// under the knob.
    private var showsMixed: Bool { draft == nil && reading.isMixed }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Spacer()
                let showing = showsMixed ? LayerStyleSelection.mixedText : format(knob)
                Text(showing)
                    .font(.caption.monospacedDigit())
                    .panelReadout(showing)
                    .foregroundStyle(MixedLook.style(showsMixed, otherwise: .secondary))
            }
            Slider(value: Binding(
                get: { knob },
                set: { v in
                    draft = v
                    preview(layerIDs, round(v))
                }), in: range) { editing in
                if !editing {
                    commit(layerIDs, round(draft ?? knob))
                    draft = nil
                }
            }
            .controlSize(.small)
            .disabled(layerIDs.isEmpty)
            .playtestControl("Slider", detail: label)
        }
        .playtestField(label)
    }
}

/// A menu that speaks for the whole selection: the one thing they all say, or
/// the word Mixed. Choosing anything makes them agree — which is exactly what
/// the word is there to offer, so it is a real entry in the menu rather than a
/// blank box.
struct SelectionMenu<Value: Hashable & Sendable>: View {
    let label: String
    let reading: StyleReading<Value>
    let options: [Value]
    let title: (Value) -> String
    /// The same value in the words a SENTENCE wants, when the words in the box
    /// are not those: the Size menu pads its numbers out with blank so every
    /// size takes the same room, and a hover must not read that blank back.
    /// Nil wherever the box already says exactly what it means.
    var spoken: ((Value) -> String)?
    /// What this menu is, in words, for anyone who hovers it. The caption above
    /// the menu says the same thing without being asked. When the box is too
    /// narrow for what it is showing, the full value is said here first.
    let help: String
    /// A width to hold, whatever ends up in the list. Nil for a menu whose list
    /// never changes, which is every menu but Font: those are already still.
    var pinnedWidth: CGFloat?
    let choose: (Value) -> Void

    /// The words the box is showing, when it is showing a value at all.
    private var shownTitle: String? {
        reading.isMixed ? nil : reading.value.map(title)
    }

    /// The same value as a sentence would say it, which is what a hover reads.
    private var saidTitle: String? {
        reading.isMixed ? nil : reading.value.map(spoken ?? title)
    }

    /// Whether the box had to shorten them.
    private var isClipped: Bool {
        guard let pinnedWidth, let shownTitle else { return false }
        return !MenuMetrics.fits(shownTitle, in: pinnedWidth)
    }

    var body: some View {
        // The caption sits above the menu, the way every other labelled
        // control in this dock reads (Effects sliders, Measure fields). A menu
        // showing Mixed is only useful if the row beside it says WHAT is
        // mixed, and with three menus in a row the shape of the word is not
        // enough: "Regular" and "Mixed" both look like a weight.
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Picker(label, selection: Binding<Value?>(
                get: { reading.isMixed ? nil : reading.value },
                set: { if let value = $0 { choose(value) } })) {
                if reading.isMixed {
                    // A closed pop-up button draws its own title, and
                    // `.foregroundStyle` on the Picker does not reach it (tried
                    // in the probe and photographed: the word stayed white).
                    // Styling the Text on the row does reach it, which is the
                    // only way this menu can say Mixed at the same strength the
                    // field and the slider beside it do.
                    Text(LayerStyleSelection.mixedText)
                        .foregroundStyle(MixedLook.style)
                        .tag(Value?.none)
                }
                ForEach(options, id: \.self) { option in
                    Text(title(option)).tag(Value?.some(option))
                }
            }
            .pickerStyle(.menu).labelsHidden().controlSize(.small)
            // Held to one width, so a name the list picked up from an opened
            // document cannot stretch the row. A pop-up takes a width smaller
            // than its content and shortens the closed title with an ellipsis,
            // which is what should happen to a name too long for the box; the
            // open menu still spells every name out in full.
            .frame(width: pinnedWidth)
            .accessibilityLabel(label)
        }
        // The caption names the row, and the row names the menu for a walk.
        // A menu wears its own value — "24 px" one moment, "48 px" the next —
        // so a walk that named it by its words would stop working the first
        // time it used it.
        .playtestField(label)
        // `panelHelp`, not `.help`, so the sentence a shortened name puts in
        // front is something a walk can read back. It is the same text either
        // way; the probe simply keeps a copy of it.
        .panelHelp(MenuTip.text(about: help, showing: saidTitle, isClipped: isClipped))
    }
}
