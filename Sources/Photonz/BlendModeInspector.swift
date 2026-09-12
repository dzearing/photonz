import PhotonzCore
import SwiftUI

/// **Blending**: how the picked layers mix with what is under them
/// (Next, `next-blend-mode`).
///
/// It sits directly under Opacity because the two answer one question between
/// them. Opacity says how MUCH of what is below shows through; Blending says
/// how the two are mixed once it does. Put anywhere else in the panel it would
/// read as a fourth kind of effect, which is exactly what it is not: nothing is
/// added to the layer, the layer is simply laid down differently.
///
/// The control is a button that opens a list rather than a pop-up menu, and
/// that is the whole point of it. A macOS pop-up is an `NSMenu`, and a menu
/// tells nobody what its words mean and never previews anything. This list
/// gives every choice a plain sentence beside its name, and moving down it
/// paints each one on the canvas as you go, so picking the right one is
/// looking rather than guessing-and-undoing. Letting go without clicking puts
/// the canvas back exactly as it was.
///
/// The words themselves are `BlendMode.title` and `BlendMode.explanation` in
/// PhotonzCore, beside the list they belong to.
struct BlendModeRow: View {
    @Environment(EditorState.self) private var editorState

    /// Open, and the mode each layer was wearing when it opened. The list
    /// previews as you move down it, so the tick and the way back both have to
    /// come from what was true BEFORE it opened rather than from the canvas.
    @State private var isOpen = false
    @State private var committed = StyleReading<PhotonzCore.BlendMode>(value: .normal,
                                                                       isMixed: false)
    @State private var hovered: PhotonzCore.BlendMode?

    /// The layers this row speaks for: everything picked whose mixing is a
    /// choice somebody has. A highlight mark is not one of them.
    private var selection: LayerStyleSelection {
        editorState.layerStyleSelection.mixable
    }

    /// What the closed button says: the mode on the canvas right now, which
    /// while the list is open is whatever the pointer is resting on.
    private var showing: StyleReading<PhotonzCore.BlendMode> {
        selection.reading { $0.blendMode }
    }

    var body: some View {
        // Nothing to mix, no row. A control that cannot do anything, with a
        // line under it explaining that there is no control, is worse than
        // either on its own — and that is exactly what a highlight got until
        // this guard went in (caught in the probe, 2026-09-12).
        if !selection.isEmpty { rows }
    }

