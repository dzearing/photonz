// Films one window, cropped to a strip of it, at the display's own rate: the
// camera behind a `filmThumb` step (`PlaytestThumbFilm`).
//
// A snapshot is one picture a quarter of a second after the fact, and the
// segmented thumb's whole move is gone in less. The user saw it fling out of
// its rail on 2026-09-29 while every walk that pressed it was green, so this
// takes every frame the window server composites while the thumb moves.
//
// Probe builds only.
#if PHOTONZ_PLAYTEST
import AppKit
import CoreImage
import CoreMedia
import ScreenCaptureKit

final class PlaytestWindowFilm: NSObject, SCStreamOutput, @unchecked Sendable {
    struct Frame {
        /// Seconds since filming began.
        let time: TimeInterval
        let image: CGImage
    }

    /// The strip kept of each frame, in the frame's pixels, top-left origin.
    private let crop: CGRect
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let queue = DispatchQueue(label: "photonz.playtest.film")
    private let lock = NSLock()
    private var kept: [Frame] = []
    private var began: CMTime?
    private var stream: SCStream?

    init(crop: CGRect) {
        self.crop = crop
    }

    var frames: [Frame] {
        lock.lock()
        defer { lock.unlock() }
        return kept
    }

    /// Starts filming `scWindow`, which is `size` pixels.
    @MainActor func start(_ scWindow: SCWindow, size: CGSize) async throws {
        let config = SCStreamConfiguration()
        config.width = Int(size.width.rounded())
        config.height = Int(size.height.rounded())
        config.minimumFrameInterval = CMTime(value: 1, timescale: 120)
        config.showsCursor = false
        config.queueDepth = 6
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.captureResolution = .best
        let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: scWindow),
                              configuration: config, delegate: nil)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
    }

    @MainActor func stop() async {
        try? await stream?.stopCapture()
        stream = nil
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .screen, let pixels = buffer.imageBuffer else { return }
        // Only frames that carry a new picture: an idle or blank one repeats
        // the last.
        let info = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false)
            as? [[SCStreamFrameInfo: Any]]
        guard let raw = info?.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete else { return }
        let image = CIImage(cvPixelBuffer: pixels)
        // Core Image counts up from the bottom.
        let rect = CGRect(x: crop.minX, y: image.extent.height - crop.maxY,
                          width: crop.width, height: crop.height).intersection(image.extent)
        guard !rect.isEmpty, let strip = context.createCGImage(image, from: rect) else { return }
        let stamp = buffer.presentationTimeStamp
        lock.lock()
        if began == nil { began = stamp }
        let time = began.map { CMTimeGetSeconds(CMTimeSubtract(stamp, $0)) } ?? 0
        kept.append(Frame(time: time, image: strip))
        lock.unlock()
    }

    /// Each column's brightness (0...1) along a band of rows, the middle value
    /// down the band so a letter crossing it does not light a column.
    static func columns(of image: CGImage, rows: ClosedRange<Int>) -> [Double] {
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = bytes.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return [] }
        let band = rows.clamped(to: 0...max(0, height - 1))
        return (0..<width).map { x in
            let values = band.map { y -> Double in
                let at = (y * width + x) * 4
                return (0.2126 * Double(bytes[at]) + 0.7152 * Double(bytes[at + 1])
                    + 0.0722 * Double(bytes[at + 2])) / 255
            }.sorted()
            return values.isEmpty ? 0 : values[values.count / 2]
        }
    }
}
#endif
