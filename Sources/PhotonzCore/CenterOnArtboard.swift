import CoreGraphics
import Foundation

/// Center on the Artboard: what is picked moves, as one piece, until its
/// middle is the middle of the frame it sits on (`icon-draw-wt.html`,
/// `#layerMenu`).
///
/// A glyph that is a few points off centre on its 24 unit board is the one in
/// a row of icons that looks wrong without anybody being able to say why, so
/// putting it in the middle is arithmetic rather than aim.
///
/// Which middle: the same one Mirror Across Center reflects about, the nearest
/// frame ABOVE the layer (a frame picked on its own centres on the canvas,
/// never on itself), and the canvas for a layer on no frame at all.
///
/// Several picked layers move TOGETHER, by one shared step, so a drawing made
/// of four shapes lands in the middle as a drawing rather than as four shapes
/// stacked on one point. Picks that sit on different frames each centre on
/// their own.
public enum CenterOnArtboard {
    /// The command's name in every menu that offers it, in the menu bar's
    /// Title Case of the mock's "Center on the artboard".
    public static let title = "Center on the Artboard"
}

extension PhotonzDocument {

    /// The box a layer is centred in, in canvas coordinates: the nearest frame
    /// above it, or the canvas.
    public func artboardBox(of id: UUID) -> CGRect? {
        guard layer(id: id) != nil else { return nil }
        if let board = artboard(of: id), let box = canvasFrame(of: board) {
            return box.standardized
        }
        return CGRect(origin: .zero, size: canvasSize)
    }

    /// The frame a layer is centred on, nil for the canvas.
    private func artboard(of id: UUID) -> UUID? {
        parentID(of: id).flatMap { frameID(containing: $0) }
    }

    /// The step each picked layer would move, keyed by layer. Layers that
    /// share a frame share one step; a layer already in the middle, locked,
    /// inside a copy of a component, or carried by another picked layer is
    /// not in it.
    func centerOnArtboardMoves(ids: Set<UUID>) -> [UUID: CGPoint] {
        let usable = ids.filter { id in
            guard let layer = layer(id: id), !layer.isLocked, path(of: id) != nil else { return false }
            if let parent = parentID(of: id), isInsideCopy(parent) { return false }
            return true
        }
        let targets = usable.filter { id in !usable.contains { $0 != id && isDescendant(id, of: $0) } }

        // One piece per frame: everything picked on it, by the box you see.
        var pieces: [UUID?: (board: CGRect, bounds: CGRect, ids: [UUID])] = [:]
        for id in targets {
            guard let board = artboardBox(of: id), let box = canvasContentBounds(of: id) else { continue }
            let key = artboard(of: id)
            if let piece = pieces[key] {
                pieces[key] = (board, piece.bounds.union(box), piece.ids + [id])
            } else {
                pieces[key] = (board, box, [id])
            }
        }
        var moves: [UUID: CGPoint] = [:]
        for piece in pieces.values {
            let board = piece.board
            let step = CGPoint(x: board.midX - piece.bounds.midX, y: board.midY - piece.bounds.midY)
            // Already there, to well under a pixel at any zoom anybody uses.
            guard abs(step.x) > 1e-6 || abs(step.y) > 1e-6 else { continue }
            for id in piece.ids { moves[id] = step }
        }
        return moves
    }

    /// Whether Center on the Artboard would move anything.
    public func canCenterOnArtboard(ids: Set<UUID>) -> Bool {
        !centerOnArtboardMoves(ids: ids).isEmpty
    }

    /// Moves the picked layers onto the middle of their frame, in one mutation
    /// so it is one undo step. False when nothing moved.
    @discardableResult
    public mutating func centerOnArtboard(ids: Set<UUID>) -> Bool {
        let moves = centerOnArtboardMoves(ids: ids)
        guard !moves.isEmpty else { return false }
        for (id, step) in moves {
            updateLayer(id: id) { $0.frame = $0.frame.offsetBy(dx: step.x, dy: step.y) }
        }
        return true
    }
}
