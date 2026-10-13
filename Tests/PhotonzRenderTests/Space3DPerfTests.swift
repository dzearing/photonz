import CoreGraphics
import Foundation
import PhotonzCore
import PhotonzRender
import Testing

/// What a frame with layers turned in space costs
/// (`layers-can-turn-about-x-and-y-and-move-in-depth`, PERF): a 1080p frame,
/// ten layers, four of them tilted and one out of focus, inside a 60 hertz
/// frame.
///
/// A frame seen in space is drawn whole every time (`RenderDiff`), so this is
/// the canvas's worst case while something turns: the playhead moving through
/// a flip with every layer redrawn.
@Suite("2.5D: a turned frame draws inside a 60 hertz frame", .serialized)
struct Space3DPerfTests {

    static let canvas = CGSize(width: 1920, height: 1080)

    static func picture(_ size: CGSize, seed: Int) -> CGImage? {
        let w = Int(size.width), h = Int(size.height)
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        for i in 0..<30 {
            context.setFillColor(CGColor(red: CGFloat((i * 37 + seed) % 255) / 255,
                                         green: CGFloat((i * 91 + seed) % 255) / 255,
                                         blue: CGFloat((i * 13) % 255) / 255, alpha: 1))
            context.fill(CGRect(x: (i * 97 + seed) % w, y: (i * 53) % h, width: w / 4, height: h / 5))
        }
        return context.makeImage()
    }

    /// Ten layers: a full-frame picture, three more pictures, four boxes and
    /// two titles. Four turn in space, one sits far back out of focus.
    static func scene(store: ImageStore) throws -> (PhotonzDocument, [UUID]) {
        var layers: [Layer] = []
        let ground = try #require(picture(canvas, seed: 3))
        layers.append(Layer(name: "Ground", content: .image(store.register(ground)),
                            frame: CGRect(origin: .zero, size: canvas)))
        for i in 0..<3 {
            let size = CGSize(width: 640, height: 360)
            let image = try #require(picture(size, seed: 40 + i * 11))
            layers.append(Layer(name: "Shot \(i)", content: .image(store.register(image)),
                                frame: CGRect(x: 120 + i * 560, y: 120, width: 640, height: 360)))
        }
        for i in 0..<4 {
            layers.append(Layer(name: "Box \(i)", content: .annotation(AnnotationContent(
                shape: .rectangle, strokeWidth: 0, colorHex: "#3366FF", start: .zero,
                end: CGPoint(x: 300, y: 200), fillColorHex: "#3366FF")),
                frame: CGRect(x: 160 + i * 420, y: 600, width: 300, height: 200)))
        }
        for i in 0..<2 {
            var title = Layer(name: "Title \(i)",
                              content: .text(TextContent(string: "Ship it faster.", fontSize: 72,
                                                         colorHex: "#FFFFFF")),
                              frame: CGRect(x: 300 + i * 700, y: 860, width: 640, height: 100))
            title.style.shadows = [ShadowStyle(radius: 12)]
            layers.append(title)
        }
        // Four tilted: two shots, a box and a title.
        let tilted = [layers[1].id, layers[2].id, layers[5].id, layers[8].id]
        var document = PhotonzDocument(canvasSize: canvas, layers: layers)
        // One far back, out of focus.
        document.updateLayer(id: layers[3].id) { $0.turn3D = LayerTurn3D(depth: -600) }
        document.camera = SceneCamera(focus: CameraFocus(depth: 0, amount: 3))
        return (document, tilted)
    }

    @Test("1080p, ten layers, four tilted and one out of focus: a frame in under 16ms")
    func turnedFrameIsInsideAFrame() throws {
        let store = ImageStore()
        let (base, tilted) = try Self.scene(store: store)
        func at(_ step: Int) -> PhotonzDocument {
            var document = base
            for (n, id) in tilted.enumerated() {
                document.updateLayer(id: id) {
                    $0.turn3D = LayerTurn3D(rotationX: n.isMultiple(of: 2) ? 0 : Double(step % 40),
                                            rotationY: Double(step * 6 + n * 20))
                }
            }
            return document
        }
        let renderer = DocumentRenderer()
        // Warm the pipelines and the rasterizer caches.
        _ = renderer.renderInteractive(at(0), store: store)
        _ = renderer.renderInteractive(at(1), store: store)
        var samples: [Double] = []
        for step in 2..<32 {
            let document = at(step)
            let began = ContinuousClock.now
            _ = renderer.renderInteractive(document, store: store)
            let took = ContinuousClock.now - began
            samples.append(Double(took.components.seconds) * 1000 + Double(took.components.attoseconds) / 1e15)
        }
        samples.sort()
        let median = samples[samples.count / 2]
        let slowest = samples[samples.count - 1]
        // The same ten layers flat, every frame drawn whole, for comparison.
        var flat = base
        flat.camera = nil
        for layer in flat.layers { flat.updateLayer(id: layer.id) { $0.turn3D = nil } }
        var flatSamples: [Double] = []
        for step in 0..<30 {
            var document = flat
            document.updateLayer(id: tilted[0]) { $0.frame.origin.x = CGFloat(120 + step) }
            let fresh = DocumentRenderer()
            let began = ContinuousClock.now
            _ = fresh.renderInteractive(document, store: store)
            let took = ContinuousClock.now - began
            flatSamples.append(Double(took.components.seconds) * 1000 + Double(took.components.attoseconds) / 1e15)
        }
        flatSamples.sort()
        print(String(format: "[perf] 2.5D frame, 1920x1080, 10 layers (4 tilted, 1 out of focus): "
                     + "median %.1fms, slowest %.1fms over %d frames; the same layers flat, drawn whole: "
                     + "median %.1fms", median, slowest, samples.count, flatSamples[flatSamples.count / 2]))
        // Calibration machine, 2026-10-11: 5.6ms median, 8.4ms slowest.
        #expect(!MachineSpeed.isGating || median < 16)
        MachineSpeed.check("2.5D frame at 1080p", medianMS: median, baselineMS: 6)
    }
}
