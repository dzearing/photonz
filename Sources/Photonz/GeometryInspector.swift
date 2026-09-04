import AppKit
import PhotonzCore
import SwiftUI

/// Where the selected layers sit and how big they are, as four numbers you can
/// type (Next, `next-geometry-fields`).
///
/// The point of this section is building to a spec: two buttons the same width,
/// a row exactly 296 by 118. Dragging can get close and never exact, so every
/// number here is typeable, steps by an arrow key the same 1 and 10 the canvas
/// nudges by, and lands as one undo step.
///
/// It speaks for the WHOLE selection. Pick four buttons and type one width and
/// all four take it; type one X and all four line up on that left edge. Where
/// the picked layers already agree the field shows their number, and where they
/// do not it says Mixed rather than showing the last one you clicked, because a
/// number that stands for one layer out of four is how you set three layers to
/// something you never meant to type.
///
/// The fields follow a drag in flight (they read `previewedFrame`), so the
/// numbers move with the layer instead of jumping on mouse-up. Which of the
/// four accept typing is `LayerGeometryEditing`'s call: a field is typeable
/// exactly where the canvas already lets you drag the same thing, and one that
/// is not says why on hover rather than sitting there dead.
struct GeometryInspector: View {
    @Environment(EditorState.self) private var editorState

    private var selection: LayerGeometrySelection { editorState.geometrySelection }

