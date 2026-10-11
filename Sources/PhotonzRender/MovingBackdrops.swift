import CoreGraphics
import CoreImage
import Foundation
import PhotonzCore

// The looks a title backdrop moves with (task
// `title-backgrounds-move-gradients-grain-and-the-r`): a mesh fill drifting,
// and grain over what a layer paints. Both are read at the moment drawn
// (`Layer.drawnAtMS`), never baked: the shape's own raster stays cached and the
// moving part is laid over it each frame.

/// A mesh paint as pixels.
///
/// The blend is worked out on a small grid, its long side `gridLongSide`
/// samples, in floating point, and Core Image enlarges it to the box. A blend
/// this soft has nothing in it a grid that size misses, and the grid is what
/// keeps a full frame drifting mesh to a fraction of a millisecond of work a
/// frame. Floating point, so enlarging it adds no steps of its own.
public enum MeshPainter {

    /// How many samples the grid has along its long side. A point's colour
    /// falls off over about four tenths of the frame's height, so a cell of a
    /// twentieth of a 1080 line frame changes by well under a level of 255
    /// across it, and enlarging the grid smoothly loses nothing.
    public static let gridLongSide = 96

    /// The grid's size for a box of `size`.
    static func gridSize(for size: CGSize) -> (width: Int, height: Int) {
        let long = max(size.width, size.height, 1)
        let scale = CGFloat(gridLongSide) / long
        return (max(2, Int((size.width * scale).rounded())), max(2, Int((size.height * scale).rounded())))
    }

    /// Premultiplied floating point samples of the mesh `ms` into its drift,
    /// row 0 at the TOP of the box: `Paint.meshColor` at the middle of each
    /// cell.
    ///
    /// A point's fall-off is a gaussian, which comes apart into a part across
    /// and a part down, so each point's weight along every column and every
    /// row is worked out once and a sample is a handful of multiplications.
    /// Normalised by the total, exactly as `Paint.meshColor` is, so the two
    /// agree to the last bit of a float.
    static func samples(_ paint: Paint, size: CGSize, atMS ms: Int,
                        grid: (width: Int, height: Int)) -> [Float] {
        let points = paint.meshPoints(atMS: ms)
        let width = grid.width, height = grid.height
        var data = [Float](repeating: 0, count: width * height * 4)
        guard !points.isEmpty else { return data }
        let short = max(min(size.width, size.height), 1)
        let sx = Float(size.width / short), sy = Float(size.height / short)
        let spread = Float(2 * Paint.meshReach * Paint.meshReach)
        let count = points.count
        var across = [Float](repeating: 0, count: count * width)
        var down = [Float](repeating: 0, count: count * height)
        var colours = [Float](repeating: 0, count: count * 4)
        for (index, point) in points.enumerated() {
            let cx = Float(point.center.x), cy = Float(point.center.y)
            for x in 0..<width {
                let d = ((Float(x) + 0.5) / Float(width) - cx) * sx
                across[index * width + x] = exp(-d * d / spread)
            }
            for y in 0..<height {
                let d = ((Float(y) + 0.5) / Float(height) - cy) * sy
                down[index * height + y] = exp(-d * d / spread)
            }
            colours[index * 4] = Float(point.color.r)
            colours[index * 4 + 1] = Float(point.color.g)
            colours[index * 4 + 2] = Float(point.color.b)
            colours[index * 4 + 3] = Float(min(max(point.color.a, 0), 1))
        }
        across.withUnsafeBufferPointer { across in
            down.withUnsafeBufferPointer { down in
                colours.withUnsafeBufferPointer { colours in
                    data.withUnsafeMutableBufferPointer { out in
                        for y in 0..<height {
                            for x in 0..<width {
                                var r: Float = 0, g: Float = 0, b: Float = 0, a: Float = 0, total: Float = 0
                                for index in 0..<count {
                                    let w = across[index * width + x] * down[index * height + y]
                                    r += colours[index * 4] * w
                                    g += colours[index * 4 + 1] * w
                                    b += colours[index * 4 + 2] * w
                                    a += colours[index * 4 + 3] * w
                                    total += w
                                }
                                guard total > 0 else { continue }
                                // Premultiplied, which is what the bitmap is.
                                let at = (y * width + x) * 4, alpha = a / total
                                out[at] = r / total * alpha
                                out[at + 1] = g / total * alpha
                                out[at + 2] = b / total * alpha
                                out[at + 3] = alpha
                            }
                        }
                    }
                }
            }
        }
        return data
    }

