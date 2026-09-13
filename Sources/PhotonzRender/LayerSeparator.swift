import CoreGraphics
import Foundation
import PhotonzCore

/// Takes a picture apart: every run of text in it comes out as its own bitmap,
/// and the picture comes back with the space each run came from filled in.
///
/// The pure decisions live in `PhotonzCore` — `TextRunSweep` says where the
/// runs are, `PatchDecision` says what goes in the hole. This is the part that
/// has to touch pixels: reading the ring around a run, painting the fill, and
/// cutting the letters out of their background so a piece is the WORDS and not
/// a rectangle of button with words on it.
///
/// Full design: `docs/design/separate-into-layers.md`.
public enum LayerSeparator {

    /// One run of text, cut out.
    public struct Piece: Sendable {
        /// Where it sat in the source picture, in image pixels, top-left
        /// origin. Includes the halo (see `haloRatio`).
        public let rect: CGRect
        /// The letters, with everything that was behind them transparent.
        public let image: CGImage
    }

    public struct Result: Sendable {
        /// The picture with every accepted run's space filled in.
        public let background: CGImage
        /// The runs that came out, in reading order.
        public let pieces: [Piece]
        /// How many runs were found but left in the picture, because their
        /// surroundings did not justify a fill or their ink was too faint to
        /// separate from it.
        public let skipped: Int
    }

    /// How much of the visible gap a run is grown by before anything is sampled
    /// or painted, as a fraction of it: two pixels on a 2x capture.
    ///
    /// Without it the antialiased rim of the glyphs sits just OUTSIDE the box.
    /// It would poison the ring reading — a pixel a tenth of the way into a
    /// letter is not ink by the 15% floor, but it is 25 levels off the panel
    /// colour, which is a dozen times the tolerance the flat case runs at — and
    /// it would be left behind in the picture as a faint grey ghost of the word.
    public static let haloRatio = 1.0 / 8

    /// How wide the ring around a piece is, in pixels. Wide enough for a real
    /// reading, narrow enough that it is still the background right THERE.
    public static let ringWidth = 3

    /// How far a run's ink must sit from its background before the app will
    /// claim to know which is which. Under this the cut would be a guess at
    /// what is letter and what is panel, so the run is left where it is.
    public static let minimumContrast = 0.1

    /// Every run of text in `image`, cut out, with `image` repaired behind
    /// them. Nil when the picture cannot be read at all.
    ///
    /// `luma` is the brightness field for this exact image — the one already
    /// cached beside its edge map, so a screenshot that has been measured pays
    /// nothing to be separated.
    public static func separateText(_ image: CGImage, luma: LumaField,
                                    gap: Double = TextLineBounds.defaultGap,
                                    minElement: Double = ElementBounds.defaultMinElement)
        -> Result? {
        let w = image.width, h = image.height
        guard w > 0, h > 0, luma.width == w, luma.height == h else { return nil }
        guard var pixels = read(image) else { return nil }

        let sweep = TextRunSweep.sweep(in: luma, gap: gap, minElement: minElement)
        guard !sweep.runs.isEmpty else {
            return Result(background: image, pieces: [], skipped: 0)
        }

        let halo = max(1, Int((haloRatio * gap).rounded()))
        let bounds = CGRect(x: 0, y: 0, width: w, height: h)
        var pieces: [Piece] = []
        var fills: [(rect: CGRect, fill: PatchFill)] = []
        var skipped = 0

        // Every reading comes off the ORIGINAL pixels: a run is cut and its
        // ring is sampled before a single hole is filled, so one patch can
        // never become another run's idea of what the background was.
        for run in sweep.runs {
            let box = run.insetBy(dx: CGFloat(-halo), dy: CGFloat(-halo))
                .integral.intersection(bounds)
            guard !box.isNull, box.width >= 1, box.height >= 1 else { skipped += 1; continue }
            guard let ring = ring(around: box, in: pixels, width: w, height: h, ink: sweep.ink),
                  let fill = PatchDecision.decide(ring) else { skipped += 1; continue }
            guard let cut = cut(box, from: pixels, width: w, over: fill) else {
                skipped += 1
                continue
            }
            pieces.append(Piece(rect: box, image: cut))
            fills.append((box, fill))
        }

        guard !fills.isEmpty else {
            return Result(background: image, pieces: [], skipped: skipped)
        }
        for (rect, fill) in fills { paint(fill, into: &pixels, width: w, rect: rect) }
        guard let background = makeImage(pixels, width: w, height: h) else { return nil }
        return Result(background: background, pieces: pieces, skipped: skipped)
    }

