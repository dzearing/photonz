import PhotonzCore
import SwiftUI

// The cut in the panel (`video-transition-wt.html`, `#propsCut`): two
// sections, Edit point and Transition, made of short labels and values. A cut
// is not a layer, so this is the one place it speaks for itself, including
// what it can afford.

/// **Edit point**: which clip goes out, which comes in, and the spare media
/// either side, the frames an overlap would be paid for with.
struct EditPointInspector: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        if let cut = editorState.cutInHand {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    CutField(key: "Out", value: cut.outgoingName)
                    CutField(key: "In", value: cut.incomingName)
                }
                HStack(spacing: 7) {
                    CutField(key: "Spare after", value: spare(cut.cut.spareAfterOutMS))
                    CutField(key: "Spare before", value: spare(cut.cut.spareBeforeInMS))
                }
            }
            .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func spare(_ ms: Int?) -> String {
        ms.map(ClipTransitionCopy.seconds) ?? "any"
    }

    /// What the section's header says on its right: where the cut is on the
    /// document's clock, the number the ruler and the transport show.
    static func headerNote(_ editorState: EditorState) -> String? {
        editorState.cutInHand.map { "at \(CaptionProgress.clock($0.atMS))" }
    }
}

/// One `.field` of the mock: a small key on the left and its value on the
/// right, in a box.
private struct CutField: View {
    let key: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Text(key)
                .font(.system(size: 10))
                .foregroundStyle(VideoKit.Palette.faint)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 11.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(VideoKit.Palette.ink)
                .lineLimit(1)
                .truncationMode(.middle)
                .panelReadout(value)
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 7).fill(VideoKit.Palette.panel))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(VideoKit.Palette.line))
        .accessibilityElement(children: .combine)
        .playtestField(key)
    }
}

/// **Transition**: what is on the cut in hand. Nothing yet is one button that
/// opens the tiles; something is a Type and a Length, and for the kinds that
/// overlap, what it is paid with.
struct TransitionInspector: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        if let inHand = editorState.cutInHand {
            VStack(alignment: .leading, spacing: 7) {
                if let transition = inHand.cut.transition {
                    type(inHand, current: transition.kind)
                    length(inHand)
                    if transition.kind.needsOverlap, inHand.cut.drawnTransition != nil {
                        VideoKit.FieldRow(label: "Paid with") {
                            VideoKit.ValueFace(value: ClipTransitionCopy.paidWith(inHand.cut))
                                .panelReadout(ClipTransitionCopy.paidWith(inHand.cut))
                        }
                        .playtestField("Paid with")
                    }
                } else {
                    VideoKit.FieldRow(label: "At the cut") {
                        Button {
                            editorState.openTransitionPicker(at: inHand.place, fromPanel: true)
                        } label: {
                            Label("Add transition", systemImage: "rectangle.righthalf.inset.filled.arrow.right")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .controlSize(.small)
                        .playtestControl("Add transition", detail: "Transition")
                        .transitionPicker(at: inHand.place, fromPanel: true, editorState: editorState)
                    }
                    .playtestField("At the cut")
                }
                if let warning = warning(inHand.cut) {
                    Text(warning)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .playtestField("Transition warning")
                }
            }
            .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The one hint this section ever shows, and only when something is off:
    /// a later trim took the spare a transition was spending, or both sides
    /// read the same frames so a dissolve would show nothing.
    private func warning(_ cut: ClipCut) -> String? {
        if cut.transition != nil, cut.drawnTransition == nil {
            return "No spare left here, so this cut plays hard."
        }
        if let drawn = cut.drawnTransition, let asked = cut.transition, drawn.lengthMS < asked.lengthMS {
            let now = ClipTransitionCopy.seconds(drawn.lengthMS)
            return "Playing at \(now): a trim took its spare."
        }
        if cut.isContinuous, cut.transition?.kind.needsOverlap ?? false {
            return "Both sides are the same frames, so this shows nothing."
        }
        return nil
    }

    private func type(_ inHand: DocumentCut, current: ClipTransitionKind) -> some View {
        VideoKit.DropdownRow(label: "Type", value: current.title) {
            ForEach(ClipTransitionKind.allCases, id: \.self) { kind in
                Toggle(kind.title, isOn: Binding(
                    get: { kind == current },
                    set: { _ in editorState.setTransition(kind, at: inHand.place) }))
                    .disabled(!inHand.cut.canAfford(kind))
            }
            Divider()
            Button("Hard cut") { editorState.setTransition(nil, at: inHand.place) }
        }
        .playtestField("Type")
    }

    private func length(_ inHand: DocumentCut) -> some View {
        let now = inHand.cut.drawnTransition?.lengthMS ?? 0
        return VideoKit.DropdownRow(label: "Length", value: ClipTransitionCopy.seconds(now)) {
            ForEach(editorState.clipTransitionLengthOffers, id: \.self) { ms in
                Toggle(ClipTransitionCopy.seconds(ms), isOn: Binding(
                    get: { ms == now },
                    set: { _ in editorState.setClipTransitionLength(ms) }))
            }
        }
        .playtestField("Length")
    }

    /// What the section's header says on its right: the kind on the cut, or
    /// None.
    static func headerNote(_ editorState: EditorState) -> String? {
        guard let inHand = editorState.cutInHand else { return nil }
        return inHand.cut.drawnTransition?.kind.title ?? "None"
    }
}
