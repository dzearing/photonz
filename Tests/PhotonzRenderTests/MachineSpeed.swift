import CoreGraphics
import CoreImage
import Foundation
@testable import PhotonzRender
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
//   * `.pixelPush` — ten layers, turned and shadowed, stacked onto a 48
//     megapixel canvas and read all the way back. This is what an export
//     costs, and it is the one that blows out on a machine with no real GPU
//     behind it.
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
    ///
    /// A gate read beside a yardstick taken in the same round can pass a
    /// tighter `tolerance` and less `slackMS`: the room above was for a machine
    /// busier at the moment of the reading than when the factor was taken,
    /// and the yardstick divides that out. Tight enough that twice the work
    /// fails is what lets such a gate catch a doubling (2026-10-30).
    static func budget(baselineMS: Double, factor: Double,
                       tolerance: Double = tolerance, slackMS: Double = jitterSlackMS) -> Double {
        (baselineMS * tolerance + slackMS) * max(1, factor)
    }

    /// The middle of a set of readings. Used instead of a mean so that one
    /// round where the thread was taken away cannot decide a whole gate.
    static func median(of values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.sorted()[values.count / 2]
    }

    /// What the subject would have read on the calibration machine, worked out
    /// from a yardstick taken back to back with it INSIDE every round.
    ///
    /// `factor(_:)` above is measured once, when the process starts. That says
    /// how fast the hardware is, and it was enough while the budgets it fed
    /// were the only thing running. Inside the full suite — 600-odd suites in
    /// one process, running in parallel — the number that moves is not the
    /// hardware, it is how much of the machine this test has at the moment it
    /// runs, and a reading taken at process start knows nothing about that.
    /// The same test then reads 5.3ms alone and 8.9ms in the suite against a
    /// budget scaled by a factor measured while it was still quiet.
    ///
    /// Taking the yardstick in the same round fixes that: whatever a round is
    /// competing with slows both readings, and dividing one by the other
    /// cancels it. The subject has to get genuinely more expensive, relative to
    /// a fixed piece of work on the same core, before this number moves.
    ///
    /// Rounds where the yardstick read nothing are dropped; if that leaves
    /// none, the answer is infinity, so a comparison that never happened fails
    /// rather than passes.
    static func normalizedMS(subject: [Double], reference: [Double],
                             referenceBaselineMS: Double) -> Double {
        let ratios = zip(subject, reference)
            .filter { $0.1 > 0 }
            .map { $0.0 / $0.1 }
        guard let typical = median(of: ratios) else { return .infinity }
        return typical * referenceBaselineMS
    }

    /// How far off its own calibration number the yardstick has to read before
    /// an interleaved reading stops meaning anything. Dividing by the ruler
    /// cancels a busy machine only while the ruler and the subject are slowed
    /// by the same thing, and at three times its own number the ruler is
    /// mostly measuring whatever else the machine is doing.
    static let untrustedYardstickFactor: Double = 3

    enum Reading: Equatable {
        case withinBudget
        case overBudget
        /// Over budget, but beside a yardstick so far off its own number that
        /// nobody can say whether the subject or the machine moved.
        case untrusted
    }

    /// What an interleaved reading says. A reading inside its budget passes
    /// however busy the machine was; one over it fails unless the yardstick
    /// taken with it says the machine was too busy to judge. A comparison that
    /// never happened is never excused.
    static func reading(normalizedMS: Double, boundMS: Double,
                        yardstickMS: Double, yardstickBaselineMS: Double) -> Reading {
        guard normalizedMS.isFinite else { return .overBudget }
        guard normalizedMS >= boundMS else { return .withinBudget }
        guard yardstickMS.isFinite,
              yardstickMS <= yardstickBaselineMS * untrustedYardstickFactor else { return .untrusted }
        return .overBudget
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
        /// Ten layers stacked onto a 2x-sized canvas and forced all the way
        /// back to bytes: 48 megapixels out, the way an export at 2x is 48
        /// megapixels out. Tracks the cost of writing a file.
        case pixelPush = "pixel push"
        /// Ten small layers, one turned and one blurred, laid on a 1080p
        /// ground and rendered into a bitmap the way the canvas renders a
        /// frame. Tracks the cost of drawing one frame of a playing edit.
        case frame = "1080p frame"

        /// What this workload measured on the calibration machine, below.
        var baselineMS: Double {
            switch self {
            case .filterGraph: return 8.0
            case .pixelPush: return 146.0
            case .frame: return 3.3
            }
        }
    }

    // Calibration machine: the arm64 Mac this repo is developed on, measured
    // 2026-09-12 with the suite serialized and nothing else running. The pixel
    // push number was re-recorded on 2026-10-13 on the same machine, when its
    // workload changed shape (see `pixelPushRound`), not because a runner moved. The
    // 1080p frame number was recorded on 2026-10-14 on the same machine, read
    // beside a frame inside `checkFrames` (alone it reads 3.1 to 3.3ms). Re-record
    // both numbers (they are printed on every run) only when the calibration
    // machine itself changes, and say so in docs/progress/perf.md — moving them
    // to match a slow runner would undo the whole point of this file.

    /// How many times slower this machine is than the calibration machine on
    /// `yardstick`. Measured once per process, the first time it is asked for.
    static func factor(_ yardstick: Yardstick) -> Double {
        switch yardstick {
        case .filterGraph: return filterGraphFactor
        case .pixelPush: return pixelPushFactor
        case .frame: return frameFactor
        }
    }

    private static let filterGraphFactor: Double = measure(.filterGraph)
    private static let pixelPushFactor: Double = measure(.pixelPush)
    private static let frameFactor: Double = measure(.frame)

    /// One round of the yardstick's fixed workload, for a caller that wants to
    /// take it back to back with its own subject rather than at process start.
    static func round(for yardstick: Yardstick) -> () -> Void {
        switch yardstick {
        case .filterGraph: return filterGraphRound()
        case .pixelPush: return pixelPushRound()
        case .frame: return frameRound()
        }
    }

    private static func measure(_ yardstick: Yardstick) -> Double {
        let measured: Double
        switch yardstick {
        case .filterGraph: measured = medianMS(rounds: 7, work: filterGraphRound())
        case .pixelPush: measured = medianMS(rounds: 5, work: pixelPushRound())
        case .frame: measured = medianMS(rounds: 15, work: frameRound())
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
    private static let pixelPushCanvas = CIImage(cgImage: texture(width: 4000, height: 3000))
        .transformed(by: CGAffineTransform(scaleX: 2, y: 2))
    private static let pixelPushLayer = CIImage(cgImage: texture(width: 1600, height: 1200))
        .transformed(by: CGAffineTransform(scaleX: 2, y: 2))

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

    /// Deliberately shaped like an export: a 48 megapixel canvas with ten
    /// layers stacked onto it, every other one turned and each with a soft
    /// shadow under it, forced out to bytes.
    ///
    /// Twice this ruler has been the wrong shape and twice it showed up the
    /// same way, as the export budget failing CI on unchanged code. First it
    /// read 12 megapixels back from a trivial graph and measured a shared
    /// runner at 3.4x while the export came in at 8.2x. Then it built one big
    /// picture with one blur, and from 2026-09-13 to 2026-10-13 read the GitHub
    /// VM at 2.6 to 4.3x while the export on the same run read 5.4 to 11x, so
    /// the budget failed about half the runs it was reached in. Measured side
    /// by side on three of those VMs and on the calibration machine
    /// (2026-10-13), the export took 2.0 to 2.1 times longer against that
    /// ruler on the VM than at home, and 1.2 to 1.5 times against this one.
    /// What that hardware is slow at is laying many big layers on top of each
    /// other, so the ruler has to lay many big layers too.
    private static func pixelPushRound() -> () -> Void {
        let canvas = pixelPushCanvas
        let layer = pixelPushLayer
        let big = canvas.extent
        return {
            var stacked = canvas
            for i in 0..<10 {
                var placed = layer
                if i.isMultiple(of: 2) {
                    placed = placed.transformed(by: CGAffineTransform(rotationAngle: .pi / 8))
                }
                placed = placed.transformed(by: CGAffineTransform(translationX: CGFloat(300 + i * 500),
                                                                  y: CGFloat(200 + i * 350)))
                let shadow = placed
                    .applyingFilter("CIColorMatrix",
                                    parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.4)])
                    .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 40])
                stacked = placed.composited(over: shadow.composited(over: stacked))
            }
            let out = probeContext.createCGImage(stacked.cropped(to: big), from: big)
            _ = out?.dataProvider?.data
        }
    }

    private static let frameGround = CIImage(cgImage: texture(width: 1920, height: 1080))
    private static let frameLayer = CIImage(cgImage: texture(width: 480, height: 200))

    /// Shaped like one frame of a playing edit, because the frame budgets are
    /// what it is divided into, and on 2026-10-14 the filter graph proved the
    /// wrong shape for them. With another process keeping the GPU busy, a
    /// headline flipping up by letter read 2.06 times the filter graph in the
    /// same round against 1.29 idle, so a budget divided by it still failed on
    /// unchanged code. Beside this ruler the same frame read 1.68 idle and 1.54
    /// to 1.70 loaded, and a 2.5D frame 1.27 idle and 0.89 to 1.00 loaded.
    /// What a busy GPU takes from a frame is the turnaround of a modest render
    /// into a bitmap, not throughput on one big blur, so the ruler is a modest
    /// render into a bitmap.
    private static func frameRound() -> () -> Void {
        let ground = frameGround
        let layer = frameLayer
        let size = ground.extent
        let rowBytes = Int(size.width) * 4
        let space = CGColorSpace(name: CGColorSpace.sRGB)
        // One buffer for every round, as the canvas keeps one frame buffer.
        let buffer = FrameBuffer(byteCount: rowBytes * Int(size.height))
        return {
            var stacked = ground
            for i in 0..<10 {
                var placed = layer
                if i.isMultiple(of: 2) {
                    placed = placed.transformed(by: CGAffineTransform(rotationAngle: 0.2))
                }
                if i == 3 {
                    placed = placed.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 6])
                }
                placed = placed.transformed(by: CGAffineTransform(translationX: CGFloat(80 + i * 170),
                                                                  y: CGFloat(60 + (i % 4) * 230)))
                stacked = placed.composited(over: stacked)
            }
            probeContext.render(stacked.cropped(to: size), toBitmap: buffer.bytes, rowBytes: rowBytes,
                                bounds: size, format: .RGBA8, colorSpace: space)
        }
    }

    private final class FrameBuffer {
        let bytes: UnsafeMutableRawPointer
        init(byteCount: Int) { bytes = .allocate(byteCount: byteCount, alignment: 16) }
        deinit { bytes.deallocate() }
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

    /// The same gate as `check`, but with the yardstick taken back to back with
    /// the subject inside every round instead of once when the process started.
    ///
    /// Use this for anything whose reading moves with how busy the machine is
    /// rather than with what hardware it is — which, inside the full suite, is
    /// everything measured in single-digit milliseconds. `check` remains right
    /// for the big renderer budgets, where the subject already takes long
    /// enough to average the machine's mood out by itself.
    ///
    /// Returns the subject's own median, as read on this machine's clock, for
    /// a caller that prints a report of its own.
    @discardableResult
    static func checkInterleaved(_ label: String, baselineMS: Double,
                                 yardstick: Yardstick = .filterGraph,
                                 rounds: Int = 15,
                                 tolerance: Double = tolerance, slackMS: Double = jitterSlackMS,
                                 fileID: String = #fileID, filePath: String = #filePath,
                                 line: Int = #line, column: Int = #column,
                                 subject: () -> Void) -> Double {
        let reading = measureInterleaved(yardstick: yardstick, rounds: rounds, subject: subject)
        judge(label, reading, baselineMS: baselineMS, tolerance: tolerance, slackMS: slackMS,
              sourceLocation: SourceLocation(fileID: fileID, filePath: filePath,
                                             line: line, column: column))
        return reading.rawMS
    }

    /// One interleaved reading: the subject on the calibration machine's
    /// clock, its own median on this one, and the yardstick taken with it.
    struct Interleaved {
        let normalizedMS: Double
        let rawMS: Double
        let yardstickMS: Double
        let yardstick: Yardstick
        let rounds: Int
    }

    /// The measuring half of `checkInterleaved`, for a gate that reads several
    /// subjects and judges the dearest (`AnimatedChartRenderTests`).
    static func measureInterleaved(yardstick: Yardstick = .filterGraph, rounds: Int = 15,
                                   subject: () -> Void) -> Interleaved {
        let reference = round(for: yardstick)
        // Warm both, so neither pays for a pipeline the other gets for free.
        reference()
        subject()

        var subjectMS: [Double] = []
        var referenceMS: [Double] = []
        let clock = ContinuousClock()
        for _ in 0..<rounds {
            referenceMS.append(ms(clock.measure { reference() }))
            subjectMS.append(ms(clock.measure { subject() }))
        }
        return Interleaved(normalizedMS: normalizedMS(subject: subjectMS, reference: referenceMS,
                                                      referenceBaselineMS: yardstick.baselineMS),
                           rawMS: median(of: subjectMS) ?? .infinity,
                           yardstickMS: median(of: referenceMS) ?? .infinity,
                           yardstick: yardstick, rounds: rounds)
    }

    /// The judging half for a subject whose ratio to the yardstick is noisier
    /// than the subject itself: its own median on this clock, against a
    /// budget scaled by how much slower than its own number the yardstick
    /// read in the same rounds. Scaled, never tightened: on a machine where
    /// the yardstick reads under its baseline the bound is the baseline's.
    ///
    /// A punch-in composite is 3ms of GPU work beside a 2ms frame ruler, and
    /// in the stopwatch run their ratio read 4.3 to 5.6ms on unchanged code
    /// while the composite itself read 3.3 to 3.9; twice the composite read
    /// 6.2ms and, divided by a ruler the work beside it had slowed, only 6.9
    /// against a budget of 8.5 (2026-10-30).
    static func judgeScaled(_ label: String, _ reading: Interleaved, baselineMS: Double,
                            tolerance: Double, slackMS: Double = 0,
                            sourceLocation location: SourceLocation) {
        let factor = reading.yardstickMS / reading.yardstick.baselineMS
        let bound = budget(baselineMS: baselineMS, factor: factor, tolerance: tolerance, slackMS: slackMS)
        let message = String(format: "%@ — %.1fms here against a budget of %.1fms (baseline %.1fms x %.1f "
                             + "tolerance + %.0fms, x %.2f for a %@ yardstick reading %.1fms against "
                             + "its own %.1fms in the same %d rounds)",
                             label, reading.rawMS, bound, baselineMS, tolerance, slackMS, max(1, factor),
                             reading.yardstick.rawValue, reading.yardstickMS,
                             reading.yardstick.baselineMS, reading.rounds)
        print("[perf] budget: \(message)")
        guard isGating else { return }
        switch self.reading(normalizedMS: reading.rawMS, boundMS: bound, yardstickMS: reading.yardstickMS,
                            yardstickBaselineMS: reading.yardstick.baselineMS) {
        case .withinBudget:
            return
        case .overBudget:
            Issue.record(Comment(rawValue: "\(label) regressed: \(message)"), sourceLocation: location)
        case .untrusted:
            print("[perf] not judged: \(label), the machine was too busy: \(message)")
            withKnownIssue("\(label) could not be measured: the machine was too busy",
                           sourceLocation: location) {
                Issue.record(Comment(rawValue: "\(label) over budget on a machine too busy to judge it: \(message)"),
                             sourceLocation: location)
            }
        }
    }

    /// The judging half: inside the budget passes, over it fails, and over it
    /// beside a yardstick too far off its own number to mean anything is said
    /// out loud as a known issue.
    static func judge(_ label: String, _ reading: Interleaved, baselineMS: Double,
                      tolerance: Double = tolerance, slackMS: Double = jitterSlackMS,
                      sourceLocation location: SourceLocation) {
        let bound = budget(baselineMS: baselineMS, factor: 1, tolerance: tolerance, slackMS: slackMS)
        let yardstick = reading.yardstick
        let message = String(format: "%@ — %.1fms on the calibration machine's clock against a "
                             + "budget of %.1fms (baseline %.1fms x %.1f tolerance + %.0fms). "
                             + "Read %.1fms here beside a %@ yardstick reading %.1fms "
                             + "against its own %.1fms, over %d interleaved rounds",
                             label, reading.normalizedMS, bound, baselineMS, tolerance, slackMS,
                             reading.rawMS, yardstick.rawValue, reading.yardstickMS,
                             yardstick.baselineMS, reading.rounds)
        print("[perf] budget: \(message)")
        guard isGating else { return }
        switch self.reading(normalizedMS: reading.normalizedMS, boundMS: bound,
                            yardstickMS: reading.yardstickMS,
                            yardstickBaselineMS: yardstick.baselineMS) {
        case .withinBudget:
            return
        case .overBudget:
            Issue.record(Comment(rawValue: "\(label) regressed: \(message)"),
                         sourceLocation: location)
        case .untrusted:
            // Said out loud, as a known issue, so the run reads "passed with a
            // known issue" rather than green or red: nothing was learned here.
            let why = String(format: "the %@ yardstick read %.1fms against its own %.1fms, so "
                             + "this machine was too busy for the reading to mean anything",
                             yardstick.rawValue, reading.yardstickMS, yardstick.baselineMS)
            print("[perf] not judged: \(label), \(why)")
            withKnownIssue("\(label) could not be measured: \(why)", sourceLocation: location) {
                Issue.record(Comment(rawValue: "\(label) over budget on a machine too busy "
                                     + "to judge it: \(message)"),
                             sourceLocation: location)
            }
        }
    }

    /// The interleaved gate over a run of frames, beside the 1080p frame
    /// yardstick. The warm-up draws frame 0 and round `n` draws frame `n`, 1
    /// through `frames`, so the subject plays forward through the moments a
    /// stopwatch loop would, and no round redraws the frame before it (which
    /// the renderer would hand back without drawing).
    ///
    /// Every frame budget goes through here rather than through `check`. A
    /// frame is a few milliseconds of GPU turnaround, and inside the full
    /// suite, or beside another session's test run, that turnaround is what
    /// gets taken away: on 2026-10-14 a second process keeping the GPU busy
    /// read a headline flipping up by letter at 149.5ms against a budget of
    /// 77ms, scaled by a machine factor taken at process start, on unchanged
    /// code. Five frame gates failed that way in one run.
    @discardableResult
    static func checkFrames(_ label: String, baselineMS: Double, frames: Int,
                            tolerance: Double = tolerance, slackMS: Double = jitterSlackMS,
                            fileID: String = #fileID, filePath: String = #filePath,
                            line: Int = #line, column: Int = #column,
                            draw: (Int) -> Void) -> Double {
        let reading = measureFrames(frames: frames, draw: draw)
        judge(label, reading, baselineMS: baselineMS, tolerance: tolerance, slackMS: slackMS,
              sourceLocation: SourceLocation(fileID: fileID, filePath: filePath,
                                             line: line, column: column))
        return reading.rawMS
    }

    /// The measuring half of `checkFrames`.
    static func measureFrames(frames: Int, draw: (Int) -> Void) -> Interleaved {
        var next = 0
        return measureInterleaved(yardstick: .frame, rounds: frames) {
            draw(next)
            next += 1
        }
    }

    /// A renderer for a frame gate to time: the app's renderer, on a Core
    /// Image context of its own. Every `DocumentRenderer()` draws through one
    /// context shared by the whole process, so inside the full suite a timed
    /// frame queues behind every other render suite drawing at that moment,
    /// which no ruler beside it can see. Run on their own at once, on a quiet
    /// machine, the frame gates read a 2.5D frame at 42.5ms and a headline
    /// flip at 41.8ms that cost 5.4ms and 7.6ms alone (2026-10-14).
    static func timedRenderer() -> DocumentRenderer {
        DocumentRenderer(privateContext: CIContext(options: [.cacheIntermediates: true]))
    }

    private static func ms(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000
            + Double(duration.components.attoseconds) / 1e15
    }
}
