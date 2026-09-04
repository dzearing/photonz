import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Bitmap ⇄ data, used by export, the .photonz package format, and layer
/// copy/paste. ImageIO only — no UI imports.
public enum ImageCodec {

    public enum Format: String, CaseIterable, Sendable {
        case png
        case jpeg
        case heic

        public var utType: UTType {
            switch self {
            case .png: .png
            case .jpeg: .jpeg
            case .heic: .heic
            }
        }

        public var fileExtension: String {
            switch self {
            case .png: "png"
            case .jpeg: "jpg"
            case .heic: "heic"
            }
        }
    }

    /// Encodes an image. `quality` applies to lossy formats (0–1; ignored by PNG).
    public static func encode(_ image: CGImage, format: Format, quality: Double = 0.9) -> Data? {
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
