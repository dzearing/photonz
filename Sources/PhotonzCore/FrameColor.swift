import CoreGraphics
import Foundation

/// The mean colour of a picture, read the way a walk's `measureColor` step
/// reads the canvas: each channel's average over the whole frame, laid over
/// black, nought to 255 in sRGB.
///
/// What a colour grade is judged by in a walk: Temperature at its warm end has
/// to raise red over blue by a clear margin, and every value put back to its
/// middle has to give the untouched picture exactly (`identical`).
public struct FrameColor: Hashable, Sendable, Codable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Red over blue: higher is warmer.
    public var warmth: Double { red - blue }

    /// The reading in words, for a walk's log.
    public var text: String {
        "red \(Int(red.rounded())) green \(Int(green.rounded())) blue \(Int(blue.rounded())), "
            + "red over blue \(Int(warmth.rounded()))"
    }

    /// The picture's mean colour, shrunk to a couple of hundred pixels across
    /// first since only the average is wanted. Nil for a picture with no area.
    public static func mean(of image: CGImage) -> FrameColor? {
        guard image.width > 0, image.height > 0 else { return nil }
        let width = min(image.width, 192)
        let height = max(1, Int((Double(width) * Double(image.height) / Double(image.width)).rounded()))
        guard let data = pixels(of: image, width: width, height: height) else { return nil }
        var r = 0.0, g = 0.0, b = 0.0
        for index in stride(from: 0, to: data.count, by: 4) {
            r += Double(data[index]); g += Double(data[index + 1]); b += Double(data[index + 2])
        }
        let count = Double(width * height)
        return FrameColor(red: r / count, green: g / count, blue: b / count)
    }

    /// Whether two pictures are the same size and the same pixel for pixel.
    public static func identical(_ a: CGImage, _ b: CGImage) -> Bool {
        guard a.width == b.width, a.height == b.height,
              let left = pixels(of: a, width: a.width, height: a.height),
              let right = pixels(of: b, width: b.width, height: b.height) else { return false }
        return left == right
    }

    /// The picture drawn over black into sRGB bytes at a size.
    static func pixels(of image: CGImage, width: Int, height: Int) -> [UInt8]? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = data.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            let whole = CGRect(x: 0, y: 0, width: width, height: height)
            context.setFillColor(gray: 0, alpha: 1)
            context.fill(whole)
            context.interpolationQuality = .medium
            context.draw(image, in: whole)
            return true
        }
        return drawn ? data : nil
    }
}
