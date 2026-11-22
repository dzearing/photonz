import AVFoundation
import CoreGraphics
import Foundation
import PhotonzCore
@testable import PhotonzMedia
import Testing
import VideoToolbox

/// **The frame shown at a whole second is the one that starts there.**
///
/// Asked for the picture at exactly 10 seconds of a 30 frames a second
/// recording, the app drew frame 299, the one that ENDS at 10 seconds, because
/// frames were fetched on a grid 33ms apart against frames 33.33ms apart: the
/// grid's moment for 10s was 9.999s, a hair short of frame 300 (2026-10-19,
/// an agent's `video_frame` on a test recording). Every reader the app has is
/// checked here against a real decode of a clip that paints its own frame
/// number into every frame (`TestClip`), at whole seconds out to ten minutes,
/// so an error that grows with length shows.
///
/// The three readers: a seek with the slop the canvas reads a single frame
/// with (`MovieDecoder`), the one pass a scrub or play fills the grid from
/// (`MovieSweepGrid`), and the one pass an export reads (`MovieFrameStream`).
@Suite("The frame shown at a whole second is the one that starts there", .serialized)
struct WholeSecondFrameTests {

    /// Sixteen stripes count to 65535 frames, about 36 minutes at 30fps.
    static let bits = 16
    /// Moments asked for, in ms, and the frame each must show.
    static let asked: [(ms: Int, frame: Int)] = [
        (0, 0), (1000, 30), (10_000, 300), (10_020, 300), (10_040, 301),
        (60_000, 1800), (600_000, 18_000),
    ]

    /// One clip for the whole suite: ten minutes and a half at 30fps is
    /// 18015 frames, which is most of what the suite costs. Written to one
    /// fixed place, replaced each run, so runs do not pile clips up.
    static let clip: Task<URL, Error> = Task {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotonzMediaTests-whole-second", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("ten-minutes.mp4")
        try await TestClip.write(to: url, seconds: 600.5, size: CGSize(width: 64, height: 16), bits: bits)
        return url
    }
    static let movie = MovieRef(pixelSize: CGSize(width: 64, height: 16), durationMS: 600_500)

    @Test("A single frame sought with the canvas's slop is the frame that starts at the moment")
    func seeking() async throws {
        let url = try await Self.clip.value
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        let slop = CMTime(value: CMTimeValue(MovieRef.seekSlopMS), timescale: 1000)
        generator.requestedTimeToleranceBefore = slop
        generator.requestedTimeToleranceAfter = slop
        for (ms, frame) in Self.asked {
            let grid = Self.movie.frameSourceMS(atSourceMS: ms)
            let image = try await generator.image(at: CMTime(value: CMTimeValue(grid), timescale: 1000)).image
            let shown = try #require(TestClip.frameCode(of: image, bits: Self.bits))
            #expect(shown.index == frame, "\(ms)ms (grid \(grid)ms) showed frame \(shown.index), wanted \(frame)")
            #expect(Self.movie.frameIndex(atSourceMS: ms) == frame, "\(ms)ms is grid frame \(Self.movie.frameIndex(atSourceMS: ms))")
        }
    }

    @Test("The one pass an export reads hands over the frame that starts at the moment")
    func streaming() async throws {
        let url = try await Self.clip.value
        for (ms, frame) in Self.asked {
            // A stream of its own for each, so each is a jump the way a clip
            // cut from deep in a recording is.
            let stream = try #require(await MovieFrameStream(url: url))
            let grid = Self.movie.frameSourceMS(atSourceMS: ms)
            let image = try #require(stream.frame(atMS: grid), "no frame at \(grid)ms")
            let shown = try #require(TestClip.frameCode(of: image, bits: Self.bits))
            #expect(shown.index == frame, "\(ms)ms (grid \(grid)ms) streamed frame \(shown.index), wanted \(frame)")
        }
    }

    @Test("A scrub's one pass files the frame that starts at a moment under that moment's grid frame")
    func sweeping() async throws {
        let url = try await Self.clip.value
        let asset = AVURLAsset(url: url)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        for (ms, frame) in Self.asked {
            let index = Self.movie.frameIndex(atSourceMS: ms)
            let frames = max(0, index - 3)...(index + 3)
            let reader = try AVAssetReader(asset: asset)
            reader.timeRange = CMTimeRange(
                start: CMTime(value: CMTimeValue(MovieRef.gridMS(ofFrame: frames.lowerBound)), timescale: 1000),
                end: CMTime(value: CMTimeValue(MovieRef.gridMS(ofFrame: frames.upperBound + 1)), timescale: 1000))
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            ])
            reader.add(output)
            #expect(reader.startReading())
            var grid = MovieSweepGrid(frames: frames)
            var previous: CGImage?
            var filed: [Int: Int] = [:]
            func file(_ indices: [Int]) {
                guard let previous, let code = TestClip.frameCode(of: previous, bits: Self.bits) else { return }
                for i in indices { filed[i] = code.index }
            }
            while let sample = output.copyNextSampleBuffer() {
                guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
                file(grid.arrived(atMS: CMSampleBufferGetPresentationTimeStamp(sample).seconds * 1000))
                var image: CGImage?
                VTCreateCGImageFromCVPixelBuffer(buffer, options: nil, imageOut: &image)
                previous = image
            }
            file(grid.finished())
            #expect(filed[index] == frame, "\(ms)ms (grid frame \(index)) was filed frame \(filed[index] ?? -1), wanted \(frame)")
        }
    }
}
