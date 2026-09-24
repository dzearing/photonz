import PhotonzCore
import SwiftUI

/// **Sound**: how loud the picked layer is (`docs/design/video-audio.md`,
/// `pages/video-audio.html`), as label and value rows.
///
/// A fader and, once the level changes over time, how many points its line on
/// the bar has, with Flatten beside it. A fade IS the level changing over time,
/// and so is a duck, so both are the line on the bar rather than controls here.
/// Detach Audio is a verb, so it is on the clip's right-click menu.
struct SoundInspector: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if editorState.soundLayerInHand != nil {
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
