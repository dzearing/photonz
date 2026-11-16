import AVFoundation
import CoreGraphics
import CoreImage
import CoreMedia
import Foundation
import PhotonzCore
@testable import PhotonzMedia
import Testing
import VideoToolbox

/// **A screen recording plays with the screen's colours, and its dark
/// gradients stay smooth.**
///
/// The frames here are made exactly the way the screen recording stream hands
/// its 10-bit frames over (Display P3 on the sRGB curve, encoded with the
/// BT.601 matrix in video range, and carrying no colour tags of their own),
/// written by `RecordingFileWriter`, and read back the way QuickTime and the
/// editor read a recording. Measured on the real stream on 2026-11-15
/// (docs/progress/2026-11-15-recording-colour.md).
@Suite("A recording's file keeps the screen's colours and smooth gradients", .serialized)
struct RecordingFileWriterTests {

    static let folder = TestTone.scratch()
    static let size = CGSize(width: 640, height: 360)

    // MARK: - Frames as the stream makes them

    /// A 10-bit 4:2:0 video-range frame, 601 matrix, from `p3(x, y)`: Display
    /// P3 R'G'B' (sRGB curve) from 0 to 1. Untagged, as the stream's are.
    static func frame(_ p3: (Int, Int) -> (Double, Double, Double)) throws -> CVPixelBuffer {
        let width = Int(size.width), height = Int(size.height)
        var made: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
                            [kCVPixelBufferIOSurfacePropertiesKey: [String: Any]()] as CFDictionary, &made)
        let buffer = try #require(made)
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        func ycc(_ c: (Double, Double, Double)) -> (y: Double, cb: Double, cr: Double) {
            let y = 0.299 * c.0 + 0.587 * c.1 + 0.114 * c.2
            return (y, (c.2 - y) / 1.772, (c.0 - y) / 1.402)
        }
        func code(_ v: Double) -> UInt16 { UInt16(max(0, min(1023, v.rounded()))) << 6 }
        let luma = try #require(CVPixelBufferGetBaseAddressOfPlane(buffer, 0)).assumingMemoryBound(to: UInt16.self)
        let lumaStride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0) / 2
        for y in 0..<height {
            for x in 0..<width { luma[y * lumaStride + x] = code(64 + 876 * ycc(p3(x, y)).y) }
        }
        let chroma = try #require(CVPixelBufferGetBaseAddressOfPlane(buffer, 1)).assumingMemoryBound(to: UInt16.self)
        let chromaStride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1) / 2
        for y in 0..<(height / 2) {
            for x in 0..<(width / 2) {
                let c = ycc(p3(x * 2, y * 2))
                chroma[y * chromaStride + x * 2] = code(512 + 896 * c.cb)
                chroma[y * chromaStride + x * 2 + 1] = code(512 + 896 * c.cr)
            }
        }
        return buffer
    }

    static func sample(_ buffer: CVPixelBuffer, at seconds: Double) throws -> CMSampleBuffer {
        var format: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: buffer, formatDescriptionOut: &format)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30),
                                        presentationTimeStamp: CMTime(seconds: seconds, preferredTimescale: 90_000),
                                        decodeTimeStamp: .invalid)
        var made: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: buffer,
                                                 formatDescription: try #require(format),
                                                 sampleTiming: &timing, sampleBufferOut: &made)
        return try #require(made)
    }

    /// Write `frames` at 30 a second, starting at a host-clock-like moment
    /// (the stream's frames are stamped on the host clock, not from zero).
    static func write(_ name: String, frames: [CVPixelBuffer], sound: Bool = false,
                      quality: RecordingQuality = .best) async throws -> URL {
        let url = folder.appendingPathComponent(name)
        let writer = try RecordingFileWriter(url: url, pixelSize: size, fps: 30, withSound: sound, quality: quality)
        let start = 81_234.5
        for (index, buffer) in frames.enumerated() {
            let at = start + Double(index) / 30
            var tries = 0
            while !writer.append(picture: try sample(buffer, at: at)) {
                if let failure = writer.failure {
                    Issue.record("frame \(index) of \(frames.count): \(writer.frameCounts) \(failure)")
                    throw failure
                }
                tries += 1
                try #require(tries < 200, "the encoder never took frame \(index)")
                try await Task.sleep(for: .milliseconds(5))
            }
            if sound { writer.append(sound: try tone(at: at, seconds: 1.0 / 30)) }
        }
        #expect(await writer.finish())
        return url
    }

    /// Stereo float sound as the stream hands it over.
    static func tone(at seconds: Double, seconds length: Double) throws -> CMSampleBuffer {
        let rate = 48_000.0
        let count = Int(rate * length)
        var asbd = AudioStreamBasicDescription(mSampleRate: rate, mFormatID: kAudioFormatLinearPCM,
                                               mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
                                               mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8,
                                               mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
        var format: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil,
                                       magicCookieSize: 0, magicCookie: nil, extensions: nil,
                                       formatDescriptionOut: &format)
        var samples = [Float](repeating: 0, count: count * 2)
        for i in 0..<count {
            let v = Float(0.5 * sin(2 * .pi * 440 * (seconds + Double(i) / rate)))
            samples[i * 2] = v
            samples[i * 2 + 1] = v
        }
        var block: CMBlockBuffer?
        let bytes = count * 8
        CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: bytes, blockAllocator: nil,
                                           customBlockSource: nil, offsetToData: 0, dataLength: bytes, flags: 0,
                                           blockBufferOut: &block)
        let data = try #require(block)
        samples.withUnsafeBytes { raw in
            _ = CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: data, offsetIntoDestination: 0,
                                              dataLength: bytes)
        }
        var made: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: nil, dataBuffer: data, formatDescription: try #require(format), sampleCount: count,
            presentationTimeStamp: CMTime(seconds: seconds, preferredTimescale: 48_000),
            packetDescriptions: nil, sampleBufferOut: &made)
        return try #require(made)
    }

    // MARK: - Reading it back

    /// What QuickTime shows at `seconds`: AVFoundation's own decode, colour
    /// matched into Display P3, as floats in code values (0 to 255).
    static func played(_ url: URL, at seconds: Double) async throws -> (width: Int, pixels: [Float]) {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let image = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
        return try p3(image)
    }

    /// What the editor shows: its own decode (`MovieFrames.picture(of:)`), to
    /// the format `MovieDecodeFormat` picks.
    static func edited(_ url: URL, at seconds: Double, eightBit: Bool = false) async throws -> (width: Int, pixels: [Float]) {
        let asset = AVURLAsset(url: url)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let format = try #require(try await track.load(.formatDescriptions).first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: eightBit
                ? kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange : MovieDecodeFormat.pixelFormat(for: format)])
        reader.add(output)
        reader.timeRange = CMTimeRange(start: CMTime(seconds: seconds, preferredTimescale: 600),
                                       duration: CMTime(seconds: 1, preferredTimescale: 600))
        reader.startReading()
        let sample = try #require(output.copyNextSampleBuffer())
        let buffer = try #require(CMSampleBufferGetImageBuffer(sample))
        let colours = CVBufferCopyAttachments(buffer, .shouldPropagate)
            .flatMap { CVImageBufferCreateColorSpaceFromAttachments($0)?.takeRetainedValue() }
            ?? CGColorSpace(name: CGColorSpace.sRGB)
        let ci = CIImage(cvPixelBuffer: buffer)
        let image = try #require(CIContext().createCGImage(ci, from: ci.extent, format: .RGBA8, colorSpace: colours))
        reader.cancelReading()
        return try p3(image)
    }

    /// The image colour matched into Display P3, as floats in code values.
    static func p3(_ image: CGImage) throws -> (width: Int, pixels: [Float]) {
        let width = image.width, height = image.height
        let space = try #require(CGColorSpace(name: CGColorSpace.extendedDisplayP3))
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 32, bytesPerRow: width * 16, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let data = try #require(context.data)
        let floats = Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self), count: width * height * 4))
        return (width, floats.map { $0 * 255 })
    }

    /// The mean colour of a block, in Display P3 code values.
    static func mean(_ read: (width: Int, pixels: [Float]), x: Range<Int>, y: Range<Int>) -> [Double] {
        var sum = [0.0, 0.0, 0.0], n = 0.0
        for row in y { for column in x {
            let i = (row * read.width + column) * 4
            for c in 0..<3 { sum[c] += Double(read.pixels[i + c]) }
            n += 1
        } }
        return sum.map { $0 / n }
    }

    // MARK: - The file

    @Test("It is 10-bit HEVC that says Display P3, the sRGB curve and the 601 matrix")
    func fileSaysWhatItHolds() async throws {
        let grey = try Self.frame { _, _ in (0.5, 0.5, 0.5) }
        let url = try await Self.write("tags.mp4", frames: Array(repeating: grey, count: 10))
        let asset = AVURLAsset(url: url)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let format = try #require(try await track.load(.formatDescriptions).first)
        #expect(CMFormatDescriptionGetMediaSubType(format) == kCMVideoCodecType_HEVC)
        func tag(_ key: CFString) -> String? { CMFormatDescriptionGetExtension(format, extensionKey: key) as? String }
        #expect(tag(kCMFormatDescriptionExtension_ColorPrimaries) == kCMFormatDescriptionColorPrimaries_P3_D65 as String)
        #expect(tag(kCMFormatDescriptionExtension_TransferFunction) == kCMFormatDescriptionTransferFunction_sRGB as String)
        #expect(tag(kCMFormatDescriptionExtension_YCbCrMatrix) == kCMFormatDescriptionYCbCrMatrix_ITU_R_601_4 as String)
        #expect(StoredWay.bitDepth(of: format) == 10)
        #expect(MovieDecodeFormat.pixelFormat(for: format) == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange)
        #expect(StoredWay.encoderProfile(of: format) == kVTProfileLevel_HEVC_Main10_AutoLevel)
        // It starts at its first frame, not at the host clock's moment.
        let duration = try await asset.load(.duration).seconds
        #expect(abs(duration - 10.0 / 30) < 0.05, "\(duration)")
    }

    @Test("An 8-bit H.264 file is still decoded to 8 bits")
    func eightBitStaysEightBit() async throws {
        let url = Self.folder.appendingPathComponent("eight.mp4")
        try await MovieColourTests.appleStyleRecording([(r: 128, g: 128, b: 128)], to: url)
        let track = try #require(try await AVURLAsset(url: url).loadTracks(withMediaType: .video).first)
        let format = try #require(try await track.load(.formatDescriptions).first)
        #expect(StoredWay.bitDepth(of: format) == 8)
        #expect(MovieDecodeFormat.pixelFormat(for: format) == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
    }

    /// Display P3 R'G'B' for each swatch: greys, the sRGB primaries as P3
    /// holds them, Display P3's own red and green (beyond sRGB), and the dark
    /// purple of a translucent terminal.
    static let swatches: [(name: String, p3: (Double, Double, Double))] = [
        ("grey 16", (16 / 255, 16 / 255, 16 / 255)), ("grey 76", (76 / 255, 76 / 255, 76 / 255)),
        ("grey 128", (128 / 255, 128 / 255, 128 / 255)), ("grey 200", (200 / 255, 200 / 255, 200 / 255)),
        ("sRGB red", (0.9175, 0.2003, 0.1386)), ("sRGB green", (0.4584, 0.9853, 0.2983)),
        ("P3 red", (1, 0, 0)), ("P3 green", (0, 1, 0)), ("purple", (43.0 / 255, 30.0 / 255, 63.0 / 255)),
    ]

    @Test("Every swatch plays within two code values of what the screen showed, in QuickTime and in the editor")
    func swatchesPlayAsTheScreenShowedThem() async throws {
        let frames = try Self.swatches.map { swatch in try Self.frame { _, _ in swatch.p3 } }
        // Ten frames of each, so each sits a third of a second.
        let url = try await Self.write("swatches.mp4", frames: frames.flatMap { Array(repeating: $0, count: 10) })
        for (index, swatch) in Self.swatches.enumerated() {
            let at = (Double(index) * 10 + 5) / 30
            let want = [swatch.p3.0, swatch.p3.1, swatch.p3.2].map { $0 * 255 }
            for (how, read) in [("QuickTime", try await Self.played(url, at: at)),
                                ("editor", try await Self.edited(url, at: at))] {
                let got = Self.mean(read, x: 200..<440, y: 100..<260)
                let off = zip(got, want).map { abs($0 - $1) }.max() ?? 99
                #expect(off <= 2, "\(swatch.name) in \(how): wrote \(want.map { Int($0.rounded()) }), plays \(got.map { ($0 * 10).rounded() / 10 })")
            }
        }
    }

    /// A slow dark ramp across the frame: Display P3 grey 16 to 56.
    static func ramp() throws -> CVPixelBuffer {
        try frame { x, _ in
            let v = (16 + 40 * Double(x) / (size.width - 1)) / 255
            return (v, v, v)
        }
    }

    /// The biggest jump across four pixels of the ramp, in code values. A
    /// smooth ramp of 40 levels over 640 pixels has steps of one; the old
    /// 8-bit recording had jumps of three.
    static func biggestJump(_ read: (width: Int, pixels: [Float])) -> Double {
        let columns = (8..<(read.width - 8)).map { x in mean(read, x: x..<(x + 1), y: 150..<210)[1] }
        return zip(columns, columns.dropFirst(4)).map { abs($1 - $0) }.max() ?? 99
    }

    @Test("A slow dark gradient has no step of more than one code value, in QuickTime and in the editor")
    func darkGradientStaysSmooth() async throws {
        let url = try await Self.write("ramp.mp4", frames: Array(repeating: try Self.ramp(), count: 15))
        let played = try await Self.played(url, at: 0.25)
        let edited = try await Self.edited(url, at: 0.25)
        #expect(Self.biggestJump(played) <= 1.2, "QuickTime: \(Self.biggestJump(played))")
        // The editor's pictures are 8-bit, so a band there is one code value
        // at least, and the encoder's noise across rows adds a fraction.
        #expect(Self.biggestJump(edited) <= 1.5, "editor: \(Self.biggestJump(edited))")

        let ends = Self.mean(played, x: 10..<14, y: 150..<210)[1]
        #expect(abs(ends - 16.5) < 1.5, "the dark end plays \(ends)")
    }

    @Test("Smaller files writes the same kind of file, as smooth")
    func smallerFiles() async throws {
        let url = try await Self.write("ramp-smaller.mp4", frames: Array(repeating: try Self.ramp(), count: 15), quality: .smaller)
        let track = try #require(try await AVURLAsset(url: url).loadTracks(withMediaType: .video).first)
        let format = try #require(try await track.load(.formatDescriptions).first)
        #expect(StoredWay.bitDepth(of: format) == 10)
        let played = try await Self.played(url, at: 0.25)
        #expect(Self.biggestJump(played) <= 1.2, "QuickTime: \(Self.biggestJump(played))")
        #expect(Self.biggestJump(try await Self.edited(url, at: 0.25)) <= 1.5)
        // Decoded to 8 bits on the way, as every movie used to be, the bands
        // come straight back (at Best the file keeps the screen's own dither,
        // which hides them even then).
        let squeezed = try await Self.edited(url, at: 0.25, eightBit: true)
        #expect(Self.biggestJump(squeezed) > 1.5, "decoded to 8 bits: \(Self.biggestJump(squeezed))")
    }

    @Test("The sound heard after the first frame is in the file")
    func soundIsWritten() async throws {
        let grey = try Self.frame { _, _ in (0.3, 0.3, 0.3) }
        let url = try await Self.write("sound.mp4", frames: Array(repeating: grey, count: 30), sound: true)
        let asset = AVURLAsset(url: url)
        let audio = try #require(try await asset.loadTracks(withMediaType: .audio).first)
        let range = try await audio.load(.timeRange)
        #expect(range.duration.seconds > 0.8, "\(range.duration.seconds)")
        let format = try #require(try await audio.load(.formatDescriptions).first)
        #expect(CMFormatDescriptionGetMediaSubType(format) == kAudioFormatMPEG4AAC)
    }

    @Test("A recording nothing was written to leaves no file")
    func nothingWrittenLeavesNothing() async throws {
        let url = Self.folder.appendingPathComponent("empty.mp4")
        let writer = try RecordingFileWriter(url: url, pixelSize: Self.size, fps: 30, withSound: false)
        #expect(await writer.finish() == false)
        writer.abandon()
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("Its export keeps the colours a sRGB file can hold")
    func exportKeepsTheColours() async throws {
        let inside = Self.swatches.filter { !$0.name.hasPrefix("P3") }
        let frames = try inside.map { swatch in try Self.frame { _, _ in swatch.p3 } }
        let source = try await Self.write("export-source.mp4", frames: frames.flatMap { Array(repeating: $0, count: 30) })
        let out = Self.folder.appendingPathComponent("export.mp4")
        let recipe = VideoExportQuality.high.recipe(format: .mp4, sourceSize: Self.size, sourceFPS: 30)
        try await VideoExporter.exportMP4(
            from: source, to: out,
            cuts: VideoCutList(pieces: [VideoPiece(start: 0, end: Double(inside.count))],
                               sourceDuration: Double(inside.count)),
            crop: nil, recipe: recipe)
        try await MovieColourTests.expectTagged(out)
        for index in inside.indices {
            let original = try await DocumentMovieWriterTests.colour(of: source, atSeconds: Double(index) + 0.5)
            let exported = try await DocumentMovieWriterTests.colour(of: out, atSeconds: Double(index) + 0.5)
            #expect(MovieColourTests.near(exported, original, within: 2),
                    "\(inside[index].name): the recording plays \(original), its export \(exported)")
        }
    }
}
