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
}
