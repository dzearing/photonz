import AVFoundation
import Foundation
import PhotonzCore
import Speech

// Listening to a recording (`docs/design/video-captions.md`).
//
// **On the machine, in pieces, stoppable.** Those three words are the whole
// design, and each of them was a decision with evidence behind it.
//
// ON THE MACHINE. macOS 26 ships `SpeechTranscriber`, which transcribes on
// device with word-level timings and confidences, needs no account, no network
// and no per-minute charge, and — unlike the older `SFSpeechRecognizer` — asks
// for no permission at all, because nothing leaves the Mac. Measured here on
// 2026-09-21: 7.5 seconds of speech transcribed in 0.25 seconds, about thirty
// times faster than listening to it. The alternative the user named was
// Whisper, which would mean carrying a model of tens to hundreds of megabytes
// in an app whose whole download is 8MB. It would have to be better by a wide
// margin to be worth that, and on this audio it is not: see the audit.
//
// IN PIECES. A recording is heard in windows of a couple of minutes rather than
// in one breath. Not because the recogniser cannot take more — it streams, so
// it can — but because everything a person wants from a long job needs the
// pieces: a progress reading that moves, a Stop that answers at once and KEEPS
// what it already heard, and a failure that costs one piece instead of forty
// minutes. The joins are the hard part, and they are handled by the two rules
// in `TranscriptSeam`: cut in a silence where there is one, overlap where there
// is not, and stitch by what was said rather than by the clock.
//
// STOPPABLE. Cancelling the task stops the feed, finishes the piece in flight,
// and hands back every word heard so far. Nothing is thrown away for having
// been interrupted.

/// What came back from listening.
public struct HeardWords: Sendable {

    /// Every word, on the recording's own clock, in order, each exactly once.
    public var words: [TranscribedWord]
    /// How much of the recording was actually listened to. Short of the whole
    /// length means somebody stopped it.
    public var listenedToMS: Int
    /// How long the recording runs for.
    public var ofMS: Int
    /// Whether it was stopped part way rather than finishing.
    public var wasStopped: Bool

    public init(words: [TranscribedWord] = [], listenedToMS: Int = 0, ofMS: Int = 0,
                wasStopped: Bool = false) {
        self.words = words
        self.listenedToMS = listenedToMS
        self.ofMS = ofMS
        self.wasStopped = wasStopped
    }

    public var isEmpty: Bool { words.isEmpty }
}

/// Why listening could not happen, said the way it would be said out loud.
public enum TranscriptionTrouble: LocalizedError, Sendable, Equatable {

    /// There is no sound track in the file at all.
    case noSound
    /// This Mac's speech recognition does not do this language.
    case noSuchLanguage(String)
    /// The language's model is not installed and could not be fetched.
    case languageNotInstalled(String)
    /// The file could not be read.
    case unreadable(String)

    public var errorDescription: String? {
        switch self {
        case .noSound:
            return Captions.nothingToHear
        case .noSuchLanguage(let name):
            return "This Mac's speech recognition does not do \(name)."
        case .languageNotInstalled(let name):
            return "The words for \(name) are not on this Mac yet, and downloading them did not work."
        case .unreadable(let why):
            return "That recording's sound could not be read: \(why)"
        }
    }
}

/// How far along, handed back while it works.
public struct TranscriptionProgress: Sendable {
    public var listenedToMS: Int
    public var ofMS: Int
    public var words: [TranscribedWord]

    public var reading: String {
        CaptionProgress.reading(doneMS: listenedToMS, ofMS: ofMS, words: words.count)
    }

    public var share: Double { CaptionProgress.share(doneMS: listenedToMS, ofMS: ofMS) }

    public init(listenedToMS: Int, ofMS: Int, words: [TranscribedWord]) {
        self.listenedToMS = listenedToMS
        self.ofMS = ofMS
        self.words = words
    }
}

/// Turning the sound of a recording into words with times on them.
public enum SpeechTranscription {

    /// Whether this Mac can transcribe at all.
    public static var isAvailable: Bool { SpeechTranscriber.isAvailable }

