import PhotonzCore
import SwiftUI

/// **Captions**: have the app write the words off the sound, and fix what it
/// got wrong (`Captions.swift`).
///
/// Four controls and one line of words. That is deliberately less than the
/// clickthrough draws: it has a language picker, a safe-area switch, a cue
/// counter, a style picker and a karaoke mode. Every one of those is a question
/// asked before anybody has a reason to answer it, and a panel of questions is
/// the thing that makes captioning feel like a mode. What is here is the one
/// button that does the work, the honest reading of what came back, the two
/// nudges that fix a track that ran late, and the way out.
///
/// The controls that are NOT here are not missing: a caption is a text layer,
/// so its font, colour, weight and shadow are the Text and Effects sections
/// that are already open above this one, and when it is on screen is the Time
/// section, the same one a title uses. Repeating any of them here would be a
/// second place to change one thing.
struct CaptionsInspector: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            reading
            if editorState.isWritingCaptions {
                listening
            } else {
                write
            }
            if editorState.hasCaptions && !editorState.isWritingCaptions {
                timing
                ways
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: What came back

    private var reading: some View {
        Text(editorState.captionsReading)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
            .playtestField("Captions reading")
    }

    // MARK: Doing the work

    private var write: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(editorState.hasCaptions ? "Write Captions Again" : "Write Captions") {
                editorState.writeCaptions()
            }
            .controlSize(.small)
            .disabled(!editorState.canWriteCaptions)
            .playtestField("Write Captions")
            .panelHelp("Listen to this recording on this Mac and put the words on the "
                       + "timeline at the moments they were said. Nothing is uploaded.")
            if !editorState.hasCaptions {
                Text("Each line lands as a text layer with an in and an out, so correcting one "
                     + "is typing and restyling one is the Text section.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// While it listens: how far along, and a way out that keeps the words.
    private var listening: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: editorState.captionsBeingWritten?.share ?? 0)
                .controlSize(.small)
                .playtestField("Captions progress")
            Button("Stop") { editorState.stopWritingCaptions() }
                .controlSize(.small)
                .playtestField("Stop Writing Captions")
                .panelHelp("Stop listening and keep every word it has already heard.")
        }
    }

    // MARK: Fixing what it got wrong

    /// The whole track, earlier or later.
    ///
    /// The other half of fixing timing is dragging one caption's bar end on the
    /// timeline, which needs no control here. This is the half a bar end cannot
    /// do: a recogniser that runs a tenth of a second late runs late
    /// everywhere, and correcting that four hundred times is not correcting it.
    private var timing: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Timing")
                .font(.system(size: 11))
            HStack(spacing: 6) {
                Button {
                    editorState.nudgeCaptions(byMS: -EditorState.captionNudgeMS)
                } label: {
                    Label("Earlier", systemImage: "arrow.left")
                }
                .controlSize(.small)
                .disabled(!editorState.canNudgeCaptions)
                .playtestField("Captions Earlier")
                .panelHelp("Move every caption a tenth of a second earlier.")
                Button {
                    editorState.nudgeCaptions(byMS: EditorState.captionNudgeMS)
                } label: {
                    Label("Later", systemImage: "arrow.right")
                }
                .controlSize(.small)
                .disabled(!editorState.canNudgeCaptions)
                .playtestField("Captions Later")
                .panelHelp("Move every caption a tenth of a second later.")
            }
            Text("One line out of step: drag either end of its bar on the timeline.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: The ways out

    private var ways: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Button("Export Captions…") { editorState.exportCaptions() }
                    .controlSize(.small)
                    .disabled(!editorState.canExportCaptions)
                    .playtestField("Export Captions")
                    .panelHelp("Write the same words out as a subtitle file, for anything that "
                               + "would rather switch them off than have them in the picture.")
                Spacer(minLength: 0)
                Button("Clear") { editorState.clearCaptions() }
                    .controlSize(.small)
                    .disabled(!editorState.canClearCaptions)
                    .playtestField("Clear Captions")
                    .panelHelp("Take every caption off, leaving everything else where it is.")
            }
            Text("They are ordinary layers, so they are already in the film you export.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
