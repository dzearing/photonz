import CoreGraphics
import Foundation
import Testing
@testable import PhotonzRender

/// A floor under the encoder's speed, so a change that makes it ten times
/// slower shows up here rather than in somebody's export.
///
/// One megapixel, not twelve. The real number the feature is judged on is a 12
/// megapixel export in a release build, which is measured and written into the
/// audit; a debug build runs this C about thirty times slower, so a twelve
/// megapixel version of this test would add twenty seconds to every run of the
/// suite to say something the audit says better.
@Suite("WebP encoding speed", .serialized)
struct WebPEncodePerfTests {

    private func megapixel() -> CGImage {
        let side = 1024
        let context = CGContext(data: nil, width: side, height: side,
                                bitsPerComponent: 8, bytesPerRow: side * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 0.12, green: 0.13, blue: 0.16, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        for row in 0..<8 {
            context.setFillColor(CGColor(srgbRed: 0.9, green: 0.92, blue: 0.95, alpha: 1))
            context.fill(CGRect(x: 40, y: row * 128 + 20, width: side - 80, height: 80))
            context.setFillColor(CGColor(srgbRed: 0.2, green: 0.48, blue: 0.95, alpha: 1))
            context.fill(CGRect(x: 64, y: row * 128 + 40, width: 180, height: 40))
        }
        let colors = [CGColor(srgbRed: 1, green: 0.4, blue: 0.1, alpha: 1),
                      CGColor(srgbRed: 0.1, green: 0.2, blue: 0.9, alpha: 1)] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  colors: colors, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: .zero,
                                   end: CGPoint(x: side, y: side), options: [])
        return context.makeImage()!
    }

    /// Each encode timed on this thread's CPU clock against the CPU ruler
    /// taken just before it, since the encoder does all its work on the
    /// calling thread. A stopwatch against a flat 8 s read the lossy encode at
    /// 2.7 to 7.1 s across five full runs on one Mac (2026-10-30), a hair from
    /// failing on unchanged code; beside the ruler the machine's mood divides
    /// out, so the bar can be close enough to catch the encoder getting twice
    /// as slow rather than ten times.
    @Test func oneMegapixelIsQuickBothWays() throws {
        let image = megapixel()
        var lossyBytes = 0, losslessBytes = 0
        let lossy = PerfClock.calibrated(rounds: 1, rulerRounds: 60) { _ in
            lossyBytes = WebPEncoder.encode(image, quality: 0.9)?.count ?? 0
        }
        let lossless = PerfClock.calibrated(rounds: 1, rulerRounds: 60) { _ in
            losslessBytes = WebPEncoder.encode(image, quality: 1)?.count ?? 0
        }
        #expect(lossyBytes > 0)
        #expect(losslessBytes > 0)
        print(String(format: "1MP WebP, s of CPU: lossy 90%% %.2fs (%d bytes), lossless %.2fs (%d bytes)",
                     lossy.subject.reduce(0, +) / 1000, lossyBytes,
                     lossless.subject.reduce(0, +) / 1000, losslessBytes))
        // Alone on the calibration machine, a debug build: lossy 1251 to 1254
        // ms, lossless 810 to 828 (2026-10-30). Twice either fails.
        PerfClock.check("1 MP lossy WebP", ms: lossy.medianMS, rulerMS: lossy.rulerMS,
                        baselineMS: 1250, tolerance: 1.6)
        PerfClock.check("1 MP lossless WebP", ms: lossless.medianMS, rulerMS: lossless.rulerMS,
                        baselineMS: 820, tolerance: 1.6)
    }
}
