import AVFoundation
import AppKit
import CoreImage
import Foundation
import PhotonzCore
import PhotonzRender
import Synchronization

// Where a clip's pixels actually come from (`docs/design/video.md` §4).
//
// The document says *which recording, at which moment*; this says *here is that
// frame*. The split is the same one pictures have always had — a document holds
// an `ImageRef`, `ImageStore` holds the bitmap — and keeping it is what lets a
// clip be an ordinary picture layer everywhere else in the app.
//
// Nothing here knows about time, trims or pieces. It is handed
// `MovieFrameRequest`s and it fills them.

/// Which file each recording in a document is, for the length of this run.
///
/// A `MovieRef` is an identity, not a path, exactly as an `ImageRef` is. This
/// is the one place that identity is turned back into a file, and it is app
/// state rather than document state: a document that travels to another machine
/// travels with its media beside it, which is `video-share`'s problem and not
/// this one's.
@MainActor
final class MovieLibrary {
    static let shared = MovieLibrary()

    private var urls: [UUID: URL] = [:]
    private var refsByURL: [URL: MovieRef] = [:]
    /// Where the pointer went in each recording, read from beside its file
    /// when the recording is opened (`PointerTrack.swift`). Absent for a
    /// recording made before Photonz kept it, or brought in from elsewhere.
    private var pointerTracks: [UUID: PointerTrack] = [:]

    /// Read a recording's size and length off the file and hand back the
    /// reference a document can hold. The same file asked for twice is the same
    /// reference, so re-opening a recording re-uses whatever frames of it are
    /// already decoded.
    ///
    /// `id` is the identity to read it under, for a recording that was opened
    /// before its file landed and already has one (`ClosingRecording`).
    func movie(at url: URL, as id: UUID? = nil) async -> MovieRef? {
        let standardized = url.standardizedFileURL
        if let known = refsByURL[standardized], id == nil || known.id == id { return known }
        let asset = AVURLAsset(url: standardized)
        guard let duration = try? await asset.load(.duration),
              let track = try? await asset.loadTracks(withMediaType: .video).first,
              let size = try? await track.load(.naturalSize),
              let transform = try? await track.load(.preferredTransform)
        else { return nil }
        // A recording made in portrait carries its rotation on the track, and
        // the picture the canvas gets is the rotated one, so the document's
        // canvas has to be that size too.
        let shown = size.applying(transform)
        // Whether it has a sound track decides whether the app offers to take
        // the sound off it, so it is read once, here, with everything else
        // about the file (`SoundClip.swift`).
        let hasSound = (try? await asset.loadTracks(withMediaType: .audio))?.isEmpty == false
        let ref = MovieRef(id: id ?? UUID(),
                           pixelSize: CGSize(width: abs(shown.width), height: abs(shown.height)),
                           durationMS: Int((duration.seconds * 1000).rounded()),
                           hasSound: hasSound)
        urls[ref.id] = standardized
        refsByURL[standardized] = ref
        pointerTracks[ref.id] = PointerTrackSidecar.load(for: standardized)
        // A recording's sound is the same file as its picture, so the sound
        // library can answer for it from the moment the recording is opened.
        if let sound = ref.soundRef { SoundLibrary.shared.link(sound, to: standardized) }
        return ref
    }

    func url(for movie: MovieRef) -> URL? { urls[movie.id] }

    /// Where the pointer went and every click while this recording was made,
    /// or nil when nothing was kept.
    func pointerTrack(for movie: MovieRef) -> PointerTrack? { pointerTracks[movie.id] }

    #if PHOTONZ_PLAYTEST
    /// A walk giving a recording a pointer path, as if the recorder had kept
    /// one (`PlaytestZoom`).
    func setPointerTrackForPlaytest(_ track: PointerTrack, for movie: MovieRef) {
        pointerTracks[movie.id] = track
    }
    #endif