    /// The languages it can do, so a picker offers what exists rather than
    /// what somebody hoped for.
    public static func languages() async -> [Locale] {
        await SpeechTranscriber.supportedLocales
    }

    /// The supported language nearest the one asked for, or nil where there is
    /// none: `en-GB` asked for on a Mac that has `en_US` is a yes, not a no.
    public static func language(nearest locale: Locale) async -> Locale? {
        await SpeechTranscriber.supportedLocale(equivalentTo: locale)
    }

    /// Listen to a recording and hand back every word with the moment it was
    /// said.
    ///
    /// Cancelling the surrounding task stops it, and what it had already heard
    /// comes back rather than being thrown away.
    ///
    /// - Parameters:
    ///   - url: the recording or sound file. Anything AVFoundation reads.
    ///   - locale: the language being spoken.
    ///   - window: how long the pieces are and how far they lean into each
    ///     other. The default is two minutes with four seconds of overlap.
    ///   - onProgress: called on no particular actor as each piece lands, with
    ///     everything heard so far.
    public static func words(of url: URL, locale: Locale = Locale(identifier: "en-US"),
                             window: ChunkWindow = ChunkWindow(),
                             onProgress: (@Sendable (TranscriptionProgress) -> Void)? = nil)
        async throws -> HeardWords {

        let asset = AVURLAsset(url: url)
        let tracks: [AVAssetTrack]
        let duration: CMTime
        do {
            tracks = try await asset.loadTracks(withMediaType: .audio)
            duration = try await asset.load(.duration)
        } catch {
            // Handed something that is not a recording at all. Say that,
            // rather than letting AVFoundation's own wording out.
            throw TranscriptionTrouble.unreadable(error.localizedDescription)
        }
        guard let track = tracks.first else { throw TranscriptionTrouble.noSound }
        let durationMS = Int(duration.seconds * 1000)
        guard durationMS > 0 else { throw TranscriptionTrouble.noSound }

        guard let spoken = await language(nearest: locale) else {
            throw TranscriptionTrouble.noSuchLanguage(name(of: locale))
        }
        try await installWords(for: spoken)

        var heard: [TranscribedWord] = []
        var quiet: [Int] = []
        var listenedToMS = 0
        var stopped = false
        var start = 0

        while let chunk = TranscriptChunks.next(startingAt: start, durationMS: durationMS,
                                                quietMS: quiet, window: window) {
            if Task.isCancelled { stopped = true; break }
            let piece = try await listen(to: asset, track: track, chunk: chunk, locale: spoken)
            // Every piece comes back on ITS OWN clock, so the first thing that
            // happens to it is being put back on the recording's. An error here
            // is invisible at the start and enormous at the end.
            heard = TranscriptSeam.joined(heard, with: piece.words.map { $0.shifted(byMS: chunk.startMS) })
            quiet.append(contentsOf: piece.quietMS.map { $0 + chunk.startMS })
            listenedToMS = chunk.endMS
            onProgress?(TranscriptionProgress(listenedToMS: listenedToMS, ofMS: durationMS,
                                              words: heard))
            guard chunk.endMS < durationMS else { break }
            start = TranscriptChunks.start(after: chunk,
                                           cutInSilence: quiet.contains(chunk.endMS),
                                           window: window)
        }

        if Task.isCancelled { stopped = true }
        return HeardWords(words: heard, listenedToMS: listenedToMS, ofMS: durationMS,
                          wasStopped: stopped)
    }

    // MARK: - One piece

    private struct Piece: Sendable {
        var words: [TranscribedWord]
        /// Moments inside this piece where the sound went quiet for long
        /// enough that a cut there would land between words.
        var quietMS: [Int]
    }

