import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Bitmap ⇄ data, used by export, the .photonz package format, and layer
/// copy/paste. No UI imports.
///
/// Reading is always the system's job, and so is writing everything except a
/// WebP, which ImageIO cannot write at all (`WebPEncoder`).
public enum ImageCodec {

    public enum Format: String, CaseIterable, Sendable {
        case png
        case jpeg
        case heic
        case webp

        /// What the file IS, which is what the save panel and the Finder want.
        ///
        /// Answerable for every format, including the one the system cannot
        /// write: macOS declares `org.webmproject.webp` because it can read
        /// one, so a WebP this app writes is a first-class file on the Mac the
        /// moment it lands.
        public var utType: UTType {
            switch self {
            case .png: .png
            case .jpeg: .jpeg
            case .heic: .heic
            case .webp: .webP
            }
        }

        public var fileExtension: String {
            switch self {
            case .png: "png"
            case .jpeg: "jpg"
            case .heic: "heic"
            case .webp: "webp"
            }
        }

        /// Whether the system writes this one, or we do.
        var isWrittenBySystem: Bool { self != .webp }
    }

    /// Encodes an image. `quality` applies to lossy formats (0–1; ignored by
    /// PNG). On WebP, and only on WebP, 1 means lossless.
    ///
    /// Three of the four go out through ImageIO. WebP branches because ImageIO
    /// cannot write one at all: `CGImageDestinationCopyTypeIdentifiers` does not
    /// list it, so there is no destination to create and no options to pass.
    /// The 0-to-1 quality is mapped to whatever each encoder wants in one place
    /// each, so 0.8 asks for the same amount of picture whichever is chosen.
    public static func encode(_ image: CGImage, format: Format, quality: Double = 0.9) -> Data? {
        guard format.isWrittenBySystem else {
            return WebPEncoder.encode(image, quality: quality)
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, format.utType.identifier as CFString, 1, nil) else { return nil }
        let options = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(destination, image, options)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    public static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// How big the picture in a file is, read from its header without decoding
    /// a single pixel. Nil for anything that is not a picture.
    ///
    /// This is what lets a drag say where a file would land before it lands:
    /// the answer is needed on every mouse move, and decoding a 12 megapixel
    /// screenshot to find out it is 4032 wide would stutter the drag.
    ///
    /// The numbers are the stored pixel counts, which is exactly what `decode`
    /// hands back for the same file, so a preview sized from here and the layer
    /// that follows it can never disagree.
    public static func pixelSize(ofFileAt url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Double,
              let height = properties[kCGImagePropertyPixelHeight] as? Double,
              width > 0, height > 0 else { return nil }
        return CGSize(width: width, height: height)
    }
}
