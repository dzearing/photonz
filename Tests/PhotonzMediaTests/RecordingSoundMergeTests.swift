import AVFoundation
import Foundation
import PhotonzCore
@testable import PhotonzMedia
import Testing

/// A recording with sound from both the Mac and the microphone has its mix
/// written while it records (`SoundMixTimeline`, `RecordingSoundWriter`), and
/// at Stop the pictures macOS wrote and that mix are put in one file
/// (`RecordingSoundMerge`) without encoding either again: tens of
/// milliseconds, where macOS mixing the two itself took 20 s for 45 s.
///
/// What matters is that nothing moves: the sound lands where it was heard,
/// to the millisecond, and every picture lands where it was.
@Suite("A recording's mixed sound is written as it records and joined to its pictures at Stop")
struct RecordingSoundMergeTests {
    private let rate = 48_000.0

    /// `seconds` of mix in tenth-second chunks, loud (a 440 Hz tone at 0.5)
    /// between `loudFrom` and `loudTo`, silent elsewhere.
    private func writeMix(to url: URL, seconds: Double, loudFrom: Double, loudTo: Double) async throws {
        let writer = try RecordingSoundWriter(url: url)
        let total = Int(seconds * rate)
        var frame = 0
        while frame < total {
            let count = min(SoundMixTimeline.maxChunkFrames, total - frame)
            var samples = [Float](repeating: 0, count: count)
            for i in 0..<count {
                let at = Double(frame + i) / rate
                if at >= loudFrom, at < loudTo { samples[i] = Float(0.5 * sin(2 * .pi * 440 * at)) }
            }
            writer.append(SoundMixTimeline.Chunk(startFrame: Int64(frame), channels: [samples, samples]))
            frame += count
        }
        let wrote = await writer.finish()
        #expect(wrote)
    }

    /// The first moment, in seconds, the sound at `url` gets loud.
    private func onset(of url: URL) async throws -> Double? {
        let samples = try await decodedLeft(of: url)
        guard let index = samples.firstIndex(where: { abs($0) > 0.05 }) else { return nil }
        return Double(index) / rate
    }

