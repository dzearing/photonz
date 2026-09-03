import CoreGraphics
import Foundation

/// What a renderer must redraw going from one document snapshot to the next.
public enum RenderDirty: Hashable, Sendable {
    /// Nothing changed.
    case none
    /// Re-render everything (canvas resized, or the change is unbounded).
    case full
    /// Re-render this canvas region; pixels outside it are unchanged.
    case rect(CGRect)
}

/// Pure dirty-region math for incremental re-rendering. Conservative by
/// design: regions may be larger than strictly necessary, never smaller.
public enum RenderDiff {

    /// The canvas region a layer can touch when rendered: its frame under the
    /// geometric transform, padded for blur/shadow/border, plus zoom-callout
    /// chrome (source outline and leader lines span source to box).
    public static func visualBounds(of layer: Layer) -> CGRect {
        if layer.isGroup {
            // A group's stored frame is only an anchor — its size is unused —
            // so the region it can touch comes from what it holds, already
            // grown by every style reach inside it. Callouts anywhere in the
            // tree also mirror the canvas they magnify.
            var bounds = layer.renderBounds
            for inner in layer.selfAndDescendants {
                if case .zoomCallout(let callout) = inner.content {
                    bounds = bounds.union(callout.sourceRect.standardized)
                }
            }
            let padding = layer.style.borderWidth + 2
            return bounds.insetBy(dx: -padding, dy: -padding)
        }
        var bounds = layer.frame
        if !layer.transform.isIdentity {
            let center = CGPoint(x: layer.frame.midX, y: layer.frame.midY)
            bounds = layer.frame.applying(layer.transform.affineTransform(around: center))
        }
        if case .zoomCallout(let callout) = layer.content {
            bounds = bounds.union(callout.sourceRect.standardized)
        }
        // +2 absorbs pixel alignment and antialiased edges.
        let padding = layer.style.previewPadding + layer.style.borderWidth + 2
        return bounds.insetBy(dx: -padding, dy: -padding)
    }

    /// Marks what changed between two versions of one stack of layers, which
    /// sits at `origin` on the canvas (`.zero` for the document's own stack,
    /// the group's canvas origin for a group's children). Layers are matched by
    /// id; changed, added, removed, and reordered layers contribute their
    /// visual bounds from both snapshots.
    private static func markChanges(from old: [Layer], to new: [Layer], origin: CGPoint,
                                    into dirty: inout CGRect) {
        let oldByID = Dictionary(uniqueKeysWithValues: old.map { ($0.id, $0) })
        let newByID = Dictionary(uniqueKeysWithValues: new.map { ($0.id, $0) })
        let oldIndex = Dictionary(uniqueKeysWithValues: old.enumerated().map { ($1.id, $0) })
        let newIndex = Dictionary(uniqueKeysWithValues: new.enumerated().map { ($1.id, $0) })

        func mark(_ layer: Layer) {
            // Layers invisible in a snapshot draw nothing there; their bounds
            // only matter on the side where they are (or become) visible.
            guard layer.isVisible else { return }
            dirty = dirty.union(visualBounds(of: layer).offsetBy(dx: origin.x, dy: origin.y))
        }

        for layer in old {
            guard let counterpart = newByID[layer.id] else { mark(layer); continue }
            guard layer != counterpart || oldIndex[layer.id] != newIndex[layer.id] else { continue }
            // A group that only changed INSIDE, and that draws its children
            // straight onto the canvas, repaints just the part that moved —
            // dragging one layer inside a group must not repaint the group.
            // A styled group is one object, so it repaints whole.
            if layer.isGroup, counterpart.isGroup,
               layer.style.isPlain, counterpart.style.isPlain,
               layer.isVisible, counterpart.isVisible,
               layer.frame.origin == counterpart.frame.origin,
               oldIndex[layer.id] == newIndex[layer.id] {
                markChanges(from: layer.children, to: counterpart.children,
                            origin: CGPoint(x: origin.x + layer.frame.origin.x,
                                            y: origin.y + layer.frame.origin.y),
                            into: &dirty)
                continue
            }
            mark(layer)
            mark(counterpart)
        }
        for layer in new where oldByID[layer.id] == nil {
            mark(layer)
        }
    }

    /// The region to redraw going from `old` to `new`, clamped to the new
    /// canvas. Layers are matched by id; changed, added, removed, and
    /// reordered layers contribute their visual bounds from both snapshots.
    /// Zoom callouts re-render whenever the dirty region touches what they
    /// magnify, propagated to a fixed point (callouts can magnify callouts).
    public static func dirtyRegion(from old: PhotonzDocument, to new: PhotonzDocument) -> RenderDirty {
        if old == new { return .none }
        guard old.canvasSize == new.canvasSize else { return .full }

        var dirty = CGRect.null
        markChanges(from: old.layers, to: new.layers, origin: .zero, into: &dirty)

        guard !dirty.isNull else {
            // Documents differ but no layer accounts for it — stay safe.
            return .full
        }

        // Callouts mirror the canvas beneath their source: if the dirty
        // region touches a source, the callout's box (and chrome) re-renders,
        // which can in turn feed another callout.
        // Callouts inside a group mirror the canvas the same way, so read the
        // leaves: for a document without groups this is the layer stack itself.
        let callouts = new.flattenedLayers.filter { $0.isVisible && $0.magnifiedSource != nil }
        var changed = true
        var iterations = 0
        while changed, iterations <= callouts.count {
            changed = false
            iterations += 1
            for layer in callouts {
                guard let source = layer.magnifiedSource else { continue }
                let bounds = visualBounds(of: layer)
                if dirty.intersects(source), !dirty.contains(bounds) {
                    dirty = dirty.union(bounds)
                    changed = true
                }
            }
        }

        let canvas = CGRect(origin: .zero, size: new.canvasSize)
        let clamped = dirty.intersection(canvas)
        guard !clamped.isNull, clamped.width >= 1, clamped.height >= 1 else {
            // Every change is off-canvas; nothing visible moved.
            return .none
        }
        return .rect(Geometry.pixelAligned(clamped).intersection(canvas))
    }
}
