import PhotonzCore
import SwiftUI

/// **At this cut**: the transitions, as tiles, opened right on the cut you
/// clicked (`video-transition-wt.html`, `#transPick`).
///
/// It already knows what this cut can pay for, so it says the spare along its
/// top and every tile says whether it needs an overlap. A tile the cut cannot
/// afford is dimmed rather than hidden, so Cross dissolve never goes missing
/// without a reason: it says "no spare" instead.
struct TransitionPicker: View {
    @Environment(EditorState.self) private var editorState
    let place: TimelineCutPlace

    /// `#transPick{width:248px}`.
    static let width: CGFloat = 248

    var body: some View {
        let cut = editorState.document?.documentCut(at: place)?.cut
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("At this cut")
                    .font(.system(size: 10, weight: .bold))
                    .kerning(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(VideoKit.Palette.faint)
                Spacer(minLength: 4)
                if let cut {
                    Text(ClipTransitionCopy.spareShort(cut))
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(VideoKit.Palette.faint)
                        .playtestField("Spare at this cut")
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            VideoKit.TileGrid(columns: 2, spacing: 8) {
                ForEach(ClipTransitionKind.allCases, id: \.self) { kind in
                    tile(kind, cut: cut)
                }
            }
            .padding(8)
            .playtestField("At this cut")
        }
        .frame(width: Self.width)
    }

    @ViewBuilder
    private func tile(_ kind: ClipTransitionKind, cut: ClipCut?) -> some View {
        let afford = cut?.canAfford(kind) ?? false
        let isOn = cut?.transition?.kind == kind
        Button {
            editorState.setTransition(kind, at: place)
            editorState.closeTransitionPicker()
        } label: {
            VideoKit.Tile(name: kind.title,
                          detail: afford ? kind.note : "no spare",
                          isSelected: isOn, isDisabled: !afford, emphasis: .cut,
                          thumbnailHeight: 26) {
                VideoKit.AnimatedTransitionThumbnail(style: Self.style(kind))
            }
        }
        .buttonStyle(.plain)
        .disabled(!afford)
        .playtestControl(kind.title, detail: "At this cut")
        .panelHelp(afford ? kind.title : "Not enough spare frames either side of this cut")
    }

    static func style(_ kind: ClipTransitionKind) -> VideoKit.TransitionThumbnail.Style {
        switch kind {
        case .dissolve: .dissolve
        case .dipToBlack: .dipToBlack
        case .dipToWhite: .dipToWhite
        case .push: .push
        case .wipe: .wipe
        case .blurThrough: .blurThrough
        }
    }
}

extension View {
    /// Hangs the transition picker off this view, open while `place` is the
    /// cut whose picker is up.
    func transitionPicker(at place: TimelineCutPlace, fromPanel: Bool = false,
                          editorState: EditorState) -> some View {
        popover(isPresented: Binding(
            get: { editorState.transitionPickerPlace == place && editorState.transitionPickerFromPanel == fromPanel },
            set: { if !$0, editorState.transitionPickerPlace == place { editorState.transitionPickerPlace = nil } }),
                arrowEdge: fromPanel ? .leading : .top) {
            TransitionPicker(place: place)
                .environment(editorState)
        }
    }
}
