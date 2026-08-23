import Foundation

/// A screenshot's brightness, at full resolution, in a form pure core code can
/// read.
///
/// `EdgeMap` answers "where are the boundaries near here", which is enough to
/// snap a ruler foot but not enough to say what a boundary BELONGS to: it stores
/// gradients summed into 16 px blocks, so it cannot tell a divider that runs the
/// width of a settings row from a card border that runs 16 px wider. Element
/// detection needs exactly that distinction, and it needs it to the pixel — a
/// redliner's number is wrong at 8 px of slop. So the analyzer keeps the
/// perceptual luma it already computes and hands it over as this field.
///
/// One byte per pixel (12 MB for a 12-megapixel capture), cached per image
/// beside the edge map. Top-left origin, row-major, matching every other image
/// buffer in the app.
public struct LumaField: Equatable, Sendable {
    public let width: Int
    public let height: Int
    /// Perceptual luma, 0 (black) … 255 (white), `samples[y * width + x]`.
    public let samples: [UInt8]

    /// Mis-sized input yields the empty field rather than trapping — the same
    /// forgiving contract `EdgeMap` has, since both are built from image data
    /// that can fail to decode.
    public init(width: Int, height: Int, samples: [UInt8]) {
        guard width > 0, height > 0, samples.count == width * height else {
            self.width = 0
            self.height = 0
            self.samples = []
            return
        }
        self.width = width
        self.height = height
        self.samples = samples
    }

    /// The field for an image that has not been analyzed yet. Detection degrades
    /// to edge-map-only reasoning rather than misbehaving.
    public static let empty = LumaField(width: 0, height: 0, samples: [])

    public var isEmpty: Bool { width == 0 || height == 0 }

    /// Luma at a pixel in 0…1, clamped to the image so callers can probe past an
    /// edge without bounds-checking every read.
    public func luma(_ x: Int, _ y: Int) -> Double {
        guard !isEmpty else { return 0 }
        let cx = min(max(x, 0), width - 1)
        let cy = min(max(y, 0), height - 1)
        return Double(samples[cy * width + cx]) / 255
    }

    /// How strongly a HORIZONTAL boundary reads at this pixel: the largest
    /// central brightness difference across the row, searched over a one-pixel
    /// band so a boundary that wanders a row (antialiasing, a rounded corner)
    /// still answers. A 1 px rule drawn on white reads here even though the rows
    /// either side of it are identical, because the difference is taken ACROSS
    /// the rule, not across the pair of rows flanking it.
    public func horizontalResponse(x: Int, y: Int) -> Double {
        guard !isEmpty else { return 0 }
        var best = 0.0
        for band in -1...1 {
            let d = abs(luma(x, y + band + 1) - luma(x, y + band - 1))
            if d > best { best = d }
        }
        return best
    }

    /// How strongly a VERTICAL boundary reads at this pixel — the column-wise
    /// mirror of `horizontalResponse`.
    public func verticalResponse(x: Int, y: Int) -> Double {
        guard !isEmpty else { return 0 }
        var best = 0.0
        for band in -1...1 {
            let d = abs(luma(x + band + 1, y) - luma(x + band - 1, y))
            if d > best { best = d }
        }
        return best
    }
}
