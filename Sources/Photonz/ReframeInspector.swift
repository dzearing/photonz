import PhotonzCore
import SwiftUI

/// **Reframe**: where the camera is pointed on this clip, and where it goes
/// next (`ClipReframe.swift`).
///
/// Two buttons and three readings. The clickthrough draws a Scale field and a
/// Centre field to type into, and typing is the thing this section exists to
/// avoid: you already pointed at the thing on the picture, so the numbers are
/// here to be READ, as a check on what the gesture did.
///
/// The third reading is the clickthrough's own open question answered. It asked
/// whether the canvas should warn when a punch-in passes the source resolution.
/// A budget beats a warning: a screen recording is usually captured at twice
/// the size it is laid out at, most punch-ins never spend that, and "Sharp to
/// 200%" tells you what you have got rather than waiting to tell you off.
struct ReframeInspector: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let reading = editorState.reframeReading {
                readings(reading)
                moves
                Text(editorState.reframeHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .panelReadout(editorState.reframeHint)
                    .playtestField("Reframe hint")
            } else {
                Text("Pick a clip to move the camera on it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: What the frame is doing right now

    @ViewBuilder
    private func readings(_ reading: ReframeReading) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            row("Scale", value: "\(percent(reading.scalePercent))%", field: "Scale reading")
            row("Centre",
                value: "\(whole(reading.centre.x)), \(whole(reading.centre.y))",
                field: "Centre reading")
            if !reading.sharpnessNote.isEmpty {
                Text(reading.sharpnessNote)
                    .font(.caption)
                    .foregroundStyle(reading.isPastNative ? .orange : .secondary)
                    .panelReadout(reading.sharpnessNote)
                    .playtestField("Sharpness reading")
            }
            if !reading.moves {
                Text("It is framed the same way for its whole length.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func row(_ title: String, value: String, field: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11))
            Spacer()
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                // Its own width, never the share a Spacer leaves it: "640, 400"
                // came back "640, 40" with the last character under the panel's
                // edge on the first walk.
                .fixedSize(horizontal: true, vertical: false)
                // Said to a walk as well as to a person, and out of the very
                // same expression, so the two can never drift
                // (`PanelReadoutProbe`).
                .panelReadout(value)
                .playtestField(field)
        }
    }

    private func percent(_ value: Double) -> String {
        String(Int(value.rounded()))
    }

    private func whole(_ value: CGFloat) -> String {
        String(Int(value.rounded()))
    }

    // MARK: The two moves

    private var moves: some View {
        HStack(spacing: 6) {
            Button("Punch In") { editorState.punchInOnRegion() }
                .controlSize(.small)
                .disabled(!editorState.canPunchIn)
                .playtestControl("Punch In", detail: "the Reframe section's push in")
                .panelHelp("Take the camera to the box you drew, arriving by the playhead, "
                           + "and hold it there.")
            Button("Pull Back Out") { editorState.pullReframeBackOut() }
                .controlSize(.small)
                .disabled(!editorState.canPullBackOut)
                .playtestControl("Pull Back Out", detail: "the Reframe section's go wide")
                .panelHelp("Go wide again, setting off from the playhead. "
                           + "Everything before it is the hold.")
            Spacer(minLength: 4)
            Button("Reset") { editorState.resetReframeInHand() }
                .controlSize(.small)
                .disabled(!editorState.canResetReframe)
                .playtestControl("Reset Reframe", detail: "puts the whole frame back")
                .panelHelp("Put the camera back on the whole frame and forget every move on it.")
        }
    }
}
