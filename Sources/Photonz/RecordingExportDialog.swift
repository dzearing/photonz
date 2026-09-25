import PhotonzCore
import SwiftUI

/// What a recording was last exported as, and at what preset.
///
/// Kept the way the picture sheet keeps its format: somebody who always sends
/// GIFs picks GIF once.
///
/// **A video remembers its own choice, separately from the animated pair.** One
/// preset covered GIF and HEIC because the preset means the same thing in both:
/// how big the frames are and how many of them there are. It means something
/// else in a video, where the top choice is "the recording as it is" and hands
/// back the instant verbatim copy, so a video opens on High and an animated
/// picture opens on Standard, and picking Small to squeeze one GIF does not
/// quietly re-encode the next recording somebody exports.
enum RecordingExportMemory {
    static let formatKey = "export.recording.format"
    static let qualityKey = "export.recording.quality"
    static let movieQualityKey = "export.recording.quality.mp4"
    /// What the DOCUMENT sheet was last set to, which is the only one of the
    /// two that can answer "one frame, as a picture". Kept apart from the
    /// format above so that grabbing a still never changes what a recording
    /// window's own sheet opens on, where a picture is not on offer at all.
    static let choiceKey = "export.recording.choice"

    static var format: RecordingFormat {
        RecordingFormat(rawValue: UserDefaults.standard.string(forKey: formatKey) ?? "") ?? .mp4
    }

    /// What the document's Export sheet opens on: the picture where that is
    /// what was last written, and otherwise whatever video format was.
    static var choice: RecordingExport.Choice {
        UserDefaults.standard.string(forKey: choiceKey) == "still" ? .still : .video(format)
    }

    static func remember(choice: RecordingExport.Choice, quality: VideoExportQuality,
                         size: VideoExportSize? = nil) {
        UserDefaults.standard.set(choice == .still ? "still" : choice.fileExtension,
                                  forKey: choiceKey)
        guard let format = choice.format else { return }
        remember(format: format, quality: quality, size: size)
    }

    /// Where the size each format was last exported at is kept: apart per
    /// format, because a video and a GIF of the same recording want different
    /// sizes.
    static func sizeKey(_ format: RecordingFormat) -> String {
        "export.recording.size.\(format.rawValue)"
    }

    /// The size this format was last exported at, or the one it opens on the
    /// first time. What is remembered is what was PICKED: a recording too
    /// small for it shows Full without forgetting it for the next big one.
    static func size(for format: RecordingFormat) -> VideoExportSize {
        VideoExportSize(rawValue: UserDefaults.standard.string(forKey: sizeKey(format)) ?? "")
            ?? VideoExportSize.firstChoice(for: format)
    }

    /// The preset this format was last exported at, or the one it opens on the
    /// first time.
    static func quality(for format: RecordingFormat) -> VideoExportQuality {
        let key = format == .mp4 ? movieQualityKey : qualityKey
        return VideoExportQuality(rawValue: UserDefaults.standard.string(forKey: key) ?? "")
            ?? (format == .mp4 ? .high : .standard)
    }

    static func remember(format: RecordingFormat, quality: VideoExportQuality,
                         size: VideoExportSize? = nil) {
        UserDefaults.standard.set(format.rawValue, forKey: formatKey)
        UserDefaults.standard.set(quality.rawValue,
                                  forKey: format == .mp4 ? movieQualityKey : qualityKey)
        if let size { UserDefaults.standard.set(size.rawValue, forKey: sizeKey(format)) }
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
    /// A GIF or a HEIC being written into a scratch file so the sheet can say
    /// what it will weigh, since nothing short of writing one tells the truth
    /// about it (`ExportWeigh`).
    @State private var weigh = ExportWeigh()

    /// Whether this format has a size preset worth offering. All three do,
    /// since a video's preset started meaning a real budget rather than
    /// "highest quality, whatever that comes to".
    private var offersQuality: Bool { RecordingExport.offersQuality(format) }

    private var shapeLine: String {
        RecordingExport.shapeLine(format: format, quality: quality, source: source)
    }

    private var sizeLine: String {
        RecordingExport.sizeLine(format: format, quality: quality, source: source,
                                 weighing: weigh.result)
    }

    /// One sentence saying who the chosen preset is for.
    private var purposeLine: String {
        RecordingExport.purposeLine(format: format, quality: quality)
    }

    /// The name a walk finds the "what will this be" line by. Steady, because
    /// the words on the line are the thing under test.
    static let shapeLabel = "What it will be"

    /// The name a walk finds the "who is it for" line by.
    static let purposeLabel = "Who it is for"

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
                        // Three words on a row say which is bigger. This is the
                        // line that says which one you want, and it is beside
                        // the choice rather than under the whole sheet, because
                        // it is about the choice.
                        Text(purposeLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .playtestControl(Self.purposeLabel, detail: purposeLine)
                    }
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
                    // The file already written to answer "how big is it" is the
                    // file being asked for, so it goes with the press: a GIF
                    // somebody waited to see the size of saves instantly. Taken
                    // before dismissing, because dismissing stops the weigh and
                    // throws its scratch file away.
                    let weighed = weigh.take(format: format, quality: quality)
                    dismiss()
                    RecordingExportMemory.remember(format: format, quality: quality)
                    coordinator.saveRecording(state, as: format, quality: quality,
                                              weighed: weighed)
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
            startWeighing()
        }
        // Each format opens on its own remembered choice, so switching to GIF
        // does not carry a video's "as it is" across to a format where it means
        // the biggest possible file.
        .onChange(of: format) { _, now in
            quality = RecordingExportMemory.quality(for: now)
            startWeighing()
        }
        .onChange(of: quality) { _, _ in startWeighing() }
        // Nothing keeps writing once the sheet is gone, and the scratch file
        // goes with it.
        .onDisappear { weigh.stop() }
    }

    /// Write this GIF or HEIC into a scratch file so the line under the row can
    /// say what it weighs. A video is never weighed this way: it has a real
    /// budget and answers instantly, and a minute of screen would be a minute
    /// of work for a number that is already on the sheet.
    private func startWeighing() {
        guard format.isAnimatedImage else { weigh.stop(); return }
        let format = format, quality = quality
        weigh.weigh(format: format, quality: quality) { [coordinator, state] url, onProgress in
            try await coordinator.writeRecording(state, as: format, quality: quality, to: url,
                                                 onProgress: onProgress)
        }
    }
}
