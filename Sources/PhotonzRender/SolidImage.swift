import CoreGraphics
import Foundation
import PhotonzCore

/// A bitmap of one flat color at a real size.
///
/// Deliberately not the 8 × 8 swatch the fill tool stretches across a layer:
/// pixel edits (a marquee fill, an eraser stroke) redraw a layer at its own
/// bitmap resolution, so a background born as a thumbnail paints blocky. A
/// blank canvas gets every pixel it claims to have.
public enum SolidImage {
    public static func make(size: CGSize, hex: String) -> CGImage? {
        let width = Int(size.width.rounded()), height = Int(size.height.rounded())
        guard width > 0, height > 0,
              let rgba = RGBA(hex: hex),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
