import CoreGraphics
import Foundation
import PhotonzCore

/// Painting a marquee box into a layer's pixels, and sizing the layer to the
/// pixels it ends up with.
///
/// A layer's box is the pixels it actually has. A region delete already works
/// that way — erase a corner and the layer shrinks to what survives
/// (`RegionOps.trimmed`) — and this is the other direction of the same rule:
/// paint that lands outside the box grows it, and a fill on a layer with
/// nothing on it gives it the box of the paint and nothing more.
///
/// Growing is bounded by the picture, since paint that runs off the edge buys
/// a sheet of pixels nobody can see. The box a layer ALREADY has is never
/// clipped: a layer dragged half off screen would otherwise lose the hidden
/// half to a fill somewhere else on it.
public enum RegionFill {

    /// The pixels a fill left behind and the box they occupy, in document
    /// coordinates.
    public struct Result: Sendable {
        public let image: CGImage
        public let frame: CGRect

        public init(image: CGImage, frame: CGRect) {
            self.image = image
            self.frame = frame
        }
    }

    /// `image` with `path`'s interior painted `hex`, and the document-space box
    /// the result occupies.
    ///
    /// `image` is nil for a layer with nothing on it yet, whose `frame` is
    /// empty; `pixelsPerPoint` is the density a first bitmap is made at (the
    /// document's, so paint on a retina capture is as sharp as the capture).
    /// `bounds` is how far the box may grow — the picture.
    ///
    /// Nil when there is nothing to paint: a marquee that misses the picture
    /// entirely, or a fill that leaves no opaque pixel anywhere.
    public static func fill(image: CGImage?, frame: CGRect, path: CGPath,
                            hex: String, pixelsPerPoint: CGFloat,
                            within bounds: CGRect) -> Result? {
        let box = frame.standardized
        // The pixels the layer already has, when it has any: a bitmap AND a
        // box to stretch it over. Either one missing is a layer with nothing
        // on it, and the paint decides the whole answer.
        let existing: (image: CGImage, box: CGRect)? = {
            guard let image, box.width > 0, box.height > 0, image.width > 0, image.height > 0
            else { return nil }
            return (image, box)
        }()
        guard let rgba = RGBA(hex: hex) else { return nil }

        // Everything below is in LAYER PIXELS: the grid the layer's own bitmap
        // sits on, so redrawing it into a bigger sheet never resamples it.
        // A layer with nothing on it has no grid yet, so the paint makes one.
        let paintDoc = path.boundingBoxOfPath.intersection(bounds)
        guard !paintDoc.isNull, paintDoc.width > 0, paintDoc.height > 0 else { return nil }
        let anchor = existing?.box.origin ?? paintDoc.origin
        let sx = existing.map { CGFloat($0.image.width) / $0.box.width } ?? max(pixelsPerPoint, 1)
        let sy = existing.map { CGFloat($0.image.height) / $0.box.height } ?? max(pixelsPerPoint, 1)
        guard sx > 0, sy > 0 else { return nil }
        let docToPixels = CGAffineTransform(scaleX: sx, y: sy)
            .translatedBy(x: -anchor.x, y: -anchor.y)

        let paintPixels = paintDoc.applying(docToPixels).integral
        let existingPixels = existing
            .map { CGRect(x: 0, y: 0, width: $0.image.width, height: $0.image.height) } ?? .null
        let target = existingPixels.union(paintPixels)
        let width = Int(target.width.rounded()), height = Int(target.height.rounded())
        guard width > 0, height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        // The context is bottom-left; the pixel grid above is top-left, the
        // document's convention, so both the old bitmap and the path are
        // flipped through the new sheet's height on the way in.
        if let existing {
            let top = existingPixels.minY - target.minY
            context.draw(existing.image, in: CGRect(x: existingPixels.minX - target.minX,
                                                    y: CGFloat(height) - top - existingPixels.height,
                                                    width: existingPixels.width,
                                                    height: existingPixels.height))
        }
        var toSheet = docToPixels
            .concatenating(CGAffineTransform(translationX: -target.minX, y: -target.minY))
            .concatenating(CGAffineTransform(scaleX: 1, y: -1)
                .translatedBy(x: 0, y: -CGFloat(height)))
        guard let onSheet = path.copy(using: &toSheet) else { return nil }
        context.saveGState()
        context.addPath(onSheet)
        context.setFillColor(CGColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a))
        context.fillPath(using: .evenOdd)
        context.restoreGState()

        guard let painted = context.makeImage(),
              let trimmed = RegionOps.trimmed(painted) else { return nil }
        let pixels = trimmed.rect.offsetBy(dx: target.minX, dy: target.minY)
        let toDocument = docToPixels.inverted()
        return Result(image: trimmed.image, frame: pixels.applying(toDocument))
    }
}
