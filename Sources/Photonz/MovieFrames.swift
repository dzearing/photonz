import AVFoundation
import AppKit
import Foundation
import PhotonzCore
import PhotonzRender

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

    /// Read a recording's size and length off the file and hand back the
    /// reference a document can hold. The same file asked for twice is the same
    /// reference, so re-opening a recording re-uses whatever frames of it are
    /// already decoded.
    func movie(at url: URL) async -> MovieRef? {
        let standardized = url.standardizedFileURL
        if let known = refsByURL[standardized] { return known }
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
        let ref = MovieRef(pixelSize: CGSize(width: abs(shown.width), height: abs(shown.height)),
                           durationMS: Int((duration.seconds * 1000).rounded()),
                           hasSound: hasSound)
        urls[ref.id] = standardized
        refsByURL[standardized] = ref
        // A recording's sound is the same file as its picture, so the sound
        // library can answer for it from the moment the recording is opened.
        if let sound = ref.soundRef { SoundLibrary.shared.link(sound, to: standardized) }
        return ref
    }

    func url(for movie: MovieRef) -> URL? { urls[movie.id] }

    /// File a reference a saved project already holds against the file its
    /// media table found for it (`ProjectMedia`), so the project's clips play
    /// under the ids they were saved with. Nothing is read off the file: the
    /// project already knows its size and length. A file this run has opened
    /// under another reference keeps that one for anybody opening it afresh.
    func adopt(_ movie: MovieRef, at url: URL) {
        let standardized = url.standardizedFileURL
        urls[movie.id] = standardized
        if refsByURL[standardized] == nil { refsByURL[standardized] = movie }
        if let sound = movie.soundRef { SoundLibrary.shared.link(sound, to: standardized) }
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
    /// 130MB, which is the most a preview is worth.
    static let frameBudget = 16

    /// How far ahead of the playhead frames are read while it plays. A
    /// quarter of a second: enough that the four lanes of `MovieDecoder` are
    /// always busy, and well inside `frameBudget` so a frame read ahead is
    /// never dropped before it is shown.
    static let playAheadFrames = 8

    private struct Resident {
        let ref: ImageRef
        let movie: UUID
        let frameIndex: Int
    }

    private let store: ImageStore
    /// Decoded frames, oldest first, so the one to drop is always at the front.
    private var resident: [Resident] = []
    /// Which frames are being read and how big, so a frame asked for bigger
    /// while a smaller read of it is under way is read again rather than left
    /// at the smaller size (`MovieFrameReads`).
    private var reads = MovieFrameReads()

    /// Called on the main actor whenever a frame lands, so the canvas can
    /// redraw with a picture it did not have a moment ago.
    var onFrameLanded: (() -> Void)?

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
    func fetch(_ requests: [MovieFrameRequest], size: (MovieFrameRequest) -> CGSize) {
        for request in requests {
            let wanted = size(request)
            guard let url = MovieLibrary.shared.url(for: request.movie),
                  reads.start(request.ref.id, width: wanted.width, filedWidth: filedWidth(request.ref))
            else { continue }
            Task { [weak self] in
                let image = await MovieDecoder.shared.frame(of: request.movie, at: url,
                                                            sourceMS: request.sourceMS, size: wanted)
                guard let self else { return }
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

    private func file(_ image: CGImage, for request: MovieFrameRequest) {
        store.register(image, as: request.ref)
        // A frame read again at a bigger size is the same frame: it moves to
        // the back of the line rather than taking two places in it.
        resident.removeAll { $0.ref.id == request.ref.id }
        resident.append(Resident(ref: request.ref, movie: request.movie.id,
                                 frameIndex: request.movie.frameIndex(atSourceMS: request.sourceMS)))
        while resident.count > Self.frameBudget {
            store.remove(resident.removeFirst().ref)
        }
    }
}
