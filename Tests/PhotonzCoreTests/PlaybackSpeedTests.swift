import Foundation
import PhotonzCore
import Testing

/// **The speed a video plays at** (`PlaybackSpeed.swift`): the transport's
/// speed menu, ⇧. and ⇧, stepping it, and which speeds keep their sound.
///
/// Written before the menu, which is the rule for `PhotonzCore`.
@Suite("Playback speed you can pick")
struct PlaybackSpeedTests {

    @Test("The menu offers the seven speeds the user asked for, slowest first, and 1x by default")
    func choices() {
        #expect(PlaybackSpeed.choices == [0.25, 0.5, 1, 1.5, 2, 4, 8])
        #expect(PlaybackSpeed.normal == 1)
    }

    @Test("Each speed reads as a player says it: 0.25x, 0.5x, 1x, 1.5x, 8x, and backwards with a minus")
    func labels() {
        #expect(PlaybackSpeed.choices.map(PlaybackSpeed.label) == ["0.25x", "0.5x", "1x", "1.5x", "2x", "4x", "8x"])
        #expect(PlaybackSpeed.label(-2) == "-2x")
        #expect(PlaybackSpeed.label(-0.5) == "-0.5x")
    }

    @Test("Faster and slower step through the menu and stop at either end")
    func stepping() {
        #expect(PlaybackSpeed.faster(than: 1) == 1.5)
        #expect(PlaybackSpeed.faster(than: 0.25) == 0.5)
        #expect(PlaybackSpeed.faster(than: 8) == 8)
        #expect(PlaybackSpeed.slower(than: 1) == 0.5)
        #expect(PlaybackSpeed.slower(than: 0.25) == 0.25)
        #expect(PlaybackSpeed.slower(than: 8) == 4)
    }

    @Test("A speed off the menu (a shuttle's, say 3x) steps to the next one on it either way")
    func steppingFromOffTheMenu() {
        #expect(PlaybackSpeed.faster(than: 3) == 4)
        #expect(PlaybackSpeed.slower(than: 3) == 2)
        #expect(PlaybackSpeed.faster(than: 16) == 8)
        #expect(PlaybackSpeed.slower(than: 0.1) == 0.25)
    }

    @Test("Sound plays forwards up to double speed and goes quiet faster than that or backwards")
    func soundBand() {
        for speed in [0.25, 0.5, 1, 1.5, 2] {
            #expect(PlaybackSpeed.playsSound(atRate: speed), "\(speed)x")
        }
        for speed in [4.0, 8, -1, -2, 0] {
            #expect(!PlaybackSpeed.playsSound(atRate: speed), "\(speed)x")
        }
    }

    @Test("Only a speed with sound and off normal needs the pitch held")
    func pitchHeld() {
        #expect(!PlaybackSpeed.holdsPitch(atRate: 1))
        #expect(PlaybackSpeed.holdsPitch(atRate: 0.5))
        #expect(PlaybackSpeed.holdsPitch(atRate: 1.5))
        #expect(!PlaybackSpeed.holdsPitch(atRate: 4))
    }

    @Test("The menu says which speeds play without sound")
    func silentChoices() {
        #expect(PlaybackSpeed.choices.filter { !PlaybackSpeed.playsSound(atRate: $0) } == [4, 8])
    }

    @Test("A speed only counts as on the menu when it is one of the seven")
    func onTheMenu() {
        #expect(PlaybackSpeed.isChoice(1.5))
        #expect(!PlaybackSpeed.isChoice(3))
        #expect(!PlaybackSpeed.isChoice(-1))
    }
}

/// **Reading the pitch of a tone** (`TonePitch.swift`): what a walk measures
/// to say the sound kept its pitch at half and one and a half speed.
@Suite("Reading the pitch of a tone")
struct TonePitchTests {

    private func tone(_ hz: Double, rate: Double = 44_100, seconds: Double = 0.25, phase: Double = 0.3)
        -> [Float] {
        (0..<Int(rate * seconds)).map { Float(0.6 * sin(2 * .pi * hz * Double($0) / rate + phase)) }
    }

    @Test("A pure tone reads back at its own pitch, to within half a percent",
          arguments: [220.0, 440, 523.25, 880])
    func pureTone(hz: Double) throws {
        let read = try #require(TonePitch.hertz(of: tone(hz), sampleRate: 44_100))
        #expect(abs(read - hz) / hz < 0.005, "read \(read) Hz for \(hz) Hz")
    }

