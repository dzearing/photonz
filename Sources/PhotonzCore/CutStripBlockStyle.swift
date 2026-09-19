import CoreGraphics
import Foundation

/// Which colour a part of a cut-strip block is drawn in. The strip has three
/// and they mean different things rather than different amounts of the same
/// thing: which piece you are holding, every other piece, and how far into a
/// piece you have watched.
public enum CutStripTint: String, Equatable, Sendable, Codable {
    /// Every piece that is not picked: the window's own foreground colour at a
    /// low alpha, so it is white on a dark bar and black on a light one.
    case neutral
    /// The picked piece, and nothing else on the strip.
    case accent
    /// Plain white, whatever the window's appearance: the lift drawn over the
    /// picked block to show how far into it you have watched, and the hairline
    /// round it.
    case lift
}

/// How one piece of a cut recording is drawn on the strip under the picture.
///
/// The strip has two things to say at once and they were fighting. A block
/// says how far you have watched into that piece, and one block says which
/// piece you are holding, which is the piece Delete would take. Drawn in the
/// same currency — brightness of the same colour — progress won: a piece
/// already watched was filled at 0.55 while the picked piece sat at 0.30, so
/// the strongest block on the strip was the one furthest from what you were
/// about to do, and the faintest was the one about to be deleted.
///
/// The fix is to stop saying both things the same way. Progress keeps
/// brightness and gets quieter. The pick takes three signals that progress
/// never uses: the accent colour, a taller block, and a hairline round it. So
/// the picked piece reads first whether it has been watched all the way
/// through or not at all, and nothing about it can be mistaken for "more of
/// this has played".
///
/// The hairline is white rather than the accent on purpose. An accent outline
/// round an accent-filled block vanishes into it the moment the piece has been
/// watched, which is exactly the case the old drawing never had to face
/// because its picked block was nearly empty. White also makes the mark the
/// same one the trim track already uses for the picked piece, so a pick looks
/// like a pick whether or not the handles are open.
public struct CutStripBlockStyle: Equatable, Sendable {
    /// Which of the strip's two colours this block is drawn in.
    public let tint: CutStripTint
    /// Alpha of the fill across the whole block.
    public let baseOpacity: Double
    /// What the watched part of the block is lit with, drawn over the base.
    /// The picked block lights up in white rather than in more of its own
    /// accent: it is already the accent one, so another layer of accent on it
    /// says almost nothing, and white is the one lift that still reads on top
    /// of a saturated colour.
    public let playedTint: CutStripTint
    /// Alpha of that lit part.
    public let playedOpacity: Double
    /// How much of the block has been watched, 0 to 1, already clamped.
    public let playedFraction: Double
    /// How tall this block is drawn. The picked one is taller, which is the
    /// one signal that survives a screenshot with the colour washed out of it.
    public let height: CGFloat
    /// Width of the hairline round the block; zero when there is none.
    public let strokeWidth: CGFloat
    /// Alpha of that hairline, always drawn in white.
    public let strokeOpacity: Double

    /// The row the blocks sit in, tall enough for the tallest of them so
    /// picking a different piece never changes the height of the strip.
    public static let rowHeight: CGFloat = 22
    /// Corner radius shared by the fill and the hairline.
    public static let cornerRadius: CGFloat = 5

    public init(tint: CutStripTint, baseOpacity: Double,
                playedTint: CutStripTint, playedOpacity: Double,
                playedFraction: Double, height: CGFloat,
                strokeWidth: CGFloat, strokeOpacity: Double) {
        self.tint = tint
        self.baseOpacity = baseOpacity
        self.playedTint = playedTint
        self.playedOpacity = playedOpacity
        self.playedFraction = playedFraction
        self.height = height
        self.strokeWidth = strokeWidth
        self.strokeOpacity = strokeOpacity
    }

    /// How much of the bar this block covers up where the playhead has NOT
    /// reached: its quietest part.
    public var quietestFill: Double { baseOpacity }
    /// How much of the bar it covers up where the playhead HAS been: its
    /// loudest part. Two fills stacked, so what is left of the bar underneath
    /// is what got through both of them.
    public var loudestFill: Double { 1 - (1 - baseOpacity) * (1 - playedOpacity) }

    /// How a piece is drawn, given whether the playhead is in it and how far
    /// into it the playhead has got.
    public static func block(isPicked: Bool, playedFraction: Double) -> CutStripBlockStyle {
        let fraction = playedFraction.isFinite ? min(max(0, playedFraction), 1) : 0
        if isPicked {
            return CutStripBlockStyle(tint: .accent, baseOpacity: 0.92,
                                      playedTint: .lift, playedOpacity: 0.42,
                                      playedFraction: fraction,
                                      height: rowHeight,
                                      strokeWidth: 1.5, strokeOpacity: 0.9)
        }
        // Quiet enough that the loudest an unpicked block can get still sits
        // under the faintest the picked one ever is.
        return CutStripBlockStyle(tint: .neutral, baseOpacity: 0.12,
                                  playedTint: .neutral, playedOpacity: 0.23,
                                  playedFraction: fraction,
                                  height: 18,
                                  strokeWidth: 0, strokeOpacity: 0)
    }
}
