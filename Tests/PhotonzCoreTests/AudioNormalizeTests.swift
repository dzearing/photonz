import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Gain, Normalize and a waveform that shows quiet sound
/// (`docs/design/video-audio.md`, "Gain and Normalize").
///
/// A screen recording's system audio lands in the file at whatever level the
/// app that played it produced, which is routinely thirty or forty decibels
/// under full scale. Premiere's answer is Audio Gain > Normalize and a
/// waveform drawn in decibels; these are the numbers under both.
@Suite("Gain, Normalize, and a waveform that shows quiet sound")
struct AudioNormalizeTests {

    static func document(soundLengthMS: Int = 10_000) -> (PhotonzDocument, UUID) {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100), layers: [])
        let id = doc.addSound(SoundRef(durationMS: soundLengthMS), name: "system audio", atMS: 0)
        return (doc, id)
    }

    static func rounded(_ value: Double, _ places: Double = 10) -> Double {
        (value * places).rounded() / places
    }

    // MARK: - Gain on the segment

    @Test("Gain is a number of decibels on the segment, nought when nobody set it")
    func gainDefaultsToNothing() {
        let level = AudioLevel()
        #expect(level.clipGainDB == 0)
        #expect(level.clipGain == 1)
        #expect(level.isUntouched)
    }

    @Test("Gain is held inside what a boost may ask for, and a nonsense number is none")
    func gainIsBounded() {
        var level = AudioLevel()
        level.clipGainDB = 200
        #expect(level.clipGainDB == AudioLevel.clipGainRangeDB.upperBound)
        level.clipGainDB = -200
        #expect(level.clipGainDB == AudioLevel.clipGainRangeDB.lowerBound)
        level.clipGainDB = .nan
        #expect(level.clipGainDB == 0)
        // Enough to bring the quietest recording measured (peak -45 dBFS) up
        // to a normal level.
        #expect(AudioLevel.clipGainRangeDB.upperBound >= 45)
    }

    @Test("Gain multiplies everything that plays: fader, points and fades keep their shape")
    func gainMultipliesThePlan() throws {
        var (doc, id) = Self.document()
        var level = AudioLevel(gain: 0.5)
        level.setFadeIn(1000, lengthMS: 10_000)
        level.clipGainDB = 20
        doc.updateLayer(id: id) { $0.setSoundLevel(level) }
        let mix = doc.audioMix()
        let segment = try #require(mix.first)
        // Silence at the start of the fade is still silence.
        #expect(segment.gain(atMS: 0) == 0)
        // Half the level, ten times louder.
        #expect(Self.rounded(segment.gain(atMS: 5000)) == 5)
        // The fader and its line are unchanged: gain is a stage before them.
        #expect(level.gain(atLayerMS: 5000) == 0.5)
    }

    @Test("A segment with gain is no longer untouched, and gain alone survives a save")
    func gainIsWrittenAndRead() throws {
        var level = AudioLevel()
        level.clipGainDB = 12.5
        #expect(level.isUntouched == false)
        let data = try JSONEncoder().encode(level)
        let back = try JSONDecoder().decode(AudioLevel.self, from: data)
        #expect(back == level)
        #expect(back.clipGainDB == 12.5)
        // A level without gain writes no gain, so older documents read back
        // byte for byte.
        let plain = try JSONEncoder().encode(AudioLevel(gain: 0.5))
        #expect(String(decoding: plain, as: UTF8.self).contains("clipGain") == false)
    }

    @Test("The segment's label reads +N dB, signed, and says nothing at nought")
    func gainLabel() {
        var level = AudioLevel()
        #expect(level.clipGainLabel == nil)
        level.clipGainDB = 18.04
        #expect(level.clipGainLabel == "+18.0 dB")
        level.clipGainDB = -3.26
        #expect(level.clipGainLabel == "-3.3 dB")
        // What the panel shows: nought has a number there.
        #expect(AudioLevel().clipGainField == "0.0 dB")
        #expect(level.clipGainField == "-3.3 dB")
    }

    @Test("A typed gain reads with or without its dB and its plus sign")
    func typedGain() {
        #expect(AudioLevel.clipGainDB(typed: "+12") == 12)
        #expect(AudioLevel.clipGainDB(typed: "12 dB") == 12)
        #expect(AudioLevel.clipGainDB(typed: " -4.5db ") == -4.5)
        #expect(AudioLevel.clipGainDB(typed: "loud") == nil)
    }

    // MARK: - Normalize to a peak

    @Test("Normalize brings the loudest peak the segment plays to -1 dBFS")
    func normalizeToPeak() throws {
        // A recording peaking at -27.3 dBFS, the level the user's own system
        // audio came out at on 2026-09-25.
        let peak = Float(pow(10, -27.3 / 20))
        let wave = Waveform(peaks: Array(repeating: peak * 0.2, count: 400) + [peak]
                            + Array(repeating: peak * 0.2, count: 99))
        let pieces = ClipPieces(single: LayerTime(inMS: 0, outMS: wave.durationMS))
        let measured = try #require(AudioNormalize.peakDBFS(of: wave, playedBy: pieces))
        #expect(Self.rounded(measured) == -27.3)
        let gain = AudioNormalize.gainDB(toPeak: AudioNormalize.peakTargetDBFS, fromPeakDBFS: measured)
        #expect(Self.rounded(gain) == 26.3)
    }

    @Test("Normalize reads only the stretch the segment plays, not what a cut threw away")
    func normalizeReadsThePlayedStretch() throws {
        // Loud in the first second, quiet after it.
        let wave = Waveform(peaks: Array(repeating: 0.9, count: 50) + Array(repeating: 0.1, count: 450))
        // Keep from 2 s to 8 s of the file only.
        let pieces = ClipPieces(pieces: [ClipPiece(sourceInMS: 2000, lengthMS: 6000)])
        let measured = try #require(AudioNormalize.peakDBFS(of: wave, playedBy: pieces))
        #expect(Self.rounded(measured) == -20)
    }

    @Test("Nothing to hear is nothing to normalize")
    func silenceIsNotNormalized() {
        let wave = Waveform(peaks: Array(repeating: 0, count: 100))
        let pieces = ClipPieces(single: LayerTime(inMS: 0, outMS: 2000))
        #expect(AudioNormalize.peakDBFS(of: wave, playedBy: pieces) == nil)
    }

    // MARK: - Normalize to a loudness

    @Test("Loudness targets are the web's -14 LUFS and a podcast's -16")
    func loudnessTargets() {
        #expect(AudioNormalize.Target.web.lufs == -14)
        #expect(AudioNormalize.Target.podcast.lufs == -16)
    }

    @Test("Normalizing loudness moves the measured loudness onto the target")
    func normalizeToLoudness() {
        let gain = AudioNormalize.gainDB(toLoudness: -14, fromLUFS: -40, peakDBFS: -27.3)
        #expect(Self.rounded(gain) == 26)
    }

    @Test("Normalizing loudness never pushes a peak past -1 dBFS")
    func loudnessNeverClips() {
        // Loud on average, with peaks close to the top already: reaching -14
        // LUFS would need +10 dB, and the peak has room for 4.
        let gain = AudioNormalize.gainDB(toLoudness: -14, fromLUFS: -24, peakDBFS: -5)
        #expect(Self.rounded(gain) == 4)
    }

    // MARK: - Measuring loudness (ITU-R BS.1770)

    /// A 997 Hz tone, the calibration signal BS.1770 is specified against.
    static func tone(amplitude: Float, seconds: Double, rate: Double = 48_000,
                     channels: Int = 2) -> [Float] {
        let frames = Int(seconds * rate)
        var out = [Float](repeating: 0, count: frames * channels)
        for frame in 0..<frames {
            let value = amplitude * Float(sin(2 * Double.pi * 997 * Double(frame) / rate))
            for channel in 0..<channels { out[frame * channels + channel] = value }
        }
        return out
    }

    @Test("A full-scale tone in one channel of two measures -3.01 LUFS, as the standard says")
    func calibration() throws {
        var meter = LoudnessMeter(sampleRate: 48_000, channels: 2)
        let frames = 48_000 * 5
        var samples = [Float](repeating: 0, count: frames * 2)
        for frame in 0..<frames {
            samples[frame * 2] = Float(sin(2 * Double.pi * 997 * Double(frame) / 48_000))
        }
        meter.add(interleaved: samples)
        let lufs = try #require(meter.integratedLUFS)
        #expect(abs(lufs - -3.01) < 0.1)
    }

    @Test("A tone at -20 dBFS in both channels measures -20 LUFS, at 44.1 kHz too")
    func quieterAndOtherRates() throws {
        let amplitude = Float(pow(10, -20.0 / 20))
        for rate in [48_000.0, 44_100.0] {
            var meter = LoudnessMeter(sampleRate: rate, channels: 2)
            meter.add(interleaved: Self.tone(amplitude: amplitude, seconds: 4, rate: rate))
            let lufs = try #require(meter.integratedLUFS)
            #expect(abs(lufs - -20) < 0.15, "at \(rate) Hz measured \(lufs)")
        }
    }

    @Test("Silence between words does not drag the loudness down: the gates leave it out")
    func gatingIgnoresSilence() throws {
        let amplitude = Float(pow(10, -20.0 / 20))
        var meter = LoudnessMeter(sampleRate: 48_000, channels: 2)
        meter.add(interleaved: Self.tone(amplitude: amplitude, seconds: 3))
        meter.add(interleaved: [Float](repeating: 0, count: 48_000 * 2 * 6))
        meter.add(interleaved: Self.tone(amplitude: amplitude, seconds: 3))
        let lufs = try #require(meter.integratedLUFS)
        #expect(abs(lufs - -20) < 0.3)
    }

    @Test("Fed in pieces or all at once, the meter reads the same")
    func chunkingDoesNotMatter() throws {
        let samples = Self.tone(amplitude: 0.3, seconds: 3)
        var whole = LoudnessMeter(sampleRate: 48_000, channels: 2)
        whole.add(interleaved: samples)
        var pieces = LoudnessMeter(sampleRate: 48_000, channels: 2)
        var at = 0
        while at < samples.count {
            let end = min(samples.count, at + 1234 * 2)
            pieces.add(interleaved: Array(samples[at..<end]))
            at = end
        }
        let a = try #require(whole.integratedLUFS)
        let b = try #require(pieces.integratedLUFS)
        #expect(abs(a - b) < 0.001)
    }

    @Test("Less than one measuring block, or only silence, has no loudness")
    func tooShortOrSilent() {
        var short = LoudnessMeter(sampleRate: 48_000, channels: 2)
        short.add(interleaved: Self.tone(amplitude: 0.5, seconds: 0.2))
        #expect(short.integratedLUFS == nil)
        var silent = LoudnessMeter(sampleRate: 48_000, channels: 2)
        silent.add(interleaved: [Float](repeating: 0, count: 48_000 * 2 * 2))
        #expect(silent.integratedLUFS == nil)
    }

    // MARK: - The waveform shows quiet sound

    @Test("The waveform draws in decibels: a -30 dBFS peak is plainly visible")
    func waveformIsDecibelScaled() {
        let quiet = Waveform.drawnHeight(ofPeak: Float(pow(10, -30.0 / 20)))
        #expect(quiet > 0.3)
        #expect(Waveform.drawnHeight(ofPeak: 1) == 1)
        #expect(Waveform.drawnHeight(ofPeak: 0) == 0)
        // Below the floor is flat, so the hiss under a recording is not drawn
        // as if it were sound.
        #expect(Waveform.drawnHeight(ofPeak: Float(pow(10, -70.0 / 20))) == 0)
        // Louder always draws taller.
        #expect(Waveform.drawnHeight(ofPeak: 0.5) > Waveform.drawnHeight(ofPeak: 0.25))
    }

    @Test("Gain redraws the waveform: +20 dB draws a -30 dBFS peak where -10 dBFS draws")
    func waveformFollowsGain() {
        let quiet = Float(pow(10, -30.0 / 20))
        let louder = Float(pow(10, -10.0 / 20))
        let boosted = Waveform.drawnHeight(ofPeak: quiet, gainDB: 20)
        #expect(abs(boosted - Waveform.drawnHeight(ofPeak: louder)) < 0.001)
        // Past full scale draws full, never taller than the lane.
        #expect(Waveform.drawnHeight(ofPeak: 0.9, gainDB: 20) == 1)
    }
}
