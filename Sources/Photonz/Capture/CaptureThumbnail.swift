import Accelerate
import AppKit
import CoreImage
import CryptoKit
import Observation
import PhotonzCore
import PhotonzMedia

/// One capture's picture as the history strip and the capture toast show it:
/// the part a tile draws (`ThumbnailDecodePlan`), decoded small and OFF the
/// main thread, plus what a tile needs to size itself before that lands.
///
/// One of these per capture, each observed on its own, so a poster landing for
/// one recording redraws that recording's tile and nothing else. The store used
/// to keep every picture in one observed dictionary, and every landing redrew
/// every tile on screen.
@MainActor
@Observable
final class CaptureThumbnail {
    /// The full bitmap's size in pixels and its backing scale, which is what
    /// `ThumbnailFit` sizes a tile by. Known before the picture itself for a
    /// screenshot (read from the file's header, no decode) so the tile takes
    /// its final shape at once and the strip never reflows when it lands.
    private(set) var pixelSize: CGSize?
    private(set) var pixelScale: CGFloat = 1
    /// The planned crop, decoded small. Nil until it lands.
    private(set) var image: CGImage?
    /// A recording's length.
    private(set) var duration: TimeInterval?

    @ObservationIgnored var requested = false

    func settle(pixelSize: CGSize?, pixelScale: CGFloat) {
        if self.pixelSize != pixelSize { self.pixelSize = pixelSize }
        if self.pixelScale != pixelScale { self.pixelScale = pixelScale }
    }

    func land(_ loaded: CaptureThumbnails.Loaded) {
        settle(pixelSize: loaded.pixelSize, pixelScale: loaded.pixelScale)
        if let duration = loaded.duration, self.duration != duration { self.duration = duration }
        image = loaded.image
    }
}

/// Making thumbnails, away from the main thread. Everything here is plain
/// ImageIO / Core Graphics / AVFoundation work on values, so it runs on
/// whatever thread the caller is on.
enum CaptureThumbnails {
    struct Loaded: @unchecked Sendable {
        // CGImage is immutable and safe to hand between threads; Core Graphics
        // does not mark it Sendable.
        let image: CGImage?
        let pixelSize: CGSize
        let pixelScale: CGFloat
        let duration: TimeInterval?
    }

    struct Header: Sendable {
        let pixelSize: CGSize
        let pixelScale: CGFloat
    }

