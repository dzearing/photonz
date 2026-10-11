import AVFoundation
import Foundation
import PhotonzCore

/// Writes a recording's mixed sound (`SoundMixTimeline`) to an AAC file as it
/// comes, so it is finished a moment after Stop.
///
/// Used from one queue at a time: the recorder appends on the queue that
/// mixes, and finishes once that queue has handed over its last chunk.
public final class RecordingSoundWriter: @unchecked Sendable {
    // @unchecked: AVAssetWriter and the pending list are only ever touched by
    // one caller at a time, the recorder's mixing queue and then its Stop.
    public let url: URL
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let channelCount: Int
    private let sampleRate: Double
    private var format: CMAudioFormatDescription?
    private var started = false
    private var pending: [CMSampleBuffer] = []
    private var appended = 0

    public init(url: URL, channelCount: Int = 2, sampleRate: Double = 48_000) throws {
        self.url = url
        self.channelCount = channelCount
        self.sampleRate = sampleRate
        try? FileManager.default.removeItem(at: url)
        writer = try AVAssetWriter(outputURL: url, fileType: .m4a)
        input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channelCount,
            AVEncoderBitRateKey: 192_000,
        ])
        input.expectsMediaDataInRealTime = true
        writer.add(input)
        var description = AudioStreamBasicDescription(
            mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(4 * channelCount), mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(4 * channelCount), mChannelsPerFrame: UInt32(channelCount),
            mBitsPerChannel: 32, mReserved: 0)
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &description, layoutSize: 0, layout: nil,
                                       magicCookieSize: 0, magicCookie: nil, extensions: nil,
                                       formatDescriptionOut: &format)
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    }

    /// Encode `chunk`, placed `startFrame` samples into the file.
    public func append(_ chunk: SoundMixTimeline.Chunk) {
        guard writer.status == .writing, let buffer = sampleBuffer(of: chunk) else { return }
        if !started {
            writer.startSession(atSourceTime: .zero)
            started = true
        }
        pending.append(buffer)
        flush()
    }

    private func flush() {
        while let next = pending.first, input.isReadyForMoreMediaData {
            pending.removeFirst()
            if input.append(next) { appended += 1 }
        }
    }

    /// Close the file. True when it holds sound; a writer given nothing, or
    /// one that failed, leaves no file.
    public func finish() async -> Bool {
        let deadline = ContinuousClock.now + .seconds(3)
        while !pending.isEmpty, writer.status == .writing, ContinuousClock.now < deadline {
            flush()
            if !pending.isEmpty { try? await Task.sleep(for: .milliseconds(2)) }
        }
        guard started, appended > 0, writer.status == .writing else {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            return false
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: url)
            return false
        }
        return true
    }

    /// The chunk as interleaved 32-bit float samples, stamped with its place.
    private func sampleBuffer(of chunk: SoundMixTimeline.Chunk) -> CMSampleBuffer? {
        let frames = chunk.frameCount
        guard frames > 0, let format, chunk.channels.count >= channelCount else { return nil }
        var interleaved = [Float](repeating: 0, count: frames * channelCount)
        for c in 0..<channelCount {
            let channel = chunk.channels[c]
            for i in 0..<frames { interleaved[i * channelCount + c] = channel[i] }
        }
        let length = interleaved.count * MemoryLayout<Float>.size
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
                allocator: nil, memoryBlock: nil, blockLength: length, blockAllocator: nil,
                customBlockSource: nil, offsetToData: 0, dataLength: length,
                flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block) == noErr,
              let block
        else { return nil }
        let copied = interleaved.withUnsafeBytes { bytes -> OSStatus in
            guard let base = bytes.baseAddress else { return -1 }
            return CMBlockBufferReplaceDataBytes(with: base, blockBuffer: block, offsetIntoDestination: 0,
                                                 dataLength: length)
        }
        guard copied == noErr else { return nil }
        var buffer: CMSampleBuffer?
        let at = CMTime(value: chunk.startFrame, timescale: CMTimeScale(sampleRate))
        guard CMAudioSampleBufferCreateReadyWithPacketDescriptions(
                allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: frames,
                presentationTimeStamp: at, packetDescriptions: nil, sampleBufferOut: &buffer) == noErr
        else { return nil }
        return buffer
    }
}

/// Puts a recording's pictures and its mixed sound in one file, at Stop.
///
/// Neither is encoded again: every picture and every packet of sound is
/// copied as it is, so it takes tens of milliseconds (measured 2026-10-11:
/// 23 ms for 10 s of a full screen, 46 ms for 45 s) and nothing moves. The
/// sound is cut where the pictures end, since the microphone is still heard
/// for a moment after the last frame.
public enum RecordingSoundMerge {
    public enum Failure: Error { case noPicture, noSound, couldNotWrite }

