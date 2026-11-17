import AppKit
import AVFoundation
import CoreGraphics
import Foundation
import PhotonzCore
import PhotonzMedia
import PhotonzRender
import UniformTypeIdentifiers

// Getting a document that has time out of the app as a video
// (`docs/design/video.md` §8).
//
// Everything a person did on the timeline — cut it, threw a piece away, carried
// the pieces into a different order, sped one up, held a frame, took the sound
// off the picture, put music under it and ducked the music — was until now
// unreachable: Export wrote the recording that was opened, and Export Sound
// wrote the mix on its own. This is the other half.
//
// **Nothing here knows how to draw a frame or how to mix.** The frame at a
// moment is `PhotonzDocument.drawn(atTimeMS:)` through the very renderer the
// canvas uses, so the export and the window cannot show two different pictures;
// the sound is `PhotonzDocument.audioMix()` through `AudioMixdown`, which is
// what Export Sound already writes. What is added is the loop between them and
// the bar that says how far along it is.
extension EditorState {

    /// Whether Export writes a VIDEO from this window rather than a picture.
    ///
    /// A document with no duration is untouched: a screenshot still leaves
    /// through the picture sheet it always did.
    var exportsVideo: Bool {
        Experiments.shared.videoExportEnabled && documentHasTime
    }

    /// What the export sheet is allowed to say about this document.
    ///
    /// The same three-way honesty the recording sheet already has
    /// (`RecordingExport`): an untouched recording going out as MP4 is a
    /// verbatim copy and its size is known to the byte, and anything that has
    /// to be made frame by frame says so rather than inventing a number.
    ///
    /// An edited document is weighed off the recordings its clips play, a
    /// second at a time (`RecordingExport.footageBytesPerSecond`), because
    /// the encoder's budget is a ceiling a screen recording never gets near.
    var videoExportSource: RecordingExport.Source { videoExportSource(.marked) }

