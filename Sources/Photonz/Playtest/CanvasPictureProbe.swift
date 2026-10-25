// What the canvas is showing as the PICTURE, apart from its chrome: the
// composite, the crisp tile over it, and the sprite a drag floats. A walk reads
// it while a drag is under way, to say whether the picture followed the hand on
// every move or sat still until the release (`spaceHandle` with `seconds`).
//
// The selection outline moving says nothing about this: on a layer turned in
// 3D the outline and the picture are drawn by different code, and the user
// found the picture standing still under a turning outline on 2026-10-12.
//
// Probe builds only.
#if PHOTONZ_PLAYTEST
import AppKit
import QuartzCore

extension CanvasNSView {
    /// Everything that decides the picture on screen, as one comparable value.
    /// A new composite landing is a new `contents` object; a floated sprite
    /// turning is a new transform. Two equal keys are the same picture.
    var playtestPictureKey: String {
        func describe(_ layer: CALayer) -> String {
            guard !layer.isHidden, let contents = layer.contents else { return "-" }
            let id = ObjectIdentifier(contents as AnyObject).hashValue
            let t = layer.affineTransform()
            return "\(id)@\(layer.position.x),\(layer.position.y) \(layer.bounds.size.width)x"
                + "\(layer.bounds.size.height) [\(t.a),\(t.b),\(t.c),\(t.d)]"
        }
        return [contentLayer, crispLayer, previewSpriteLayer, previewOverlayLayer].map(describe).joined(separator: " | ")
    }

    /// The picture alone drawn into a bitmap the size of the canvas view, one
    /// pixel to the point: the composite, then the crisp tile, then the sprite,
    /// then what is drawn over the sprite, each where and how Core Animation
    /// places it. Read just before a drag's
    /// release and again once the committed render has landed, the two must
    /// agree, or the picture jumped as the hand let go.
    func playtestPicture() -> CGImage? {
        let size = bounds.size
        guard size.width >= 1, size.height >= 1,
              let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // The view is flipped: put the origin at the top left, y down, the way
        // its layers are laid out.
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        // The brush's live stroke too, at its opacity, so a walk can hold the
        // stroke under the hand against the one that lands (`CanvasBrush`).
        for layer in [contentLayer, crispLayer, previewSpriteLayer, previewOverlayLayer, brushLayer]
        where !layer.isHidden {
            guard let contents = layer.contents else { continue }
            let image: CGImage?
            if CFGetTypeID(contents as CFTypeRef) == CGImage.typeID {
                image = (contents as! CGImage)
            } else if let picture = contents as? NSImage {
                image = picture.cgImage(forProposedRect: nil, context: nil, hints: nil)
            } else {
                image = nil
            }
            guard let image else { continue }
            context.saveGState()
            context.setAlpha(CGFloat(layer.opacity))
            context.translateBy(x: layer.position.x, y: layer.position.y)
            context.concatenate(layer.affineTransform())
            let box = layer.bounds
            let rect = CGRect(x: -box.width * layer.anchorPoint.x, y: -box.height * layer.anchorPoint.y,
                              width: box.width, height: box.height)
            // Contents draw upright in a flipped space: flip about the box.
            context.translateBy(x: 0, y: rect.midY * 2)
            context.scaleBy(x: 1, y: -1)
            context.draw(image, in: rect)
            context.restoreGState()
        }
        return context.makeImage()
    }

    /// The share of pixels that differ by more than a few levels between two
    /// pictures of the same size, 0 to 1.
    static func playtestPictureDifference(_ a: CGImage, _ b: CGImage) -> Double {
        guard a.width == b.width, a.height == b.height,
              let pa = rgba(a), let pb = rgba(b) else { return 1 }
        var differing = 0
        let count = a.width * a.height
        for i in 0..<count {
            let o = i * 4
            if abs(Int(pa[o]) - Int(pb[o])) > 8 || abs(Int(pa[o + 1]) - Int(pb[o + 1])) > 8
                || abs(Int(pa[o + 2]) - Int(pb[o + 2])) > 8 || abs(Int(pa[o + 3]) - Int(pb[o + 3])) > 8 {
                differing += 1
            }
        }
        return Double(differing) / Double(max(count, 1))
    }

    private static func rgba(_ image: CGImage) -> [UInt8]? {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let made = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress, width: image.width, height: image.height,
                                          bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        return made ? bytes : nil
    }
}
#endif
