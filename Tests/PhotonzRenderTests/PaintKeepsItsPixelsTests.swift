import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// A saved picture's paint looks the same after any change to how it is
/// painted fast: the document keeps strokes, not pixels, so every open, undo
/// and redo paints them again, and a change that moved a pixel would quietly
/// change every saved painting. On 2026-10-27 the media were split across
/// cores, a wet wash stopped working out water it could not reach, and the
/// live stroke moved into the layer's own pixels; this layer, every medium and
/// a smudge, wet washes blooming into each other and mouse strokes thinning at
/// their ends, was painted by the code before that and after it, byte for
/// byte the same. The numbers below are that painting's fingerprint.
@Suite("Paint keeps its pixels")
struct PaintKeepsItsPixelsTests {
    private func strokes() -> [BrushStroke] {
        func line(_ a: CGPoint, _ b: CGPoint, _ t0: Double) -> [StrokeSample] {
            (0...24).map { i in
                let f = CGFloat(i) / 24
                return StrokeSample(point: CGPoint(x: a.x + (b.x - a.x) * f + sin(CGFloat(i)) * 3,
                                                   y: a.y + (b.y - a.y) * f), ms: t0 + Double(i) * 16)
            }
        }
        var strokes: [BrushStroke] = []
        let media: [BrushMedium] = [.watercolour, .watercolour, .oil, .pencil, .charcoal, .chalk, .crayon, .marker,
                                    .airbrush, .watercolour, .oil, .watercolour]
        for (n, medium) in media.enumerated() {
            var settings = BrushSettings(medium: medium, values: ["size": Double(18 + n * 7)])
            settings.mode = .paint
            let y = CGFloat(20 + n * 22)
            strokes.append(BrushStroke(samples: line(CGPoint(x: 20, y: y), CGPoint(x: 380, y: y + 40), Double(n) * 400),
                                       settings: settings, colorHex: ["#2060E0", "#D03030", "#30A040"][n % 3],
                                       seed: UInt32(n + 1), startedAt: 100 + Double(n) * 0.7))
        }
        var smudge = BrushSettings(medium: .oil, values: ["size": 30])
        smudge.mode = .smudge
        strokes.append(BrushStroke(samples: line(CGPoint(x: 200, y: 10), CGPoint(x: 220, y: 300), 0),
                                   settings: smudge, colorHex: "#000000", seed: 77, startedAt: 110))
        return strokes
    }

    /// FNV-1a over the raster's bytes.
    private func fingerprint(scale: CGFloat) throws -> UInt64 {
        let image = try #require(PaintRasterizer.replay(PaintContent(strokes: strokes()),
                                                        size: CGSize(width: 400, height: 320), scale: scale))
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try #require(CGContext(data: &data, width: image.width, height: image.height,
                                             bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    @Test func aLayerOfEveryMediumPaintsTheSamePixelsAsBefore() throws {
        // At 2x the same layer was the same too (0xb692_1fd8_cc45_808b);
        // only 1x is held here, to keep the suite quick. Taken again on
        // 2026-10-31, when oil's look was changed on purpose (its ends fray,
        // its sides wander, its ridges clump).
        let print = try fingerprint(scale: 1)
        #expect(print == 0x6279_2497_4301_4321, "0x\(String(print, radix: 16))")
    }
}
