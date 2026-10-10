import CoreGraphics
import Foundation
import PhotonzCore

/// What a preview looks like on the strip's one dark chip
/// (icon-draw-wt.html, step 11).
///
/// The mock draws the same glyph LIGHT on that chip, and it is right to: a
/// glyph drawn in one dark grey is a template, and the Mac draws a template in
/// the label colour, which is light on a dark ground. Shown as drawn it would
/// be black on near black, which tells nobody anything.
///
/// Only that case changes. A glyph of one bright colour, a light glyph, and an
/// icon of many colours (an app icon, a two tone glyph, one with shading) are
/// shown exactly as drawn, because that is how they will really be seen.
public enum IconPreviewInk {

    /// The picture to put on the dark chip: the same coverage in the light
    /// ink when it is a one colour dark glyph, otherwise the picture itself.
    public static func onDarkGround(_ image: CGImage) -> CGImage {
        guard isOneDarkColour(image), let ink = inkColour,
              let context = context(width: image.width, height: image.height) else { return image }
        let box = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.draw(image, in: box)
        // Keeps every pixel's coverage and swaps its colour, so a soft edge
        // stays exactly as soft as it was drawn.
        context.setBlendMode(.sourceIn)
        context.setFillColor(ink)
        context.fill(box)
        return context.makeImage() ?? image
    }

    /// Whether every pixel with real coverage is the same dark grey. Faint
    /// edge pixels are left out of the vote: un-premultiplied, an eighth of a
    /// pixel of black rounds to almost any colour.
    static func isOneDarkColour(_ image: CGImage) -> Bool {
        guard let context = context(width: image.width, height: image.height),
              let data = context.data else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = data.bindMemory(to: UInt8.self, capacity: image.width * image.height * 4)
        var low = [255, 255, 255], high = [0, 0, 0], counted = 0
        for offset in stride(from: 0, to: image.width * image.height * 4, by: 4) {
            let alpha = Int(bytes[offset + 3])
            guard alpha >= 64 else { continue }
            counted += 1
            for channel in 0..<3 {
                let straight = min(255, Int(bytes[offset + channel]) * 255 / alpha)
                low[channel] = min(low[channel], straight)
                high[channel] = max(high[channel], straight)
            }
        }
        guard counted > 0 else { return false }
        // One colour: no channel wanders more than a rounding's worth.
        guard (0..<3).allSatisfy({ high[$0] - low[$0] <= 24 }) else { return false }
        // A grey: the channels agree with each other.
        let mean = (0..<3).map { (high[$0] + low[$0]) / 2 }
        guard (mean.max() ?? 0) - (mean.min() ?? 0) <= 24 else { return false }
        // Dark: the side of the scale a label colour sits on in light mode.
        return (mean.max() ?? 255) <= 96
    }

    private static let inkColour: CGColor? = RGBA(hex: IconPreviews.inkOnDarkHex)
        .map { CGColor(srgbRed: $0.r, green: $0.g, blue: $0.b, alpha: 1) }

    private static func context(width: Int, height: Int) -> CGContext? {
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                         bytesPerRow: width * 4, space: space,
                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }
}
