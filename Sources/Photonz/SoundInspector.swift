import PhotonzCore
import SwiftUI

/// **Sound**: how loud the picked layer is, and what shapes it
/// (`docs/design/video-audio.md`).
///
/// Three rows and no more. The mock draws a channel strip with mute, solo,
/// volume, a fade in, a fade out and a curve picker, and most of that is the
/// same idea said several times: a fade IS the level changing over time, and so
/// is a duck, so this section has a fader and the bar has a line, and there is
/// no fade control and no curve menu to keep in step with either.
///
/// Mute is absent for the same reason: a level pulled all the way down reads
/// Silent and nothing is heard, so a second control that also means silent
/// would be two switches for one fact.
struct SoundInspector: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let layer = editorState.soundLayerInHand {
                level
                if editorState.soundLevelInHand.changesOverTime {
                    overTime
                }
                if layer.isClip {
                    detach
                } else {
                    Text("Drag its bar on the timeline to move it. Cut it with B, like anything else.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Nothing picked makes a sound.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: The fader

    private var level: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Level")
                    .font(.system(size: 11))
                Spacer()
                Text(editorState.soundLevelInHand.label)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .playtestField("Level reading")
            }
            Slider(value: Binding(
                get: { editorState.soundLevelInHand.gain },
                set: { editorState.setSoundGain($0) }
            ), in: 0...AudioLevel.loudestGain)
            .controlSize(.small)
            .playtestField("Level")
            .panelHelp("How loud this layer plays. It carries the whole shape of the level with it.")
        }
    }

    // MARK: What the line on the bar is doing

    private var overTime: some View {
        HStack(spacing: 8) {
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 4)
            Button("Flatten") { editorState.clearSoundLevelPoints() }
                .controlSize(.small)
                .playtestField("Flatten Level")
                .panelHelp("Take every point off the level line and leave the fader where it is.")
        }
    }

    private var summary: String {
        let points = editorState.soundLevelInHand.points.count
        return points == 1
            ? "The level is pinned at one moment, on its bar in the timeline"
            : "The level changes at \(points) moments, on its bar in the timeline"
    }

    // MARK: Taking the sound off the picture

    private var detach: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("This clip's sound is still on its picture, so a cut to one is a cut to both.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Detach Sound") { editorState.detachSound() }
                .controlSize(.small)
                .disabled(!editorState.canDetachSound)
                .playtestField("Detach Sound")
                .panelHelp("Put this clip's sound on a layer of its own, in step and with the same cuts.")
        }
    }
}
