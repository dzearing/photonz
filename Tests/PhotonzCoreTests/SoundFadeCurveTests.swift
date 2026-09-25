import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **A fade's curve**: how the sound rises out of silence and falls back into
/// it, picked from the one list of curves every timed thing in the app uses
/// (`pages/video-audio.html`, the Fades section's Curve dropdown).
///
/// A fade is still two points on the level line. The curve only bends the
/// stretch between them, and it bends it in the plan the player and the export
/// both read, so what you hear is the curve you picked.
@Suite("Sound fade curves")
struct SoundFadeCurveTests {

    @Test("A fade nobody has shaped runs in a straight line, as fades always have")
    func linearByDefault() {
        var level = AudioLevel()
        level.setFadeIn(1000, lengthMS: 5000)
        #expect(level.fadeCurve == .linear)
        #expect(abs(level.gain(atLayerMS: 250) - 0.25) < 0.0001)
    }

    @Test("A curved fade in follows the curve from silence up to the level")
    func curvedFadeIn() {
        var level = AudioLevel()
        level.setFadeIn(1000, lengthMS: 5000)
        level.fadeCurve = .easeIn
        let expected = EasingCurve.easeIn.value(at: 0.25)
        #expect(abs(level.gain(atLayerMS: 250) - expected) < 0.0001)
        #expect(level.gain(atLayerMS: 0) == 0)
        #expect(level.gain(atLayerMS: 1000) == 1)
        // Past the fade the level is untouched by the curve.
        #expect(level.gain(atLayerMS: 3000) == 1)
    }

    @Test("A curved fade out is the fade in played backwards, as the mock draws it")
    func curvedFadeOutMirrors() {
        var level = AudioLevel()
        level.setFadeOut(1000, lengthMS: 5000)
        level.fadeCurve = .easeIn
        // A quarter of the way into the fade out is three quarters of the way
        // back from silence.
        let expected = EasingCurve.easeIn.value(at: 0.75)
        #expect(abs(level.gain(atLayerMS: 4250) - expected) < 0.0001)
        #expect(level.gain(atLayerMS: 5000) == 0)
        #expect(level.gain(atLayerMS: 4000) == 1)
    }

    @Test("The curve bends only the fades, never a duck in the middle")
    func duckStaysStraight() {
        var level = AudioLevel()
        level.setPoint(atMS: 2000, gain: 1)
        level.setPoint(atMS: 3000, gain: 0.2)
        level.fadeCurve = .easeInOut
        #expect(abs(level.gain(atLayerMS: 2500) - 0.6) < 0.0001)
    }

    @Test("The fader still moves the whole shape, curve included")
    func faderCarriesTheCurve() {
        var level = AudioLevel(gain: 0.5)
        level.setFadeIn(1000, lengthMS: 5000)
        level.fadeCurve = .easeOut
        let expected = 0.5 * EasingCurve.easeOut.value(at: 0.5)
        #expect(abs(level.gain(atLayerMS: 500) - expected) < 0.0001)
    }

    @Test("A curve that overshoots never asks for a level below silence")
    func neverBelowSilence() {
        var level = AudioLevel()
        level.setFadeIn(1000, lengthMS: 5000)
        level.fadeCurve = .easeOutElastic
        for ms in stride(from: 0, through: 1000, by: 10) {
            #expect(level.gain(atLayerMS: ms) >= 0)
        }
    }

    @Test("A curve is written down only when somebody picked one, and reads back")
    func codable() throws {
        var level = AudioLevel()
        level.setFadeIn(1000, lengthMS: 5000)
        let plain = try JSONEncoder().encode(level)
        #expect(!String(decoding: plain, as: UTF8.self).contains("fadeCurve"))

        level.fadeCurve = .easeInOut
        let data = try JSONEncoder().encode(level)
        let back = try JSONDecoder().decode(AudioLevel.self, from: data)
        #expect(back == level)
        #expect(back.fadeCurve == .easeInOut)
    }

    @Test("A curve picked before any fade is kept, so the next fade wears it")
    func curveAloneIsATouch() {
        var level = AudioLevel()
        level.fadeCurve = .easeOut
        #expect(!level.isUntouched)
    }

    // MARK: - What plays

    @Test("A straight fade is one ramp, as it always was")
    func straightFadeIsOneRamp() throws {
        var (doc, id) = AudioMixTests.document(soundLengthMS: 5000)
        doc.updateLayer(id: id) { layer in
            var level = AudioLevel()
            level.setFadeIn(1000, lengthMS: 5000)
            layer.setSoundLevel(level)
        }
        let segment = try #require(doc.audioMix().first)
        #expect(segment.ramps.map(\.fromMS) == [0, 1000])
    }

    @Test("A curved fade plays as the curve: the plan follows it closely all the way")
    func curvedFadePlaysTheCurve() throws {
        var (doc, id) = AudioMixTests.document(soundLengthMS: 5000)
        doc.updateLayer(id: id) { layer in
            var level = AudioLevel()
            level.setFadeIn(1200, lengthMS: 5000)
            level.setFadeOut(800, lengthMS: 5000)
            level.fadeCurve = .easeInOut
            layer.setSoundLevel(level)
        }
        let level = try #require(doc.layer(id: id)?.soundLevel)
        let segment = try #require(doc.audioMix().first)
        #expect(segment.ramps.count > 10)
        #expect(segment.ramps.first?.fromMS == 0)
        #expect(segment.ramps.last?.toMS == 5000)
        for ms in stride(from: 0, through: 5000, by: 7) {
            #expect(abs(segment.gain(atMS: ms) - level.gain(atLayerMS: ms)) < 0.02,
                    "at \(ms)ms the plan says \(segment.gain(atMS: ms)), the level \(level.gain(atLayerMS: ms))")
        }
    }

    @Test("The corners the lane draws are the corners the plan plays")
    func laneAndPlanAgree() {
        var level = AudioLevel()
        level.setFadeIn(1000, lengthMS: 5000)
        level.fadeCurve = .easeIn
        let moments = level.moments(fromMS: 0, toMS: 5000)
        #expect(moments.first == 0)
        #expect(moments.last == 5000)
        #expect(moments.contains(1000))
        #expect(moments.filter { $0 > 0 && $0 < 1000 }.count >= 10)
        #expect(moments == moments.sorted())
        // Straight, there is nothing between the corners to draw.
        level.fadeCurve = .linear
        #expect(level.moments(fromMS: 0, toMS: 5000) == [0, 1000, 5000])
    }

    // MARK: - Saying it

    @Test("A fade length reads in seconds, one place, the way the mock says it")
    func fadeLabel() {
        #expect(AudioLevel.fadeLabel(ms: 1500) == "1.5s")
        #expect(AudioLevel.fadeLabel(ms: 0) == "0.0s")
        #expect(AudioLevel.fadeLabel(ms: 2040) == "2.0s")
    }

    @Test("A typed fade length takes seconds, with or without the s")
    func fadeTyped() {
        #expect(AudioLevel.fadeMS(typed: "1.5") == 1500)
        #expect(AudioLevel.fadeMS(typed: "1.5s") == 1500)
        #expect(AudioLevel.fadeMS(typed: " 2 s ") == 2000)
        #expect(AudioLevel.fadeMS(typed: "0") == 0)
        #expect(AudioLevel.fadeMS(typed: "-1") == 0)
        #expect(AudioLevel.fadeMS(typed: "soon") == nil)
        #expect(AudioLevel.fadeMS(typed: "") == nil)
    }
}
