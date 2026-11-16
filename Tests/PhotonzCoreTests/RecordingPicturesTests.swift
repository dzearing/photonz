import CoreGraphics
@testable import PhotonzCore
import Testing

/// How a screen recording stores its pictures when Photonz writes the file
/// itself. The numbers behind every choice are in
/// docs/progress/2026-11-15-recording-colour.md.
@Suite("A screen recording stores its pictures the way the screen showed them")
struct RecordingPicturesTests {

    @Test("The file says Display P3 colours on the sRGB curve, with the 601 matrix the stream encodes 10-bit frames in")
    func colourTags() {
        // These are the exact Core Video / AVFoundation strings, kept as plain
        // text here so the core stays free of media frameworks.
        #expect(RecordingPictures.colourPrimaries == "P3_D65")
        #expect(RecordingPictures.transferFunction == "IEC_sRGB")
        #expect(RecordingPictures.yCbCrMatrix == "ITU_R_601_4")
    }

    @Test("Smaller files gives a full Retina screen at 60 frames a second about 20 megabits a second")
    func fullScreenRate() {
        let rate = RecordingPictures.bitsPerSecond(pixelSize: CGSize(width: 3456, height: 2234), fps: 60)
        #expect(rate >= 19_000_000 && rate <= 22_000_000, "\(rate)")
    }

    @Test("The rate grows with the pixels recorded")
    func rateFollowsPixels() {
        let half = RecordingPictures.bitsPerSecond(pixelSize: CGSize(width: 2560, height: 1440), fps: 60)
        let full = RecordingPictures.bitsPerSecond(pixelSize: CGSize(width: 5120, height: 2880), fps: 60)
        #expect(full > half)
        #expect(full <= RecordingPictures.mostBitsPerSecond)
    }

    @Test("A small region never drops below the floor, and the biggest screen never passes the ceiling")
    func floorAndCeiling() {
        #expect(RecordingPictures.bitsPerSecond(pixelSize: CGSize(width: 200, height: 120), fps: 60)
                == RecordingPictures.fewestBitsPerSecond)
        #expect(RecordingPictures.bitsPerSecond(pixelSize: CGSize(width: 12_000, height: 8000), fps: 60)
                == RecordingPictures.mostBitsPerSecond)
        #expect(RecordingPictures.bitsPerSecond(pixelSize: .zero, fps: 60) == RecordingPictures.fewestBitsPerSecond)
    }

    @Test("Sound is AAC at 48 kHz in stereo, as the Mac's own recordings carry it")
    func sound() {
        #expect(RecordingPictures.soundSampleRate == 48_000)
        #expect(RecordingPictures.soundChannels == 2)
        #expect(RecordingPictures.soundBitsPerSecond == 160_000)
    }

    @Test("Smaller files holds the encoder to the rate; Best asks for its top quality")
    func qualityChoice() {
        let size = CGSize(width: 3456, height: 2234)
        #expect(RecordingPictures.compression(.smaller, pixelSize: size, fps: 60)
                == .averageBitsPerSecond(RecordingPictures.bitsPerSecond(pixelSize: size, fps: 60)))
        #expect(RecordingPictures.compression(.best, pixelSize: size, fps: 60) == .quality(1))
    }

    @Test("The setting reads Best unless it says Smaller files, and its labels are plain")
    func qualitySetting() {
        #expect(RecordingQuality(stored: nil) == .best)
        #expect(RecordingQuality(stored: "nonsense") == .best)
        #expect(RecordingQuality(stored: "smaller") == .smaller)
        #expect(RecordingQuality.allCases.map(\.label) == ["Best", "Smaller files"])
        #expect(RecordingQuality.allCases.allSatisfy { !$0.label.contains("\u{2014}") && $0.label.count <= 30 })
    }
}
