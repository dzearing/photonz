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
    /// How dark a title's glass dims the recording under it: enough that
    /// white words read at 4.5 to 1 over a white screenshot, and dark words
    /// on a light glass over a black one.
    public static let glassDim: Double = 0.55

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

    /// The soft shade words wear over a moving title background when their
    /// own colour would not stand out from the brightest (or darkest) the
    /// look can draw (`LivePalette.limit`): wide, centred and opposing their
    /// colour, so the words keep the colour they were designed in. Its exact
    /// shape is how the title knows it put it there (`isLiveScrim`), and takes
    /// it off again when the background stops moving.
    public static func liveScrim(forColorHex hex: String, fontSize: CGFloat) -> ShadowStyle {
        ShadowStyle(radius: fontSize * liveScrimShareOfSize, offset: .zero,
                    colorHex: TextBuilder.autoContrastShadow(forColorHex: hex).colorHex,
                    opacity: liveScrimOpacity)
    }

    static let liveScrimShareOfSize: CGFloat = 0.3
    static let liveScrimOpacity = 0.72

    /// Words as they land over a moving look they would not stand out from
    /// everywhere: wearing the shade a restyle would give them, so laying
    /// the title out again changes nothing.
    public static func shadedOverALook(_ words: Layer) -> Layer {
        guard case .text(let text) = words.content else { return words }
        var shaded = words
        shaded.style.shadows = [liveScrim(forColorHex: text.colorHex, fontSize: text.fontSize)]
        return shaded
    }

    public static func isLiveScrim(_ shadow: ShadowStyle) -> Bool {
        shadow.offset == .zero && shadow.opacity == liveScrimOpacity && shadow.spread == 0 && shadow.kind == .drop
    }

    /// How wide the tight edge is, as a share of the type: two pixels of
    /// softness on 80px words.
    public static let edgeShareOfSize: CGFloat = 1.0 / 40

    /// Everything a new title throws: the mock's soft shadow, then a tight edge
    /// hugging the letters. The soft shadow alone leaves white words the same
    /// colour as a white card they cross in a screen recording; the edge draws
    /// the letters' outline there, and on dark footage it is dark on dark, so
    /// the title looks as it always did.
    public static func shadows(forColorHex hex: String, fontSize: CGFloat) -> [ShadowStyle] {
        let soft = shadow(forColorHex: hex, fontSize: fontSize)
        let edge = ShadowStyle(radius: fontSize * edgeShareOfSize,
                               offset: .zero,
                               colorHex: soft.colorHex,
                               opacity: 0.85)
        return [soft, edge]
    }
}
