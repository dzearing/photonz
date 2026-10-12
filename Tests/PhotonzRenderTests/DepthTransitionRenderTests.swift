import CoreGraphics
import Foundation
import PhotonzCore
import PhotonzRender
import Testing

/// Transitions and title words that turn in depth, as drawn (task
/// `3d-transitions-and-title-entrances-flip-cube-swi`).
///
/// The canvas and the export draw the same pictures (both photograph the
/// document drawn at a moment), a frame mid transition fits inside a 60 hertz
/// frame at 1080p, and a word swinging in by its own reveal is drawn turned.
@Suite("Turning in depth, as drawn", .serialized)
struct DepthTransitionRenderTests {

    static let canvas = CGSize(width: 1920, height: 1080)

    static func shot(_ store: ImageStore, seed: Int) throws -> Layer {
        let picture = try #require(Space3DPerfTests.picture(canvas, seed: seed))
        return Layer(name: "Shot \(seed)", content: .image(store.register(picture)),
                     frame: CGRect(origin: .zero, size: canvas))
    }

    /// Ten layers mid transition: a black ground, the transition's pictures
    /// (two, or three for a doorway), three boxes and two titles over them, and
    /// two inset pictures.
    static func scene(_ kind: ClipTransitionKind, progress: Double, store: ImageStore,
                      shots: (Layer, Layer), motionBlur: Bool = false) throws -> PhotonzDocument {
        let ground = Self.box(CGRect(origin: .zero, size: canvas), hex: "#000000", name: "Ground")
        var pictures = Layer.depthTransitionDrawn(kind, direction: .left, progress: progress,
                                                  outgoing: shots.0, incoming: shots.1)
        if motionBlur {
            // A smear the size a mid transition makes in one 180 degree
            // shutter: 32 places, the picture averaged over all of them.
            pictures = pictures.map { picture in
                var smeared = picture
                smeared.motionSmear = MotionSmear(samples: (0..<32).map {
                    CGAffineTransform(translationX: CGFloat($0) * 1.5, y: CGFloat($0) * 0.4)
                }, span: 48)
                return smeared
            }
        }
        var layers = [ground] + pictures
        for i in 0..<3 {
            layers.append(Self.box(CGRect(x: 160 + i * 520, y: 760, width: 300, height: 120),
                                           hex: "#3366FF", name: "Box \(i)"))
        }
        for i in 0..<2 {
            layers.append(Layer(name: "Title \(i)",
                                content: .text(TextContent(string: "Ship it faster.", fontSize: 72,
                                                           colorHex: "#FFFFFF")),
                                frame: CGRect(x: 300 + i * 700, y: 900, width: 640, height: 100)))
        }
        return PhotonzDocument(canvasSize: canvas, layers: layers)
    }

    static func box(_ frame: CGRect, hex: String, name: String) -> Layer {
        Layer(name: name,
              content: .annotation(AnnotationContent(shape: .rectangle, strokeWidth: 0, colorHex: hex,
                                                     start: .zero, end: CGPoint(x: frame.width, y: frame.height),
                                                     fillColorHex: hex)),
              frame: frame)
    }

