import CoreGraphics
import CoreImage
import Foundation
import Testing

// MARK: A performance budget that knows what machine it is on
//
// The render budgets used to be flat numbers, with a second flat number for
// "CI". That is a guess about hardware dressed up as a measurement, and on
// 2026-09-12 it stopped the v0.15.0 release twice: a shared build runner came
// in at 210ms against a flat 200ms bound that the identical code cleared at
// 46ms at home, and at 843ms and 985ms against a 700ms export bound it cleared
// at 113ms. Nothing had got slower. The machine was slower.
//
// So every budget here is now expressed the same way:
//
//     bound = (recorded baseline x tolerance + slack) x how much slower this
//             machine is than the one the baselines were recorded on
//
// and "how much slower" is MEASURED, on this machine, in this process, by
// running a fixed reference workload.
//
// The trap in that idea is picking a reference whose cost does not track the
// thing being measured: scale a GPU-bound render by a CPU-bound probe and the
// bound is noise. The numbers from the failed release say so out loud — the
// same runner was 4.5x slower on an interactive composite and 8x slower on an
// export that forces every pixel back out of the GPU. One scalar cannot be
// both, so there are two yardsticks:
//
//   * `.filterGraph` — a fixed Core Image filter chain over a modest image.
//     This is what a composite, an interactive patch and a zoom tile cost.
//   * `.pixelPush` — 12 million pixels produced and read all the way back.
//     This is what an export costs, and it is the one that blows out on a
//     machine with no real GPU behind it.
//
// Neither yardstick runs a single line of Photonz code, on purpose: if the
// composite path regresses, the subject moves and the reference does not, so
// the gate still fires. They are hardware rulers, not a second copy of the
// thing being measured.
enum MachineSpeed {

    // MARK: The arithmetic (pure, tested in MachineSpeedTests)

    /// How much slower than its recorded baseline a measurement has to be
    /// before it counts as a regression rather than a bad afternoon.
    static let tolerance: Double = 2.5

    /// Absolute headroom added to every budget. The fastest numbers here are
    /// around 6ms, where a tolerance alone leaves a window a few milliseconds
    /// wide that ordinary scheduler noise can cross on its own. The cost is
    /// that a budget under ~16ms of baseline only catches regressions bigger
    /// than 3x; that is the right trade for numbers this small.
    static let jitterSlackMS: Double = 8

    /// The bound a measurement has to stay under.
    /// `factor` is clamped at 1: a probe reading fast must never tighten a
    /// budget below what it was calibrated to allow.
    static func budget(baselineMS: Double, factor: Double) -> Double {
        (baselineMS * tolerance + jitterSlackMS) * max(1, factor)
    }

    /// Whether a budget failing should fail the build.
    /// Set `PHOTONZ_PERF_GATE=report` to collect the numbers without gating:
    /// the release workflow does exactly that, so publishing a build can never
    /// be stopped by a stopwatch.
    static func gates(mode: String?) -> Bool {
        (mode ?? "").lowercased() != "report"
    }

    static var isGating: Bool {
        gates(mode: ProcessInfo.processInfo.environment["PHOTONZ_PERF_GATE"])
    }

    // MARK: The yardsticks

    enum Yardstick: String {
        /// A Core Image filter chain: blur, colour, composite. Tracks the cost
        /// of compositing a document.
        case filterGraph = "filter graph"
        /// 12 megapixels produced and forced all the way back to bytes. Tracks
        /// the cost of writing an export.
        case pixelPush = "pixel push"

        /// What this workload measured on the calibration machine, below.
        var baselineMS: Double {
            switch self {
            case .filterGraph: return 8.0
            case .pixelPush: return 15.4
            }
        }
    }

    // Calibration machine: the arm64 Mac this repo is developed on, measured
    // 2026-09-12 with the suite serialized and nothing else running. Re-record
    // both numbers (they are printed on every run) only when the calibration
    // machine itself changes, and say so in docs/progress/perf.md — moving them
    // to match a slow runner would undo the whole point of this file.

    /// How many times slower this machine is than the calibration machine on
    /// `yardstick`. Measured once per process, the first time it is asked for.
    static func factor(_ yardstick: Yardstick) -> Double {
        switch yardstick {
        case .filterGraph: return filterGraphFactor
        case .pixelPush: return pixelPushFactor
        }
    }

    private static let filterGraphFactor: Double = measure(.filterGraph)
    private static let pixelPushFactor: Double = measure(.pixelPush)

