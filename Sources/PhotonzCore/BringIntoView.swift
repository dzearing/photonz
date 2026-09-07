import CoreGraphics
import Foundation

/// The one move back from out of view.
///
/// `RowOutOfView` gives a cut-off layer a mark and a sentence naming the box
/// that swallowed it, and then leaves the way back to the reader: drag it, or
/// turn off the container's Clip contents, or type a new number into the
/// inspector. Every one of those is several moves, and two of them change
/// something other than the layer you are trying to rescue.
///
/// This is the single move. The layer slides back over the edge it left by and
/// stops there, the shortest distance that puts it inside every box in force.
/// Sliding rather than centring is the whole point: somebody put the layer at
/// that x, and only the axis that failed has any business changing.
extension OutOfView {

    /// The one box a layer has to land inside to be seen: everything cutting
    /// it, overlapped.
    ///
    /// Two clipping boxes that miss each other leave nowhere at all to land.
    /// The nearest one wins there, because that is the box somebody would open
    /// and the one whose name the mark is already saying.
    static func landingBox(under clips: [ClipScope]) -> CGRect? {
        guard var box = clips.first?.rect.standardized else { return nil }
        for scope in clips.dropFirst() {
            let overlap = box.intersection(scope.rect.standardized)
            box = overlap.isNull || overlap.isEmpty ? scope.rect.standardized : overlap
        }
        return box
    }

    /// Where `box` should sit so `clips` stop cutting it off: the same box,
    /// pushed the shortest distance on each axis.
    ///
    /// A layer too big for the box it lives in cannot fit however it is moved,
    /// so it lands on the container's top left corner and shows what it can.
    /// That is what a person dragging it would do too.
    static func landing(for box: CGRect, under clips: [ClipScope]) -> CGPoint? {
        guard let target = landingBox(under: clips) else { return nil }
        let b = box.standardized
        var x = b.minX, y = b.minY
        if x + b.width > target.maxX { x = target.maxX - b.width }
        if x < target.minX { x = target.minX }
        if y + b.height > target.maxY { y = target.maxY - b.height }
        if y < target.minY { y = target.minY }
        return CGPoint(x: x, y: y)
    }
}

extension PhotonzDocument {

    /// The clipping boxes in force on one layer, in the space that layer's own
    /// frame is stored in — the same walk `layerRows` does to decide whether
    /// the row wears the mark, so the offer and the mark can never disagree.
    func clipScopes(around id: UUID) -> [ClipScope] {
        func walk(_ list: [Layer], _ clips: [ClipScope]) -> [ClipScope]? {
            for layer in list {
                if layer.id == id { return clips }
                guard layer.isOpenableGroup else { continue }
                let inner = OutOfView.scopes(inside: layer, box: layer.localBounds, under: clips)
                if let found = walk(layer.children, inner) { return found }
            }
            return nil
        }
        return walk(layers, []) ?? []
    }

    /// Whether this layer's position is its own to change at all — the same
    /// question the inspector's X and Y ask before they let you type into
    /// them.
    ///
    /// A layer in a stack or a grid has no position of its own: the container
    /// works one out on every pass, and a number set behind its back is put
    /// straight back, after shuffling the running order on the way. What is
    /// wrong there is that the container is not big enough for what is inside
    /// it, and that is not a thing to fix by moving one layer. Same for a
    /// locked layer, which is locked precisely so that nothing moves it.
    func canPlace(_ id: UUID) -> Bool {
        guard let layer = layer(id: id) else { return false }
        let container = parentID(of: id).flatMap { self.layer(id: $0) }
        return LayerGeometryEditing(layer: layer, in: container).canMove
    }

    /// Where this layer's box would land if it were brought back into view, in
    /// the space the inspector's X and Y type into. Nil when nothing is
    /// cutting the layer off, which is every layer but the marked ones.
    public func bringIntoViewOrigin(of id: UUID) -> CGPoint? {
        guard let box = layer(id: id)?.localBounds else { return nil }
        let clips = clipScopes(around: id)
        // Only a layer with NOTHING left on screen is offered this, exactly as
        // only such a layer is marked. One hanging half out is a layer you can
        // still see and still grab, and moving it under somebody would be the
        // app tidying up work nobody asked it to touch.
        guard OutOfView.cutter(of: box, under: clips) != nil,
              canPlace(id), let landing = OutOfView.landing(for: box, under: clips),
              landing != box.origin else { return nil }
        return landing
    }

    /// Whether the row for this layer should offer a way back into view.
    public func canBringLayerIntoView(id: UUID) -> Bool {
        bringIntoViewOrigin(of: id) != nil
    }

    /// Slides one layer back inside the boxes cutting it off. False when there
    /// was nothing to do, so a caller can leave the document, and the undo
    /// stack, untouched.
    @discardableResult
    public mutating func bringLayerIntoView(id: UUID) -> Bool {
        guard let landing = bringIntoViewOrigin(of: id) else { return false }
        moveLayer(id: id, toParentOrigin: landing)
        return true
    }
}
