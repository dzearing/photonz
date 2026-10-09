import PhotonzCore
import SwiftUI

/// **Audio Effects**: what is put ON the picked sound, as a list you add to
/// (`pages/video-audio.html`, `#gEffects`, and its plus, `#efxMenu`).
///
/// One row per effect, drawn by the same row a layer's Effects list draws
/// (`EffectsListRow`): the chevron and the lit name, the mock's reading at its
/// end ("low cut 80", "3:1", "off"), the switch that stops it and keeps its
/// settings, the cross, a right-click menu, and its settings folding under it.
///
/// The rows read in the order the sound passes through them, noise reduction,
/// then EQ, then compressor (`SoundEffectKind.processingOrder`), and that
/// order is fixed, so the row has no grip. Noise reduction is the very setting
/// Normalize's Clean noise writes (`AudioLevel.noiseReduction`), so a sound
/// Normalize cleaned shows it here.
struct SoundEffectsInspector: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        VStack(alignment: .leading, spacing: EffectsListInspector.paneSpacing) {
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
            .panelHelp("Add an EQ, a compressor or noise reduction with the plus above")
            .panelReadout(Self.nothingYet)
            .playtestField("Audio Effects Empty")
    }
}

/// One effect on the sound: the list's row with a sound effect's reading and
/// settings in it.
private struct SoundEffectRowView: View {
    @Environment(EditorState.self) private var editorState
    let row: SoundEffectRow

    var body: some View {
        let kind = row.kind
        EffectsListRow(
            title: kind.title,
            kindWord: kind == .eq ? "EQ" : kind.title.lowercased(),
            isOn: row.isOn,
            isFolded: editorState.foldedSoundEffects.contains(kind),
            toggleFold: { editorState.toggleSoundEffectFolded(kind) },
            reading: reading,
            switchReading: row.isOn ? "on" : "off",
            switchHelp: "Stops it playing, and keeps its settings",
            setOn: { editorState.setSoundEffectInHand(kind, on: $0) },
            remove: { editorState.removeSoundEffectInHand(kind) },
            headerDrop: EmptyModifier(),
            accessory: { EmptyView() },
            settings: { settings })
    }

    /// The mock's `.emeta`: the row's reading, or how far along the copy that
    /// plays is while it is being made.
    private var reading: String {
        guard row.isOn, row.kind == .noiseReduction,
              let id = editorState.soundLayerInHand?.id,
              let progress = editorState.soundCleaningProgress(of: id) else { return row.reading }
        return "Cleaning \(Int((progress * 100).rounded()))%"
    }

    @ViewBuilder private var settings: some View {
        let level = editorState.soundLevelInHand
        switch row.kind {
        case .noiseReduction:
            strength
        case .eq:
            let eq = level.eq ?? .standard
            SoundEffectSlider(label: "Low cut", value: eq.lowCutHz, range: SoundEQ.lowCutRangeHz, step: 5,
                              spell: { "\(Int($0.rounded())) Hz" }) { new in
                editorState.changeSoundEQInHand { $0.lowCutHz = new }
            }
            SoundEffectSlider(label: "Low", value: eq.lowDB, range: SoundEQ.shelfRangeDB, step: 0.5,
                              spell: SoundEffectSlider.decibels) { new in
                editorState.changeSoundEQInHand { $0.lowDB = new }
            }
            SoundEffectSlider(label: "High", value: eq.highDB, range: SoundEQ.shelfRangeDB, step: 0.5,
                              spell: SoundEffectSlider.decibels) { new in
                editorState.changeSoundEQInHand { $0.highDB = new }
            }
        case .compressor:
            let compressor = level.compressor ?? .standard
            SoundEffectSlider(label: "Threshold", value: compressor.thresholdDB,
                              range: SoundCompressor.thresholdRangeDB, step: 1,
                              spell: { "\(Int($0.rounded())) dB" }) { new in
                editorState.changeSoundCompressorInHand { $0.thresholdDB = new }
            }
            SoundEffectSlider(label: "Ratio", value: compressor.ratio, range: SoundCompressor.ratioRange,
                              step: 0.5, spell: { "\(SoundCompressor.spell($0)):1" }) { new in
                editorState.changeSoundCompressorInHand { $0.ratio = new }
            }
        }
    }

    /// Light, Medium or Strong: how hard the noise is taken out.
    private var strength: some View {
        let reduction = editorState.soundLevelInHand.noiseReduction ?? .standard
        return PanelFieldRow("Strength") {
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

/// One setting of an audio effect: its name, a track, and what it is set to.
///
/// The sound is remade whenever a setting lands, which takes a moment, so a
/// drag lands once, when it is let go: the reading follows the hand the whole
/// way and the sound changes when the hand stops, rather than a copy being
/// started and thrown away on every step of the drag.
private struct SoundEffectSlider: View {
    let label: String
    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    let spell: (Double) -> String
    let land: (Double) -> Void

    /// Where the hand has the track, while it is being dragged.
    @State private var draft: Double?
    @State private var dragging = false

    static func decibels(_ dB: Double) -> String {
        abs(dB) < 0.05 ? "0 dB" : String(format: "%+.1f dB", dB)
    }

    var body: some View {
        let shown = draft ?? value
        PanelFieldRow(label) {
            HStack(spacing: 6) {
                Slider(value: Binding(
                    get: { shown },
                    set: { new in
                        // A press that is not a drag (a click on the track,
                        // a step from the keyboard or a screen reader)
                        // lands at once.
                        // Rounded here rather than given to the slider as a
                        // step: a stepped track draws a tick for every step,
                        // and seventy six of them is a dotted line.
                        let stepped = (new / step).rounded() * step
                        if dragging { draft = stepped } else { land(stepped) }
                    }
                ), in: range) { editing in
                    dragging = editing
                    if !editing, let landed = draft {
                        land(landed)
                        draft = nil
                    }
                }
                .controlSize(.small)
                .frame(minWidth: PanelSliderRow.trackMinimum)
                .playtestField(label)
                Text(spell(shown))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 50, alignment: .trailing)
                    .panelReadout(spell(shown))
                    .playtestField("\(label) reading")
            }
        }
    }
}

/// The plus on the Audio Effects header, the mock's `#efxMenu`: EQ,
/// Compressor and Noise reduction. A row the sound already has is listed and
/// dimmed.
struct AddSoundEffectButton: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        let state = editorState
        let level = state.soundLevelInHand
        return VideoKit.HeaderMenu(
            label: "Add Audio Effect", symbol: "plus", help: "Add an audio effect",
            choices: SoundEffectKind.allCases.map { kind in
                .item(kind.title, isEnabled: level.canAddEffect(kind)) { state.addSoundEffectInHand(kind) }
            })
            .fixedSize()
            .disabled(state.soundLayerInHand == nil)
            .panelHelp("Add an audio effect")
            .playtestControl("Add Audio Effect", detail: "the plus on the Audio Effects header")
    }
}