    /// File a reference a saved project already holds against the file its
    /// media table found for it (`ProjectMedia`), so the project's clips play
    /// under the ids they were saved with. Nothing is read off the file: the
    /// project already knows its size and length. A file this run has opened
    /// under another reference keeps that one for anybody opening it afresh.
    func adopt(_ movie: MovieRef, at url: URL) {
        let standardized = url.standardizedFileURL
        urls[movie.id] = standardized
        if refsByURL[standardized] == nil { refsByURL[standardized] = movie }
        pointerTracks[movie.id] = PointerTrackSidecar.load(for: standardized)
        if let sound = movie.soundRef { SoundLibrary.shared.link(sound, to: standardized) }
    }

    /// Every recording this run plays from `old`, played from `new` from now
    /// on: a save into history keeps the recording as it was made in the
    /// originals folder and is about to write the edit over the file the
    /// window opened (`HistoryVideoSave`). The two files are the same bytes
    /// when this runs, so nothing on screen changes, and the readers already
    /// open on the old path are let go so none of them reads the edit.
    func relocate(from old: URL, to new: URL) {
        let from = old.standardizedFileURL
        let to = new.standardizedFileURL
        let moved = urls.filter { $0.value == from }.map(\.key)
        guard !moved.isEmpty else { return }
        for id in moved {
            urls[id] = to
            Task { await MovieDecoder.shared.forget(id) }
        }
        if let movie = refsByURL.removeValue(forKey: from) { refsByURL[to] = movie }
        // A recording's sound is the same file, filed under the same id.
        SoundLibrary.shared.relocate(from: from, to: to)
    }

    /// Whether any recording this run plays is the file at `url`.
    func plays(_ url: URL, in document: PhotonzDocument) -> Bool {
        let file = url.standardizedFileURL
        return urls(in: document).values.contains(file)
    }

    /// The same question asked with an id on its own, which is what a
    /// recording's SOUND has: a clip's sound shares the recording's identity
    /// because it is the same file (`SoundClip.swift`).
    func url(forID id: UUID) -> URL? { urls[id] }

    /// The reference this file already has, if anything has opened it.
    func existingMovie(at url: URL) -> MovieRef? { refsByURL[url.standardizedFileURL] }

    /// Which file every recording in a document is, taken once so a job that
    /// runs off the main actor — writing a video out — never has to come back
    /// here to ask (`EditorState+VideoExport`).
    func urls(in document: PhotonzDocument) -> [UUID: URL] {
        var found: [UUID: URL] = [:]
        for layer in document.allLayers {
            guard let movie = layer.movie, found[movie.id] == nil,
                  let url = urls[movie.id] else { continue }
            found[movie.id] = url
        }
        return found
    }
}

