import PhotonzCore
import SwiftUI

/// **Channel**: the picked sound's strip, as `pages/video-audio.html` draws
/// `#propBody` (`docs/design/video-audio.md`).
///
/// Mute and Solo under the header, then Volume in decibels; the file the
/// sound came from rides the header beside the title. Mute and Solo are the
/// switches on the sound's own track, the ones on its header in the timeline,
/// so the two places can never disagree. Once the level changes over time, how
/// many points its line on the bar has, with Flatten beside it. The fades have
/// a section of their own under this one, as the mock draws them
/// (`SoundFadesInspector`), and Gain sits under those (`SoundGainInspector`),
/// apart from Volume the way Premiere's Audio Gain is. Detach Audio is a verb,
/// so it is on the clip's right-click menu.
struct SoundInspector: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if editorState.soundLayerInHand != nil {
                switches
                volume
                if editorState.soundLevelInHand.changesOverTime {
                    points
                }
            }
        }
        .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// What the header says beside Channel: the file the sound came from.
    static func headerNote(_ editorState: EditorState) -> String? {
        editorState.soundChannelFileName
    }

    /// The mock's `.btnrow`: Mute lights red, Solo lights in the accent.
    private var switches: some View {
        let track = editorState.soundChannelTrack
        return HStack(spacing: 8) {
            ChannelSwitch(title: "Mute",
                          symbol: track?.isMuted == true ? "speaker.slash.fill" : "speaker.wave.2",
                          isOn: track?.isMuted == true,
                          tint: AnyShapeStyle(VideoKit.Palette.crit),
                          help: "Silence this track.") {
                editorState.toggleSoundChannelMuted()
            }
            ChannelSwitch(title: "Solo", symbol: "headphones",
                          isOn: track?.isSolo == true,
                          tint: AnyShapeStyle(VideoKit.Palette.accent),
                          help: "Hear only this track.") {
                editorState.toggleSoundChannelSolo()
            }
        }
        .disabled(track == nil)
    }

    /// The fader, in the mock's decibels. Muted, it dims and stops taking the
    /// hand, as the mock's does: the level it would play at is kept for when
    /// the track comes back.
    private var volume: some View {
        let level = editorState.soundLevelInHand
        let muted = editorState.soundChannelTrack?.isMuted == true
        return VideoKit.FieldRow(label: "Volume") {
            HStack(spacing: 8) {
                Slider(value: Binding(
                    get: { AudioLevel.volumeSliderDB(forGain: level.gain) },
                    set: { editorState.setSoundVolume(sliderDB: $0) }
                ), in: AudioLevel.volumeRangeDB)
                .controlSize(.small)
                .playtestField("Volume")
                .panelHelp("How loud this layer plays.")
                Text(level.label)
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(VideoKit.Palette.ink)
                    .fixedSize()
                    .panelReadout(level.label)
                    .playtestField("Volume reading")
            }
        }
        .disabled(muted)
        .opacity(muted ? 0.45 : 1)
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

/// **Gain**: boost or cut before the Volume fader, and Normalize, which sets
/// it from the sound's own peaks. Its own section under Fades, where the mock
/// keeps what differs per selection (`#chExtra`), so the Channel strip holds
/// the one Volume row the mock draws. Normalize is on the segment's
/// right-click menu as well.
struct SoundGainInspector: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if editorState.soundLayerInHand != nil {
                gain
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
                    .frame(minWidth: PanelSliderRow.trackMinimum)
                    .playtestField("Gain")
                    .panelHelp("Boost or cut before the volume.")
                    PanelNumberField(
                        showing: .number(Self.spell(dB)),
                        label: "Gain in dB",
                        identity: editorState.soundLayerInHand?.id,
                        suffix: "dB",
                        width: .fixed(40),
                        floor: CGFloat(range.lowerBound),
                        ceiling: CGFloat(range.upperBound),
                        playtest: ("Gain in dB", "Gain"),
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
                .playtestControl("Normalize", detail: "Gain")
                .panelHelp("Bring the loudest peak to -1 dB.")
            }
        }
    }

    /// A gain as the box spells it: one place, signed when it is a boost.
    static func spell(_ dB: Double) -> String {
        abs(dB) < 0.05 ? "0.0" : String(format: "%+.1f", dB)
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

    /// What the section header's question mark says. The mock printed its
    /// first half beside the title; the panel holds labels, not sentences.
    static let headerHelp = "Drag the diamonds on the lane to set a fade, or type it"

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
        return VideoKit.DropdownRow(
            label: "Curve", value: title,
            choices: EasingCurve.named.map { curve in
                .item(curve.title, isOn: curve == current, image: CurveMenuImage.image(for: curve)) {
                    editorState.setSoundFadeCurve(curve)
                }
            } + [.divider, .item("Draw a curve...") { isDrawing = true }])
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

/// One of the Channel's two switches, the mock's `.btn.sm`: quiet (`ghost`)
/// until pressed, then filled in its colour, red for Mute (`danger`) and the
/// accent for Solo (`primary`), and filled for as long as it is on.
private struct ChannelSwitch: View {
    let title: String
    let symbol: String
    let isOn: Bool
    let tint: AnyShapeStyle
    let help: String
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 13, height: 13)
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 12)
            .frame(height: 24)
            .background { Capsule().fill(fill) }
            .overlay {
                Capsule().strokeBorder(!isOn && hovering ? AnyShapeStyle(VideoKit.Palette.edgeLo)
                                                         : AnyShapeStyle(Color.clear))
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.42)
        .playtestHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isOn)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .panelHelp(help)
        .playtestControl(title, detail: "Channel")
        .panelReadout(isOn ? "On" : "Off")
        .playtestField(title)
    }

    private var ink: AnyShapeStyle {
        if isOn { return AnyShapeStyle(Color.white) }
        return hovering ? AnyShapeStyle(VideoKit.Palette.ink) : AnyShapeStyle(VideoKit.Palette.dim)
    }

    private var fill: AnyShapeStyle {
        if isOn { return tint }
        return hovering ? AnyShapeStyle(VideoKit.Palette.glassThin) : AnyShapeStyle(Color.clear)
    }
}
