import CoreGraphics
import Foundation
import ImageIO
import PhotonzCore
import PhotonzRender
import Testing

/// The measured bar of task `3d-transitions-ease-in-and-out-of-the-picture-in`,
/// read off the real renderer, frame by frame at 30 frames a second (the
/// export's rate), for every transition that turns in depth at its usual
/// length and curve:
///
/// - **(a) No slam.** The incoming shot's share of the frame starts at nought
///   and never grows by more than 15 per cent of the frame between two frames.
///   Measured with the outgoing shot solid red and the incoming solid green on
///   black, so the green in the frame IS the incoming shot, faded or not.
/// - **(b) No void.** No frame in the middle half of the move is more than a
///   quarter pure black (every channel under 10 of 255), with two pictures
///   that are nowhere black standing in for the shots.
/// - **(c) No hitch.** Each step from one frame to the next is the mean
///   absolute difference of the two, nought to one. A hitch is a frame where
///   the picture jumps instead of flowing (a step over 0.03 and more than
///   twice the mean of the steps either side of it) or stalls between two
///   frames that move (both steps either side over 0.03, and this one under a
///   quarter of the smaller). Measured against the frames beside it, not against the whole
///   move, because an eased move is fast in its middle and slow at its ends
///   and that is not a hitch. The same measure
///   `Scripts/depth-transition-measure.mjs` reads an exported reel with.
///
/// Before the task (2026-11-26, today's main), measured here: push in depth's
/// incoming shot jumped onto 0.33 of the frame in one frame, flip's middle was
/// 0.97 black, cube's 0.6 (`queue/audits/2026-11-26-3d-transitions-ease.json`
/// carries every number, before and after).
@Suite("3D transitions ease in and out of the picture, as drawn")
struct DepthTransitionEaseRenderTests {

    static let canvas = CGSize(width: 480, height: 270)
    static let fps = 30.0

    // MARK: - Stand-ins

    static func solid(_ red: Double, _ green: Double, _ store: ImageStore) throws -> Layer {
        let w = Int(canvas.width), h = Int(canvas.height)
        let context = try #require(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: red, green: green, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let image = try #require(context.makeImage())
        return Layer(name: red > 0 ? "Red" : "Green", content: .image(store.register(image)), frame: CGRect(origin: .zero, size: canvas))
    }