/// The one place an `AVAssetImageGenerator` lives.
///
/// An actor rather than a lock, because a generator is neither `Sendable` nor
/// cheap to make: a few per recording, kept here, and every decode runs off the
/// main actor so a frame landing never stalls a drag.
actor MovieDecoder {
    static let shared = MovieDecoder()

    /// How many generators read one recording at one size side by side.
    ///
    /// One generator reads one frame at a time, and a frame of a full-screen
    /// Retina recording costs about 40ms to seek to and read, which is longer
    /// than the 33ms it is on screen for: playing one fell further behind with
    /// every frame and flickered. Measured on a real 3456x2234 recording
    /// (2026-09-23): one generator read 60 frames in about 2.4s, four side by
    /// side read them in 0.36s. Reading smaller does not help, the time is in
    /// the decode, so the answer is more hands, not smaller frames.
    static let lanes = 4

    private struct Key: Hashable {
        let movie: UUID
        let width: Int
        let height: Int
    }

    private var generators: [Key: [AVAssetImageGenerator]] = [:]
    private var nextLane: [Key: Int] = [:]

    /// Let go of every reader open on a recording, so the next frame asked
    /// for opens its file afresh where `MovieLibrary` now says it is.
    func forget(_ movie: UUID) {
        for key in generators.keys where key.movie == movie {
            generators[key] = nil
            nextLane[key] = nil
        }
        pictureGenerators[movie] = nil
        nextPictureLane[movie] = nil
    }

    /// One frame of one recording, or nil where the file will not give it up.
    ///
    /// `size` is the most it is worth reading the frame at, the recording's
    /// own size when left out, which is what writing a file wants.
    ///
    /// The callback form rather than the `async` one on purpose: a generator is
    /// not `Sendable`, and awaiting a method ON it would carry it across an
    /// isolation boundary. This way it never leaves the actor and only the
    /// finished picture comes back.
    func frame(of movie: MovieRef, at url: URL, sourceMS: Int, size: CGSize? = nil) async -> CGImage? {
        let generator = generator(for: movie, at: url, size: size ?? movie.pixelSize)
        let time = CMTime(value: CMTimeValue(sourceMS), timescale: 1000)
        return await withCheckedContinuation { continuation in
            generator.generateCGImageAsynchronously(for: time) { image, _, _ in
                continuation.resume(returning: image)
            }
        }
    }

    /// The next generator in line for this recording at this size, made the
    /// first time one is asked for.
    private func generator(for movie: MovieRef, at url: URL, size: CGSize) -> AVAssetImageGenerator {
        let key = Key(movie: movie.id, width: Int(size.width.rounded()), height: Int(size.height.rounded()))
        if generators[key] == nil {
            // A zoom moved the size frames are read at: the lanes for the size
            // before it are done with. The recording's own size stays, since
            // that is what writing a file out reads at.
            let full = Key(movie: movie.id, width: Int(movie.pixelSize.width.rounded()),
                           height: Int(movie.pixelSize.height.rounded()))
            for stale in generators.keys where stale.movie == movie.id && stale != full {
                generators[stale] = nil
                nextLane[stale] = nil
            }
        }
        let lanes = generators[key] ?? (0..<Self.lanes).map { _ in
            Self.makeGenerator(url: url, size: size)
        }
        generators[key] = lanes
        let lane = nextLane[key, default: 0]
        nextLane[key] = (lane + 1) % lanes.count
        return lanes[lane]
    }

    // MARK: Pictures along a clip

    /// How many generators read the small pictures along a clip on the
    /// timeline (`ClipFilmstripFrames`). Fewer than the playhead has, and
    /// apart from its lanes, so a zoomed timeline filling in never makes the
    /// picture under the playhead wait, and never throws away the playhead's
    /// generators the way a new size for the SAME lanes would.
    static let pictureLanes = 2

    private var pictureGenerators: [UUID: [AVAssetImageGenerator]] = [:]
    private var nextPictureLane: [UUID: Int] = [:]

    /// One small picture of a recording for the timeline, at most `size`.
    func picture(of movie: MovieRef, at url: URL, sourceMS: Int, size: CGSize) async -> CGImage? {
        let lanes = pictureGenerators[movie.id] ?? (0..<Self.pictureLanes).map { _ in
            Self.makeGenerator(url: url, size: size)
        }
        pictureGenerators[movie.id] = lanes
        let lane = nextPictureLane[movie.id, default: 0]
        nextPictureLane[movie.id] = (lane + 1) % lanes.count
        let generator = lanes[lane]
        let time = CMTime(value: CMTimeValue(sourceMS), timescale: 1000)
        return await withCheckedContinuation { continuation in
            generator.generateCGImageAsynchronously(for: time) { image, _, _ in
                continuation.resume(returning: image)
            }
        }
    }

    private static func makeGenerator(url: URL, size: CGSize) -> AVAssetImageGenerator {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        // Half a frame either way: exact seeking makes every frame a full
        // decode from the nearest keyframe, and half a frame of slop is
        // invisible while costing a fraction of the time.
        let slop = CMTime(value: CMTimeValue(MovieRef.frameStepMS / 2), timescale: 1000)
        generator.requestedTimeToleranceBefore = slop
        generator.requestedTimeToleranceAfter = slop
        // Read at the size it is shown, never bigger than the recording: a
        // full-screen Retina frame is 30MB, and a window showing it at half
        // size has no use for three quarters of that.
        generator.maximumSize = size
        return generator
    }
}

/// Reads a stretch of a recording in one pass and hands over each grid frame
/// in it, small (`MovieSweep`).
///
/// Not on `MovieDecoder`'s actor: a pass runs for a couple of hundred
/// milliseconds, and the actor answering a sharp frame must never wait behind
/// it. Nothing here outlives one pass, so nothing is shared.
enum MovieSweeper {

    private static let context = CIContext(options: [.cacheIntermediates: false])

