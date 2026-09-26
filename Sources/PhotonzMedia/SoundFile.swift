import AVFoundation
import Foundation
import PhotonzCore

/// Reading a file's sound: how long it is, whether it has any, and its shape
/// (`docs/design/video-audio.md`).
///
/// The shape is a `Waveform` — one peak per twenty milliseconds — and it is
/// read here rather than in the document for the same reason pixels are:
/// **nothing about a file's contents belongs in the document model.** The
/// document holds a `SoundRef`; this turns a URL into what that reference
/// stands for.
public enum SoundFile {

    /// What a file's sound turns out to be.
    public struct Reading: Sendable {
        public let durationMS: Int
        public let waveform: Waveform

        public init(durationMS: Int, waveform: Waveform) {
            self.durationMS = durationMS
            self.waveform = waveform
        }
    }

    /// Whether this file has a sound track in it at all.
    public static func hasSound(at url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        guard let tracks = try? await asset.loadTracks(withMediaType: .audio) else { return false }
        return !tracks.isEmpty
    }

    /// How long a file's sound runs for, in milliseconds.
    public static func durationMS(at url: URL) async -> Int? {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration), duration.seconds.isFinite else { return nil }
        return Int((duration.seconds * 1000).rounded())
    }

    /// The whole reading: how long, and the shape.
    ///
    /// Decoded once, forward, in one pass. A file is read at whatever rate it
    /// was recorded at and reduced to fifty numbers a second as it goes, so a
    /// quarter of an hour of sound never exists in memory as samples — which is
    /// the difference between a waveform costing a few megabytes and costing a
    /// hundred.
    public static func read(at url: URL) async -> Reading? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
              let duration = try? await asset.load(.duration), duration.seconds.isFinite
        else { return nil }

        let durationMS = Int((duration.seconds * 1000).rounded())
        let peaks = (try? peaks(of: track, in: asset)) ?? []
        return Reading(durationMS: durationMS, waveform: Waveform(peaks: peaks))
    }

    /// The loudest sample in each bucket of the file, start to end.
    ///
    /// Every channel folded into one number, because a waveform on a timeline
    /// is a picture of how loud a moment is and a stereo pair drawn as two
    /// lanes is twice the ink for the same answer.
    private static func peaks(of track: AVAssetTrack, in asset: AVAsset) throws -> [Float] {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return [] }
        reader.add(output)
        guard reader.startReading() else { return [] }

        var peaks: [Float] = []
        var loudest: Float = 0
        var samplesInBucket = 0
        // Worked out off the first buffer's own format, because a file's rate
        // and channel count are the file's business and not something to guess.
        var samplesPerBucket = 0

        while let buffer = output.copyNextSampleBuffer() {
            defer { CMSampleBufferInvalidate(buffer) }
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            if samplesPerBucket == 0,
               let format = CMSampleBufferGetFormatDescription(buffer),
               let basic = CMAudioFormatDescriptionGetStreamBasicDescription(format) {
                let rate = basic.pointee.mSampleRate
                let channels = max(1, Int(basic.pointee.mChannelsPerFrame))
                samplesPerBucket = max(1, Int(rate * Double(Waveform.bucketMS) / 1000) * channels)
            }
            var length = 0
            var pointer: UnsafeMutablePointer<Int8>?
            guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil,
                                              totalLengthOut: &length,
                                              dataPointerOut: &pointer) == noErr,
                  let pointer else { continue }
            let count = length / MemoryLayout<Float>.size
            pointer.withMemoryRebound(to: Float.self, capacity: count) { samples in
                for index in 0..<count {
                    let value = abs(samples[index])
                    if value.isFinite, value > loudest { loudest = value }
                    samplesInBucket += 1
                    if samplesInBucket >= max(1, samplesPerBucket) {
                        peaks.append(min(1, loudest))
                        loudest = 0
                        samplesInBucket = 0
                    }
                }
            }
        }
        if samplesInBucket > 0 { peaks.append(min(1, loudest)) }
        return peaks
    }

    // MARK: - How loud it is

    /// The integrated loudness, in LUFS, of the stretches of a file a segment
    /// plays (`LoudnessMeter`), or nil where the file has no sound or those
    /// stretches are silence. What Normalize Loudness measures before it sets
    /// the gain, read off the file itself because a waveform's peaks say
    /// nothing about how loud something sounds.
    public static func loudnessLUFS(at url: URL, sourceRangesMS ranges: [Range<Int>]) async -> Double? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first else { return nil }
        var meter: LoudnessMeter?
        for range in ranges where !range.isEmpty {
            let timeRange = CMTimeRange(
                start: CMTime(value: CMTimeValue(range.lowerBound), timescale: 1000),
                duration: CMTime(value: CMTimeValue(range.count), timescale: 1000))
            guard let reader = try? AVAssetReader(asset: asset) else { return nil }
            reader.timeRange = timeRange
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ])
            guard reader.canAdd(output) else { return nil }
            reader.add(output)
            guard reader.startReading() else { return nil }
            var samples: [Float] = []
            while let buffer = output.copyNextSampleBuffer() {
                defer { CMSampleBufferInvalidate(buffer) }
                if meter == nil,
                   let format = CMSampleBufferGetFormatDescription(buffer),
                   let basic = CMAudioFormatDescriptionGetStreamBasicDescription(format) {
                    meter = LoudnessMeter(sampleRate: basic.pointee.mSampleRate,
                                          channels: max(1, Int(basic.pointee.mChannelsPerFrame)))
                }
                guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
                let length = CMBlockBufferGetDataLength(block)
                let count = length / MemoryLayout<Float>.size
                guard count > 0 else { continue }
                if samples.count != count { samples = [Float](repeating: 0, count: count) }
                let copied = samples.withUnsafeMutableBytes { raw -> OSStatus in
                    guard let base = raw.baseAddress else { return -1 }
                    return CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: count * 4,
                                                      destination: base)
                }
                guard copied == noErr else { continue }
                meter?.add(interleaved: samples)
            }
        }
        return meter?.integratedLUFS
    }
}