    var body: some View {
        let selection = selection
        return VStack(alignment: .leading, spacing: 6) {
            // Two pairs, position over size, each field taking half the panel:
            // the numbers are the point of the section, so they get the room
            // rather than sitting in 58 points with the panel empty beside them.
            HStack(spacing: 8) {
                field(.x, selection)
                field(.y, selection)
            }
            HStack(spacing: 8) {
                field(.width, selection)
                field(.height, selection)
            }
            Text(caption(selection))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    /// What the numbers mean, in words. With one layer picked that is where
    /// the layer sits on the picture; with several it has to say that a number
    /// lands on every one of them, and which edge each letter is, or "type 24
    /// into X" reads as a guess.
    private func caption(_ selection: LayerGeometrySelection) -> String {
        guard selection.count > 1 else {
            return "\(LayerGeometry.unitSuffix) from the top left. Up or down arrow steps by 1, Shift by 10."
        }
        return "\(selection.count) layers, all at once. X sets every left edge, Y every top edge, "
            + "W and H each layer's own size. Arrow steps them all by 1, Shift by 10."
    }

    private func field(_ field: LayerGeometryField,
                       _ selection: LayerGeometrySelection) -> some View {
        GeometryNumberField(
            field: field,
            selectionKey: selection.members.map(\.id),
            reading: selection.reading(field),
            isEditable: selection.allows(field),
            help: help(field, selection),
            commit: { value in
                editorState.setLayerGeometry(field: field, to: value)
            },
            landing: { value in selection.landing(value, in: field) },
            stepAll: { direction, coarse in
                editorState.stepLayerGeometry(field: field, direction: direction, coarse: coarse)
            })
    }

    /// The hover tip: why a field takes nothing, or what it is plus how much of
    /// the selection it reaches. A width that quietly skips the arrow in the
    /// selection says so here rather than looking broken.
    private func help(_ field: LayerGeometryField,
                      _ selection: LayerGeometrySelection) -> String {
        if let reason = selection.fixedReason(for: field) { return reason }
        guard let note = selection.note(for: field) else { return field.title }
        return "\(field.title). \(note)"
    }
}

/// One typed geometry number, standing for every selected layer.
///
/// The draft lives in the field until it lands, and it lands on Return, on Tab,
/// and on clicking away, because a number typed and then abandoned is the most
/// common way a person loses an edit. Up and down arrow step it without leaving
/// the field. Text that is not a number snaps back to what the layers really
/// are rather than being guessed at.
///
/// Typing a number is a moment, not a mode: Return and Escape both finish it
/// and hand the keyboard back to the picture, so the very next key picks a tool
/// or nudges the layer instead of landing in the box. `NumberFieldEntry` owns
/// that rule.
private struct GeometryNumberField: View {
    let field: LayerGeometryField
    /// Which layers the number stands for. A different set of layers is a
    /// different set of numbers, so the draft starts fresh when this changes
    /// rather than carrying the last selection's half-typed text. The FIELD
    /// itself stays: the section used to take a new identity per selection,
    /// which tore down and rebuilt four text fields on every click, the single
    /// biggest cost of selecting a layer (measured 2026-09-03). Only the draft
    /// ever had to be reset.
    let selectionKey: [UUID]
    let reading: LayerGeometryReading
    let isEditable: Bool
    let help: String
    let commit: (CGFloat) -> Void
    /// What the field will read once a number lands. A layer can refuse part
    /// of what was typed — a text box will not go below its floor — and the
    /// box has to show what the layer took, not what was asked for, or the
    /// next arrow key steps from a number nothing has.
    let landing: (CGFloat) -> LayerGeometryReading
    /// An arrow key with no number in the box: every layer steps from its own
    /// value, which is the only thing a step can mean when they differ.
    let stepAll: (Int, Bool) -> Void

    @State private var text = ""
    /// Set while Return or Escape is handing the keyboard over, so the focus
    /// loss that follows does not land the draft a second time. Escape needs
    /// it: without it, letting go would commit the rounded number on screen
    /// over the fraction a drag left behind, and abandoning an edit would cost
    /// an undo step that changes nothing you can see.
    @State private var isFinishing = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text(field.label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 11, alignment: .leading)
            TextField(field.label, text: $text)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .multilineTextAlignment(.trailing)
                .frame(minWidth: 52, maxWidth: .infinity)
                .focused($isFocused)
                .disabled(!isEditable)
                .monospacedDigit()
                // Mixed is a word among numbers, so it reads as the quieter
                // thing it is rather than as a value someone typed. A number
                // you cannot type — how tall a paragraph came out, where the
                // stack put a row — reads quiet for the same reason: it is
                // there to be read, not to be edited.
                .foregroundStyle(reading.isMixed || !isEditable
                                 ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                // Tab, and anything else that moves the keyboard on by itself,
                // still lands the draft; Return goes through the key rule
                // below so it can hand the keyboard back as well.
                .onSubmit { land() }
                // Up and down step the number. The canvas nudges the layer on
                // the same keys, but it only sees them when the canvas itself
                // has focus, so a focused field and a focused canvas never both
                // answer one press.
                .numberFieldKeys(
                    isEditable: isEditable,
                    commit: { finish { land() } },
                    revert: { finish { text = display() } },
                    step: { direction, coarse in step(direction: direction, coarse: coarse) })
        }
        .help(help)
        .onAppear { text = display() }
        .onChange(of: reading) { text = display() }
        .onChange(of: selectionKey) { text = display() }
        .onChange(of: isFocused) { _, focused in
            if focused {
                selectEverything()
            } else if isFinishing {
                isFinishing = false
            } else {
                land()
            }
        }
    }

    /// Taking the keyboard selects the whole number, the way it does in every
    /// design tool: you click W to type a new width, not to append digits to
    /// the old one. SwiftUI has no way to say this, so it goes through the
    /// field editor that just became first responder.
    private func selectEverything() {
        DispatchQueue.main.async {
            let windows = [NSApp.keyWindow, NSApp.mainWindow].compactMap { $0 } + NSApp.windows
            for window in windows {
                if let editor = window.firstResponder as? NSTextView {
                    editor.selectAll(nil)
                    return
                }
            }
        }
    }

    /// Finishing with the field: do the thing the key means, then remember
    /// that the focus loss on its way over is this, not a click somewhere else.
    private func finish(_ body: () -> Void) {
        body()
        isFinishing = true
    }

    /// The field's draft becoming every selected layer's real number.
    private func land() {
        guard isEditable, let parsed = LayerGeometry.parse(text) else {
            text = display()
            return
        }
        // The layers may clamp what was asked for (a width of 0 is not a
        // layer, and a text box stops at its own floor); showing what they
        // actually became beats showing what was typed.
        let landed = landing(parsed)
        commit(parsed)
        text = display(landed)
    }

    /// An arrow key. A number in the box steps that number and lands it on
    /// everything; an empty box or a Mixed one steps each layer from its own
    /// value, so a spread-out row moves together and stays spread out.
    private func step(direction: Int, coarse: Bool) {
        guard let base = LayerGeometry.parse(text) ?? reading.number else {
            stepAll(direction, coarse)
            return
        }
        let next = LayerGeometry.stepped(base, direction: direction, coarse: coarse)
        let landed = landing(next)
        commit(next)
        // Down arrow at a text box's floor holds at the floor rather than
        // counting on down a box that is not moving.
        text = display(landed)
    }

    /// What the box shows: the number the layers agree on, or the word that
    /// says they do not.
    private func display() -> String { display(reading) }

    private func display(_ reading: LayerGeometryReading) -> String {
        switch reading {
        case .empty: return ""
        case .mixed: return LayerGeometrySelection.mixedText
        case .agreed(let value): return displayed(value)
        }
    }

    /// Whole points, the same rounding `LayerGeometry.displayValue` does, so
    /// what is on screen is exactly what an arrow key steps from.
    private func displayed(_ value: CGFloat) -> String {
        String(Int(value.rounded()))
    }
}
