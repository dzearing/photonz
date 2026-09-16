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

/// The small print under a style section: what it skips and where the picked
/// layers differ. Said only when there is something to say — over one layer
/// every row means what it always meant, and a sentence explaining that is a
/// sentence in the way.
///
/// It used to end with a caption counting the selection and promising that a
/// slider reached all of it. That went on 2026-09-14 (UX-PATTERNS §4, "How much
/// a section may say"): the Layers section already prints "3 layers selected"
/// two sections above, and a change reaching everything you picked is what
/// picking several things means. What is left here is the register the rule
/// does NOT cap — a note that reports a condition, shown only while it holds.
struct SelectionStyleNotes: View {
    let notes: [String?]

    var body: some View {
        let lines = notes.compactMap { $0 }
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

/// The number beside a slider.
///
/// A row that says how its number is typed (`SliderNumber`) gets **the one
/// number box**: click the number, type an exact one, press Return. An exact
/// 12 stops being a matter of nudging the knob until the readout agrees, which
/// on a 1-to-40 Thickness over a 24 point icon is the whole useful range
/// packed into the first two points of travel.
///
/// A row whose answer is a WORD rather than a number — Label corners reads
/// Square and Pill at its ends — keeps the readout it has always had. There is
/// nothing to type there.
///
/// Everything about typing is decided once, in `PanelNumberField` and
/// `NumberBox`: Return and Tab land it, Escape puts it back, clicking in
/// selects the whole number, up and down step it, the word Mixed is drawn at
/// the one strength every other Mixed in the dock uses, and landing a number
/// something already has spends no undo step.
struct SliderReadout: View {
    /// How this row's number is typed, or nil where its readout is a word.
    let typing: SliderNumber?
    /// The row's own name. It becomes the box's placeholder and its
    /// accessibility label, so a walk finds the box by the word above it.
    let label: String
    /// Where the slider is, in the slider's own units.
    let value: CGFloat
    let isMixed: Bool
    let range: ClosedRange<CGFloat>
    /// How the row writes the number when there is no box to type in. Only
    /// the rows whose answer is a word ever need one.
    var format: (CGFloat) -> String = { String(Int($0.rounded())) }
    /// WHICH thing the number speaks for: the layers a style row reaches, the
    /// style a saved effect row edits. A different thing is a different
    /// number, so a half-typed draft does not carry across a change of
    /// selection.
    let identity: AnyHashable?
    /// Whether there is anything to type into. A row speaking for no layers
    /// draws its number and takes no keyboard, exactly as its slider does.
    var isEnabled = true
    /// The typed number, in the SLIDER's units, reaching whatever the row
    /// speaks for.
    ///
    /// Nothing is handed back, because nothing here refuses: every one of
    /// these rows stores the number it is given, and the only limit is the
    /// ends of the slider, which the box has already held it inside. That was
    /// checked row by row on 2026-09-16 — a shadow's Distance and Direction
    /// are the two that go in as one number and come out of another
    /// (an offset), and both read back the number that was typed. A row that
    /// one day DOES refuse owes the box what it really took
    /// (`PanelNumberField.land`), or the next arrow key steps from a number
    /// nothing on the canvas is wearing.
    let land: (CGFloat) -> Void

    var body: some View {
        if let typing {
            box(typing)
        } else {
            let showing = isMixed ? LayerStyleSelection.mixedText : format(value)
            Text(showing)
                .font(.caption.monospacedDigit())
                .foregroundStyle(MixedLook.style(isMixed, otherwise: .secondary))
                .panelReadout(showing)
        }
    }

    private func box(_ typing: SliderNumber) -> some View {
        PanelNumberField(
            showing: isMixed ? .standIn(LayerStyleSelection.mixedText)
                             : .number(typing.spell(typing.shown(value))),
            label: label,
            identity: identity,
            leading: typing.leading,
            suffix: typing.suffix,
            // Narrower than the geometry boxes: these sit at the end of a row
            // that already spent its width on the row's name, and the numbers
            // are short — a strength stops at 100 and a length at 40.
            width: .fixed(48),
            // The ends of the slider are the ends of the box, so a typed 140
            // on a 0-to-100 strength shows 100 rather than 140 over a knob
            // sitting at the top.
            floor: typing.shown(range.lowerBound),
            ceiling: typing.shown(range.upperBound),
            wholeNumbers: typing.wholeNumbers,
            spell: typing.spell,
            land: { typed in
                land(typing.slid(typed))
                return nil
            })
        .disabled(!isEnabled)
        // What a PERSON reads here, which is the number and the unit beside
        // it — "12 px", not the "12" in the box. The one-unit check and every
        // walk that quotes a row read this, and they must see the row the way
        // it is written rather than the way it is stored.
        .panelReadout(isMixed ? LayerStyleSelection.mixedText
                              : typing.readout(typing.shown(value)))
    }
}

/// A labeled style slider wired to EditorState's preview/commit gesture
/// pattern, over every layer the row speaks for: dragging previews without
/// recording undo; release commits ONE step, however many layers it reached.
///
/// The number beside it is typed into wherever the row says how its number is
/// written (`typing`), and a typed number is ONE undo step, the same as a pull
/// on the knob.
struct LayerStyleSlider: View {
    @Environment(EditorState.self) private var editorState
    /// The layers one pull on this slider changes.
    let layerIDs: [UUID]
    let label: String
    /// What the layers say: one number when they agree, Mixed when they do not.
    let reading: StyleReading<Double>
    let range: ClosedRange<Double>
    /// How this row's number is written and typed: a length, a strength, a
    /// turn. Lengths are so much the commonest that they are the default.
    var typing: SliderNumber = .points
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
                SliderReadout(
                    typing: typing, label: label, value: CGFloat(knob),
                    isMixed: reading.isMixed,
                    range: CGFloat(range.lowerBound)...CGFloat(range.upperBound),
                    identity: layerIDs, isEnabled: !layerIDs.isEmpty,
                    // ONE undo step, the same as a pull on the knob is: a
                    // typed number is a one-shot edit with no preview behind
                    // it, so it goes the way the steppers and the switches go.
                    land: { value in
                        editorState.setLayerStyle(ids: layerIDs) { apply(&$0, Double(value)) }
                    })
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
    /// How this row's number is written and typed. Nil on the one row whose
    /// answer is a WORD — Label corners reads Square and Pill at its ends —
    /// which keeps the plain readout it has always had.
    var typing: SliderNumber? = nil
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
                SliderReadout(
                    typing: typing, label: label, value: knob, isMixed: showsMixed,
                    range: range, format: format,
                    identity: layerIDs, isEnabled: !layerIDs.isEmpty,
                    // The commit is ONE undo step on its own — it is what the
                    // end of a drag calls — so a typed number costs exactly
                    // what a pull costs. The shapes clamp it to the same ends
                    // the box already held it inside, so there is nothing for
                    // them to refuse.
                    land: { value in commit(layerIDs, round(value)) })
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
