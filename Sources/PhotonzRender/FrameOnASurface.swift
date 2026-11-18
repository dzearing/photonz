import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import VideoToolbox

/// A decoded frame of a recording, drawn onto a GPU surface and kept there.
///
/// The picture is what everything that reads pixels uses; it is made of the
/// surface itself and holds no copy of its own. Registered together
/// (`ImageStore.register(_:as:surface:)`), a composite reads the surface
/// straight off the GPU. Read back into a bitmap instead, every frame was
/// copied off the GPU once when it was decoded and onto it again by every
/// composite that drew it: on the 6 minute reference edit those two copies
/// were about three quarters of a composite's time on the render thread
/// (2026-11-18).
///
/// Unchecked: a pixel buffer is not Sendable. The surface is written once,
/// inside `FrameOnASurface.draw`, before anything else can see it, and only
/// read after.
public struct SurfaceFrame: @unchecked Sendable {
    public let image: CGImage
    public let surface: CVPixelBuffer

    public init(image: CGImage, surface: CVPixelBuffer) {
        self.image = image
        self.surface = surface
    }
}

public enum FrameOnASurface {
    /// `image`'s `extent` drawn onto a surface of its own, in `colorSpace`,
    /// with a picture made of it. The same picture
    /// `context.createCGImage(image, from: extent, format: .RGBA8, colorSpace:)`
    /// makes, without reading it back. Nil where there is nothing to draw.
    public static func draw(_ image: CIImage, from extent: CGRect, colorSpace: CGColorSpace,
                            context: CIContext) -> SurfaceFrame? {
        let width = Int(extent.width.rounded()), height = Int(extent.height.rounded())
        guard width >= 1, height >= 1, extent.minX.isFinite, extent.minY.isFinite else { return nil }
        var made: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
        guard CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA,
                                  attributes as CFDictionary, &made) == kCVReturnSuccess,
              let buffer = made
        else { return nil }
        // The picture made of the surface says the colours it is in.
        CVBufferSetAttachment(buffer, kCVImageBufferCGColorSpaceKey, colorSpace, .shouldPropagate)
        let destination = CIRenderDestination(pixelBuffer: buffer)
        destination.colorSpace = colorSpace
        let target = CGRect(x: 0, y: 0, width: width, height: height)
        let moved = image.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            .cropped(to: target)
        guard let task = try? context.startTask(toRender: moved, from: target, to: destination, at: .zero),
              (try? task.waitUntilCompleted()) != nil
        else { return nil }
        var picture: CGImage?
        VTCreateCGImageFromCVPixelBuffer(buffer, options: nil, imageOut: &picture)
        guard let picture else { return nil }
        return SurfaceFrame(image: picture, surface: buffer)
    }

    /// A bitmap copied once onto a GPU surface and read from there.
    ///
    /// Core Image copies a bitmap's bytes into GPU memory on every render
    /// that draws it, however long the CIImage made of it is kept: the 6
    /// minute reference edit's moving background, a full-frame mask kept
    /// between frames, was copied in at 30 MB a frame, about half of every
    /// composite's time on the render thread (2026-11-18). On a surface it is
    /// copied once. The same pixels exactly: drawn across with no blending
    /// and no change of colours. Nil for anything but 8 bit colour, which is
    /// left as it was.
    public static func keep(_ cg: CGImage) -> CIImage? {
        guard let space = cg.colorSpace, space.model == .rgb, cg.bitsPerComponent == 8,
              cg.width >= 1, cg.height >= 1
        else { return nil }
        var made: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
        guard CVPixelBufferCreate(nil, cg.width, cg.height, kCVPixelFormatType_32BGRA,
                                  attributes as CFDictionary, &made) == kCVReturnSuccess,
              let buffer = made
        else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let opaque = [.none, .noneSkipFirst, .noneSkipLast].contains(cg.alphaInfo)
        let info = CGBitmapInfo.byteOrder32Little.rawValue
            | (opaque ? CGImageAlphaInfo.noneSkipFirst : CGImageAlphaInfo.premultipliedFirst).rawValue
        guard let base = CVPixelBufferGetBaseAddress(buffer),
              let context = CGContext(data: base, width: cg.width, height: cg.height, bitsPerComponent: 8,
                                      bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: space,
                                      bitmapInfo: info)
        else { return nil }
        context.setBlendMode(.copy)
        context.interpolationQuality = .none
        context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        if opaque {
            // Skipped alpha is whatever was there: say solid.
            let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
            let bytes = base.assumingMemoryBound(to: UInt8.self)
            for y in 0..<cg.height {
                let row = bytes + y * rowBytes
                for x in 0..<cg.width { row[x * 4 + 3] = 255 }
            }
        }
        return CIImage(cvPixelBuffer: buffer, options: [.colorSpace: space])
    }
}