    /// The same, for the stretch the sheet's Range row has picked. A marked
    /// stretch says how long it is against the whole ("0:04 of 0:10"), and is
    /// never a verbatim copy: the file on disk is the whole recording.
    func videoExportSource(_ range: VideoExportRange) -> RecordingExport.Source {
        let seconds = Double(documentLengthMS) / 1000
        let span = document?.exportRangeMS(range) ?? 0..<0
        let kept = Double(span.count) / 1000
        let partial = document.map { span != $0.exportRangeMS(.whole) } ?? false
        let untouched = document?.untouchedRecording
        let bytes = untouched
            .flatMap { MovieLibrary.shared.url(for: $0) }
            .flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize } ?? 0
        let canvas = document?.canvasSize ?? .zero
        let mix = document.map { AudioMixSegment.windowed($0.audioMix(), to: span) } ?? []
        return RecordingExport.Source(sourceDuration: seconds, keptDuration: kept,
                                      sourceSize: canvas,
                                      fileBytes: bytes, isEdited: untouched == nil || partial,
                                      sourceFPS: DocumentVideoExport.movieFPS,
                                      hasAudio: !mix.isEmpty,
                                      playheadTime: Double(documentTimeMS) / 1000,
                                      footageBytesPerSecond: untouched == nil
                                        ? RecordingExport.footageBytesPerSecond(footage, at: canvas)
                                        : nil,
                                      captionedSeconds: document?.captionedSeconds(in: span) ?? 0,
                                      isCutOnly: copyablePieces(range: range) != nil,
                                      mayBeSmoothed: RecordingSmoothing.isOn)
    }

    /// The stretches of one recording this edit is made of, where it is
    /// nothing but those, for the stretch `range` picks and with the captions
    /// going out as `captions` (`PhotonzDocument.copyablePieces`).
    func copyablePieces(captions: CaptionExport = .burnedIn,
                        range: VideoExportRange = .marked) -> CopyablePieces? {
        guard let document = document?.forExport(captions: captions), document.hasTime else { return nil }
        return document.copyablePieces(in: document.exportRangeMS(range))
    }

    /// Every recording file the document's clips play, weighed once each.
    private var footage: [RecordingExport.Footage] {
        guard let document else { return [] }
        let files = MovieLibrary.shared.urls(in: document)
        var seen = Set<UUID>()
        var found: [RecordingExport.Footage] = []
        for layer in document.allLayers {
            guard let movie = layer.movie, seen.insert(movie.id).inserted,
                  let url = files[movie.id],
                  let bytes = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
            else { continue }
            found.append(RecordingExport.Footage(bytes: bytes,
                                                 seconds: Double(movie.durationMS) / 1000,
                                                 pixelSize: movie.pixelSize))
        }
        return found
    }

    /// **Export…** on a document that has time: pick a place, then write it.
    ///
    /// - weighed: the scratch file the sheet already wrote to say what this
    ///   would weigh (`ExportWeigh`). That file IS the export and is moved into
    ///   place rather than written again: the number the sheet showed is the
    ///   file that lands, which a second write could not promise for a HEIC.
    func exportVideo(format: RecordingFormat, quality: VideoExportQuality,
                     size: VideoExportSize? = nil,
                     weighed: URL? = nil, captions: CaptionExport = .burnedIn,
                     range: VideoExportRange = .marked) {
        guard let document, document.hasTime else { return }
        // The sheet remembers the size that was PICKED; the one handed here
        // may be Full only because this document is too small for the pick.
        RecordingExportMemory.remember(format: format, quality: quality)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.savePanelType]
        panel.nameFieldStringValue = RecordingExport.suggestedFileName(
            recording: videoExportName, format: format)
        panel.canCreateDirectories = true
        panel.message = "Write what plays in this window out as a file"
        guard panel.runModal() == .OK, let url = panel.url else {
            if let weighed { try? FileManager.default.removeItem(at: weighed) }
            return
        }
        startVideoExport(format: format, quality: quality, size: size, to: url,
                         weighed: weighed, captions: captions, range: range)
    }

    /// What the file is called before anybody renames it: the document's own
    /// name, so a video off a recording lands beside it under the same word.
    var videoExportName: String {
        (documentURL ?? openedFileURL ?? recordingURL)?.lastPathComponent ?? "Video"
    }

    /// Write it, with a bar on screen that can be stopped.
    ///
    /// Playing is paused first: an export is a minute of decoding and
    /// compositing, and a playhead running through it would be fighting for the
    /// same frames.
    func startVideoExport(format: RecordingFormat, quality: VideoExportQuality,
                          size: VideoExportSize? = nil, to url: URL,
                          weighed: URL? = nil, captions: CaptionExport = .burnedIn,
                          range: VideoExportRange = .marked) {
        guard videoExport == nil else { return }
        // Already written, to answer what it would weigh: move it into place
        // and there is nothing to watch.
        // The sheet writes it with the captions it shows, burned in or not, so
        // a file of words beside it is all that is left to write.
        if let weighed, AppCoordinator.putWeighedFileInPlace(weighed, at: url) {
            keptByExport()
            raiseCanvasNotice(.videoWritten(file: url.lastPathComponent))
            if let file = captions.file { writeCaptionsBeside(film: url, as: file, range: range) }
            return
        }
        pauseDocument()
        let run = VideoExportRun(fileName: url.lastPathComponent, title: format.writingTitle)
        videoExport = run
        // A write now runs several frames a millisecond apart, and the bar
        // cannot show a step finer than a pixel or two: only a step the card
        // can show is sent to the main actor, so the window is not asked to
        // redraw its card hundreds of times a second.
        let steps = ProgressSteps(count: 500)
        videoExportTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await writeVideo(format: format, quality: quality, size: size, to: url,
                                     captions: captions, range: range) { done in
                    guard steps.isNewStep(done) else { return }
                    Task { @MainActor in run.fraction = done }
                }
                videoExport = nil
                videoExportTask = nil
                keptByExport()
                raiseCanvasNotice(.videoWritten(file: url.lastPathComponent))
                // The words as a file beside the film, named after it, where
                // a player looks for them.
                if let file = captions.file {
                    writeCaptionsBeside(film: url, as: file, range: range)
                }
            } catch is CancellationError {
                // Stopped on purpose, and `DocumentMovieWriter` took the
                // half-written file with it. The sheet going away is the whole
                // of the news.
                videoExport = nil
                videoExportTask = nil
            } catch {
                NSLog("Video export failed: \(error)")
                videoExport = nil
                videoExportTask = nil
                raiseCanvasNotice(.videoWritten(file: nil))
            }
        }
    }

    /// A recording that cannot be saved in place is kept by exporting it, so
    /// what was just written out is the new clean baseline: closing stops
    /// asking about edits that are now safely in a file. Anything that CAN be
    /// saved keeps its own baseline, because an export is a copy, not a save.
    func keptByExport() {
        if isRecordingDocument { markSaved() }
    }

    // MARK: One frame of it, as a picture

    /// The frame at a moment, as the bytes of a PNG file.
    ///
    /// The same picture the video export writes at that moment, through the
    /// same `DocumentFrames`: the clip's own frame fetched if the window is
    /// not already holding it, everything drawn over it, at the size the
    /// document is. Rendering and encoding both happen off the main actor, so
    /// the sheet keeps drawing while its size line is being worked out.
    ///
    /// Nil where there is no document with time, or where the frame could not
    /// be made at all.
    func stillFrame(atMS ms: Int) async -> Data? {
        guard let document, document.hasTime else { return nil }
        let pictures = DocumentFrames(document: document, store: store,
                                      movieURLs: MovieLibrary.shared.urls(in: document))
        defer { pictures.putTheStoreBack() }
        return await pictures.png(atMS: ms)
    }

    /// **Export…** with the picture chosen: pick a place, then write the one
    /// frame there.
    ///
    /// `weighed` is the file the sheet already made to say what it would
    /// weigh, so pressing Export after reading that number writes those very
    /// bytes rather than rendering the frame a second time. Without one, the
    /// frame is made here.
    func exportStillFrame(atMS ms: Int, weighed: Data? = nil) {
        guard let document, document.hasTime else { return }
        let name = RecordingExport.suggestedFileName(recording: videoExportName, choice: .still)
        Task { [weak self] in
            guard let self else { return }
            var data = weighed
            if data == nil { data = await stillFrame(atMS: ms) }
            guard let data else {
                raiseCanvasNotice(.frameWritten(file: nil))
                return
            }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [UTType.png]
            panel.nameFieldStringValue = name
            panel.canCreateDirectories = true
            panel.message = "Write the frame the playhead is on out as a picture"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do {
                try data.write(to: url)
                raiseCanvasNotice(.frameWritten(file: url.lastPathComponent))
            } catch {
                NSLog("Frame export failed: \(error)")
                raiseCanvasNotice(.frameWritten(file: nil))
            }
        }
    }

    // MARK: Onto the clipboard

    /// Whether Edit ▸ Copy Video and Copy as GIF can run: a document with
    /// time, and no export or copy already writing (there is one toast).
    var canCopyVideo: Bool { exportsVideo && videoExport == nil }

    /// **Edit ▸ Copy Video / Copy as GIF.** The edit written the way the
    /// Export sheet writes it, at the sheet's last choice for this format
    /// (`VideoClipboardCopy`), into a scratch file that then goes on the
    /// clipboard: what Current's recording window did for a trim, for the
    /// whole timeline. The same toast an export shows says it is copying and
    /// can stop it; the result pill says Copied once a paste would work.
    func copyVideo(as format: RecordingFormat) {
        guard canCopyVideo, let document else { return }
        let choice = VideoClipboardCopy.choice(
            rememberedQuality: RecordingExportMemory.quality(for: format),
            rememberedSize: RecordingExportMemory.size(for: format),
            canvasSize: document.canvasSize, format: format)
        let url = Self.clipboardCopyURL(
            named: RecordingExport.suggestedFileName(recording: videoExportName, format: format))
        pauseDocument()
        let run = VideoExportRun(fileName: url.lastPathComponent, title: format.copyingTitle)
        videoExport = run
        let steps = ProgressSteps(count: 500)
        videoExportTask = Task { [weak self] in
            guard let self else { return }
            do {
                try? FileManager.default.removeItem(at: url)
                try await writeVideo(format: format, quality: choice.quality, size: choice.size,
                                     to: url, captions: choice.captions, range: choice.range) { done in
                    guard steps.isNewStep(done) else { return }
                    Task { @MainActor in run.fraction = done }
                }
                // A GIF's own bytes ride along for apps that paste a picture
                // rather than attach a file, read off the main actor: a long
                // one is tens of megabytes.
                let bytes: Data? = format == .gif
                    ? await Task.detached { try? Data(contentsOf: url) }.value : nil
                try Task.checkCancellation()
                ClipboardWriter.writeFile(url, data: bytes, dataType: bytes == nil ? nil : .gif)
                videoExport = nil
                videoExportTask = nil
                raiseCanvasNotice(.videoCopied(file: url.lastPathComponent, format: format))
            } catch is CancellationError {
                try? FileManager.default.removeItem(at: url)
                videoExport = nil
                videoExportTask = nil
            } catch {
                NSLog("Copy to the clipboard failed: \(error)")
                videoExport = nil
                videoExportTask = nil
                raiseCanvasNotice(.videoCopied(file: nil, format: format))
            }
        }
    }

    /// Where a copy is written: a scratch folder of its own, under the name a
    /// paste will carry. The next copy of the same name replaces it.
    private static func clipboardCopyURL(named name: String) -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotonzClipboard", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(name)
    }

    /// Stop an export that is running. What has been written so far goes with
    /// it, so there is never a half a video left on the disk.
    func cancelVideoExport() {
        videoExportTask?.cancel()
    }

    /// Write the document out, with no save box and no reporting.
    ///
    /// The part both the sheet and a scripted walk need, so a walk can check
    /// the file that actually lands rather than trusting what the app says it
    /// wrote.
    @discardableResult
    func writeVideo(format: RecordingFormat, quality: VideoExportQuality,
                    size: VideoExportSize? = nil, to url: URL,
                    captions: CaptionExport = .burnedIn,
                    range: VideoExportRange = .marked,
                    mayCopyPieces: Bool = true,
                    onProgress: (@Sendable (Double) -> Void)? = nil) async throws -> VideoWriteRoute {
        guard let document else { throw CocoaError(.fileNoSuchFile) }
        return try await Self.writeVideo(of: document, pictures: store, format: format,
                                         quality: quality, size: size, to: url, captions: captions,
                                         range: range, mayCopyPieces: mayCopyPieces,
                                         onProgress: onProgress)
    }

    /// The same write for a document no window is holding: what a save into
    /// history runs, which carries on after its window has closed
    /// (`CaptureStore+VideoSaves`). `pictures` is where the document's own
    /// pictures are, a snapshot of the window's store when one had it.
    /// `mayCopyPieces` false draws an edit that could have been copied, which
    /// only a walk timing the two against each other asks for.
    /// `throughPictures` draws every frame as a picture first, read back off
    /// the GPU and drawn again into the encoder's buffer, the way every export
    /// did before 2026-11-16: only a walk comparing the two asks for it.
    @discardableResult
    static func writeVideo(of document: PhotonzDocument, pictures store: ImageStore,
                           format: RecordingFormat, quality: VideoExportQuality,
                           size: VideoExportSize? = nil, to url: URL,
                           captions: CaptionExport = .burnedIn,
                           range: VideoExportRange = .marked,
                           mayCopyPieces: Bool = true,
                           throughPictures: Bool = false,
                           onProgress: (@Sendable (Double) -> Void)? = nil) async throws -> VideoWriteRoute {
        // Work a person asked for and is waiting on, said so to the system,
        // so a long export left running while they step away is neither
        // napped nor stopped half way by the Mac going to sleep.
        let activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiated, reason: "Writing a video")
        defer { ProcessInfo.processInfo.endActivity(activity) }
        // Written beside `url` and swapped in whole: `url` may be the very
        // recording this plays (the save box offers the recording's own name),
        // and every route below starts by removing its destination
        // (`FileSwap`).
        return try await FileSwap.write(to: url) { scratch in
            try await writeVideoUnswapped(
                of: document, pictures: store, format: format, quality: quality, size: size,
                to: scratch, captions: captions, range: range, mayCopyPieces: mayCopyPieces,
                throughPictures: throughPictures, onProgress: onProgress)
        }
    }

    private static func writeVideoUnswapped(of document: PhotonzDocument, pictures store: ImageStore,
                                            format: RecordingFormat, quality: VideoExportQuality,
                                            size: VideoExportSize?, to url: URL,
                                            captions: CaptionExport, range: VideoExportRange,
                                            mayCopyPieces: Bool,
                                            throughPictures: Bool,
                                            onProgress: (@Sendable (Double) -> Void)?) async throws -> VideoWriteRoute {
        let document = document.forExport(captions: captions)
        guard document.hasTime else { throw CocoaError(.fileNoSuchFile) }
        // The In to the Out where they are set, and all of it otherwise
        // (`VideoExportRange`): a stretch is the window's own pictures and mix
        // over it, on a clock that starts at the In.
        let span = document.exportRangeMS(range)
        let whole = span == document.exportRangeMS(.whole)

        // The recording nobody has touched is already the answer: copy the file
        // rather than photographing it back into existence. Only at the top
        // choice: the two below it are asking for a SMALLER file than the one
        // on disk, and that cannot be done by copying it
        // (`RecordingExport.copiesVerbatim`), and neither is a size that
        // shrinks the picture.
        // A stretch of it cannot be copied either: the file is all of it.
        if format == .mp4, quality == .high, whole,
           !(size?.shrinks(document.canvasSize) ?? false),
           let movie = document.untouchedRecording,
           let source = MovieLibrary.shared.url(for: movie) {
            // Unless the Mac drew a soft gradient of it in steps: then it is
            // written out again with the steps smoothed, at its own depth,
            // so other players show what Photonz does (`ExportSmoothing`).
            if await ExportSmoothing.isWorthIt(source, movie: movie, rangesMS: nil) {
                let mix = AudioMixSegment.windowed(document.audioMix(), to: span)
                let soundURLs = await SoundLibrary.shared.readyURLs(for: mix)
                let frames = try await SmoothedCopyWriter.write(
                    source: source, ranges: nil, mix: mix, soundURLs: soundURLs,
                    filter: ExportSmoothing.filter, to: url, onProgress: onProgress)
                return .smoothed(frames: frames, piecesOnly: false)
            }
            try? FileManager.default.removeItem(at: url)
            try FileManager.default.copyItem(at: source, to: url)
            onProgress?(1)
            return .copiedWhole
        }

        // An edit that is nothing but cuts is the stretches of the recording
        // it keeps, already compressed: copy them across, and encode again
        // only the few frames between a cut and the next key frame
        // (`PieceCopyWriter`). Same choice as the whole copy, for the same
        // reasons. A file it cannot copy from is drawn the ordinary way.
        if mayCopyPieces, format == .mp4, quality == .high,
           !(size?.shrinks(document.canvasSize) ?? false),
           let pieces = document.copyablePieces(in: span),
           let source = MovieLibrary.shared.url(for: pieces.movie) {
            let mix = AudioMixSegment.windowed(document.audioMix(), to: span)
            let soundURLs = await SoundLibrary.shared.readyURLs(for: mix)
            if await ExportSmoothing.isWorthIt(source, movie: pieces.movie, rangesMS: pieces.sourceRangesMS) {
                let frames = try await SmoothedCopyWriter.write(
                    source: source, ranges: pieces.sourceRangesMS, mix: mix, soundURLs: soundURLs,
                    filter: ExportSmoothing.filter, to: url, onProgress: onProgress)
                return .smoothed(frames: frames, piecesOnly: true)
            }
            do {
                let outcome = try await PieceCopyWriter.write(
                    source: source, ranges: pieces.sourceRangesMS, mix: mix, soundURLs: soundURLs,
                    to: url, onProgress: onProgress)
                return .copiedPieces(copiedFrames: outcome.copiedFrames,
                                     renderedFrames: outcome.renderedFrames)
            } catch let error as PieceCopyWriter.CopyError {
                NSLog("Copying the kept pieces did not work (\(error)); drawing the edit instead")
            }
        }

        let plan = DocumentVideoExport.plan(range: span,
                                            canvasSize: document.canvasSize,
                                            format: format, quality: quality, size: size)
        let mix = AudioMixSegment.windowed(document.audioMix(), to: span)
        let soundURLs = await SoundLibrary.shared.readyURLs(for: mix)
        // Drawn at the file's size rather than the canvas's: a 1080p file
        // off a Retina recording has no use for the other 60% of the pixels,
        // and drawing them only to throw them away was a third of the write.
        // Clips are read front to back, since that is the order a file asks
        // for them in (`MovieFrameStream`).
        let pictures = DocumentFrames(document: document, store: store,
                                      movieURLs: MovieLibrary.shared.urls(in: document),
                                      size: plan.size, streaming: true,
                                      smoothsStreamed: quality == .high && format == .mp4,
                                      readsSurfaces: !throughPictures)
        let frames: DocumentMovieWriter.FrameSource = { ms in await pictures.frame(atMS: ms) }
        defer { pictures.putTheStoreBack() }

        if format == .mp4 {
            // Each frame drawn on the GPU straight into the buffer the encoder
            // reads (`DocumentFrames.draw(atMS:into:)`).
            let drawn: DocumentMovieWriter.Pictures = throughPictures ? .images(frames) : .drawnInto { ms, buffer in
                await pictures.draw(atMS: ms, into: buffer)
            }
            try await DocumentMovieWriter.write(plan: plan, mix: mix, soundURLs: soundURLs,
                                                to: url, pictures: drawn, onProgress: onProgress)
        } else {
            try await DocumentMovieWriter.writeAnimated(plan: plan, format: format, to: url,
                                                        frames: frames, onProgress: onProgress)
        }
        return .drawn
    }
}

