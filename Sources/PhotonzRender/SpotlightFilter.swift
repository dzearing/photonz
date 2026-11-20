import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics
import Foundation
import PhotonzCore

/// Draws a spotlight: the picture beneath it, dimmed and softened everywhere
/// EXCEPT the lit area, ready to be laid over the composite so far.
///
/// Every other lens draws the inside of its box. A spotlight draws the
/// outside, so what this hands back covers the whole canvas and is see-through
/// over the area: laid over the picture it leaves the area exactly as it was.
///
/// Everything here is in Core Image's bottom-left space, in output pixels, the
/// same as `LensFilter`; the caller states the area's outline in that space.
enum SpotlightFilter {

    /// `backdrop` is the composite below the spotlight; `canvas` the region to
    /// cover (the canvas, or a group's buffer). `area(outset)` is the lit area
    /// as white on clear, grown by `outset` output pixels; nought is the area
    /// itself, with a hard edge. `opacity` is the layer's own, so a spotlight
    /// faded to half is half as strong. `linearLight` says which space the
    /// renderer mixes in, so the dim means the same thing in both.
    ///
    /// Nil when there is nothing to draw: both numbers at nought, no opacity,
    /// or no canvas.
    static func veil(of lens: LensContent, over backdrop: CIImage, canvas: CGRect,
                     opacity: CGFloat, linearLight: Bool,
                     area: (CGFloat) -> CIImage?) -> CIImage? {
        guard !lens.isIdentity, opacity > 0, canvas.width >= 1, canvas.height >= 1,
              let hard = area(0) else { return nil }
        let changed = changedPicture(backdrop.cropped(to: canvas), lens: lens, canvas: canvas,
                                     linearLight: linearLight)
        let clear = CIImage(color: .clear).cropped(to: canvas)

        // How lit each pixel is: one over the area, nought out in the dim, and
        // with a feather a falloff between. The falloff is a blurred copy of
        // the area GROWN by half the feather, so it runs from fully lit at the
        // area's own edge to fully dimmed a feather's width beyond it, and the
        // larger of it and the hard area is taken, so the inside stays exactly
        // lit however soft the edge is.
        var lit = hard.composited(over: clear)
        let feather = max(0, lens.spotlightFeather)
        // Blurred only round the area, not across the whole canvas: past a
        // feather's width out the falloff is nought anyway, and a canvas-sized
        // blur of a mask cost a 12 megapixel picture about ten milliseconds a
        // frame while the Feather slider moved. An area pushed wholly off the
        // picture has no edge on it to soften, and the rest is simply dimmed.
        if feather >= 0.5, let grown = area(feather / 2),
           case let near = grown.extent.insetBy(dx: -feather, dy: -feather).intersection(canvas),
           !near.isNull, near.width >= 1, near.height >= 1 {
            let soft = grown.composited(over: CIImage(color: .clear).cropped(to: near))
                .applyingGaussianBlur(sigma: feather / 6)
                .cropped(to: near)
            lit = soft.applyingFilter("CIMaximumCompositing",
                                      parameters: [kCIInputBackgroundImageKey: lit])
                .cropped(to: canvas)
        }

        // How much of the changed picture shows: the layer's opacity wherever
        // the area is not lit.
        let strength = CIImage(color: CIColor(red: 1, green: 1, blue: 1,
                                              alpha: min(max(opacity, 0), 1)))
            .cropped(to: canvas)
        let shows = strength.applyingFilter("CISourceOutCompositing",
                                            parameters: [kCIInputBackgroundImageKey: lit])
        return changed.applyingFilter("CISourceInCompositing",
                                      parameters: [kCIInputBackgroundImageKey: shows])
            .cropped(to: canvas)
    }

    /// The whole canvas, softened and then dimmed.
    static func changedPicture(_ picture: CIImage, lens: LensContent, canvas: CGRect,
                               linearLight: Bool) -> CIImage {
        var image = picture
        if lens.spotlightBlur > 0 {
            // Held at the picture's own edge before blurring, the way the blur
            // lens does it: blurred against the transparency past the canvas,
            // the edge of the picture would wear a dark rim.
            image = image.clampedToExtent()
                .applyingGaussianBlur(sigma: lens.spotlightBlur)
                .cropped(to: canvas)
        }
        let dim = min(max(lens.spotlightDim, 0), 1)
        if dim > 0 {
            image = dimmed(image, keeping: 1 - dim, linearLight: linearLight)
        }
        return image
    }

    /// The picture with its stored colour values scaled by `keeping`: half is
    /// half as bright to the eye, the way a black veil at half opacity darkens
    /// a picture in any editor. In light the values are first put back into
    /// the numbers they were written in, scaled there, and turned back into
    /// light, so Dim means the same thing whichever space the app mixes in.
    private static func dimmed(_ image: CIImage, keeping: CGFloat, linearLight: Bool) -> CIImage {
        let k = min(max(keeping, 0), 1)
        let scale: (CIImage) -> CIImage = {
            $0.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: k, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: k, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: k, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            ])
        }
        guard linearLight else { return scale(image) }
        return scale(image.applyingFilter("CILinearToSRGBToneCurve"))
            .applyingFilter("CISRGBToneCurveToLinear")
    }

    /// An ellipse filling `box`, white inside and clear outside, with a one
    /// pixel soft edge so it does not stair-step.
    static func ellipse(in box: CGRect) -> CIImage? {
        guard box.width >= 1, box.height >= 1 else { return nil }
        let radius = box.width / 2
        let gradient = CIFilter.radialGradient()
        gradient.center = .zero
        gradient.radius0 = Float(max(0, radius - 0.5))
        gradient.radius1 = Float(radius + 0.5)
        gradient.color0 = .white
        gradient.color1 = .clear
        guard let circle = gradient.outputImage else { return nil }
        let reach = radius + 1
        return circle
            .cropped(to: CGRect(x: -reach, y: -reach, width: reach * 2, height: reach * 2))
            .transformed(by: CGAffineTransform(scaleX: 1, y: box.height / box.width))
            .transformed(by: CGAffineTransform(translationX: box.midX, y: box.midY))
    }
}