    /// Read `frames` of `movie` from start to end, handing each grid frame to
    /// `deliver` at most `size` big, as soon as it is read. Stops as soon as
    /// the task is cancelled. Answers false when the recording cannot be read
    /// this way at all (a turn that is not a right angle), so the caller goes
    /// back to reading exact frames.
    ///
    /// `waitsAt` is told, before each sample is read, the first grid frame not
    /// handed over yet, and answers whether to wait before reading on: a pass
    /// playing ahead of the playhead waits there for it (`MoviePlayPass`).
    static func sweep(movie: MovieRef, url: URL, frames: ClosedRange<Int>, size: CGSize,
                      waitsAt: (@Sendable (Int) -> Bool)? = nil,
                      deliver: @escaping @Sendable (Int, CGImage) -> Void) async -> Bool {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let transform = try? await track.load(.preferredTransform),
              let orientation = orientation(of: transform),
              let reader = try? AVAssetReader(asset: asset)
        else { return false }
        let step = MovieRef.frameStepMS
        reader.timeRange = CMTimeRange(
            start: CMTime(value: CMTimeValue(frames.lowerBound * step), timescale: 1000),
            end: CMTime(value: CMTimeValue((frames.upperBound + 1) * step), timescale: 1000))
        // The decoder's own format: asking for RGB made the pass three times
        // slower, and only the frames kept are converted.
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return false }
        reader.add(output)
        guard reader.startReading() else { return false }

        var grid = MovieSweepGrid(frames: frames)
        var previous: CVPixelBuffer?
        func hand(_ indices: [Int], _ buffer: CVPixelBuffer?) {
            guard !indices.isEmpty, let buffer,
                  let image = picture(of: buffer, orientation: orientation, size: size) else { return }
            for index in indices { deliver(index, image) }
        }
        // Stopped between samples only: `cancelReading` from another thread
        // while a sample is being read crashes (tried 2026-09-27).
        while !Task.isCancelled {
            if let waitsAt, waitsAt(grid.nextFrame) {
                try? await Task.sleep(for: .milliseconds(4))
                continue
            }
            guard let sample = output.copyNextSampleBuffer() else { break }
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            let ms = CMSampleBufferGetPresentationTimeStamp(sample).seconds * 1000
            hand(grid.arrived(atMS: ms), previous)
            previous = buffer
        }
        if Task.isCancelled {
            reader.cancelReading()
        } else if reader.status == .completed {
            hand(grid.finished(), previous)
        }
        return true
    }

    /// One decoded frame, turned the way the recording is shown and at most
    /// `size` big, in the recording's own colours.
    private static func picture(of buffer: CVPixelBuffer, orientation: CGImagePropertyOrientation,
                                size: CGSize) -> CGImage? {
        var image = CIImage(cvPixelBuffer: buffer).oriented(orientation)
        let scale = min(1, size.width / max(1, image.extent.width))
        image = image.samplingLinear().transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let extent = image.extent.integral
        let colors = CVBufferCopyAttachments(buffer, .shouldPropagate)
            .flatMap { CVImageBufferCreateColorSpaceFromAttachments($0)?.takeRetainedValue() }
            ?? CGColorSpace(name: CGColorSpace.sRGB)
        return context.createCGImage(image, from: extent, format: .RGBA8, colorSpace: colors)
    }

    /// The four right-angle turns a recording's track can carry, and nil for
    /// anything else.
    private static func orientation(of transform: CGAffineTransform) -> CGImagePropertyOrientation? {
        switch (transform.a.rounded(), transform.b.rounded(), transform.c.rounded(), transform.d.rounded()) {
        case (1, 0, 0, 1): return .up
        case (0, 1, -1, 0): return .right
        case (0, -1, 1, 0): return .left
        case (-1, 0, 0, -1): return .down
        default: return nil
        }
    }
}

/// Decodes the frames one window is asking for and files them in its
/// `ImageStore` under the reference the document already points at.
///
/// **Bounded on purpose.** A 1080p frame is eight megabytes, so a cache that
/// simply grew would eat a gigabyte in two seconds of playing. It keeps the
/// most recent `frameBudget` frames and drops the rest, which is enough for the
/// playhead to move smoothly and small enough to leave the machine alone.
@MainActor
final class MovieFrameFetcher {