extension EditorState {

    /// What an MP4 of the document will weigh at this choice, found by writing
    /// a few stretches of it with the same pictures `writeVideo` draws
    /// (`DocumentMovieWriter.weigh`). For the Export sheet, which quotes the
    /// budget until this answers.
    func weighVideo(quality: VideoExportQuality, size: VideoExportSize? = nil,
                    captions: CaptionExport = .burnedIn,
                    range: VideoExportRange = .marked,
                    onProgress: (@Sendable (Double) -> Void)? = nil) async throws -> Int {
        guard let document = document?.forExport(captions: captions), document.hasTime
        else { throw CocoaError(.fileNoSuchFile) }
        let span = document.exportRangeMS(range)
        let plan = DocumentVideoExport.plan(range: span, canvasSize: document.canvasSize,
                                            format: .mp4, quality: quality, size: size)
        let mix = AudioMixSegment.windowed(document.audioMix(), to: span)
        // Weighed with the same frames the write draws, grain and all.
        let pictures = DocumentFrames(document: document, store: store,
                                      movieURLs: MovieLibrary.shared.urls(in: document),
                                      size: plan.size, streaming: true,
                                      smoothsStreamed: quality == .high)
        defer { pictures.putTheStoreBack() }
        return try await DocumentMovieWriter.weigh(
            span: span, canvasSize: document.canvasSize, quality: quality, size: size,
            mix: mix, soundURLs: await SoundLibrary.shared.readyURLs(for: mix),
            pictures: .drawnInto { ms, buffer in await pictures.draw(atMS: ms, into: buffer) },
            onProgress: onProgress)
    }
}

