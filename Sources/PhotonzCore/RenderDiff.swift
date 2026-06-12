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

    /// The region to redraw going from `old` to `new`, clamped to the new
    /// canvas. Layers are matched by id; changed, added, removed, and
    /// reordered layers contribute their visual bounds from both snapshots.
    /// Zoom callouts re-render whenever the dirty region touches what they
    /// magnify, propagated to a fixed point (callouts can magnify callouts).
    public static func dirtyRegion(from old: PhotonzDocument, to new: PhotonzDocument) -> RenderDirty {
        if old == new { return .none }
        guard old.canvasSize == new.canvasSize else { return .full }

        let oldByID = Dictionary(uniqueKeysWithValues: old.layers.map { ($0.id, $0) })
        let newByID = Dictionary(uniqueKeysWithValues: new.layers.map { ($0.id, $0) })
        let oldIndex = Dictionary(uniqueKeysWithValues: old.layers.enumerated().map { ($1.id, $0) })
        let newIndex = Dictionary(uniqueKeysWithValues: new.layers.enumerated().map { ($1.id, $0) })

        var dirty = CGRect.null
        func mark(_ layer: Layer) {
            // Layers invisible in a snapshot draw nothing there; their bounds
            // only matter on the side where they are (or become) visible.
            guard layer.isVisible else { return }
            dirty = dirty.union(visualBounds(of: layer))
        }

        for layer in old.layers {
            guard let counterpart = newByID[layer.id] else { mark(layer); continue }
            if layer != counterpart || oldIndex[layer.id] != newIndex[layer.id] {
                mark(layer)
                mark(counterpart)
            }
        }
        for layer in new.layers where oldByID[layer.id] == nil {
            mark(layer)
        }

        guard !dirty.isNull else {
            // Documents differ but no layer accounts for it — stay safe.
            return .full
        }

        // Callouts mirror the canvas beneath their source: if the dirty
        // region touches a source, the callout's box (and chrome) re-renders,
        // which can in turn feed another callout.
        var changed = true
        var iterations = 0
        while changed, iterations <= new.layers.count {
            changed = false
            iterations += 1
            for layer in new.layers where layer.isVisible {
                guard case .zoomCallout(let callout) = layer.content else { continue }
                let bounds = visualBounds(of: layer)
                if dirty.intersects(callout.sourceRect.standardized), !dirty.contains(bounds) {
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