    private var rows: some View {
        let reading = showing
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Blending").font(.caption).foregroundStyle(.secondary)
                if let only = soleLayerID(selection.layerIDs) {
                    InstanceStyleRevert(layerID: only, field: .blendMode)
                }
                Spacer()
            }
            button(reading)
            // The sentence for whatever the row is currently reading, without
            // being asked for. A person who never opens the list still learns
            // what Multiply is doing to their screenshot, and while the list IS
            // open this line follows the pointer down it.
            //
            // Not under Normal, though. Every layer in the document is Normal,
            // so a line there would be two rows of small print on every panel
            // forever, explaining the thing that needs no explaining: painting
            // over. It appears the moment somebody chooses otherwise, which is
            // the moment it means something.
            if !reading.isMixed, let mode = reading.value, mode != .normal {
                Text(mode.explanation)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let note = reachNote {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .playtestField("Blending")
        .panelStartProbe(.row, owner: "Blending")
    }

    /// The closed control. A bordered button wearing the mode's name and a
    /// chevron, so it reads as the pop-ups beside it even though what it opens
    /// is a list with sentences in it.
    private func button(_ reading: StyleReading<PhotonzCore.BlendMode>) -> some View {
        Button {
            committed = editorState.layerStyleSelection.mixable.reading { $0.blendMode }
            hovered = nil
            isOpen = true
        } label: {
            HStack(spacing: 4) {
                let words = reading.isMixed
                    ? LayerStyleSelection.mixedText
                    : (reading.value?.title ?? PhotonzCore.BlendMode.normal.title)
                Text(words)
                    .foregroundStyle(MixedLook.style(reading.isMixed, otherwise: .primary))
                    .panelReadout(words)
                Spacer(minLength: 6)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .controlSize(.small)
        .disabled(selection.isEmpty)
        // The detail carries the value as well as the place, the way the Fill
        // row's switch says "Fill, on": a walk has to be able to CLAIM what
        // the row is reading, and the words here are a SwiftUI Text, which
        // publishes nothing a walk could read off the screen.
        .playtestControl("Blending",
                         detail: reading.isMixed
                            ? LayerStyleSelection.mixedText
                            : (reading.value?.title ?? PhotonzCore.BlendMode.normal.title))
        .panelHelp("How the picked layers mix with what is under them. "
                   + "Opacity says how much of what is below shows through; this says how "
                   + "the two are mixed once it does.")
        .popover(isPresented: $isOpen, arrowEdge: .bottom) { list }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(PhotonzCore.BlendMode.allCases, id: \.self) { mode in
                row(mode)
            }
        }
        .padding(6)
        .frame(width: 288)
        // Whatever closed it — Escape, a click outside, a choice — the canvas
        // must not be left wearing a mode nobody chose.
        .onDisappear {
            hovered = nil
            editorState.cancelLayerStylePreview()
        }
    }

    private func row(_ mode: PhotonzCore.BlendMode) -> some View {
        let isHovered = hovered == mode
        return Button {
            let ids = selection.layerIDs
            editorState.previewLayerStyle(ids: ids) { $0.blendMode = mode }
            editorState.commitLayerStyle(ids: ids)
            committed = StyleReading(value: mode, isMixed: false)
            isOpen = false
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                // The tick says what the layers are SET to, not what the
                // pointer is painting: the preview under your eye is already
                // showing you that.
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.semibold))
                    .opacity(!committed.isMixed && committed.value == mode ? 1 : 0)
                    .frame(width: 11, alignment: .leading)
                VStack(alignment: .leading, spacing: 1) {
                    Text(mode.title).font(.callout)
                    Text(mode.explanation)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: 5)
            .fill(isHovered ? AnyShapeStyle(.selection) : AnyShapeStyle(.clear)))
        // The preview itself. Resting on a row paints it on the canvas and
        // records nothing; leaving the list puts back what was there.
        .onHover { inside in
            if inside {
                hovered = mode
                editorState.previewLayerStyle(ids: selection.layerIDs) { $0.blendMode = mode }
            } else if hovered == mode {
                hovered = nil
                editorState.cancelLayerStylePreview()
            }
        }
        .playtestControl(mode.title, detail: "Blending")
    }

    /// Said only when the row is leaving a picked layer out, which over a
    /// selection means a highlight mark is in it. A row that quietly skipped
    /// one would be a row you could not trust.
    private var reachNote: String? {
        let all = editorState.layerStyleSelection
        let mine = all.mixable
        guard !mine.isEmpty, mine.count < all.count else { return nil }
        let fixed = all.count - mine.count
        return "Blending applies to \(mine.count) of the \(all.count) selected layers. "
            + "The other \(fixed == 1 ? "one is a highlight" : "\(fixed) are highlights"), "
            + "and a highlight always mixes with the words under it."
    }
}

/// Where the row would have been, when every picked layer is a highlight. A
/// row that simply vanished would look like the app had forgotten it, so the
/// section says what happened instead — the way it names the knob that owns a
/// copy's roundness rather than dropping the Corner Radius row in silence.
struct FixedMixingNote: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        let all = editorState.layerStyleSelection
        if !all.isEmpty, all.mixable.isEmpty {
            Text(all.count == 1
                 ? "A highlight always mixes with the words under it, which is what makes it a highlighter, so it has no Blending to set."
                 : "Highlights always mix with the words under them, which is what makes them highlighters, so there is no Blending to set.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .panelStartProbe(.row, owner: "Blending note")
        }
    }
}