/// How a video was written, which a walk checks against what it expected.
enum VideoWriteRoute: Equatable, Sendable {
    /// The recording nobody touched, copied byte for byte.
    case copiedWhole
    /// An edit that is nothing but cuts, its stretches copied across and only
    /// the frames between a cut and the next key frame encoded again.
    case copiedPieces(copiedFrames: Int, renderedFrames: Int)
    /// The recording, or the stretches an edit of cuts keeps, written out
    /// again at its own depth with its soft gradients smoothed
    /// (`SmoothedCopyWriter`), where a copy would have kept the steps.
    case smoothed(frames: Int, piecesOnly: Bool)
    /// Every frame drawn and encoded.
    case drawn
}

/// Whether a top quality export writes a recording out smoothed rather than
/// copying it, and the pass it writes it with.
///
/// A copy is instant and exact, so it stays the answer for a recording the
/// pass would not change, and for any recording stored at 8 bits, which
/// would round the ramp straight back into its steps (every recording made
/// since 2026-11-16 is 10-bit; the tutorial sample, H.264 at 112 kbps, also
/// read as "changed" on nothing but its encoder's noise). The check reads three frames at a quarter size and
/// asks how much of each the pass would move by a 10-bit code or more
/// (`RecordingSmoothing.changedShare`). The user's own recording of a terminal
/// window moved about 2 per cent of its pixels (the window's sidebar is 4 per
/// cent of the screen); a page of flat colours and text moves none.
enum ExportSmoothing {

