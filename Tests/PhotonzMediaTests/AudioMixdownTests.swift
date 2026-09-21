import AVFoundation
import CoreGraphics
import Foundation
import PhotonzCore
@testable import PhotonzMedia
import Testing

/// **The mix that plays and the mix that exports are the same mix.**
///
/// That is an acceptance item nobody can settle by ear in a test, so it is
/// settled by construction and then MEASURED: `PhotonzDocument.audioMix()` is
/// the only answer to what plays, `DocumentAudioPlayer` schedules it and
/// `AudioMixdown` writes it, and these tests take the written file apart again
/// and check that what came out is the shape the plan asked for.
///
/// Everything here is a real file. A tone is written, mixed, exported and read
/// back through the same `SoundFile` reader the timeline draws its waveform
/// from, so a peak in one of these assertions is a peak somebody would hear.
@Suite("A mix exports the way it plays", .serialized)
struct AudioMixdownTests {

    static let folder = TestTone.scratch()

    /// Ten seconds at one steady level.
    static func flatTone(_ name: String, seconds: Double = 10) throws -> URL {
        let url = folder.appendingPathComponent("\(name).m4a")
        if !FileManager.default.fileExists(atPath: url.path) {
            try TestTone.writeFlat(to: url, seconds: seconds)
        }
        return url
    }

    /// Ten seconds that are loud only in the middle two, so a cut can be proved
    /// to have kept the part it says it kept.
    static func burstTone(_ name: String) throws -> URL {
        let url = folder.appendingPathComponent("\(name).m4a")
        if !FileManager.default.fileExists(atPath: url.path) {
            try TestTone.writeBurst(to: url, seconds: 10, loudFrom: 4, loudTo: 6)
        }
        return url
    }

