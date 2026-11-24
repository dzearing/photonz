import AVFoundation
import CoreGraphics
import Foundation
import PhotonzCore

/// The one place an `AVAssetImageGenerator` lives.
///
/// An actor rather than a lock, because a generator is neither `Sendable` nor
/// cheap to make: a few per recording, kept here, and every decode runs off the
/// main actor so a frame landing never stalls a drag.
public actor MovieDecoder {

    /// What is done to every picture before it is handed over: the app blends
    /// the steps of soft gradients (`RecordingSmoothing`).
    private let finish: @Sendable (CGImage, MovieRef) -> CGImage

    public init(finish: @escaping @Sendable (CGImage, MovieRef) -> CGImage) {
        self.finish = finish
    }

    /// How many generators read one recording at one size side by side.
    ///
    /// One generator reads one frame at a time, and a frame of a full-screen
    /// Retina recording costs about 40ms to seek to and read, which is longer
    /// than the 33ms it is on screen for: playing one fell further behind with
    /// every frame and flickered. Measured on a real 3456x2234 recording
    /// (2026-09-23): one generator read 60 frames in about 2.4s, four side by
    /// side read them in 0.36s. Reading smaller does not help, the time is in
    /// the decode, so the answer is more hands, not smaller frames.
    public static let lanes = 4

    private struct Key: Hashable {
        let movie: UUID
        let width: Int
        let height: Int
    }

    private var generators: [Key: [AVAssetImageGenerator]] = [:]
    private var nextLane: [Key: Int] = [:]

    /// Let go of every reader open on a recording, so the next frame asked
    /// for opens its file afresh where `MovieLibrary` now says it is.
    public func forget(_ movie: UUID) {
        for key in generators.keys where key.movie == movie {
            generators[key] = nil
            nextLane[key] = nil
        }
        pictureGenerators[movie] = nil
        nextPictureLane[movie] = nil
        glimpseGenerators[movie] = nil
        keyFrameTables[movie] = nil
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
    public func frame(of movie: MovieRef, at url: URL, sourceMS: Int, size: CGSize? = nil) async -> CGImage? {
        let generator = generator(for: movie, at: url, size: size ?? movie.pixelSize)
        let time = CMTime(value: CMTimeValue(sourceMS), timescale: 1000)
        let image = await withCheckedContinuation { continuation in
            generator.generateCGImageAsynchronously(for: time) { image, _, _ in
                continuation.resume(returning: image)
            }
        }
        return image.map { finish($0, movie) }
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

    // MARK: Key frames for a hand too fast to follow

    private var keyFrameTables: [UUID: MovieKeyFrames] = [:]
    /// One reader per recording for key frames, small, apart from the
    /// playhead's lanes so a fast drag never throws away the generators the
    /// sharp frame is read with when the hand stops.
    private var glimpseGenerators: [UUID: (width: Int, generator: AVAssetImageGenerator)] = [:]

    /// Which grid frames of a recording are key frames, from the file's own
    /// table of samples: nothing is decoded. Nil where the file cannot say.
    public func keyFrames(of movie: MovieRef, at url: URL) async -> MovieKeyFrames? {
        if let known = keyFrameTables[movie.id] { return known }
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              (try? await track.load(.canProvideSampleCursors)) == true,
              let cursor = track.makeSampleCursorAtFirstSampleInDecodeOrder() else { return nil }
        var moments: [Int] = []
        repeat {
            if cursor.currentSampleSyncInfo.sampleIsFullSync.boolValue {
                moments.append(Int((cursor.presentationTimeStamp.seconds * 1000).rounded()))
            }
        } while cursor.stepInDecodeOrder(byCount: 1) == 1
        let keys = MovieKeyFrames(sourceMS: moments)
        keyFrameTables[movie.id] = keys
        return keys
    }

    /// One key frame of a recording, at most `size` big: a single decode.
    public func keyFrame(of movie: MovieRef, at url: URL, sourceMS: Int, size: CGSize) async -> CGImage? {
        let width = Int(size.width.rounded())
        let generator: AVAssetImageGenerator
        if let kept = glimpseGenerators[movie.id], kept.width == width {
            generator = kept.generator
        } else {
            generator = Self.makeGenerator(url: url, size: size)
            glimpseGenerators[movie.id] = (width, generator)
        }
        let time = CMTime(value: CMTimeValue(sourceMS), timescale: 1000)
        let image = await withCheckedContinuation { continuation in
            generator.generateCGImageAsynchronously(for: time) { image, _, _ in
                continuation.resume(returning: image)
            }
        }
        return image.map { finish($0, movie) }
    }

    // MARK: Pictures along a clip

    /// How many generators read the small pictures along a clip on the
    /// timeline (`ClipFilmstripFrames`). Fewer than the playhead has, and
    /// apart from its lanes, so a zoomed timeline filling in never makes the
    /// picture under the playhead wait, and never throws away the playhead's
    /// generators the way a new size for the SAME lanes would.
    public static let pictureLanes = 2

    private var pictureGenerators: [UUID: [AVAssetImageGenerator]] = [:]
    private var nextPictureLane: [UUID: Int] = [:]

    /// One small picture of a recording for the timeline, at most `size`.
    public func picture(of movie: MovieRef, at url: URL, sourceMS: Int, size: CGSize) async -> CGImage? {
        let lanes = pictureGenerators[movie.id] ?? (0..<Self.pictureLanes).map { _ in
            Self.makeGenerator(url: url, size: size)
        }
        pictureGenerators[movie.id] = lanes
        let lane = nextPictureLane[movie.id, default: 0]
        nextPictureLane[movie.id] = (lane + 1) % lanes.count
        let generator = lanes[lane]
        let time = CMTime(value: CMTimeValue(sourceMS), timescale: 1000)
        let image = await withCheckedContinuation { continuation in
            generator.generateCGImageAsynchronously(for: time) { image, _, _ in
                continuation.resume(returning: image)
            }
        }
        return image.map { finish($0, movie) }
    }

    private static func makeGenerator(url: URL, size: CGSize) -> AVAssetImageGenerator {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        // Half a frame either way: exact seeking makes every frame a full
        // decode from the nearest keyframe, and half a frame of slop is
        // invisible while costing a fraction of the time.
        let slop = CMTime(value: CMTimeValue(MovieRef.seekSlopMS), timescale: 1000)
        generator.requestedTimeToleranceBefore = slop
        generator.requestedTimeToleranceAfter = slop
        // Read at the size it is shown, never bigger than the recording: a
        // full-screen Retina frame is 30MB, and a window showing it at half
        // size has no use for three quarters of that.
        generator.maximumSize = size
        return generator
    }
}
