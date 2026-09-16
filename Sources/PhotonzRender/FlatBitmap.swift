import CoreGraphics
import Foundation
import PhotonzCore

/// Whether a picture is really just one flat colour.
///
/// A blank canvas starts as a REAL full-size bitmap of white (`SolidImage`),
/// because a marquee fill or an eraser stroke on the background has to redraw
/// at full resolution. That is right on the canvas and wrong in a file: an icon
/// drawn on a blank canvas used to export as an SVG with a photograph of white
/// inside it, tens of kilobytes of base64 around a few hundred bytes of shapes.
///
/// A flat colour is a rectangle, so this is what lets `SVGExporter` say so. It
/// is here rather than in `PhotonzCore` because it reads pixels, and pixels
/// never reach the pure layer.
public enum FlatBitmap {

    /// The one colour every pixel of `image` is, or nil where any two differ.
    ///
    /// Strict: no tolerance at all. A photograph of a white wall is not flat
    /// and must not lose its pixels, while a canvas painted one colour is
    /// exactly uniform and always will be.
    public static func color(of image: CGImage) -> RGBA? {
        let width = image.width, height = image.height
        guard width > 0, height > 0 else { return nil }

        // A cheap look first. A photograph differs somewhere inside any
        // thirty-second of itself, so it is answered from a 32 × 32 sample
        // rather than by walking twelve megapixels.
        let coarseWidth = min(width, 32), coarseHeight = min(height, 32)
        guard let coarse = uniform(image, width: coarseWidth, height: coarseHeight)
        else { return nil }
        if coarseWidth == width, coarseHeight == height { return unpremultiplied(coarse) }

        // Then every pixel, a band of rows at a time, so an 8192-wide canvas
        // never needs a buffer the size of itself.
        let rows = max(1, bandPixels / width)
        var top = 0
        while top < height {
            let band = min(rows, height - top)
            guard let slice = image.cropping(to: CGRect(x: 0, y: top, width: width, height: band)),
                  let found = uniform(slice, width: width, height: band),
                  found == coarse else { return nil }
            top += band
        }
        return unpremultiplied(coarse)
    }

    /// The flat colour of every image layer in `document`, keyed by the id of
    /// the bitmap it draws — what `SVGExport` needs to know which pictures are
    /// really rectangles.
    ///
    /// Asked once per export: two layers sharing a bitmap read it once, and a
    /// layer that could never go out as a rectangle anyway is never read.
    public static func colors(in document: PhotonzDocument, store: ImageStore) -> [UUID: RGBA] {
        var found: [UUID: RGBA] = [:]
        var asked: Set<UUID> = []
        for layer in document.allLayers where layer.isVisible {
            guard case .image(let ref) = layer.content, layer.crop == nil,
                  asked.insert(ref.id).inserted, let bitmap = store.image(for: ref)
            else { continue }
            if let colour = color(of: bitmap) { found[ref.id] = colour }
        }
        return found
    }

    // MARK: - Reading the pixels

    /// How many pixels one band of the full walk holds, so the buffer stays a
    /// few megabytes whatever the picture's size.
    private static let bandPixels = 4_000_000

    /// The four bytes every pixel of `image` is when drawn at `width` × `height`,
    /// or nil where they differ. Premultiplied sRGB, same as everywhere else.
    private static func uniform(_ image: CGImage, width: Int, height: Int) -> [UInt8]? {
        guard width > 0, height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drew = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress,
                  let context = CGContext(data: base, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            // Nearest neighbour: the sample has to BE one of the picture's own
            // pixels, not an average of several, or a checkerboard would blur
            // into a flat grey and go out as a rectangle.
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drew, bytes.count >= 4 else { return nil }
        // Every pixel the same as the one before it, said in one pass the
        // machine can do four thousand bytes at a time: the buffer against
        // itself, shifted along by a pixel. Walking twelve megapixels a byte
        // at a time is what makes a flat canvas slow to answer for.
        let same = bytes.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress, raw.count > 4 else { return true }
            return memcmp(base, base.advanced(by: 4), raw.count - 4) == 0
        }
        guard same else { return nil }
        return Array(bytes[0..<4])
    }

    /// One premultiplied pixel as a colour, with the alpha divided back out —
    /// the same reading `PixelField` does, so there is one rule for it.
    private static func unpremultiplied(_ pixel: [UInt8]) -> RGBA? {
        guard pixel.count == 4 else { return nil }
        return PixelField(width: 1, height: 1, samples: pixel).color(0, 0)
    }
}
