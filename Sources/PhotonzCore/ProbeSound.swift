import Foundation

/// Whether the loop's test app may be heard, and how to tell that it is.
///
/// The probe plays real documents with real soundtracks all day, and on
/// 2026-11-26 the person at the Mac heard music and synth voices coming out of
/// its speakers from nowhere. So a probe is inaudible to the room: its sound
/// engines run, mix and keep time exactly as in real use, and the system
/// throws the result away at the very last step, on its way to the device.
/// A person running a walk by hand who wants to hear it sets
/// `PHOTONZ_PROBE_SOUND=1`.
///
/// "Heard" is checked the way the system itself records it: an output device
/// in use by a process keeps an `audio-out` assertion created for that
/// process, which `pmset -g assertions` lists. A probe that is truly silent to
/// the room holds none.
public enum ProbeSound {

    /// The environment switch that lets a probe be heard.
    public static let hearItKey = "PHOTONZ_PROBE_SOUND"

    public static func isHeard(environment: [String: String]) -> Bool {
        environment[hearItKey] == "1"
    }

    /// The output devices `pmset -g assertions` (the text in `assertions`)
    /// says are playing out of for `pid`, in the order listed. Empty when that
    /// process is sending nothing to any speaker.
    public static func outputsHeld(byPID pid: Int32, inAssertions assertions: String) -> [String] {
        var outputs: [String] = []
        var blockPID: Int32?
        var blockOutputs: [String] = []
        func close() {
            if blockPID == pid { outputs += blockOutputs }
            blockPID = nil
            blockOutputs = []
        }
        for raw in assertions.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("pid "), line.contains("):") {
                close()
            } else if line.hasPrefix("Created for PID:") {
                let number = line.dropFirst("Created for PID:".count)
                    .trimmingCharacters(in: CharacterSet(charactersIn: " ."))
                blockPID = Int32(number)
            } else if line.hasPrefix("Resources:") {
                let words = line.dropFirst("Resources:".count).split(separator: " ")
                for (index, word) in words.enumerated() where word == "audio-out" && index + 1 < words.count {
                    blockOutputs.append(String(words[index + 1]))
                }
            } else if !raw.hasPrefix("\t"), !raw.hasPrefix(" ") {
                close()
            }
        }
        close()
        return outputs
    }
}