    private static func listen(to asset: AVURLAsset, track: AVAssetTrack,
                               chunk: AudioChunk, locale: Locale) async throws -> Piece {
        let transcriber = SpeechTranscriber(locale: locale,
                                            transcriptionOptions: [],
                                            reportingOptions: [],
                                            attributeOptions: [.audioTimeRange,
                                                               .transcriptionConfidence])
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])

        let collecting = Task { () -> [TranscribedWord] in
            var words: [TranscribedWord] = []
            for try await result in transcriber.results {
                words.append(contentsOf: self.words(in: result.text))
            }
            return words
        }

        let quiet = try await feed(asset: asset, track: track, chunk: chunk,
                                   format: format, into: analyzer)
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        let words = try await collecting.value
        return Piece(words: words, quietMS: quiet)
    }

    /// Read this stretch of the recording's sound and hand it to the analyzer,
    /// noting where it went quiet on the way past.
    ///
    /// The sound is converted into EXACTLY the format the recogniser asked for
    /// (`bestAvailableAudioFormat`) rather than into one that looks like it.
    /// Those two are not the same thing: a buffer of the right rate and channel
    /// count in a format object the analyzer did not hand out crashes inside
    /// the framework rather than being refused, which is how this was found.
    private static func feed(asset: AVURLAsset, track: AVAssetTrack, chunk: AudioChunk,
                             format: AVAudioFormat?,
                             into analyzer: SpeechAnalyzer) async throws -> [Int] {
        let wanted = format ?? AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                                             channels: 1, interleaved: false)!
        let reader: AVAssetReader
        do { reader = try AVAssetReader(asset: asset) }
        catch { throw TranscriptionTrouble.unreadable(error.localizedDescription) }
        reader.timeRange = CMTimeRange(start: CMTime(value: CMTimeValue(chunk.startMS), timescale: 1000),
                                       duration: CMTime(value: CMTimeValue(chunk.lengthMS), timescale: 1000))
        // Read at the recogniser's own rate, in one channel: a voiceover is
        // mono whatever it was recorded as, and resampling once here is
        // cheaper than resampling every buffer twice.
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            // Not optional, and not the default for every file: an AIFF holds
            // its samples big-endian, and reading them as little-endian floats
            // gives numbers around 10^38 that the recogniser dutifully
            // transcribes as somebody clearing their throat.
            AVLinearPCMIsBigEndianKey: false,
            AVSampleRateKey: wanted.sampleRate,
            AVNumberOfChannelsKey: 1,
        ])
        guard reader.canAdd(output) else {
            throw TranscriptionTrouble.unreadable("this file's sound is in a form that cannot be read")
        }
        reader.add(output)
        guard reader.startReading() else {
            throw TranscriptionTrouble.unreadable(reader.error?.localizedDescription ?? "unknown")
        }

        let read = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: wanted.sampleRate,
                                 channels: 1, interleaved: false)!
        let converter = read == wanted ? nil : AVAudioConverter(from: read, to: wanted)
        let (stream, feed) = AsyncStream<AnalyzerInput>.makeStream()
        let running = Task { try await analyzer.start(inputSequence: stream) }

        var quiet = Silences(sampleRate: wanted.sampleRate)
        while let sample = output.copyNextSampleBuffer() {
            if Task.isCancelled { break }
            guard let buffer = pcm(from: sample, format: read) else { continue }
            quiet.listen(to: buffer)
            guard let ready = converted(buffer, by: converter, to: wanted) else { continue }
            // No timestamp on the buffer: the analyzer keeps its own clock
            // from the first sample it is handed, which is the start of THIS
            // piece, and stamping each buffer by hand only gives it two clocks
            // to disagree about ("audio input timestamp overlaps or precedes
            // prior audio input"). Putting the piece back on the recording's
            // clock is one addition, done once, by the caller.
            feed.yield(AnalyzerInput(buffer: ready))
        }
        feed.finish()
        reader.cancelReading()
        _ = try? await running.value
        return quiet.moments
    }

    /// The same sound in the format the recogniser handed out.
    private static func converted(_ buffer: AVAudioPCMBuffer, by converter: AVAudioConverter?,
                                  to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter else { return buffer }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var handed = false
        var trouble: NSError?
        converter.convert(to: out, error: &trouble) { _, status in
            if handed { status.pointee = .noDataNow; return nil }
            handed = true
            status.pointee = .haveData
            return buffer
        }
        guard trouble == nil, out.frameLength > 0 else { return nil }
        return out
    }

    /// An audio sample from the file as a buffer the analyzer takes.
    private static func pcm(from sample: CMSampleBuffer, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let block = CMSampleBufferGetDataBuffer(sample) else { return nil }
        let bytes = CMBlockBufferGetDataLength(block)
        let frames = AVAudioFrameCount(bytes / MemoryLayout<Float>.size)
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        guard CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: bytes,
                                         destination: channel) == kCMBlockBufferNoErr else { return nil }
        return buffer
    }

    // MARK: - Reading the answer

    /// The words in one result, with the times and the confidences the
    /// recogniser put on them.
    ///
    /// The answer is an `AttributedString` whose runs each carry the stretch of
    /// audio they were heard in, which is exactly one word per run with
    /// `.audioTimeRange` asked for.
    private static func words(in text: AttributedString) -> [TranscribedWord] {
        var words: [TranscribedWord] = []
        for run in text.runs {
            guard let range = run.audioTimeRange else { continue }
            let said = String(text[run.range].characters).trimmingCharacters(in: .whitespaces)
            guard !said.isEmpty else { continue }
            words.append(TranscribedWord(said,
                                         startMS: Int(range.start.seconds * 1000),
                                         endMS: Int(range.end.seconds * 1000),
                                         confidence: run.transcriptionConfidence.map(fraction(of:))))
        }
        return words
    }

    /// The recogniser's confidence as nought to one.
    ///
    /// It reports a `Double`, and the one thing not written down anywhere is
    /// the top of its scale, so this clamps rather than trusting: a score
    /// already inside nought to one is passed straight through and anything
    /// larger is held at one.
    private static func fraction(of score: Double) -> Double {
        min(1, max(0, score))
    }

    // MARK: - The language's words

    /// Make sure the language's model is on this Mac, fetching it once if it
    /// is not. Nothing is sent anywhere; this is Apple's own on-device model.
    private static func installWords(for locale: Locale) async throws {
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        guard await AssetInventory.status(forModules: [transcriber]) != .installed else { return }
        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
        } catch {
            throw TranscriptionTrouble.languageNotInstalled(name(of: locale))
        }
    }

    private static func name(of locale: Locale) -> String {
        Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
    }
}

