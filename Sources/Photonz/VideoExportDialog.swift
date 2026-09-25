import PhotonzCore
import SwiftUI

/// Export… for a document that has time (Next, `next-export-the-video`): the
/// sheet a picture and a recording already leave through, writing what plays in
/// the window.
///
/// **It is the recording's sheet, not a second one.** The same three formats in
/// the same order, the same quality presets, the same two lines saying what the
/// file will be and what it will weigh, worked out by the same
/// `RecordingExport`. The only difference is what is behind it: a recording
/// exports one file re-timed, and this exports the document, which is the
/// pieces in the order they are in with everything drawn over them and the mix
/// under them.
///
/// **And one frame of it, as a picture.** PNG is a fourth button on the same
/// row rather than a second sheet, because everything leaving this window
/// leaves through one. Picking it puts the size presets away — they cap how big
/// a video's picture is and how fast it runs, and one frame has neither
/// question in it — and writes the frame the playhead is on at the size the
/// document is. The moment is read when the sheet opens and the playhead is
/// stopped there, so the line saying "the frame at 0:04" and the file that
/// lands are the same frame.
///
/// **A Size row the recording's sheet does not have.** Full, 1080p and 720p
/// for a video, Full, 720p and 480p for an animated picture
/// (`VideoExportSize`): a Retina recording is 2880 by 1800 and what people post
/// is 1080p. The size owns the pixels, so beside it Quality says only how
/// smooth the file runs and what is spent on it.
///
/// The sheet only CHOOSES. Pressing Export… hands to the save box and then to
/// `EditorState.writeVideo`, so the fast path for an untouched recording is
/// still a verbatim file copy.
struct VideoExportDialog: View {
    @Environment(EditorState.self) private var editor
    @Environment(\.dismiss) private var dismiss

    @State private var choice: RecordingExport.Choice = .video(.mp4)
    @State private var quality: VideoExportQuality = .standard
    /// How big the picture is: Full, 1080p or 720p, which is what people post
    /// and what Premiere offers. It owns the pixels; Quality keeps the frame
    /// rate and the budget.
    @State private var size: VideoExportSize = .full
    /// Words on the picture, or in a file beside it. Offered only on a film
    /// with captions in it.
    @State private var captions: CaptionExport = .burnedIn
    /// Everything the lines are worked out from, read once when the sheet
    /// opens: nothing can edit the document while its own window is behind a
    /// sheet.
    @State private var source = RecordingExport.Source(sourceDuration: 0, keptDuration: 0,
                                                       sourceSize: .zero, fileBytes: 0,
                                                       isEdited: false)
    /// Which moment the picture is of, read when the sheet opens.
    @State private var momentMS = 0
    /// The frame already written out as a PNG, which is both what the size line
    /// says and what Export saves: one frame is a render and an encode, so
    /// unlike a GIF it really can be weighed while somebody watches.
    @State private var stillFile: Data?
    @State private var weighing: Task<Void, Never>?
    /// A GIF or a HEIC being written into a scratch file so the sheet can say
    /// what it will weigh. There is no formula for an animated picture, so the
    /// only honest number comes from writing one (`ExportWeigh`).
    @State private var weigh = ExportWeigh()

    private var offersQuality: Bool { RecordingExport.offersQuality(choice) }

    /// Whether the answer showing is the picture rather than a video.
    private var isStill: Bool { choice == .still }

    /// The sizes that would shrink this document, with Full first. One entry
    /// means nothing to choose, and the row stays away.
    private var sizes: [VideoExportSize] {
        VideoExportSize.offered(for: source.sourceSize, format: choice.format ?? .mp4)
    }

    /// The size this export is written at: nil for one frame, which leaves at
    /// the size the document is.
    private var chosenSize: VideoExportSize? {
        choice.format.map { size.offeredOrFull(for: source.sourceSize, format: $0) }
    }

    /// What the lines are worked out from: the document, with its captions
    /// counted only where they go into the picture rather than beside it.
    private var described: RecordingExport.Source {
        var described = source
        if choice == .video(.mp4), captions != .burnedIn { described.captionedSeconds = 0 }
        return described
    }

    private var shapeLine: String {
        RecordingExport.shapeLine(choice: choice, quality: quality, source: described,
                                  size: chosenSize)
    }

    private var sizeLine: String {
        RecordingExport.sizeLine(choice: choice, quality: quality, source: described,
                                 stillBytes: stillFile?.count, weighing: weigh.result,
                                 size: chosenSize)
    }

