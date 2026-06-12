import CoreGraphics
import Foundation

/// Aspect-ratio locks offered by the crop tool.
public enum CropAspect: String, CaseIterable, Hashable, Codable, Sendable {
    case free
    case square
    case fourThree
    case sixteenNine

    /// Width ÷ height, nil when unconstrained.
    public var ratio: CGFloat? {
        switch self {
        case .free: nil
        case .square: 1
        case .fourThree: 4.0 / 3.0
        case .sixteenNine: 16.0 / 9.0
        }
    }

    public var label: String {
        switch self {
        case .free: "Free"
        case .square: "1:1"
        case .fourThree: "4:3"
        case .sixteenNine: "16:9"
        }
    }
}

/// Crop-mode geometry: the crop rect always honors the aspect lock and never
/// leaves the canvas. Views feed pointer positions; every decision lives here.
public enum Crop {

    /// The largest rect with `aspect`'s ratio that fits inside `rect`, centered.
    public static func fitted(_ rect: CGRect, to aspect: CropAspect) -> CGRect {
        guard let ratio = aspect.ratio, rect.width > 0, rect.height > 0 else { return rect }
        var size = CGSize(width: rect.width, height: rect.width / ratio)
        if size.height > rect.height {
            size = CGSize(width: rect.height * ratio, height: rect.height)
        }
        return CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    /// The crop rect after dragging `handle` to `p`. The opposite corner/edge
    /// stays anchored, the aspect lock holds (dominant axis wins on corners,
    /// edges scale the cross axis around its center), and the result never
    /// inverts or leaves `bounds` (the canvas, or a layer's frame for
    /// per-layer crops).
    public static func resize(_ rect: CGRect, dragging handle: ResizeHandle, to p: CGPoint,
                              aspect: CropAspect, bounds: CGRect, minSize: CGFloat = 1) -> CGRect {
        let p = CGPoint(x: min(max(bounds.minX, p.x), bounds.maxX),
                        y: min(max(bounds.minY, p.y), bounds.maxY))
        guard let ratio = aspect.ratio else {
            return Handles.resize(rect, dragging: handle, to: p, preserveAspect: false, minSize: minSize)
        }

        if handle.isCorner {
            let anchor = CGPoint(x: handle.movesMinX ? rect.maxX : rect.minX,
                                 y: handle.movesMinY ? rect.maxY : rect.minY)
            let sx: CGFloat = handle.movesMinX ? -1 : 1
            let sy: CGFloat = handle.movesMinY ? -1 : 1
            let dw = max((p.x - anchor.x) * sx, minSize)
            let dh = max((p.y - anchor.y) * sy, minSize)
            var w = max(dw, dh * ratio)
            let availX = sx > 0 ? bounds.maxX - anchor.x : anchor.x - bounds.minX
            let availY = sy > 0 ? bounds.maxY - anchor.y : anchor.y - bounds.minY
            w = min(w, availX, availY * ratio)
            let h = w / ratio
            return CGRect(x: sx > 0 ? anchor.x : anchor.x - w,
                          y: sy > 0 ? anchor.y : anchor.y - h,
                          width: w, height: h)
        }

        if handle.movesMinX || handle.movesMaxX {
            // Width from the pointer; height follows, centered vertically.
            let anchorX = handle.movesMinX ? rect.maxX : rect.minX
            let sx: CGFloat = handle.movesMinX ? -1 : 1
            let availX = sx > 0 ? bounds.maxX - anchorX : anchorX - bounds.minX
            let maxH = 2 * min(rect.midY - bounds.minY, bounds.maxY - rect.midY)
            var w = max((p.x - anchorX) * sx, minSize)
            w = min(w, availX, maxH * ratio)
            let h = w / ratio
            return CGRect(x: sx > 0 ? anchorX : anchorX - w, y: rect.midY - h / 2,
                          width: w, height: h)
        } else {
            // Height from the pointer; width follows, centered horizontally.
            let anchorY = handle.movesMinY ? rect.maxY : rect.minY
            let sy: CGFloat = handle.movesMinY ? -1 : 1
            let availY = sy > 0 ? bounds.maxY - anchorY : anchorY - bounds.minY
            let maxW = 2 * min(rect.midX - bounds.minX, bounds.maxX - rect.midX)
            var h = max((p.y - anchorY) * sy, minSize)
            h = min(h, availY, maxW / ratio)
            let w = h * ratio
            return CGRect(x: rect.midX - w / 2, y: sy > 0 ? anchorY : anchorY - h,
                          width: w, height: h)
        }
    }

    public static func resize(_ rect: CGRect, dragging handle: ResizeHandle, to p: CGPoint,
                              aspect: CropAspect, canvas: CGSize, minSize: CGFloat = 1) -> CGRect {
        resize(rect, dragging: handle, to: p, aspect: aspect,
               bounds: CGRect(origin: .zero, size: canvas), minSize: minSize)
    }

    /// The crop rect translated by `delta`, clamped inside `bounds`.
    public static func moved(_ rect: CGRect, by delta: CGPoint, in bounds: CGRect) -> CGRect {
        var r = rect
        r.origin.x = min(max(bounds.minX, rect.origin.x + delta.x),
                         max(bounds.minX, bounds.maxX - rect.width))
        r.origin.y = min(max(bounds.minY, rect.origin.y + delta.y),
                         max(bounds.minY, bounds.maxY - rect.height))
        return r
    }

    public static func moved(_ rect: CGRect, by delta: CGPoint, in canvas: CGSize) -> CGRect {
        moved(rect, by: delta, in: CGRect(origin: .zero, size: canvas))
    }

    /// A fresh crop rect drawn from `anchor` toward `current` — standardized,
    /// ratio-locked along the dominant axis, clamped to `bounds`. Nil while
    /// the drag is still empty.
    public static func dragRect(anchor: CGPoint, current: CGPoint,
                                aspect: CropAspect, bounds: CGRect) -> CGRect? {
        let c = CGPoint(x: min(max(bounds.minX, current.x), bounds.maxX),
                        y: min(max(bounds.minY, current.y), bounds.maxY))
        guard let ratio = aspect.ratio else {
            let rect = CGRect(x: anchor.x, y: anchor.y,
                              width: c.x - anchor.x, height: c.y - anchor.y).standardized
            let clamped = rect.intersection(bounds)
            return clamped.isNull || clamped.isEmpty ? nil : clamped
        }
        let dx = c.x - anchor.x
        let dy = c.y - anchor.y
        guard dx != 0 || dy != 0 else { return nil }
        let sx: CGFloat = dx < 0 ? -1 : 1
        let sy: CGFloat = dy < 0 ? -1 : 1
        var w = max(abs(dx), abs(dy) * ratio)
        let availX = sx > 0 ? bounds.maxX - anchor.x : anchor.x - bounds.minX
        let availY = sy > 0 ? bounds.maxY - anchor.y : anchor.y - bounds.minY
        w = min(w, availX, availY * ratio)
        let h = w / ratio
        guard w > 0, h > 0 else { return nil }
        return CGRect(x: sx > 0 ? anchor.x : anchor.x - w,
                      y: sy > 0 ? anchor.y : anchor.y - h,
                      width: w, height: h)
    }

    public static func dragRect(anchor: CGPoint, current: CGPoint,
                                aspect: CropAspect, canvas: CGSize) -> CGRect? {
        dragRect(anchor: anchor, current: current, aspect: aspect,
                 bounds: CGRect(origin: .zero, size: canvas))
    }

    /// The four rule-of-thirds segments inside `rect` (two vertical, two
    /// horizontal), for the crop overlay grid.
    public static func thirdsLines(in rect: CGRect) -> [(from: CGPoint, to: CGPoint)] {
        let x1 = rect.minX + rect.width / 3
        let x2 = rect.minX + rect.width * 2 / 3
        let y1 = rect.minY + rect.height / 3
        let y2 = rect.minY + rect.height * 2 / 3
        return [(CGPoint(x: x1, y: rect.minY), CGPoint(x: x1, y: rect.maxY)),
                (CGPoint(x: x2, y: rect.minY), CGPoint(x: x2, y: rect.maxY)),
                (CGPoint(x: rect.minX, y: y1), CGPoint(x: rect.maxX, y: y1)),
                (CGPoint(x: rect.minX, y: y2), CGPoint(x: rect.maxX, y: y2))]
    }
}

extension Layer {
    /// Per-layer crop only applies to image layers: their content is fixed
    /// pixels. Text/annotation content re-rasterizes at the frame size, so a
    /// stored crop would chase its own tail.
    public var supportsContentCrop: Bool {
        if case .image = content { return true }
        return false
    }

    /// Crops the layer to `subRect` (canvas coordinates, clipped to the
    /// frame): the kept pixels stay exactly where they were on canvas. The
    /// sub-rect is mapped through the frame→content scale into the `crop`
    /// rect (composing with any existing crop) and the frame shrinks to it.
    public mutating func cropContent(to subRect: CGRect) {
        guard supportsContentCrop, frame.width > 0, frame.height > 0 else { return }
        let contentSize: CGSize
        if case .image(let ref) = content {
            contentSize = ref.pixelSize
        } else {
            return
        }
        let clipped = subRect.standardized.intersection(frame)
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { return }
        let existing = crop ?? CGRect(origin: .zero, size: contentSize)
        let sx = existing.width / frame.width
        let sy = existing.height / frame.height
        crop = CGRect(x: existing.minX + (clipped.minX - frame.minX) * sx,
                      y: existing.minY + (clipped.minY - frame.minY) * sy,
                      width: clipped.width * sx, height: clipped.height * sy)
        frame = clipped
    }
}
