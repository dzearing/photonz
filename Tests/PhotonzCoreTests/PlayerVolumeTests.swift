import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// **How loud you are listening** (`PlayerVolume.swift`): the speaker and the
/// short slider at the left of the transport.
///
/// On 2026-09-28 the user clicked what looked like a volume slider and nothing
/// happened: it was the mix meter, and there was no level control at all, only
/// a mute button. This is the arithmetic behind the slider that replaced it:
/// where a click lands, what the wheel does, what the speaker button does, and
/// what reaches the speakers.
@Suite("The transport's volume")
struct PlayerVolumeTests {

    @Test("It starts at full and sounding")
    func startsFull() {
        let volume = PlayerVolume()
        #expect(volume.level == 1)
        #expect(!volume.isMuted)
        #expect(volume.sliderFraction == 1)
        #expect(volume.outputGain == 1)
        #expect(volume.tier == .high)
    }

    @Test("A level is held to the slider's ends")
    func clamps() {
        var volume = PlayerVolume()
        volume.setLevel(1.7)
        #expect(volume.level == 1)
        volume.setLevel(-0.3)
        #expect(volume.level == 0)
        #expect(PlayerVolume(level: 4).level == 1)
        #expect(PlayerVolume(level: .nan).level == 1)
    }

    @Test("What reaches the speakers is the level squared, so half way is quieter than half loud")
    func taper() {
        var volume = PlayerVolume()
        volume.setLevel(0.2)
        #expect(abs(volume.outputGain - 0.04) < 1e-9)
        volume.setLevel(0.5)
        #expect(abs(volume.outputGain - 0.25) < 1e-9)
    }

    @Test("Mute silences the output and empties the slider, and unmute brings the level back")
    func mute() {
        var volume = PlayerVolume()
        volume.setLevel(0.2)
        volume.toggleMute()
        #expect(volume.isMuted)
        #expect(volume.outputGain == 0)
        #expect(volume.sliderFraction == 0)
        #expect(volume.tier == .off)
        #expect(volume.level == 0.2)
        volume.toggleMute()
        #expect(!volume.isMuted)
        #expect(volume.sliderFraction == 0.2)
        #expect(abs(volume.outputGain - 0.04) < 1e-9)
    }

    @Test("Setting a level while muted turns the sound back on at that level")
    func levelUnmutes() {
        var volume = PlayerVolume()
        volume.toggleMute()
        volume.setLevel(0.6)
        #expect(!volume.isMuted)
        #expect(volume.level == 0.6)
    }

    @Test("Dragging to nothing while muted keeps it muted")
    func zeroKeepsMute() {
        var volume = PlayerVolume(level: 0.8)
        volume.toggleMute()
        volume.setLevel(0)
        #expect(volume.isMuted)
        #expect(volume.level == 0.8)
    }

    @Test("The speaker at a level of nothing comes back at half rather than staying silent")
    func unmuteFromZero() {
        var volume = PlayerVolume()
        volume.setLevel(0)
        #expect(volume.tier == .off)
        #expect(volume.isSilent)
        volume.toggleMute()
        #expect(!volume.isMuted)
        #expect(volume.level == PlayerVolume.comeBackLevel)
        #expect(!volume.isSilent)
    }

    @Test("The speaker's waves follow the level")
    func tiers() {
        #expect(PlayerVolume(level: 0.1).tier == .low)
        #expect(PlayerVolume(level: 0.5).tier == .medium)
        #expect(PlayerVolume(level: 0.9).tier == .high)
        #expect(PlayerVolume(level: 0).tier == .off)
    }

    @Test("A click lands the knob's centre under the pointer, held to the track")
    func clickFraction() {
        // A 60 wide track and a 12 wide knob: the centre travels 6...54.
        #expect(PlayerVolume.fraction(atX: 6, width: 60, knob: 12) == 0)
        #expect(PlayerVolume.fraction(atX: 54, width: 60, knob: 12) == 1)
        #expect(abs(PlayerVolume.fraction(atX: 15.6, width: 60, knob: 12) - 0.2) < 1e-9)
        #expect(PlayerVolume.fraction(atX: -20, width: 60, knob: 12) == 0)
        #expect(PlayerVolume.fraction(atX: 200, width: 60, knob: 12) == 1)
        // A track no wider than its knob answers something rather than dividing by nothing.
        #expect(PlayerVolume.fraction(atX: 3, width: 4, knob: 12) == 0)
    }

    @Test("The knob sits where a click at that level would land")
    func knobCentre() {
        #expect(PlayerVolume.knobCentre(forFraction: 0, width: 60, knob: 12) == 6)
        #expect(PlayerVolume.knobCentre(forFraction: 1, width: 60, knob: 12) == 54)
        let x = PlayerVolume.knobCentre(forFraction: 0.35, width: 60, knob: 12)
        #expect(abs(PlayerVolume.fraction(atX: x, width: 60, knob: 12) - 0.35) < 1e-9)
    }

    @Test("The wheel turns it up and down, a notch of a mouse wheel a twentieth")
    func wheel() {
        var volume = PlayerVolume(level: 0.5)
        volume.nudge(by: PlayerVolume.wheelStep(dx: 0, dy: 1, precise: false))
        #expect(abs(volume.level - 0.55) < 1e-9)
        volume.nudge(by: PlayerVolume.wheelStep(dx: 0, dy: -2, precise: false))
        #expect(abs(volume.level - 0.45) < 1e-9)
        // A trackpad reports points: two hundred of them run the whole slider.
        volume.nudge(by: PlayerVolume.wheelStep(dx: 0, dy: 100, precise: true))
        #expect(abs(volume.level - 0.95) < 1e-9)
        // Sideways counts too, right is louder, whichever way moved more.
        #expect(PlayerVolume.wheelStep(dx: -3, dy: 1, precise: false) < 0)
        #expect(PlayerVolume.wheelStep(dx: 0, dy: 0, precise: true) == 0)
    }

    @Test("Turning the wheel up while muted starts from nothing and turns the sound on")
    func wheelWhileMuted() {
        var volume = PlayerVolume(level: 0.9)
        volume.toggleMute()
        volume.nudge(by: 0.05)
        #expect(!volume.isMuted)
        #expect(abs(volume.level - 0.05) < 1e-9)
        var down = PlayerVolume(level: 0.9)
        down.toggleMute()
        down.nudge(by: -0.05)
        #expect(down.isMuted)
        #expect(down.level == 0.9)
    }

    @Test("It says itself as a percentage")
    func reading() {
        #expect(PlayerVolume(level: 0.2).percent == 20)
        var muted = PlayerVolume(level: 0.2)
        muted.toggleMute()
        #expect(muted.percent == 0)
    }
}
