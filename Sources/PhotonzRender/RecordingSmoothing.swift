import CoreGraphics
import CoreImage
import Foundation
import Synchronization

/// Smooths the steps out of a recording's soft gradients when it is SHOWN or
/// WRITTEN OUT, never while it is being recorded.
///
/// The Mac draws a dark translucent window (a terminal's sidebar, a sheet's
/// material) in 8-bit steps, so the screen itself holds a staircase: ten shades
/// down 1300 pixels is ten flat bands about 130 pixels wide, and a recording
/// that copies the screen exactly copies the staircase too. Capturing deeper
/// cannot add shades that were never drawn (measured 2026-11-16 on the user's
/// own recording: 11 levels over 1300 px, the same as a screenshot of it). So
/// this blends them, on the GPU, wherever a recording's frame is turned into a
/// picture: the player, the canvas, the clips on the timeline and a drawn
/// export. The recording file stays a faithful copy of the screen.
///
/// Three passes, all on the GPU:
///
/// 1. **A small copy.** The frame shrunk by a power of two, each pixel the
///    average of the block under it. Bands are hundreds of pixels wide, so
///    nothing about them is lost, and the next pass reads a sixteenth of the
///    pixels.
/// 2. **An edge-aware blur of the small copy.** Each pixel is averaged with 32
///    points spread over a disc `reach` wide, keeping only the points within
///    about two shades of it, so a window edge or a line of text is never
///    averaged in.
/// 3. **Back at full size**, a pixel takes the blurred value only where it is
///    flat itself (no neighbour more than a shade and a half off it, and not a
///    one-pixel line standing off both sides) and the blur moved it by less
///    than the threshold. Into an 8-bit picture it goes with up to a shade of
///    triangular grain either way, so the ramp survives being rounded to 8
///    bits and enlarged after: the eye
///    reads the mean of the grain, which is the smooth value. A pixel the blur
///    did not move is left exactly as it was, grain and all.
///
/// The work is done in the picture's own encoded colours (sRGB, Display P3),
/// so a shade and the grain are both one step of the 8-bit picture it becomes.
public enum RecordingSmoothing {

    private static let on = Mutex(false)

    /// Whether frames of a recording are smoothed where they are shown and
    /// written out. The app sets it from the running release's switch, so a
    /// flip in the Experiments window reaches the next frame read; off, every
    /// frame is exactly what the decoder gave.
    public static var isOn: Bool {
        get { on.withLock { $0 } }
        set { on.withLock { $0 = newValue } }
    }

    /// How far a pixel looks for the band beside it, in pixels of the
    /// recording at its own size. A band of the user's recording was up to 164
    /// pixels wide, and a disc of 96 reaches across the middle of one that
    /// wide from both edges.
    public static let reachInRecordingPixels: CGFloat = 128

    /// The reach for a frame read at `scale` of the recording's own size.
    public static func reach(readAt scale: CGFloat) -> CGFloat {
        guard scale.isFinite, scale > 0 else { return reachInRecordingPixels }
        return max(2, reachInRecordingPixels * min(1, scale))
    }

    /// One shade of an 8-bit channel.
    static let shade: Float = 1 / 255
    /// How far a point may be from the pixel and still count as the same
    /// soft area: two steps of the staircase, and half of a third.
    static let threshold: Float = 2.5 / 255

    // Core Image kernels are immutable once made and Apple documents them as
    // safe to apply from any thread; the type is simply not marked Sendable,
    // so the cache is guarded by hand (as `LiveBackdropPainter` does).
    nonisolated(unsafe) private static var kernels: Kernels?
    nonisolated(unsafe) private static var failed = false
    private static let lock = NSLock()

    private struct Kernels {
        let shrink: CIKernel
        let blur: CIKernel
        let apply: CIKernel
    }

    private static func compiled() -> Kernels? {
        lock.lock()
        defer { lock.unlock() }
        if let kernels { return kernels }
        guard !failed else { return nil }
        // Compiled one to a source: Core Image hands back the last function
        // for every kernel of one source whose arguments match
        // (`LiveBackdropPainter.source`).
        func one(_ name: String, _ body: String) -> CIKernel? {
            (try? CIKernel.kernels(withMetalString: common + body))?.first { $0.name == name }
        }
        guard let shrink = one("smoothing_shrink", shrinkSource),
              let blur = one("smoothing_blur", blurSource),
              let apply = one("smoothing_apply", applySource)
        else {
            failed = true
            return nil
        }
        kernels = Kernels(shrink: shrink, blur: blur, apply: apply)
        return kernels
    }

