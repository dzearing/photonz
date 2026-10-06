import CoreGraphics
import PhotonzCore

/// The colour round the very edge of a picture: what a ring drawn just inside
/// it sits on.
///
/// Different from `ChromaKeySampler`, which asks which colour a wide band
/// holds most of and gives up on a busy one. A border needs an answer for any
/// picture, and only to pick a light or a dark ink, so this averages a thin
/// band, the width of a thick ring.
public enum EdgeColourSampler {

    /// How far in from each edge counts, in pixels at most.
    static let band = 12

    /// The average colour of the outermost band of the picture, or nil when it
    /// is too small to have one.
    public static func edgeColour(of image: CGImage) -> RGBA? {
        // Read through a small copy: a 12 megapixel frame would be 48 MB to
        // walk for one average.
        let scale = min(1, 256 / Double(max(image.width, image.height)))
        let width = Int((Double(image.width) * scale).rounded())
        let height = Int((Double(image.height) * scale).rounded())
        guard width >= 2, height >= 2 else { return nil }
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: &data, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let inset = max(1, min(Int((Double(band) * scale).rounded()), min(width, height) / 4))
        var r = 0, g = 0, b = 0, seen = 0
        for y in 0..<height {
            let edgeRow = y < inset || y >= height - inset
            for x in 0..<width where edgeRow || x < inset || x >= width - inset {
                let i = (y * width + x) * 4
                guard data[i + 3] > 200 else { continue }
                r += Int(data[i]); g += Int(data[i + 1]); b += Int(data[i + 2])
                seen += 1
            }
        }
        guard seen > 0 else { return nil }
        let n = Double(seen) * 255
        return RGBA(r: Double(r) / n, g: Double(g) / n, b: Double(b) / n)
    }
}