    static func document() -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 100, height: 100), layers: [])
    }

    /// Export a plan and read the loudness of the result straight back.
    static func exported(_ mix: [AudioMixSegment], urls: [UUID: URL],
                         named name: String) async throws -> Waveform {
        let out = folder.appendingPathComponent("\(name)-out.m4a")
        try await AudioMixdown.write(mix, urls: urls, to: out)
        let reading = try #require(await SoundFile.read(at: out))
        return reading.waveform
    }

    /// How loud a stretch of the written file is. A mean rather than a peak,
    /// because an encoder's attack and release move a single peak around and a
    /// second of level does not move at all.
    static func loudness(_ wave: Waveform, fromMS: Int, toMS: Int) -> Float {
        let lo = max(0, fromMS / Waveform.bucketMS)
        let hi = min(wave.peaks.count, toMS / Waveform.bucketMS)
        guard hi > lo else { return 0 }
        return wave.peaks[lo..<hi].reduce(0, +) / Float(hi - lo)
    }

    // MARK: - One sound

    @Test("A sound placed on the timeline comes out where it was placed")
    func onePiecePlacedInTime() async throws {
        let url = try Self.flatTone("flat")
        var doc = Self.document()
        let sound = SoundRef(durationMS: 4000)
        _ = doc.addSound(sound, name: "tone", atMS: 3000)
        let wave = try await Self.exported(doc.audioMix(), urls: [sound.id: url],
                                           named: "placed")
        // Silence where nothing was put, sound where something was.
        #expect(Self.loudness(wave, fromMS: 200, toMS: 2600) < 0.05)
        #expect(Self.loudness(wave, fromMS: 3400, toMS: 6600) > 0.2)
    }

    @Test("A cut sound exports the part of the file it kept, not the part it dropped")
    func cutKeepsWhatItSays() async throws {
        let url = try Self.burstTone("burst")
        var doc = Self.document()
        let sound = SoundRef(durationMS: 10_000)
        let id = doc.addSound(sound, name: "burst", atMS: 0)
        // Keep only the loud middle: cut at 4s and 6s, throw the ends away.
        let cutA = doc.splitClip(id, atMS: 4000)
        let cutB = doc.splitClip(id, atMS: 6000)
        let droppedTail = doc.removeClipPiece(id, at: 2)
        let droppedHead = doc.removeClipPiece(id, at: 0)
        #expect(cutA && cutB && droppedTail && droppedHead)
        let mix = doc.audioMix()
        #expect(mix.count == 1)
        #expect(mix[0].sourceInMS == 4000)

        let wave = try await Self.exported(mix, urls: [sound.id: url], named: "cut")
        // What is left is two seconds, and all of it is the loud part: the cut
        // moved the kept stretch to the front of the timeline and threw away
        // the silence that used to be either side of it.
        #expect(Self.loudness(wave, fromMS: 200, toMS: 1800) > 0.2)
        #expect(wave.durationMS < 2600)
    }

    // MARK: - Level

    @Test("A level pulled down comes out quieter, by about as much as it was pulled")
    func levelIsHonoured() async throws {
        let url = try Self.flatTone("flat")
        let sound = SoundRef(durationMS: 4000)

        var loud = Self.document()
        _ = loud.addSound(sound, name: "tone", atMS: 0)
        let atFull = try await Self.exported(loud.audioMix(), urls: [sound.id: url],
                                              named: "full")

        var quiet = Self.document()
        _ = quiet.addSound(sound, name: "tone", atMS: 0)
        quiet.layers[0].setSoundLevel(AudioLevel(gain: 0.25))
        let atQuarter = try await Self.exported(quiet.audioMix(), urls: [sound.id: url],
                                                 named: "quarter")

        let full = Self.loudness(atFull, fromMS: 500, toMS: 3500)
        let quarter = Self.loudness(atQuarter, fromMS: 500, toMS: 3500)
        #expect(full > 0.2)
        // A quarter of the level, give or take what an encoder does to it.
        #expect(quarter < full * 0.45)
        #expect(quarter > full * 0.1)
    }

    @Test("A duck exports as a duck: the music really is quieter under the voice")
    func aDuckIsAudibleInTheFile() async throws {
        let url = try Self.flatTone("flat")
        var doc = Self.document()
        let music = SoundRef(durationMS: 8000)
        let id = doc.addSound(music, name: "music", atMS: 0)
        // Down over a fifth of a second at 2s, back up at 5s: two points either
        // side of a dip, which is all a duck is.
        var level = AudioLevel()
        level.setPoint(atMS: 1800, gain: 1)
        level.setPoint(atMS: 2000, gain: 0.15)
        level.setPoint(atMS: 5000, gain: 0.15)
        level.setPoint(atMS: 5200, gain: 1)
        doc.updateLayer(id: id) { $0.setSoundLevel(level) }

        let segment = try #require(doc.audioMix().first)
        // The plan says it in ramps on the document's own clock, which is what
        // the export is built from and what the player follows.
        #expect(segment.ramps.map(\.fromMS) == [0, 1800, 2000, 5000, 5200])

        let wave = try await Self.exported(doc.audioMix(), urls: [music.id: url], named: "duck")
        let before = Self.loudness(wave, fromMS: 400, toMS: 1600)
        let under = Self.loudness(wave, fromMS: 2400, toMS: 4600)
        let after = Self.loudness(wave, fromMS: 5600, toMS: 7600)
        #expect(before > 0.2)
        #expect(after > 0.2)
        #expect(under < before * 0.45)
        #expect(under < after * 0.45)
    }

    // MARK: - Several at once

    @Test("Three sounds laid over each other all come out, and where they overlap it is louder")
    func severalSoundsMixTogether() async throws {
        let bed = try Self.flatTone("bed")
        var doc = Self.document()
        let a = SoundRef(durationMS: 6000)
        let b = SoundRef(durationMS: 6000)
        let c = SoundRef(durationMS: 6000)
        _ = doc.addSound(a, name: "one", atMS: 0)
        _ = doc.addSound(b, name: "two", atMS: 2000)
        _ = doc.addSound(c, name: "three", atMS: 4000)
        // All three at a quarter, so three together is still inside the ceiling
        // and the difference between one and three is a difference in level
        // rather than a clip.
        for index in doc.layers.indices {
            doc.layers[index].setSoundLevel(AudioLevel(gain: 0.25))
        }
        let mix = doc.audioMix()
        #expect(mix.count == 3)
        #expect(doc.audioMix(atMS: 5000).count == 3)

        let urls = [a.id: bed, b.id: bed, c.id: bed]
        let wave = try await Self.exported(mix, urls: urls, named: "three")
        let alone = Self.loudness(wave, fromMS: 400, toMS: 1600)
        let together = Self.loudness(wave, fromMS: 4400, toMS: 5600)
        #expect(alone > 0.05)
        #expect(together > alone * 1.5)
        // ...and it runs as long as the last one leaves.
        #expect(wave.durationMS > 9000)
    }

    @Test("A sound with nothing behind it is refused rather than written as an empty file")
    func nothingToMixIsRefused() async throws {
        let sound = SoundRef(durationMS: 1000)
        var doc = Self.document()
        _ = doc.addSound(sound, name: "missing", atMS: 0)
        await #expect(throws: (any Error).self) {
            try await AudioMixdown.write(doc.audioMix(), urls: [:],
                                         to: Self.folder.appendingPathComponent("never.m4a"))
        }
    }
}
