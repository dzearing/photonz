import Foundation

/// The level each voice of the player should be at, at a moment of the
/// document: what the player's per-voice faders are set to as it plays.
///
/// A voice with a piece playing is at that piece's level. A voice whose next
/// piece starts within `aheadMS` is already at the level that piece opens on,
/// because the faders are set on a tick (about thirty times a second, off the
/// picture's clock) while the engine renders ahead of the picture: held at
/// nought until the first tick after it started, a clip that met another on
/// the timeline came in after a hole of 18 to 26 ms (2026-11-26,
/// `sound-clips-that-meet-play-straight-through-walk`). A voice with neither
/// has no entry, and the player keeps it silent.
public enum AudioVoiceLevels {

    public struct Key: Hashable, Sendable {
        public let layerID: UUID
        public let voice: Int
        public init(layerID: UUID, voice: Int) {
            self.layerID = layerID
            self.voice = voice
        }
        public init(_ segment: AudioMixSegment) {
            self.init(layerID: segment.layerID, voice: segment.voice)
        }
    }

    /// Long enough to cover a tick and the output's latency on a wired
    /// speaker; short enough that a voice is never turned up long before its
    /// sound, which a fader nobody hears cannot show anyway.
    public static let defaultAheadMS = 250

    public static func at(ms: Int, in mix: [AudioMixSegment],
                          aheadMS: Int = defaultAheadMS) -> [Key: Double] {
        var now: [Key: Double] = [:]
        var next: [Key: (startMS: Int, gain: Double)] = [:]
        for segment in mix {
            let key = Key(segment)
            if segment.contains(ms: ms) {
                now[key] = segment.gain(atMS: ms)
            } else if segment.startMS > ms, segment.startMS <= ms + aheadMS {
                if let known = next[key], known.startMS <= segment.startMS { continue }
                next[key] = (segment.startMS, segment.gain(atMS: segment.startMS))
            }
        }
        for (key, coming) in next where now[key] == nil { now[key] = coming.gain }
        return now
    }
}
