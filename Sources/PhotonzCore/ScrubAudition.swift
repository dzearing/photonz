import Foundation

// What you hear while you drag the playhead (`docs/design/video-audio.md` §6).
//
// Playing and scrubbing want opposite things from the same plan. Playing
// schedules whole pieces once and lets the engine's clock carry them; a scrub
// has no clock at all, because the clock is somebody's hand. So a scrub is a
// run of short GRAINS: every so often, the little bit of the file that is
// under the playhead right now, played once, the way the hand is going.
//
// **The arithmetic is the whole of it.** Which file, which frames of it, which
// way round and how loud is worked out here, from the same `audioMix()` the
// player and the exporter read, so what you hear while you hunt for a word is
// the same sound you hear when you press play and the same sound that exports.
// Everything left over is an engine node.

/// One short piece of a file to play once, because the playhead went over it.
public struct ScrubWindow: Hashable, Sendable {
    /// Whose sound this is, so two layers under the playhead stay two sounds.
    public let layerID: UUID
    public let sound: SoundRef
    /// Where in the FILE it reads from, and how much of it.
    public let sourceInMS: Int
    public let lengthMS: Int
    /// How loud, at the moment the playhead is standing on.
    public let gain: Double
    /// Whether it plays back to front, which is what dragging backwards is.
    public let isReversed: Bool

    public init(layerID: UUID, sound: SoundRef, sourceInMS: Int, lengthMS: Int,
                gain: Double, isReversed: Bool) {
        self.layerID = layerID
        self.sound = sound
        self.sourceInMS = sourceInMS
        self.lengthMS = lengthMS
        self.gain = gain
        self.isReversed = isReversed
    }

    public var sourceOutMS: Int { sourceInMS + lengthMS }
}

public enum ScrubAudition {

    /// How long one grain is.
    ///
    /// Short enough that it is a scrub rather than a playback — a hand that
    /// stops is quiet within this — and long enough to carry a syllable, which
    /// is what somebody hunting for a word is listening for. Sixty
    /// milliseconds is about two cycles of the lowest note in a voice.
    public static let windowMS = 60

    /// How much of each end of a grain is faded.
    ///
    /// Grains butt up against each other and against silence, and a waveform
    /// cut off mid-cycle is a click. Five milliseconds either end is below
    /// what anybody hears as a fade and above what anybody hears as a click.
    public static let fadeMS = 5

    /// What to play, now that the playhead has moved from one moment to
    /// another.
    ///
    /// One grain per piece of sound under the moment it landed on, so two
    /// sounds laid over each other are both heard. Nothing at all where the
    /// hand has not moved: a scrub is a sound that MOVEMENT makes, so the
    /// instant somebody stops, the last grain plays out and it is quiet.
    public static func windows(in mix: [AudioMixSegment], movingFromMS: Int, toMS: Int,
                               windowMS: Int = ScrubAudition.windowMS) -> [ScrubWindow] {
        guard toMS != movingFromMS, windowMS > 0 else { return [] }
        let backwards = toMS < movingFromMS
        return mix.compactMap { segment in
            guard segment.contains(ms: toMS) else { return nil }
            let gain = segment.gain(atMS: toMS)
            guard gain > 0 else { return nil }

            // Where in the file the playhead is standing. A piece not at the
            // speed it was recorded at covers more (or less) of its file than
            // it does of the timeline, so the moment moves along at its rate.
            let speed = Double(max(1, segment.speedPercent)) / 100
            let at = segment.sourceInMS + Int((Double(toMS - segment.startMS) * speed).rounded())

            // Going forwards the grain STARTS where the playhead is; going
            // backwards it ENDS there, so either way what you hear is the run
            // the hand is making, in the direction it is making it.
            let wanted = backwards ? at - windowMS : at
            let lastStart = max(segment.sourceInMS, segment.sourceOutMS - 1)
            let sourceIn = min(max(segment.sourceInMS, wanted), lastStart)
            let lengthMS = min(windowMS, segment.sourceOutMS - sourceIn)
            guard lengthMS > 0 else { return nil }

            return ScrubWindow(layerID: segment.layerID, sound: segment.sound,
                               sourceInMS: sourceIn, lengthMS: lengthMS,
                               gain: gain, isReversed: backwards)
        }
    }
}
