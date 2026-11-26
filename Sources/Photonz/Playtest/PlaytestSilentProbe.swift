#if PHOTONZ_PLAYTEST
import AppKit
import CoreAudio
import PhotonzCore

/// Keeps everything the probe plays out of the room. Probe builds only.
///
/// The loop's walks play real documents with real soundtracks, and on
/// 2026-11-26 the person at this Mac heard music and synth voices coming out of
/// the speakers from nowhere: a scrub walk's probe, holding the speakers'
/// `audio-out` assertion. So a probe tells Core Audio two things about itself
/// before it plays anything, the way the private clipboard is one switch at the
/// root rather than a change at each call site:
///
/// * `kAudioHardwarePropertyProcessIsAudible` 0: "all audio in the process will
///   not be heard". Every engine (the document's, the scrub's, the plain video
///   player) still runs on the real output device, at its real rate, latency and
///   clock, and every tap on a mixer still reads the real mix; the system zeroes
///   the process's share of the device at the very last step.
/// * `kAudioHardwarePropertySleepingIsAllowed` 1: the running output no longer
///   keeps the Mac from idle sleep, which is what takes the `audio-out`
///   assertion away (`pmset -g assertions` lists none for the probe). The loop
///   holds the Mac awake on its own (`queue/bin/go-loop.sh`), so a walk loses
///   nothing by it.
///
/// Both are the process's own and end with it. Measured on 2026-11-26 with a
/// tone on an engine: the mixer tap peak, the output's presentation latency and
/// a valid host time on its last render read the same with and without them.
///
/// A person running a walk by hand who wants to hear it sets
/// `PHOTONZ_PROBE_SOUND=1` (passed through by `Scripts/probe-app.sh`).
enum PlaytestSilentProbe {

    /// Whether this probe asked to be inaudible and Core Audio took both.
    @MainActor private(set) static var isSilent = false

    /// First thing at launch, before any engine is made.
    @MainActor
    static func install() {
        guard !ProbeSound.isHeard(environment: ProcessInfo.processInfo.environment) else {
            NSLog("Probe sound: heard out loud, as asked (\(ProbeSound.hearItKey)=1)")
            return
        }
        let muted = set(kAudioHardwarePropertyProcessIsAudible, to: 0)
        let sleeps = set(kAudioHardwarePropertySleepingIsAllowed, to: 1)
        isSilent = muted == noErr && sleeps == noErr
        if !isSilent {
            NSLog("Probe sound: could not keep it out of the room (audible \(muted), sleep \(sleeps))")
        }
    }

    /// What Core Audio says about this process right now: whether it is
    /// audible, and the outputs the system's assertions say it is playing out
    /// of. For a walk.
    static func audibleNow() -> Bool? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessIsAudible,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 1
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                                                &size, &value)
        return status == noErr ? value != 0 : nil
    }

    /// The output devices `pmset -g assertions` says this process holds.
    /// Nil when pmset could not be read.
    static func outputsHeld() -> [String]? {
        let pmset = Process()
        pmset.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        pmset.arguments = ["-g", "assertions"]
        let pipe = Pipe()
        pmset.standardOutput = pipe
        pmset.standardError = FileHandle.nullDevice
        do { try pmset.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        pmset.waitUntilExit()
        guard pmset.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else { return nil }
        return ProbeSound.outputsHeld(byPID: getpid(), inAssertions: text)
    }

    /// Nil when the room hears nothing of this probe, or why it does.
    @MainActor
    static func whyTheRoomHearsIt() -> String? {
        if ProbeSound.isHeard(environment: ProcessInfo.processInfo.environment) { return nil }
        if audibleNow() != false {
            return "the probe is audible to the room: Core Audio did not take its mute"
        }
        guard let held = outputsHeld() else { return "pmset -g assertions could not be read" }
        if !held.isEmpty {
            return "the probe holds an audio-out assertion on \(held.joined(separator: ", ")), so the "
                + "Mac treats it as playing out of its speakers"
        }
        return nil
    }

    private static func set(_ selector: AudioObjectPropertySelector, to value: UInt32) -> OSStatus {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value = value
        return AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                                          UInt32(MemoryLayout<UInt32>.size), &value)
    }
}
#endif