    /// Whether the kernels compiled on this Mac. Where they did not, every
    /// picture is handed back as it was.
    public static var isAvailable: Bool { compiled() != nil }

    /// Compiles the kernels ahead of the first frame, off the main thread.
    public static func prepare() {
        DispatchQueue.global(qos: .utility).async { _ = compiled() }
    }

    /// `image`, in Core Image's working space (linear light), smoothed, in
    /// the same space. `reach` is in the image's own pixels; `grain` adds up
    /// to a shade either way for a picture about to be rounded to 8 bits.
    ///
    /// The work stays in linear light, with every comparison and the grain
    /// turned into steps of the sRGB curve inside the kernels. Matched into
    /// the picture's own colours and back around the pass instead, through
    /// Core Image's half floats, one pixel of text's edge in ten came out a
    /// shade off; this way about one in a thousand does (measured 2026-11-16
    /// on the user's recording). Pictures passed in as `CGImage`s come back
    /// bit for bit wherever the pass leaves them alone.
    public static func smoothed(_ image: CIImage, reach: CGFloat, grain: Bool) -> CIImage {
        smoothed(image, reach: reach, grain: grain ? 1 : 0, linear: true)
    }

    /// The pass. `linear` says the numbers are linear light, which every
    /// comparison and the grain turn into shades of the sRGB curve first;
    /// otherwise they are already the 8-bit picture's own numbers.
    static func smoothed(_ image: CIImage, reach: CGFloat, grain: Float, linear: Bool) -> CIImage {
        guard let kernels = compiled(), reach >= 1 else { return image }
        let extent = image.extent
        guard extent.width >= 4, extent.height >= 4, extent.width.isFinite, extent.height.isFinite
        else { return image }
        // Worked at the origin.
        let origin = CGAffineTransform(translationX: -extent.minX, y: -extent.minY)
        let placed = image.transformed(by: origin)
        let source = placed.clampedToExtent()
        let size = CGRect(origin: .zero, size: extent.size)
        let curve: Float = linear ? 1 : 0

        // The small copy: shrunk so the disc is about 24 of its pixels across.
        var factor: CGFloat = 1
        while factor < 8, reach / (factor * 2) >= 12 { factor *= 2 }
        let small: CIImage
        let smallSize = CGRect(x: 0, y: 0, width: (size.width / factor).rounded(.up),
                               height: (size.height / factor).rounded(.up))
        if factor > 1 {
            guard let shrunk = kernels.shrink.apply(
                extent: smallSize,
                roiCallback: { _, rect in
                    CGRect(x: rect.minX * factor, y: rect.minY * factor,
                           width: rect.width * factor, height: rect.height * factor).insetBy(dx: -2, dy: -2)
                },
                arguments: [source, Float(factor)])
            else { return image }
            small = shrunk
        } else {
            small = placed
        }

        let smallReach = Float(reach / factor)
        guard let blurred = kernels.blur.apply(
            extent: smallSize,
            roiCallback: { _, rect in rect.insetBy(dx: -CGFloat(smallReach) - 2, dy: -CGFloat(smallReach) - 2) },
            arguments: [small.clampedToExtent(), smallReach, threshold, curve])
        else { return image }

        guard let moved = kernels.apply.apply(
            extent: size,
            roiCallback: { index, rect in
                index == 0
                    ? rect.insetBy(dx: -2, dy: -2)
                    : CGRect(x: rect.minX / factor, y: rect.minY / factor,
                             width: rect.width / factor, height: rect.height / factor).insetBy(dx: -2, dy: -2)
            },
            arguments: [source, blurred.clampedToExtent(), Float(factor), threshold,
                        shade * max(0, grain), curve])
        else { return image }

        return moved.transformed(by: origin.inverted()).cropped(to: extent)
    }

    /// No colour matching at all: a picture's numbers go through as they are,
    /// so a pixel the pass leaves alone comes back bit for bit. (Matched into
    /// linear light and back, about one pixel in a hundred of a line of text
    /// came back a shade off.)
    private static let context = CIContext(options: [
        .cacheIntermediates: false,
        .workingColorSpace: NSNull(),
        .workingFormat: CIFormat.RGBAf.rawValue as NSNumber,
    ])

