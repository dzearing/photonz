import CoreGraphics
import Foundation

/// A picture's colours, as plain bytes, so the parts of the app that have to
/// reason about what a screenshot LOOKS like can do it without importing an
/// imaging framework.
///
/// `LumaField` is the same idea for brightness and is what the measure tool and
/// the text sweep read. Colour is a separate field because brightness cannot
/// tell a red button from a blue one of the same weight, and separating a box
/// is exactly the job where that difference is the whole point.
///
/// Premultiplied sRGB, one byte per channel, RGBA, row-major, top-left origin —
/// the same shape every other image buffer in the app has.
public struct PixelField: Sendable {
    public let width: Int
    public let height: Int
    public let samples: [UInt8]

    public init(width: Int, height: Int, samples: [UInt8]) {
        guard width > 0, height > 0, samples.count == width * height * 4 else {
            self.width = 0
            self.height = 0
            self.samples = []
            return
        }
        self.width = width
        self.height = height
        self.samples = samples
    }

    public static let empty = PixelField(width: 0, height: 0, samples: [])

    public var isEmpty: Bool { width == 0 || height == 0 }

    /// The colour at a pixel, with the alpha divided back out so a translucent
    /// pixel can be compared with an opaque one. Outside the picture is clear.
    public func color(_ x: Int, _ y: Int) -> RGBA {
        guard !isEmpty, x >= 0, y >= 0, x < width, y < height else {
            return RGBA(r: 0, g: 0, b: 0, a: 0)
        }
        let i = (y * width + x) * 4
        let a = Double(samples[i + 3]) / 255
        let scale = a > 0 ? 1 / a : 0
        return RGBA(r: Double(samples[i]) / 255 * scale,
                    g: Double(samples[i + 1]) / 255 * scale,
                    b: Double(samples[i + 2]) / 255 * scale,
                    a: a)
    }
}