    /// The pass a smoothed export writes with: no grain, since the file is
    /// as deep as the recording and the encoder drops grain anyway
    /// (`SmoothedCopyWriter.quality`).
    static let filter: SmoothedCopyWriter.Filter = { image in
        RecordingSmoothing.smoothed(image, reach: RecordingSmoothing.reachInRecordingPixels, grain: false)
    }

    /// The share of a frame's pixels the pass has to move before a write is
    /// worth it: one in five hundred.
    static let worthIt = 0.002

    /// Whether `ranges` of the recording at `url` (all of it when nil) have
    /// steps worth smoothing. False whenever the switch is off.
    static func isWorthIt(_ url: URL, movie: MovieRef, rangesMS: [Range<Int>]?) async -> Bool {
        guard RecordingSmoothing.isOn, RecordingSmoothing.isAvailable,
              await SmoothedCopyWriter.isDeep(url) else { return false }
        let ranges = rangesMS ?? [0..<max(1, movie.durationMS)]
        let total = ranges.reduce(0) { $0 + $1.count }
        guard total > 0 else { return false }
        // Three moments spread over what is kept, in the recording's own time.
        let moments: [Int] = [0.2, 0.5, 0.8].map { share in
            var left = Int(Double(total) * share)
            for range in ranges {
                if left < range.count { return range.lowerBound + left }
                left -= range.count
            }
            return ranges.last.map { max($0.lowerBound, $0.upperBound - 1) } ?? 0
        }
        let scale: CGFloat = 0.25
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: max(64, movie.pixelSize.width * scale),
                                       height: max(64, movie.pixelSize.height * scale))
        for ms in moments {
            guard let image = try? await generator.image(
                at: CMTime(value: CMTimeValue(ms), timescale: 1000)).image else { continue }
            let read = CGFloat(image.width) / max(1, movie.pixelSize.width)
            if let share = RecordingSmoothing.changedShare(
                of: image, reach: RecordingSmoothing.reach(readAt: read)), share >= worthIt {
                return true
            }
        }
        return false
    }
}

