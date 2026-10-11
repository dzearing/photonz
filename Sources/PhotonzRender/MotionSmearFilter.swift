import CoreGraphics
import CoreImage
import Foundation
import PhotonzCore

// Motion blur, drawn (`MotionSmear.swift` in PhotonzCore works out where).
//
// A part's finished picture, laid down again at each place it was while the
// shutter was open and averaged: the light is the same, spread along the way
// it went. Each copy is the same picture moved, so nothing is drawn again; on
// the GPU it is a handful of reads a pixel over the part's own area. Measured
// before building it on a full 1080p frame: about 0.5ms more at 8 copies,
// 1.7ms at 32 and 4ms at 64, readback included.

public enum MotionSmearFilter {

    /// `image`, a part as drawn on a canvas `canvasHeight` tall in Core
    /// Image's own space (y up), smeared along `smear`.
    public static func smeared(_ image: CIImage, by smear: MotionSmear, canvasHeight: CGFloat) -> CIImage {
        // The smear is stated top-left, as the document is; the picture is
        // y-up. The same move seen through a vertical flip.
        let flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: canvasHeight)
        return averaged(image, over: smear.samples.map { flip.concatenating($0).concatenating(flip) })
    }

    /// The average of `image` moved by each of `transforms`, in its own space.
    /// Nothing to average over, or a picture with no edge, comes back as it was.
    public static func averaged(_ image: CIImage, over transforms: [CGAffineTransform]) -> CIImage {
        guard !transforms.isEmpty, !image.extent.isInfinite, !image.extent.isEmpty else { return image }
        let share = 1 / CGFloat(transforms.count)
        // A colour matrix works on colour with its coverage taken out and put
        // back after, so scaling the coverage alone weighs the whole pixel.
        // Scaling the colour as well weighed it twice: the sum came out the
        // right coverage and a fraction of the light.
        let weighed = image.applyingFilter("CIColorMatrix", parameters: [
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: share),
        ])
        var sum: CIImage?
        for transform in transforms {
            let copy = weighed.transformed(by: transform)
            sum = sum.map {
                copy.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: $0])
            } ?? copy
        }
        return sum ?? image
    }
}