    /// How many decoded frames one window keeps. Sixteen 1080p frames is about
    /// 130MB, which is the most a preview is worth. The ones let go are the
    /// farthest from the playhead, so a scrub that turns round finds the
    /// frames it has just shown still there.
    static let frameBudget = 16

    /// How far ahead of the playhead frames are read while it plays. A
    /// quarter of a second: enough that the four lanes of `MovieDecoder` are
    /// always busy, and well inside `frameBudget` so a frame read ahead is
    /// never dropped before it is shown.
    static let playAheadFrames = 8

    /// How many moves ahead of a hand scrubbing frames are read, at the
    /// stride the hand is moving. Few, because a hand turns round: a frame read
    /// for a move that never comes is a read the frame under the hand waited
    /// behind.
    static let scrubAheadMoves = 3

    private struct Resident {
        let ref: ImageRef
        let movie: UUID
        let frameIndex: Int
        /// Read in passing for a moving hand, small (`MovieSweep`). Counted
        /// against its own budget, since a stretch of them costs about as much
        /// as a handful of sharp ones.
        var rough = false
    }

    /// The one-pass read running for each recording, and which grid frames it
    /// covers.
    private struct Sweep {
        let token: UUID
        let frames: ClosedRange<Int>
        let task: Task<Void, Never>
    }
    private var sweeps: [UUID: Sweep] = [:]
    /// Recordings a one-pass read cannot turn the right way up, which a moving
    /// hand reads frame by frame as before.
    private var unsweepable = Set<UUID>()

    /// Where a pass playing ahead of the playhead has got to, and where the
    /// playhead is, shared with the pass as it reads off the main actor.
    private final class PlayMark: Sendable {
        private let state: Mutex<(playhead: Int, reached: Int)>
        init(playhead: Int) { state = Mutex((playhead, playhead)) }
        var playhead: Int {
            get { state.withLock { $0.playhead } }
            set { state.withLock { $0.playhead = newValue } }
        }
        var reached: Int {
            get { state.withLock { $0.reached } }
            set { state.withLock { $0.reached = newValue } }
        }
        /// Note how far the pass has got, and answer whether it is far enough
        /// ahead of the playhead to wait.
        func passed(_ next: Int) -> Bool {
            state.withLock {
                $0.reached = next
                return MoviePlayPass.shouldWait(next: next, playhead: $0.playhead)
            }
        }
    }

    /// The pass reading ahead of a playing playhead in each recording, at the
    /// size the canvas shows it (`MoviePlayPass`).
    private struct PlayPass {
        let token: UUID
        let frames: ClosedRange<Int>
        let width: Int
        let mark: PlayMark
        let task: Task<Void, Never>
    }
    private var playPasses: [UUID: PlayPass] = [:]

    private let store: ImageStore
    /// Decoded frames, in the order they landed.
    private var resident: [Resident] = []
    /// Which frames are being read and how big, so a frame asked for bigger
    /// while a smaller read of it is under way is read again rather than left
    /// at the smaller size (`MovieFrameReads`).
    private var reads = MovieFrameReads()

    private struct Read: Sendable {
        let request: MovieFrameRequest
        let size: CGSize
        let url: URL
    }
    /// Reads waiting to start, and how many are running: one per lane of the
    /// decoder, so a read asked for now starts the moment a lane is free
    /// rather than queuing inside the decoder behind one the hand has left.
    private var queue = MovieFrameQueue<Read>(capacity: MovieDecoder.lanes)
    /// Which frame each recording's playhead is on, last anybody asked.
    private var focus: [UUID: Int] = [:]

    /// Called on the main actor whenever a frame lands, so the canvas can
    /// redraw with a picture it did not have a moment ago.
    var onFrameLanded: (() -> Void)?

    /// The frames most recently let go to stay inside the budget, newest last.
    /// A walk reads it to tell a frame that was never read from one that was
    /// read and then dropped (`expectScrubSmooth`).
    private(set) var dropped: [UUID] = []

    init(store: ImageStore) {
        self.store = store
    }

    /// Whether this frame is already decoded and filed.
    func has(_ ref: ImageRef) -> Bool { store.image(for: ref) != nil }

