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

    @Test("Silence has no pitch")
    func silence() {
        #expect(TonePitch.hertz(of: [Float](repeating: 0, count: 8000), sampleRate: 44_100) == nil)
        #expect(TonePitch.hertz(of: [], sampleRate: 44_100) == nil)
    }
}
