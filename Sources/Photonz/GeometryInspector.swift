import AppKit
import PhotonzCore
import SwiftUI

/// Where the selected layer sits and how big it is, as four numbers you can
/// type (Next, `next-geometry-fields`).
///
/// The point of this section is building to a spec: two buttons the same width,
/// a row exactly 296 by 118. Dragging can get close and never exact, so every
/// number here is typeable, steps by an arrow key the same 1 and 10 the canvas
/// nudges by, and lands as one undo step.
///
/// The fields follow a drag in flight (they read `previewedFrame`), so the
/// numbers move with the layer instead of jumping on mouse-up. Which of the
/// four accept typing is `LayerGeometryEditing`'s call: a field is typeable
/// exactly where the canvas already lets you drag the same thing, and one that
/// is not says why on hover rather than sitting there dead.
struct GeometryInspector: View {
    @Environment(EditorState.self) private var editorState
    let layer: Layer

    /// Preview-aware, so the numbers keep up with a canvas drag.
    private var frame: CGRect {
        editorState.previewedFrame(of: layer.id) ?? layer.frame
    }

    /// Read fresh from the document: locking a layer while it is selected has
    /// to close its fields on the spot.
    private var editing: LayerGeometryEditing {
        LayerGeometryEditing(layer: editorState.document?.layer(id: layer.id) ?? layer)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Two pairs, position over size, each field taking half the panel:
            // the numbers are the point of the section, so they get the room
            // rather than sitting in 58 points with the panel empty beside them.
            HStack(spacing: 8) {
                field(.x)
                field(.y)
            }
            HStack(spacing: 8) {
                field(.width)
                field(.height)
            }
            Text("\(LayerGeometry.unitSuffix) from the top left. Up or down arrow steps by 1, Shift by 10.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        // A different layer is a different set of numbers, so its fields start
        // fresh rather than carrying the last one's half-typed draft.
        .id(layer.id)
    }

    private func field(_ field: LayerGeometryField) -> some View {
        let editing = editing
        return GeometryNumberField(
            field: field,
            value: LayerGeometry.displayValue(field, of: frame),
            isEditable: editing.allows(field),
            fixedReason: editing.fixedReason(for: field),
            commit: { value in
                editorState.setLayerGeometry(id: layer.id, field: field, to: value)
            })
    }
}

/// One typed geometry number.
///
/// The draft lives in the field until it lands, and it lands on Return, on Tab,
/// and on clicking away, because a number typed and then abandoned is the most
/// common way a person loses an edit. Up and down arrow step it without leaving
/// the field. Text that is not a number snaps back to what the layer really is
/// rather than being guessed at.
///
/// Typing a number is a moment, not a mode: Return and Escape both finish it
/// and hand the keyboard back to the picture, so the very next key picks a tool
/// or nudges the layer instead of landing in the box. `NumberFieldEntry` owns
/// that rule.
private struct GeometryNumberField: View {
    let field: LayerGeometryField
    let value: CGFloat
    let isEditable: Bool
    let fixedReason: String?
    let commit: (CGFloat) -> Void

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
                    revert: { finish { text = display(value) } },
                    step: { direction, coarse in step(direction: direction, coarse: coarse) })
        }
        .help(fixedReason ?? field.title)
        .onAppear { text = display(value) }
        .onChange(of: value) { text = display(value) }
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

    /// The field's draft becoming the layer's real number.
    private func land() {
        guard isEditable, let parsed = LayerGeometry.parse(text) else {
            text = display(value)
            return
        }
        commit(parsed)
        // The layer may have clamped what was asked for (a width of 0 is not a
        // layer); showing what it actually became beats showing what was typed.
        text = display(value)
    }

    private func step(direction: Int, coarse: Bool) {
        let base = LayerGeometry.parse(text) ?? value
        let next = LayerGeometry.stepped(base, direction: direction, coarse: coarse)
        commit(next)
        text = display(next)
    }

    /// Whole points, the same rounding `LayerGeometry.displayValue` does, so
    /// what is on screen is exactly what an arrow key steps from.
    private func display(_ value: CGFloat) -> String {
        String(Int(value.rounded()))
    }
}