    /// The mesh across a box of `size`, origin at nought, in Core Image's
    /// bottom-left space. Nil for a paint with no points.
    public static func image(_ paint: Paint, size: CGSize, atMS ms: Int) -> CIImage? {
        guard size.width >= 1, size.height >= 1 else { return nil }
        let grid = gridSize(for: size)
        let data = samples(paint, size: size, atMS: ms, grid: grid)
        let row = grid.width * 4
        // Rows top first, the way Core Image reads a bitmap whatever its own
        // coordinates say.
        let bytes = data.withUnsafeBufferPointer { Data(buffer: $0) }
        let small = CIImage(bitmapData: bytes, bytesPerRow: row * MemoryLayout<Float>.size,
                            size: CGSize(width: grid.width, height: grid.height), format: .RGBAf,
                            colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        // Enlarged from the middle of each sample to the middle of each pixel,
        // held at the edges so the box's border is the blend and not a fade.
        let sx = size.width / CGFloat(grid.width), sy = size.height / CGFloat(grid.height)
        return small.clampedToExtent()
            .samplingLinear()
            .transformed(by: CGAffineTransform(scaleX: sx, y: sy))
            .cropped(to: CGRect(origin: .zero, size: size))
    }

    /// The mesh as a still picture, row 0 at the top: what a shape's cached
    /// raster, a swatch or a frame's surface draws when it is not moving.
    public static func cgImage(_ paint: Paint, size: CGSize, atMS ms: Int = 0) -> CGImage? {
        guard size.width >= 1, size.height >= 1 else { return nil }
        let grid = gridSize(for: size)
        let data = samples(paint, size: size, atMS: ms, grid: grid)
        var bytes = [UInt8](repeating: 0, count: data.count)
        for index in data.indices { bytes[index] = UInt8((min(max(data[index], 0), 1) * 255).rounded()) }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: grid.width, height: grid.height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: grid.width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true,
                       intent: .defaultIntent)
    }
}

/// Film grain over what a layer paints (`GrainEffect`).
///
/// Every pixel lands somewhere between the picture a little darker and the
/// picture a little lighter, picked by uniform noise, so it neither lightens
/// nor darkens on average and stays exactly the layer's own shape. Worked on
/// stored (sRGB) values rather than on light, so a dark backdrop gets the same
/// visible grain as a bright one. A fresh pattern every frame of a moving
/// picture; a still one keeps one.
public enum GrainFilter {

    /// How far the noise reaches at 100%, either side of the picture, in
    /// stored values: very heavy. The default 25% is about eight levels of 255.
    public static let fullReach: CGFloat = 0.12

    /// How long one pattern lasts: a frame at sixty a second.
    public static let frameMS = 16

    /// `image` with grain over it, as strong as `amount` percent, the pattern
    /// for the moment `atMS` (nil for a still picture). `linearLight` says
    /// whether the picture's numbers are light, in which case they are taken
    /// to stored values for the noise and back.
    /// How big one grain is: two pixels of a 1080 line frame, and the same
    /// share of any other. Measured on 2026-10-10: one pixel grain at 1080p is
    /// wiped out by the movie encoder at the app's own bitrate, and the bands
    /// it was there to break up come straight back; two pixel grain survives
    /// (`GrainBandingExportTests`).
    public static func cell(forFrame size: CGSize) -> CGFloat {
        max(1, min(size.width, size.height) / 540)
    }

    public static func grained(_ image: CIImage, amount: Double, atMS ms: Int?,
                               linearLight: Bool, cell: CGFloat = 1) -> CIImage {
        guard amount > 0, !image.extent.isInfinite, !image.extent.isEmpty else { return image }
        let reach = fullReach * CGFloat(min(amount, 100) / 100)
        // A fresh stretch of the generator's endless noise each frame, far
        // enough along that no two frames share a row.
        let frame = (ms ?? 0) / frameMS
        let shift = CGPoint(x: CGFloat((frame &* 7919) % 4096), y: CGFloat((frame &* 104_729) % 4096))
        let noise = CIFilter(name: "CIRandomGenerator")?.outputImage ?? CIImage(color: .gray)
        // The generator's ALPHA is the uniform number: its colour is stored
        // premultiplied by that alpha, so read straight it is not uniform.
        let pick = noise
            .transformed(by: CGAffineTransform(translationX: -shift.x, y: -shift.y))
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            ])
            .samplingLinear()
            .transformed(by: CGAffineTransform(scaleX: max(1, cell), y: max(1, cell)))
            .cropped(to: image.extent)
        let base = linearLight ? image.applyingFilter("CILinearToSRGBToneCurve") : image
        let mixed = shifted(base, by: reach).applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: shifted(base, by: -reach),
            kCIInputMaskImageKey: pick,
        ]).cropped(to: image.extent)
        return linearLight ? mixed.applyingFilter("CISRGBToneCurveToLinear") : mixed
    }

    /// The picture with `amount` added to its colour. The matrix works on
    /// colour taken out of its alpha and puts it back after, so where the
    /// layer only half paints the grain is only half as strong, and a soft
    /// edge is not given a hard rim.
    private static func shifted(_ image: CIImage, by amount: CGFloat) -> CIImage {
        image.applyingFilter("CIColorMatrix", parameters: [
            "inputBiasVector": CIVector(x: amount, y: amount, z: amount, w: 0),
        ])
    }
}
