import Accelerate
import AVFoundation
import Foundation
import PhotonzCore

/// Clean noise: the cleaned copy of a sound, rendered on this Mac
/// (`docs/design/video-audio.md`, "Clean noise").
///
/// Spectral noise reduction, the way DeNoise works in every editor that has
/// one. The sound is cut into overlapping frames of about forty milliseconds;
/// in the pauses (`NoiseReduction.quietStretchesMS`) each frequency's level is
/// learned as the noise, and every frame then keeps each frequency in
/// proportion to how far it stands over that noise. The proportion is the
/// decision-directed Wiener gain (Ephraim and Malah), which follows speech
/// closely and does not flicker frame to frame in the noise, and that flicker
/// is what makes cheap noise reduction sound watery. Noise is never taken
/// further down than the strength's floor, so words never hang in a vacuum.
///
/// Two passes over the file, never the whole file in memory: one to learn the
/// noise from its quiet stretches, one to clean and write. The copy is written
/// lossless at the file's own rate and channel count, sample for sample in
/// step with the original, so a cut or a caption on it lands where it did.
public enum NoiseCleaner {

    public enum CleanError: Error { case noSound, unreadable, unwritable }

    /// What the cleaning learned and did, for anybody who wants to say so.
    public struct Result: Sendable {
        /// How many frames of noise the profile was learned from.
        public let framesLearned: Int
        public let sampleRate: Double
        public let channels: Int
    }

    /// Frames of about forty milliseconds, a power of two long: 2048 samples
    /// at 44.1 and 48 kHz, fine enough in frequency to take a hum out between
    /// the harmonics of a voice and short enough in time not to smear a word.
    public static func frameLength(sampleRate: Double) -> Int {
        var length = 256
        while Double(length) < sampleRate * 0.04 { length *= 2 }
        return length
    }

    /// The decision-directed smoothing: how much of the last frame's estimate
    /// of the voice carries into this one's.
    static let smoothing: Float = 0.98

    /// Clean `source` and write the cleaned copy to `destination`.
    ///
    /// `quietMS` is where the noise is (`NoiseReduction.quietStretchesMS`).
    /// `progress` is told nought to one as it goes. Cancelling the task stops
    /// it between chunks and leaves no file behind.
    @discardableResult
    public static func write(from source: URL, reduction: NoiseReduction, quietMS: [Range<Int>],
                             to destination: URL,
                             progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> Result {
        try await write(from: source, reduction: reduction, quietMS: quietMS, eq: nil, compressor: nil,
                        to: destination, progress: progress)
    }

    /// Make the copy a sound's Effects list asks for: the noise taken out
    /// where `reduction` says, then the EQ, then the compressor
    /// (`SoundShaper`). With no noise to take out the learning pass is
    /// skipped and the samples go straight to the shaping.
    @discardableResult
    public static func write(from source: URL, reduction: NoiseReduction?, quietMS: [Range<Int>],
                             eq: SoundEQ?, compressor: SoundCompressor?,
                             to destination: URL,
                             progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> Result {
        // Seconds of decoding and arithmetic: off the pool async work shares
        // (`OffThePool`).
        let calledOff = CalledOff()
        return try await withTaskCancellationHandler {
            try await OffThePool.run {
                try clean(source, reduction: reduction, quietMS: quietMS, eq: eq, compressor: compressor,
                          to: destination, calledOff: calledOff, progress: progress)
            }
        } onCancel: {
            calledOff.set()
        }
    }

    /// Whether the task that asked for a cleaning has been cancelled, read
    /// from the queue the cleaning runs on.
    final class CalledOff: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func set() { lock.withLock { value = true } }
        var isSet: Bool { lock.withLock { value } }
        func check() throws { if isSet { throw CancellationError() } }
    }

    private static func clean(_ source: URL, reduction: NoiseReduction?, quietMS: [Range<Int>],
                              eq: SoundEQ?, compressor: SoundCompressor?,
                              to destination: URL, calledOff: CalledOff,
                              progress: @Sendable (Double) -> Void) throws -> Result {
        guard let probe = try? AVAudioFile(forReading: source) else { throw CleanError.noSound }
        let rate = probe.processingFormat.sampleRate
        let channels = Int(probe.processingFormat.channelCount)
        let length = max(1, probe.length)
        guard rate > 0, channels > 0 else { throw CleanError.unreadable }
        // Told in hundredths, not once per chunk: the listener is a view.
        var told = -1.0
        func tell(_ value: Double) {
            guard value >= told + 0.01 || value >= 1 else { return }
            told = value
            progress(value)
        }

        // Pass one: learn the noise, where there is noise to take out.
        var learner = Learner(channels: channels, sampleRate: rate, quietMS: reduction == nil ? [] : quietMS)
        let learning = reduction == nil ? 0.0 : 0.3
        if reduction != nil {
            try read(source) { chunk in
                learner.add(chunk)
                tell(learning * Double(learner.consumed) / Double(length))
                try calledOff.check()
            }
        }
        let noise = learner.profile()
        let shaper = SoundShaper(sampleRate: rate, channels: channels, eq: eq, compressor: compressor)

        // Pass two: clean, and write.
        try? FileManager.default.removeItem(at: destination)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatAppleLossless,
            AVSampleRateKey: rate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitDepthHintKey: 24,
        ]
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate,
                                         channels: AVAudioChannelCount(channels)),
              let file = try? AVAudioFile(forWriting: destination, settings: settings,
                                          commonFormat: .pcmFormatFloat32, interleaved: false)
        else { throw CleanError.unwritable }
        var cleaners: [ChannelCleaner] = []
        if let reduction {
            for channel in 0..<channels {
                guard let cleaner = ChannelCleaner(sampleRate: rate, noise: noise.power[channel],
                                                   reduction: reduction) else { throw CleanError.unwritable }
                cleaners.append(cleaner)
            }
        }
        var total = 0
        var written = 0
        func shapeAndWrite(_ outs: [[Float]]) throws {
            var outs = outs
            shaper?.process(&outs)
            try write(outs, to: file, format: format)
            written += outs.first?.count ?? 0
        }
        do {
            try read(source) { chunk in
                total += chunk.first?.count ?? 0
                let outs = cleaners.isEmpty ? chunk : (0..<channels).map { cleaners[$0].push(chunk[$0]) }
                try shapeAndWrite(outs)
                tell(min(0.99, learning + (1 - learning) * Double(total) / Double(length)))
                try calledOff.check()
            }
            // What is still inside the frames, cut to exactly the length read.
            let owed = max(0, total - written)
            if !cleaners.isEmpty {
                try shapeAndWrite(cleaners.map { Array($0.finish().prefix(owed)) })
            }
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        tell(1)
        return Result(framesLearned: noise.frames, sampleRate: rate, channels: channels)
    }