    @Test("A tone an octave up, the way a sound sped up twice without its pitch held sounds, reads an octave up")
    func octave() throws {
        let read = try #require(TonePitch.hertz(of: tone(880, rate: 48_000), sampleRate: 48_000))
        #expect(abs(read - 880) < 4)
    }

    @Test("A tone with a little noise on it still reads at its pitch")
    func noisy() throws {
        var generator = SystemRandomNumberGenerator()
        let noisy = tone(440).map { $0 + Float.random(in: -0.05...0.05, using: &generator) }
        let read = try #require(TonePitch.hertz(of: noisy, sampleRate: 44_100))
        #expect(abs(read - 440) / 440 < 0.01)
    }

    // Sound with its pitch held at 1.5x is spliced from overlapping pieces,
    // and in 2 of 5 runs of the speed walk the 440 Hz tone read 220.1 Hz
    // (2026-11-13): the peak two cycles along came out more than a tenth
    // taller than the one a cycle along. A tone a cycle along is a peak a
    // tone has; a sound only twice as long a period has a trough there.
    @Test("A tone whose every other cycle is quieter still reads at its own pitch, not an octave down")
    func unevenCycles() throws {
        let rate = 44_100.0, hz = 440.0
        let uneven: [Float] = (0..<Int(rate * 0.25)).map { index in
            let cycle = Int(Double(index) * hz / rate)
            let loudness = cycle % 2 == 0 ? 0.7 : 0.35
            return Float(loudness * sin(2 * .pi * hz * Double(index) / rate + 0.3))
        }
        let read = try #require(TonePitch.hertz(of: uneven, sampleRate: rate))
        #expect(abs(read - hz) / hz < 0.01)
        // ...while a real 220 Hz tone still reads 220.
        let low = try #require(TonePitch.hertz(of: tone(220), sampleRate: rate))
        #expect(abs(low - 220) / 220 < 0.005)
    }

    @Test("Silence has no pitch")
    func silence() {
        #expect(TonePitch.hertz(of: [Float](repeating: 0, count: 8000), sampleRate: 44_100) == nil)
        #expect(TonePitch.hertz(of: [], sampleRate: 44_100) == nil)
    }
}

// A walk reads the playhead at its looks, and the playhead moves once a
// frame's step (`PlayClockPace`): a look can find it up to 33ms of the clock
// stale. Over the two seconds a walk plays at 0.5x that alone reads 0.514x
// on a clock going at exactly 0.5x (2026-11-13), so the two percent is
// measured on top of what one tick can hide.
@Suite("Whether a playhead went at the speed asked")
struct PlaybackPaceTests {

    @Test("Within two percent, plus the one tick a look can find the playhead stale by")
    func toleratesOneTick() {
        #expect(PlaybackSpeed.wentAtSpeed(measured: 0.514, rate: 0.5, overSeconds: 1.92))
        #expect(PlaybackSpeed.wentAtSpeed(measured: 7.92, rate: 8, overSeconds: 2.87))
        #expect(!PlaybackSpeed.wentAtSpeed(measured: 0.53, rate: 0.5, overSeconds: 1.92))
        #expect(!PlaybackSpeed.wentAtSpeed(measured: 7.6, rate: 8, overSeconds: 2.87))
        #expect(!PlaybackSpeed.wentAtSpeed(measured: 1.05, rate: 1, overSeconds: 10))
        #expect(PlaybackSpeed.wentAtSpeed(measured: -2.02, rate: -2, overSeconds: 3))
    }

    // The first look after opening the six minute reference edit found the
    // playhead 40ms stale (the main thread busy with the first frames), and
    // first-to-last read 0.520x on a clock going at 0.5x (2026-11-13). A line
    // through every look is not thrown by one.
    @Test("The pace is the line through every look, so one stale look does not throw it")
    func paceThroughEveryLook() throws {
        var looks: [(seconds: Double, ms: Double)] = (0..<24).map { look in
            let seconds = 0.08 * Double(look + 1)
            return (seconds, 500 * seconds - Double(look % 2) * 8)
        }
        looks[0].ms -= 20
        let rate = try #require(PlaybackSpeed.pace(of: looks))
        #expect(abs(rate - 0.5) < 0.006)
        #expect(PlaybackSpeed.pace(of: [(0, 0)]) == nil)
        #expect(PlaybackSpeed.pace(of: [(1, 0), (1, 10)]) == nil)
    }
}
