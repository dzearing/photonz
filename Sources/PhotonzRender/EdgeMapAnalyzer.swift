import CoreImage
import CoreGraphics
import Foundation
import PhotonzCore

/// Produces a per-image `EdgeMap` by running directional Sobel gradients over the
/// base bitmap and projecting them onto the X and Y axes (|Gx|→X for vertical
/// boundaries, |Gy|→Y for horizontal ones). The render side owns only the CI pass
/// + projection into two 1-D profiles; `EdgeMap`/`EdgeProfile` (core) own the peak
/// finding. Together they answer "where are the strong UI boundaries in this
/// screenshot" for measure snapping (16.5).
public enum EdgeMapAnalyzer {

    /// One shared context — building a `CIContext` per call is expensive and this
    /// runs once per image (results are cached by `EdgeMapCache`).
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// Analyzes `image` and returns its detected edges in top-left image space.
    ///
    /// Uses DIRECTIONAL Sobel rather than combined magnitude (`CIEdges`): the
    /// horizontal gradient (Gx) is projected onto X to find vertical boundaries,
    /// and the vertical gradient (Gy) onto Y to find horizontal boundaries. This
    /// keeps a glyph's vertical stems out of the horizontal profile, so a line of
    /// text peaks cleanly at its cap-line and baseline instead of smearing a
    /// plateau across the whole band (the combined-magnitude failure).
    ///
    /// - threshold / minSeparation: forwarded to the core peak finder.
    public static func analyze(_ image: CGImage,
                               threshold: Double = 0.2,
                               minSeparation: Int = 4) -> EdgeMap {
        guard let (xProfile, yProfile) = profiles(image) else {
            return EdgeMap(width: image.width, height: image.height,
                           verticalEdges: [], horizontalEdges: [])
        }
        return EdgeMap.from(xProfile: xProfile, yProfile: yProfile,
                            width: image.width, height: image.height,
                            threshold: threshold, minSeparation: minSeparation)
    }

    /// Sobel Gx weights (responds to vertical boundaries).
    private static let sobelX = CIVector(values: [-1, 0, 1, -2, 0, 2, -1, 0, 1], count: 9)
    /// Sobel Gy weights (responds to horizontal boundaries).
    private static let sobelY = CIVector(values: [-1, -2, -1, 0, 0, 0, 1, 2, 1], count: 9)

    /// Returns the per-axis edge-magnitude profiles: `x[col] = Σ|Gx|` over rows
    /// (top-left order trivially, X is flip-invariant) and `y[row] = Σ|Gy|` over
    /// columns, flipped into top-left order. Nil if the CI graph can't build.
    static func profiles(_ image: CGImage) -> (x: [Double], y: [Double])? {
        let w = image.width, h = image.height
        guard w > 0, h > 0 else { return nil }
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
        ])?.outputImage?.clampedToExtent() else { return nil }

        func convolve(_ weights: CIVector) -> CIImage? {
            CIFilter(name: "CIConvolution3X3", parameters: [
                kCIInputImageKey: mono,
                "inputWeights": weights,
                "inputBias": 0,
            ])?.outputImage?.cropped(to: bounds)
        }
        guard let gx = convolve(sobelX), let gy = convolve(sobelY) else { return nil }

        // Render each gradient to a single-channel FLOAT buffer so the signed
        // response survives (8-bit would clamp the negative half to zero, halving
        // every edge). `render(toBitmap:)` is bottom-left, so the row profile is
        // built bottom-up then reversed.
        guard let gxBuf = renderFloat(gx, w: w, h: h, bounds: bounds),
              let gyBuf = renderFloat(gy, w: w, h: h, bounds: bounds) else { return nil }

        var xProfile = [Double](repeating: 0, count: w)
        var yBottomUp = [Double](repeating: 0, count: h)
        for row in 0..<h {
            let base = row * w
            var rowSum = 0.0
            for col in 0..<w {
                xProfile[col] += Double(abs(gxBuf[base + col]))
                rowSum += Double(abs(gyBuf[base + col]))
            }
            yBottomUp[row] = rowSum
        }
        return (xProfile, Array(yBottomUp.reversed()))
    }

    /// Renders a CIImage's red channel to a `w*h` array of 32-bit floats.
    private static func renderFloat(_ image: CIImage, w: Int, h: Int, bounds: CGRect) -> [Float]? {
        var buffer = [Float](repeating: 0, count: w * h)
        var ok = true
        buffer.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { ok = false; return }
            context.render(image, toBitmap: base, rowBytes: w * MemoryLayout<Float>.stride,
                           bounds: bounds, format: .Rf, colorSpace: nil)
        }
        return ok ? buffer : nil
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
    public func edgeMap(for ref: ImageRef, store: ImageStore,
                        threshold: Double = 0.2,
                        minSeparation: Int = 4) -> EdgeMap {
        lock.lock()
        if let hit = cache[ref.id] { lock.unlock(); return hit }
        lock.unlock()

        guard let image = store.image(for: ref) else { return .empty }
        let map = EdgeMapAnalyzer.analyze(image, threshold: threshold, minSeparation: minSeparation)
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