    /// Every frame this window has read and still holds, which is what the
    /// canvas draws a late moment with (`MovieFramesInHand.swift`). Read off
    /// the store rather than remembered, so a frame something else took back
    /// out of it is never offered as one to show.
    var inHand: MovieFramesInHand {
        var hand = MovieFramesInHand()
        for frame in resident where has(frame.ref) {
            hand.insert(movie: frame.movie, frameIndex: frame.frameIndex)
        }
        return hand
    }

    /// Ask for everything a moment needs, each frame read at the size it comes
    /// back from `size`. Frames already filed, or already being read, at least
    /// that big cost nothing; a frame filed or being read smaller (the canvas
    /// was zoomed in, or fitted to its window, since) is read again, and the
    /// smaller one keeps showing until the bigger one lands.
    ///
    /// Each call is what the playhead wants NOW, most wanted first: the frame
    /// under it, then the ones it is heading for. Only a few reads run at once
    /// (`MovieFrameQueue`), and any read the last call asked for that has not
    /// started yet is forgotten, so a hand flinging the playhead across a clip
    /// never leaves a queue of frames it has already passed standing between
    /// it and the frame it is on.
    ///
    /// While a hand is moving the playhead (`handMoving`), nothing is read one
    /// exact frame at a time: the stretch it is heading into is read in one
    /// pass instead and filed small (`MovieSweep`), and a frame already in
    /// hand at any size is good enough until the hand holds still. Any other
    /// call stops those passes, so the sharp frame it asks for has the decoder
    /// to itself.
    ///
    /// While the clock plays it forwards (`playing`), the frames ahead of the
    /// playhead are read in one pass that keeps a little ahead of it, sharp,
    /// rather than one at a time (`MoviePlayPass`); only a frame the pass will
    /// not reach soon, across a cut, is read on its own. Any other call stops
    /// those passes.
    func fetch(_ requests: [MovieFrameRequest], size: (MovieFrameRequest) -> CGSize,
               handMoving: Bool = false, backward: Bool = false, playing: Bool = false) {
        if !handMoving { stopSweeps() }
        let playsAhead = playing && !handMoving && !backward
        if !playsAhead { stopPlayPasses() }
        var wanted: [Read] = []
        var asked = Set<UUID>()
        var focused = Set<UUID>()
        for request in requests where asked.insert(request.ref.id).inserted {
            let width = size(request)
            guard let url = MovieLibrary.shared.url(for: request.movie) else { continue }
            // The first frame asked of a recording is where its playhead is,
            // which is what the budget keeps the frames around.
            if focused.insert(request.movie.id).inserted {
                let frame = request.movie.frameIndex(atSourceMS: request.sourceMS)
                focus[request.movie.id] = frame
                if handMoving, !unsweepable.contains(request.movie.id) {
                    sweep(request.movie, url: url, around: frame, backward: backward,
                          size: MovieSweep.roughSize(for: width))
                }
                if playsAhead, !unsweepable.contains(request.movie.id) {
                    play(request.movie, url: url, at: frame, size: width)
                }
            }
            if handMoving, !unsweepable.contains(request.movie.id) { continue }
            if let filed = filedWidth(request.ref), filed >= width.width - 1 { continue }
            if playsAhead, let pass = playPasses[request.movie.id],
               pass.width >= Int(width.width.rounded()) - 1,
               MoviePlayPass.covers(frame: request.movie.frameIndex(atSourceMS: request.sourceMS),
                                    running: pass.frames, reached: pass.mark.reached,
                                    playhead: pass.mark.playhead) { continue }
            if handMoving, has(request.ref) { continue }
            wanted.append(Read(request: request, size: width, url: url))
        }
        queue.replace(with: wanted)
        startReads()
    }

    // MARK: Reading a stretch in one pass