    private func decodedLeft(of url: URL) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        let track = try #require(try await asset.loadTracks(withMediaType: .audio).first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: rate,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ])
        reader.add(output)
        reader.startReading()
        var left: [Float] = []
        while let buffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var data = [Float](repeating: 0, count: length / 4)
            _ = data.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: $0.baseAddress!) }
            for i in stride(from: 0, to: data.count, by: 2) { left.append(data[i]) }
        }
        return left
    }

    @Test func theMixIsWrittenAsItComesAndSoundsWhereItWasHeard() async throws {
        let dir = TestClip.makeScratchDirectory()
        defer { TestClip.cleanUp(dir) }
        let sound = dir.appendingPathComponent("mix.m4a")
        try await writeMix(to: sound, seconds: 2, loudFrom: 1.0, loudTo: 1.2)
        let start = try #require(try await onset(of: sound))
        #expect(abs(start - 1.0) < 0.002, "the sound got loud at \(start) s, not 1 s")
        let duration = await TestClip.duration(of: sound)
        #expect(abs(duration - 2) < 0.03)
    }

    @Test func aWriterGivenNothingSaysSo() async throws {
        let dir = TestClip.makeScratchDirectory()
        defer { TestClip.cleanUp(dir) }
        let writer = try RecordingSoundWriter(url: dir.appendingPathComponent("empty.m4a"))
        let wrote = await writer.finish()
        #expect(!wrote)
    }

    @Test func thePicturesAndTheMixLandInOneFileWithNothingMoved() async throws {
        let dir = TestClip.makeScratchDirectory()
        defer { TestClip.cleanUp(dir) }
        let picture = dir.appendingPathComponent("picture.mp4")
        let sound = dir.appendingPathComponent("mix.m4a")
        let joined = dir.appendingPathComponent("joined.mp4")
        try await TestClip.write(to: picture, seconds: 2, likeAScreenRecording: true)
        try await writeMix(to: sound, seconds: 2, loudFrom: 0.5, loudTo: 0.7)

        try await RecordingSoundMerge.merge(picture: picture, sound: sound, into: joined)

        let asset = AVURLAsset(url: joined)
        #expect(try await asset.loadTracks(withMediaType: .video).count == 1)
        #expect(try await asset.loadTracks(withMediaType: .audio).count == 1)
        let start = try #require(try await onset(of: joined))
        #expect(abs(start - 0.5) < 0.002, "the sound got loud at \(start) s, not 0.5 s")
        for seconds in [0.0, 0.5, 1.0, 1.9] {
            let code = await TestClip.frameCode(at: seconds, in: joined)
            #expect(code?.index == Int((seconds * Double(TestClip.fps)).rounded()),
                    "the picture at \(seconds) s is frame \(String(describing: code?.index))")
        }
    }

    @Test func soundPastTheLastPictureIsLeftOut() async throws {
        let dir = TestClip.makeScratchDirectory()
        defer { TestClip.cleanUp(dir) }
        let picture = dir.appendingPathComponent("picture.mp4")
        let sound = dir.appendingPathComponent("mix.m4a")
        let joined = dir.appendingPathComponent("joined.mp4")
        try await TestClip.write(to: picture, seconds: 1)
        // The microphone stops a moment after the pictures do.
        try await writeMix(to: sound, seconds: 1.5, loudFrom: 0, loudTo: 1.5)

        try await RecordingSoundMerge.merge(picture: picture, sound: sound, into: joined)

        let duration = await TestClip.duration(of: joined)
        #expect(abs(duration - 1) < 0.03, "the joined file runs \(duration) s for 1 s of pictures")
    }

    @Test func aMissingMixLeavesNoFileBehind() async throws {
        let dir = TestClip.makeScratchDirectory()
        defer { TestClip.cleanUp(dir) }
        let picture = dir.appendingPathComponent("picture.mp4")
        let joined = dir.appendingPathComponent("joined.mp4")
        try await TestClip.write(to: picture, seconds: 1)
        await #expect(throws: (any Error).self) {
            try await RecordingSoundMerge.merge(picture: picture,
                                                sound: dir.appendingPathComponent("none.m4a"),
                                                into: joined)
        }
        #expect(!FileManager.default.fileExists(atPath: joined.path))
    }

    /// A sound buffer the way macOS hands one over, in either layout.
    private func pcmBuffer(frames: Int, channels: Int, nonInterleaved: Bool, int16: Bool,
                           value: (Int, Int) -> Float) throws -> CMSampleBuffer {
        let bytes = int16 ? 2 : 4
        var flags: AudioFormatFlags = int16 ? kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked
                                            : kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked
        if nonInterleaved { flags |= kAudioFormatFlagIsNonInterleaved }
        let perFrame = nonInterleaved ? bytes : bytes * channels
        var asbd = AudioStreamBasicDescription(
            mSampleRate: rate, mFormatID: kAudioFormatLinearPCM, mFormatFlags: flags,
            mBytesPerPacket: UInt32(perFrame), mFramesPerPacket: 1, mBytesPerFrame: UInt32(perFrame),
            mChannelsPerFrame: UInt32(channels), mBitsPerChannel: UInt32(bytes * 8), mReserved: 0)
        var format: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil,
                                       magicCookieSize: 0, magicCookie: nil, extensions: nil,
                                       formatDescriptionOut: &format)
        var data = Data()
        func put(_ v: Float) {
            if int16 { withUnsafeBytes(of: Int16(v * 32_767)) { data.append(contentsOf: $0) } }
            else { withUnsafeBytes(of: v) { data.append(contentsOf: $0) } }
        }
        if nonInterleaved {
            for c in 0..<channels { for i in 0..<frames { put(value(c, i)) } }
        } else {
            for i in 0..<frames { for c in 0..<channels { put(value(c, i)) } }
        }
        var block: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: data.count,
                                           blockAllocator: nil, customBlockSource: nil, offsetToData: 0,
                                           dataLength: data.count, flags: kCMBlockBufferAssureMemoryNowFlag,
                                           blockBufferOut: &block)
        let filled = try #require(block)
        _ = data.withUnsafeBytes { CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: filled,
                                                                  offsetIntoDestination: 0, dataLength: data.count) }
        var buffer: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: nil, dataBuffer: filled, formatDescription: try #require(format), sampleCount: frames,
            presentationTimeStamp: .zero, packetDescriptions: nil, sampleBufferOut: &buffer)
        return try #require(buffer)
    }

    @Test func theMacsSoundIsReadChannelByChannel() throws {
        let buffer = try pcmBuffer(frames: 512, channels: 2, nonInterleaved: true, int16: false) { c, i in
            c == 0 ? Float(i) / 1024 : -Float(i) / 1024
        }
        let channels = try #require(PCMSamples.channels(of: buffer))
        #expect(channels.count == 2)
        #expect(channels[0].count == 512)
        #expect(abs(channels[0][256] - 0.25) < 0.0001)
        #expect(abs(channels[1][256] + 0.25) < 0.0001)
    }

    @Test func aSixteenBitMicrophoneReadsTheSame() throws {
        let buffer = try pcmBuffer(frames: 480, channels: 2, nonInterleaved: false, int16: true) { c, _ in
            c == 0 ? 0.5 : -0.5
        }
        let channels = try #require(PCMSamples.channels(of: buffer))
        #expect(channels.count == 2)
        #expect(abs(channels[0][100] - 0.5) < 0.001)
        #expect(abs(channels[1][100] + 0.5) < 0.001)
    }
}
