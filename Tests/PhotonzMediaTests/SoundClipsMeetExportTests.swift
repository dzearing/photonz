import AVFoundation
import Foundation
import PhotonzCore
@testable import PhotonzMedia
import Testing

/// **Sound clips that meet play straight through.**
///
/// A music bed made of short loops laid end to end went silent for most of a
/// second just before one pair of loops handed over to the next, in a reel
/// whose sound files have no silence in them at all (2026-11-26,
/// `queue/audits/2026-11-26-sizzle-intake/`). The clip at 14 s of that reel had
/// been sped up to 200%, and its recording carries a sound track of its own.
///
/// Every test here writes a real mix and reads every sample of it back,
/// looking for the thing a person hears: a stretch longer than 10 ms quieter
/// than -45 dB anywhere a sound clip is playing.
@Suite("Sound clips that meet play straight through", .serialized)
struct SoundClipsMeetExportTests {

    static let folder = TestTone.scratch()

    static func tone(_ name: String, seconds: Double, amplitude: Double = 0.5) throws -> URL {
        let url = folder.appendingPathComponent("\(name).m4a")
        if !FileManager.default.fileExists(atPath: url.path) {
            try TestTone.writeFlat(to: url, seconds: seconds, amplitude: amplitude)
        }
        return url
    }

    static func piece(_ sound: SoundRef, at startMS: Int, length: Int, sourceIn: Int = 0,
                      speed: Int = 100, layer: UUID = UUID(), gain: Double = 1) -> AudioMixSegment {
        let read = length * speed / 100
        return AudioMixSegment(layerID: layer, sound: sound, startMS: startMS, lengthMS: length,
                               sourceInMS: sourceIn, sourceLengthMS: read, speedPercent: speed,
                               ramps: [AudioGainRamp(fromMS: startMS, toMS: startMS + length,
                                                     fromGain: gain, toGain: gain)])
    }

