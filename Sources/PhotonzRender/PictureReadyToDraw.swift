import CoreGraphics

/// A picture made, once, into the pixels a drawing takes as they are: 8 bit
/// BGRA, premultiplied, little endian, in the colours it is drawn in.
///
/// A picture in any other form is converted again on the CPU every time it is
/// drawn. A clip's thumbnails come from the movie in the recording's own
/// colours, and a lane of the timeline paints them into a picture of its own
/// (`TimelinePaintedPicture`), in sRGB: every picture laid converted every
/// thumbnail in it again, and the frame that showed the picture waited for
/// that, 9 to 10 ms of a scroll's frame on the 50 track reference edit
/// (2026-11-27, `no-frame-of-a-50-track-zoom-is-held-up-by-the-sy`, pass 3).
/// The same holds for a layer's contents and the display's colours: a
/// 7794 by 160 picture in RGBA sRGB took a commit 9 ms, in BGRA in the
/// display's colours 0.14 ms.
public enum PictureReadyToDraw {
    static let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue

    /// `image` drawn once into `space` in that pixel order, or `image` itself
    /// when it already is, when `space` is not known (nil) or not RGB, or when
    /// it cannot be drawn.
    public static func picture(_ image: CGImage, in space: CGColorSpace?) -> CGImage {
        guard let space, space.model == .rgb else { return image }
        if isAlready(image, in: space) { return image }
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space, bitmapInfo: bitmapInfo)
        else { return image }
        context.interpolationQuality = .none
        context.setBlendMode(.copy)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage() ?? image
    }

    static func isAlready(_ image: CGImage, in space: CGColorSpace) -> Bool {
        image.bitsPerComponent == 8 && image.bitsPerPixel == 32
            && image.bitmapInfo.rawValue & (CGBitmapInfo.alphaInfoMask.rawValue | CGBitmapInfo.byteOrderMask.rawValue)
                == bitmapInfo
            && image.colorSpace == space
    }
}