    // MARK: - The ring

    /// The background just outside `box`: a band `ringWidth` wide on all four
    /// sides, keeping only pixels the sweep did not call ink, so a button's
    /// border or a neighbouring word never votes on what is behind this one.
    static func ring(around box: CGRect, in pixels: [UInt8], width w: Int, height h: Int,
                     ink: InkMask) -> PatchRing? {
        let x0 = Int(box.minX), y0 = Int(box.minY)
        let bw = Int(box.width), bh = Int(box.height)
        guard bw > 0, bh > 0 else { return nil }
        var samples: [PatchRing.Sample] = []
        samples.reserveCapacity(2 * (bw + bh) * ringWidth)

        func take(_ x: Int, _ y: Int) {
            guard x >= 0, y >= 0, x < w, y < h, !ink.isInk(x, y) else { return }
            let i = (y * w + x) * 4
            let a = Double(pixels[i + 3]) / 255
            // Premultiplied on the way in, so a translucent pixel has to be
            // divided back out before it can be compared with an opaque one.
            let scale = a > 0 ? 1 / a : 0
            samples.append(PatchRing.Sample(
                u: (Double(x - x0) + 0.5) / Double(bw),
                v: (Double(y - y0) + 0.5) / Double(bh),
                color: RGBA(r: Double(pixels[i]) / 255 * scale,
                            g: Double(pixels[i + 1]) / 255 * scale,
                            b: Double(pixels[i + 2]) / 255 * scale,
                            a: a)))
        }
        for band in 1...ringWidth {
            for x in (x0 - band)...(x0 + bw - 1 + band) {
                take(x, y0 - band)
                take(x, y0 + bh - 1 + band)
            }
            for y in y0...(y0 + bh - 1) {
                take(x0 - band, y)
                take(x0 + bw - 1 + band, y)
            }
        }
        return samples.isEmpty ? nil : PatchRing(samples: samples)
    }

    // MARK: - Cutting the letters out

