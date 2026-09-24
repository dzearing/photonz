import Foundation

// A frame held on screen (`docs/design/mocks/pages/video-freeze-wt.html`).
//
// **A freeze is not a special object: it is a clip whose in and out are the
// same frame, so it drops into the timeline like any other.** Everything that
// makes one is already somewhere else — `ClipPiece.held` is the piece,
// `ClipPieces.holdFrame` makes it, `ClipPieces.setHoldLength` sizes it — and
// this file is only the two READINGS that the surfaces on top of it need:
//
// 1. **What is being held at this moment**, so the canvas can say why the
//    picture has stopped moving while the clock carries on.
// 2. **What a layer drawn at this moment should be on screen for**, which is
//    the reason a person holds a frame at all: to point at something on it.
//
// Neither is a new kind of object. The first is a window on to a piece that
// already exists; the second is an ordinary in and out on an ordinary layer.

/// The frame being held at a moment of the document, and everything a surface
/// needs to say about it.
public struct HeldFrame: Hashable, Sendable {

    /// The clip whose piece is doing the holding.
    public let layerID: UUID
    /// Which of that clip's pieces it is.
    public let pieceIndex: Int
    /// When the hold starts, on the DOCUMENT's clock.
    public let inMS: Int
    /// When it is over, on the same clock. Half open, like every other stretch:
    /// the out is the first moment the hold is not on screen.
    public let outMS: Int
    /// The frame of the recording being held, in the recording's own clock.
    ///
    /// The moment the hold was taken AT, not the frame grid that moment is
    /// fetched on: a badge saying 0:03 about a freeze taken at 0:04 is a badge
    /// nobody believes. Which picture gets fetched for it is `MovieRef`'s
    /// business and is a frame's width away at most.
    public let sourceMS: Int

    public init(layerID: UUID, pieceIndex: Int, inMS: Int, outMS: Int, sourceMS: Int) {
        self.layerID = layerID
        self.pieceIndex = pieceIndex
        self.inMS = inMS
        self.outMS = max(outMS, inMS)
        self.sourceMS = max(0, sourceMS)
    }

    /// How long the frame is on screen for.
    public var lengthMS: Int { outMS - inMS }

    /// The stretch of the document it occupies, as a layer would say it. This
    /// is what a mark drawn on the held frame takes for its own.
    public var span: LayerTime { LayerTime(inMS: inMS, outMS: outMS) }

    /// What the canvas says while the picture is standing still: the one line
    /// that tells a stopped picture apart from a stalled one.
    ///
    /// It names the FRAME rather than the moment, because the question somebody
    /// asks looking at it is "which frame am I looking at", and the answer is
    /// the same however far into the hold the playhead has got.
    public var badge: String { "Held frame · \(MotionStripRuler.timecode(Double(sourceMS)))" }

    /// The same sentence the panel says about a held piece, so the canvas and
    /// the panel never say it two ways.
    public var lengthSentence: String {
        "One frame, on screen for \(ClipSpeed.seconds(lengthMS))."
    }
}

extension PhotonzDocument {

    /// What is being held at this moment, or nil where the picture is playing.
    ///
    /// The topmost clip wins, which is the same rule the canvas draws by: with
    /// two clips stacked, the one you are looking at is the one on top.
    public func heldFrame(atTimeMS ms: Int) -> HeldFrame? {
        guard hasTime else { return nil }
        // Visited in order and the LAST hold kept, which is the topmost: the
        // same answer as searching the flattened list backwards, without
        // copying every layer to make it.
        var found: HeldFrame?
        forEachLayer { layer in
            guard let time = layer.time, time.contains(ms: ms),
                  let pieces = layer.clipPieces else { return }
            let offset = ms - time.inMS
            guard let index = pieces.pieceIndex(atMS: offset),
                  let piece = pieces.piece(at: index), piece.isHeld,
                  let range = pieces.rangeMS(ofPiece: index) else { return }
            found = HeldFrame(layerID: layer.id, pieceIndex: index,
                              inMS: time.inMS + range.start, outMS: time.inMS + range.end,
                              sourceMS: piece.sourceInMS)
        }
        return found
    }

    /// A layer drawn on the picture at a moment: `addLayerDrawnOnFrame`, plus
    /// the one thing a document with time adds to it.
    ///
    /// **A mark made on a held frame is on screen for exactly that hold.** That
    /// is the whole reason a frame gets held: there is something standing still
    /// to point at, and an arrow that outlives the frame it was pointing at is
    /// an arrow pointing at the wrong thing. Anywhere else it behaves as it
    /// always has — drawn over a stretch that plays, a mark stays up for the
    /// whole document, and a layer that already occupies time keeps the stretch
    /// it came with.
    public mutating func addLayerDrawn(_ layer: Layer, atTimeMS ms: Int) {
        var drawn = layer
        if drawn.time == nil, let held = heldFrame(atTimeMS: ms) { drawn.time = held.span }
        addLayerDrawnOnFrame(drawn)
    }
}
