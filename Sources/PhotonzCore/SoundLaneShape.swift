import CoreGraphics

/// **How a sound's lane on the timeline is drawn** (`SoundLaneShapeTests`).
///
/// video-audio.html draws a sound lane 84 points tall, 72 when the window is
/// 880 points wide or less, so a fade, a quiet stretch and the level line over
/// them all have room to be read and dragged. Its waveform is one filled shape,
/// the top edge drawn along and the bottom edge drawn back, mirrored about the
/// middle, the loudest sound reaching 42 of the 50 units either side of it.
public enum SoundLaneShape {
    /// `.tlgrid .track .lane.alane{height:84px}`.
    public static let height: CGFloat = 84
    /// The same lane in a narrow window.
    public static let narrowHeight: CGFloat = 72
    /// `@container shell (max-width:880px)`: this wide or narrower is narrow.
    public static let narrowWindowWidth: CGFloat = 880
    /// How far the loudest sound reaches from the middle toward the edge.
    public static let reach: CGFloat = 0.84
    /// How far either side of the middle silence still draws, so a quiet
    /// stretch reads as silence rather than as a gap in the drawing.
    public static let hairline: CGFloat = 0.5

    /// Where the volume line sits for the level a sound was recorded at, as a
    /// share of the lane from its top: `yOfLevel(1) = 90 - 78 = 12` of 100.
    public static let recordedLevelLine: CGFloat = 0.12
    /// Where it sits for silence: `yOfLevel(0) = 90` of 100.
    public static let silenceLine: CGFloat = 0.90
    /// The least room kept above the recorded level, in points, so a bar too
    /// short for the mock's twelve hundredths to clear a dot's own room still
    /// has somewhere to turn a sound up in.
    public static let leastRoomToTurnUp: CGFloat = 3

    /// How far down a lane `height` tall the volume line is drawn for `gain`.
    ///
    /// Up to the recorded level it is the mock's straight line, silence at 90
    /// of 100 and the recorded level at 12, so a sound nobody has touched reads
    /// as full with its waveform under the line. The mock stops there; the app
    /// lets a level go to twice as loud, and that room is the strip above, from
    /// the recorded level to `inset` from the top (where a dot is still drawn
    /// whole), straight as well.
    public static func levelY(forGain gain: Double, height: CGFloat, inset: CGFloat) -> CGFloat {
        let (top, unity, silence) = levelLines(height: height, inset: inset)
        let held = gain.isFinite ? min(max(0, gain), AudioLevel.loudestGain) : AudioLevel.unityGain
        if held <= AudioLevel.unityGain {
            return silence - (silence - unity) * CGFloat(held / AudioLevel.unityGain)
        }
        let over = (held - AudioLevel.unityGain) / (AudioLevel.loudestGain - AudioLevel.unityGain)
        return unity - (unity - top) * CGFloat(over)
    }

    /// The level a height on the lane stands for: `levelY` read backwards, so a
    /// drag lands the line under the hand. Above the top of the room it is as
    /// loud as a level goes, below silence's line it is silence.
    public static func gain(atLevelY y: CGFloat, height: CGFloat, inset: CGFloat) -> Double {
        guard height > inset * 2, y.isFinite else { return AudioLevel.unityGain }
        let (top, unity, silence) = levelLines(height: height, inset: inset)
        if y >= unity {
            let through = (silence - min(y, silence)) / (silence - unity)
            return AudioLevel.bounded(Double(through) * AudioLevel.unityGain)
        }
        let over = unity > top ? (unity - max(y, top)) / (unity - top) : 1
        return AudioLevel.bounded(AudioLevel.unityGain
                                  + Double(over) * (AudioLevel.loudestGain - AudioLevel.unityGain))
    }

    /// The top of the room to turn a sound up in, the recorded level's line and
    /// silence's, down a lane `height` tall.
    private static func levelLines(height: CGFloat, inset: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
        let top = inset
        let unity = max(height * recordedLevelLine, top + leastRoomToTurnUp)
        let silence = max(unity + 1, min(height * silenceLine, height - inset))
        return (top, unity, silence)
    }

    /// The lane's height in a window this wide. A window not measured yet is
    /// taken as wide, which is how nearly every window opens.
    public static func height(windowWidth: CGFloat) -> CGFloat {
        guard windowWidth.isFinite, windowWidth > 0 else { return height }
        return windowWidth <= narrowWindowWidth ? narrowHeight : height
    }

    /// The waveform's outline in a box `width` by `height`: one point per
    /// column at the column's middle along the top, left to right, then the
    /// same columns along the bottom, right to left. `heights` is one
    /// nought-to-one height per column, already worked out
    /// (`Waveform.drawnHeights`).
    public static func outline(heights: [Float], width: CGFloat, height: CGFloat) -> [CGPoint] {
        guard !heights.isEmpty, width > 0, height > 0 else { return [] }
        let step = width / CGFloat(heights.count)
        let middle = height / 2
        let halves = heights.map { max(hairline, CGFloat(min(max(0, $0), 1)) * middle * reach) }
        let xs = heights.indices.map { (CGFloat($0) + 0.5) * step }
        let top = zip(xs, halves).map { CGPoint(x: $0, y: middle - $1) }
        let bottom = zip(xs, halves).reversed().map { CGPoint(x: $0, y: middle + $1) }
        return top + bottom
    }
}