// MARK: - Where it went quiet

/// Where the sound drops away for long enough that a cut there lands between
/// words rather than through one.
///
/// Measured on the samples going past on their way to the recogniser, so it
/// costs one pass over a buffer that has already been read rather than a pass
/// of its own over a forty minute file.
private struct Silences {

    /// Under this, averaged over a slice, nobody is talking. Well under speech
    /// and well above the noise floor of a screen recording.
    static let quietBelow: Float = 0.01
    /// How long the quiet has to last before the gap is a real gap rather than
    /// the pause between two syllables.
    static let longEnoughMS = 350
    /// How finely the sound is measured.
    static let sliceMS = 50

    let sampleRate: Double
    private(set) var moments: [Int] = []
    private var atMS = 0
    private var quietSinceMS: Int?
    private var carry: [Float] = []

    init(sampleRate: Double) { self.sampleRate = sampleRate }

    mutating func listen(to buffer: AVAudioPCMBuffer) {
        guard let samples = buffer.floatChannelData?[0] else { return }
        let perSlice = max(1, Int(sampleRate * Double(Self.sliceMS) / 1000))
        var index = 0
        let count = Int(buffer.frameLength)
        while index < count {
            let end = min(count, index + perSlice - carry.count)
            var sum: Float = carry.reduce(0) { $0 + $1 * $1 }
            for i in index..<end { sum += samples[i] * samples[i] }
            let taken = carry.count + (end - index)
            if taken < perSlice {
                // Not a whole slice: hold it for the next buffer rather than
                // calling a fragment loud or quiet on its own.
                carry.append(contentsOf: (index..<end).map { samples[$0] })
                break
            }
            carry = []
            let level = (sum / Float(taken)).squareRoot()
            note(level: level)
            index = end
        }
    }

    private mutating func note(level: Float) {
        if level < Self.quietBelow {
            if quietSinceMS == nil { quietSinceMS = atMS }
        } else {
            if let since = quietSinceMS, atMS - since >= Self.longEnoughMS {
                // The middle of the gap: the furthest point from either word.
                moments.append((since + atMS) / 2)
            }
            quietSinceMS = nil
        }
        atMS += Self.sliceMS
    }
}
