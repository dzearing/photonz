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

    /// The Does dropdown's hover tip, on the AppKit button and in the panel's
    /// register where a walk reads it.
    static let help = "What this layer does to the picture underneath it. " + LensCopy.safety

    private var lens: LensContent {
        editorState.document?.layer(id: layer.id)?.lens ?? LensContent()
    }

    /// What this layer is one of the six: an adjustment, or Magnify. A
    /// magnifier is a zoom callout under the hood, which is why this is asked
    /// of the layer rather than read off `lens`.
    private var kind: LensKind {
        editorState.document?.layer(id: layer.id)?.lensKind ?? LensKind(lens.adjustment)
    }

    /// Live through a slider pull, so the thumb does not snap back mid-drag.
    private var amount: CGFloat {
        editorState.selectedLensAmount ?? lens.amount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Does").font(.caption).foregroundStyle(.secondary)
                // The panel's dropdown, filling the rest of the row the way
                // Font does in the Text section.
                VideoKit.Dropdown(
                    label: "Does",
                    value: kind.title,
                    help: Self.help,
                    choices: .picking(LensKind.allCases, current: kind,
                                      title: \.title) { editorState.setLensKind($0) })
                    .frame(maxWidth: .infinity)
                    .panelHelp(Self.help)
                    .playtestControl("Does", detail: kind.title)
            }
            .playtestField("Does")
            // Magnify's picture comes from somewhere else on the canvas, so it
            // has a magnification and a shape where the other five have one
            // number. Same two rows a callout has always had.
            if kind.magnifies {
                MagnifierSettingsRows(layer: layer)
            } else if let title = lens.adjustment.settingTitle {
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

    static let help = "What the next lens you draw does to the picture underneath it. "
        + "A lens already on the canvas is switched in its own section. " + LensCopy.safety

    var body: some View {
        @Bindable var state = editorState
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Does").font(.caption).foregroundStyle(.secondary)
                VideoKit.Dropdown(
                    label: "Does",
                    value: editorState.lensToolKind.title,
                    help: Self.help,
                    choices: .picking(LensKind.allCases, current: editorState.lensToolKind,
                                      title: \.title) { state.lensToolKind = $0 })
                    .frame(maxWidth: .infinity)
                    .panelHelp(Self.help)
                    .playtestControl("Does", detail: editorState.lensToolKind.title)
            }
            .playtestField("Does")
            if editorState.lensToolKind.magnifies {
                MagnifierToolSettingsRows()
            } else if let title = editorState.lensToolAdjustment.settingTitle {
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
            // One line, because covering an address is the one thing here that
            // is worth being sure about. The rest of it, that the saved
            // document still holds the original, is on the Does picker's tip.
            // Magnify hides nothing, so it is not told this: a reassurance
            // about the wrong thing is one more sentence to read past.
            if !editorState.lensToolKind.magnifies {
                Text(LensCopy.safetyCaption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
        .padding(.vertical, 8)
        // The memory lives in UserDefaults, which nothing observes, so the
        // section is redrawn by the counter the setters bump.
        .id(editorState.lensToolRevision)
    }
}
