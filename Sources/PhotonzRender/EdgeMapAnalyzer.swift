import CoreImage
import CoreGraphics
import Foundation
import PhotonzCore

/// Produces a per-image `EdgeMap` by running directional Sobel gradients over the
/// base bitmap. The render side owns only the CI pass that yields the |Gx| and
/// |Gy| magnitude fields (in top-left row order); `EdgeMap` (core) owns the
/// block-summed storage and the windowed peak queries that answer "which UI
/// boundaries does this ruler line cross". Directional gradients matter: |Gy|
/// alone finds text tops/baselines without glyph stems polluting the signal, and
/// |Gx| alone finds vertical borders without underlines polluting theirs.
public enum EdgeMapAnalyzer {

    /// One shared context — building a `CIContext` per call is expensive and this
    /// runs once per image (results are cached by `EdgeMapCache`).
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// Sobel Gx weights (responds to vertical boundaries).
    private static let sobelX = CIVector(values: [-1, 0, 1, -2, 0, 2, -1, 0, 1], count: 9)
    /// Sobel Gy weights (responds to horizontal boundaries).
    private static let sobelY = CIVector(values: [-1, -2, -1, 0, 0, 0, 1, 2, 1], count: 9)

    /// Analyzes `image` and returns its locally-queryable edge map.
    public static func analyze(_ image: CGImage) -> EdgeMap {
        let w = image.width, h = image.height
        guard w > 0, h > 0 else { return .empty }
        let bounds = CGRect(x: 0, y: 0, width: w, height: h)

        // Work on luminance so coloured text/UI is treated by brightness contrast.
        let input = CIImage(cgImage: image)
        let lumaVector = CIVector(x: 0.299, y: 0.587, z: 0.114, w: 0)
        guard let mono = CIFilter(name: "CIColorMatrix", parameters: [
            kCIInputImageKey: input,
            "inputRVector": lumaVector,
            "inputGVector": lumaVector,
            "inputBVector": lumaVector,
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ])?.outputImage?.clampedToExtent() else { return .empty }

        func convolve(_ weights: CIVector) -> CIImage? {
            CIFilter(name: "CIConvolution3X3", parameters: [
                kCIInputImageKey: mono,
                "inputWeights": weights,
                "inputBias": 0,
            ])?.outputImage?.cropped(to: bounds)
        }
        guard let gxImage = convolve(sobelX), let gyImage = convolve(sobelY),
              // Float buffers so the signed response survives (8-bit would clamp
              // the negative half to zero, halving every edge).
              let gxBuf = renderFloat(gxImage, w: w, h: h, bounds: bounds),
              let gyBuf = renderFloat(gyImage, w: w, h: h, bounds: bounds) else {
            return .empty
        }

        // |G| magnitudes. NOTE: unlike CIContext's coordinate SPACE (bottom-left),
        // `render(toBitmap:)` writes buffer rows top-down (CGImage layout), so row
        // 0 is already the image's TOP row — no flip. Verified by an asymmetric
        // fixture: a flip here relocates a rect's edges to mirrored rows.
        var gx = [Double](repeating: 0, count: w * h)
        var gy = [Double](repeating: 0, count: w * h)
        gx.withUnsafeMutableBufferPointer { dstX in
            gy.withUnsafeMutableBufferPointer { dstY in
                gxBuf.withUnsafeBufferPointer { srcX in
                    gyBuf.withUnsafeBufferPointer { srcY in
                        for i in 0..<(w * h) {
                            dstX[i] = Double(abs(srcX[i]))
                            dstY[i] = Double(abs(srcY[i]))
                        }
                    }
                }
            }
        }

        // Landing refinement wants PERCEPTUAL luma ("does this row read as clean
        // background to a human"), so compute it on the CPU from the sRGB-encoded
        // pixels — gamma-encoded values are already perceptual, and it sidesteps
        // a third CI render. 0...1 units; top-left row order by construction.
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        var luma: [Double]?
        let drewImage = rgba.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress,
                  let cg = CGContext(data: base, width: w, height: h,
                                     bitsPerComponent: 8, bytesPerRow: w * 4,
                                     space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            cg.draw(image, in: bounds)
            return true
        }
        if drewImage {
            var l = [Double](repeating: 0, count: w * h)
            rgba.withUnsafeBufferPointer { src in
                l.withUnsafeMutableBufferPointer { dst in
                    for i in 0..<(w * h) {
                        let o = i * 4
                        dst[i] = (0.299 * Double(src[o]) + 0.587 * Double(src[o + 1])
                                  + 0.114 * Double(src[o + 2])) / 255
                    }
                }
            }
            luma = l
        }

        return EdgeMap(width: w, height: h, gxMagnitude: gx, gyMagnitude: gy, luma: luma)
    }

    /// Renders a CIImage's red channel to a `w*h` array of 32-bit floats.
    private static func renderFloat(_ image: CIImage, w: Int, h: Int, bounds: CGRect) -> [Float]? {
        var buffer = [Float](repeating: 0, count: w * h)
        buffer.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            context.render(image, toBitmap: base, rowBytes: w * MemoryLayout<Float>.stride,
                           bounds: bounds, format: .Rf, colorSpace: nil)
        }
        return buffer
    }
}

/// Caches the `EdgeMap` for each `ImageRef`, since the edge pass is a full-image
/// GPU + CPU sweep and the base bitmap never changes for a given ref. Thread-safe;
/// shared by the app so every measure drag reuses one analysis per image.
public final class EdgeMapCache: @unchecked Sendable {
    private var cache: [UUID: EdgeMap] = [:]
    private let lock = NSLock()

    public init() {}

    /// Returns the cached map for `ref`, computing (and caching) it on first use.
    /// Returns `.empty` if the ref has no registered bitmap.
    public func edgeMap(for ref: ImageRef, store: ImageStore) -> EdgeMap {
        lock.lock()
        if let hit = cache[ref.id] { lock.unlock(); return hit }
        lock.unlock()

        guard let image = store.image(for: ref) else { return .empty }
        let map = EdgeMapAnalyzer.analyze(image)
        lock.lock()
        cache[ref.id] = map
        lock.unlock()
        return map
    }

    public func invalidate(_ ref: ImageRef) {
        lock.lock()
        cache[ref.id] = nil
        lock.unlock()
    }
}
