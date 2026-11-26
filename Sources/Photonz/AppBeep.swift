import AppKit

/// The app's alert beep. One place, because the system plays it in its own
/// sound server, not in this process, so the probe's mute
/// (`PlaytestSilentProbe`) does not reach it: in a probe that is keeping its
/// sound out of the room, a beep is not played at all.
enum AppBeep {
    @MainActor static func play() {
        #if PHOTONZ_PLAYTEST
        if PlaytestSilentProbe.isSilent { return }
        #endif
        NSSound.beep()
    }
}
