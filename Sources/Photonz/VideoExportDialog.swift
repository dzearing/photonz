import PhotonzCore
import SwiftUI

/// Export… for a document that has time (Next, `next-export-the-video`): the
/// sheet a picture and a recording already leave through, writing what plays in
/// the window.
///
/// **It is the recording's sheet, not a second one.** The same three formats in
/// the same order, the same size presets, the same two lines saying what the
/// file will be and what it will weigh, worked out by the same
/// `RecordingExport`. The only difference is what is behind it: a recording
/// exports one file re-timed, and this exports the document, which is the
/// pieces in the order they are in with everything drawn over them and the mix
/// under them.
///
/// The sheet only CHOOSES. Pressing Export… hands to the save box and then to
/// `EditorState.writeVideo`, so the fast path for an untouched recording is
/// still a verbatim file copy.
struct VideoExportDialog: View {
    @Environment(EditorState.self) private var editor
    @Environment(\.dismiss) private var dismiss

    @State private var format: RecordingFormat = .mp4
    @State private var quality: VideoExportQuality = .standard
    /// Everything the lines are worked out from, read once when the sheet
    /// opens: nothing can edit the document while its own window is behind a
    /// sheet.
    @State private var source = RecordingExport.Source(sourceDuration: 0, keptDuration: 0,
                                                       sourceSize: .zero, fileBytes: 0,
                                                       isEdited: false)

    private var offersQuality: Bool { RecordingExport.offersQuality(format) }

    private var shapeLine: String {
        RecordingExport.shapeLine(format: format, quality: quality, source: source)
    }

    private var sizeLine: String {
        RecordingExport.sizeLine(format: format, quality: quality, source: source)
    }

    private var purposeLine: String {
        RecordingExport.purposeLine(format: format, quality: quality)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ExportSheetMetrics.spacing) {
            Text("Export")
                .font(.headline)
            ExportSheetRow("Format") {
                Picker("Format", selection: $format) {
                    ForEach(RecordingExport.formats, id: \.self) { format in
                        Text(RecordingExport.shortName(format)).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            if offersQuality {
                ExportSheetRow("Quality") {
                    VStack(alignment: .leading, spacing: 4) {
                        Picker("Quality", selection: $quality) {
                            ForEach(VideoExportQuality.allCases, id: \.self) { quality in
                                Text(quality.shortLabel).tag(quality)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        Text(purposeLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .playtestControl(RecordingExportDialog.purposeLabel,
                                             detail: purposeLine)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(shapeLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .playtestControl(RecordingExportDialog.shapeLabel, detail: shapeLine)
                Text(sizeLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .playtestControl(ExportDialog.sizeLabel, detail: sizeLine)
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Export…") {
                    dismiss()
                    editor.exportVideo(format: format, quality: quality)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(ExportSheetMetrics.padding)
        .frame(width: ExportSheetMetrics.width)
        .onAppear {
            format = RecordingExportMemory.format
            quality = RecordingExportMemory.quality(for: format)
            #if PHOTONZ_PLAYTEST
            if let asked = editor.playtestOpensExportOnRecordingFormat {
                format = asked
                editor.playtestOpensExportOnRecordingFormat = nil
            }
            if let asked = editor.playtestOpensExportAtQuality {
                quality = asked
                editor.playtestOpensExportAtQuality = nil
            }
            #endif
            source = editor.videoExportSource
        }
        .onChange(of: format) { _, now in
            quality = RecordingExportMemory.quality(for: now)
        }
    }
}

/// What a video export looks like while it is happening: how far along it is,
/// and the one thing you can do about it.
///
/// A card rather than a spinner, because writing a minute of screen is a minute
/// of work: a person has to be able to see it moving and be able to stop it.
/// Stopping takes the half-written file with it
/// (`DocumentMovieWriter.write`), so there is nothing to tidy up afterwards and
/// nothing to warn about here.
struct VideoExportProgressSheet: View {
    let run: VideoExportRun
    /// What Stop does. The card is the same whichever door the export came
    /// through; only the thing it stops differs.
    let stop: () -> Void

    /// The name a walk finds the bar by.
    static let progressLabel = "Export progress"

    var body: some View {
        VStack(alignment: .leading, spacing: ExportSheetMetrics.spacing) {
            Text(run.title)
                .font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: min(1, max(0, run.fraction)))
                    .progressViewStyle(.linear)
                    .playtestControl(Self.progressLabel, detail: "\(run.percent)%")
                Text("\(run.fileName) · \(run.percent)%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Stop") { stop() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(ExportSheetMetrics.padding)
        .frame(width: ExportSheetMetrics.width)
    }
}