/// An export that is running: what it is called and how far along it is.
@MainActor
@Observable
final class VideoExportRun: Identifiable {
    let id = UUID()
    let fileName: String
    /// What the card says it is writing, which follows the format rather than
    /// always saying "video".
    let title: String
    var fraction: Double = 0

    init(fileName: String, title: String = "Writing the video") {
        self.fileName = fileName
        self.title = title
    }

    /// The percentage, said the way a person reads one.
    var percent: Int { Int((min(1, max(0, fraction)) * 100).rounded()) }
}

/// Whether a fraction done has reached the next of `count` even steps.
///
/// Called from the one loop writing the file, one frame after another, so
/// there is never a second caller; the `@unchecked` is that promise.
final class ProgressSteps: @unchecked Sendable {
    private let count: Double
    private var last = -1

    init(count: Int) { self.count = Double(max(1, count)) }

    func isNewStep(_ fraction: Double) -> Bool {
        let step = Int((min(1, max(0, fraction)) * count).rounded(.down))
        guard step != last else { return false }
        last = step
        return true
    }
}

/// The picture of a document at any moment, made the way the canvas makes it.
///
/// Off the main actor on purpose: a minute of recording is a couple of thousand
/// decodes and composites, and doing that on the main actor is a window that
/// stops drawing. `ImageStore` and `DocumentRenderer` are both safe to use from
/// anywhere, so the export borrows the window's store — which is where every
/// picture in the document already lives — and brings its own renderer so the
/// canvas's own caches are left alone.
///
/// **It puts the store back as it found it.** A decoded frame is eight
/// megabytes and a long export needs thousands of them, so each one is dropped
/// once the picture that needed it has been drawn.
final class DocumentFrames: @unchecked Sendable {

