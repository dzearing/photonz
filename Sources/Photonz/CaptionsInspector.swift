import PhotonzCore
import SwiftUI

/// **Captions**: have the app write the words off the sound, and fix what it
/// got wrong (`Captions.swift`, `pages/video-captions.html`), as label and
/// value rows.
///
/// How many captions there are, the button that writes them (or the progress
/// while it listens), the nudge that fixes a whole track that ran late, and the
/// way out. A caption is a text layer, so its look is the Text section and when
/// it is on screen is its bar on the timeline.
struct CaptionsInspector: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if editorState.isWritingCaptions {
                listening
            } else {
                captions
            }
            if editorState.hasCaptions && !editorState.isWritingCaptions {
                timing
                file
            }
        }
        .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// How many there are, in two words, and the long answer on hover.
    private var count: String {
        guard editorState.hasCaptions else { return "None" }
        let cues = editorState.document?.captionCues ?? []
        let unsure = cues.filter(\.isUncertain).count
        let said = "\(cues.count) caption\(cues.count == 1 ? "" : "s")"
        return unsure > 0 ? "\(said), \(unsure) unsure" : said
    }

    private var captions: some View {
        VideoKit.FieldRow(label: "Captions") {
            HStack(spacing: 6) {
                VideoKit.ValueFace(value: count)
                    .panelReadout(count)
                    .playtestField("Captions reading")
                    .panelHelp(editorState.captionsReading)
                Button(editorState.hasCaptions ? "Write Again" : "Write") {
                    editorState.writeCaptions()
                }
                .controlSize(.small)
                .disabled(!editorState.canWriteCaptions)
                .playtestField("Write Captions")
                .panelHelp("Listen on this Mac, never uploaded, and write the words.")
            }
        }
    }

    /// While it listens: how far along, and a way out that keeps the words.
    private var listening: some View {
        VideoKit.FieldRow(label: "Listening") {
            HStack(spacing: 6) {
                ProgressView(value: editorState.captionsBeingWritten?.share ?? 0)
                    .controlSize(.small)
                    .playtestField("Captions progress")
                    .panelHelp(editorState.captionsReading)
                Button("Stop") { editorState.stopWritingCaptions() }
                    .controlSize(.small)
                    .playtestField("Stop Writing Captions")
                    .panelHelp("Stop, and keep every word heard so far.")
            }
        }
    }

    /// The whole track, earlier or later. One caption out of step is its bar's
    /// end, dragged on the timeline.
    private var timing: some View {
        VideoKit.FieldRow(label: "Timing") {
            HStack(spacing: 6) {
                Button {
                    editorState.nudgeCaptions(byMS: -EditorState.captionNudgeMS)
                } label: {
                    Label("Earlier", systemImage: "arrow.left")
                }
                .disabled(!editorState.canNudgeCaptions)
                .playtestField("Captions Earlier")
                .panelHelp("Every caption a tenth of a second earlier.")
                Button {
                    editorState.nudgeCaptions(byMS: EditorState.captionNudgeMS)
                } label: {
                    Label("Later", systemImage: "arrow.right")
                }
                .disabled(!editorState.canNudgeCaptions)
                .playtestField("Captions Later")
                .panelHelp("Every caption a tenth of a second later.")
            }
            .controlSize(.small)
        }
    }

    private var file: some View {
        VideoKit.FieldRow(label: "Subtitles") {
            HStack(spacing: 6) {
                Button("Export…") { editorState.exportCaptions() }
                    .disabled(!editorState.canExportCaptions)
                    .playtestField("Export Captions")
                    .panelHelp("Save the words as a subtitle file.")
                Button("Clear") { editorState.clearCaptions() }
                    .disabled(!editorState.canClearCaptions)
                    .playtestField("Clear Captions")
                    .panelHelp("Take every caption off.")
            }
            .controlSize(.small)
        }
    }
}
