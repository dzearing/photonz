import CoreGraphics
import Foundation

/// The stretch of a title its design was written onto as keys: how long it
/// was, and where its own clock started (`LayerTime.sourceInMS`).
///
/// A trim does not write a title's keys again, so after one the keys still
/// say the stretch they were written for. Reading them against that stretch,
/// rather than the one the title has now, is what tells a key somebody
/// dragged from a key a trim simply left where it was.
public struct TitleKeyedSpan: Hashable, Codable, Sendable {
    public var lengthMS: Int
    public var clockMS: Int

    public init(lengthMS: Int, clockMS: Int) {
        self.lengthMS = lengthMS
        self.clockMS = clockMS
    }

    init(_ time: LayerTime) {
        self.init(lengthMS: time.lengthMS, clockMS: time.sourceInMS)
    }
}

/// One of a title part's moves somebody changed by hand (task
/// `a-title-part-move-dragged-by-hand-on-the-timelin`): its bar dragged on
/// the timeline, or its keys moved or retyped.
struct TitleHandMove {
    var pieceID: UUID
    /// The move as the hand left it.
    var motion: LayerMotion
    /// True when only WHEN it happens differs from what the design wrote: the
    /// design's keys are written again (into a new layout, at a new theme's
    /// sizes) and take this timing. False keeps the hand's keys whole.
    var onlyRetimed: Bool
}

extension PhotonzDocument {

    /// Moves somebody changed by hand on a title's parts: any key that is not
    /// what the old design wrote, on a part whose in, hold and out the change
    /// leaves alone. A theme, an energy, an intensity or another part retimed
    /// never undoes them; retiming that part, or changing how it comes in,
    /// says how it moves now.
    func handMoves(layerID: UUID, from old: TitleRecipe, to recipe: TitleRecipe) -> [TitleHandMove] {
        guard let group = layer(id: layerID), let time = group.time else { return [] }
        let span = old.keyedOver ?? TitleKeyedSpan(time)
        let compiled = old.compiled.parts
        var moves: [TitleHandMove] = []
        for (index, part) in old.design.parts.enumerated() where compiled.indices.contains(index) {
            guard recipe.design.parts.first(where: { $0.path == part.path }) == part,
                  let piece = TitleDesign.find(part.path, in: group), let motions = piece.motions else { continue }
            let compiler = TitleCompiler(piece: piece, lengthMS: span.lengthMS, clock: span.clockMS,
                                         unit: titleUnit)
            let written = compiler.motions(for: compiled[index])
            // Words wiped in fade by their own reveal, so a fade keyed on
            // them is the hand's own.
            let revealed = compiler.wordReveal(for: compiled[index]) != nil
            for motion in motions {
                guard let wrote = written.first(where: {
                    $0.property == motion.property && $0.effectOrdinal == motion.effectOrdinal
                }) else {
                    if revealed, motion.property == .opacity {
                        moves.append(TitleHandMove(pieceID: piece.id, motion: motion, onlyRetimed: false))
                    }
                    continue
                }
                guard !motion.movesLike(wrote) else { continue }
                moves.append(TitleHandMove(pieceID: piece.id, motion: motion,
                                           onlyRetimed: motion.movesLike(wrote.retimed(to: motion.timing))))
            }
        }
        return moves
    }

    /// Put the hand's moves back on a title just compiled again.
    mutating func putBack(_ moves: [TitleHandMove]) {
        for move in moves {
            updateLayer(id: move.pieceID) { piece in
                var motions = piece.motions ?? []
                let index = motions.firstIndex {
                    $0.property == move.motion.property && $0.effectOrdinal == move.motion.effectOrdinal
                }
                if move.onlyRetimed {
                    guard let index else { return }
                    motions[index] = motions[index].retimed(to: move.motion.timing)
                } else if let index {
                    motions[index] = move.motion
                } else {
                    motions.append(move.motion)
                }
                piece.motions = motions
            }
        }
    }
}

extension LayerMotion {

    /// Whether this moves exactly as `other` does, whatever either is called:
    /// a design writes its keys afresh, with new ids, every time it compiles.
    func movesLike(_ other: LayerMotion) -> Bool {
        guard property == other.property, timing == other.timing else { return false }
        return Self.withoutID(self) == Self.withoutID(other)
    }

    private static func withoutID(_ motion: LayerMotion) -> NSDictionary? {
        guard let data = try? JSONEncoder().encode(motion),
              var fields = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        fields["id"] = nil
        return fields as NSDictionary
    }
}