    /// A picture smoothed into a picture as deep and in the same colours, with
    /// the grain that keeps the ramp through rounding to 8 bits, which the
    /// canvas and an export both do. `reach` in the
    /// picture's own pixels. Nil only when Core Image would not draw it; a Mac
    /// whose GPU cannot compile the kernels gets the picture back as it was.
    public static func smoothedPicture(_ picture: CGImage,
                                       reach: CGFloat = reachInRecordingPixels) -> CGImage? {
        guard isAvailable else { return picture }
        let space = picture.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)
        guard let space, space.model == .rgb else { return picture }
        let input = CIImage(cgImage: picture)
        let out = smoothed(input, reach: reach, grain: 1, linear: false)
        // Written as deep as it came: a 10-bit recording's frame comes from
        // the decoder in half floats, and rounded to 8 bits every edge in it
        // would move by up to half a shade.
        let format: CIFormat = picture.bitsPerComponent > 8 ? .RGBAh : .RGBA8
        return context.createCGImage(out, from: input.extent, format: format, colorSpace: space)
    }

    /// The same pass with no grain, written at 16 bits: what the pass works
    /// out before it is rounded, for measuring how smooth it is.
    public static func deepPicture(_ picture: CGImage,
                                   reach: CGFloat = reachInRecordingPixels) -> CGImage? {
        guard isAvailable else { return nil }
        let space = picture.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)
        guard let space, space.model == .rgb else { return nil }
        let input = CIImage(cgImage: picture)
        let out = smoothed(input, reach: reach, grain: 0, linear: false)
        return context.createCGImage(out, from: input.extent, format: .RGBA16, colorSpace: space)
    }

    /// The share of `picture`'s pixels the pass moves by a quarter of a shade
    /// (one 10-bit code) or more, with no grain. A pixel of a staircase moves
    /// by up to half a shade, the most at the edge of its band: what a top quality export reads off a few frames to
    /// decide whether a recording is written out smoothed or copied as it is.
    /// Nil when the pass cannot run on this Mac.
    public static func changedShare(of picture: CGImage,
                                    reach: CGFloat = reachInRecordingPixels) -> Double? {
        guard let deep = deepPicture(picture, reach: reach) else { return nil }
        guard let before = greens(picture), let after = greens(deep), before.count == after.count,
              !before.isEmpty else { return nil }
        let quarter = 65535.0 / 255 / 4
        var moved = 0
        for i in before.indices where abs(Double(before[i]) - Double(after[i])) + 0.5 >= quarter { moved += 1 }
        return Double(moved) / Double(before.count)
    }

    /// The green channel of every pixel at 16 bits, in the picture's own
    /// colours.
    private static func greens(_ image: CGImage) -> [UInt16]? {
        let w = image.width, h = image.height
        guard w > 0, h > 0, let space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) else {
            return nil
        }
        var raw = [UInt16](repeating: 0, count: w * h * 4)
        let drawn = raw.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 16,
                                      bytesPerRow: w * 8, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                                        | CGBitmapInfo.byteOrder16Little.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        return stride(from: 1, to: raw.count, by: 4).map { raw[$0] }
    }

    // MARK: - The kernels

    static let common = #"""
    #include <CoreImage/CoreImage.h>
    using namespace metal;

    namespace smoothing {
        // A channel of linear light as the sRGB curve writes it, which is
        // where a shade is one step (`curve` 0: the numbers already are).
        inline float3 written(float3 v, float curve) {
            if (curve < 0.5) { return v; }
            float3 a = abs(v);
            float3 lo = a * 12.92;
            float3 hi = 1.055 * pow(a, float3(1.0 / 2.4)) - 0.055;
            return sign(v) * select(hi, lo, a <= float3(0.0031308));
        }
        // How much linear light one written step is worth at `w`.
        inline float3 stepOf(float3 w, float curve) {
            if (curve < 0.5) { return float3(1.0); }
            float3 a = abs(w);
            float3 hi = (2.4 / 1.055) * pow((a + 0.055) / 1.055, float3(1.4));
            return select(hi, float3(1.0 / 12.92), a <= float3(0.04045));
        }
        // How far apart two colours are, in written steps: the biggest
        // difference of a channel.
        inline float apart(float3 a, float3 b) {
            float3 d = abs(a - b);
            return max(d.x, max(d.y, d.z));
        }
        // White noise from 0 to 1 for a pixel: an integer hash of where it is.
        inline float grain(float2 p) {
            uint2 u = uint2(int2(floor(p)) + int2(32768));
            uint h = u.x * 0x8da6b343u ^ u.y * 0xd8163841u;
            h ^= h >> 16; h *= 0x7feb352du;
            h ^= h >> 15; h *= 0x846ca68bu;
            h ^= h >> 16;
            return float(h & 0xffffffu) / 16777216.0;
        }
    }

    """#

    static let shrinkSource = #"""
    // The block of the picture under this pixel of the small copy, averaged:
    // one bilinear read at the centre of each two-by-two inside it.
    extern "C" float4 smoothing_shrink(coreimage::sampler s, float k,
                                       coreimage::destination d) [[stitchable]] {
        float2 corner = (d.coord() - 0.5) * k;
        int count = int(k * 0.5);
        float4 sum = float4(0.0);
        for (int a = 0; a < count; a++) {
            for (int b = 0; b < count; b++) {
                sum += s.sample(s.transform(corner + float2(2 * a + 1, 2 * b + 1)));
            }
        }
        return sum / float(count * count);
    }

    """#

    static let blurSource = #"""
    // The average of 32 points over a disc, golden-angle spaced, keeping only
    // the ones within `limit` written steps of this pixel: a soft area is
    // averaged, and a real edge in reach is left out of it.
    extern "C" float4 smoothing_blur(coreimage::sampler s, float reach, float limit, float curve,
                                     coreimage::destination d) [[stitchable]] {
        float2 p = d.coord();
        float4 c = s.sample(s.transform(p));
        float3 wc = smoothing::written(c.rgb, curve);
        float3 sum = c.rgb;
        float n = 1.0;
        for (int i = 0; i < 32; i++) {
            float r = reach * sqrt((float(i) + 0.5) / 32.0);
            float a = float(i) * 2.39996323;
            float3 v = s.sample(s.transform(p + r * float2(cos(a), sin(a)))).rgb;
            if (smoothing::apart(smoothing::written(v, curve), wc) <= limit) { sum += v; n += 1.0; }
        }
        return float4(sum / n, c.a);
    }

    """#

    static let applySource = #"""
    // Back at full size: a flat pixel takes the blurred value, with grain when
    // it is about to become 8 bits; anything with an edge stays as it is.
    extern "C" float4 smoothing_apply(coreimage::sampler s, coreimage::sampler soft, float k,
                                      float limit, float amount, float curve,
                                      coreimage::destination d) [[stitchable]] {
        const float shade = 1.0 / 255.0;
        float2 p = d.coord();
        float4 keep = s.sample(s.transform(p));
        float3 lc = keep.rgb;
        // Every difference below is read in written steps through the slope
        // of the curve at this pixel: two powers a pixel rather than one for
        // every neighbour (seven times the GPU time, measured 2026-11-16). A
        // neighbour far enough off for the slope to misjudge it is far past
        // every threshold either way.
        float3 c = smoothing::written(lc, curve);
        float3 per = 1.0 / smoothing::stepOf(c, curve);
        float3 l = (s.sample(s.transform(p + float2(-1.0, 0.0))).rgb - lc) * per;
        float3 r = (s.sample(s.transform(p + float2(1.0, 0.0))).rgb - lc) * per;
        float3 u = (s.sample(s.transform(p + float2(0.0, 1.0))).rgb - lc) * per;
        float3 w = (s.sample(s.transform(p + float2(0.0, -1.0))).rgb - lc) * per;
        float3 zero = float3(0.0);
        float edge = max(max(smoothing::apart(l, zero), smoothing::apart(r, zero)),
                         max(smoothing::apart(u, zero), smoothing::apart(w, zero)));
        if (edge > 1.5 * shade) { return keep; }
        // A one-pixel line: both neighbours across it on the same side of it.
        float3 third = float3(1.0 / 3.0);
        float dl = dot(l, third), dr = dot(r, third);
        float du = dot(u, third), dw = dot(w, third);
        float stand = 0.5 * shade;
        if ((dl * dr > 0.0 && min(abs(dl), abs(dr)) > stand) ||
            (du * dw > 0.0 && min(abs(du), abs(dw)) > stand)) { return keep; }
        float3 v = soft.sample(soft.transform(p / k)).rgb;
        float moved = smoothing::apart((v - lc) * per, zero);
        if (moved > limit || moved < 0.1 * shade) { return keep; }
        // Triangular grain, a shade either way at most: it keeps the ramp
        // through a picture enlarged after it, where an even half shade was
        // blended back into steps (the 1280 wide fixture shown at 1.5x read
        // a flat run of 62 px on screen with it, against 155 px unsmoothed).
        float g = (smoothing::grain(p) + smoothing::grain(p + float2(7919.0, 104729.0)) - 1.0) * amount;
        return float4(v + g / per, keep.a);
    }

    """#
}
