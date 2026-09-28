import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import VideoToolbox

// Reading a recording FRONT TO BACK, for writing a video out
// (`docs/design/video.md` §8).
//
// The canvas asks for frames wherever the playhead happens to be, so it seeks:
// an image generator per frame, each one a jump to the nearest key frame and a
// decode forward from there. An export asks for every frame of a clip in order,
// and seeking to each of those on its own cost about as long as the frame is on
// screen for: five minutes of a Retina recording took six minutes to write
// (measured 2026-09-24). Read in one pass, the decoder runs ahead on its own and
// a frame costs a small fraction of that.
//
// It still answers ANY moment: a document can play pieces out of order, so a
// moment behind the last one read, or far ahead of it, starts the pass again
// from there rather than refusing.

/// One recording read in order, one frame per moment asked for.
///
/// Not `Sendable`: a reader belongs to the one export that made it, and that
/// export asks for one frame at a time.
public final class MovieFrameStream {

    /// A moment further ahead than this starts a new pass rather than decoding
    /// every frame on the way there.
    static let jumpAheadMS = 1_500

    private struct Sample {
        let ms: Double
        let buffer: CVPixelBuffer
        var image: CGImage?
    }

    private let asset: AVURLAsset
    private let track: AVAssetTrack
    private var reader: AVAssetReader?
    private var output: AVAssetReaderTrackOutput?
    /// The frame last handed over, and the one after it, read to tell whether
    /// it is nearer the next moment asked for.
    private var current: Sample?
    private var pending: Sample?
    private var exhausted = false

    /// A stream over the recording at `url`, or nil where it has no picture a
    /// single pass can hand over the right way up (a track turned by anything
    /// but nothing at all is left to the image generator, which turns it).
    public init?(url: URL) async {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let transform = try? await track.load(.preferredTransform),
              transform.isIdentity
        else { return nil }
        self.asset = asset
        self.track = track
        guard start(atMS: 0) else { return nil }
    }

    /// The frame of the recording nearest `ms`, or nil where there is none.
    public func frame(atMS ms: Int) -> CGImage? {
        let wanted = Double(ms)
        if let current, wanted < current.ms - Double(Self.halfFrameMS)
            || wanted > current.ms + Double(Self.jumpAheadMS) {
            guard start(atMS: ms) else { return nil }
        }
        if current == nil { current = next() }
        guard current != nil else { return nil }
        // Step on while the frame after is at least as near the moment.
        while true {
            if pending == nil { pending = next() }
            guard let after = pending, let now = current,
                  abs(after.ms - wanted) <= abs(now.ms - wanted) else { break }
            current = after
            pending = nil
        }
        guard var shown = current else { return nil }
        if shown.image == nil {
            var image: CGImage?
            VTCreateCGImageFromCVPixelBuffer(shown.buffer, options: nil, imageOut: &image)
            shown.image = image
            current = shown
        }
        return shown.image
    }

    /// Half a frame at the rate the document keeps: a moment behind the frame
    /// last handed over by less than this is still that frame.
    private static let halfFrameMS = 17

    /// A new pass, starting a little before `ms` so the frame nearest it is in
    /// the pass even where it sits just ahead of the moment.
    @discardableResult
    private func start(atMS ms: Int) -> Bool {
        reader?.cancelReading()
        reader = nil
        output = nil
        current = nil
        pending = nil
        exhausted = false
        guard let reader = try? AVAssetReader(asset: asset) else { return false }
        let from = max(0, ms - 50)
        reader.timeRange = CMTimeRange(start: CMTime(value: CMTimeValue(from), timescale: 1000),
                                       duration: .positiveInfinity)
        // Turned into RGB by the decoder itself, and backed by a surface the
        // GPU can read without a copy.
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return false }
        reader.add(output)
        guard reader.startReading() else { return false }
        self.reader = reader
        self.output = output
        return true
    }

    /// The next decoded frame of the pass, or nil at its end. The end keeps
    /// the last frame up: a moment past it is still the recording's last
    /// picture.
    private func next() -> Sample? {
        guard !exhausted, let output else { return nil }
        while let sample = output.copyNextSampleBuffer() {
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            let ms = CMSampleBufferGetPresentationTimeStamp(sample).seconds * 1000
            guard ms.isFinite else { continue }
            return Sample(ms: ms, buffer: buffer, image: nil)
        }
        exhausted = true
        return nil
    }

    deinit {
        reader?.cancelReading()
    }
}
