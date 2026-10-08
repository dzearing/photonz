import Foundation

// A retimed clip shows its original length beside it
// (task `a-sped-up-or-slowed-clip-shows-its-original-leng`,
// `docs/design/mocks/pages/video-speed.html` `.srcbar`, the Source row over
// the Retimed one).
//
// Change a clip's speed and the clip grows or shrinks; nothing said how long
// it was before. The ghost is that before: a striped bar on a lane under the
// picked clip, starting where the clip starts and as long as the clip would
// be with every piece that plays at 100%. It is a view of the clip, never part
// of the document, so it is worked out here and stored nowhere.

/// The original length of a retimed clip, where its Source lane draws it.
public struct ClipSourceGhost: Hashable, Sendable {
    /// Where the clip starts on the timeline, and so where the ghost does.
    public let startMS: Int
    /// How long the clip would run with every piece at 100%. A held frame
    /// keeps its own length: a hold is not a speed to undo.
    public let lengthMS: Int
    /// How long the clip runs now.
    public let retimedLengthMS: Int

    public var endMS: Int { startMS + lengthMS }

    /// Nil where no piece that plays is retimed, which is the only case with
    /// a before and after to show. A held frame on its own is not a retime.
    public init?(pieces: ClipPieces, startMS: Int) {
        let playing = pieces.pieces.filter { !$0.isHeld }
        guard playing.contains(where: { $0.speedPercent != ClipPiece.asRecordedPercent }) else { return nil }
        self.startMS = startMS
        self.lengthMS = pieces.pieces.reduce(0) { $0 + ($1.isHeld ? $1.lengthMS : $1.sourceLengthMS) }
        self.retimedLengthMS = pieces.pieces.reduce(0) { $0 + $1.lengthMS }
    }
}