    public static func merge(picture: URL, sound: URL, into destination: URL) async throws {
        let pictureAsset = AVURLAsset(url: picture)
        let soundAsset = AVURLAsset(url: sound)
        guard let video = try await pictureAsset.loadTracks(withMediaType: .video).first,
              let videoFormat = try await video.load(.formatDescriptions).first
        else { throw Failure.noPicture }
        guard let audio = try? await soundAsset.loadTracks(withMediaType: .audio).first,
              let audioFormat = try await audio.load(.formatDescriptions).first
        else { throw Failure.noSound }
        let pictureEnd = try await video.load(.timeRange).end
        let transform = try await video.load(.preferredTransform)
        let copy = Copy(picture: pictureAsset, video: video, videoFormat: videoFormat, transform: transform,
                        sound: soundAsset, audio: audio, audioFormat: audioFormat, end: pictureEnd,
                        destination: destination)
        do {
            try await OffThePool.run { try copy.run() }
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    /// The copy itself, which blocks while it runs.
    private struct Copy: @unchecked Sendable {
        // @unchecked: the format descriptions are immutable Core Media objects
        // and the assets and tracks are only read; the copy runs on one queue.
        let picture: AVURLAsset
        let video: AVAssetTrack
        let videoFormat: CMFormatDescription
        let transform: CGAffineTransform
        let sound: AVURLAsset
        let audio: AVAssetTrack
        let audioFormat: CMFormatDescription
        let end: CMTime
        let destination: URL

        func run() throws {
            try? FileManager.default.removeItem(at: destination)
            let pictureReader = try AVAssetReader(asset: picture)
            let pictures = AVAssetReaderTrackOutput(track: video, outputSettings: nil)
            pictures.alwaysCopiesSampleData = false
            pictureReader.add(pictures)
            let soundReader = try AVAssetReader(asset: sound)
            soundReader.timeRange = CMTimeRange(start: .zero, end: end)
            let packets = AVAssetReaderTrackOutput(track: audio, outputSettings: nil)
            packets.alwaysCopiesSampleData = false
            soundReader.add(packets)

            let writer = try AVAssetWriter(outputURL: destination, fileType: .mp4)
            let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: videoFormat)
            videoInput.transform = transform
            videoInput.expectsMediaDataInRealTime = false
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: audioFormat)
            audioInput.expectsMediaDataInRealTime = false
            writer.add(videoInput)
            writer.add(audioInput)
            guard pictureReader.startReading(), soundReader.startReading(), writer.startWriting()
            else { throw writer.error ?? pictureReader.error ?? soundReader.error ?? Failure.couldNotWrite }
            writer.startSession(atSourceTime: .zero)

            // Each track is fed as the writer asks, so it interleaves them.
            let done = DispatchGroup()
            for (input, output, label) in [(videoInput, pictures, "pictures"), (audioInput, packets, "sound")] {
                done.enter()
                let feed = Feed(input: input, output: output)
                input.requestMediaDataWhenReady(on: DispatchQueue(label: "photonz.recording.merge.\(label)")) {
                    if feed.pump() { done.leave() }
                }
            }
            done.wait()
            let finished = DispatchSemaphore(value: 0)
            writer.finishWriting { finished.signal() }
            finished.wait()
            guard writer.status == .completed, pictureReader.status == .completed,
                  soundReader.status == .completed
            else { throw writer.error ?? pictureReader.error ?? soundReader.error ?? Failure.couldNotWrite }
        }
    }

    /// Hands one track's samples to the writer while it will take them.
    private final class Feed: @unchecked Sendable {
        // @unchecked: only ever pumped on the one queue the writer calls back on.
        let input: AVAssetWriterInput
        let output: AVAssetReaderTrackOutput
        private var finished = false

        init(input: AVAssetWriterInput, output: AVAssetReaderTrackOutput) {
            self.input = input
            self.output = output
        }

        /// True the one time the track runs out.
        func pump() -> Bool {
            guard !finished else { return false }
            while input.isReadyForMoreMediaData {
                guard let sample = output.copyNextSampleBuffer(), input.append(sample) else {
                    input.markAsFinished()
                    finished = true
                    return true
                }
            }
            return false
        }
    }
}

/// The samples of an uncompressed sound buffer, as floats from -1 to 1.
public enum PCMSamples {
    /// One array per channel, or nil for a buffer that is not plain PCM in a
    /// layout read here (32-bit float, or 16- or 32-bit integer).
    public static func channels(of sampleBuffer: CMSampleBuffer) -> [[Float]]? {
        guard let format = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
              asbd.mFormatID == kAudioFormatLinearPCM
        else { return nil }
        let frames = CMSampleBufferGetNumSamples(sampleBuffer)
        let channels = Int(asbd.mChannelsPerFrame)
        guard frames > 0, channels > 0 else { return nil }
        let isFloat = asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0
        let nonInterleaved = asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        let bits = Int(asbd.mBitsPerChannel)
        guard (isFloat && bits == 32) || (!isFloat && (bits == 16 || bits == 32)) else { return nil }

        var sizeNeeded = 0
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer, bufferListSizeNeededOut: &sizeNeeded, bufferListOut: nil, bufferListSize: 0,
            blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: nil)
        guard sizeNeeded > 0 else { return nil }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: sizeNeeded,
                                                   alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        let list = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
        var block: CMBlockBuffer?
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
                sampleBuffer, bufferListSizeNeededOut: nil, bufferListOut: list, bufferListSize: sizeNeeded,
                blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
                flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
                blockBufferOut: &block) == noErr
        else { return nil }

        func sample(_ data: UnsafeMutableRawPointer, _ index: Int) -> Float {
            if isFloat { return data.load(fromByteOffset: index * 4, as: Float.self) }
            if bits == 16 { return Float(data.load(fromByteOffset: index * 2, as: Int16.self)) / 32_768 }
            return Float(Double(data.load(fromByteOffset: index * 4, as: Int32.self)) / 2_147_483_648)
        }
        var out = [[Float]](repeating: [Float](repeating: 0, count: frames), count: channels)
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        if nonInterleaved {
            for c in 0..<min(channels, buffers.count) {
                guard let data = buffers[c].mData else { continue }
                let available = min(frames, Int(buffers[c].mDataByteSize) / (bits / 8))
                for i in 0..<available { out[c][i] = sample(data, i) }
            }
        } else if let first = buffers.first, let data = first.mData {
            let available = min(frames, Int(first.mDataByteSize) / (bits / 8) / channels)
            for i in 0..<available {
                for c in 0..<channels { out[c][i] = sample(data, i * channels + c) }
            }
        }
        return out
    }
}
