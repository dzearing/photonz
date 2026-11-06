import CoreGraphics

/// **How a clip with its own sound shares its lane** (the user, 2026-11-05).
///
/// A recording that still carries its sound is one clip: the picture across
/// the top and the waveform across the bottom, the way Final Cut draws attached
/// audio. The picture stays as tall as a clip with no sound, so thumbnails and
/// the name read the same on every track. The sound gets the same again: at
/// 22 points the level line had half the travel of a sound lane and was too
/// coarse to set by hand. Still shorter than the two rows it replaced.
public struct ClipHalves: Equatable, Sendable {

    /// The lane of a clip with its own sound at the rows' resting height.
    public static let restingLaneHeight: CGFloat = 56
    /// The picture's height at rest: the height of a clip with no sound.
    private static let restingPicture: CGFloat = 28

    /// The top of the clip.
    public let picture: CGFloat
    /// The bottom of the clip, under the picture.
    public let sound: CGFloat

    /// The two halves of a lane `laneHeight` tall, in the resting proportion
    /// so a taller row grows both.
    public init(laneHeight: CGFloat) {
        picture = (laneHeight * Self.restingPicture / Self.restingLaneHeight).rounded()
        sound = laneHeight - picture
    }
}
