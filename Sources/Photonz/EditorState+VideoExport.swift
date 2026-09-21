import AppKit
import CoreGraphics
import Foundation
import PhotonzCore
import PhotonzMedia
import PhotonzRender

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
    var videoExportSource: RecordingExport.Source {
        let seconds = Double(documentLengthMS) / 1000
        let untouched = document?.untouchedRecording
        let bytes = untouched
            .flatMap { MovieLibrary.shared.url(for: $0) }
            .flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize } ?? 0
        return RecordingExport.Source(sourceDuration: seconds, keptDuration: seconds,
                                      sourceSize: document?.canvasSize ?? .zero,
                                      fileBytes: bytes, isEdited: untouched == nil)
    }

    /// **Export…** on a document that has time: pick a place, then write it.
    func exportVideo(format: RecordingFormat, quality: VideoExportQuality) {
        guard let document, document.hasTime else { return }
        RecordingExportMemory.remember(format: format, quality: quality)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.savePanelType]
        panel.nameFieldStringValue = RecordingExport.suggestedFileName(
            recording: videoExportName, format: format)
        panel.canCreateDirectories = true
        panel.message = "Write what plays in this window out as a file"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        startVideoExport(format: format, quality: quality, to: url)
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
    func startVideoExport(format: RecordingFormat, quality: VideoExportQuality, to url: URL) {
        guard videoExport == nil else { return }
        pauseDocument()
        let run = VideoExportRun(fileName: url.lastPathComponent)
        videoExport = run
        videoExportTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await writeVideo(format: format, quality: quality, to: url) { done in
                    Task { @MainActor in run.fraction = done }
                }
                videoExport = nil
                videoExportTask = nil
                raiseCanvasNotice(.videoWritten(file: url.lastPathComponent))
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
    func writeVideo(format: RecordingFormat, quality: VideoExportQuality, to url: URL,
                    onProgress: (@Sendable (Double) -> Void)? = nil) async throws {
        guard let document, document.hasTime else { throw CocoaError(.fileNoSuchFile) }

        // The recording nobody has touched is already the answer: copy the file
        // rather than photographing it back into existence.
        if format == .mp4, let movie = document.untouchedRecording,
           let source = MovieLibrary.shared.url(for: movie) {
            try? FileManager.default.removeItem(at: url)
            try FileManager.default.copyItem(at: source, to: url)
            onProgress?(1)
            return
        }

        let plan = DocumentVideoExport.plan(durationMS: document.documentDurationMS,
                                            canvasSize: document.canvasSize,
                                            format: format, quality: quality)
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
    var fraction: Double = 0

    init(fileName: String) {
        self.fileName = fileName
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
            guard store.image(for: request.ref) == nil,
                  let url = movieURLs[request.movie.id],
                  let picture = await MovieDecoder.shared.frame(of: request.movie, at: url,
                                                                sourceMS: request.sourceMS)
            else { continue }
            store.register(picture, as: request.ref)
            borrowed.append(request.ref)
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