    private static func write(_ channels: [[Float]], to file: AVAudioFile, format: AVAudioFormat) throws {
        let frames = channels.first?.count ?? 0
        guard frames > 0 else { return }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let data = buffer.floatChannelData else { throw CleanError.unwritable }
        buffer.frameLength = AVAudioFrameCount(frames)
        for (channel, samples) in channels.enumerated() {
            samples.withUnsafeBufferPointer { source in
                guard let base = source.baseAddress else { return }
                data[channel].update(from: base, count: frames)
            }
        }
        try file.write(from: buffer)
    }

    // MARK: - Reading

    /// Every sample of the file, a channel per array, chunk by chunk: read the
    /// way the player reads it, so the cleaned copy lines up with what plays.
    private static func read(_ url: URL, _ body: ([[Float]]) throws -> Void) throws {
        guard let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 16_384)
        else { throw CleanError.unreadable }
        let channels = Int(file.processingFormat.channelCount)
        while file.framePosition < file.length {
            do { try file.read(into: buffer) } catch { throw CleanError.unreadable }
            let frames = Int(buffer.frameLength)
            guard frames > 0, let data = buffer.floatChannelData else { break }
            try body((0..<channels).map { Array(UnsafeBufferPointer(start: data[$0], count: frames)) })
        }
    }

    // MARK: - Learning the noise

    /// The noise, per channel: the average power of each frequency over the
    /// frames that fell wholly inside a quiet stretch. Where the pauses are
    /// all shorter than a frame, the frames centred in one are used instead.
    struct Learner {
        let channels: Int
        let sampleRate: Double
        let length: Int
        let hop: Int
        let quietMS: [Range<Int>]
        private var buffers: [[Float]]
        private var bufferStart = 0
        private(set) var consumed = 0
        private var strict: [[Float]]
        private var strictCount = 0
        private var centred: [[Float]]
        private var centredCount = 0
        private var nextStretch = 0
        private let spectrum: Spectrum?

        init(channels: Int, sampleRate: Double, quietMS: [Range<Int>]) {
            self.channels = channels
            self.sampleRate = sampleRate
            length = NoiseCleaner.frameLength(sampleRate: sampleRate)
            hop = length / 4
            self.quietMS = quietMS.sorted { $0.lowerBound < $1.lowerBound }
            buffers = Array(repeating: [], count: channels)
            strict = Array(repeating: [Float](repeating: 0, count: length / 2 + 1), count: channels)
            centred = strict
            spectrum = Spectrum(length: length)
        }

        mutating func add(_ chunk: [[Float]]) {
            let frames = chunk.first?.count ?? 0
            for channel in 0..<min(channels, chunk.count) {
                buffers[channel].append(contentsOf: chunk[channel])
            }
            consumed += frames
            var used = 0
            while buffers[0].count - used >= length {
                look(atFrame: bufferStart + used, offset: used)
                used += hop
            }
            if used > 0 {
                for channel in 0..<channels { buffers[channel].removeFirst(used) }
                bufferStart += used
            }
        }

        private mutating func look(atFrame start: Int, offset: Int) {
            guard !quietMS.isEmpty, let spectrum else { return }
            let fromMS = Int(Double(start) * 1000 / sampleRate)
            let toMS = Int(Double(start + length) * 1000 / sampleRate)
            let middleMS = (fromMS + toMS) / 2
            while nextStretch < quietMS.count, quietMS[nextStretch].upperBound <= fromMS { nextStretch += 1 }
            var whole = false, centre = false
            var index = nextStretch
            while index < quietMS.count, quietMS[index].lowerBound < toMS {
                let stretch = quietMS[index]
                if stretch.lowerBound <= fromMS, stretch.upperBound >= toMS { whole = true }
                if stretch.contains(middleMS) { centre = true }
                index += 1
            }
            guard whole || centre else { return }
            for channel in 0..<channels {
                let power = buffers[channel].withUnsafeBufferPointer { samples in
                    spectrum.power(of: samples, from: offset)
                }
                if whole { Self.add(power, to: &strict[channel]) }
                if centre { Self.add(power, to: &centred[channel]) }
            }
            if whole { strictCount += 1 }
            if centre { centredCount += 1 }
        }

        private static func add(_ power: [Float], to total: inout [Float]) {
            for bin in 0..<min(power.count, total.count) { total[bin] += power[bin] }
        }

        func profile() -> (power: [[Float]], frames: Int) {
            let (sums, count) = strictCount >= 4 ? (strict, strictCount) : (centred, centredCount)
            guard count > 0 else {
                return (Array(repeating: [Float](repeating: 0, count: length / 2 + 1), count: channels), 0)
            }
            return (sums.map { $0.map { $0 / Float(count) } }, count)
        }
    }

    // MARK: - Cleaning one channel

    /// One channel cleaned as it streams through: frames a quarter apart,
    /// windowed in and out, added back together.
    final class ChannelCleaner {
        let length: Int
        let hop: Int
        private let spectrum: Spectrum
        /// The noise, taken out as many times as the strength says.
        private let noise: [Float]
        private let floor: Float
        private var pending: [Float]
        private var overlap: [Float]
        private var previousVoice: [Float]
        private var toDrop: Int

        init?(sampleRate: Double, noise: [Float], reduction: NoiseReduction) {
            length = NoiseCleaner.frameLength(sampleRate: sampleRate)
            hop = length / 4
            guard let spectrum = Spectrum(length: length) else { return nil }
            self.spectrum = spectrum
            let over = Float(reduction.oversubtraction)
            self.noise = (0...(length / 2)).map { $0 < noise.count ? noise[$0] * over : 0 }
            floor = Float(pow(10, reduction.floorDB / 20))
            // Primed with silence so the first real sample is covered by as
            // many frames as every other, and dropped again on the way out.
            pending = [Float](repeating: 0, count: length - hop)
            overlap = [Float](repeating: 0, count: length)
            previousVoice = [Float](repeating: 0, count: length / 2 + 1)
            toDrop = length - hop
        }

        /// Feed samples in; what has been cleaned so far comes out, running
        /// a frame behind what went in.
        func push(_ samples: [Float]) -> [Float] {
            pending.append(contentsOf: samples)
            var out: [Float] = []
            var used = 0
            while pending.count - used >= length {
                clean(from: used)
                out.append(contentsOf: overlap[0..<hop])
                overlap.removeFirst(hop)
                overlap.append(contentsOf: repeatElement(0, count: hop))
                used += hop
            }
            if used > 0 { pending.removeFirst(used) }
            if toDrop > 0 {
                let dropping = min(toDrop, out.count)
                out.removeFirst(dropping)
                toDrop -= dropping
            }
            return out
        }

        /// Everything still inside the frames.
        func finish() -> [Float] {
            push([Float](repeating: 0, count: length))
        }

        private func clean(from offset: Int) {
            pending.withUnsafeBufferPointer { samples in
                spectrum.transform(samples, from: offset) { power, gains in
                    for bin in 0..<power.count {
                        let noisePower = noise[bin]
                        guard noisePower > 0 else { gains[bin] = 1; continue }
                        let posterior = power[bin] / noisePower
                        let prior = NoiseCleaner.smoothing * previousVoice[bin] / noisePower
                            + (1 - NoiseCleaner.smoothing) * max(posterior - 1, 0)
                        let wiener = prior / (1 + prior)
                        previousVoice[bin] = wiener * wiener * power[bin]
                        gains[bin] = max(wiener, floor)
                    }
                }
            }
            spectrum.addInverse(into: &overlap)
        }
    }

    // MARK: - The transform

    /// A windowed real FFT of one length, forward and back.
    final class Spectrum {
        let length: Int
        private let log2n: vDSP_Length
        private let setup: FFTSetup
        private let window: [Float]
        private var windowed: [Float]
        private var real: [Float]
        private var imaginary: [Float]
        private var power: [Float]
        private var gains: [Float]
        /// Forward is twice the DFT and back is `length` times, and a Hann
        /// window in and out at a quarter hop sums to one and a half.
        private let scale: Float

        init?(length: Int) {
            self.length = length
            log2n = vDSP_Length(log2(Double(length)).rounded())
            guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return nil }
            self.setup = setup
            window = (0..<length).map { 0.5 - 0.5 * Float(cos(2 * Double.pi * Double($0) / Double(length))) }
            windowed = [Float](repeating: 0, count: length)
            real = [Float](repeating: 0, count: length / 2)
            imaginary = [Float](repeating: 0, count: length / 2)
            power = [Float](repeating: 0, count: length / 2 + 1)
            gains = [Float](repeating: 1, count: length / 2 + 1)
            scale = 1 / (2 * Float(length) * 1.5)
        }

        deinit { vDSP_destroy_fftsetup(setup) }

        /// The power of each frequency in the frame starting at `offset`.
        func power(of samples: UnsafeBufferPointer<Float>, from offset: Int) -> [Float] {
            forward(samples, from: offset)
            measure()
            return power
        }

        /// Transform the frame at `offset`, let `shape` say how much of each
        /// frequency to keep, and apply it. `addInverse` then brings it back.
        func transform(_ samples: UnsafeBufferPointer<Float>, from offset: Int,
                       shape: ([Float], inout [Float]) -> Void) {
            forward(samples, from: offset)
            measure()
            shape(power, &gains)
            let half = length / 2
            real[0] *= gains[0]
            imaginary[0] *= gains[half]
            for bin in 1..<half {
                real[bin] *= gains[bin]
                imaginary[bin] *= gains[bin]
            }
        }

        /// The frame back in time, windowed again, added onto `overlap`.
        func addInverse(into overlap: inout [Float]) {
            let half = length / 2
            real.withUnsafeMutableBufferPointer { re in
                imaginary.withUnsafeMutableBufferPointer { im in
                    guard let reBase = re.baseAddress, let imBase = im.baseAddress else { return }
                    var split = DSPSplitComplex(realp: reBase, imagp: imBase)
                    vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_INVERSE))
                    windowed.withUnsafeMutableBufferPointer { out in
                        guard let outBase = out.baseAddress else { return }
                        outBase.withMemoryRebound(to: DSPComplex.self, capacity: half) { complex in
                            vDSP_ztoc(&split, 1, complex, 2, vDSP_Length(half))
                        }
                    }
                }
            }
            for index in 0..<length {
                overlap[index] += windowed[index] * window[index] * scale
            }
        }

        private func forward(_ samples: UnsafeBufferPointer<Float>, from offset: Int) {
            let half = length / 2
            for index in 0..<length {
                let at = offset + index
                windowed[index] = at < samples.count ? samples[at] * window[index] : 0
            }
            real.withUnsafeMutableBufferPointer { re in
                imaginary.withUnsafeMutableBufferPointer { im in
                    guard let reBase = re.baseAddress, let imBase = im.baseAddress else { return }
                    var split = DSPSplitComplex(realp: reBase, imagp: imBase)
                    windowed.withUnsafeBufferPointer { input in
                        guard let inBase = input.baseAddress else { return }
                        inBase.withMemoryRebound(to: DSPComplex.self, capacity: half) { complex in
                            vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(half))
                        }
                    }
                    vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                }
            }
        }

        private func measure() {
            let half = length / 2
            power[0] = real[0] * real[0]
            power[half] = imaginary[0] * imaginary[0]
            for bin in 1..<half {
                power[bin] = real[bin] * real[bin] + imaginary[bin] * imaginary[bin]
            }
        }
    }
}