    private static func measure(_ yardstick: Yardstick) -> Double {
        let measured: Double
        switch yardstick {
        case .filterGraph: measured = medianMS(rounds: 7, work: filterGraphRound())
        case .pixelPush: measured = medianMS(rounds: 5, work: pixelPushRound())
        }
        let factor = measured / yardstick.baselineMS
        print(String(format: "[perf] machine yardstick %@ — %.1fms here against %.1fms on the "
                     + "calibration machine, so this machine is %.2fx",
                     yardstick.rawValue, measured, yardstick.baselineMS, factor))
        return factor
    }

    // MARK: The probes

    /// Its own context, with its own fixed options, so that a change to how
    /// the app builds its renderer never moves the ruler.
    private static let probeContext = CIContext(options: [.cacheIntermediates: false])

    /// A textured bitmap — never a flat fill, so nothing downstream can decide
    /// the work is not worth doing.
    private static func texture(width: Int, height: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 0.35, green: 0.45, blue: 0.65, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let step = max(8, width / 40)
        for x in stride(from: 0, to: width, by: step) {
            for y in stride(from: 0, to: height, by: step) {
                let shade = CGFloat((x / step + y / step) % 7) / 7
                context.setFillColor(CGColor(srgbRed: shade, green: 1 - shade, blue: 0.5, alpha: 1))
                context.fill(CGRect(x: x, y: y, width: step / 2, height: step / 2))
            }
        }
        return context.makeImage()!
    }

    // Big enough that the reading is tens of milliseconds: a one-millisecond
    // ruler is mostly per-call overhead and tracks nothing.
    private static let filterGraphSource = CIImage(cgImage: texture(width: 2400, height: 1800))
    private static let pixelPushSource = CIImage(cgImage: texture(width: 4000, height: 3000))

    private static func filterGraphRound() -> () -> Void {
        let source = filterGraphSource
        return {
            let blurred = source
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 20])
                .cropped(to: source.extent)
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 8])
                .cropped(to: source.extent)
            let graded = blurred.applyingFilter("CIColorControls",
                                                parameters: [kCIInputSaturationKey: 0.4,
                                                             kCIInputContrastKey: 1.2])
            let stacked = graded.applyingFilter("CISourceOverCompositing",
                                                parameters: [kCIInputBackgroundImageKey: source])
            let out = probeContext.createCGImage(stacked, from: source.extent)
            _ = out?.dataProvider?.data
        }
    }

    private static func pixelPushRound() -> () -> Void {
        let source = pixelPushSource
        return {
            let shifted = source.applyingFilter("CIColorControls",
                                                parameters: [kCIInputBrightnessKey: 0.02])
            let out = probeContext.createCGImage(shifted, from: source.extent)
            _ = out?.dataProvider?.data
        }
    }

    private static func medianMS(rounds: Int, work: () -> Void) -> Double {
        work()  // warm up: the first Core Image call of a process compiles pipelines.
        var samples: [Double] = []
        let clock = ContinuousClock()
        for _ in 0..<rounds {
            let duration = clock.measure { work() }
            samples.append(Double(duration.components.seconds) * 1000
                           + Double(duration.components.attoseconds) / 1e15)
        }
        samples.sort()
        return samples[samples.count / 2]
    }

    // MARK: The check every budget in RenderPerfTests goes through

    /// Records the measurement, and fails only if it is out of budget for the
    /// speed of THIS machine — and only when gating is on.
    static func check(_ label: String, medianMS: Double, baselineMS: Double,
                      yardstick: Yardstick = .filterGraph,
                      fileID: String = #fileID, filePath: String = #filePath,
                      line: Int = #line, column: Int = #column) {
        let factor = self.factor(yardstick)
        let bound = budget(baselineMS: baselineMS, factor: factor)
        let message = String(format: "%@ — %.1fms against a budget of %.0fms "
                             + "(baseline %.1fms x %.1f tolerance, on a machine measuring %.2fx "
                             + "on the %@ yardstick)",
                             label, medianMS, bound, baselineMS, tolerance, factor,
                             yardstick.rawValue)
        print("[perf] budget: \(message)")
        guard isGating else { return }
        guard medianMS >= bound else { return }
        Issue.record(Comment(rawValue: "\(label) regressed: \(message)"),
                     sourceLocation: SourceLocation(fileID: fileID, filePath: filePath,
                                                    line: line, column: column))
    }
}
