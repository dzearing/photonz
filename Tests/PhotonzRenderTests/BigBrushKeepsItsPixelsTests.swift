import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// A big brush paints the same pixels however fast it is made to paint them.
/// On 2026-10-30 the dab work of every medium was made cheaper so a 500 point
/// brush keeps up with the hand (every-brush-follows-the-pointer-with-no-lag);
/// none of it was allowed to move a pixel, because a saved painting is its
/// strokes and is painted again on every open, undo and redo. These layers, a
/// 160 point stroke of every medium at a zoom of 1.5 over earlier paint, the
/// way it lands and the way the hand sees it while drawing (its thinned end
/// laid again on every move), were painted by the code before that change and
/// after it, byte for byte the same. The numbers are their fingerprints.
@Suite("A big brush keeps its pixels")
struct BigBrushKeepsItsPixelsTests {
    private let size = CGSize(width: 420, height: 240)
    private let scale: CGFloat = 1.5

    private func line(_ a: CGPoint, _ b: CGPoint, _ t0: Double, steps: Int = 30) -> [StrokeSample] {
        (0...steps).map { i in
            let f = CGFloat(i) / CGFloat(steps)
            return StrokeSample(point: CGPoint(x: a.x + (b.x - a.x) * f + sin(CGFloat(i)) * 2,
                                               y: a.y + (b.y - a.y) * f), ms: t0 + Double(i) * 8)
        }
    }

    private func stroke(_ medium: BrushMedium, _ n: Int, size: Double = 160) -> BrushStroke {
        let settings = BrushSettings(medium: medium, values: ["size": size])
        let y = CGFloat(60 + (n % 4) * 40)
        return BrushStroke(samples: line(CGPoint(x: 40, y: y), CGPoint(x: 380, y: y + 30), Double(n) * 300),
                           settings: settings, colorHex: ["#2060E0", "#D03030", "#30A040"][n % 3],
                           seed: UInt32(n + 11), startedAt: 200 + Double(n) * 0.5)
    }

    /// Paint for the big strokes to pick up, bloom into and lie over.
    private var under: [BrushStroke] {
        [stroke(.watercolour, 0, size: 60), stroke(.oil, 1, size: 50), stroke(.charcoal, 2, size: 30)]
    }

    private func fingerprint(_ data: UnsafeRawBufferPointer) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    private func fingerprint(_ image: CGImage) throws -> UInt64 {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try #require(CGContext(data: &data, width: image.width, height: image.height,
                                             bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setBlendMode(.copy)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return data.withUnsafeBytes { fingerprint($0) }
    }

    /// The layer with a big stroke of `medium` landed on the paint under it.
    private func landed(_ medium: BrushMedium) throws -> UInt64 {
        let content = PaintContent(strokes: under + [stroke(medium, 5)])
        return try fingerprint(try #require(PaintRasterizer.replay(content, size: size, scale: scale)))
    }

    /// What the hand sees while drawing it: the overlay as the canvas drives
    /// it, a move at a time, before the release.
    private func live(_ medium: BrushMedium) throws -> UInt64 {
        let cache = PaintRasterCache(budgetBytes: 64 << 20)
        let base = try #require(cache.base(PaintContent(strokes: under), size: size, scale: scale))
        let new = stroke(medium, 5)
        let live = try #require(PaintLayerStroke(stroke: BrushStroke(samples: [], settings: new.settings,
                                                                     colorHex: new.colorHex, seed: new.seed,
                                                                     startedAt: new.startedAt),
                                                 base: base, size: size, scale: scale))
        var walker = BrushPlacement.Walker(settings: new.settings, seed: new.seed,
                                           jitter: PaintRasterizer.jitter(for: new.settings.medium))
        for sample in new.samples.dropLast(4) { live.mark(walker.add(sample)) }
        let all = CGRect(x: 0, y: 0, width: live.width, height: live.height)
        return try fingerprint(try #require(live.picture(of: all)))
    }

    static let media: [BrushMedium] = [.pencil, .charcoal, .chalk, .crayon, .marker, .airbrush, .oil, .watercolour]

    static let landedPrints: [BrushMedium: UInt64] = [
        .pencil: 0x87b1_7584_cdab_9d0b, .charcoal: 0x27c7_fd08_f4e5_6f79, .chalk: 0xf627_938e_02e7_8d2f,
        .crayon: 0x1c18_85fc_8bfb_f044, .marker: 0xed9f_3b18_a81a_88a6, .airbrush: 0x1019_3239_7544_29f4,
        .oil: 0x7f9f_6dc9_31d3_66b5, .watercolour: 0x9e62_ebdb_a69c_a312,
    ]
    static let livePrints: [BrushMedium: UInt64] = [
        .pencil: 0x4e5a_c511_0cb9_af7c, .charcoal: 0x77b8_af8d_f60e_b155, .chalk: 0xda57_317d_0843_d73c,
        .crayon: 0x806b_af2a_fee6_1b3e, .marker: 0xfa21_2d56_a9ef_5a7e, .airbrush: 0x6657_a342_c448_8c58,
        .oil: 0xf116_ca85_9e65_65e0, .watercolour: 0x2681_c5a8_fd9a_1c3d,
    ]

    @Test(arguments: media)
    func aBigStrokeLandsAsItAlwaysHas(_ medium: BrushMedium) throws {
        let print = try landed(medium)
        #expect(print == Self.landedPrints[medium], "\(medium): 0x\(String(print, radix: 16))")
    }

    @Test(arguments: media)
    func aBigStrokeShowsAsItAlwaysHasWhileDrawn(_ medium: BrushMedium) throws {
        let print = try live(medium)
        #expect(print == Self.livePrints[medium], "\(medium): 0x\(String(print, radix: 16))")
    }
}
