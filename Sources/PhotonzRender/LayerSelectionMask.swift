import CoreGraphics
import Foundation
import PhotonzCore

extension DocumentRenderer {
    /// The silhouette of a layer's opaque pixels as a canvas-space `CGPath`
    /// (top-left origin, even-odd) — the primitive behind ⌘-clicking a layer to
    /// "load its pixels as a selection" (Photoshop's load-transparency). The
    /// layer is rendered ALONE at full opacity with its soft effects removed
    /// (drop shadow, blur, layer opacity) so the selection hugs the shape itself
    /// rather than its glow, then the pixels with alpha ≥ `alphaThreshold` are
    /// contour-traced. Border and corner radius stay — they're part of the
    /// visible shape. Returns nil when the layer draws nothing opaque.
    public func layerSelectionPath(for id: UUID, in document: PhotonzDocument,
                                   store: ImageStore, alphaThreshold: UInt8 = 128) -> CGPath? {
        guard var layer = document.layer(id: id) else { return nil }
        layer.isVisible = true
        // Soft effects would bleed the selection past the shape (shadow/blur) or
        // empty it (a translucent layer) — strip them to a hard silhouette.
        layer.style.shadow = nil
        layer.style.blurRadius = 0
        layer.style.opacity = 1

        // The footprint the shape can cover: transformed frame corners, clamped
        // to the canvas and snapped to whole pixels so the traced path lines up.
        var bounds = layer.frame
        if !layer.transform.isIdentity {
            let corners = layer.transformedCorners
            if let first = corners.first {
                bounds = corners.dropFirst().reduce(CGRect(origin: first, size: .zero)) {
                    $0.union(CGRect(origin: $1, size: .zero))
                }
            }
        }
        let region = Geometry.clampCrop(bounds, toCanvas: document.canvasSize).integral
        guard region.width >= 1, region.height >= 1 else { return nil }

        var temp = document
        temp.layers = [layer]
        guard let raster = rasterize(region: region, of: temp, store: store) else { return nil }

        let w = raster.width, h = raster.height
        guard w > 0, h > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        let drew = rgba.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress,
                  let ctx = CGContext(data: base, width: w, height: h,
                                      bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            ctx.draw(raster, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drew else { return nil }

        var mask = [Bool](repeating: false, count: w * h)
        for i in 0..<(w * h) where rgba[i * 4 + 3] >= alphaThreshold { mask[i] = true }
        guard let local = ContourTracer.path(fromMask: mask, width: w, height: h) else { return nil }

        // ContourTracer works in bitmap pixels (top-left, matching the region's
        // origin); shift the path into canvas space.
        var shift = CGAffineTransform(translationX: region.minX, y: region.minY)
        return local.copy(using: &shift) ?? local
    }
}
