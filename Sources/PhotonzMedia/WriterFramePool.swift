import AVFoundation
import CoreVideo

/// Picture buffers for a writer's pixel buffer adaptor, from a pool the
/// writer makes once and holds for the whole write.
///
/// Never ask `AVAssetWriterInputPixelBufferAdaptor.pixelBufferPool` for a
/// frame's buffer. The adaptor swaps that pool for a new one a few frames into
/// every write (the fourth frame, at 160x120 and 320x200, measured on
/// 2026-11-22), and the encoder frees the old one on its own thread
/// (`vtBuildPixelBufferPoolsCommon`) while the adaptor can still hand it out.
/// A buffer asked of it then comes from a pool being torn down, and the process
/// dies: `EXC_BAD_ACCESS` at 0x0 in `CVPixelBufferPool::createPixelBuffer`. A
/// full test run died that way, and reading the adaptor's pool from a second
/// thread through the first frames of eight writes at once reproduced it in the
/// first round (`WriterFramePoolTests`).
///
/// A pool of our own is never touched by the encoder, and costs nothing the
/// adaptor's did not: it carries the adaptor's own pixel buffer attributes, on
/// an IOSurface, so the encoder still takes each frame without a copy.
public enum WriterFramePool {

    /// A pool of frames in the format, size and backing `adaptor` was made
    /// with. Nil when the adaptor names no pixel format or size, or the pool
    /// cannot be made.
    public static func make(for adaptor: AVAssetWriterInputPixelBufferAdaptor) -> CVPixelBufferPool? {
        var attributes: [String: Any] = [:]
        for (key, value) in adaptor.sourcePixelBufferAttributes ?? [:] { attributes[key] = value }
        guard attributes[kCVPixelBufferPixelFormatTypeKey as String] != nil,
              attributes[kCVPixelBufferWidthKey as String] != nil,
              attributes[kCVPixelBufferHeightKey as String] != nil else { return nil }
        if attributes[kCVPixelBufferIOSurfacePropertiesKey as String] == nil {
            attributes[kCVPixelBufferIOSurfacePropertiesKey as String] = [String: Any]()
        }
        var pool: CVPixelBufferPool?
        guard CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &pool)
                == kCVReturnSuccess else { return nil }
        return pool
    }

    /// One frame from `pool`, nil when the pool has none to give.
    public static func frame(from pool: CVPixelBufferPool) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer) == kCVReturnSuccess
        else { return nil }
        return buffer
    }
}
