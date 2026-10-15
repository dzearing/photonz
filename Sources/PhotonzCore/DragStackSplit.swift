import Foundation

// **A dragged layer stays where it sits in the stack.**
//
// While a layer is dragged the canvas floats a picture of it over a picture of
// everything else, so each move is only Core Animation moving a picture. With
// "everything else" drawn as one picture under the sprite, a layer that sits
// under another came out on top for the whole of the move and dropped back
// under on the release. The fix is a third picture: what is drawn OVER the
// layer, floated over the sprite. Painting straight over is the same whether
// it is done in one pass or in three, so the sandwich is the document exactly,
// as long as nothing over the layer mixes with or reads what is under it.

/// The document cut in two at a dragged layer: what is drawn under it and what
/// is drawn over it, each with the layer itself left out.
public struct DragStackSplit: Sendable {
    /// Everything drawn under the layer, the layer and everything over it hidden.
    public var below: PhotonzDocument
    /// Everything drawn over the layer and nothing else, on a clear canvas the
    /// same size. Nil when nothing visible is drawn over it, which is the
    /// common case of moving the top layer.
    public var above: PhotonzDocument?
    /// The top level layers `above` draws, so a caller that builds its own
    /// picture of what is under (a region lifted out of a picture) can leave
    /// them out of it too.
    public var over: [UUID] = []
}

extension PhotonzDocument {

    /// The stack cut in two at `id`, for a drag preview. Nil when it cannot be
    /// cut faithfully, and the canvas then draws the document again on every
    /// move instead: something over the layer mixes with what is under it (a
    /// blend mode, a lens, glass), the document is seen in space, or the layer
    /// is a piece inside a group with something drawn over it.
    public func dragStackSplit(at id: UUID) -> DragStackSplit? {
        guard let path = path(of: id), let top = path.first else { return nil }
        var below = self
        below.updateLayer(id: id) { $0.isVisible = false }

        if path.count > 1 {
            // A piece inside a group: its group's own look (its opacity, its
            // clip) sits between it and anything over it, so only a piece with
            // nothing at all drawn over it keeps the two-picture arrangement.
            guard !isSeenInSpace, !hasAnythingDrawnOver(path) else { return nil }
            return DragStackSplit(below: below, above: nil)
        }

        let order = Self.drawingIndices(of: layers)
        guard let slot = order.firstIndex(of: top) else { return nil }
        let over = order[(slot + 1)...].filter { layers[$0].isVisible }
        guard !over.isEmpty else { return DragStackSplit(below: below, above: nil) }
        guard !isSeenInSpace, over.allSatisfy({ Self.paintsStraightOver(layers[$0]) }) else { return nil }

        var above = self
        for index in order[...slot] { above.layers[index].isVisible = false }
        for index in over { below.layers[index].isVisible = false }
        return DragStackSplit(below: below, above: above, over: over.map { layers[$0].id })
    }

    /// Whether anything visible is drawn over the layer at `path`, at any
    /// level of the groups holding it.
    private func hasAnythingDrawnOver(_ path: [Int]) -> Bool {
        let order = Self.drawingIndices(of: layers)
        if let slot = order.firstIndex(of: path[0]),
           order[(slot + 1)...].contains(where: { layers[$0].isVisible }) {
            return true
        }
        for depth in 1..<path.count {
            guard let parent = layer(atPath: Array(path[..<depth])) else { return true }
            if parent.children[(path[depth] + 1)...].contains(where: \.isVisible) { return true }
        }
        return false
    }

    /// Whether `layer` and everything inside it paint straight over whatever
    /// is under them, so drawing them on their own and laying that picture
    /// over the rest gives the same picture as drawing them in place.
    static func paintsStraightOver(_ layer: Layer) -> Bool {
        guard layer.isVisible else { return true }
        guard layer.effectiveBlendMode == .normal, !layer.readsBackdrop else { return false }
        return layer.children.allSatisfy(paintsStraightOver)
    }
}