    private let document: PhotonzDocument
    private let store: ImageStore
    private let movieURLs: [UUID: URL]
    private let renderer = DocumentRenderer()
    /// How many output pixels per document point, 1 for the canvas's own size.
    private let scale: CGFloat
    /// Whether clips are read front to back (`MovieFrameStream`) rather than
    /// sought frame by frame: what a file written from start to end wants.
    private let streaming: Bool
    /// Whether frames read off a stream get the smoothing the window shows
    /// them with (`RecordingSmoothing`). Only a top quality file keeps its
    /// grain: at Standard's budget the encoder wiped it and the file read
    /// exactly as banded as one written without it, in twice the time
    /// (measured 2026-11-16 on the user's recording: longest flat run 94 px
    /// against 95, 11.2 s against 5.4 s). At High's, about 55 Mbps for a
    /// full-screen Retina recording, it kept a flat run of 31 px against 116.
    private let smoothsStreamed: Bool
    /// Whether a frame read off a stream is handed to the renderer on the
    /// surface it was decoded onto (`ImageStore.register(_:as:surface:)`).
    private let readsSurfaces: Bool
    /// One pass per CLIP, keyed by the clip's layer, made the first time it
    /// is asked for and closed once the clip is off screen.
    ///
    /// Not one per recording: an edit cuts the same recording into many
    /// clips, and two of them are on screen at once in a dissolve between two
    /// pieces of one take, or with a clip of it as B-roll over another. Shared,
    /// the one pass was asked for two moments in turn and started again from
    /// the nearest key frame every time: 385 passes for 30 seconds of the
    /// reference edit, most of the export spent waiting on the decoder
    /// (measured 2026-11-16).
    private var streams: [UUID: MovieFrameStream] = [:]
    /// Recordings a single pass cannot read the right way up, left to the
    /// image generator.
    private var unstreamable = Set<UUID>()
    /// Frames this export put in the store, which are this export's to remove.
    ///
    /// Held without a lock because the writer asks for one frame at a time and
    /// waits for it (`DocumentMovieWriter.writePictures`), so there is never a
    /// second caller in here; the `@unchecked` above is that promise written
    /// down. What it must NOT do is outlive the write, which is why the export
    /// gives the store back in a `defer`.
    private var borrowed: [ImageRef] = []

    /// - size: what each picture comes out at, the canvas's own size when left
    ///   out. The document is drawn AT that size, never drawn big and shrunk.
    init(document: PhotonzDocument, store: ImageStore, movieURLs: [UUID: URL],
         size: CGSize? = nil, streaming: Bool = false, smoothsStreamed: Bool = false,
         readsSurfaces: Bool = true) {
        self.readsSurfaces = readsSurfaces
        self.document = document
        self.store = store
        self.movieURLs = movieURLs
        self.streaming = streaming
        self.smoothsStreamed = smoothsStreamed
        let canvas = document.canvasSize
        if let size, canvas.width > 0, size.width > 0, abs(size.width - canvas.width) >= 1 {
            scale = size.width / canvas.width
        } else {
            scale = 1
        }
    }

