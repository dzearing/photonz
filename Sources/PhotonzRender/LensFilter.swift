import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics
import Foundation
import PhotonzCore

/// Draws the picture beneath a lens layer through the lens's adjustment.
///
/// The input is the composite so far, in CANVAS space (Core Image's bottom-left
/// origin), and the output is the same space with the adjustment applied. The
/// caller crops it to the lens's box afterwards; this deliberately does not,
/// because blur and pixelate are neighbourhood operations and cutting to the
/// box before filtering is exactly what leaves a dark rim at the edge.
enum LensFilter {

    /// `backdrop` is everything composited below the lens; `box` is the lens's
    /// frame in Core Image coordinates, already stated in output pixels, as is
    /// every length on `lens` (`LensContent.magnified(by:)` does that upstream,
    /// which is why nothing here multiplies by a scale).
    ///
    /// Returns nil when there is nothing to draw.
    static func image(of lens: LensContent, over backdrop: CIImage, box: CGRect) -> CIImage? {
        guard box.width >= 1, box.height >= 1 else { return nil }
        // Sample wider than the box, filter, then cut: a gaussian and a block
        // both read their neighbours, and a picture cut to the box first has
        // no neighbours past its edge to read.
        let reach = max(0, lens.sampleReach)
        let sampled = backdrop.cropped(to: box.insetBy(dx: -reach, dy: -reach))
        guard !sampled.extent.isEmpty else { return nil }
        // Held at its own edge rather than fading into transparency, the way
        // every photo editor blurs a photograph: without this the outermost
        // pixels mix with nothing and the lens wears a dark rim.
        let source = reach > 0 ? sampled.clampedToExtent() : sampled
        return adjusted(source, by: lens).cropped(to: box)
    }

    private static func adjusted(_ image: CIImage, by lens: LensContent) -> CIImage {
        guard !lens.isIdentity else { return image }
        switch lens.adjustment {
        case .blur:
            return image.applyingGaussianBlur(sigma: lens.blurRadius)
        case .pixelate:
            // The grid is anchored to the CANVAS ORIGIN, not to the lens.
            // Anchored to the lens, nudging one a single point would reshuffle
            // every block under it and a dragged lens would boil; anchored to
            // the canvas, the blocks belong to the picture and a lens moved
            // over them simply shows more or fewer of the same ones.
            return image.applyingFilter("CIPixellate", parameters: [
                kCIInputCenterKey: CIVector(x: 0, y: 0),
                kCIInputScaleKey: max(1, lens.blockSize),
            ])
        case .greyscale:
            return image.applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 1 - min(max(lens.greyscaleAmount, 0), 1),
            ])
        case .invert:
            // CIColorInvert leaves alpha alone, so the clear parts of the
            // picture beneath stay clear instead of turning into a white box.
            return image.applyingFilter("CIColorInvert")
        case .brightness:
            return image.applyingFilter("CIColorControls", parameters: [
                kCIInputBrightnessKey: min(max(lens.brightness, -1), 1),
            ])
        }
    }
}