    /// A picture that is nowhere black: a gradient with a window on it.
    static func shot(_ seed: Int, _ store: ImageStore) throws -> Layer {
        let w = Int(canvas.width), h = Int(canvas.height)
        let context = try #require(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let a = seed == 0 ? [0.07, 0.56, 0.71] : [0.8, 0.42, 0.26]
        let b = seed == 0 ? [0.39, 0.25, 0.8] : [0.8, 0.26, 0.46]
        let gradient = try #require(CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                               colors: [CGColor(red: a[0], green: a[1], blue: a[2], alpha: 1),
                                                        CGColor(red: b[0], green: b[1], blue: b[2], alpha: 1)]
                                                   as CFArray, locations: [0, 1]))
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: w, y: h), options: [])
        context.setFillColor(CGColor(gray: 0.95, alpha: 1))
        context.fill(CGRect(x: 60, y: 40, width: 360, height: 190))
        for row in 0..<5 {
            context.setFillColor(row == 2 ? CGColor(red: b[0], green: b[1], blue: b[2], alpha: 1)
                                 : CGColor(gray: 0.7, alpha: 1))
            context.fill(CGRect(x: 80, y: 190 - row * 30, width: 220 + (row * 37) % 90, height: 12))
        }
        let image = try #require(context.makeImage())
        return Layer(name: "Shot \(seed)", content: .image(store.register(image)),
                     frame: CGRect(origin: .zero, size: canvas))
    }

    static func ground() -> Layer {
        Layer(name: "Ground", content: .annotation(AnnotationContent(
            shape: .rectangle, strokeWidth: 0, colorHex: "#000000", start: .zero,
            end: CGPoint(x: canvas.width, y: canvas.height), fillColorHex: "#000000")),
              frame: CGRect(origin: .zero, size: canvas))
    }

    /// Every frame of `kind` at its usual length, 30 a second, first to last:
    /// the pictures a cut between two full-frame shots draws, as the document
    /// draws them.
    ///
    /// `backdrop` false leaves out what fills the space the move opens, so
    /// only the shots themselves are measured.
    static func frames(_ kind: ClipTransitionKind, _ a: Layer, _ b: Layer, backdrop: Bool = true,
                       store: ImageStore) throws -> [[UInt8]] {
        let transition = ClipTransition(kind: kind)
        let count = Int((Double(transition.lengthMS) / 1000 * fps).rounded())
        return try (0...count).map { frame in
            let p = transition.curve.value(at: Double(frame) / Double(count))
            let drawn = Layer.depthTransitionDrawn(kind, direction: transition.direction, progress: p,
                                                   outgoing: a, incoming: b, canvas: backdrop ? canvas : nil)
            let document = PhotonzDocument(canvasSize: canvas, layers: [ground()] + drawn)
            return TextRevealRenderTests.bytes(try #require(DocumentRenderer().render(document, store: store)))
        }
    }

    /// How much of the frame is green: the incoming shot's share.
    static func green(_ pixels: [UInt8]) -> Double {
        var sum = 0.0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            sum += max(0, Double(pixels[index + 1]) - Double(pixels[index])) / 255
        }
        return sum / Double(pixels.count / 4)
    }

    static func black(_ pixels: [UInt8]) -> Double {
        var count = 0
        for index in stride(from: 0, to: pixels.count, by: 4)
        where pixels[index] < 10 && pixels[index + 1] < 10 && pixels[index + 2] < 10 {
            count += 1
        }
        return Double(count) / Double(pixels.count / 4)
    }

    static func step(_ a: [UInt8], _ b: [UInt8]) -> Double {
        var sum = 0
        for index in a.indices where index % 4 != 3 { sum += abs(Int(a[index]) - Int(b[index])) }
        return Double(sum) / Double(a.count / 4 * 3) / 255
    }

    /// The frames where the picture jumps or stalls against the frames beside it.
    static func hitches(_ steps: [Double]) -> Int {
        guard steps.count >= 3 else { return 0 }
        var count = 0
        for index in 1..<(steps.count - 1) {
            let beside = (steps[index - 1] + steps[index + 1]) / 2
            if steps[index] > 0.03 && steps[index] > 2 * beside { count += 1 }
            let either = min(steps[index - 1], steps[index + 1])
            if either > 0.03 && steps[index] < either / 4 { count += 1 }
        }
        return count
    }

    struct Numbers {
        var coverage: [Double]
        var biggestJump: Double
        var middleBlack: Double
        var steps: [Double]
        var hitches: Int
    }

    static func numbers(_ kind: ClipTransitionKind, store: ImageStore) throws -> Numbers {
        let solids = try frames(kind, solid(1, 0, store), solid(0, 1, store), backdrop: false, store: store)
        let coverage = solids.map(green)
        let jumps = zip(coverage, coverage.dropFirst()).map { $1 - $0 }
        let pictures = try frames(kind, shot(0, store), shot(1, store), store: store)
        let blacks = pictures.map(black)
        let middle = blacks[(blacks.count / 4)...(blacks.count * 3 / 4)]
        let steps = zip(pictures, pictures.dropFirst()).map { step($0, $1) }
        return Numbers(coverage: coverage, biggestJump: jumps.max() ?? 0, middleBlack: middle.max() ?? 0,
                       steps: steps, hitches: hitches(steps))
    }

    // MARK: - The bar

    @Test("The incoming shot comes on smoothly from nothing: no frame takes more than 15 per cent of the picture",
          arguments: ClipTransitionKind.inDepth)
    func noSlam(kind: ClipTransitionKind) throws {
        let n = try Self.numbers(kind, store: ImageStore())
        #expect(n.coverage[0] < 0.01, "\(kind.title) starts with \(n.coverage[0]) of the incoming shot")
        #expect(n.biggestJump <= 0.15, "\(kind.title) jumps by \(n.biggestJump): \(n.coverage.map { ($0 * 100).rounded() })")
        #expect((n.coverage.last ?? 0) > 0.95, "\(kind.title) ends on \(n.coverage.last ?? 0) of the incoming shot")
    }

    @Test("What a move opens up is never a void: the middle half is never more than a quarter black",
          arguments: ClipTransitionKind.inDepth)
    func noVoid(kind: ClipTransitionKind) throws {
        let n = try Self.numbers(kind, store: ImageStore())
        #expect(n.middleBlack <= 0.25, "\(kind.title): \(n.middleBlack) of a middle frame is black")
    }

    @Test("Frame to frame the picture flows: no hitch", arguments: ClipTransitionKind.inDepth)
    func noHitch(kind: ClipTransitionKind) throws {
        let n = try Self.numbers(kind, store: ImageStore())
        #expect(n.hitches == 0, "\(kind.title): steps \(n.steps.map { ($0 * 1000).rounded() / 1000 })")
    }

    @Test("Out of a black title page the incoming shot flows in too: no hitch where the page's own move is unseen",
          arguments: ClipTransitionKind.inDepth)
    func noHitchOutOfBlack(kind: ClipTransitionKind) throws {
        let store = ImageStore()
        let pictures = try Self.frames(kind, Self.solid(0, 0, store), Self.shot(1, store), store: store)
        let steps = zip(pictures, pictures.dropFirst()).map { Self.step($0, $1) }
        #expect(Self.hitches(steps) == 0, "\(kind.title): steps \(steps.map { ($0 * 1000).rounded() / 1000 })")
    }

    /// Every frame of every kind as PNGs, solids and pictures, when
    /// `PHOTONZ_DEPTH_FRAMES` names a folder: for looking, not for the suite.
    @Test("The frames, for looking", .enabled(if: ProcessInfo.processInfo.environment["PHOTONZ_DEPTH_FRAMES"] != nil))
    func writeFrames() throws {
        let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["PHOTONZ_DEPTH_FRAMES"] ?? "/tmp")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = ImageStore()
        for kind in ClipTransitionKind.inDepth {
            let transition = ClipTransition(kind: kind)
            let count = Int((Double(transition.lengthMS) / 1000 * Self.fps).rounded())
            for (set, pair, backdrop) in [("solid", (try Self.solid(1, 0, store), try Self.solid(0, 1, store)), false),
                                          ("shot", (try Self.shot(0, store), try Self.shot(1, store)), true)] {
                for frame in 0...count {
                    let p = transition.curve.value(at: Double(frame) / Double(count))
                    let drawn = Layer.depthTransitionDrawn(kind, direction: transition.direction, progress: p,
                                                           outgoing: pair.0, incoming: pair.1,
                                                           canvas: backdrop ? Self.canvas : nil)
                    let document = PhotonzDocument(canvasSize: Self.canvas, layers: [Self.ground()] + drawn)
                    let image = try #require(DocumentRenderer().render(document, store: store))
                    let url = folder.appendingPathComponent(String(format: "%@-%@-%02d.png", kind.rawValue, set, frame))
                    let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
                    CGImageDestinationAddImage(destination, image, nil)
                    #expect(CGImageDestinationFinalize(destination))
                }
            }
        }
    }

    /// The numbers the audit carries, printed for it.
    @Test("The numbers, for the audit")
    func printNumbers() throws {
        let store = ImageStore()
        var rows: [String] = []
        for kind in ClipTransitionKind.inDepth {
            let n = try Self.numbers(kind, store: store)
            rows.append("  steps " + n.steps.map { String(format: "%.3f", $0) }.joined(separator: " "))
            rows.append("  cover " + n.coverage.map { String(format: "%.2f", $0) }.joined(separator: " "))
            rows.append(String(format: "%@: biggest jump %.3f, middle black %.3f, biggest step %.3f, hitches %d",
                               kind.rawValue, n.biggestJump, n.middleBlack, n.steps.max() ?? 0, n.hitches))
        }
        print("[depth-numbers]\n  " + rows.joined(separator: "\n  "))
    }
}
