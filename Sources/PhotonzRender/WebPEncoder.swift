import Accelerate
import CWebP
import CoreGraphics
import Foundation

/// Writes a WebP, which is the one picture format macOS can read and cannot
/// write.
///
/// Everything else in this app goes out through ImageIO. ImageIO lists 22
/// writable types on macOS 26 and WebP is not one of them, while its readable
/// list does include `org.webmproject.webp`. So reading stays exactly where it
/// was, through the system, and only writing comes here, through libwebp built
/// from vendored source (see `Vendor/libwebp/VERSION`).
///
/// One quality, 0 to 1, the same number every other format takes. The top of
/// the range is not "nearly all of it": WebP is two encoders sharing a file
/// format, and 1 asks for the lossless one. That matters for what this app
/// mostly makes, because a screenshot of flat panels comes out smaller and
/// sharper lossless than it does either as a PNG or as a lossy WebP.
public enum WebPEncoder {

    /// The longest side WebP can describe, from the format itself: the width
    /// and height fields in the bitstream are 14 bits.
    public static let limit = 16383

    /// How hard the lossless encoder tries, of libwebp's 0 to 9.
    ///
    /// Measured on the 1800 × 1400 screenshot the render tests use: level 3
    /// takes 0.43s for 287 KB, level 6 takes 0.51s for 256 KB, and level 9
    /// takes 2.62s for 155 KB. Six is the knee. Nine is a fifth of the size
    /// again but five times the wait, and the wait is the part somebody
    /// exporting a screenshot feels.
    private static let losslessLevel: Int32 = 6

    public static func canEncode(width: Int, height: Int) -> Bool {
        width > 0 && height > 0 && width <= limit && height <= limit
    }

    /// Encodes `image` as a WebP. `quality` is 0 to 1, where 1 is lossless.
    /// Nil when the picture is too big for the format, or the encoder refuses.
    public static func encode(_ image: CGImage, quality: Double) -> Data? {
        guard canEncode(width: image.width, height: image.height),
              let rgba = straightRGBA(from: image) else { return nil }

        // Every path starts from the defaults. WebPConfigLosslessPreset only
        // sets three fields and leaves the rest alone, so on a config that was
        // never initialised it produces one the validator refuses.
        var config = WebPConfig()
        guard WebPConfigPreset(&config, WEBP_PRESET_DEFAULT, 100) != 0 else { return nil }
        let lossless = quality >= 1
        if lossless {
            guard WebPConfigLosslessPreset(&config, losslessLevel) != 0 else { return nil }
            // Flat interface is nothing but hard edges between solid colours,
            // which is the shape this encoder is best at when it is told to
            // look for it.
            config.image_hint = WEBP_HINT_GRAPH
        } else {
            config.quality = Float(min(max(quality, 0), 1) * 100)
            // Alpha is kept losslessly either way, so a fading edge stays an
            // edge even where the colour under it is being thrown away.
            config.alpha_quality = 100
        }
        config.thread_level = 1
        guard WebPValidateConfig(&config) != 0 else { return nil }

        var picture = WebPPicture()
        guard WebPPictureInit(&picture) != 0 else { return nil }
        defer { WebPPictureFree(&picture) }
        picture.width = Int32(image.width)
        picture.height = Int32(image.height)
        // The lossless encoder works on the pixels as they are; the lossy one
        // wants YUV, and letting libwebp make that conversion is what keeps the
        // two paths one line apart.
        picture.use_argb = lossless ? 1 : 0

        let imported = rgba.withUnsafeBufferPointer { bytes in
            WebPPictureImportRGBA(&picture, bytes.baseAddress, Int32(image.width * 4))
        }
        guard imported != 0 else { return nil }

        var memory = WebPMemoryWriter()
        WebPMemoryWriterInit(&memory)
        defer { WebPMemoryWriterClear(&memory) }
        picture.writer = WebPMemoryWrite
        let wrote = withUnsafeMutablePointer(to: &memory) { sink -> Bool in
            picture.custom_ptr = UnsafeMutableRawPointer(sink)
            defer { picture.custom_ptr = nil }
            return WebPEncode(&config, &picture) != 0
        }
        guard wrote, let buffer = memory.mem, memory.size > 0 else { return nil }
        return Data(bytes: buffer, count: memory.size)
    }

    /// The image as straight (un-premultiplied) 8-bit RGBA in sRGB.
    ///
    /// The un-premultiplying is the whole point of this function. Core Graphics
    /// hands out premultiplied pixels, where a half-transparent red is already
    /// halfway to black, and libwebp expects straight ones. Hand it the
    /// premultiplied bytes and every fading edge in the file comes back muddy,
    /// which on this app's pictures means exactly the soft shadows and rounded
    /// corners it puts on things.
    ///
    /// Core Graphics will not draw into a straight-alpha bitmap at all, so the
    /// draw is premultiplied and Accelerate undoes it in one pass.
    private static func straightRGBA(from image: CGImage) -> [UInt8]? {
        let width = image.width
        let height = image.height
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = bytes.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress,
                  let context = CGContext(
                    data: base, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                        | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            var buffer = vImage_Buffer(data: base, height: vImagePixelCount(height),
                                       width: vImagePixelCount(width), rowBytes: width * 4)
            return vImageUnpremultiplyData_RGBA8888(&buffer, &buffer, vImage_Flags(kvImageNoFlags))
                == kvImageNoError
        }
        return drawn ? bytes : nil
    }
}
