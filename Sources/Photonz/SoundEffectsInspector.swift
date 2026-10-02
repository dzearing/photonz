import PhotonzCore
import SwiftUI

/// **Audio Effects**: what is put ON the picked sound, as a list you add to
/// (`pages/video-audio.html`, `#gEffects`, and its plus, `#efxMenu`).
///
/// One row per effect, the mock's `.efx`: the name, the value at its end, and
/// the cross that takes it off, with its settings under it behind the same
/// rule the layer's own Effects list hangs from its rows (`OwnedSettings`).
///
/// Noise reduction is the row there is today. It is the very setting
/// Normalize's Clean noise writes (`AudioLevel.noiseReduction`), so a sound
/// Normalize cleaned shows it here, and taking it off here is the segment's
/// Remove Noise Cleaning. EQ and Compressor are on the plus's menu, as the
/// mock draws it, with no sound behind them yet (`SoundEffectKind.isBuilt`).
struct SoundEffectsInspector: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if editorState.soundLayerInHand != nil {
                let rows = editorState.soundLevelInHand.effectRows
                if rows.isEmpty {
                    empty
                } else {
                    ForEach(rows) { row in
                        SoundEffectRowView(row: row)
                    }
                }
            }
        }
        .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A sound with nothing on it: one label, with where the plus is in its tip.
    private static let nothingYet = "No effects"

    private var empty: some View {
        Text(Self.nothingYet)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .panelHelp("Add noise reduction with the plus above")
            .panelReadout(Self.nothingYet)
            .playtestField("Audio Effects Empty")
    }
}

/// One effect on the sound: its name lit, its reading, the cross, and its
/// settings under it.
private struct SoundEffectRowView: View {
    @Environment(EditorState.self) private var editorState
    let row: SoundEffectRow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: ColorPartLayout.spacing) {
                Text(row.kind.title)
                    .font(PanelSectionLook.EffectRow.titleFont)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(reading)
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(VideoKit.Palette.faint)
                    .lineLimit(1)
                    .fixedSize()
                    .panelReadout(reading)
                    .playtestField("\(row.kind.title) reading")
                removeButton
            }
            .frame(minHeight: ColorPartLayout.rowHeight)
            OwnedSettings(owner: row.kind.title) { settings }
        }
        .playtestField(row.kind.title)
        .contextMenu {
            Button("Remove \(row.kind.title)") { editorState.removeSoundEffectInHand(row.kind) }
        }
    }

    /// The mock's `.emeta`: the strength, or how far along the cleaned sound
    /// is while it is being made.
    private var reading: String {
        guard row.kind == .noiseReduction,
              let id = editorState.soundLayerInHand?.id,
              let progress = editorState.soundCleaningProgress(of: id) else { return row.reading }
        return "Cleaning \(Int((progress * 100).rounded()))%"
    }

    private var removeButton: some View {
        Button {
            editorState.removeSoundEffectInHand(row.kind)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .semibold))
                .frame(width: 14, height: ColorPartLayout.rowHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .panelHelp("Remove \(row.kind.title.lowercased())")
        .accessibilityLabel("Remove \(row.kind.title)")
        .playtestControl("Remove \(row.kind.title)", detail: "Audio Effects")
    }

    @ViewBuilder private var settings: some View {
        switch row.kind {
        case .noiseReduction:
            strength
        case .eq, .compressor:
            EmptyView()
        }
    }

    /// Light, Medium or Strong: how hard the noise is taken out.
    private var strength: some View {
        let reduction = editorState.soundLevelInHand.noiseReduction ?? .standard
        return HStack(spacing: 8) {
            Text("Strength")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 8)
            SegmentedControl("Strength", selection: reduction,
                             options: NoiseReduction.allCases.map { .init($0, $0.title) },
                             size: .small, form: .natural) {
                editorState.setSoundNoiseReductionInHand($0)
            }
            .fixedSize()
            .panelHelp("How much noise to take out")
        }
    }
}

/// The plus on the Audio Effects header, the mock's `#efxMenu`: EQ,
/// Compressor and Noise reduction. A row the sound already has, or one with no
/// sound behind it yet, is listed and dimmed.
struct AddSoundEffectButton: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        Menu {
            ForEach(SoundEffectKind.allCases) { kind in
                Button(kind.title) { editorState.addSoundEffectInHand(kind) }
                    .disabled(!editorState.soundLevelInHand.canAddEffect(kind))
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(editorState.soundLayerInHand == nil)
        .accessibilityLabel("Add Audio Effect")
        .panelHelp("Add an audio effect")
        .playtestControl("Add Audio Effect", detail: "the plus on the Audio Effects header")
    }
}
