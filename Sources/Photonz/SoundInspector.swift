import PhotonzCore
import SwiftUI

/// **Sound**: how loud the picked layer is (`docs/design/video-audio.md`,
/// `pages/video-audio.html`), as label and value rows.
///
/// A fader and, once the level changes over time, how many points its line on
/// the bar has, with Flatten beside it. The fades have a section of their own
/// under this one, as the mock draws them (`SoundFadesInspector`). Detach
/// Audio is a verb, so it is on the clip's right-click menu.
struct SoundInspector: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if editorState.soundLayerInHand != nil {
                gain
                level
                if editorState.soundLevelInHand.changesOverTime {
                    points
                }
            }
        }
        .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Gain, before the fader: dragged on the slider, typed in the box, or
    /// set by Normalize beside it, the way Premiere's Audio Gain sits apart
    /// from its Volume.
    private var gain: some View {
        let dB = editorState.soundLevelInHand.clipGainDB
        let range = AudioLevel.clipGainRangeDB
        return VStack(alignment: .leading, spacing: 4) {
            VideoKit.FieldRow(label: "Gain") {
                HStack(spacing: 6) {
                    Slider(value: Binding(
                        get: { dB },
                        // Whole decibels while dragging: finer than that is
                        // what the box is for.
                        set: { editorState.setSoundClipGain($0.rounded()) }
                    ), in: range)
                    .controlSize(.small)
                    .frame(minWidth: 60)
                    .playtestField("Gain")
                    .panelHelp("Boost or cut before the level.")
                    PanelNumberField(
                        showing: .number(Self.spell(dB)),
                        label: "Gain in dB",
                        identity: editorState.soundLayerInHand?.id,
                        suffix: "dB",
                        width: .fixed(40),
                        floor: CGFloat(range.lowerBound),
                        ceiling: CGFloat(range.upperBound),
                        playtest: ("Gain in dB", "Sound"),
                        spell: { Self.spell(Double($0)) },
                        land: { typed in
                            editorState.setSoundClipGain(Double(typed))
                            return .number(Self.spell(editorState.soundLevelInHand.clipGainDB))
                        })
                    .panelReadout(editorState.soundLevelInHand.clipGainField)
                }
            }
            // Under the box it sets, in the control column.
            VideoKit.FieldRow(label: "") {
                Button("Normalize") {
                    guard let id = editorState.soundLayerInHand?.id else { return }
                    let ids = editorState.soundLayers(actingOn: id)
                    Task { await editorState.normalizeSound(layers: ids) }
                }
                .controlSize(.small)
                .playtestControl("Normalize", detail: "Sound")
                .panelHelp("Bring the loudest peak to -1 dB.")
            }
        }
    }

    /// A gain as the box spells it: one place, signed when it is a boost.
    static func spell(_ dB: Double) -> String {
        abs(dB) < 0.05 ? "0.0" : String(format: "%+.1f", dB)
    }

    private var level: some View {
        VideoKit.FieldRow(label: "Level") {
            HStack(spacing: 8) {
                Slider(value: Binding(
                    get: { editorState.soundLevelInHand.gain },
                    set: { editorState.setSoundGain($0) }
                ), in: 0...AudioLevel.loudestGain)
                .controlSize(.small)
                .playtestField("Level")
                .panelHelp("How loud this layer plays.")
                Text(editorState.soundLevelInHand.label)
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(VideoKit.Palette.ink)
                    .fixedSize()
                    .panelReadout(editorState.soundLevelInHand.label)
                    .playtestField("Level reading")
            }
        }
    }

    /// The level's line on the bar, counted, and the way to take it off.
    private var points: some View {
        let count = editorState.soundLevelInHand.points.count
        return VideoKit.FieldRow(label: "Points") {
            HStack(spacing: 6) {
                VideoKit.ValueFace(value: "\(count) on the bar")
                    .panelReadout("\(count) on the bar")
                Button("Flatten") { editorState.clearSoundLevelPoints() }
                    .controlSize(.small)
                    .playtestField("Flatten Level")
                    .panelHelp("Take every point off the level line.")
            }
        }
    }
}

/// **Fades**: how long the picked sound takes to rise out of silence and to
/// fall back into it, and the curve both follow (`pages/video-audio.html`,
/// `#propBody`, the Fades section).
///
/// Two boxes, In and Out, the way the mock draws them, and each one takes a
/// typed number of seconds as well as reading back what the handles at the
/// corners of the bar set. The curve is the one list every timed thing in the
/// app picks from, each shape drawn beside its name. Underneath it is still
/// the level line: a fade is two points on it (`AudioLevel.setFadeIn`).
struct SoundFadesInspector: View {
    @Environment(EditorState.self) private var editorState
    @State private var isDrawing = false