    /// `box`'s pixels with the background unmixed back out of them: full alpha
    /// inside a stroke, partial on an antialiased rim, nothing on the panel.
    ///
    /// There is no OCR here, so this is an unmix rather than a trace. Every
    /// pixel is read as `alpha` of some ink over the background that is about to
    /// be painted under it, `alpha` comes from how far the pixel sits from that
    /// background against how far the run's own ink does, and the ink colour is
    /// divided back out — so two-tone or syntax-coloured words keep their own
    /// colours instead of being repainted one flat tone.
    ///
    /// Nil when the run's ink barely differs from its background: the app does
    /// not know which is which, so it does not claim to.
    static func cut(_ box: CGRect, from pixels: [UInt8], width w: Int,
                    over fill: PatchFill) -> CGImage? {
        let x0 = Int(box.minX), y0 = Int(box.minY)
        let bw = Int(box.width), bh = Int(box.height)
        guard bw > 0, bh > 0 else { return nil }

        // How far each pixel sits from what will be behind it, and how far the
        // run's ink does — the brightest tenth of those distances, so one
        // stray pixel cannot set the scale and a thin stroke still reaches it.
        var distance = [Double](repeating: 0, count: bw * bh)
        var background = [RGBA](repeating: RGBA(r: 0, g: 0, b: 0, a: 0), count: bw * bh)
        for y in 0..<bh {
            for x in 0..<bw {
                let i = ((y0 + y) * w + x0 + x) * 4
                let a = Double(pixels[i + 3]) / 255
                let scale = a > 0 ? 1 / a : 0
                let pixel = RGBA(r: Double(pixels[i]) / 255 * scale,
                                 g: Double(pixels[i + 1]) / 255 * scale,
                                 b: Double(pixels[i + 2]) / 255 * scale,
                                 a: a)
                let under = fill.color(u: (Double(x) + 0.5) / Double(bw),
                                       v: (Double(y) + 0.5) / Double(bh))
                background[y * bw + x] = under
                distance[y * bw + x] = max(max(abs(pixel.r - under.r), abs(pixel.g - under.g)),
                                           max(abs(pixel.b - under.b), abs(pixel.a - under.a)))
            }
        }
        // The top fiftieth rather than the very top: a stroke's interior is
        // hundreds of pixels, so this lands inside one, while a single stray
        // saturated pixel cannot set the scale for the whole run.
        let ranked = distance.sorted()
        let contrast = ranked[Int(Double(ranked.count - 1) * 0.98)]
        guard contrast >= minimumContrast else { return nil }

        var out = [UInt8](repeating: 0, count: bw * bh * 4)
        for y in 0..<bh {
            for x in 0..<bw {
                let index = y * bw + x
                let alpha = min(distance[index] / contrast, 1)
                guard alpha > 0.004 else { continue }
                let i = ((y0 + y) * w + x0 + x) * 4
                let a = Double(pixels[i + 3]) / 255
                let scale = a > 0 ? 1 / a : 0
                let under = background[index]
                func ink(_ pixel: Double, _ behind: Double) -> Double {
                    min(max((pixel - (1 - alpha) * behind) / alpha, 0), 1)
                }
                // Premultiplied out, matching the context this is drawn into.
                let r = ink(Double(pixels[i]) / 255 * scale, under.r)
                let g = ink(Double(pixels[i + 1]) / 255 * scale, under.g)
                let b = ink(Double(pixels[i + 2]) / 255 * scale, under.b)
                let o = index * 4
                out[o] = UInt8((r * alpha * 255).rounded())
                out[o + 1] = UInt8((g * alpha * 255).rounded())
                out[o + 2] = UInt8((b * alpha * 255).rounded())
                out[o + 3] = UInt8((alpha * 255).rounded())
            }
        }
        return makeImage(out, width: bw, height: bh)
    }

    // MARK: - Painting the repair

    static func paint(_ fill: PatchFill, into pixels: inout [UInt8], width w: Int,
                      rect: CGRect) {
        let x0 = Int(rect.minX), y0 = Int(rect.minY)
        let bw = Int(rect.width), bh = Int(rect.height)
        guard bw > 0, bh > 0 else { return }
        for y in 0..<bh {
            for x in 0..<bw {
                let color = fill.color(u: (Double(x) + 0.5) / Double(bw),
                                       v: (Double(y) + 0.5) / Double(bh))
                let a = min(max(color.a, 0), 1)
                let i = ((y0 + y) * w + x0 + x) * 4
                func byte(_ value: Double) -> UInt8 {
                    UInt8((min(max(value, 0), 1) * a * 255).rounded())
                }
                pixels[i] = byte(color.r)
                pixels[i + 1] = byte(color.g)
                pixels[i + 2] = byte(color.b)
                pixels[i + 3] = UInt8((a * 255).rounded())
            }
        }
    }

    // MARK: - Bitmaps

    /// `image` as premultiplied sRGB bytes, row-major, top-left origin.
    static func read(_ image: CGImage) -> [UInt8]? {
        let w = image.width, h = image.height
        guard w > 0, h > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let drew = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress,
                  let context = CGContext(data: base, width: w, height: h,
                                          bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return drew ? pixels : nil
    }

    /// Bytes back into a bitmap. The context owns its own storage and the rows
    /// are copied in one at a time against ITS stride, so nothing depends on
    /// the buffer outliving the call or on Core Graphics choosing the row
    /// padding we happened to assume.
    static func makeImage(_ pixels: [UInt8], width w: Int, height h: Int) -> CGImage? {
        guard w > 0, h > 0, pixels.count == w * h * 4,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: w, height: h,
                                      bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return nil }
        let stride = context.bytesPerRow
        pixels.withUnsafeBytes { source in
            guard let base = source.baseAddress else { return }
            for y in 0..<h {
                memcpy(data.advanced(by: y * stride), base.advanced(by: y * w * 4), w * 4)
            }
        }
        return context.makeImage()
    }
}
