import PhotonzCore
import SwiftUI

/// A part that is switched OFF as somewhere to let a colour go.
///
/// Every other colour in the panel lives on a swatch, and a swatch is
/// something you pull a colour out of and drop a colour onto. A part that is
/// off has no swatch: off has to look off, so its colour and its settings are
/// not sitting there pretending to do something. That left one gesture with
/// nowhere to land. A box drawn with no line round it showed an Outline row
/// with an off switch and an empty column, so a colour carried over from Fill
/// was refused and the only way to a coloured edge was to find the switch,
/// flip it, and repaint whatever came back (reported 2026-09-07).
///
/// So the ROW is the landing spot. It is a bigger target than any swatch, it
/// is where a person carrying a colour is already looking (they are aiming at
/// the word Outline), and it costs nothing at rest: the row draws exactly what
/// it drew before until a colour is actually over it.
///
/// Letting go both switches the part on and paints it, in one step one undo
/// puts back. The sentence the row says while the colour is in the air says so
/// before it happens.
struct OffPartColorDrop: ViewModifier {
    @Environment(EditorState.self) private var editorState
    let row: LayerPartRow
    /// Only while the part is off. A part that is on has its own swatch, and
    /// two drop targets stacked on one row would fight over the same pointer.
    let active: Bool
    @Binding var incoming: ColorDrop.Answer?

    @ViewBuilder func body(content: Content) -> some View {
        if active, row.hasSwitch, Experiments.shared.colorDragEnabled {
            content
                // The whole band, gaps included: a row is mostly empty space
                // once its colour is gone, and empty space that swallows a
                // drop is the thing this exists to stop.
                .contentShape(Rectangle())
                .overlay { ring }
                .onDrop(of: ColorDrag.acceptedTypes,
                        delegate: OffPartDropDelegate(answer: answer, incoming: $incoming,
                                                      apply: apply))
                // A tip does not show while a drag is in the air, so this is
                // here for the accessibility reader and for the pointer
                // resting on the row mid-thought.
                .accessibilityValue(incoming?.note ?? "")
        } else {
            content
        }
    }

    /// What this row would do with whatever is in the air right now.
    private func answer() -> ColorDrop.Answer? {
        guard let payload = ColorDrag.payloadInFlight() else { return nil }
        let target = ColorTarget(row.colors)
        // The shadow has no colour of the layer's own, so it wears no names —
        // exactly as its swatch already answers once the shadow is on.
        var welcome = ColorDrop.StyleWelcome.neverWearsNames
        if let style = payload.style, let target {
            welcome = editorState.styleWelcome(target, styleID: style.id)
        }
        return ColorDrop.answer(
            dropping: payload.paint, bringing: payload.style,
            on: ColorDrop.Target(
                part: row.title,
                // What the part would come back at if the switch were flipped
                // instead. It is never compared against the colour arriving —
                // an absent part is not WEARING anything — so this is only
                // here to keep the value honest.
                wearing: target.flatMap { editorState.selectionPaint($0) } ?? Paint(hex: "#000000"),
                reaches: row.switchIDs.count,
                isAbsent: true,
                acceptsGradient: target?.acceptsGradient ?? false,
                welcome: welcome))
    }

    private func apply(_ landing: ColorDrop.Landing) {
        editorState.dropColorOnOffPart(row, landing: landing)
    }

    /// The row lighting up, drawn the way a swatch does: a ring outside the
    /// content rather than a wash over it, so the words stay readable while
    /// the colour is overhead.
    @ViewBuilder private var ring: some View {
        if incoming?.lightsUp == true {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .padding(.vertical, -3)
                .padding(.horizontal, -5)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }
}

/// The row as a drop target, shaped exactly like the swatch's own delegate:
/// the answer is read BEFORE the pointer is let go, because the ring is a
/// promise about what letting go would do.
struct OffPartDropDelegate: DropDelegate {
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

/// The same landing spot, for a switched-off row in the Effects list.
///
/// A shadow that is off shows its name and its tick and nothing else, exactly
/// as a switched-off outline does, so a colour carried over to it needs the row
/// itself to catch it. Letting go switches the shadow back on wearing that
/// colour, in one step one undo puts back.
struct OffEffectColorDrop: ViewModifier {
    @Environment(EditorState.self) private var editorState
    let row: LayerEffectRow
    let active: Bool
    @Binding var incoming: ColorDrop.Answer?

    @ViewBuilder func body(content: Content) -> some View {
        if active, row.kind.paintsAColor, Experiments.shared.colorDragEnabled {
            content
                .contentShape(Rectangle())
                .overlay { ring }
                .onDrop(of: ColorDrag.acceptedTypes,
                        delegate: OffPartDropDelegate(answer: answer, incoming: $incoming,
                                                      apply: apply))
                .accessibilityValue(incoming?.note ?? "")
        } else {
            content
        }
    }

    /// What this row would do with whatever is in the air right now. An effect
    /// wears no saved colour names of its own — its colour is not one of the
    /// layer's slots — exactly as its swatch already answers once it is on.
    private func answer() -> ColorDrop.Answer? {
        guard let payload = ColorDrag.payloadInFlight() else { return nil }
        return ColorDrop.answer(
            dropping: payload.paint, bringing: payload.style,
            on: ColorDrop.Target(
                part: row.title,
                wearing: Paint(hex: "#000000"),
                reaches: row.switchIDs.count,
                isAbsent: true,
                acceptsGradient: false,
                welcome: .neverWearsNames))
    }

    private func apply(_ landing: ColorDrop.Landing) {
        editorState.dropColorOnOffEffect(row, landing: landing)
    }

    @ViewBuilder private var ring: some View {
        if incoming?.lightsUp == true {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .padding(.vertical, -3)
                .padding(.horizontal, -5)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }
}
