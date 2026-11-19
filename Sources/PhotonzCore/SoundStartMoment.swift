import Foundation

/// Where the document's sound opens when play is pressed.
///
/// The playhead starts moving the moment play is pressed, and the picture
/// follows it. The sound cannot be heard that soon: its engine has to start,
/// everything is hung a safety lead after that so pieces meant to start
/// together do, and the output device adds its own latency on the way to the
/// room. Opened at the press's moment, the sound was heard about 180 ms behind
/// the picture for the whole of a playthrough (measured 2026-11-19, task
/// `find-out-whether-the-sound-plays-a-fifth-of-a-se`). So it opens at the
/// moment the playhead will have reached when it is first heard: the first
/// fifth of a second after a press is silent, and everything after it is in
/// step with the picture.
public enum SoundStartMoment {

    /// How long after its moment the picture is on screen, as the sound
    /// allows for it: the play clock ticks once a frame and a picture is
    /// drawn and waits for the display's refresh, so the picture for a
    /// moment goes up about half a frame after it (measured on the 6 and 20
    /// minute reference edits, 2026-11-19). Late sound is far less noticeable
    /// than early (ITU-R BT.1359), so erring this way is the safe side.
    public static let pictureLagMS = Double(MovieRef.frameStepMS) / 2

    /// The moment of the document to open the sound on, in milliseconds.
    ///
    /// - Parameters:
    ///   - playheadMS: where the playhead was at `playheadAtSeconds`.
    ///   - playheadAtSeconds: when, on the same clock as the other times.
    ///   - startsAtSeconds: when the engine puts out its first sample.
    ///   - outputLatencySeconds: what the output device adds after that.
    ///   - rate: how fast the playhead runs, in document seconds a second.
    ///   - pictureLagMS: how long after its moment the picture reaches the
    ///     screen, in wall milliseconds (`pictureLagMS`).
    public static func documentMS(playheadMS: Int, playheadAtSeconds: Double, startsAtSeconds: Double,
                                  outputLatencySeconds: Double, rate: Double, pictureLagMS: Double = 0) -> Int {
        let heardAt = startsAtSeconds + max(0, outputLatencySeconds) - max(0, pictureLagMS) / 1000
        let onMS = (heardAt - playheadAtSeconds) * 1000 * rate
        guard onMS.isFinite else { return playheadMS }
        return playheadMS + Int(max(0, onMS).rounded())
    }
}
