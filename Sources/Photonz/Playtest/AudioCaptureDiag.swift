#if PHOTONZ_PLAYTEST
import AppKit
import PhotonzCore

/// Probe-only check of how loud system audio lands in a recording
/// (`--audio-capture-diag <sound file>`). Records five seconds of the main
/// display with system audio through the real `ScreenRecorder`, while `afplay`
/// plays the given file, and leaves the recording at
/// `/tmp/photonz-audio-diag.mp4`. Measure it against the file played
/// (`ffmpeg -i … -af volumedetect -f null -`): equal peaks mean the capture is
/// at unity, lower ones mean it follows the output volume. Add
/// `--with-microphone` to record the microphone alongside, as a person would.
@MainActor
enum AudioCaptureDiag {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--audio-capture-diag"), i + 1 < args.count else { return }
        let sound = args[i + 1]
        Task { await run(sound: sound, args: args) }
    }

    private static func run(sound: String, args: [String]) async {
        guard let screen = NSScreen.main else { return }
        let url = URL(fileURLWithPath: "/tmp/photonz-audio-diag.mp4")
        try? FileManager.default.removeItem(at: url)
        let recorder = ScreenRecorder()
        do {
            try await recorder.start(config: RecordingConfig(audio: args.contains("--with-microphone") ? [.systemAudio, .microphone] : [.systemAudio]),
                                     screen: screen, to: url, excluding: [])
            try await Task.sleep(for: .milliseconds(500))
            let player = Process()
            player.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
            player.arguments = [sound]
            try player.run()
            try await Task.sleep(for: .seconds(4))
            player.terminate()
            try await recorder.stop()
            NSLog("[audio-capture-diag] wrote \(url.path)")
        } catch {
            NSLog("[audio-capture-diag] failed: \(error)")
        }
        try? "done".write(toFile: "/tmp/photonz-audio-diag.done", atomically: true, encoding: .utf8)
    }
}
#endif
