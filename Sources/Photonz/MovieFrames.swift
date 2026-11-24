import AVFoundation
import AppKit
import CoreImage
import Foundation
import PhotonzCore
import PhotonzMedia
import PhotonzRender
import Synchronization
import VideoToolbox

// Where a clip's pixels actually come from (`docs/design/video.md` §4).
//
// The document says *which recording, at which moment*; this says *here is that
// frame*. The split is the same one pictures have always had — a document holds
// an `ImageRef`, `ImageStore` holds the bitmap — and keeping it is what lets a
// clip be an ordinary picture layer everywhere else in the app.
//
// Nothing here knows about time, trims or pieces. It is handed
// `MovieFrameRequest`s and it fills them.

/// Reads a stretch of a recording in one pass and hands over each grid frame
/// in it, small (`MovieSweep`).
///
/// Not on `MovieDecoder`'s actor: a pass runs for a couple of hundred
/// milliseconds, and the actor answering a sharp frame must never wait behind
/// it. Nothing here outlives one pass, so nothing is shared.
enum MovieSweeper {

    private static let context = CIContext(options: [.cacheIntermediates: false])
    /// How many passes may read at once, across every window.
    ///
    /// A pass blocks the thread it runs on in `copyNextSampleBuffer` until the
    /// decoder hands a sample over, and it runs on Swift's shared pool, one
    /// thread per core. A hand scrubbing starts a pass with every stretch it
    /// moves into and cancels the last, which stops only between samples, so
    /// once the long edit stopped stalling the main thread a scrub had a pass
    /// blocked on every thread of the pool: sixteen parked in CoreMedia with
    /// the decoder's own threads waiting beside them, and nothing asynchronous
    /// in the app ran again (the speed walk's scrub, 3 of 6 runs, 2026-11-13).
    /// Half the cores, at least two, leaves the pool its room. Reading each
    /// pass on a thread of its own instead fixed the hang too, but the
    /// picture trailed a scrub by two display frames in 2 of 5 runs of
    /// `scrub-never-blacks-out-walk`, and a third of the cores in 1 of 5: a
    /// new pass waits there for a cancelled one to finish its sample.
    static let readingAtOnce = max(2, ProcessInfo.processInfo.activeProcessorCount / 2)
    static let gate = SweepGate(limit: readingAtOnce)

    /// Lets `limit` passes read at once; the rest wait their turn without
    /// holding a thread.
    final class SweepGate: Sendable {
        private struct State {
            var reading = 0
            var waiting: [CheckedContinuation<Void, Never>] = []
        }
        private let state = Mutex(State())
        let limit: Int

        init(limit: Int) { self.limit = limit }

        func enter() async {
            await withCheckedContinuation { (turn: CheckedContinuation<Void, Never>) in
                let now = state.withLock { state -> Bool in
                    guard state.reading < limit else {
                        state.waiting.append(turn)
                        return false
                    }
                    state.reading += 1
                    return true
                }
                if now { turn.resume() }
            }
        }

        func leave() {
            let next = state.withLock { state -> CheckedContinuation<Void, Never>? in
                guard !state.waiting.isEmpty else {
                    state.reading -= 1
                    return nil
                }
                return state.waiting.removeFirst()
            }
            next?.resume()
        }
    }

