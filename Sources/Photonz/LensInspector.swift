import PhotonzCore
import SwiftUI

extension LensAdjustment {
    /// The slider's range as Doubles. Precomputed rather than built inline:
    /// converting both ends inside a `Slider(in:)` blows the type checker up.
    var sliderRange: ClosedRange<Double> {
        Double(range.lowerBound)...Double(range.upperBound)
    }
}

/// A picked lens's own two settings: what it does to the picture underneath it,
/// and how hard it does it (Next, `next-lens`).
///
/// Nothing else about a lens is here. Its corner radius, its border, its shadow
/// and its opacity are the LAYER's, so they stay in Appearance and Effects with
/// every other layer's: one home each, and no copy down here to wonder about.
/// That is also why this is not a second Effects list — an effect acts on the
/// layer's own pixels, and a lens has none of its own.
struct LensInspector: View {
    @Environment(EditorState.self) private var editorState
    let layer: Layer

    private var lens: LensContent {
        editorState.document?.layer(id: layer.id)?.lens ?? LensContent()
    }

    /// Live through a slider pull, so the thumb does not snap back mid-drag.
    private var amount: CGFloat {
        editorState.selectedLensAmount ?? lens.amount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Does").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Picker("Does", selection: Binding(
                    get: { lens.adjustment },
                    set: { editorState.setLensAdjustment($0) })) {
                    ForEach(LensAdjustment.allCases, id: \.self) { adjustment in
                        Text(adjustment.title).tag(adjustment)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
                .panelHelp("What this layer does to the picture underneath it. "
                           + LensCopy.safety)
            }
            // Invert is the one adjustment with nothing to set, so it gets no
            // slider rather than a dead one.
            if let title = lens.adjustment.settingTitle {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(title).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(lens.adjustment.label(amount))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    // A pull previews through the regular render path and
                    // commits one undo step on release, so a drag is one step
                    // to undo rather than forty.
                    Slider(value: Binding(
                        get: { Double(amount) },
                        set: { editorState.previewLensAmount(CGFloat($0)) }),
                           in: lens.adjustment.sliderRange) { editing in
                        if !editing { editorState.commitLensAmount() }
                    }
                    .controlSize(.small)
                    .panelHelp(help(for: lens.adjustment))
                }
            }
        }
        .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
        .padding(.vertical, 8)
        .id(layer.id)
    }

    private func help(for adjustment: LensAdjustment) -> String {
        switch adjustment {
        case .blur:
            return "How far the picture underneath is smeared. Past about twenty points nothing under it can be read."
        case .pixelate:
            return "How big one block is. Bigger blocks give less away."
        case .greyscale:
            return "How much of the colour is drained out. All the way is black and white."
        case .invert:
            return ""
        case .brightness:
            return "Lifts the picture underneath towards white, or pushes it towards black."
        }
    }
}

/// The Lens tool's own settings in the right hand panel, beside the other
/// tool-in-hand sections: what the NEXT lens you draw will do.
struct LensToolInspector: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        @Bindable var state = editorState
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Does").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Picker("Does", selection: $state.lensToolAdjustment) {
                    ForEach(LensAdjustment.allCases, id: \.self) { adjustment in
                        Text(adjustment.title).tag(adjustment)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
                .panelHelp("What the next lens you draw does to the picture underneath it. "
                           + "A lens already on the canvas is switched in its own section.")
            }
            if let title = editorState.lensToolAdjustment.settingTitle {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(title).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(editorState.lensToolAdjustment.label(editorState.lensToolAmount))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(get: { Double(editorState.lensToolAmount) },
                                          set: { editorState.lensToolAmount = CGFloat($0) }),
                           in: editorState.lensToolAdjustment.sliderRange)
                        .controlSize(.small)
                }
            }
            Text(LensCopy.safety)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
        .padding(.vertical, 8)
        // The memory lives in UserDefaults, which nothing observes, so the
        // section is redrawn by the counter the setters bump.
        .id(editorState.lensToolRevision)
    }
}
