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
/// cheap to make: one per recording, kept here, and every decode runs off the
/// main actor so a frame landing never stalls a drag.
actor MovieDecoder {
    static let shared = MovieDecoder()

    private var generators: [UUID: AVAssetImageGenerator] = [:]

    /// One frame of one recording, or nil where the file will not give it up.
    ///
    /// The callback form rather than the `async` one on purpose: a generator is
    /// not `Sendable`, and awaiting a method ON it would carry it across an
    /// isolation boundary. This way it never leaves the actor and only the
    /// finished picture comes back.
    func frame(of movie: MovieRef, at url: URL, sourceMS: Int) async -> CGImage? {
        let generator = generator(for: movie, at: url)
        let time = CMTime(value: CMTimeValue(sourceMS), timescale: 1000)
        return await withCheckedContinuation { continuation in
            generator.generateCGImageAsynchronously(for: time) { image, _, _ in
                continuation.resume(returning: image)
            }
        }
    }

    private func generator(for movie: MovieRef, at url: URL) -> AVAssetImageGenerator {
        if let known = generators[movie.id] { return known }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        // Half a frame either way: exact seeking makes every frame a full
        // decode from the nearest keyframe, and half a frame of slop is
        // invisible while costing a fraction of the time.
        let slop = CMTime(value: CMTimeValue(MovieRef.frameStepMS / 2), timescale: 1000)
        generator.requestedTimeToleranceBefore = slop
        generator.requestedTimeToleranceAfter = slop
        // The canvas draws the frame at whatever size the picture is, so
        // decoding it larger than the recording buys nothing.
        generator.maximumSize = movie.pixelSize
        generators[movie.id] = generator
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

    private let store: ImageStore
    /// Decoded frames, oldest first, so the one to drop is always at the front.
    private var resident: [ImageRef] = []
    private var inFlight: Set<UUID> = []

    /// Called on the main actor whenever a frame lands, so the canvas can
    /// redraw with a picture it did not have a moment ago.
    var onFrameLanded: (() -> Void)?

    init(store: ImageStore) {
        self.store = store
    }

    /// Whether this frame is already decoded and filed.
    func has(_ ref: ImageRef) -> Bool { store.image(for: ref) != nil }

    /// Ask for everything a moment needs. Frames already filed cost nothing;
    /// the rest are decoded in the background and land one by one.
    func fetch(_ requests: [MovieFrameRequest]) {
        for request in requests where !has(request.ref) && !inFlight.contains(request.ref.id) {
            guard let url = MovieLibrary.shared.url(for: request.movie) else { continue }
            inFlight.insert(request.ref.id)
            Task { [weak self] in
                let image = await MovieDecoder.shared.frame(of: request.movie, at: url,
                                                            sourceMS: request.sourceMS)
                guard let self else { return }
                inFlight.remove(request.ref.id)
                guard let image else { return }
                file(image, as: request.ref)
                onFrameLanded?()
            }
        }
    }

    /// Decode one frame and wait for it. Used where there is nothing sensible
    /// to draw without it — measuring what a frame costs, writing one out —
    /// never on the way to putting a picture on screen.
    @discardableResult
    func frame(_ request: MovieFrameRequest) async -> CGImage? {
        if let already = store.image(for: request.ref) { return already }
        guard let url = MovieLibrary.shared.url(for: request.movie) else { return nil }
        guard let image = await MovieDecoder.shared.frame(of: request.movie, at: url,
                                                          sourceMS: request.sourceMS)
        else { return nil }
        file(image, as: request.ref)
        return image
    }

    private func file(_ image: CGImage, as ref: ImageRef) {
        store.register(image, as: ref)
        resident.append(ref)
        while resident.count > Self.frameBudget {
            store.remove(resident.removeFirst())
        }
    }
}