    /// Start reading the stretch a hand on `frame` is heading into, unless
    /// it is in hand already or being read (`MovieSweep.next`).
    private func sweep(_ movie: MovieRef, url: URL, around frame: Int, backward: Bool, size: CGSize) {
        guard let frames = MovieSweep.next(
            handFrame: frame, backward: backward, movie: movie,
            inHand: { [self] in has(movie.frameRef(atSourceMS: $0 * MovieRef.frameStepMS)) },
            running: sweeps[movie.id]?.frames)
        else { return }
        sweeps[movie.id]?.task.cancel()
        let token = UUID()
        let file: @MainActor @Sendable (Int, CGImage) -> Void = { [weak self] index, image in
            self?.fileRough(image, movie: movie, frameIndex: index)
        }
        let finished: @MainActor @Sendable (Bool) -> Void = { [weak self] swept in
            guard let self else { return }
            if !swept { unsweepable.insert(movie.id) }
            if sweeps[movie.id]?.token == token { sweeps[movie.id] = nil }
        }
        let task = Task.detached(priority: .userInitiated) {
            let swept = await MovieSweeper.sweep(movie: movie, url: url, frames: frames, size: size) { index, image in
                Task { @MainActor in file(index, image) }
            }
            await finished(swept)
        }
        sweeps[movie.id] = Sweep(token: token, frames: frames, task: task)
    }

    /// Stop every one-pass read: the hand holds still, or let go, or the clock
    /// took over.
    private func stopSweeps() {
        for sweep in sweeps.values { sweep.task.cancel() }
        sweeps.removeAll()
    }

    // MARK: Reading ahead of a playing playhead

    /// Keep a pass reading ahead of a playhead on `frame`: the one running, if
    /// it still serves it, told where the playhead is now; else a new one
    /// from here.
    private func play(_ movie: MovieRef, url: URL, at frame: Int, size: CGSize) {
        let width = Int(size.width.rounded())
        if let pass = playPasses[movie.id], pass.width == width,
           MoviePlayPass.serves(running: pass.frames, reached: pass.mark.reached, playhead: frame,
                                inHand: { [self] in has(movie.frameRef(atSourceMS: $0 * MovieRef.frameStepMS)) }) {
            pass.mark.playhead = frame
            return
        }
        playPasses[movie.id]?.task.cancel()
        let frames = MoviePlayPass.window(from: frame, movie: movie)
        let token = UUID()
        let mark = PlayMark(playhead: frame)
        let file: @MainActor @Sendable (Int, CGImage) -> Void = { [weak self] index, image in
            self?.filePlayed(image, movie: movie, frameIndex: index)
        }
        let finished: @MainActor @Sendable (Bool) -> Void = { [weak self] swept in
            guard let self, playPasses[movie.id]?.token == token else { return }
            if swept {
                // Read to the end: it stays, so the playhead running out the
                // last frames does not start a pass over them again.
                mark.reached = frames.upperBound + 1
            } else {
                unsweepable.insert(movie.id)
                playPasses[movie.id] = nil
            }
        }
        let task = Task.detached(priority: .userInitiated) {
            let swept = await MovieSweeper.sweep(movie: movie, url: url, frames: frames, size: size,
                                                 waitsAt: { mark.passed($0) }) { index, image in
                Task { @MainActor in file(index, image) }
            }
            if !Task.isCancelled { await finished(swept) }
        }
        playPasses[movie.id] = PlayPass(token: token, frames: frames, width: width, mark: mark, task: task)
    }

    /// Stop every pass reading ahead of a playhead: it stopped, or turned
    /// round, or a hand took it.
    private func stopPlayPasses() {
        for pass in playPasses.values { pass.task.cancel() }
        playPasses.removeAll()
    }

    /// A frame a pass ahead of the playhead reached, filed sharp like any
    /// exact read. Only one at or behind the playhead redraws the canvas: the
    /// clock's next tick draws a frame read ahead when it gets there, and
    /// thirty redraws a second of a picture that did not change is a core
    /// spent on nothing.
    private func filePlayed(_ image: CGImage, movie: MovieRef, frameIndex: Int) {
        let ref = movie.frameRef(atSourceMS: frameIndex * MovieRef.frameStepMS)
        if let filed = filedWidth(ref), filed >= CGFloat(image.width) - 1 { return }
        let first = !resident.contains { $0.movie == movie.id }
        store.register(image, as: ref)
        resident.removeAll { $0.ref.id == ref.id }
        resident.append(Resident(ref: ref, movie: movie.id, frameIndex: frameIndex))
        keepInsideBudget()
        if first || frameIndex <= focus[movie.id] ?? frameIndex { onFrameLanded?() }
    }

