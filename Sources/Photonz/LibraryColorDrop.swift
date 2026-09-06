import AppKit
import PhotonzCore
import SwiftUI

// MARK: - Letting a colour go on the Library shelf (Next, `next-styles`)

/// A colour let go of on the Library shelf, waiting for its name.
///
/// It carries the shelf the Library was showing when the colour landed as well
/// as the colour itself: the shelf turns to Styles so the field sits above the
/// tiles the colour is joining, and Escape owes somebody the shelf they were
/// actually looking at.
struct DroppedColorNaming: Equatable {
    var paint: Paint
    var scopeBefore: String
}

/// The Library as somewhere to drop a colour.
///
/// Every other well in the panel takes a colour to PAINT with it. The shelf is
/// the one place that KEEPS it: letting go asks for a name, and the colour
/// becomes a tile any colour row can reach afterwards. Until this existed a
/// colour you liked could be carried from swatch to swatch but never put down
/// anywhere, so keeping one meant going back to the row it came from and
/// finding Save as Style there.
///
/// The whole panel takes the drop, not only the tiles: the shelf is small, the
/// tiles move as it is searched, and a target you have to hit is not a target
/// somebody discovers. It lights up in EVERY scope too, and letting go turns
/// the shelf to Styles as the colour lands — three scopes out of four that
/// quietly refuse a colour would be the confusing answer to the same
/// question, and naming a colour over a wall of screenshots says nothing
/// about where it is going. Escape turns the shelf back.
struct LibraryColorDrop: ViewModifier {
    @Environment(EditorState.self) private var editorState

    /// The answer to whatever is being held over the shelf right now. Nil when
    /// nothing is, and when what is in the air is not a colour at all.
    @State private var incoming: ColorDrop.Answer?

    func body(content: Content) -> some View {
        if Experiments.shared.colorDragEnabled && editorState.colorStylesEnabled {
            content
                .onDrop(of: ColorDrag.acceptedTypes,
                        delegate: LibraryColorDropDelegate(answer: answer,
                                                           incoming: $incoming,
                                                           apply: save))
                .overlay { highlight }
                // The sentence the shelf would say. A tip does not show while
                // a drag is in the air, so this is for the accessibility
                // reader and for the moment the pointer rests mid-thought.
                .accessibilityValue(incoming?.note ?? "")
                // Named so a scripted walk can let a colour go on the shelf
                // through the same delegate a pointer drives.
                .playtestTarget("Library", kind: .row, detail: "Shelf")
        } else {
            content
        }
    }

    /// What the shelf would do with the paint in the air right now.
    private func answer() -> ColorDrop.Answer? {
        guard let payload = ColorDrag.payloadInFlight() else { return nil }
        return editorState.colorShelfDrop(payload.paint)
    }

    private func save(_ landing: ColorDrop.Landing) {
        editorState.beginNamingDroppedColor(landing.paint)
    }

    /// What the shelf about to keep a colour looks like: the ring the swatches
    /// use, around the whole panel, and one short line saying what letting go
    /// would do.
    ///
    /// The line is here and not on a swatch because a swatch that lights up is
    /// self-explanatory — it paints — while a shelf that lights up is a
    /// promise nobody has seen before. It is an overlay rather than a row, so
    /// the shelf does not jump under the pointer at the moment of the drop.
    @ViewBuilder private var highlight: some View {
        if let paint = incoming?.landing?.paint {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, lineWidth: 2))
                .overlay {
                    Text("Save this \(ColorStyleNaming.subject(paint))")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.accentColor))
                        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                }
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }
}

/// The shelf as a drop target.
///
/// The paint is READ before the pointer is let go, off the drag pasteboard
/// rather than out of the carrier the drop hands over, for the reason the
/// swatch delegate gives: a carrier gives up its bytes asynchronously and the
/// highlight is a promise that has to be on screen the frame the pointer
/// arrives.
private struct LibraryColorDropDelegate: DropDelegate {
    let answer: () -> ColorDrop.Answer?
    @Binding var incoming: ColorDrop.Answer?
    let apply: (ColorDrop.Landing) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        !info.itemProviders(for: ColorDrag.acceptedTypes).isEmpty
    }

    func dropEntered(info: DropInfo) {
        incoming = answer()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let next = answer()
        if incoming != next { incoming = next }
        return DropProposal(operation: next?.lightsUp == true ? .copy : .forbidden)
    }

    func dropExited(info: DropInfo) {
        incoming = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        let landing = answer()?.landing
        incoming = nil
        guard let landing else { return false }
        apply(landing)
        return true
    }
}

// MARK: - The name the dropped colour is waiting for

/// The field a colour let go of on the shelf opens.
///
/// It is the colour row's field, in the shelf's own words: the same suggested
/// name on a name nobody is using, the same Return to keep and Escape to drop,
/// the same one line. What it adds is the colour itself beside the box —
/// a colour dropped here came from somewhere else in the panel, or from
/// another app entirely, so the field has to say WHICH colour it is naming.
///
/// Asking before anything is made is the point. A shelf that quietly grew a
/// tile called "Color 1" on every drop would be a shelf full of colours nobody
/// meant to keep.
struct LibraryColorNamingField: View {
    @Environment(EditorState.self) private var editorState
    let paint: Paint

    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            swatch
            TextField("Style name", text: $draft)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .controlSize(.small)
                .focused($focused)
                .onSubmit(save)
                // Escape drops it: nothing was made, so there is nothing to
                // undo either. Both keys hand the keyboard back to the
                // picture, so the next tool letter picks a tool rather than
                // vanishing into a field that has just closed.
                .nameFieldKeys(commit: save,
                               revert: { editorState.endNamingDroppedColor() })
            Button("Save", action: save)
                .controlSize(.small)
                .help("Saves this \(ColorStyleNaming.subject(paint)) under that name")
                .playtestControl("Save", detail: "Library")
        }
        .playtestField("Style name")
        // Keyed on the paint, so a second colour dropped while the field is
        // still open re-opens it on that colour rather than naming the first
        // one by mistake.
        .onChange(of: paint, initial: true) { _, incoming in
            draft = editorState.suggestedColorStyleName(paint: incoming)
            focused = true
            DispatchQueue.main.async { NSApp.keyWindow?.firstResponder?.trySelectAllText() }
        }
    }

    private var swatch: some View {
        PaintFill(paint: paint)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .background(CheckerBoard(square: 4).clipShape(RoundedRectangle(cornerRadius: 4)))
            .frame(width: 18, height: 18)
            .overlay(RoundedRectangle(cornerRadius: 4)
                .strokeBorder(.primary.opacity(0.25), lineWidth: 1))
            .help(ColorStyleNaming.paintText(paint))
    }

    private func save() {
        editorState.saveDroppedColorStyle(name: draft)
    }
}

extension View {
    /// Makes this the place a colour can be let go of to keep it.
    func libraryColorDrop() -> some View {
        modifier(LibraryColorDrop())
    }
}
