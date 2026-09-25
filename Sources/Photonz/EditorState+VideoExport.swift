import AppKit
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
    var videoExportSource: RecordingExport.Source {
        let seconds = Double(documentLengthMS) / 1000
        let untouched = document?.untouchedRecording
        let bytes = untouched
            .flatMap { MovieLibrary.shared.url(for: $0) }
            .flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize } ?? 0
        let canvas = document?.canvasSize ?? .zero
        return RecordingExport.Source(sourceDuration: seconds, keptDuration: seconds,
                                      sourceSize: canvas,
                                      fileBytes: bytes, isEdited: untouched == nil,
                                      sourceFPS: DocumentVideoExport.movieFPS,
                                      hasAudio: document?.audioMix().isEmpty == false,
                                      playheadTime: Double(documentTimeMS) / 1000,
                                      footageBytesPerSecond: untouched == nil
                                        ? RecordingExport.footageBytesPerSecond(footage, at: canvas)
                                        : nil,
                                      captionedSeconds: document?.captionedSeconds ?? 0)
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
    ///   would weigh (`ExportWeigh`). An animated export lands at the same size
    ///   every time, so that file IS the export and is moved into place rather
    ///   than written again.
    func exportVideo(format: RecordingFormat, quality: VideoExportQuality,
                     size: VideoExportSize? = nil,
                     weighed: URL? = nil, captions: CaptionExport = .burnedIn) {
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
                         weighed: weighed, captions: captions)
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
                          weighed: URL? = nil, captions: CaptionExport = .burnedIn) {
        guard videoExport == nil else { return }
        // Already written, to answer what it would weigh: move it into place
        // and there is nothing to watch.
        if captions == .burnedIn, let weighed, AppCoordinator.putWeighedFileInPlace(weighed, at: url) {
            keptByExport()
            raiseCanvasNotice(.videoWritten(file: url.lastPathComponent))
            return
        }
        pauseDocument()
        let run = VideoExportRun(fileName: url.lastPathComponent, title: format.writingTitle)
        videoExport = run
        videoExportTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await writeVideo(format: format, quality: quality, size: size, to: url,
                                     captions: captions) { done in
                    Task { @MainActor in run.fraction = done }
                }
                videoExport = nil
                videoExportTask = nil
                keptByExport()
                raiseCanvasNotice(.videoWritten(file: url.lastPathComponent))
                // The words as a file beside the film, named after it, where
                // a player looks for them.
                if let file = captions.file { writeCaptionsBeside(film: url, as: file) }
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
    func writeVideo(format: RecordingFormat, quality: VideoExportQuality,
                    size: VideoExportSize? = nil, to url: URL,
                    captions: CaptionExport = .burnedIn,
                    onProgress: (@Sendable (Double) -> Void)? = nil) async throws {
        guard let document = document?.forExport(captions: captions), document.hasTime
        else { throw CocoaError(.fileNoSuchFile) }

        // The recording nobody has touched is already the answer: copy the file
        // rather than photographing it back into existence. Only at the top
        // choice: the two below it are asking for a SMALLER file than the one
        // on disk, and that cannot be done by copying it
        // (`RecordingExport.copiesVerbatim`), and neither is a size that
        // shrinks the picture.
        if format == .mp4, quality == .high,
           !(size?.shrinks(document.canvasSize) ?? false),
           let movie = document.untouchedRecording,
           let source = MovieLibrary.shared.url(for: movie) {
            try? FileManager.default.removeItem(at: url)
            try FileManager.default.copyItem(at: source, to: url)
            onProgress?(1)
            return
        }

        let plan = DocumentVideoExport.plan(durationMS: document.documentDurationMS,
                                            canvasSize: document.canvasSize,
                                            format: format, quality: quality, size: size)
        let mix = document.audioMix()
        let soundURLs = SoundLibrary.shared.urls(for: mix)
        let pictures = DocumentFrames(document: document, store: store,
                                      movieURLs: MovieLibrary.shared.urls(in: document))
        let frames: DocumentMovieWriter.FrameSource = { ms in await pictures.frame(atMS: ms) }
        defer { pictures.putTheStoreBack() }

        if format == .mp4 {
            try await DocumentMovieWriter.write(plan: plan, mix: mix, soundURLs: soundURLs,
                                                to: url, frames: frames, onProgress: onProgress)
        } else {
            try await DocumentMovieWriter.writeAnimated(plan: plan, format: format, to: url,
                                                        frames: frames, onProgress: onProgress)
        }
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
    /// Frames this export put in the store, which are this export's to remove.
    ///
    /// Held without a lock because the writer asks for one frame at a time and
    /// waits for it (`DocumentMovieWriter.writePictures`), so there is never a
    /// second caller in here; the `@unchecked` above is that promise written
    /// down. What it must NOT do is outlive the write, which is why the export
    /// gives the store back in a `defer`.
    private var borrowed: [ImageRef] = []

    init(document: PhotonzDocument, store: ImageStore, movieURLs: [UUID: URL]) {
        self.document = document
        self.store = store
        self.movieURLs = movieURLs
    }

    /// What the document looks like at a moment, with every frame it needs
    /// fetched first.
    func frame(atMS ms: Int) async -> CGImage? {
        for request in document.movieFrames(atTimeMS: ms) {
            // The window reads frames at the size it SHOWS them, so one it is
            // holding may be smaller than the recording: a file is written
            // from the recording's own size, never from the preview.
            let filed = store.image(for: request.ref)
            if let filed, CGFloat(filed.width) >= request.movie.pixelSize.width - 1 { continue }
            guard let url = movieURLs[request.movie.id],
                  let picture = await MovieDecoder.shared.frame(of: request.movie, at: url,
                                                                sourceMS: request.sourceMS)
            else { continue }
            store.register(picture, as: request.ref)
            // One the window already held stays the window's, now sharper;
            // only a frame this export brought in is taken back out.
            if filed == nil { borrowed.append(request.ref) }
        }
        let shown = document.drawn(atTimeMS: ms)
        // Nothing on screen at this moment is a PICTURE — an empty one — not a
        // frame that could not be made. A document whose music runs past its
        // last clip ends in darkness, which is what the window shows, rather
        // than in the last frame held for six seconds nobody asked for.
        let picture = renderer.render(shown, store: store) ?? blank()
        dropOldFrames()
        return picture
    }

    /// One frame as the bytes of a PNG file, made and encoded off the main
    /// actor: what a still export writes, and what the sheet weighs to say
    /// what it will weigh.
    func png(atMS ms: Int) async -> Data? {
        guard let picture = await frame(atMS: ms) else { return nil }
        return ImageCodec.encode(picture, format: .png)
    }

    /// An empty frame the size of the canvas.
    private func blank() -> CGImage? {
        let width = Int(document.canvasSize.width.rounded())
        let height = Int(document.canvasSize.height.rounded())
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
