// Reads how well an arrow's chip words stand off their plate, off the PIXELS of
// a rendered picture rather than off the model. The probe uses it so a walk can
// say what a person would actually see (`expectChipContrast`), and the tests
// hold it to the colours the chip is drawn in.

import CoreGraphics
import PhotonzCore

public enum ChipContrastReader {

    public struct Reading: Hashable, Sendable {
        /// The words' colour: the pixel in the words' band that stands
        /// furthest from the plate, which is the core of a letter's stroke.
        public var words: RGBA
        /// The plate right beside the words, at the worse of two points in the
        /// chip's trailing padding (one high, one low, so Highlighter's swipe
        /// is read too).
        public var plate: RGBA
        /// WCAG contrast between the two.
        public var contrast: Double
    }

    /// The chip's rectangle in document points, or nil for an arrow with no
    /// words.
    public static func chipRect(_ layer: Layer) -> CGRect? {
        guard let a = layer.annotation, a.hasCaption, let caption = a.caption else { return nil }
        let size = CaptionMetrics.pillSize(for: caption, in: a)
        let center = a.captionPillCenter(forPillSize: size)
        return CGRect(x: layer.frame.minX + center.x - size.width / 2,
                      y: layer.frame.minY + center.y - size.height / 2,
                      width: size.width, height: size.height)
    }

    /// The chip of `layer` as drawn in `image`, a picture of the whole
    /// document at `scale` pixels to the point, top row first.
    public static func read(_ layer: Layer, in image: CGImage, scale: CGFloat = 1) -> Reading? {
        guard let a = layer.annotation, let rect = chipRect(layer) else { return nil }
        let pixels = Pixels(image)
        func at(_ point: CGPoint) -> RGBA? {
            pixels.at(Int((point.x * scale).rounded(.down)), Int((point.y * scale).rounded(.down)))
        }
        let pad = a.captionPadding
        let plates = [CGPoint(x: rect.maxX - pad * 0.6, y: rect.midY - rect.height * 0.25),
                      CGPoint(x: rect.maxX - pad * 0.8, y: rect.midY + rect.height * 0.2)].compactMap(at)
        guard let firstPlate = plates.first else { return nil }
        // The words' band: past the marker, inside the padding, the middle of
        // the line's height where every letter has ink.
        let left = rect.minX + pad + a.captionLeadWidth
        let right = rect.maxX - pad
        let top = rect.midY - rect.height * 0.3
        let bottom = rect.midY + rect.height * 0.3
        guard right > left else { return nil }
        var words = firstPlate
        var best = 1.0
        var y = top
        let step = 1 / max(scale, 1)
        while y <= bottom {
            var x = left
            while x <= right {
                if let pixel = at(CGPoint(x: x, y: y)) {
                    let ratio = InkPlate.contrast(pixel, firstPlate)
                    if ratio > best { best = ratio; words = pixel }
                }
                x += step
            }
            y += step
        }
        let worst = plates.map { (plate: $0, ratio: InkPlate.contrast(words, $0)) }
            .min { $0.ratio < $1.ratio }
        guard let worst else { return nil }
        return Reading(words: words, plate: worst.plate, contrast: worst.ratio)
    }

    /// The picture as sRGB bytes, read a pixel at a time.
    private struct Pixels {
        let data: [UInt8]
        let width: Int
        let height: Int

        init(_ image: CGImage) {
            width = image.width
            height = image.height
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            let w = width, h = height
            bytes.withUnsafeMutableBytes { buffer in
                guard let context = CGContext(data: buffer.baseAddress, width: w, height: h,
                                              bitsPerComponent: 8, bytesPerRow: w * 4,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)
                                                  ?? CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                else { return }
                context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            }
            data = bytes
        }

        func at(_ x: Int, _ y: Int) -> RGBA? {
            guard x >= 0, y >= 0, x < width, y < height else { return nil }
            let i = (y * width + x) * 4
            return RGBA(r: Double(data[i]) / 255, g: Double(data[i + 1]) / 255, b: Double(data[i + 2]) / 255)
        }
    }
}
