import AVFoundation
import CoreGraphics
import Foundation
import PhotonzCore
@testable import PhotonzMedia
import Testing

/// **A stretch cleaned on its own eases in and out, in the mix itself.**
///
/// Clean Noise in Section plays a cleaned copy between the range's edges and
/// the file as recorded either side. Switched over hard, the room tone drops
/// from one sample to the next, which a person hears as a click at each edge.
/// This lays the plan into the exporter's own composition and reads the
/// samples back, so what is measured is what plays: the largest jump from one
/// sample to the next across each edge, against the largest the room tone
/// makes on its own either side.
@Suite("A cleaned stretch eases in and out of the sound around it", .serialized)
struct SectionCleaningSeamExportTests {

    static let rate: Double = 48_000

    /// Ten seconds of room tone: a 60 Hz hum, peaking on every whole second so
    /// a hard switch at 0:03 and 0:06 lands on the hum's crest, under a faint
    /// hiss.
    static func roomTone(seconds: Double = 10, hiss: Double = 0.002) -> [Float] {
        var state: UInt32 = 54_321
        func random() -> Double {
            state = state &* 1_664_525 &+ 1_013_904_223
            return Double(state) / Double(UInt32.max) * 2 - 1
        }
        return (0..<Int(seconds * rate)).map { index in
            let t = Double(index) / rate
            return Float(0.05 * cos(2 * .pi * 60 * t) + hiss * random())
        }
    }

    /// The recording, its own sound the room tone, cleaned between 0:03 and
    /// 0:06 the way the right click does it, with its cleaned copy made the way
    /// the app makes it.
    static func cleanedInTheMiddle(hiss: Double) async throws -> (doc: PhotonzDocument, urls: [UUID: URL]) {
        let raw = NoiseCleanerTests.temporary("room.wav")
        try NoiseCleanerTests.writeWAV(roomTone(hiss: hiss), to: raw)
        let talk = MovieRef(pixelSize: CGSize(width: 100, height: 60), durationMS: 10_000,
                            hasSound: true)
        var doc = PhotonzDocument.recording(talk, name: "talk")
        let take = doc.layers[0].id
        let did = doc.cleanNoiseSection([take], within: 3000..<6000)
        #expect(did)
        let cleanedRef = try #require(doc.layer(id: take)?.sectionCleanedSoundRefs.first)
        let cleaning = try #require(cleanedRef.cleaning)
        let reduction = try #require(cleaning.reduction)
        let reading = try #require(await SoundFile.read(at: raw))
        let quiet = NoiseReduction.quietStretchesMS(of: reading.waveform, within: cleaning.learnFromMS)
        let cleaned = NoiseCleanerTests.temporary("room-cleaned.caf")
        try await NoiseCleaner.write(from: raw, reduction: reduction, quietMS: quiet, to: cleaned)
        return (doc, [talk.id: raw, cleanedRef.id: cleaned])
    }

    /// Every sample the plan plays, mono, read straight off the composition the
    /// exporter writes from: no lossy coding in the way of a one-sample jump.
    static func played(_ plan: [AudioMixSegment], urls: [UUID: URL]) async throws -> [Float] {
        let mixed = try await AudioMixdown.composition(for: plan, urls: urls)
        let reader = try AVAssetReader(asset: mixed.composition)
        let tracks = try await mixed.composition.loadTracks(withMediaType: .audio)
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: rate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ])
        output.audioMix = mixed.audioMix
        reader.add(output)
        #expect(reader.startReading())
        var samples: [Float] = []
        while let buffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var chunk = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            chunk.withUnsafeMutableBytes { bytes in
                _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length,
                                               destination: bytes.baseAddress!)
            }
            samples += chunk
        }
        return samples
    }

    /// The largest jump from one sample to the next between two moments.
    static func largestJump(_ samples: [Float], fromMS: Int, toMS: Int) -> Float {
        let lo = max(1, Int(Double(fromMS) * rate / 1000))
        let hi = min(samples.count, Int(Double(toMS) * rate / 1000))
        guard hi > lo else { return 0 }
        return (lo..<hi).map { abs(samples[$0] - samples[$0 - 1]) }.max() ?? 0
    }

    /// With a hiss, the way room tone sounds, and with only the hum, where
    /// the tone's own jumps are so small that a blip of a few milliseconds at
    /// either edge stands out ten times over.
    @Test("Each edge of the cleaned stretch is no bigger a jump than the room tone makes either side",
          arguments: [0.002, 0])
    func noClickAtEitherEdge(hiss: Double) async throws {
        let (doc, urls) = try await Self.cleanedInTheMiddle(hiss: hiss)
        let samples = try await Self.played(doc.audioMix(), urls: urls)
        #expect(samples.count > Int(9 * Self.rate))
        let half = SectionCleaningSeam.lengthMS / 2
        // The room tone's own jumps either side of each seam: as recorded
        // before, cleaned inside, as recorded after.
        let before = Self.largestJump(samples, fromMS: 50, toMS: 3000 - half)
        let cleaned = Self.largestJump(samples, fromMS: 3000 + half, toMS: 6000 - half)
        let after = Self.largestJump(samples, fromMS: 6000 + half, toMS: 9000)
        // The stretch really is cleaned: the hum is well down inside it.
        let quieter = NoiseCleanerTests.rmsDB(samples, from: 4, to: 5)
            - NoiseCleanerTests.rmsDB(samples, from: 1, to: 2)
        #expect(quieter < -10)
        let into = Self.largestJump(samples, fromMS: 3000 - half, toMS: 3000 + half)
        let outOf = Self.largestJump(samples, fromMS: 6000 - half, toMS: 6000 + half)
        print("seam jumps (hiss \(hiss)): before \(before) cleaned \(cleaned) after \(after) into \(into) outOf \(outOf) quieter \(quieter) dB")
        #expect(into <= max(before, cleaned))
        #expect(outOf <= max(cleaned, after))
    }
}
