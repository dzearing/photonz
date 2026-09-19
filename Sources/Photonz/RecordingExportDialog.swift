import PhotonzCore
import SwiftUI

/// What a recording was last exported as, and at what preset.
///
/// Kept the way the picture sheet keeps its format: somebody who always sends
/// GIFs picks GIF once. One preset for both animated formats, because the
/// preset is a size choice rather than a format choice.
enum RecordingExportMemory {
    static let formatKey = "export.recording.format"
    static let qualityKey = "export.recording.quality"

    static var format: RecordingFormat {
        RecordingFormat(rawValue: UserDefaults.standard.string(forKey: formatKey) ?? "") ?? .mp4
    }

    static var quality: VideoExportQuality {
        VideoExportQuality(rawValue: UserDefaults.standard.string(forKey: qualityKey) ?? "")
            ?? .standard
    }

    static func remember(format: RecordingFormat, quality: VideoExportQuality) {
        UserDefaults.standard.set(format.rawValue, forKey: formatKey)
        UserDefaults.standard.set(quality.rawValue, forKey: qualityKey)
    }
}

/// Export… for a recording (Next, `next-recording-export-sheet`): the sheet a
/// picture already leaves through, with the recording's formats in it.
///
/// Before this, a recording was the one thing in the app that left through a
/// bare save box with the format already decided by which of three menu items
/// you happened to pick, and with nothing said about how big the file would be.
/// A screen recording is the file most likely to be too big to send, so it was
/// the worst one to say nothing about.
///
/// The sheet only CHOOSES. Pressing Export… hands straight to the save box and
/// the exporter that always ran, so the fast path for an untouched recording is
/// still a verbatim file copy and nothing about writing the file changed.
///
/// What it is allowed to say about the size is `RecordingExport`, which draws
/// the line between an exact number, an estimate measured off this very
/// recording, and a number that does not honestly exist until the file is
/// written.
struct RecordingExportDialog: View {
    @Environment(VideoEditorState.self) private var state
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.dismiss) private var dismiss

    @State private var format: RecordingFormat = .mp4
    @State private var quality: VideoExportQuality = .standard
    /// Everything about the recording the lines are worked out from, read once
    /// when the sheet opens. The recording cannot change while its own window
    /// is behind a sheet.
    @State private var source = RecordingExport.Source(sourceDuration: 0, keptDuration: 0,
                                                       sourceSize: .zero, fileBytes: 0,
                                                       isEdited: false)

    /// Whether this format has a size preset worth offering. MP4 has none yet,
    /// and the row goes away rather than dimming, exactly as the quality slider
    /// goes away for PNG.
    private var offersQuality: Bool { RecordingExport.offersQuality(format) }

    private var shapeLine: String {
        RecordingExport.shapeLine(format: format, quality: quality, source: source)
    }

    private var sizeLine: String {
        RecordingExport.sizeLine(format: format, source: source)
    }

    /// The name a walk finds the "what will this be" line by. Steady, because
    /// the words on the line are the thing under test.
    static let shapeLabel = "What it will be"

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
                    Picker("Quality", selection: $quality) {
                        ForEach(VideoExportQuality.allCases, id: \.self) { quality in
                            Text(quality.shortLabel).tag(quality)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }
            // The two lines the whole sheet exists for, in the order the
            // picture sheet puts them: what the file will BE, then what it will
            // WEIGH. The shape line sits under the preset rather than over it,
            // because on a GIF the preset is what moves it.
            VStack(alignment: .leading, spacing: 4) {
                Text(shapeLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .playtestControl(Self.shapeLabel, detail: shapeLine)
                Text(sizeLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .playtestControl(ExportDialog.sizeLabel, detail: sizeLine)
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                // Cancel writes nothing at all: the sheet has chosen a format
                // and a preset and touched neither the recording nor the disk.
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Export…") {
                    dismiss()
                    RecordingExportMemory.remember(format: format, quality: quality)
                    coordinator.saveRecording(state, as: format, quality: quality)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(ExportSheetMetrics.padding)
        .frame(width: ExportSheetMetrics.width)
        .onAppear {
            format = RecordingExportMemory.format
            quality = RecordingExportMemory.quality
            #if PHOTONZ_PLAYTEST
            if let asked = state.playtestOpensExportOnRecordingFormat {
                format = asked
                // Taken once, so a walk that photographs GIF cannot decide what
                // the NEXT walk's Export opens on.
                state.playtestOpensExportOnRecordingFormat = nil
            }
            if let asked = state.playtestOpensExportAtQuality {
                quality = asked
                state.playtestOpensExportAtQuality = nil
            }
            #endif
            source = state.exportSource
        }
    }
}
