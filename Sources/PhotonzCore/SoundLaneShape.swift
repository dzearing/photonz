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
