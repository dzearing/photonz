import CoreGraphics
import Foundation

/// Holding a card that has been TURNED still while one piece inside it
/// changes.
///
/// A turned group swings about the middle of the box its contents make
/// (`Layer.turnPivot`), and that box is measured live from the children. So
/// the moment one piece inside the card grows, or moves, or leaves, the point
/// the whole card swings about slides — and every other piece in the card
/// swings with it, a few points across the screen, with nobody having touched
/// them. On a 20 degree card, widening one label by 20 points walked the bar
/// beside it 4 points down the screen (`turned-piece-walk`, reported
/// 2026-09-20).
///
/// The cure is one number. A group's own frame origin is an anchor rather than
/// a box, and moving it slides the card's finished picture by exactly that
/// much: for a piece stored at `x`, what is drawn is
///
///     M(x - m) + m + O
///
/// where `m` is the middle of the contents in the group's own space, `O` is
/// the group's origin and `M` is the turn. Let the contents' middle move by
/// `d` and the whole picture moves by `(I - M)d`; give the origin `(M - I)d`
/// back and it does not. Every piece nobody touched then draws exactly where
/// it drew before, and the piece under the hand lands where the pointer aimed
/// it, because the pointer was read through the card's turn as it stood at the
/// start of the gesture.
///
/// It is the other half of `PhotonzDocument.uprightPoint`, which takes the
/// card's swing off the POINTER. That one makes a gesture inside a turned card
/// land where the hand is; this one stops the gesture dragging the rest of the
/// card along behind it.
extension PhotonzDocument {

    /// Runs `change`, then puts every turned card above `id` back on the pivot
    /// it was swinging about beforehand.
    ///
    /// Nothing at all happens where nothing above the layer has been turned,
    /// which is every document that has never used the knob on a group.
    public mutating func holdingTurnedPivots(above id: UUID,
                                             _ change: (inout PhotonzDocument) -> Void) {
        holdingTurnedPivots(above: [id], change)
    }

    /// The same, for a change that touches several pieces at once — a whole
    /// selection dragged inside one card, say. Every turned card above any of
    /// them is held.
    public mutating func holdingTurnedPivots(above ids: [UUID],
                                             _ change: (inout PhotonzDocument) -> Void) {
        let held = turnedContainersAbove(ids)
        change(&self)
        // Deepest first: settling an inner card moves its own origin, which is
        // part of what the card outside it measures its contents by.
        for card in held.sorted(by: { $0.depth > $1.depth }) {
            // A card with nothing left in it has no contents box to hold, and
            // its pivot has fallen back to its anchor: giving it the whole of
            // that would throw an empty card across the canvas.
            guard let layer = layer(id: card.id), !layer.transform.isIdentity,
                  let group = layer.group, !group.children.isEmpty
            else { continue }
            let now = Self.contentsPivot(of: layer)
            let drift = CGPoint(x: now.x - card.pivot.x, y: now.y - card.pivot.y)
            guard drift != .zero else { continue }
            let swung = drift.applying(layer.transform.affineTransform(around: .zero))
            let give = CGPoint(x: swung.x - drift.x, y: swung.y - drift.y)
            guard give != .zero else { continue }
            updateLayer(id: card.id) { $0.frame = $0.frame.offsetBy(dx: give.x, dy: give.y) }
        }
    }

    /// Where a group is swinging about, stated in the space its CHILDREN are
    /// stored in rather than in its parent's, so the reading does not move
    /// when the group's own anchor does. That is what makes it comparable
    /// across the very change this file exists to undo.
    static func contentsPivot(of layer: Layer) -> CGPoint {
        let pivot = layer.turnPivot
        return CGPoint(x: pivot.x - layer.frame.origin.x, y: pivot.y - layer.frame.origin.y)
    }

    /// Every turned group holding any of `ids`, with how deep it sits and what
    /// it is swinging about right now.
    private func turnedContainersAbove(_ ids: [UUID]) -> [(id: UUID, depth: Int, pivot: CGPoint)] {
        var seen: Set<UUID> = []
        var found: [(id: UUID, depth: Int, pivot: CGPoint)] = []
        for id in ids {
            guard let path = path(of: id), path.count > 1 else { continue }
            var list = layers
            for (depth, index) in path.dropLast().enumerated() {
                guard list.indices.contains(index) else { break }
                let container = list[index]
                if !container.transform.isIdentity, seen.insert(container.id).inserted {
                    found.append((container.id, depth, Self.contentsPivot(of: container)))
                }
                list = container.children
            }
        }
        return found
    }
}