    /// The recording's frame at a moment of it, off one pass through the file
    /// where that can be had, and sought on its own otherwise.
    ///
    /// A frame read off a stream comes with the surface it was decoded onto,
    /// which a render reads straight off the GPU, unless it is smoothed: then
    /// the picture is a new one the surface does not hold.
    private func decode(_ request: MovieFrameRequest, at url: URL) async
        -> (image: CGImage, surface: CVPixelBuffer?)? {
        let id = request.movie.id
        if streaming, !unstreamable.contains(id) {
            let clip = request.layerID
            if streams[clip] == nil {
                if let stream = await MovieFrameStream(url: url) {
                    streams[clip] = stream
                } else {
                    unstreamable.insert(id)
                }
            }
            if let read = streams[clip]?.frameAndSurface(atMS: request.sourceMS) {
                if smoothsStreamed {
                    return MovieDecoder.smoothed(read.image, of: request.movie).map { ($0, nil) }
                }
                return (read.image, read.surface)
            }
        }
        return await MovieDecoder.shared.frame(of: request.movie, at: url,
                                               sourceMS: request.sourceMS).map { ($0, nil) }
    }

    /// What the document looks like at a moment, with every frame it needs
    /// fetched first.
    func frame(atMS ms: Int) async -> CGImage? {
        let shown = await fetched(atMS: ms)
        // Nothing on screen at this moment is a PICTURE — an empty one — not a
        // frame that could not be made. A document whose music runs past its
        // last clip ends in darkness, which is what the window shows, rather
        // than in the last frame held for six seconds nobody asked for.
        let picture = (scale == 1 ? renderer.render(shown, store: store)
                                  : renderer.render(shown, store: store, scale: scale)) ?? blank()
        dropOldFrames()
        return picture
    }

    /// What the document looks like at a moment, drawn straight into `buffer`
    /// (a 32BGRA buffer the size the pictures come out at) rather than handed
    /// back as a picture: what an MP4 is written from, so the frame never
    /// leaves the GPU between being drawn and being encoded
    /// (`DocumentRenderer.render(_:store:scale:into:)`). The same pixels
    /// `frame(atMS:)` makes, laid on black.
    func draw(atMS ms: Int, into buffer: CVPixelBuffer) async -> Bool {
        let shown = await fetched(atMS: ms)
        let drawn = renderer.render(shown, store: store, scale: scale, into: buffer)
        dropOldFrames()
        return drawn
    }

    /// The document at a moment, with every recording frame it needs fetched
    /// into the store first.
    private func fetched(atMS ms: Int) async -> PhotonzDocument {
        let requests = document.movieFrames(atTimeMS: ms)
        // A clip off screen at this moment is done with until the write comes
        // back round to it, and its pass holds decoded frames: let it go.
        if !streams.isEmpty {
            let onScreen = Set(requests.map(\.layerID))
            for clip in streams.keys where !onScreen.contains(clip) {
                streams[clip] = nil
            }
        }
        for request in requests {
            // The window reads frames at the size it SHOWS them, so one it is
            // holding may be smaller than the recording: a file is written
            // from the recording's own size, never from the preview.
            let filed = store.image(for: request.ref)
            if let filed, CGFloat(filed.width) >= request.movie.pixelSize.width - 1 { continue }
            guard let url = movieURLs[request.movie.id],
                  let read = await decode(request, at: url)
            else { continue }
            if readsSurfaces, let surface = read.surface {
                store.register(read.image, as: request.ref, surface: surface)
            } else {
                store.register(read.image, as: request.ref)
            }
            // One the window already held stays the window's, now sharper;
            // only a frame this export brought in is taken back out.
            if filed == nil { borrowed.append(request.ref) }
        }
        return document.drawn(atTimeMS: ms)
    }

    /// One frame as the bytes of a PNG file, made and encoded off the main
    /// actor: what a still export writes, and what the sheet weighs to say
    /// what it will weigh.
    func png(atMS ms: Int) async -> Data? {
        guard let picture = await frame(atMS: ms) else { return nil }
        return ImageCodec.encode(picture, format: .png)
    }

    /// An empty frame the size the pictures come out at.
    private func blank() -> CGImage? {
        let width = Int((document.canvasSize.width * scale).rounded())
        let height = Int((document.canvasSize.height * scale).rounded())
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)
                                          ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        return context.makeImage()
    }

    /// Keep only the last couple of frames: enough that two moments landing on
    /// the same decoded frame do not decode it twice, small enough that a long
    /// export never grows.
    private func dropOldFrames() {
        while borrowed.count > 2 { store.remove(borrowed.removeFirst()) }
    }

    /// Everything this export borrowed, given back.
    func putTheStoreBack() {
        for ref in borrowed { store.remove(ref) }
        borrowed = []
    }
}
