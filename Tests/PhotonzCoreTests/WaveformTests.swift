import Foundation
import PhotonzCore
import Testing

/// The shape of a sound, so a cut can be aimed at a word rather than guessed
/// (`docs/design/video-audio.md`).
///
/// A waveform is **not in the document**: it is read off the file, exactly as a
/// picture's pixels are, and the document holds only the reference. What is
/// here is the arithmetic that turns a run of peaks into the columns a bar of a
/// given width draws, which is the part worth being sure about and the part a
/// view cannot be tested for.
@Suite("The shape of a sound")
struct WaveformTests {

    /// A second of sound that swells from nothing to full and back.
    static func swell(seconds: Int = 1) -> Waveform {
        let count = seconds * 1000 / Waveform.bucketMS
        return Waveform(peaks: (0..<count).map { i in
            let t = Float(i) / Float(max(1, count - 1))
            return 1 - abs(t - 0.5) * 2
        })
    }

    @Test("A waveform knows how long it is from how many peaks it has")
    func lengthFollowsFromPeaks() {
        let wave = Self.swell(seconds: 3)
        #expect(wave.durationMS == 3000)
        #expect(wave.peaks.count == 3000 / Waveform.bucketMS)
    }

    @Test("A peak is read at a moment of the file, and past the end there is silence")
    func peakAtAMoment() {
        let wave = Self.swell()
        #expect(wave.peak(atSourceMS: 500) > 0.9)
        #expect(wave.peak(atSourceMS: 0) < 0.1)
        #expect(wave.peak(atSourceMS: 99_000) == 0)
        #expect(wave.peak(atSourceMS: -10) == 0)
    }

    @Test("Peaks are held between nought and one, so no column can draw outside its lane")
    func peaksAreBounded() {
        let wave = Waveform(peaks: [-3, 0.5, 9])
        #expect(wave.peaks == [0, 0.5, 1])
    }

    @Test("A stretch of the file becomes as many columns as the bar is wide")
    func stretchBecomesColumns() {
        let wave = Self.swell()
        let columns = wave.columns(count: 40, fromSourceMS: 0, toSourceMS: 1000)
        #expect(columns.count == 40)
        // It swells to the middle and falls away, and the columns say so.
        #expect(columns[20] > columns[0])
        #expect(columns[20] > columns[39])
    }

    @Test("A column says the loudest thing inside it, so a beat is never averaged away")
    func aColumnTakesThePeak() {
        // One loud bucket in a quiet second: at four columns it must still show.
        var peaks = [Float](repeating: 0.05, count: 50)
        peaks[3] = 1
        let wave = Waveform(peaks: peaks)
        let columns = wave.columns(count: 4, fromSourceMS: 0, toSourceMS: 1000)
        #expect(columns[0] == 1)
        #expect(columns[1] < 0.1)
    }

    @Test("A bar with no width asks for no columns rather than dividing by nothing")
    func zeroWidthIsEmpty() {
        #expect(Self.swell().columns(count: 0, fromSourceMS: 0, toSourceMS: 1000).isEmpty)
        #expect(Self.swell().columns(count: -4, fromSourceMS: 0, toSourceMS: 1000).isEmpty)
    }

    @Test("The columns of a cut clip follow the cuts, so what is drawn is what plays")
    func columnsFollowTheCuts() {
        // A file whose first half is loud and second half quiet.
        let count = 2000 / Waveform.bucketMS
        let wave = Waveform(peaks: (0..<count).map { $0 < count / 2 ? 1 : 0.1 })

        // The clip keeps only the quiet half, so every column is quiet even
        // though the quiet half is at the END of the file.
        let pieces = ClipPieces(pieces: [ClipPiece(sourceInMS: 1000, lengthMS: 1000)],
                               sourceLengthMS: 2000)
        let columns = wave.columns(count: 10, forPieces: pieces)
        #expect(columns.count == 10)
        #expect(columns.allSatisfy { $0 < 0.2 })
    }

    @Test("A held frame draws a flat line, because there is no sound under it")
    func heldFramesDrawFlat() {
        let wave = Waveform(peaks: [Float](repeating: 1, count: 100))
        let pieces = ClipPieces(pieces: [ClipPiece(sourceInMS: 0, lengthMS: 1000),
                                         ClipPiece.held(atSourceMS: 1000, forMS: 1000)],
                               sourceLengthMS: 2000)
        let columns = wave.columns(count: 20, forPieces: pieces)
        #expect(columns.count == 20)
        #expect(columns[0] == 1)
        #expect(columns[19] == 0)
    }

    @Test("A waveform is small enough to keep: a quarter of an hour is under fifty thousand peaks")
    func aWaveformIsSmall() {
        // 20ms buckets is fifty peaks a second, which is what makes keeping one
        // per sound in memory reasonable rather than a second cache problem.
        #expect(15 * 60 * 1000 / Waveform.bucketMS == 45_000)
    }
}