    private var purposeLine: String {
        guard let format = choice.format else {
            return RecordingExport.purposeLine(choice: choice, quality: quality)
        }
        return quality.purposeBesideASize(for: format)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ExportSheetMetrics.spacing) {
            Text("Export")
                .font(.headline)
            ExportSheetRow("Format") {
                Picker("Format", selection: $choice) {
                    ForEach(RecordingExport.choices, id: \.self) { choice in
                        Text(RecordingExport.shortName(choice)).tag(choice)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            if choice.format != nil, sizes.count > 1 {
                ExportSheetRow("Size") {
                    Picker("Size", selection: $size) {
                        ForEach(sizes, id: \.self) { size in
                            Text(size.label(for: source.sourceSize)).tag(size)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .playtestControl("Export size", detail: size.label(for: source.sourceSize))
                }
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
                        purpose
                    }
                }
            }
            if editor.hasCaptions, choice == .video(.mp4) {
                ExportSheetRow("Captions") {
                    Picker("Captions", selection: $captions) {
                        ForEach(CaptionExport.choices, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .playtestControl("Export captions", detail: captions.title)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                // With no preset row to sit under, the sentence saying what
                // this answer is moves down beside the two lines. PNG next to
                // three video formats needs it most of the three: without it,
                // it reads as though it might turn the whole recording into
                // pictures.
                if !offersQuality { purpose }
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
                Button("Export…") { export() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(ExportSheetMetrics.padding)
        .frame(width: ExportSheetMetrics.width)
        // The video guide's export cards point at this sheet, so they sit
        // beside it rather than over the rows they are talking about.
        .tutorialAnchor(.dialog(.export))
        .onAppear {
            choice = RecordingExportMemory.choice
            quality = RecordingExportMemory.quality(for: choice.format ?? .mp4)
            source = editor.videoExportSource
            size = RecordingExportMemory.size(for: choice.format ?? .mp4)
                .offeredOrFull(for: source.sourceSize, format: choice.format ?? .mp4)
            #if PHOTONZ_PLAYTEST
            if editor.playtestOpensExportOnFrame {
                choice = .still
                editor.playtestOpensExportOnFrame = false
            }
            if let asked = editor.playtestOpensExportOnRecordingFormat {
                choice = .video(asked)
                editor.playtestOpensExportOnRecordingFormat = nil
            }
            if let asked = editor.playtestOpensExportAtQuality {
                quality = asked
                editor.playtestOpensExportAtQuality = nil
            }
            if let asked = editor.playtestOpensExportAtSize {
                size = asked.offeredOrFull(for: source.sourceSize, format: choice.format ?? .mp4)
                editor.playtestOpensExportAtSize = nil
            }
            #endif
            // A picture is of a MOMENT, so the playhead stops where it is and
            // stays there: a document still playing behind the sheet would
            // make the line and the file disagree about which frame this is.
            editor.pauseDocument()
            momentMS = editor.documentTimeMS
            weighTheFrame()
            weighTheAnimation()
        }
        .onChange(of: choice) { _, now in
            if let format = now.format {
                quality = RecordingExportMemory.quality(for: format)
                size = RecordingExportMemory.size(for: format)
                    .offeredOrFull(for: source.sourceSize, format: format)
            }
            weighTheFrame()
            weighTheAnimation()
        }
        .onChange(of: quality) { _, _ in weighTheAnimation() }
        .onChange(of: size) { _, _ in weighTheAnimation() }
        .onDisappear {
            weighing?.cancel()
            weighing = nil
            weigh.stop()
        }
    }

    /// The one sentence saying who this answer is for, wherever it sits.
    private var purpose: some View {
        Text(purposeLine)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .playtestControl(RecordingExportDialog.purposeLabel, detail: purposeLine)
    }

    /// Make the picture, once, the first time it is asked for. It is the
    /// answer to what the file will weigh AND the file itself, so pressing
    /// Export after reading the number writes those very bytes.
    private func weighTheFrame() {
        guard isStill, stillFile == nil, weighing == nil else { return }
        weighing = Task { @MainActor in
            let made = await editor.stillFrame(atMS: momentMS)
            guard !Task.isCancelled else { return }
            stillFile = made
            weighing = nil
        }
    }

    /// Write this GIF or HEIC of the document into a scratch file so the line
    /// under the row can say what it weighs, and so pressing Export after
    /// reading that number saves the very file that was weighed.
    ///
    /// A video is never weighed this way: it has a real budget and answers
    /// instantly (`VideoExportRecipe`).
    private func weighTheAnimation() {
        guard let format = choice.format, format.isAnimatedImage else { weigh.stop(); return }
        let quality = quality
        let size = chosenSize
        weigh.weigh(format: format, quality: quality, size: size) { [editor] url, onProgress in
            try await editor.writeVideo(format: format, quality: quality, size: size, to: url,
                                        onProgress: onProgress)
        }
    }

    /// Hand what was chosen to the save box.
    private func export() {
        // Remembered only where there was a size to choose: a recording too
        // small for any keeps whatever was picked on the last one.
        RecordingExportMemory.remember(choice: choice, quality: quality,
                                       size: sizes.count > 1 ? size : nil)
        let size = chosenSize
        // Taken before dismissing: dismissing stops the weigh and throws its
        // scratch file away, and that file is the export.
        let weighed = choice.format.flatMap { weigh.take(format: $0, quality: quality, size: size) }
        dismiss()
        if let format = choice.format {
            editor.exportVideo(format: format, quality: quality, size: size, weighed: weighed,
                               captions: format == .mp4 ? captions : .burnedIn)
        } else {
            editor.exportStillFrame(atMS: momentMS, weighed: stillFile)
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