    static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }

    @Test("The canvas and the export draw the same pictures mid transition", arguments: ClipTransitionKind.inDepth)
    func canvasMatchesExport(kind: ClipTransitionKind) throws {
        let store = ImageStore()
        let shots = (try Self.shot(store, seed: 3), try Self.shot(store, seed: 120))
        for progress in [0.25, 0.5, 0.75] {
            let document = try Self.scene(kind, progress: progress, store: store, shots: shots)
            #expect(document.isSeenInSpace)
            let exported = try #require(DocumentRenderer().render(document, store: store))
            let canvas = try #require(DocumentRenderer().renderInteractive(document, store: store))
            let a = TextRevealRenderTests.bytes(exported), b = TextRevealRenderTests.bytes(canvas)
            #expect(a.count == b.count)
            var off = 0
            for index in stride(from: 0, to: min(a.count, b.count), by: 4) where abs(Int(a[index]) - Int(b[index])) > 2 {
                off += 1
            }
            #expect(off < a.count / 4 / 100, "\(kind.title) at \(progress): \(off) pixels differ")
        }
    }

    @Test("Mid transition the frame is neither shot laid flat: something turned is on screen",
          arguments: ClipTransitionKind.inDepth)
    func midFrameIsTurned(kind: ClipTransitionKind) throws {
        let store = ImageStore()
        let shots = (try Self.shot(store, seed: 3), try Self.shot(store, seed: 120))
        let mid = try #require(DocumentRenderer().render(
            try Self.scene(kind, progress: kind == .flip ? 0.4 : 0.5, store: store, shots: shots), store: store))
        let flatA = try #require(DocumentRenderer().render(
            try Self.scene(kind, progress: 0, store: store, shots: shots), store: store))
        let flatB = try #require(DocumentRenderer().render(
            try Self.scene(kind, progress: 1, store: store, shots: shots), store: store))
        let m = TextRevealRenderTests.bytes(mid)
        for flat in [flatA, flatB] {
            let f = TextRevealRenderTests.bytes(flat)
            var differ = 0
            for index in stride(from: 0, to: m.count, by: 16) where abs(Int(m[index]) - Int(f[index])) > 24 {
                differ += 1
            }
            #expect(differ > m.count / 16 / 10, "\(kind.title): only \(differ) samples differ from a flat shot")
        }
    }

    @Test("1080p, ten layers, mid transition in depth: a frame in under 16ms")
    func perf() throws {
        let store = ImageStore()
        let shots = (try Self.shot(store, seed: 3), try Self.shot(store, seed: 120))
        let renderer = DocumentRenderer()
        var lines: [String] = []
        var worstMedian = 0.0
        for kind in ClipTransitionKind.inDepth {
            for blurred in [false, true] {
                _ = renderer.renderInteractive(try Self.scene(kind, progress: 0.1, store: store, shots: shots,
                                                              motionBlur: blurred), store: store)
                var samples: [Double] = []
                for step in 1..<21 {
                    let document = try Self.scene(kind, progress: Double(step) / 21, store: store, shots: shots,
                                                  motionBlur: blurred)
                    let began = ContinuousClock.now
                    _ = renderer.renderInteractive(document, store: store)
                    samples.append(Self.milliseconds(ContinuousClock.now - began))
                }
                samples.sort()
                let median = samples[samples.count / 2], slowest = samples[samples.count - 1]
                lines.append(String(format: "%@%@: median %.1fms, slowest %.1fms", kind.title,
                                    blurred ? " with motion blur" : "", median, slowest))
                if !blurred { worstMedian = max(worstMedian, median) }
            }
        }
        print("[perf] transitions in depth, 1920x1080, 10 layers, 20 frames each:\n  "
              + lines.joined(separator: "\n  "))
        #expect(worstMedian < 16)
        MachineSpeed.check("transition in depth at 1080p", medianMS: worstMedian, baselineMS: 8)
    }

    // MARK: - Words

    @Test("Words swinging in by word are drawn turned mid reveal, and as the plain words once home")
    func wordsSwingIn() throws {
        var reveal = TextReveal(style: .swingIn, unit: .word, staggerMS: 120, lengthMS: 600)
        reveal.startMS = 0
        let box = CGRect(x: 120, y: 380, width: 1680, height: 140)
        let (doc, _) = TextRevealRenderTests.document(reveal, string: "One two three four", box: box)
        let (plainDoc, _) = TextRevealRenderTests.document(nil, string: "One two three four", box: box)
        let mid = try #require(TextRevealRenderTests.render(doc, atMS: 1_300))
        let plain = try #require(TextRevealRenderTests.render(plainDoc, atMS: 1_300))
        let inkMid = TextRevealRenderTests.ink(mid, in: box)
        let inkPlain = TextRevealRenderTests.ink(plain, in: box)
        // Turned away and still arriving, the words cover less than they do home.
        #expect(inkMid > 0 && inkMid < inkPlain * 9 / 10, "mid \(inkMid), plain \(inkPlain)")
        let home = try #require(TextRevealRenderTests.render(doc, atMS: 3_000))
        #expect(TextRevealRenderTests.bytes(home) == TextRevealRenderTests.bytes(plain))
    }
}