    /// The section header's muted note, as the mock words it.
    static let headerNote = "drag the diamonds on the lane"

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let layer = editorState.soundLayerInHand {
                let fades = editorState.soundFadesInHand
                HStack(spacing: 7) {
                    SoundFadeField(key: "In", label: "Fade in", ms: fades.inMS, identity: layer.id) {
                        editorState.setSoundFadeInHand(fadeIn: true, ms: $0)
                    }
                    SoundFadeField(key: "Out", label: "Fade out", ms: fades.outMS, identity: layer.id) {
                        editorState.setSoundFadeInHand(fadeIn: false, ms: $0)
                    }
                }
                curve
            }
        }
        .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var curve: some View {
        let current = editorState.soundLevelInHand.fadeCurve
        let title = current.isDrawn ? "Drawn" : current.title
        return VideoKit.DropdownRow(label: "Curve", value: title) {
            ForEach(Array(EasingCurve.named.enumerated()), id: \.offset) { _, curve in
                Toggle(isOn: Binding(
                    get: { curve == current },
                    set: { _ in editorState.setSoundFadeCurve(curve) })) {
                    Label { Text(curve.title) } icon: { CurveThumbnail(curve: curve, side: 14) }
                }
            }
            Divider()
            Button("Draw a curve...") { isDrawing = true }
        }
        .panelReadout(title)
        .panelHelp("How the fades rise and fall.")
        .playtestField("Curve")
        .popover(isPresented: $isDrawing, arrowEdge: .bottom) {
            CurveEditor(curve: current) { editorState.setSoundFadeCurve($0) }
        }
    }
}

/// One `.field` of the mock that you can also type into: a small key on the
/// left and the length on the right, in a box. Return, Tab or clicking away
/// lands what was typed; Escape puts it back.
private struct SoundFadeField: View {
    let key: String
    /// The box's own name, so a walk can put the keyboard in "Fade in".
    let label: String
    let ms: Int
    /// A different sound is a different number, so the draft starts over.
    let identity: UUID
    /// Lands a length and hands back the one the sound really took.
    let land: (Int) -> Int

    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(key)
                .font(.system(size: 10))
                .foregroundStyle(VideoKit.Palette.faint)
                .lineLimit(1)
                .layoutPriority(1)
            TextField(label, text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5, weight: .medium))
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .foregroundStyle(VideoKit.Palette.ink)
                .focused($isFocused)
                .accessibilityLabel(label)
                .onSubmit { commit() }
                .numberFieldKeys(commit: { commit() },
                                 revert: { draft = AudioLevel.fadeLabel(ms: ms) },
                                 step: { direction, coarse in
                                     reach(max(0, ms + direction * (coarse ? 1000 : 100)))
                                 })
                .onAppear { draft = AudioLevel.fadeLabel(ms: ms) }
                // What was taken, which a handle on the bar may change too.
                .onChange(of: ms) { draft = AudioLevel.fadeLabel(ms: ms) }
                .onChange(of: identity) { draft = AudioLevel.fadeLabel(ms: ms) }
                .onChange(of: isFocused) { _, focused in if !focused { commit() } }
                .panelReadout(AudioLevel.fadeLabel(ms: ms))
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 7).fill(VideoKit.Palette.panel))
        .overlay(RoundedRectangle(cornerRadius: 7)
            .strokeBorder(isFocused ? AnyShapeStyle(VideoKit.Palette.accent.opacity(0.6))
                                    : AnyShapeStyle(VideoKit.Palette.line)))
        .contentShape(RoundedRectangle(cornerRadius: 7))
        .onTapGesture { isFocused = true }
        .panelHelp(key == "In" ? "Seconds to rise out of silence." : "Seconds to fall into silence.")
        .playtestField(label)
    }

    /// Lands what was typed. Anything that is not a number puts the length
    /// back; a length the sound cannot hold is cut to what it can, and the
    /// box then shows what was taken.
    private func commit() {
        guard let typed = AudioLevel.fadeMS(typed: draft) else {
            draft = AudioLevel.fadeLabel(ms: ms)
            return
        }
        reach(typed)
    }

    private func reach(_ typed: Int) {
        draft = AudioLevel.fadeLabel(ms: typed == ms ? ms : land(typed))
    }
}