    /// A frame a one-pass read reached. Filed unless something at least as
    /// big is filed already; the budget lets go of whichever small frames are
    /// farthest from the playhead.
    private func fileRough(_ image: CGImage, movie: MovieRef, frameIndex: Int) {
        let ref = movie.frameRef(atSourceMS: frameIndex * MovieRef.frameStepMS)
        if let filed = filedWidth(ref), filed >= CGFloat(image.width) { return }
        store.register(image, as: ref)
        resident.removeAll { $0.ref.id == ref.id }
        resident.append(Resident(ref: ref, movie: movie.id, frameIndex: frameIndex, rough: true))
        keepInsideBudget()
        onFrameLanded?()
    }

    /// Start whatever the queue lets start.
    private func startReads() {
        while let read = queue.take() {
            let request = read.request, wanted = read.size, url = read.url
            guard reads.start(request.ref.id, width: wanted.width, filedWidth: filedWidth(request.ref))
            else {
                queue.finished()
                continue
            }
            Task { [weak self] in
                let image = await MovieDecoder.shared.frame(of: request.movie, at: url,
                                                            sourceMS: request.sourceMS, size: wanted)
                guard let self else { return }
                queue.finished()
                defer { startReads() }
                // A bigger read of the same frame may have landed first, and
                // the smaller one must never draw over it.
                guard reads.finish(request.ref.id, width: wanted.width,
                                   landedWidth: image.map { CGFloat($0.width) },
                                   filedWidth: filedWidth(request.ref)),
                      let image
                else { return }
                file(image, for: request)
                onFrameLanded?()
            }
        }
    }

    private func filedWidth(_ ref: ImageRef) -> CGFloat? {
        store.image(for: ref).map { CGFloat($0.width) }
    }

    /// Decode one frame at the recording's own size and wait for it. Used
    /// where there is nothing sensible to draw without it — measuring what a
    /// frame costs, writing one out — never on the way to putting a picture on
    /// screen.
    @discardableResult
    func frame(_ request: MovieFrameRequest) async -> CGImage? {
        if let already = store.image(for: request.ref),
           CGFloat(already.width) >= request.movie.pixelSize.width - 1 { return already }
        guard let url = MovieLibrary.shared.url(for: request.movie) else { return nil }
        guard let image = await MovieDecoder.shared.frame(of: request.movie, at: url,
                                                          sourceMS: request.sourceMS)
        else { return nil }
        file(image, for: request)
        return image
    }

    /// File a frame that came from somewhere other than the file: the last
    /// frame of a recording whose file is still being closed. It is kept like
    /// any frame read, inside the budget, and stands in for its neighbours
    /// until they are read.
    func hold(_ image: CGImage, for request: MovieFrameRequest) {
        file(image, for: request)
    }

    private func file(_ image: CGImage, for request: MovieFrameRequest) {
        store.register(image, as: request.ref)
        // A frame read again at a bigger size is the same frame: it moves to
        // the back of the line rather than taking two places in it.
        resident.removeAll { $0.ref.id == request.ref.id }
        resident.append(Resident(ref: request.ref, movie: request.movie.id,
                                 frameIndex: request.movie.frameIndex(atSourceMS: request.sourceMS)))
        keepInsideBudget()
    }

    /// Let go of the frames farthest from the playhead until the sharp ones
    /// and the small ones are each inside their own budget.
    private func keepInsideBudget() {
        for (rough, budget) in [(false, Self.frameBudget), (true, MovieSweep.roughBudget)] {
            while resident.count(where: { $0.rough == rough }) > budget {
                let kind = resident.indices.filter { resident[$0].rough == rough }
                guard let farthest = MovieFrameQueue<Read>.farthest(
                    kind.map { (resident[$0].movie, resident[$0].frameIndex) }, from: focus) else { break }
                let gone = resident.remove(at: kind[farthest]).ref
                store.remove(gone)
                dropped.append(gone.id)
                if dropped.count > 512 { dropped.removeFirst(dropped.count - 512) }
            }
        }
    }
}

