import CoreGraphics
import Foundation
import PhotonzCore
import Testing
@testable import PhotonzRender

/// What cutting a piece onto its own layer COSTS, on a picture the size a real
/// camera makes, for a marquee the size somebody actually draws and for one as
/// big as half the photograph.
///
/// This is a stopwatch, not a check, so it does not run with the suite: set
/// `PHOTONZ_BENCH=1` and run it in a RELEASE build, which is the only build
/// whose numbers mean anything, because the passes here are Swift loops over
/// millions of pixels and a debug build runs those many times slower than the
/// app anybody installs.
///
///     Scripts/test.sh -c release --filter SmartCutBench
///
/// It prints a line per phase so a slow number says WHICH pass was slow.
@Suite("How long cutting a piece takes", .serialized, .enabled(if: ProcessInfo.processInfo.environment["PHOTONZ_BENCH"] == "1"))
struct SmartCutBenchTests {

    /// A twelve megapixel photograph: a sky gradient with some detail in it,
    /// so no pass can take a shortcut a flat fill would give it.
    private func photograph(_ w: Int = 4000, _ h: Int = 3000) -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                bytesPerRow: w * 4, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let gradient = CGGradient(colorsSpace: space,
                                  colors: [CGColor(srgbRed: 0.10, green: 0.32, blue: 0.62, alpha: 1),
                                           CGColor(srgbRed: 0.86, green: 0.74, blue: 0.55, alpha: 1)] as CFArray,
                                  locations: [0, 1])!
        context.drawLinearGradient(gradient, start: .zero,
                                   end: CGPoint(x: CGFloat(w), y: CGFloat(h)), options: [])
        context.setFillColor(CGColor(srgbRed: 0.95, green: 0.95, blue: 0.93, alpha: 1))
        for i in 0..<400 {
            let x = CGFloat((i &* 2_654_435) % w)
            let y = CGFloat((i &* 40_503) % h)
            context.fillEllipse(in: CGRect(x: x, y: y, width: 22, height: 22))
        }
        return context.makeImage()!
    }

    private func ms(_ body: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        body()
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }

    /// Runs `body` three times and reports the fastest, so a cold cache or a
    /// stray wake-up does not get reported as the cost of the command.
    private func best(_ label: String, _ body: () -> Void) -> Double {
        let runs = (0..<3).map { _ in ms(body) }
        let fastest = runs.min()!
        let name = label.padding(toLength: 24, withPad: " ", startingAt: 0)
        let each = runs.map { String(format: "%.1f", $0) }.joined(separator: ", ")
        print(String(format: "  \(name) %8.1f ms   (runs: \(each))", fastest))
        return fastest
    }

    /// Every phase of `SmartCut.cut`, timed on its own, so the total has an
    /// explanation attached to it rather than just a number.
    private func breakdown(_ image: CGImage, _ path: CGPath) {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let box = path.boundingBoxOfPath.integral.intersection(bounds)
        var inside: [Bool] = []
        _ = best("mask") { inside = SmartCut.mask(path, over: box) ?? [] }
        var pixels: [UInt8] = []
        _ = best("read pixels") { pixels = LayerSeparator.read(image) ?? [] }
        var spots: [PatchRingWalk.Spot] = []
        _ = best("ring walk") {
            spots = PatchRingWalk.spots(inside: inside, rect: box, clip: bounds,
                                        width: SmartCut.ringWidth, gap: SmartCut.ringGap)
        }
        print("  ring samples: \(spots.count), pixels read: \(pixels.count / 4)")
        let ring = PatchRing(samples: spots.map { spot in
            let i = (spot.y * image.width + spot.x) * 4
            let a = Double(pixels[i + 3]) / 255
            let scale = a > 0 ? 1 / a : 0
            return PatchRing.Sample(u: spot.u, v: spot.v,
                                    color: RGBA(r: Double(pixels[i]) / 255 * scale,
                                                g: Double(pixels[i + 1]) / 255 * scale,
                                                b: Double(pixels[i + 2]) / 255 * scale,
                                                a: a))
        })
        _ = best("decide") { _ = PatchDecision.decide(ring) }
        _ = best("middle") { _ = PatchDecision.middle(of: ring) }
        var extracted: CGImage?
        _ = best("extract piece") { extracted = RegionOps.extracted(image, path: path) }
        if let extracted {
            _ = best("trim piece") { _ = RegionOps.trimmed(extracted) }
        }
        _ = best("patch hole") {
            _ = RegionOps.patched(image, path: path, fill: .solid(RGBA(r: 0.5, g: 0.5, b: 0.5, a: 1)),
                                  box: box)
        }
    }

    @Test("A marquee the size people actually draw, on a 12 megapixel picture")
    func smallMarquee() {
        let image = photograph()
        let path = CGPath(rect: CGRect(x: 1200, y: 900, width: 200, height: 120), transform: nil)
        print("\nSMALL MARQUEE  200x120 over 4000x3000")
        let total = best("SmartCut.cut TOTAL") { _ = SmartCut.cut(image, path: path) }
        breakdown(image, path)
        #expect(total > 0)
    }

    @Test("A marquee over half the picture, which is the worst case anybody can draw")
    func hugeMarquee() {
        let image = photograph()
        // An ellipse whose box is half the photograph: not a rectangle, so the
        // ring has to follow a curve rather than four straight sides.
        let path = CGPath(ellipseIn: CGRect(x: 100, y: 100, width: 3800, height: 1600), transform: nil)
        print("\nHUGE MARQUEE  ellipse in a 3800x1600 box, half of 4000x3000")
        let total = best("SmartCut.cut TOTAL") { _ = SmartCut.cut(image, path: path) }
        breakdown(image, path)
        #expect(total > 0)
    }

    @Test("A marquee round the whole picture, which is as big as one can get")
    func wholePicture() {
        let image = photograph()
        // Nothing outside it to read, so this is also the path that fills the
        // space with nothing and says so.
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: 4000, height: 3000), transform: nil)
        print("\nWHOLE PICTURE  4000x3000 marquee over 4000x3000")
        let total = best("SmartCut.cut TOTAL") { _ = SmartCut.cut(image, path: path) }
        breakdown(image, path)
        #expect(total > 0)
    }
}
