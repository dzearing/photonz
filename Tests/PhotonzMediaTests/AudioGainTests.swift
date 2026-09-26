import AVFoundation
import CoreGraphics
import Foundation
import PhotonzCore
@testable import PhotonzMedia
import Testing

/// Gain reaches the file, and a file's loudness can be measured
/// (`docs/design/video-audio.md`, "Gain and Normalize").
///
/// A Normalize that looks right on the timeline and exports at the old level is
/// worse than none, so the export is measured, not trusted.
@Suite("Gain reaches the export, and loudness is read off the file", .serialized)
struct AudioGainTests {

    static let folder = TestTone.scratch()

    static func tone(_ name: String, amplitude: Double, seconds: Double = 6) throws -> URL {
        let url = folder.appendingPathComponent("\(name).m4a")
        if !FileManager.default.fileExists(atPath: url.path) {
            try TestTone.writeFlat(to: url, seconds: seconds, amplitude: amplitude)
        }
        return url
    }

    static func exportedLoudness(of doc: PhotonzDocument, urls: [UUID: URL],
                                 named name: String) async throws -> Float {
        let out = folder.appendingPathComponent("\(name)-out.m4a")
        try await AudioMixdown.write(doc.audioMix(), urls: urls, to: out)
        let reading = try #require(await SoundFile.read(at: out))
        return AudioMixdownTests.loudness(reading.waveform, fromMS: 500, toMS: 3500)
    }

    @Test("A quiet sound with +20 dB of gain exports ten times louder")
    func gainBoostsTheExport() async throws {
        let url = try Self.tone("quiet", amplitude: 0.03)
        let sound = SoundRef(durationMS: 4000)

        var plain = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100), layers: [])
        _ = plain.addSound(sound, name: "quiet", atMS: 0)
        let before = try await Self.exportedLoudness(of: plain, urls: [sound.id: url], named: "plain")

        var boosted = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100), layers: [])
        let id = boosted.addSound(sound, name: "quiet", atMS: 0)
        boosted.updateLayer(id: id) { $0.setSoundLevel(AudioLevel(clipGainDB: 20)) }
        let after = try await Self.exportedLoudness(of: boosted, urls: [sound.id: url], named: "boosted")

        #expect(before > 0.02 && before < 0.04)
        #expect(after > before * 8)
        #expect(after < before * 12)
    }

    @Test("Loudness is read off the file: twenty decibels quieter reads twenty LU lower")
    func loudnessOfAFile() async throws {
        let loud = try Self.tone("loud-8", amplitude: 0.8)
        let quiet = try Self.tone("quiet-08", amplitude: 0.08)
        let a = try #require(await SoundFile.loudnessLUFS(at: loud, sourceRangesMS: [0..<6000]))
        let b = try #require(await SoundFile.loudnessLUFS(at: quiet, sourceRangesMS: [0..<6000]))
        // A 440 Hz tone at 0.8 in one channel: about -5.7 LUFS.
        #expect(a > -7 && a < -4.5)
        #expect(abs((a - b) - 20) < 0.5)
    }

    @Test("Loudness reads only the stretches the segment plays")
    func loudnessReadsTheRanges() async throws {
        let url = AudioMixdownTests.folder.appendingPathComponent("burst-for-loudness.m4a")
        try TestTone.writeBurst(to: url, seconds: 10, loudFrom: 4, loudTo: 6)
        // The silent start is silence, which has no loudness.
        #expect(await SoundFile.loudnessLUFS(at: url, sourceRangesMS: [0..<3000]) == nil)
        let middle = try #require(await SoundFile.loudnessLUFS(at: url, sourceRangesMS: [4100..<5900]))
        #expect(middle > -7 && middle < -4.5)
    }
}
