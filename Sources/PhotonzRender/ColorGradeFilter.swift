import CoreGraphics
import CoreImage
import Foundation
import PhotonzCore

// A colour grade, drawn (`ColorGradeEffect` in PhotonzCore says what it is).
//
// Three of Core Image's own filters, each only when a value it answers for is
// off its middle: exposure first, as a camera's would be, then the white
// balance, then contrast and saturation together. A grade with every value at
// its middle never reaches here (`LayerStyle.colorGrade` is nil), so a clip
// with its sliders put back is drawn exactly as it was.
//
// Cost on the composite path: per-pixel colour kernels Core Image folds into
// one pass with whatever reads the picture, so no extra buffer. Measured with
// the render tests' frame and on a 1920x1080 frame in the commit note.

public enum ColorGradeFilter {

    /// How far Temperature at its ends moves the white point, in mireds (a
    /// million over the kelvin), the scale a white point moves evenly on: 100
    /// mireds either side of daylight is about 3900K warm and 18600K cool, as
    /// orange and as blue as each other, Lumetri's two ends. Measured on a
    /// grey card before building: red over blue moves 55 levels either way.
    static let miredsAtTheEnds: CGFloat = 100
    /// How far Tint at its ends moves along the green to magenta axis.
    static let tintPerStep: CGFloat = 0.5
    /// Daylight, the white point the recording is taken to have.
    static let daylight: CGFloat = 6500

    /// `image` with `grade` applied to its colours. Transparent pixels stay
    /// transparent: every filter here works on colour, not coverage.
    public static func graded(_ image: CIImage, by grade: ColorGradeEffect) -> CIImage {
        guard grade.paints else { return image }
        var image = image
        if grade.exposure != 0 {
            image = image.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: grade.exposure])
        }
        if grade.temperature != 0 || grade.tint != 0 {
            // Warmer is a LOWER target white: the picture is told the light it
            // was taken in is bluer than it is, and so is warmed to make up
            // for it. Magenta is the negative end of Core Image's tint axis.
            let mireds = 1_000_000 / daylight + CGFloat(grade.temperature) / 100 * miredsAtTheEnds
            let target = CIVector(x: 1_000_000 / mireds, y: -CGFloat(grade.tint) * tintPerStep)
            image = image.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: daylight, y: 0),
                "inputTargetNeutral": target
            ])
        }
        if grade.contrast != 0 || grade.saturation != 100 {
            // Contrast at its ends halves or half again the slope about the
            // middle grey: flat, never a grey card; punchy, never posterised.
            image = image.applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: 1 + grade.contrast / 200,
                kCIInputSaturationKey: grade.saturation / 100,
                kCIInputBrightnessKey: 0
            ])
        }
        return image
    }
}
