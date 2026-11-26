import Testing
@testable import PhotonzCore

@Suite("The probe keeps its sound out of the room")
struct ProbeSoundTests {

    @Test func silentUnlessAPersonAsksToHearIt() {
        #expect(!ProbeSound.isHeard(environment: [:]))
        #expect(!ProbeSound.isHeard(environment: ["PHOTONZ_PROBE_SOUND": "0"]))
        #expect(!ProbeSound.isHeard(environment: ["PHOTONZ_PROBE_SOUND": "yes"]))
        #expect(ProbeSound.isHeard(environment: ["PHOTONZ_PROBE_SOUND": "1"]))
    }

    /// Exactly what `pmset -g assertions` printed on 2026-11-26 while the
    /// scrub task's walk played music out of the speakers, with the other
    /// processes' assertions around it.
    static let heldBy19693 = """
    Assertion status system-wide:
       PreventUserIdleSystemSleep     1
    Listed by owning process:
       pid 717(coreaudiod): [0x0029785d0001876b] 00:00:01 PreventUserIdleSystemSleep named: "com.apple.audio.BuiltInSpeakerDevice.context.preventuseridlesleep"  \u{20}
    \tCreated for PID: 19693.\u{20}
    \tResources: audio-out BuiltInSpeakerDevice\u{20}
       pid 544(powerd): [0x0018e01100019629] 302:06:18 PreventUserIdleSystemSleep named: "Powerd - Prevent sleep while display is on"  \u{20}
       pid 8415(caffeinate): [0x002978100001875c] 00:01:25 PreventUserIdleSystemSleep named: "caffeinate command-line tool"
    \tDetails: caffeinate asserting on behalf of PID 8405
    \tCreated for PID: 8405.
    Kernel Assertions: 0x4=USB
    """

    @Test func readsTheOutputAProcessIsPlayingOutOf() {
        #expect(ProbeSound.outputsHeld(byPID: 19693, inAssertions: Self.heldBy19693) == ["BuiltInSpeakerDevice"])
    }

    /// The caffeinate assertion is created for the loop's pid but holds no
    /// audio, so it is not an output.
    @Test func anAssertionWithNoAudioIsNotAnOutput() {
        #expect(ProbeSound.outputsHeld(byPID: 8405, inAssertions: Self.heldBy19693).isEmpty)
    }

    @Test func anotherProcessesOutputIsNotThisOnes() {
        #expect(ProbeSound.outputsHeld(byPID: 196, inAssertions: Self.heldBy19693).isEmpty)
        #expect(ProbeSound.outputsHeld(byPID: 1969, inAssertions: Self.heldBy19693).isEmpty)
    }

    @Test func twoDevicesAreBothNamed() {
        let text = """
           pid 717(coreaudiod): [0x1] 00:00:01 PreventUserIdleSystemSleep named: "com.apple.audio.A.context.preventuseridlesleep"
        \tCreated for PID: 42.
        \tResources: audio-out BuiltInSpeakerDevice
           pid 717(coreaudiod): [0x2] 00:00:01 PreventUserIdleSystemSleep named: "com.apple.audio.B.context.preventuseridlesleep"
        \tCreated for PID: 42.
        \tResources: audio-out AirPods-Output audio-in AirPods-Input
        """
        #expect(ProbeSound.outputsHeld(byPID: 42, inAssertions: text) == ["BuiltInSpeakerDevice", "AirPods-Output"])
    }
}
