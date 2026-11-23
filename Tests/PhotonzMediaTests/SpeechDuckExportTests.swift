import AVFoundation
import CoreGraphics
import Foundation
import PhotonzCore
@testable import PhotonzMedia
import PhotonzRender
import Testing

/// Duck Under Speech reaches the exported MP4: the music written into the
/// file is quieter under each stretch the captions heard than in the pause
/// between them (`SpeechDucking.swift`).
///
/// A real movie, written by the writer Export uses, and its sound read back
/// out of the MP4 through the reader the timeline draws its waveform from.
@Suite("Music ducked under the speech is quieter there in the exported movie", .serialized)
struct SpeechDuckExportTests {

    static let folder = TestTone.scratch()
    static let canvas = CGSize(width: 64, height: 64)

    static func word(_ text: String, _ start: Int, _ end: Int) -> TranscribedWord {
        TranscribedWord(text, startMS: start, endMS: end)
    }

    @Test("The exported music is down under the speech and back up in the pause")
    func theDipIsInTheMovie() async throws {
        let tone = Self.folder.appendingPathComponent("duck-bed.m4a")
        if !FileManager.default.fileExists(atPath: tone.path) {
            try TestTone.writeFlat(to: tone, seconds: 10)
        }
        let ground = Layer(name: "Ground",
                           content: .annotation(AnnotationContent(shape: .rectangle, strokeWidth: 0,
                                                                  colorHex: "#808080", start: .zero,
                                                                  end: CGPoint(x: 64, y: 64),
                                                                  fillColorHex: "#808080")),
                           frame: CGRect(origin: .zero, size: Self.canvas))
        var doc = PhotonzDocument(canvasSize: Self.canvas, layers: [ground])
        doc.durationMS = 8000
        let music = SoundRef(durationMS: 10_000)
        let id = doc.addSound(music, name: "Music", atMS: 0, stoppingWithThePicture: true)
        // Speech from 1.0 to 3.0 s and from 5.5 to 7.0 s.
        _ = doc.landCaptions([
            CaptionCue(words: [Self.word("Hello", 1000, 1800), Self.word("there.", 1900, 3000)], inMS: 1000, outMS: 3000),
            CaptionCue(words: [Self.word("Again.", 5500, 7000)], inMS: 5500, outMS: 7000),
        ])
        let did = doc.duckUnderSpeech(layerID: id)
        #expect(did)

        let plan = DocumentVideoExport.plan(durationMS: 8000, canvasSize: Self.canvas, format: .mp4,
                                            quality: .standard)
        let out = Self.folder.appendingPathComponent("speech-duck.mp4")
        let picture = PhotonzDocument(canvasSize: Self.canvas, layers: [ground])
        try await DocumentMovieWriter.write(plan: plan, mix: doc.audioMix(), soundURLs: [music.id: tone],
                                            to: out) { ms in
            DocumentRenderer().render(picture.drawn(atTimeMS: ms), store: ImageStore())
        }

        let reading = try #require(await SoundFile.read(at: out))
        let wave = reading.waveform
        func loudness(_ from: Int, _ to: Int) -> Float {
            let lo = max(0, from / Waveform.bucketMS), hi = min(wave.peaks.count, to / Waveform.bucketMS)
            guard hi > lo else { return 0 }
            return wave.peaks[lo..<hi].reduce(0, +) / Float(hi - lo)
        }
        let before = loudness(100, 500)
        let underFirst = loudness(1300, 2700)
        let pause = loudness(3600, 4900)
        let underSecond = loudness(5800, 6700)
        #expect(before > 0.2, "full before anybody talks: \(before)")
        #expect(pause > 0.2, "back up in the pause: \(pause)")
        // -8 dB is about 0.4 of the level; the encoder's attack and release
        // blur it a little, so the bar is well clear of full but not exact.
        #expect(underFirst < before * 0.55, "down under the first stretch: \(underFirst) vs \(before)")
        #expect(underSecond < pause * 0.55, "down under the second stretch: \(underSecond) vs \(pause)")
        #expect(underFirst > before * 0.25, "a dip, not silence: \(underFirst)")
    }
}
