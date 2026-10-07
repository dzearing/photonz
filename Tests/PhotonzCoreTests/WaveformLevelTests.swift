import Foundation
import PhotonzCore
import Testing

/// A sound's waveform drawn at the level it plays at
/// (`docs/design/mocks/pages/video-audio.html`, `samp[i]*levelAt(tr,t)`).
///
/// The waveform on the timeline says what you will hear, so a fade in rises out
/// of nothing, and pulling the level down shrinks the drawing with it. What is
/// here is the per-column arithmetic: which moment of the layer a column
/// stands for, and how tall the level lets it draw.
@Suite("The waveform follows the level")
struct WaveformLevelTests {

    /// Forty columns across four seconds, every one a full-scale peak, so each
    /// column's height is the level's answer alone.
    static let loud = [Float](repeating: 1, count: 40)

    static func heights(_ level: AudioLevel, columns: [Float] = loud,
                        from: Int = 0, to: Int = 4000) -> [Float] {
        Waveform.drawnHeights(ofPeaks: columns, level: level, fromLayerMS: from, toLayerMS: to)
    }

    static func faded(in fadeIn: Int = 0, out fadeOut: Int = 0, curve: EasingCurve = .linear) -> AudioLevel {
        var level = AudioLevel(fadeCurve: curve)
        level.setFadeIn(fadeIn, lengthMS: 4000)
        level.setFadeOut(fadeOut, lengthMS: 4000)
        return level
    }

    @Test("Untouched, the waveform draws as it always has, gain included")
    func untouchedIsUnchanged() {
        let peaks: [Float] = [0, 0.01, 0.1, 0.5, 1]
        for gainDB in [0.0, 12, -6] {
            let drawn = Waveform.drawnHeights(ofPeaks: peaks, level: AudioLevel(clipGainDB: gainDB),
                                              fromLayerMS: 0, toLayerMS: 1000)
            #expect(drawn == peaks.map { Waveform.drawnHeight(ofPeak: $0, gainDB: gainDB) })
        }
    }

    @Test("A one second fade in rises from a hairline to full height at its end")
    func fadeInRises() {
        let drawn = Self.heights(Self.faded(in: 1000))
        // Column 0 stands for 50 ms in: five per cent of the way up.
        #expect(drawn[0] < 0.06)
        #expect(abs(drawn[4] - 0.45) < 0.001)
        for index in 1..<10 { #expect(drawn[index] > drawn[index - 1]) }
        #expect(drawn[10...].allSatisfy { $0 == 1 })
    }

    @Test("A fade out is the fade in backwards")
    func fadeOutFalls() {
        let drawn = Self.heights(Self.faded(out: 1000))
        #expect(drawn[..<30].allSatisfy { $0 == 1 })
        for index in 31..<40 { #expect(drawn[index] < drawn[index - 1]) }
        #expect(drawn[39] < 0.06)
        let rising = Self.heights(Self.faded(in: 1000))
        for index in 0..<10 { #expect(abs(drawn[39 - index] - rising[index]) < 0.0001) }
    }

    @Test("The fader scales the whole drawing")
    func faderShrinksTheDrawing() {
        let peaks = [Float](repeating: 0.1, count: 8)
        let full = Waveform.drawnHeights(ofPeaks: peaks, level: AudioLevel(),
                                         fromLayerMS: 0, toLayerMS: 800)
        let half = Waveform.drawnHeights(ofPeaks: peaks, level: AudioLevel(gain: 0.5),
                                         fromLayerMS: 0, toLayerMS: 800)
        for (whole, halved) in zip(full, half) { #expect(abs(halved - whole * 0.5) < 0.0001) }
        let quarter = Waveform.drawnHeights(ofPeaks: peaks, level: AudioLevel(gain: 0.25),
                                            fromLayerMS: 0, toLayerMS: 800)
        #expect(quarter.allSatisfy { $0 < half[0] })
    }

    @Test("Between two level points the drawing scales between them")
    func pointsScaleBetween() {
        let level = AudioLevel(points: [AudioLevelPoint(atMS: 0, gain: 1),
                                        AudioLevelPoint(atMS: 4000, gain: 0.2)])
        let drawn = Self.heights(level)
        // Column 19 stands for 1950 ms: a little over half way down the ramp.
        #expect(abs(drawn[19] - Float(level.gain(atLayerMS: 1950))) < 0.0001)
        #expect(drawn[19] < drawn[0] && drawn[19] > drawn[39])
    }

    @Test("A curved fade draws along the same curve the level line draws")
    func curvedFadeFollowsTheLine() {
        let level = Self.faded(in: 1000, curve: .easeIn)
        let drawn = Self.heights(level)
        for index in 0..<10 {
            let ms = (index * 100) + 50
            #expect(abs(drawn[index] - Float(level.gain(atLayerMS: ms))) < 0.0001)
        }
    }

    @Test("Opened out on part of the layer, a column stands for the moment it is drawn over")
    func windowedColumns() {
        // Only the second half of the fade in is on screen: 500 ms to 1000 ms
        // across ten columns, so the first column is 525 ms in.
        let drawn = Self.heights(Self.faded(in: 1000), columns: [Float](repeating: 1, count: 10),
                                 from: 500, to: 1000)
        #expect(abs(drawn[0] - 0.525) < 0.001)
        #expect(abs(drawn[9] - 0.975) < 0.001)
    }

    @Test("Silence draws nothing, which the lane shows as a hairline")
    func silenceIsFlat() {
        let drawn = Self.heights(AudioLevel(gain: 0))
        #expect(drawn.allSatisfy { $0 == 0 })
    }

    @Test("Turned up past where it was recorded, it grows as gain does, never past the lane")
    func boostGrowsAsGain() {
        let quiet = Float(pow(10, -30.0 / 20))
        let drawn = Waveform.drawnHeights(ofPeaks: [quiet, 1], level: AudioLevel(gain: 2),
                                          fromLayerMS: 0, toLayerMS: 200)
        let sixUp = Waveform.drawnHeight(ofPeak: quiet, gainDB: 20 * log10(2))
        #expect(abs(drawn[0] - sixUp) < 0.0001)
        #expect(drawn[0] > Waveform.drawnHeight(ofPeak: quiet))
        #expect(drawn[1] == 1)
    }

    @Test("No columns, or no time, draws nothing and asks nothing")
    func degenerate() {
        #expect(Waveform.drawnHeights(ofPeaks: [], level: AudioLevel(), fromLayerMS: 0, toLayerMS: 10).isEmpty)
        let still = Waveform.drawnHeights(ofPeaks: [1, 1], level: Self.faded(in: 1000),
                                          fromLayerMS: 500, toLayerMS: 500)
        #expect(still.allSatisfy { abs($0 - 0.5) < 0.001 })
    }
}
