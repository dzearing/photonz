import CoreGraphics
import Foundation

/// **Pictures along a clip on the timeline.**
///
/// At Fit a clip is the coloured bar the mock draws (`video.html`, the
/// timeline). Opened out far enough that one small picture stands for a short
/// stretch of the recording, the clip shows frames of what is in it, the way
/// Premiere and Final Cut draw one, so a moment in a five minute recording can
/// be found by looking rather than by playing. The user chose exactly that on
/// 2026-09-25: pictures only when zoomed in.
///
/// Everything here is arithmetic: whether pictures show, how big one is, and
/// which moment of the recording each one is of. Reading the frames is the
/// app's (`ClipFilmstripFrames`).
public enum ClipFilmstrip {

    // MARK: When pictures show

    /// A tile standing for this much of the timeline or less is a picture of
    /// something in particular, and pictures show in full.
    public static let clearTileMS: Double = 8000
    /// A tile standing for this much or more is a picture of nothing in
    /// particular, and the clip stays its coloured bar. Between the two they
    /// fade, so a pinch never makes them pop.
    public static let goneTileMS: Double = 16000
    /// How far past Fit the timeline has to be opened before pictures are in
    /// full. The first zoom step (2x) is past it, so a press shows them; a
    /// pinch passes through the fade.
    public static let fullScale: Double = 1.5

    /// How strongly the pictures show, nought to one.
    ///
    /// Nought at Fit whatever the clip, because at Fit the clip is the mock's
    /// bar: that is the answer the user gave, and a short clip whose tiles
    /// would each be a fraction of a second does not change it.
    public static func opacity(zoom: TimelineZoom, msPerTile: Double) -> Double {
        guard !zoom.isFit else { return 0 }
        let opened = min(1, max(0, (zoom.scale - 1) / (fullScale - 1)))
        let recognisable = min(1, max(0, (goneTileMS - msPerTile) / (goneTileMS - clearTileMS)))
        return min(opened, recognisable)
    }

    // MARK: How big a picture is

    /// The narrowest and widest a tile is drawn, as a share of its height. A
    /// phone recording on its side is still a tile you can see into, and a
    /// panorama is not a sliver of a strip.
    public static let narrowestAspect: CGFloat = 0.6
    public static let widestAspect: CGFloat = 2.4

    /// How wide one picture is before the ladder rounds it: the recording's
    /// own shape at the strip's height.
    public static func tileWidth(height: CGFloat, aspect: CGFloat) -> CGFloat {
        height * min(widestAspect, max(narrowestAspect, aspect))
    }

    // MARK: Which moments the pictures are of

    /// How much of the timeline one tile stands for: one frame times a power
    /// of two, the one nearest the nominal width at this zoom.
    ///
    /// A ladder rather than the exact width because a tile's moment is what a
    /// decoded frame is filed under. Exact, every step of a pinch would ask for
    /// a whole new row of frames; on the ladder a pinch inside one rung asks
    /// for none, and stepping a rung in keeps every other frame it had.
    public static func tileMS(nominalWidth: CGFloat, msPerPoint: Double) -> Int {
        let frame = Double(MovieRef.frameStepMS)
        let wanted = max(frame, Double(nominalWidth) * msPerPoint)
        let rung = min(20, max(0, (log2(wanted / frame)).rounded()))
        return MovieRef.frameStepMS << Int(rung)
    }

    /// One picture along a piece.
    public struct Tile: Hashable, Sendable {
        /// Its place in the piece's row, counted from the piece's start. Stays
        /// the same as the window scrolls, which is what keeps it on screen
        /// rather than being drawn again.
        public let index: Int
        /// Where it starts and how wide it is, in the piece's own points.
        public let x: CGFloat
        public let width: CGFloat
        /// The moment in the recording it is a picture of.
        public let sourceMS: Int
    }

    /// The most tiles one piece ever lays out, however it is asked. A window
    /// is a couple of thousand points wide at most, so this is never reached
    /// by anything real; it is here so nothing can ever ask for thousands.
    static let mostTiles = 200

    /// The tiles of `piece` that fall over `visible`, a stretch of the piece's
    /// own points, for a piece drawn `pieceWidth` points wide.
    ///
    /// Anchored to the piece's start rather than to the window, so scrolling
    /// slides the same pictures along instead of asking for new ones, and each
    /// is the frame at the tile's START: stepping a rung in halves the tiles
    /// and every other one lands on a moment already read.
    public static func tiles(of piece: ClipPiece, pieceWidth: CGFloat,
                             visible: ClosedRange<CGFloat>, nominalWidth: CGFloat) -> [Tile] {
        guard pieceWidth > 0, piece.lengthMS > 0, nominalWidth > 0 else { return [] }
        let msPerPoint = Double(piece.lengthMS) / Double(pieceWidth)
        let step = tileMS(nominalWidth: nominalWidth, msPerPoint: msPerPoint)
        let width = CGFloat(Double(step) / msPerPoint)
        guard width > 0 else { return [] }
        let low = max(0, visible.lowerBound)
        let high = min(pieceWidth, visible.upperBound)
        guard high > low else { return [] }
        let first = Int((low / width).rounded(.down))
        let last = min(Int((high / width).rounded(.up)) - 1, first + mostTiles - 1)
        guard last >= first else { return [] }
        return (first...last).compactMap { index in
            let x = CGFloat(index) * width
            guard x < pieceWidth else { return nil }
            return Tile(index: index, x: x, width: min(width, pieceWidth - x),
                        sourceMS: piece.sourceMS(atOffsetMS: index * step))
        }
    }
}
