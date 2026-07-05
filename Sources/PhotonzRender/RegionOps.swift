import CoreGraphics
import Foundation
import PhotonzCore

/// Bakes selection-region operations into bitmaps. Paths arrive in image
/// pixel coordinates (top-left origin, the document convention) and select
/// their interior by the even-odd rule — exactly what `SelectionRegion`
/// holds. These are destructive pixel edits; undoability comes from the
/// caller registering the result as a NEW bitmap in one History step.
public enum RegionOps {

    /// `image` with the path's interior painted `hex` (over the existing
    /// pixels, full coverage).
    public static func filled(_ image: CGImage, path: CGPath, hex: String) -> CGImage? {
        guard let rgba = RGBA(hex: hex) else { return nil }
        return redraw(image) { context, height in
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: height))
            context.saveGState()
            addTopLeftPath(path, to: context, height: height)
            context.setFillColor(CGColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a))
            context.fillPath(using: .evenOdd)
            context.restoreGState()
        }
    }

    /// `image` with the path's interior cleared to transparent.
    public static func erased(_ image: CGImage, path: CGPath) -> CGImage? {
        redraw(image) { context, height in
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: height))
            context.saveGState()
            addTopLeftPath(path, to: context, height: height)
            context.clip(using: .evenOdd)
            context.clear(CGRect(x: 0, y: 0, width: image.width, height: height))
            context.restoreGState()
        }
    }

    /// The path's bounding box cropped from `image`, with everything outside
    /// the path transparent — the "copy the region" primitive. `nil` when the
    /// path doesn't overlap the image.
    public static func extracted(_ image: CGImage, path: CGPath) -> CGImage? {
        let bounds = path.boundingBoxOfPath.integral
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !bounds.isNull, bounds.width >= 1, bounds.height >= 1 else { return nil }
        let w = Int(bounds.width), h = Int(bounds.height)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: w, height: h,
                                      bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // Shift image space so the bounds origin lands at the context origin,
        // then clip to the path and draw the source.
        var shift = CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY)
        let shifted = path.copy(using: &shift) ?? path
        addTopLeftPath(shifted, to: context, height: h)
        context.clip(using: .evenOdd)
        context.draw(image, in: CGRect(x: -bounds.minX, y: -(CGFloat(image.height) - bounds.maxY),
                                       width: CGFloat(image.width), height: CGFloat(image.height)))
        return context.makeImage()
    }

    /// `base` with `overlay` composited over it (source-over) at `rect` —
    /// top-left image coordinates. The "drop the moved region content back
    /// into the layer" primitive.
    public static func stamped(_ base: CGImage, overlay: CGImage, at rect: CGRect) -> CGImage? {
        redraw(base) { context, height in
            context.draw(base, in: CGRect(x: 0, y: 0, width: base.width, height: height))
            let flipped = CGRect(x: rect.minX, y: CGFloat(height) - rect.maxY,
                                 width: rect.width, height: rect.height)
            context.draw(overlay, in: flipped)
        }
    }

    /// The tight bounding box of the image's non-transparent pixels, cropped
    /// — how a layer "slices down" after a region delete (Photoshop-style
    /// derived bounds). `rect` is in image pixel coordinates (top-left).
    /// `nil` when every pixel is fully transparent.
    public static func trimmed(_ image: CGImage) -> (image: CGImage, rect: CGRect)? {
        let w = image.width, h = image.height
        guard w > 0, h > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        let drew = rgba.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress,
                  let cg = CGContext(data: base, width: w, height: h,
                                     bitsPerComponent: 8, bytesPerRow: w * 4,
                                     space: space,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            cg.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drew else { return nil }
        var minX = w, minY = h, maxX = -1, maxY = -1
        rgba.withUnsafeBufferPointer { px in
            for y in 0..<h {
                let row = y * w
                for x in 0..<w where px[(row + x) * 4 + 3] > 0 {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        let rect = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        if rect == CGRect(x: 0, y: 0, width: w, height: h) { return (image, rect) }
        // CGImage.cropping addresses pixels from the first row — top-left,
        // same as our rect.
        guard let cropped = image.cropping(to: rect) else { return nil }
        return (cropped, rect)
    }

    /// Runs `draw` in a fresh RGBA8 context matching `image`'s size and
    /// returns the result.
    private static func redraw(_ image: CGImage,
                               _ draw: (CGContext, Int) -> Void) -> CGImage? {
        let w = image.width, h = image.height
        guard w > 0, h > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: w, height: h,
                                      bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        draw(context, h)
        return context.makeImage()
    }

    /// Adds a top-left-coordinate path to a (bottom-left) CGContext by
    /// flipping it through the image height.
    private static func addTopLeftPath(_ path: CGPath, to context: CGContext, height: Int) {
        var flip = CGAffineTransform(scaleX: 1, y: -1)
            .translatedBy(x: 0, y: -CGFloat(height))
        context.addPath(path.copy(using: &flip) ?? path)
    }
}
