import CoreGraphics
import Foundation

/// How words typed over a video come out before anybody styles them
/// (`docs/design/mocks/pages/video.html`, the "Ship it faster." title).
///
/// Text on a still keeps the text tool's own remembered type, which starts at
/// 24pt regular in the current foreground colour: right for a callout on a
/// screenshot, invisible on a dark screen recording. Premiere and Final Cut
/// both start a title large, white and bold, and so does the mock, so a
/// document with time hands the text tool this look instead. It is a starting
/// point only: whatever somebody sets in the Text section while the video is
/// open is what the next title wears.
public enum TitleLook {

    /// The mock sets its title in the system serif, which the renderer cannot
    /// reach by name; Georgia is the curated serif it falls back to.
    public static let fontName = "Georgia"
    public static let weight = TextWeight.bold
    public static let colorHex = "#FFFFFF"

    /// The mock draws 26px words on a 248px frame, and Premiere's type tool
    /// starts at 100px on 1080: both about a tenth of the picture's height.
    public static let shareOfHeight: CGFloat = 0.1

    /// Never smaller than the text tool's own starting size.
    public static let smallestSize: CGFloat = 24

    /// The size a title starts at on a picture this size.
    public static func fontSize(in size: CGSize) -> CGFloat {
        max(smallestSize, (size.height * shareOfHeight).rounded())
    }

    /// The text tool's type for a new title on a picture this size.
    public static func styles(in size: CGSize) -> TextStyles {
        TextStyles(fontName: fontName, fontSize: fontSize(in: size),
                   weight: weight, colorHex: colorHex)
    }

    /// The mock's soft drop shadow (`0 2px 12px` at forty per cent on 26px
    /// words), scaled to the type so a big title throws a big soft shadow.
    /// Its colour opposes the words, as every text layer's shadow does.
    public static func shadow(forColorHex hex: String, fontSize: CGFloat) -> ShadowStyle {
        let contrast = TextBuilder.autoContrastShadow(forColorHex: hex)
        return ShadowStyle(radius: fontSize * 6 / 26,
                           offset: CGSize(width: 0, height: fontSize * 2 / 26),
                           colorHex: contrast.colorHex,
                           opacity: 0.45)
    }
}
