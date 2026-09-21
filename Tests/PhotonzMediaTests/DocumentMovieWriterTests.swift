import AVFoundation
import CoreGraphics
import Foundation
import PhotonzCore
@testable import PhotonzMedia
import Testing

/// **The file a document writes is what the document says.**
///
/// Every test here writes a real movie and then opens it again: how long it
/// runs, how big its picture is, what colour the picture is at a given moment,
/// and whether the sound that came out is the sound the mix asked for. Nothing
/// is checked by asking the writer what it thinks it did.
@Suite("A document comes out as a video file", .serialized)
struct DocumentMovieWriterTests {

    static let folder = TestTone.scratch()

    /// A flat picture of one colour, the size the plan asks for.
    static func solid(_ color: (r: Double, g: Double, b: Double), size: CGSize) -> CGImage? {
        let width = Int(size.width), height = Int(size.height)
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(red: color.r, green: color.g, blue: color.b, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// Red for the first half of the document, blue for the second: a file that
    /// says which moment of itself you are looking at.
    static func twoHalves(plan: VideoFramePlan) -> @Sendable (Int) async -> CGImage? {
        let size = plan.size
        let half = plan.durationMS / 2
        return { ms in
            ms < half ? solid((1, 0, 0), size: size) : solid((0, 0, 1), size: size)
        }
    }

    /// What colour the written file shows at a moment.
    static func colour(of url: URL, atSeconds seconds: Double) async throws -> (r: Int, g: Int, b: Int) {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let frame = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = pixel.withUnsafeMutableBytes({ bytes in
            CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                      bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }) else { throw TestTone.Failure.noBuffer }
        // The whole frame squeezed into one pixel: for a flat picture that one
        // pixel IS the colour.
        context.interpolationQuality = .low
        context.draw(frame, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (Int(pixel[0]), Int(pixel[1]), Int(pixel[2]))
    }

    // MARK: - The picture

    @Test("The file runs as long as the document and shows what the document shows")
    func picturesLandWhereTheDocumentPutsThem() async throws {
        let plan = DocumentVideoExport.plan(durationMS: 2000,
                                            canvasSize: CGSize(width: 320, height: 240),
                                            format: .mp4, quality: .standard)
        let out = Self.folder.appendingPathComponent("two-halves.mp4")
        try await DocumentMovieWriter.write(plan: plan, mix: [], soundURLs: [:], to: out,
                                            frames: Self.twoHalves(plan: plan))

        let asset = AVURLAsset(url: out)
        let seconds = try await asset.load(.duration).seconds
        #expect(abs(seconds - 2) < 0.15)

        let size = await VideoExporter.orientedNaturalSize(of: out)
        #expect(size == CGSize(width: 320, height: 240))

        let early = try await Self.colour(of: out, atSeconds: 0.3)
        #expect(early.r > 200 && early.b < 60)
        let late = try await Self.colour(of: out, atSeconds: 1.7)
        #expect(late.b > 200 && late.r < 60)
    }

    @Test("A document with no sound in it writes a file with no sound track")
    func noSoundMeansNoSoundTrack() async throws {
        let plan = DocumentVideoExport.plan(durationMS: 600,
                                            canvasSize: CGSize(width: 160, height: 120),
                                            format: .mp4, quality: .standard)
        let out = Self.folder.appendingPathComponent("silent.mp4")
        try await DocumentMovieWriter.write(plan: plan, mix: [], soundURLs: [:], to: out,
                                            frames: Self.twoHalves(plan: plan))
        let tracks = try await AVURLAsset(url: out).loadTracks(withMediaType: .audio)
        #expect(tracks.isEmpty)
    }

    @Test("A frame with nothing on it comes out empty, not as the frame before it")
    func anEmptyFrameDoesNotKeepTheLastOne() async throws {
        // What a document does when its music runs past its last clip: the
        // picture is over, and every frame after it is empty. A writer that
        // draws each frame into a recycled buffer without clearing it first
        // leaves the last picture showing through, which reads as a freeze
        // frame nobody asked for.
        let plan = DocumentVideoExport.plan(durationMS: 2000,
                                            canvasSize: CGSize(width: 320, height: 240),
                                            format: .mp4, quality: .standard)
        let out = Self.folder.appendingPathComponent("goes-empty.mp4")
        let size = plan.size
        try await DocumentMovieWriter.write(plan: plan, mix: [], soundURLs: [:], to: out) { ms in
            ms < 1000 ? Self.solid((1, 0, 0), size: size) : Self.clear(size: size)
        }
        let early = try await Self.colour(of: out, atSeconds: 0.3)
        #expect(early.r > 200)
        let late = try await Self.colour(of: out, atSeconds: 1.7)
        #expect(late.r < 40 && late.g < 40 && late.b < 40)
    }

    /// A picture with nothing drawn on it at all.
    static func clear(size: CGSize) -> CGImage? {
        CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                  bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
    }

    // MARK: - The sound

    @Test("The sound in the file is the mix, in step with the picture")
    func theMixRidesWithThePicture() async throws {
        // A tone that is loud only between 4s and 6s of its own file, placed on
        // the timeline at 0: so the file that lands must be quiet early and
        // loud late, and the moment it turns is the mix's moment.
        let tone = Self.folder.appendingPathComponent("burst.m4a")
        if !FileManager.default.fileExists(atPath: tone.path) {
            try TestTone.writeBurst(to: tone, seconds: 8, loudFrom: 4, loudTo: 6)
        }
        var document = PhotonzDocument(canvasSize: CGSize(width: 160, height: 120), layers: [])
        let sound = SoundRef(durationMS: 8000)
        _ = document.addSound(sound, name: "tone", atMS: 0)
        document.durationMS = 8000

        let plan = DocumentVideoExport.plan(durationMS: 8000,
                                            canvasSize: document.canvasSize,
                                            format: .mp4, quality: .standard)
        let out = Self.folder.appendingPathComponent("with-sound.mp4")
        try await DocumentMovieWriter.write(plan: plan, mix: document.audioMix(),
                                            soundURLs: [sound.id: tone], to: out,
                                            frames: Self.twoHalves(plan: plan))

        let tracks = try await AVURLAsset(url: out).loadTracks(withMediaType: .audio)
        #expect(!tracks.isEmpty)
        let reading = try #require(await SoundFile.read(at: out))
        #expect(Self.loudness(reading.waveform, fromMS: 200, toMS: 3600) < 0.05)
        #expect(Self.loudness(reading.waveform, fromMS: 4400, toMS: 5600) > 0.2)
        // ...and the picture is still as long as the document, so nothing slid.
        let seconds = try await AVURLAsset(url: out).load(.duration).seconds
        #expect(abs(seconds - 8) < 0.3)
    }

    @Test("A level pulled down comes out quieter")
    func aLevelReachesTheFile() async throws {
        let tone = Self.folder.appendingPathComponent("flat.m4a")
        if !FileManager.default.fileExists(atPath: tone.path) {
            try TestTone.writeFlat(to: tone, seconds: 4)
        }
        var document = PhotonzDocument(canvasSize: CGSize(width: 160, height: 120), layers: [])
        let sound = SoundRef(durationMS: 4000)
        let added = document.addSound(sound, name: "tone", atMS: 0)
        let layerID = try #require(added)
        document.durationMS = 4000
        document.updateLayer(id: layerID) { $0.setSoundLevel(AudioLevel(gain: 0.1)) }

        let plan = DocumentVideoExport.plan(durationMS: 4000,
                                            canvasSize: document.canvasSize,
                                            format: .mp4, quality: .standard)
        let out = Self.folder.appendingPathComponent("quiet.mp4")
        try await DocumentMovieWriter.write(plan: plan, mix: document.audioMix(),
                                            soundURLs: [sound.id: tone], to: out,
                                            frames: Self.twoHalves(plan: plan))
        let reading = try #require(await SoundFile.read(at: out))
        #expect(Self.loudness(reading.waveform, fromMS: 400, toMS: 3600) < 0.12)
    }

    // MARK: - Stopping

    @Test("Cancelling leaves nothing half written behind")
    func cancellingLeavesNoFile() async throws {
        let plan = DocumentVideoExport.plan(durationMS: 20_000,
                                            canvasSize: CGSize(width: 640, height: 480),
                                            format: .mp4, quality: .standard)
        let out = Self.folder.appendingPathComponent("cancelled.mp4")
        let size = plan.size
        let task = Task {
            try await DocumentMovieWriter.write(plan: plan, mix: [], soundURLs: [:], to: out) { _ in
                // Slow enough that the cancel below lands mid-write.
                try? await Task.sleep(for: .milliseconds(20))
                return Self.solid((0, 1, 0), size: size)
            }
        }
        try await Task.sleep(for: .milliseconds(300))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(!FileManager.default.fileExists(atPath: out.path))
    }

    // MARK: - Animated pictures

    @Test("The same frames write a GIF at the preset's size")
    func aGIFComesOutAtThePresetSize() async throws {
        let plan = DocumentVideoExport.plan(durationMS: 1000,
                                            canvasSize: CGSize(width: 1600, height: 1200),
                                            format: .gif, quality: .small)
        let out = Self.folder.appendingPathComponent("small.gif")
        try await DocumentMovieWriter.writeAnimated(plan: plan, format: .gif, to: out,
                                                    frames: Self.twoHalves(plan: plan))
        let source = try #require(CGImageSourceCreateWithURL(out as CFURL, nil))
        #expect(CGImageSourceGetCount(source) == plan.frameCount)
        let first = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(first.width == 480)
    }

    /// How loud a stretch of a written file is, read the way the timeline reads
    /// a waveform.
    static func loudness(_ wave: Waveform, fromMS: Int, toMS: Int) -> Float {
        let lo = max(0, fromMS / Waveform.bucketMS)
        let hi = min(wave.peaks.count, toMS / Waveform.bucketMS)
        guard hi > lo else { return 0 }
        return wave.peaks[lo..<hi].reduce(0, +) / Float(hi - lo)
    }
}