    /// Read `frames` of `movie` from start to end, handing each grid frame to
    /// `deliver` at most `size` big, as soon as it is read. Stops as soon as
    /// the task is cancelled. Answers false when the recording cannot be read
    /// this way at all (a turn that is not a right angle), so the caller goes
    /// back to reading exact frames.
    ///
    /// `waitsAt` is told, before each sample is read, the first grid frame not
    /// handed over yet, and answers whether to wait before reading on: a pass
    /// playing ahead of the playhead waits there for it (`MoviePlayPass`).
    ///
    /// `keeps` picks the grid frames worth handing over; every sample is still
    /// decoded, but only those are turned into pictures, which is most of the
    /// cost (`MoviePlayBackward.stride`).
    ///
    /// `skipsUnreferenced` decodes only the frames other frames are decoded
    /// from (`MoviePlayPass.skipsUnreferenced`); a skipped frame's grid frames
    /// show the one decoded before it.
    ///
    /// `yieldsWhileWaiting` gives the pass's place among those reading at once
    /// (`gate`) to another while `waitsAt` holds it, and takes one again to
    /// read on: for a pass that may wait for seconds for a hand to come
    /// (`MovieSweep.restingPass`, `MovieSweep.comingPausesAfter`). A waiting
    /// pass holds no thread, which is all the limit is for.
    static func sweep(movie: MovieRef, url: URL, frames: ClosedRange<Int>, size: CGSize,
                      waitsAt: (@Sendable (Int) -> Bool)? = nil,
                      yieldsWhileWaiting: Bool = false,
                      keeps: (@Sendable (Int) -> Bool)? = nil,
                      skipsUnreferenced: Bool = false,
                      deliver: @escaping @Sendable (Int, SurfaceFrame) -> Void) async -> Bool {
        // Only a few read at once (`SweepGate`); one asked to stop while it
        // waited for its turn reads nothing.
        await gate.enter()
        var holding = true
        defer { if holding { gate.leave() } }
        guard !Task.isCancelled else { return true }
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let transform = try? await track.load(.preferredTransform),
              let orientation = orientation(of: transform),
              let reader = try? AVAssetReader(asset: asset)
        else { return false }
        reader.timeRange = CMTimeRange(
            start: CMTime(value: CMTimeValue(MovieRef.gridMS(ofFrame: frames.lowerBound)), timescale: 1000),
            end: CMTime(value: CMTimeValue(MovieRef.gridMS(ofFrame: frames.upperBound + 1)), timescale: 1000))
        // The decoder's own format: asking for RGB made the pass three times
        // slower, and only the frames kept are converted. A 10-bit recording
        // is read at 10 bits (`MovieDecodeFormat`): squeezed to 8 on the way,
        // its dark gradients banded again.
        let description = try? await track.load(.formatDescriptions).first
        let format: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: description.map(MovieDecodeFormat.pixelFormat(for:))
                ?? kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        ]
        // Skipping, the samples come over as they are in the file and are
        // decoded here (`SkippingDecoder`); a track that cannot be decoded
        // that way is read the usual way.
        let skipping: SkippingDecoder?
        if skipsUnreferenced, let description {
            skipping = SkippingDecoder(format: description, attributes: format)
        } else {
            skipping = nil
        }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: skipping == nil ? format : nil)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return false }
        reader.add(output)
        guard reader.startReading() else { return false }
        defer { skipping?.close() }
        func nextFrame() -> (ms: Double, buffer: CVPixelBuffer)? {
            if let skipping { return skipping.next(from: output) }
            while let sample = output.copyNextSampleBuffer() {
                guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
                return (CMSampleBufferGetPresentationTimeStamp(sample).seconds * 1000, buffer)
            }
            return nil
        }

        var grid = MovieSweepGrid(frames: frames)
        var previous: CVPixelBuffer?
        func hand(_ arrived: [Int], _ buffer: CVPixelBuffer?) {
            let indices = keeps.map { arrived.filter($0) } ?? arrived
            guard !indices.isEmpty, let buffer,
                  let image = picture(of: buffer, orientation: orientation, size: size) else { return }
            for index in indices { deliver(index, image) }
        }
        // Stopped between samples only: `cancelReading` from another thread
        // while a sample is being read crashes (tried 2026-09-27).
        while !Task.isCancelled {
            if let waitsAt, waitsAt(grid.nextFrame) {
                if yieldsWhileWaiting, holding {
                    gate.leave()
                    holding = false
                }
                try? await Task.sleep(for: .milliseconds(4))
                continue
            }
            if !holding {
                await gate.enter()
                holding = true
                if Task.isCancelled { break }
            }
            guard let (ms, buffer) = nextFrame() else { break }
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

    /// Decodes a recording's samples itself, in the order the file holds
    /// them, skipping every one no other frame is decoded from, and hands the
    /// rest back in the order they are shown (`MovieDecodeReorder`). What a
    /// pass above double speed reads with (`MoviePlayPass.skipsUnreferenced`).
    // Unchecked: it holds a decoder session, which is not Sendable, and is
    // used only by the one task reading its pass; the decoder's own thread
    // touches only `finished`, under its lock.
    final class SkippingDecoder: @unchecked Sendable {
        private let session: VTDecompressionSession
        /// Frames the decoder has finished, in the order it finished them;
        /// filled on the decoder's own thread.
        private final class Finished: @unchecked Sendable {
            // Unchecked: a pixel buffer is not Sendable, and every touch of
            // `frames` is under `lock`; the decoder hands each one over once.
            private let lock = NSLock()
            private var frames: [(ms: Double, buffer: CVPixelBuffer)] = []
            func add(_ ms: Double, _ buffer: CVPixelBuffer) {
                lock.withLock { frames.append((ms, buffer)) }
            }
            func takeAll() -> [(ms: Double, buffer: CVPixelBuffer)] {
                lock.withLock { defer { frames.removeAll() }; return frames }
            }
        }
        private let finished = Finished()
        /// Only touched by the one task reading the pass.
        private var order = MovieDecodeReorder<CVPixelBuffer>(depth: 3)
        private var ended = false

        init?(format: CMFormatDescription, attributes: [String: Any]) {
            var made: VTDecompressionSession?
            let status = VTDecompressionSessionCreate(
                allocator: nil, formatDescription: format, decoderSpecification: nil,
                imageBufferAttributes: attributes as CFDictionary, outputCallback: nil,
                decompressionSessionOut: &made)
            guard status == noErr, let made else { return nil }
            session = made
        }

        /// The next frame in the order shown, decoding as many samples as it
        /// takes; nil once the samples run out and every frame is handed on.
        func next(from output: AVAssetReaderTrackOutput) -> (ms: Double, buffer: CVPixelBuffer)? {
            while true {
                take()
                if let ready = order.next() { return (ready.ms, ready.frame) }
                if ended { return order.drain().map { ($0.ms, $0.frame) } }
                guard let sample = output.copyNextSampleBuffer() else {
                    VTDecompressionSessionWaitForAsynchronousFrames(session)
                    ended = true
                    continue
                }
                guard CMSampleBufferGetNumSamples(sample) > 0, !Self.unreferenced(sample) else { continue }
                let status = VTDecompressionSessionDecodeFrame(
                    session, sampleBuffer: sample, flags: [._EnableAsynchronousDecompression],
                    infoFlagsOut: nil
                ) { [finished] status, _, image, shown, _ in
                    guard status == noErr, let image else { return }
                    finished.add(shown.seconds * 1000, image)
                }
                if status != noErr { continue }
            }
        }

        func close() {
            VTDecompressionSessionWaitForAsynchronousFrames(session)
            VTDecompressionSessionInvalidate(session)
        }

        private func take() {
            for frame in finished.takeAll() {
                order.insert(frame.ms, frame.buffer)
            }
        }

        /// Whether nothing else in the recording is decoded from this sample.
        private static func unreferenced(_ sample: CMSampleBuffer) -> Bool {
            guard let all = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false)
                    as? [[CFString: Any]], let first = all.first,
                  let referenced = first[kCMSampleAttachmentKey_IsDependedOnByOthers] as? Bool
            else { return false }
            return !referenced
        }
    }

    /// One decoded frame, turned the way the recording is shown and at most
    /// `size` big, in the recording's own colours, kept on a GPU surface of its
    /// own (`FrameOnASurface`): read back into a bitmap, every composite that
    /// drew it uploaded it to the GPU again.
    private static func picture(of buffer: CVPixelBuffer, orientation: CGImagePropertyOrientation,
                                size: CGSize) -> SurfaceFrame? {
        var image = CIImage(cvPixelBuffer: buffer).oriented(orientation)
        let scale = min(1, size.width / max(1, image.extent.width))
        image = image.samplingLinear().transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let extent = image.extent.integral
        let colors = CVBufferCopyAttachments(buffer, .shouldPropagate)
            .flatMap { CVImageBufferCreateColorSpaceFromAttachments($0)?.takeRetainedValue() }
            ?? CGColorSpace(name: CGColorSpace.sRGB)
        // The steps the Mac drew a soft gradient in, blended as the frame is
        // made, in the same pass on the GPU (`RecordingSmoothing`).
        if RecordingSmoothing.isOn {
            image = RecordingSmoothing.smoothed(image.cropped(to: extent),
                                               reach: RecordingSmoothing.reach(readAt: scale), grain: true)
        }
        guard let colors else { return nil }
        return FrameOnASurface.draw(image, from: extent, colorSpace: colors, context: context)
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
        /// Where the hand is, shared with the pass as it reads off the main
        /// actor, so it makes pictures only of frames the hand has not
        /// passed (`MovieSweep.worthShowing`).
        let hand: HandMark
        /// A glimpse for a hand too fast for a stretch: the key frame nearest
        /// it (`MovieKeyFrames`), or the frame under it until the recording's
        /// key frames are known (`MovieSweep.next(glimpse:)`). Left to finish
        /// rather than replaced by the next one: a read stops only between
        /// frames, and replacing a stretch read at every move piled reads up
        /// in the decoder, eight at a time, each taking 200 to 600ms to show
        /// anything (2026-11-17).
        let glimpse: Bool
        /// A pass following a hand going forward under it to the end of the
        /// recording, paced a little ahead of it (`MovieSweep.window(follows:)`,
        /// `MovieSweep.followLeadMS`), or waiting for one to come to it: at
        /// rest (`restingOn`), or on a clip it is heading for.
        var follows = false
        /// The grid frame a read around a playhead at rest was opened for
        /// (`readAroundRest`): kept while the playhead stays there, so a hunt
        /// from it has a pass to follow it.
        var restingOn: Int? = nil
    }
    private var sweeps: [UUID: Sweep] = [:]
    /// Which way a hand on the playhead is going, nil when none is: the
    /// frames it has passed go first when there are too many small ones
    /// (`keepInsideBudget`). Let go by distance alone, a pass following a
    /// hunting hand a second ahead lost the frames ahead, the next ones the
    /// hand needed, and the picture sat on one frame for a quarter second
    /// with them read and gone (2026-11-20).
    private var handGoesBack: Bool?
    /// The recordings under a moving hand (`underHand`): every other one on
    /// screen is a clip it is only heading for, whose small frames go first
    /// (`MovieFrameQueue.farthest(aside:)`).
    private var handMovies = Set<UUID>()
    /// The glimpses being read, across every recording: a hand that fast is
    /// in a different clip, often a different recording, on nearly every
    /// refresh.
    private var glimpseRunning = Set<UUID>()
    /// How many glimpses read at once. Two, once each clip on screen had its
    /// own (pass 15, 2026-11-17): a fast drag crossing into a moment with
    /// three clips on screen waited three reads in a row for the last of
    /// them, and two at once took the medium drag's worst from 105 refreshes
    /// behind to 34. With one glimpse per recording (pass 14) two made no
    /// difference.
    static let glimpsesAtOnce = 2
    /// The glimpses to read once one lands: the newest place the hand asked
    /// for for each clip on screen while it ran (`glimpse`).
    private var glimpseNext: [(slot: UUID, movie: UUID, start: () -> Void)] = []
    /// The key frames being read (`glimpse`), by their glimpse's token: which
    /// picture each is, so nothing reads it twice, and its read, to stop.
    private var glimpseReads: [UUID: (ref: UUID, task: Task<Void, Never>)] = [:]
    /// When each clip on screen last had a key frame read for it: the one
    /// that waited longest goes next, so two clips on screen at once take
    /// turns. Newest asked first, the clip asked for last in every refresh
    /// had them all and the other kept a frame from twenty seconds away
    /// (2026-11-17).
    private var glimpseServed: [UUID: Int] = [:]
    /// Where each recording's playhead rests, once a fetch has asked for a
    /// still moment: read around small once the sharp frames are in
    /// (`readAroundRest`).
    private var resting: [(movie: MovieRef, url: URL, frame: Int, size: CGSize)] = []
    /// The grid frame each recording's read at rest was last opened for, so
    /// it is opened once per rest (`readAroundRest`).
    private var restRead: [UUID: Int] = [:]
    private var glimpseServings = 0
    /// Each recording's key frames, once read (`MovieKeyFrames`).
    private var keyFrames: [UUID: MovieKeyFrames] = [:]
    private var keyFramesAsked = Set<UUID>()

    /// The frame a hand is on, for a pass reading off the main actor.
    final class HandMark: Sendable {
        private let frame: Mutex<Int?>
        init(_ frame: Int?) { self.frame = Mutex(frame) }
        /// Nil until the hand is on the recording.
        var value: Int? {
            get { frame.withLock { $0 } }
            set { frame.withLock { $0 = newValue } }
        }
    }
    /// Recordings a one-pass read cannot turn the right way up, which a moving
    /// hand reads frame by frame as before.
    private var unsweepable = Set<UUID>()

    /// Where a pass playing ahead of the playhead has got to, and where the
    /// playhead is, shared with the pass as it reads off the main actor.
    private final class PlayMark: Sendable {
        private let state: Mutex<(aim: MoviePlayPass.Aim, reached: Int)>
        init(_ aim: MoviePlayPass.Aim) { state = Mutex((aim, aim.playhead)) }
        /// The frame the pass keeps ahead of, and how far ahead: the
        /// playhead, or the first frame of a stretch about to come on.
        var aim: MoviePlayPass.Aim {
            get { state.withLock { $0.aim } }
            set { state.withLock { $0.aim = newValue } }
        }
        var reached: Int {
            get { state.withLock { $0.reached } }
            set { state.withLock { $0.reached = newValue } }
        }
        /// Note how far the pass has got, and answer whether it is far enough
        /// ahead of where it is aimed to wait.
        func passed(_ next: Int) -> Bool {
            state.withLock {
                $0.reached = next
                return MoviePlayPass.shouldWait(next: next, playhead: $0.aim.playhead, reach: $0.aim.reach)
            }
        }
    }

    /// The passes reading ahead of a playing playhead in each recording, at
    /// the size the canvas shows it: the stretch playing, and any about to
    /// come on (`MoviePlayPass`).
    private struct PlayPass {
        let token: UUID
        let frames: ClosedRange<Int>
        let width: Int
        let mark: PlayMark
        let task: Task<Void, Never>

        var running: MoviePlayPass.Running {
            let aim = mark.aim
            return .init(running: frames, reached: mark.reached, playhead: aim.playhead, reach: aim.reach)
        }
    }
    private var playPasses: [UUID: [PlayPass]] = [:]
    #if PHOTONZ_PLAYTEST
    /// Probe only: each recording's passes as "frames reached>aim+reach".
    var playtestPasses: [UUID: [String]] {
        playPasses.mapValues { passes in
            passes.map { "\($0.frames.lowerBound)-\($0.frames.upperBound) at \($0.mark.reached)"
                + " aimed \($0.mark.aim.playhead)+\($0.mark.aim.reach)" }
        }
    }
    #endif
    /// Every how many frames the passes in `playPasses` keep
    /// (`MoviePlayBackward.stride`). A pass keeps what it was opened to keep,
    /// so a change of speed that changes this starts them all over: a pass
    /// thinned for 8x left running at 1x would show every third frame.
    private var playPassStride = 1
    /// ...and whether they skip the frames nothing is decoded from
    /// (`MoviePlayPass.skipsUnreferenced`): one opened at 4x left running at
    /// 2x would show some frames a frame early.
    private var playPassSkips = false

    /// A block of frames being read behind a playhead playing backwards, in
    /// one pass, at the size the canvas shows it (`MoviePlayBackward`).
    private struct BackBlock {
        let token: UUID
        let frames: ClosedRange<Int>
        let width: Int
        let task: Task<Void, Never>
    }
    private var backBlocks: [UUID: [BackBlock]] = [:]
    /// How many places each recording is being read behind: the playhead,
    /// and the far side of a cut coming up.
    private var backPlaces: [UUID: Int] = [:]
    /// How fast the clock is playing backwards, while it is.
    private var backSpeed: Double?

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
    /// Which frame each recording's playhead is on, as the last fetch asked:
    /// two while a dissolve runs between parts of it, none for a recording
    /// it no longer shows.
    private var focus: [UUID: [Int]] = [:]
    /// ...and the first frames of the stretches about to come on, which the
    /// budget keeps as close as the playhead (`MoviePlayPass`).
    private var coming: [UUID: [Int]] = [:]

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
    /// While the clock plays it forwards (`playing`, the frames under the
    /// playhead and the stretches about to come on), the frames ahead of the
    /// playhead are read in one pass that keeps a little ahead of it, sharp,
    /// rather than one at a time (`MoviePlayPass`), and the far side of a cut
    /// or the shot coming in over a dissolve has a pass of its own, opened
    /// before the playhead gets there. Only a frame no pass will reach soon is
    /// read on its own. Any other call stops those passes.
    ///
    /// While the clock plays it backwards (`playingBackward`, at that speed),
    /// the stretch just behind the playhead is read in blocks, each in one
    /// pass, rather than one frame at a time from its key frame, and so is
    /// the far side of a cut it is about to cross (`backPlaces`,
    /// `MoviePlayBackward`). Any other call stops those blocks.
    func fetch(_ requests: [MovieFrameRequest], size: (MovieFrameRequest) -> CGSize,
               handMoving: Bool = false, handPace: Double = 0,
               played: (MovieFrameRequest) -> ClosedRange<Int>? = { _ in nil },
               underHand: Int = .max, backward: Bool = false,
               playing: MoviePlayPoints? = nil,
               playingSpeed: Double = 1,
               playingBackward: Double? = nil, backPlaces: [MovieBackPlace] = []) {
        if !handMoving {
            // A read around a playhead still resting where it was opened is
            // left open (`readAroundRest`); anything else stops.
            let rests = playingBackward == nil && (playing == nil || backward)
            stopSweeps(keepingRestsAt: rests ? Self.restingFrames(requests, underHand: underHand) : [:])
        } else {
            restRead = [:]
        }
        handGoesBack = handMoving ? backward : nil
        handMovies = handMoving ? Set(requests.prefix(max(0, underHand)).map(\.movie.id)) : []
        let playsAhead = playing != nil && !handMoving && !backward
        if !playsAhead { stopPlayPasses() }
        let stride = MoviePlayBackward.stride(speed: playingSpeed)
        let skips = MoviePlayPass.skipsUnreferenced(speed: playingSpeed)
        if playsAhead, stride != playPassStride || skips != playPassSkips {
            stopPlayPasses()
            playPassStride = stride
            playPassSkips = skips
        }
        let playsBack = playingBackward != nil && !handMoving
        if !playsBack { stopBackBlocks() }
        backSpeed = playsBack ? playingBackward : nil
        coming = [:]
        // Only what this moment shows keeps a place, so the frames of a clip
        // the playhead jumped away from are the first the budget lets go
        // (`MovieFrameQueue.placesStillShown`).
        focus = MovieFrameQueue<Read>.placesStillShown(focus, asked: requests.map(\.movie.id))
        var wanted: [Read] = []
        var asked = Set<UUID>()
        var focused = Set<UUID>()
        let glimpsing = handMoving && MovieSweep.glimpses(pace: handPace)
        for (place, request) in requests.enumerated() where asked.insert(request.ref.id).inserted {
            let width = size(request)
            guard let url = MovieLibrary.shared.url(for: request.movie) else { continue }
            let frame = request.movie.frameIndex(atSourceMS: request.sourceMS)
            // A hand too fast for a stretch: each clip on screen is shown its
            // nearest key frame (`glimpse`).
            let glimpsed = glimpsing && place < underHand && !unsweepable.contains(request.movie.id)
                && glimpse(request.movie, url: url, around: frame, within: played(request),
                           slot: request.layerID, size: MovieSweep.roughSize(for: width))
            // ...and a stretch still running from when it was slower stops:
            // it shares the decoder with the key frames.
            if glimpsed, let running = sweeps[request.movie.id], !running.glimpse {
                running.task.cancel()
                sweeps[request.movie.id] = nil
            }
            // The first frame asked of a recording is where its playhead is,
            // which is what the budget keeps the frames around.
            if !focused.insert(request.movie.id).inserted {
                // ...and every other place on screen it shows: two clips of
                // one recording at once (a dissolve between two takes of it).
                // Kept to the first, the budget counted the second's frames
                // as far from anything and let each go the moment it landed
                // (2026-11-17).
                if place < underHand || glimpsing, !playsAhead, focus[request.movie.id]?.contains(frame) == false {
                    focus[request.movie.id, default: []].append(frame)
                }
            } else {
                focus[request.movie.id] = [frame]
                // (A recording only under the hand now, not where it will be,
                // is being left: nothing is read for it.)
                if handMoving, !glimpsed, !(glimpsing && place >= underHand),
                   !unsweepable.contains(request.movie.id) {
                    sweep(request.movie, url: url, around: frame, backward: backward,
                          glimpse: glimpsing, underHand: place < underHand,
                          size: MovieSweep.roughSize(for: width))
                }
                if playsAhead, let playing, !unsweepable.contains(request.movie.id) {
                    play(request.movie, url: url, points: playing, speed: playingSpeed, size: width)
                }
                if playsBack, let speed = playingBackward, !unsweepable.contains(request.movie.id) {
                    let places = backPlaces.filter { $0.movie.id == request.movie.id }
                    playBack(request.movie, url: url,
                             places: places.isEmpty ? [MovieBackPlace(request: request, floor: 0)] : places,
                             speed: speed, size: width)
                }
            }
            if handMoving, !unsweepable.contains(request.movie.id) { continue }
            if let filed = filedWidth(request.ref),
               filed >= width.width - 1 || (playsAhead && MoviePlayPass.anySizeServes(speed: playingSpeed)) { continue }
            if playsAhead, coveredByPlay(request, width: width, speed: playingSpeed) { continue }
            if playsBack, coveredByBack(request, width: width) { continue }
            // ...and at a speed that keeps only some frames, one it does not
            // keep is never read on its own: a seek from the key frame for a
            // frame the clock passes in 4ms.
            if playsBack, let speed = playingBackward,
               !MoviePlayBackward.keeps(frame: request.movie.frameIndex(atSourceMS: request.sourceMS), speed: speed) {
                continue
            }
            // ...forwards too (`MoviePlayPass.keeps`).
            if playsAhead,
               !MoviePlayPass.keeps(frame: request.movie.frameIndex(atSourceMS: request.sourceMS), speed: playingSpeed) {
                continue
            }
            if handMoving, has(request.ref) { continue }
            wanted.append(Read(request: request, size: width, url: url))
        }
        // A recording the hand has moved off (the far side of a dissolve it
        // has left) stops being read: that pass shares the decoder with the
        // one under the hand, and on 2026-11-17 kept the first half second of
        // a hunt on stand-ins. A glimpse is left to land: it stops only
        // between frames, and its first frame is the one it was opened for.
        if handMoving {
            for (id, sweep) in sweeps where !focused.contains(id) && !sweep.glimpse {
                sweep.task.cancel()
                sweeps[id] = nil
            }
            glimpseNext.removeAll { !focused.contains($0.movie) }
        }
        // A recording not on screen yet but about to come on (a clip that
        // starts in a moment) is opened too.
        if playsAhead, let playing {
            for request in playing.coming where focused.insert(request.movie.id).inserted {
                guard !unsweepable.contains(request.movie.id),
                      let url = MovieLibrary.shared.url(for: request.movie) else { continue }
                play(request.movie, url: url, points: playing, speed: playingSpeed, size: size(request))
            }
        }
        // Played backwards, so is one only across a cut behind.
        if playsBack, let speed = playingBackward {
            for place in backPlaces where focused.insert(place.movie.id).inserted {
                guard !unsweepable.contains(place.movie.id),
                      let url = MovieLibrary.shared.url(for: place.movie) else { continue }
                playBack(place.movie, url: url, places: backPlaces.filter { $0.movie.id == place.movie.id },
                         speed: speed, size: size(place.request))
            }
        }
        // A still playhead, paused: the second around it is read small once
        // the sharp frames are in (`readAroundRest`).
        resting = []
        if !handMoving, !playsAhead, !playsBack {
            for (index, request) in requests.enumerated() where index < underHand {
                guard !unsweepable.contains(request.movie.id),
                      !resting.contains(where: { $0.movie.id == request.movie.id }),
                      let url = MovieLibrary.shared.url(for: request.movie) else { continue }
                resting.append((request.movie, url, request.movie.frameIndex(atSourceMS: request.sourceMS),
                                MovieSweep.roughSize(for: size(request))))
            }
        }
        queue.replace(with: wanted)
        startReads()
    }

    /// Read the second around each resting playhead small, in one pass, once
    /// nothing else is being read: a hand that then takes the playhead and
    /// hunts has a picture for its first move instead of the frame it
    /// started on for a fifth of a second (`MovieSweep.restingWindow`).
    private func readAroundRest() {
        guard !resting.isEmpty, queue.waiting.isEmpty, queue.running == 0 else { return }
        let places = resting
        resting = []
        for place in places where sweeps[place.movie.id] == nil {
            let movie = place.movie
            let pass = MovieSweep.restingPass(around: place.frame, movie: movie, places: places.count)
            let window = pass.frames.lowerBound...pass.pausesAfter
            // Read once per rest: with its window in hand already, the pass
            // is opened anyway the first time, so a hunt from here has one
            // to follow it (`MovieSweep.restingPass`), but not again once it
            // stopped waiting.
            guard restRead[movie.id] != place.frame
                    || window.contains(where: { !has(movie.frameRef(atFrame: $0)) })
            else { continue }
            restRead[movie.id] = place.frame
            let token = UUID()
            let hand = HandMark(nil)
            // Quiet until a hand takes it: a landing redraws the canvas and
            // every clip's row in the layers list.
            let file: @MainActor @Sendable (Int, SurfaceFrame) -> Void = { [weak self] index, image in
                self?.fileRough(image, movie: movie, frameIndex: index, quiet: hand.value == nil)
            }
            let finished: @MainActor @Sendable (Bool) -> Void = { [weak self] swept in
                guard let self else { return }
                if !swept { unsweepable.insert(movie.id) }
                if sweeps[movie.id]?.token == token { sweeps[movie.id] = nil }
            }
            let url = place.url, size = place.size, pausesAfter = pass.pausesAfter
            let paced: @Sendable (Int) -> Bool = { next in
                MovieSweep.restWaits(nextFrame: next, hand: hand.value, pausesAfter: pausesAfter)
            }
            let keeps: @Sendable (Int) -> Bool = { index in
                hand.value.map { MovieSweep.worthShowing(frame: index, hand: $0, backward: false) } ?? true
            }
            // At the hand's own priority, not in the background: this is the
            // pass a hunt from here follows, and at utility it made a frame
            // every 5.5ms against the 2.7 of a pass the hand started
            // (2026-11-20), slower than a hand hunting at five times speed.
            let task = Task.detached(priority: .userInitiated) {
                let swept = await MovieSweeper.sweep(movie: movie, url: url, frames: pass.frames, size: size,
                                                     waitsAt: paced, yieldsWhileWaiting: true,
                                                     keeps: keeps) { index, image in
                    Task { @MainActor in file(index, image) }
                }
                await finished(swept)
            }
            sweeps[movie.id] = Sweep(token: token, frames: pass.frames, task: task, hand: hand, glimpse: false,
                                     follows: true, restingOn: place.frame)
            // A playhead left alone that long is not about to be hunted from.
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(MovieSweep.restHoldsMS))
                guard let self, sweeps[movie.id]?.token == token, hand.value == nil else { return }
                task.cancel()
                sweeps[movie.id] = nil
            }
        }
    }

    /// Whether a pass reading ahead of the playhead will reach this frame, so
    /// nothing reads it on its own.
    private func coveredByPlay(_ request: MovieFrameRequest, width: CGSize, speed: Double) -> Bool {
        let frame = request.movie.frameIndex(atSourceMS: request.sourceMS)
        return (playPasses[request.movie.id] ?? []).contains { pass in
            let aim = pass.mark.aim
            return (pass.width >= Int(width.width.rounded()) - 1 || MoviePlayPass.anySizeServes(speed: speed))
                && MoviePlayPass.covers(frame: frame, running: pass.frames, reached: pass.mark.reached,
                                        playhead: aim.playhead, reach: aim.reach, speed: speed)
        }
    }

    /// Whether a block being read behind a playhead playing backwards will
    /// reach this frame, so nothing reads it on its own.
    private func coveredByBack(_ request: MovieFrameRequest, width: CGSize) -> Bool {
        let blocks = (backBlocks[request.movie.id] ?? []).filter { $0.width >= Int(width.width.rounded()) - 1 }
        return MoviePlayBackward.covers(frame: request.movie.frameIndex(atSourceMS: request.sourceMS),
                                        running: blocks.map(\.frames))
    }

    // MARK: Reading a stretch in one pass

    /// Start reading the stretch a hand on `frame` is heading into, unless
    /// it is in hand already or being read (`MovieSweep.next`).
    ///
    /// A hand too fast for a stretch (`glimpse`) is shown the key frame
    /// nearest it instead (`MovieKeyFrames`), one read at a time, the newest
    /// place it asked for once the last lands.
    ///
    /// A recording read ahead of the hand (`underHand` false: a clip it is
    /// about to cross into) has every frame of its stretch made, since the
    /// hand has not passed any of them yet.
    private func sweep(_ movie: MovieRef, url: URL, around frame: Int, backward: Bool, glimpse: Bool,
                       underHand: Bool = true, size: CGSize) {
        if underHand { sweeps[movie.id]?.hand.value = frame }
        if glimpse, glimpseRunning.count >= Self.glimpsesAtOnce {
            glimpseNext.removeAll { $0.slot == movie.id }
            if sweeps[movie.id]?.frames.contains(frame) == true { return }
            glimpseNext.append((movie.id, movie.id, { [weak self] in
                self?.sweep(movie, url: url, around: frame, backward: backward, glimpse: glimpse,
                            underHand: underHand, size: size)
            }))
            return
        }
        if sweeps[movie.id]?.glimpse == true { return }
        // A hand going forward under the recording is followed by one pass
        // rather than read in stretches (`MovieSweep.window(follows:)`). One
        // that turns back is not covered by it, however far it reaches.
        let follows = underHand && !backward && !glimpse
        // A clip it is heading for is read a little, then waits for the hand
        // to cross in and follows it (`MovieSweep.comingPausesAfter`).
        let waitsForHand = !underHand && !backward && !glimpse
        var running = sweeps[movie.id]
        if backward, running?.follows == true { running = nil }
        guard let frames = MovieSweep.next(
            handFrame: frame, backward: backward, movie: movie,
            inHand: { [self] in has(movie.frameRef(atFrame: $0)) },
            running: running?.frames, glimpse: glimpse, follows: follows || waitsForHand)
        else { return }
        sweeps[movie.id]?.task.cancel()
        let token = UUID()
        let file: @MainActor @Sendable (Int, SurfaceFrame) -> Void = { [weak self] index, image in
            self?.fileRough(image, movie: movie, frameIndex: index)
        }
        let finished: @MainActor @Sendable (Bool) -> Void = { [weak self] swept in
            guard let self else { return }
            if !swept { unsweepable.insert(movie.id) }
            glimpseLanded(token, of: movie.id)
        }
        let hand = HandMark(underHand ? frame : nil)
        let keeps: (@Sendable (Int) -> Bool)? = glimpse ? nil : { @Sendable index in
            hand.value.map { MovieSweep.worthShowing(frame: index, hand: $0, backward: backward) } ?? true
        }
        let pausesAfter = MovieSweep.comingPausesAfter(frame, movie: movie)
        let paced: (@Sendable (Int) -> Bool)? = follows ? { @Sendable next in
            MovieSweep.waits(nextFrame: next, hand: hand.value)
        } : waitsForHand ? { @Sendable next in
            MovieSweep.restWaits(nextFrame: next, hand: hand.value, pausesAfter: pausesAfter)
        } : nil
        let task = Task.detached(priority: .userInitiated) {
            let swept = await MovieSweeper.sweep(movie: movie, url: url, frames: frames, size: size,
                                                 waitsAt: paced, yieldsWhileWaiting: waitsForHand,
                                                 keeps: keeps) { index, image in
                Task { @MainActor in file(index, image) }
            }
            await finished(swept)
        }
        sweeps[movie.id] = Sweep(token: token, frames: frames, task: task, hand: hand, glimpse: glimpse,
                                 follows: follows || waitsForHand)
        if glimpse { glimpseRunning.insert(token) }
    }

    /// A one-pass read or a key frame finished: free its place, and start the
    /// newest glimpse waiting if it was the glimpse running.
    private func glimpseLanded(_ token: UUID, of movie: UUID) {
        glimpseReads[token] = nil
        if glimpseRunning.remove(token) != nil, !glimpseNext.isEmpty {
            // The clip that waited longest; among those never served, the
            // one asked for last, which is where the hand is now.
            let index = glimpseNext.indices.max { a, b in
                let (servedA, servedB) = (glimpseServed[glimpseNext[a].slot] ?? -1,
                                          glimpseServed[glimpseNext[b].slot] ?? -1)
                return servedA != servedB ? servedA > servedB : a < b
            } ?? glimpseNext.count - 1
            glimpseNext.remove(at: index).start()
        }
        if sweeps[movie]?.token == token { sweeps[movie] = nil }
    }

    /// The key frame nearest `frame` of a recording, or nil while its key
    /// frames are not known yet (asked for the first time this is) or where
    /// it has none to tell.
    private func keyFrame(near frame: Int, within: ClosedRange<Int>?, of movie: MovieRef,
                          url: URL) -> (frame: Int, sourceMS: Int)? {
        if let keys = keyFrames[movie.id] { return keys.nearest(to: frame, within: within) }
        learnKeyFrames(of: movie, at: url)
        return nil
    }

    /// Show a hand too fast for a stretch the key frame nearest `frame` that
    /// its clip plays (`within`, grid frames), read on its own. One read at a
    /// time across every recording; while one runs, each clip on screen
    /// (`slot`) keeps the newest place it asked for, and the clip asked last
    /// goes next. Per clip rather than per recording: two clips of one
    /// recording on screen at once (a dissolve between two takes of it, a
    /// picture in picture) each need their own, and per recording the second
    /// showed whatever frame was in hand, often twenty seconds away
    /// (2026-11-17).
    ///
    /// False while the recording's key frames are not known yet, or where it
    /// has none to tell: the frame under the hand is read instead (`sweep`).
    private func glimpse(_ movie: MovieRef, url: URL, around frame: Int, within: ClosedRange<Int>?,
                         slot: UUID, size: CGSize) -> Bool {
        guard let (key, keyMS) = keyFrame(near: frame, within: within, of: movie, url: url) else { return false }
        glimpseNext.removeAll { $0.slot == slot }
        let ref = movie.frameRef(atFrame: key)
        if has(ref) || glimpseReads.values.contains(where: { $0.ref == ref.id }) { return true }
        if glimpseRunning.count >= Self.glimpsesAtOnce {
            glimpseNext.append((slot, movie.id, { [weak self] in
                _ = self?.glimpse(movie, url: url, around: frame, within: within, slot: slot, size: size)
            }))
            return true
        }
        let token = UUID()
        glimpseRunning.insert(token)
        glimpseServings += 1
        glimpseServed[slot] = glimpseServings
        let task = Task { @MainActor [weak self] in
            let image = await MovieDecoder.shared.keyFrame(of: movie, at: url, sourceMS: keyMS, size: size)
            guard let self else { return }
            if let image, !Task.isCancelled { fileRough(image, movie: movie, frameIndex: key) }
            glimpseLanded(token, of: movie.id)
        }
        glimpseReads[token] = (ref.id, task)
        return true
    }

    /// Read a recording's key frames from its file's table of samples, once.
    private func learnKeyFrames(of movie: MovieRef, at url: URL) {
        guard keyFramesAsked.insert(movie.id).inserted else { return }
        Task { @MainActor [weak self] in
            let keys = await MovieDecoder.shared.keyFrames(of: movie, at: url)
            self?.keyFrames[movie.id] = keys ?? MovieKeyFrames(sourceMS: [])
        }
    }

    /// A hand took hold of the playhead: read the key frames of every
    /// recording the edit plays now, before it reaches them. Learned on first
    /// meeting instead, a fast drag showed the frame it had left behind for
    /// the length of a table read each time it crossed into a recording it
    /// had not met yet (2026-11-17).
    func learnKeyFrames(of movies: [MovieRef]) {
        for movie in movies where !keyFramesAsked.contains(movie.id) {
            guard let url = MovieLibrary.shared.url(for: movie) else { continue }
            learnKeyFrames(of: movie, at: url)
        }
    }

    /// Stop every one-pass read: the hand holds still, or let go, or the clock
    /// took over.
    private func stopSweeps(keepingRestsAt rests: [UUID: Int] = [:]) {
        for (id, sweep) in sweeps where sweep.restingOn == nil || rests[id] != sweep.restingOn {
            sweep.task.cancel()
            sweeps[id] = nil
        }
        for read in glimpseReads.values { read.task.cancel() }
        glimpseReads.removeAll()
        glimpseServed.removeAll()
        glimpseNext.removeAll()
        glimpseRunning.removeAll()
    }

    /// The grid frame each recording under the hand rests on, the first
    /// place asked for each, as `fetch` opens its reads at rest.
    private static func restingFrames(_ requests: [MovieFrameRequest], underHand: Int) -> [UUID: Int] {
        var frames: [UUID: Int] = [:]
        for (index, request) in requests.enumerated() where index < underHand && frames[request.movie.id] == nil {
            frames[request.movie.id] = request.movie.frameIndex(atSourceMS: request.sourceMS)
        }
        return frames
    }

    // MARK: Reading ahead of a playing playhead

    /// Keep the passes this recording's playing playhead needs: one under
    /// each frame it shows, told where the playhead is now, and one opened a
    /// few frames into each stretch about to come on (`MoviePlayPass.plan`).
    /// Passes nobody needs any more stop.
    private func play(_ movie: MovieRef, url: URL, points: MoviePlayPoints, speed: Double, size: CGSize) {
        let width = Int(size.width.rounded())
        func frames(_ requests: [MovieFrameRequest]) -> [Int] {
            requests.filter { $0.movie.id == movie.id }.map { movie.frameIndex(atSourceMS: $0.sourceMS) }
        }
        let now = frames(points.now), next = frames(points.coming)
        if !now.isEmpty { focus[movie.id] = now }
        coming[movie.id] = next
        let passes = (playPasses[movie.id] ?? []).filter { pass in
            // Above double speed one read at another size goes on
            // (`MoviePlayPass.anySizeServes`).
            if pass.width == width || MoviePlayPass.anySizeServes(speed: speed) { return true }
            pass.task.cancel()
            return false
        }
        // Where it starts decoding from decides whether a pass fallen behind
        // is worth starting over (`MoviePlayPass.serves`).
        learnKeyFrames(of: movie, at: url)
        let plan = MoviePlayPass.plan(now: now, coming: next, passes: passes.map(\.running),
                                      inHand: { [self] in has(movie.frameRef(atFrame: $0)) },
                                      speed: speed, keyFrames: keyFrames[movie.id])
        var kept: [PlayPass] = []
        for (index, pass) in passes.enumerated() {
            if let aim = plan.aim[index] {
                pass.mark.aim = aim
                kept.append(pass)
            } else {
                pass.task.cancel()
            }
        }
        playPasses[movie.id] = kept
        for aim in plan.open { open(movie, url: url, aim: aim, speed: speed, size: size) }
        keepInsideBudget()
    }

    /// Start a pass over `movie` from `aim`'s frame, reading as far ahead of
    /// it as the aim says and waiting there.
    private func open(_ movie: MovieRef, url: URL, aim: MoviePlayPass.Aim, speed: Double, size: CGSize) {
        let width = Int(size.width.rounded())
        let frames = MoviePlayPass.window(from: aim.playhead, movie: movie)
        let token = UUID()
        let mark = PlayMark(aim)
        let file: @MainActor @Sendable (Int, SurfaceFrame) -> Void = { [weak self] index, image in
            self?.filePlayed(image, movie: movie, frameIndex: index)
        }
        let finished: @MainActor @Sendable (Bool) -> Void = { [weak self] swept in
            guard let self, playPasses[movie.id]?.contains(where: { $0.token == token }) == true else { return }
            if swept {
                // Read to the end: it stays, so the playhead running out the
                // last frames does not start a pass over them again.
                mark.reached = frames.upperBound + 1
            } else {
                unsweepable.insert(movie.id)
                stopPlayPasses(of: movie.id)
            }
        }
        // A pass opened at 8x keeps every third frame for as long as it runs;
        // a change of speed opens passes afresh only where the playhead
        // leaves this one behind, and the frames it skips are then read on
        // their own (`MoviePlayPass.keeps`).
        // ...and a frame the playhead has already left behind is decoded on
        // the way but never converted, so a pass kept while it catches up
        // gets there sooner (`MoviePlayPass.worthTurningIntoAPicture`).
        let thins = MoviePlayBackward.stride(speed: speed) > 1
        let keeps: @Sendable (Int) -> Bool = { frame in
            MoviePlayPass.worthTurningIntoAPicture(frame: frame, aimedAt: mark.aim.playhead)
                && (!thins || MoviePlayPass.keeps(frame: frame, speed: speed))
        }
        let skips = MoviePlayPass.skipsUnreferenced(speed: speed)
        let task = Task.detached(priority: .userInitiated) {
            let swept = await MovieSweeper.sweep(movie: movie, url: url, frames: frames, size: size,
                                                 waitsAt: { mark.passed($0) }, keeps: keeps,
                                                 skipsUnreferenced: skips) { index, image in
                Task { @MainActor in file(index, image) }
            }
            if !Task.isCancelled { await finished(swept) }
        }
        playPasses[movie.id, default: []].append(
            PlayPass(token: token, frames: frames, width: width, mark: mark, task: task))
    }

    // MARK: Reading behind a playhead playing backwards

    /// Keep the blocks a playhead going backwards needs, behind each of
    /// `places` (the playhead, then the far side of a cut coming up): the
    /// ones it has not gone past, and a new one below them when a frame
    /// within reach behind is neither in hand nor being read
    /// (`MoviePlayBackward.next`).
    private func playBack(_ movie: MovieRef, url: URL, places: [MovieBackPlace], speed: Double, size: CGSize) {
        let width = Int(size.width.rounded())
        coming[movie.id] = places.dropFirst().map(\.head)
        backPlaces[movie.id] = places.count
        var blocks = (backBlocks[movie.id] ?? []).filter { block in
            if block.width == width,
               places.contains(where: { MoviePlayBackward.serves(block.frames, playhead: $0.head, speed: speed) }) {
                return true
            }
            block.task.cancel()
            return false
        }
        let sharp: (Int) -> Bool = { [self] in
            filedWidth(movie.frameRef(atFrame: $0)).map { $0 >= CGFloat(width) - 1 } ?? false
        }
        for place in places where blocks.count < MoviePlayBackward.blocksPerRecording {
            if let frames = MoviePlayBackward.next(playhead: place.head, floor: place.floor, speed: speed,
                                                   movie: movie, inHand: sharp, running: blocks.map(\.frames)) {
                blocks.append(openBack(movie, url: url, frames: frames, speed: speed, size: size))
            }
        }
        backBlocks[movie.id] = blocks
        keepInsideBudget()
    }

    /// Start reading `frames` of `movie` in one pass, lowest first, keeping
    /// the frames kept at `speed` (`MoviePlayBackward.keeps`).
    private func openBack(_ movie: MovieRef, url: URL, frames: ClosedRange<Int>, speed: Double,
                          size: CGSize) -> BackBlock {
        let token = UUID()
        let file: @MainActor @Sendable (Int, SurfaceFrame) -> Void = { [weak self] index, image in
            self?.filePlayed(image, movie: movie, frameIndex: index, backward: true)
        }
        let finished: @MainActor @Sendable (Bool) -> Void = { [weak self] swept in
            guard let self else { return }
            backBlocks[movie.id]?.removeAll { $0.token == token }
            if !swept {
                unsweepable.insert(movie.id)
                stopBackBlocks()
            }
        }
        let task = Task.detached(priority: .userInitiated) {
            let swept = await MovieSweeper.sweep(movie: movie, url: url, frames: frames, size: size,
                                                 keeps: { MoviePlayBackward.keeps(frame: $0, speed: speed) }) { index, image in
                Task { @MainActor in file(index, image) }
            }
            if !Task.isCancelled { await finished(swept) }
        }
        return BackBlock(token: token, frames: frames, width: Int(size.width.rounded()), task: task)
    }

    /// Stop every block reading behind a playhead: it stopped, turned round,
    /// or a hand took it.
    private func stopBackBlocks() {
        for block in backBlocks.values.joined() { block.task.cancel() }
        backBlocks.removeAll()
        backPlaces.removeAll()
    }

    /// Stop every pass reading ahead of a playhead: it stopped, or turned
    /// round, or a hand took it.
    private func stopPlayPasses() {
        for pass in playPasses.values.joined() { pass.task.cancel() }
        playPasses.removeAll()
        coming.removeAll()
    }

    private func stopPlayPasses(of movie: UUID) {
        for pass in playPasses[movie] ?? [] { pass.task.cancel() }
        playPasses[movie] = nil
    }

    /// A frame a pass ahead of the playhead reached, filed sharp like any
    /// exact read. Only one at or behind the playhead redraws the canvas: the
    /// clock's next tick draws a frame read ahead when it gets there, and
    /// thirty redraws a second of a picture that did not change is a core
    /// spent on nothing.
    ///
    /// Played `backward`, the frames gone by are the ones above the playhead,
    /// so it is one at or above it that redraws.
    private func filePlayed(_ frame: SurfaceFrame, movie: MovieRef, frameIndex: Int, backward: Bool = false) {
        let ref = movie.frameRef(atFrame: frameIndex)
        if let filed = filedWidth(ref), filed >= CGFloat(frame.image.width) - 1 { return }
        let first = !resident.contains { $0.movie == movie.id }
        store.register(frame.image, as: ref, surface: frame.surface)
        resident.removeAll { $0.ref.id == ref.id }
        resident.append(Resident(ref: ref, movie: movie.id, frameIndex: frameIndex))
        keepInsideBudget()
        // With two shots of one recording playing, a frame belongs to the
        // nearer of them: the outgoing shot's frames are all before the
        // incoming one's, and must not redraw the canvas for it.
        let nearest = (focus[movie.id] ?? []).min { abs($0 - frameIndex) < abs($1 - frameIndex) }
        let due = backward ? frameIndex >= nearest ?? frameIndex : frameIndex <= nearest ?? frameIndex
        if first || due { onFrameLanded?() }
    }

    /// A frame a one-pass read reached. Filed unless something at least as
    /// big is filed already; the budget lets go of whichever small frames are
    /// farthest from the playhead.
    /// `quiet` for a frame nobody is looking at yet (`readAroundRest`): a
    /// landing redraws the canvas and every clip's row in the layers list.
    private func fileRough(_ frame: SurfaceFrame, movie: MovieRef, frameIndex: Int, quiet: Bool = false) {
        fileRough(frame.image, surface: frame.surface, movie: movie, frameIndex: frameIndex, quiet: quiet)
    }

    private func fileRough(_ image: CGImage, surface: CVPixelBuffer? = nil, movie: MovieRef, frameIndex: Int,
                           quiet: Bool = false) {
        let ref = movie.frameRef(atFrame: frameIndex)
        if let filed = filedWidth(ref), filed >= CGFloat(image.width) { return }
        if let surface {
            store.register(image, as: ref, surface: surface)
        } else {
            store.register(image, as: ref)
        }
        resident.removeAll { $0.ref.id == ref.id }
        resident.append(Resident(ref: ref, movie: movie.id, frameIndex: frameIndex, rough: true))
        keepInsideBudget()
        if !quiet { onFrameLanded?() }
    }

    /// A recording nothing here plays any more (its file was replaced): stop
    /// reading it and let its frames go. A read still under way lands under
    /// its own id, which nothing draws, and the budget drops it.
    func forget(_ movie: UUID) {
        sweeps.removeValue(forKey: movie)?.task.cancel()
        stopPlayPasses(of: movie)
        for block in backBlocks.removeValue(forKey: movie) ?? [] { block.task.cancel() }
        backPlaces[movie] = nil
        glimpseNext.removeAll { $0.movie == movie }
        resting.removeAll { $0.movie.id == movie }
        restRead[movie] = nil
        keyFrames[movie] = nil
        keyFramesAsked.remove(movie)
        unsweepable.remove(movie)
        focus[movie] = nil
        coming[movie] = nil
        for frame in resident where frame.movie == movie { store.remove(frame.ref) }
        resident.removeAll { $0.movie == movie }
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
        readAroundRest()
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
        // Every place being played counts as the playhead: the stretch
        // playing, the shot coming in, the far side of the next cut.
        let foci = focus.merging(coming) { $0 + $1 }
        let ahead = MoviePlayPass.frameBudget(base: Self.frameBudget,
                                              reaches: playPasses.values.joined().map { $0.mark.aim.reach })
        let places = backPlaces.values.reduce(0, +)
        let sharp = backSpeed.map { MoviePlayBackward.frameBudget(base: ahead, speed: $0, places: places) } ?? ahead
        for (rough, budget) in [(false, sharp), (true, MovieSweep.roughBudget)] {
            while resident.count(where: { $0.rough == rough }) > budget {
                let kind = resident.indices.filter { resident[$0].rough == rough }
                guard let farthest = MovieFrameQueue<Read>.farthest(
                    kind.map { (resident[$0].movie, resident[$0].frameIndex) }, from: foci,
                    forward: !playPasses.isEmpty || handGoesBack == false,
                    backward: backSpeed != nil || handGoesBack == true,
                    aside: rough && handGoesBack != nil ? Set(foci.keys).subtracting(handMovies) : []) else { break }
                let gone = resident.remove(at: kind[farthest]).ref
                store.remove(gone)
                dropped.append(gone.id)
                if dropped.count > 512 { dropped.removeFirst(dropped.count - 512) }
            }
        }
    }
}