    /// A still's size and scale from its header alone: no pixels are decoded.
    static func header(of url: URL) -> Header? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let dpi = props[kCGImagePropertyDPIWidth] as? Double
        return Header(pixelSize: CGSize(width: width, height: height),
                      pixelScale: dpi.map(DisplayScale.pixelScale(forDPI:)) ?? 1)
    }

    /// A screenshot's thumbnail, decoded here and now.
    static func still(at url: URL) -> Loaded? {
        guard let header = header(of: url),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let plan = ThumbnailFit.decodePlan(pixelSize: header.pixelSize)
        let image: CGImage?
        if plan.crop.size == header.pixelSize {
            // The whole picture, shrunk: ImageIO's own thumbnailer, told to
            // finish decoding here rather than on first draw.
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(plan.outputSize.width, plan.outputSize.height),
                kCGImageSourceShouldCacheImmediately: true,
            ]
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        } else {
            image = CGImageSourceCreateImageAtIndex(source, 0, nil).flatMap { render($0, plan) }
        }
        return Loaded(image: image, pixelSize: header.pixelSize, pixelScale: header.pixelScale, duration: nil)
    }

    /// A thumbnail made from a picture already in memory (one just captured).
    static func still(from full: CGImage, pixelScale: CGFloat) -> Loaded {
        let size = CGSize(width: full.width, height: full.height)
        return Loaded(image: render(full, ThumbnailFit.decodePlan(pixelSize: size)),
                      pixelSize: size, pixelScale: pixelScale, duration: nil)
    }

    /// The plan's crop of `full`, drawn at the plan's size into a fresh bitmap,
    /// so the result is decoded and small whatever `full` was.
    static func render(_ full: CGImage, _ plan: ThumbnailDecodePlan) -> CGImage? {
        guard plan.outputSize.width >= 1, plan.outputSize.height >= 1 else { return nil }
        let width = Int(plan.outputSize.width), height = Int(plan.outputSize.height)
        let space = full.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                          | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        context.interpolationQuality = .high
        // Scale the whole picture so the crop fills the bitmap. The crop is in
        // top-left pixels; Core Graphics draws bottom-left, so the picture is
        // pushed down by whatever lies below the crop.
        let k = plan.outputSize.width / plan.crop.width
        let size = CGSize(width: full.width, height: full.height)
        let drawn = CGRect(x: -plan.crop.minX * k,
                           y: -(size.height - plan.crop.maxY) * k,
                           width: size.width * k, height: size.height * k)
        context.draw(full, in: drawn)
        return context.makeImage()
    }

    // MARK: - Recordings

    private static let frameContext = CIContext(options: [.cacheIntermediates: false])

    /// The last frame a recording's stream delivered, as a picture: the whole
    /// frame for an editor to open on, and its tile's thumbnail made from it.
    /// Read once, at Stop, while macOS is still closing the file.
    ///
    /// A stream feeding a recording hands over 4:2:0 video (`420v`), turned
    /// into RGB here on the CPU in one pass (about 10 ms for a 5K screen).
    /// Core Image is the fallback for any other layout: its first use in a run
    /// costs tens of milliseconds of setting up, which is most of what a short
    /// recording takes macOS to close.
    static func lastFrame(_ frame: RecordedFrame) -> CGImage? {
        yuvPicture(frame.buffer) ?? coreImagePicture(frame.buffer)
    }

    /// A recording's tile thumbnail made from a whole frame of it.
    static func recordingThumbnail(from full: CGImage, duration: TimeInterval?) -> Loaded {
        let size = CGSize(width: full.width, height: full.height)
        return Loaded(image: render(full, ThumbnailFit.decodePlan(pixelSize: size)),
                      pixelSize: size, pixelScale: 1, duration: duration)
    }

    private static func colorSpace(of buffer: CVPixelBuffer) -> CGColorSpace? {
        CVBufferCopyAttachments(buffer, .shouldPropagate)
            .flatMap { CVImageBufferCreateColorSpaceFromAttachments($0)?.takeRetainedValue() }
            ?? CGColorSpace(name: CGColorSpace.sRGB)
    }

    private static func yuvPicture(_ buffer: CVPixelBuffer) -> CGImage? {
        let format = CVPixelBufferGetPixelFormatType(buffer)
        let videoRange = format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        guard videoRange || format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
              CVPixelBufferGetPlaneCount(buffer) == 2,
              let space = colorSpace(of: buffer) else { return nil }
        var range = videoRange
            ? vImage_YpCbCrPixelRange(Yp_bias: 16, CbCr_bias: 128, YpRangeMax: 235, CbCrRangeMax: 240,
                                      YpMax: 255, YpMin: 0, CbCrMax: 255, CbCrMin: 0)
            : vImage_YpCbCrPixelRange(Yp_bias: 0, CbCr_bias: 128, YpRangeMax: 255, CbCrRangeMax: 255,
                                      YpMax: 255, YpMin: 0, CbCrMax: 255, CbCrMin: 1)
        let matrixName = CVBufferCopyAttachment(buffer, kCVImageBufferYCbCrMatrixKey, nil) as? String
        // vImage's own ITU-R 601 and 709 matrices, written out: its globals
        // are mutable C state Swift 6 will not read across threads.
        var matrix = matrixName == (kCVImageBufferYCbCrMatrix_ITU_R_601_4 as String)
            ? vImage_YpCbCrToARGBMatrix(Yp: 1, Cr_R: 1.402, Cr_G: -0.7141363, Cb_G: -0.3441363, Cb_B: 1.772)
            : vImage_YpCbCrToARGBMatrix(Yp: 1, Cr_R: 1.5748, Cr_G: -0.4681242, Cb_G: -0.1873243, Cb_B: 1.8556)
        var info = vImage_YpCbCrToARGB()
        guard vImageConvert_YpCbCrToARGB_GenerateConversion(
            &matrix, &range, &info, kvImage420Yp8_CbCr8, kvImageARGB8888,
            vImage_Flags(kvImageNoFlags)) == kvImageNoError else { return nil }

        guard CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        func plane(_ index: Int) -> vImage_Buffer? {
            guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, index) else { return nil }
            return vImage_Buffer(data: base,
                                 height: vImagePixelCount(CVPixelBufferGetHeightOfPlane(buffer, index)),
                                 width: vImagePixelCount(CVPixelBufferGetWidthOfPlane(buffer, index)),
                                 rowBytes: CVPixelBufferGetBytesPerRowOfPlane(buffer, index))
        }
        guard var luma = plane(0), var chroma = plane(1) else { return nil }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let rowBytes = width * 4
        let pixels = UnsafeMutableRawPointer.allocate(byteCount: rowBytes * height, alignment: 64)
        var out = vImage_Buffer(data: pixels, height: vImagePixelCount(height),
                                width: vImagePixelCount(width), rowBytes: rowBytes)
        // ARGB in, B G R A out: what Core Graphics reads as 32-bit little
        // endian with the alpha first.
        let bgra: [UInt8] = [3, 2, 1, 0]
        guard vImageConvert_420Yp8_CbCr8ToARGB8888(&luma, &chroma, &out, &info, bgra, 255,
                                                    vImage_Flags(kvImageNoFlags)) == kvImageNoError,
              let provider = CGDataProvider(dataInfo: nil, data: pixels, size: rowBytes * height,
                                            releaseData: { _, data, _ in data.deallocate() })
        else {
            pixels.deallocate()
            return nil
        }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: rowBytes, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue
                                                    | CGBitmapInfo.byteOrder32Little.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    private static func coreImagePicture(_ buffer: CVPixelBuffer) -> CGImage? {
        let image = CIImage(cvPixelBuffer: buffer)
        return frameContext.createCGImage(image, from: image.extent, format: .RGBA8,
                                          colorSpace: colorSpace(of: buffer))
    }

    /// Files a recording's thumbnail in the poster cache under this exact
    /// file, so the next launch reads it rather than cutting one from the file.
    static func cachePoster(_ loaded: Loaded, for url: URL, stamp: String?) {
        guard let base = posterCacheURL(for: url, stamp: stamp) else { return }
        writePoster(loaded, to: base)
    }

    /// A recording's thumbnail: from the poster cache when this exact file
    /// (by path, size and modification time) has been seen before, otherwise
    /// a frame read from the file and written to the cache for next time.
    static func recording(at url: URL, stamp: String?) async -> Loaded? {
        let cached = posterCacheURL(for: url, stamp: stamp)
        if let cached, let hit = readPoster(cached) { return hit }
        let duration = await VideoExporter.duration(of: url)
        guard let poster = await VideoExporter.posterFrame(of: url) else {
            return Loaded(image: nil, pixelSize: .zero, pixelScale: 1, duration: duration)
        }
        let size = CGSize(width: poster.width, height: poster.height)
        let loaded = Loaded(image: render(poster, ThumbnailFit.decodePlan(pixelSize: size)),
                            pixelSize: size, pixelScale: 1, duration: duration)
        if let cached { writePoster(loaded, to: cached) }
        return loaded
    }

    /// The size and length a recording's cached poster remembers, read without
    /// touching the picture: a tile can take its shape before the picture lands.
    static func cachedRecordingHeader(at url: URL, stamp: String?) -> (Header, TimeInterval)? {
        guard let cached = posterCacheURL(for: url, stamp: stamp),
              let meta = readMeta(cached) else { return nil }
        return (Header(pixelSize: meta.size, pixelScale: 1), meta.duration)
    }

    /// Where posters are kept: the app's own caches folder, never the person's
    /// capture folder.
    static let posterCache: URL? = {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        return caches.appendingPathComponent(Bundle.main.bundleIdentifier ?? "Photonz", isDirectory: true)
            .appendingPathComponent("CapturePosters", isDirectory: true)
    }()

    static func posterCacheURL(for url: URL, stamp: String?) -> URL? {
        guard let posterCache, let stamp else { return nil }
        let key = SHA256.hash(data: Data("\(url.standardizedFileURL.path)|\(stamp)".utf8))
            .map { String(format: "%02x", $0) }.joined()
        return posterCache.appendingPathComponent(String(key.prefix(32)))
    }

    private struct Meta: Codable {
        var width: Double
        var height: Double
        var duration: Double
        var size: CGSize { CGSize(width: width, height: height) }
    }

    private static func readMeta(_ base: URL) -> Meta? {
        guard let data = try? Data(contentsOf: base.appendingPathExtension("json")) else { return nil }
        return try? JSONDecoder().decode(Meta.self, from: data)
    }

    private static func readPoster(_ base: URL) -> Loaded? {
        guard let meta = readMeta(base),
              let source = CGImageSourceCreateWithURL(base.appendingPathExtension("jpg") as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(
                source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { return nil }
        return Loaded(image: image, pixelSize: meta.size, pixelScale: 1, duration: meta.duration)
    }

    private static func writePoster(_ loaded: Loaded, to base: URL) {
        guard let image = loaded.image, let dir = posterCache else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let jpg = base.appendingPathExtension("jpg")
        guard let destination = CGImageDestinationCreateWithURL(
            jpg as CFURL, "public.jpeg" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image,
                                   [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return }
        let meta = Meta(width: loaded.pixelSize.width, height: loaded.pixelSize.height,
                        duration: loaded.duration ?? 0)
        try? JSONEncoder().encode(meta).write(to: base.appendingPathExtension("json"), options: .atomic)
    }
}
