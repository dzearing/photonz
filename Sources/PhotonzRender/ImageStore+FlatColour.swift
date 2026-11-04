import CoreGraphics
import Foundation
import PhotonzCore

extension ImageStore {

    /// The one opaque colour a picture is, as #RRGGBB, or nil when it is not
    /// one colour: a blank canvas's page is a picture, and Ask reads words
    /// against it (`AskLayoutCheck`). Read from a grid of its own pixels,
    /// picked rather than blended, so a pattern never averages into a flat.
    public func flatColourHex(for ref: ImageRef) -> String? {
        guard let image = image(for: ref) else { return nil }
        return Self.flatColourHex(of: image)
    }

    static func flatColourHex(of image: CGImage) -> String? {
        let side = 32
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let drawn: Bool = pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn, pixels[3] == 255 else { return nil }
        for at in stride(from: 0, to: pixels.count, by: 4) {
            for channel in 0..<4 where abs(Int(pixels[at + channel]) - Int(pixels[channel])) > 1 { return nil }
        }
        return String(format: "#%02X%02X%02X", pixels[0], pixels[1], pixels[2])
    }
}
