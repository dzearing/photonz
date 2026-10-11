import Foundation

/// Mixes the sounds of one recording (the Mac's and the microphone's) into
/// one, as they arrive, on the clock they share.
///
/// macOS can mix the two itself, but it does that after Stop, at about 0.45 s
/// for every second recorded on a full screen (measured 2026-10-10: 20 s for a
/// 45 s recording), and Play waits for it. With one sound it closes the file in
/// under 100 ms. So the recorder gives macOS the Mac's sound only, hears both
/// itself, and mixes them here while recording: by Stop the mix is already
/// written.
///
/// Each sound arrives in buffers stamped with the moment they were heard, in
/// seconds on the shared clock. The mix counts in samples from the recording's
/// first frame (`setZero`), which is where the file starts. What both sounds
/// have reached comes out (`take`); a sound that falls silent holds the other
/// back by at most `maxLagSeconds`, after which it counts as silence and
/// anything it says later for that stretch is dropped. Stop lets everything
/// out (`take(finishing: true)`).
///
/// Pure: the recorder turns what it hears into channels of samples and asks
/// here.
public struct SoundMixTimeline: Sendable {
    public enum Source: Int, Sendable, Hashable, CaseIterable {
        case mac
        case microphone
    }

    /// A stretch of the mix, `startFrame` samples from the first frame.
    public struct Chunk: Sendable, Equatable {
        public let startFrame: Int64
        /// One array of samples per channel, all the same length.
        public let channels: [[Float]]
        public var frameCount: Int { channels.first?.count ?? 0 }

        public init(startFrame: Int64, channels: [[Float]]) {
            self.startFrame = startFrame
            self.channels = channels
        }
    }

    /// The longest stretch `take` hands out at once: a tenth of a second at
    /// 48 kHz, so the encoder is fed evenly.
    public static let maxChunkFrames = 4800

    public let channelCount: Int
    public let sampleRate: Double
    public let sources: Set<Source>
    private let maxLagFrames: Int64
    /// A buffer stamped this close to where its sound left off follows on from
    /// it: the stamps are rounded, and a one-sample gap or overlap is a click.
    private let snapFrames: Int64

    /// Absolute sample index (seconds times the rate) of `pending[c][0]`.
    private var base: Int64?
    private var pending: [[Float]]
    /// Where each sound's last buffer ended, as an absolute sample index.
    private var ends: [Source: Int64] = [:]
    /// The first frame, as an absolute sample index.
    private var zero: Int64?
    /// Nothing before this absolute index is accepted: it has been handed out.
    private var written: Int64?

    public init(sources: Set<Source>, channelCount: Int = 2, sampleRate: Double = 48_000,
                maxLagSeconds: Double = 2) {
        self.sources = sources
        self.channelCount = max(1, channelCount)
        self.sampleRate = sampleRate
        maxLagFrames = Int64((maxLagSeconds * sampleRate).rounded())
        snapFrames = max(1, Int64((sampleRate / 1000).rounded()))
        pending = Array(repeating: [], count: max(1, channelCount))
    }

    private func frame(_ seconds: Double) -> Int64 { Int64((seconds * sampleRate).rounded()) }

    /// The recording's first frame was taken at `seconds`: the mix starts there.
    public mutating func setZero(atSeconds seconds: Double) {
        guard zero == nil else { return }
        let at = frame(seconds)
        zero = at
        written = at
        trim(before: at)
    }

    /// `channels` of `source`, heard starting at `seconds`. One channel is
    /// heard on every side; more channels than the mix has are left out.
    public mutating func add(_ source: Source, atSeconds seconds: Double, channels: [[Float]]) {
        guard sources.contains(source), let length = channels.first?.count, length > 0 else { return }
        var start = frame(seconds)
        var skip = 0
        if let end = ends[source] {
            if abs(start - end) <= snapFrames {
                start = end
            } else if start < end {
                skip = Int(min(Int64(length), end - start))
            }
        }
        // What has been handed out already is too late to mix in.
        if let written, start + Int64(skip) < written {
            skip = Int(min(Int64(length), written - start))
        }
        ends[source] = max(ends[source] ?? start + Int64(length), start + Int64(length))
        guard skip < length else { return }
        let from = start + Int64(skip)
        if base == nil { base = from }
        guard var origin = base else { return }
        if from < origin {
            // Earlier than anything held (only before the first frame is known).
            let extra = Int(origin - from)
            for c in 0..<channelCount { pending[c].insert(contentsOf: repeatElement(0, count: extra), at: 0) }
            origin = from
            base = from
        }
        let offset = Int(from - origin)
        let needed = offset + (length - skip)
        for c in 0..<channelCount {
            let input = channels[min(c, channels.count - 1)]
            if pending[c].count < needed {
                pending[c].append(contentsOf: repeatElement(0, count: needed - pending[c].count))
            }
            pending[c].withUnsafeMutableBufferPointer { out in
                input.withUnsafeBufferPointer { inp in
                    for i in skip..<length { out[offset + i - skip] += inp[i] }
                }
            }
        }
    }

    /// The next stretch of the mix that is ready, or nil. While recording that
    /// is what every sound has reached, or what is more than the lag behind
    /// the newest; `finishing` lets out everything heard.
    public mutating func take(finishing: Bool = false) -> Chunk? {
        guard let zero, let from = written, let newest = ends.values.max() else { return nil }
        let ready: Int64
        if finishing {
            ready = newest
        } else {
            let heardFromAll = sources.allSatisfy { ends[$0] != nil }
            let together = heardFromAll ? (ends.values.min() ?? newest) : Int64.min
            ready = max(together, newest - maxLagFrames)
        }
        guard ready > from else { return nil }
        let count = Int(min(ready - from, Int64(Self.maxChunkFrames)))
        let origin = base ?? from
        let offset = Int(from - origin)
        var out: [[Float]] = []
        out.reserveCapacity(channelCount)
        for c in 0..<channelCount {
            var samples = [Float](repeating: 0, count: count)
            // The held samples may start after `from`: nothing was heard there.
            let held = pending[c]
            for i in min(count, max(0, -offset))..<count where offset + i < held.count {
                samples[i] = min(1, max(-1, held[offset + i]))
            }
            out.append(samples)
        }
        written = from + Int64(count)
        trim(before: from + Int64(count))
        return Chunk(startFrame: from - zero, channels: out)
    }

    /// Let go of the samples before `index`.
    private mutating func trim(before index: Int64) {
        guard let origin = base, index > origin else { return }
        let drop = Int(index - origin)
        for c in 0..<channelCount {
            if drop >= pending[c].count { pending[c].removeAll(keepingCapacity: true) }
            else { pending[c].removeFirst(drop) }
        }
        base = index
    }
}