    /// Every sample of a written file, mixed down to one channel's loudest.
    static func samples(of url: URL) throws -> (samples: [Float], rate: Double) {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let count = AVAudioFrameCount(file.length)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count))
        try file.read(into: buffer)
        let channels = Int(format.channelCount)
        let data = try #require(buffer.floatChannelData)
        var out = [Float](repeating: 0, count: Int(buffer.frameLength))
        for index in 0..<out.count {
            var loudest: Float = 0
            for channel in 0..<channels { loudest = max(loudest, abs(data[channel][index])) }
            out[index] = loudest
        }
        return (out, format.sampleRate)
    }

    /// Every stretch over 10 ms quieter than -45 dB between two moments
    /// (`SoundDropouts`). Empty is what a mix with sound all the way through
    /// reads as; a file that ends before `toMS` has dropped out at its end.
    static func dropouts(in url: URL, fromMS: Int, toMS: Int) throws -> [SoundDropouts.Dropout] {
        let (samples, rate) = try samples(of: url)
        let lo = min(samples.count, Int(Double(fromMS) / 1000 * rate))
        let hi = min(samples.count, Int(Double(toMS) / 1000 * rate))
        var found = SoundDropouts.find(in: Array(samples[lo..<hi]), sampleRate: rate).map {
            SoundDropouts.Dropout(fromMS: $0.fromMS + Double(fromMS), toMS: $0.toMS + Double(fromMS))
        }
        let heardToMS = Double(samples.count) / rate * 1000
        if heardToMS < Double(toMS) - 10 {
            found.append(SoundDropouts.Dropout(fromMS: heardToMS, toMS: Double(toMS)))
        }
        return found
    }

    static func written(_ plan: [AudioMixSegment], urls: [UUID: URL], named name: String) async throws -> URL {
        let out = folder.appendingPathComponent("\(name)-out.m4a")
        try await AudioMixdown.write(plan, urls: urls, to: out)
        return out
    }

    // MARK: - The reel's music bed

    /// The reel as it was built, in the small: a loop at 0 and 6 s on one track,
    /// and a second loop over it from 2 s handing over at 6 s, with a sped-up
    /// clip whose recording is silent starting at 4 s on a track of its own.
    @Test("Loops that meet play straight through with a sped-up clip under them")
    func loopsMeetPastASpeedChange() async throws {
        let synthURL = try Self.tone("synth", seconds: 6)
        let beatURL = try Self.tone("beat", seconds: 4)
        let roomURL = try Self.tone("room", seconds: 6, amplitude: 0)
        let synth = SoundRef(durationMS: 6000)
        let beat = SoundRef(durationMS: 4000)
        let room = SoundRef(durationMS: 6000)
        let plan = [
            Self.piece(synth, at: 0, length: 6000),
            Self.piece(beat, at: 2000, length: 4000),
            Self.piece(room, at: 4000, length: 1500, speed: 200),
            Self.piece(synth, at: 6000, length: 6000),
            Self.piece(beat, at: 6000, length: 4000),
        ]
        let out = try await Self.written(plan, urls: [synth.id: synthURL, beat.id: beatURL,
                                                      room.id: roomURL], named: "reel-bed")
        let gaps = try Self.dropouts(in: out, fromMS: 0, toMS: 12_000)
        #expect(gaps.isEmpty, "\(SoundDropouts.describe(gaps))")
    }

    @Test("A sped-up clip leaves the music playing beside it at its own speed and length")
    func speedChangeStaysOnItsOwnClip() async throws {
        let musicURL = try Self.tone("music", seconds: 10)
        let roomURL = try Self.tone("room", seconds: 6, amplitude: 0)
        let music = SoundRef(durationMS: 10_000)
        let room = SoundRef(durationMS: 6000)
        let plan = [
            Self.piece(music, at: 0, length: 10_000),
            Self.piece(room, at: 3000, length: 1500, speed: 200),
        ]
        let out = try await Self.written(plan, urls: [music.id: musicURL, room.id: roomURL],
                                         named: "music-beside-speed")
        let gaps = try Self.dropouts(in: out, fromMS: 0, toMS: 10_000)
        #expect(gaps.isEmpty, "\(SoundDropouts.describe(gaps))")
    }

    @Test("A slowed-down clip leaves the music after it where it was put")
    func slowDownStaysOnItsOwnClip() async throws {
        let musicURL = try Self.tone("music", seconds: 10)
        let roomURL = try Self.tone("room", seconds: 6, amplitude: 0)
        let music = SoundRef(durationMS: 10_000)
        let room = SoundRef(durationMS: 6000)
        // Music in two halves meeting at 5 s, and a clip at half speed from 2 s
        // to 4 s: stretching the whole composition pushed the first half past
        // 5 s, where the second half was then refused for overlapping it.
        let plan = [
            Self.piece(music, at: 0, length: 5000),
            Self.piece(room, at: 2000, length: 2000, speed: 50),
            Self.piece(music, at: 5000, length: 5000, sourceIn: 5000),
        ]
        let out = try await Self.written(plan, urls: [music.id: musicURL, room.id: roomURL],
                                         named: "music-beside-slow")
        let gaps = try Self.dropouts(in: out, fromMS: 0, toMS: 10_000)
        #expect(gaps.isEmpty, "\(SoundDropouts.describe(gaps))")
        let length = try Self.samples(of: out)
        #expect(abs(Double(length.samples.count) / length.rate - 10) < 0.1)
    }

    @Test("Short loops end to end on one track play straight through")
    func loopsEndToEndOnOneTrack() async throws {
        let loopURL = try Self.tone("loop", seconds: 3.75)
        let loop = SoundRef(durationMS: 3750)
        let plan = (0..<4).map { Self.piece(loop, at: $0 * 3750, length: 3750) }
        let out = try await Self.written(plan, urls: [loop.id: loopURL], named: "loops")
        let gaps = try Self.dropouts(in: out, fromMS: 0, toMS: 15_000)
        #expect(gaps.isEmpty, "\(SoundDropouts.describe(gaps))")
    }
}
