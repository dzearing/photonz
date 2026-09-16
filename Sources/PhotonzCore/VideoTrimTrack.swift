import CoreGraphics
import Foundation

/// Where one piece of a recording is drawn on the trim track, and how much of
/// that block the trim window still keeps.
///
/// The trim handles used to hide the pieces: opening them turned the strip back
/// into one plain bar, so you were dragging the start and end of something you
/// could no longer see the shape of. These blocks put the pieces back under the
/// handles, and the lit part of each one is what the window would keep, so a
/// handle coming up on a join shows what it is about to eat into.
///
/// Positions are points along the track, already including the breathing room
/// at each end, so a view draws them straight without doing arithmetic of its
/// own.
public struct VideoTrimTrackBlock: Equatable, Sendable {
    /// The piece's place in the cut list, in play order.
    public let index: Int
    /// The whole piece.
    public let x: CGFloat
    public let width: CGFloat
    /// The part of it the trim window keeps. Zero width when the window has let
    /// go of this piece entirely.
    public let keptX: CGFloat
    public let keptWidth: CGFloat

    public init(index: Int, x: CGFloat, width: CGFloat, keptX: CGFloat, keptWidth: CGFloat) {
        self.index = index
        self.x = x
        self.width = width
        self.keptX = keptX
        self.keptWidth = keptWidth
    }

    /// Nothing of this piece survives the window: applying the trim throws it away.
    public var isDropped: Bool { keptWidth <= 0 }

    /// Lay the pieces out along a track.
    ///
    /// - Parameters:
    ///   - pieces: the pieces read against the live trim window.
    ///   - duration: the timeline length the track spans.
    ///   - inset: breathing room at each end, so a handle at either extreme
    ///     stays on screen and grabbable.
    ///   - trackWidth: the drawable width between the insets.
    ///   - joinGap: the space drawn at a cut, taken half from each side, so the
    ///     gap between two pieces is the cut itself.
    public static func blocks(for pieces: [VideoPieceTrim],
                              duration: TimeInterval,
                              inset: CGFloat,
                              trackWidth: CGFloat,
                              joinGap: CGFloat) -> [VideoTrimTrackBlock] {
        let span = max(duration, 0.0001)
        func x(_ seconds: TimeInterval) -> CGFloat {
            inset + CGFloat(min(max(0, seconds), span) / span) * trackWidth
        }
        return pieces.map { piece in
            let left = x(piece.start) + joinGap / 2
            let right = max(left, x(piece.end) - joinGap / 2)
            let width = right - left
            guard let keptStart = piece.keptStart, let keptEnd = piece.keptEnd else {
                return VideoTrimTrackBlock(index: piece.index, x: left, width: width,
                                           keptX: left, keptWidth: 0)
            }
            // Clamped into the block: a handle sitting in the gap at a cut
            // belongs to the block, not to the space beside it.
            let keptX = min(max(left, x(keptStart)), right)
            let keptRight = min(max(keptX, x(keptEnd)), right)
            return VideoTrimTrackBlock(index: piece.index, x: left, width: width,
                                       keptX: keptX, keptWidth: keptRight - keptX)
        }
    }
}
