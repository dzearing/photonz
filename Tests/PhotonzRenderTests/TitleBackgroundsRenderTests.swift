import CoreGraphics
import CoreImage
import Foundation
import PhotonzCore
@testable import PhotonzRender
import Testing

/// Title backgrounds move, as drawn (task
/// `title-backgrounds-move-gradients-grain-and-the-r`).
///
/// A drifting mesh is a different picture a moment later and the same picture
/// at the same moment; grain sits on what a layer paints and nowhere else,
/// averaging to nothing; glass zooms what is behind it and, keyed down to
/// nothing, is exactly the picture under it; a trimmed line draws only the part
/// it keeps. And a whole title page with all of it stays inside a frame.
@Suite("Title backgrounds move, as drawn", .serialized)
struct TitleBackgroundsRenderTests {

    static let canvas = CGSize(width: 1920, height: 1080)

    static let aurora = Paint(hex: "#0E1030", kind: .mesh,
                              stops: [GradientStop(hex: "#0E1030", position: 0),
                                      GradientStop(hex: "#3A1F8F", position: 0.5),
                                      GradientStop(hex: "#8C2B6B", position: 1)],
                              angle: 200, drift: 40)

    static func box(_ fill: Paint, _ rect: CGRect = CGRect(origin: .zero, size: canvas)) -> Layer {
        var content = AnnotationContent(shape: .rectangle, strokeWidth: 0, colorHex: fill.hex,
                                        start: .zero, end: CGPoint(x: rect.width, y: rect.height))
        content.fill = fill
        return Layer(name: "Box", content: .annotation(content), frame: rect)
    }

    static func timed(_ layers: [Layer], lengthMS: Int = 8000) -> PhotonzDocument {
        var doc = PhotonzDocument(canvasSize: canvas)
        doc.layers = layers.map { layer in
            var timed = layer
            if timed.time == nil { timed.time = LayerTime(inMS: 0, outMS: lengthMS, sourceInMS: 0) }
            return timed
        }
        doc.durationMS = lengthMS
        return doc
    }

    static func render(_ doc: PhotonzDocument, atMS ms: Int, store: ImageStore = ImageStore(),
                       renderer: DocumentRenderer = DocumentRenderer()) -> CGImage? {
        renderer.render(doc.drawn(atTimeMS: ms), store: store)
    }

    static func bytes(_ image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        data.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                          bytesPerRow: w * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return data
    }

    /// The colour at a point given top-left.
    static func pixel(_ data: [UInt8], width: Int, x: Int, y: Int) -> (Int, Int, Int, Int) {
        let i = (y * width + x) * 4
        return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]), Int(data[i + 3]))
    }

    /// Mean and spread of the red channel over a patch, top-left given.
    static func stats(_ data: [UInt8], width: Int, _ rect: CGRect) -> (mean: Double, spread: Double) {
        var values: [Double] = []
        for y in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<Int(rect.maxX) {
                values.append(Double(data[(y * width + x) * 4]))
            }
        }
        let mean = values.reduce(0, +) / Double(max(values.count, 1))
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(max(values.count, 1))
        return (mean, variance.squareRoot())
    }

    static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }

    // MARK: - Mesh

    @Test("A drifting mesh is the mesh: its colour points, blended, and a different picture a moment later")
    func meshDrifts() throws {
        let doc = Self.timed([Self.box(Self.aurora)])
        let renderer = DocumentRenderer()
        let a = try #require(Self.render(doc, atMS: 0, renderer: renderer))
        let again = try #require(Self.render(doc, atMS: 0, renderer: renderer))
        let later = try #require(Self.render(doc, atMS: 5000, renderer: renderer))
        let da = Self.bytes(a), db = Self.bytes(again), dl = Self.bytes(later)
        // The same moment is the same picture, every time it is drawn.
        let same = da == db, moved = da != dl
        #expect(same)
        #expect(moved)
        // Near each colour point, nearest that point's colour.
        for point in Self.aurora.meshPoints(atMS: 0) {
            let x = Int(point.center.x * Self.canvas.width), y = Int(point.center.y * Self.canvas.height)
            guard x >= 0, y >= 0, x < a.width, y < a.height else { continue }
            let (r, g, b, alpha) = Self.pixel(da, width: a.width, x: x, y: y)
            #expect(alpha == 255)
            let want = point.color
            let mine = abs(Double(r) / 255 - want.r) + abs(Double(g) / 255 - want.g) + abs(Double(b) / 255 - want.b)
            for other in Self.aurora.meshPoints(atMS: 0) where other.color != want {
                let theirs = abs(Double(r) / 255 - other.color.r) + abs(Double(g) / 255 - other.color.g)
                    + abs(Double(b) / 255 - other.color.b)
                #expect(mine < theirs)
            }
        }
    }

    @Test("A still mesh, or one drawn with no clock, is the picture the shape's own raster paints")
    func stillMeshMatchesTheRaster() throws {
        var still = Self.aurora
        still.drift = 0
        let box = Self.box(still, CGRect(x: 100, y: 100, width: 640, height: 360))
        let drawn = try #require(Self.render(Self.timed([box]), atMS: 0))
        var moving = Self.box(Self.aurora, CGRect(x: 100, y: 100, width: 640, height: 360))
        moving.drawnAtMS = 0
        // The live path and the cached still path draw the same blend.
        let live = try #require(DocumentRenderer().render(
            PhotonzDocument(canvasSize: Self.canvas, layers: [moving]), store: ImageStore()))
        let a = Self.bytes(drawn), b = Self.bytes(live)
        var worst = 0
        for y in stride(from: 110, to: 450, by: 20) {
            for x in stride(from: 110, to: 730, by: 20) {
                let p = Self.pixel(a, width: drawn.width, x: x, y: y)
                let q = Self.pixel(b, width: live.width, x: x, y: y)
                worst = max(worst, abs(p.0 - q.0), abs(p.1 - q.1), abs(p.2 - q.2))
            }
        }
        #expect(worst <= 3, "still and live mesh differ by \(worst) levels")
        // Only inside the box.
        #expect(Self.pixel(b, width: live.width, x: 50, y: 50).3 == 0)
    }

    // MARK: - Grain

    @Test("Grain sits on what the layer paints: a spread of values about the same colour, a new one each frame")
    func grainOnTheLayerOnly() throws {
        var grainy = Self.box(Paint(hex: "#30364A"), CGRect(x: 0, y: 0, width: 960, height: 1080))
        grainy.style.effects = [.grain(GrainEffect())]
        let plain = Self.box(Paint(hex: "#30364A"), CGRect(x: 960, y: 0, width: 960, height: 1080))
        let doc = Self.timed([grainy, plain])
        let now = try #require(Self.render(doc, atMS: 1000))
        let next = try #require(Self.render(doc, atMS: 1000 + GrainFilter.frameMS))
        let same = try #require(Self.render(doc, atMS: 1000))
        let data = Self.bytes(now)
        let withGrain = Self.stats(data, width: now.width, CGRect(x: 200, y: 200, width: 200, height: 200))
        let without = Self.stats(data, width: now.width, CGRect(x: 1400, y: 200, width: 200, height: 200))
        #expect(without.spread < 0.01)
        #expect(withGrain.spread > 1.5, "grain spread \(withGrain.spread)")
        // Neither lighter nor darker on average.
        #expect(abs(withGrain.mean - without.mean) < 1.5, "grain moved the mean \(withGrain.mean) vs \(without.mean)")
        // A fresh pattern on the next frame; the same one at the same moment.
        let fresh = Self.bytes(next) != data, repeatable = Self.bytes(same) == data
        #expect(fresh)
        #expect(repeatable)
        // Nothing where the layer is not.
        var cut = grainy
        cut.frame = CGRect(x: 0, y: 0, width: 400, height: 400)
        let alone = try #require(Self.render(Self.timed([cut]), atMS: 1000))
        #expect(Self.pixel(Self.bytes(alone), width: alone.width, x: 800, y: 800).3 == 0)
    }

    // MARK: - Glass

    /// A picture with sharp stripes, as a recording under a title would be.
    static func stripes(store: ImageStore) -> Layer {
        let w = Int(canvas.width), h = Int(canvas.height)
        var pixels = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w where (x / 40) % 2 == 0 {
                let i = (y * w + x) * 4
                pixels[i] = 20; pixels[i + 1] = 120; pixels[i + 2] = 220
            }
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)
        let image = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: provider!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let ref = store.register(image)
        return Layer(name: "Recording", content: .image(ref), frame: CGRect(origin: .zero, size: canvas))
    }

    @Test("Glass zooms what is behind it, and keyed down to nothing it is the picture under it")
    func glassZoomsAndClears() throws {
        let store = ImageStore()
        let picture = Self.stripes(store: store)
        var glass = Self.box(Paint(hex: "#000000"))
        glass.style.opacity = 0.4
        glass.style.effects = [.blur(BlurEffect(radius: 6, kind: .background))]
        let flat = try #require(Self.render(Self.timed([picture, glass]), atMS: 0, store: store))
        glass.style.effects = [.blur(BlurEffect(radius: 6, kind: .background, zoom: 120))]
        let zoomed = try #require(Self.render(Self.timed([picture, glass]), atMS: 0, store: store))
        let zoomChanged = Self.bytes(flat) != Self.bytes(zoomed)
        #expect(zoomChanged)
        // In the middle the zoom has spread the stripes wider: the run of
        // one colour across the centre is longer.
        func run(_ image: CGImage) -> Int {
            let data = Self.bytes(image)
            let y = image.height / 2
            var longest = 0, current = 0
            var last = -1
            for x in 0..<image.width {
                let r = Self.pixel(data, width: image.width, x: x, y: y).0
                let dark = r < 60 ? 1 : 0
                current = dark == last ? current + 1 : 1
                last = dark
                longest = max(longest, current)
            }
            return longest
        }
        #expect(run(zoomed) > run(flat))
        // Cleared: no blur and no dim leaves the footage exactly.
        glass.style.opacity = 0
        glass.style.effects = [.blur(BlurEffect(radius: 0, kind: .background, zoom: 100))]
        let clear = try #require(Self.render(Self.timed([picture, glass]), atMS: 0, store: store))
        let bare = try #require(Self.render(Self.timed([picture]), atMS: 0, store: store))
        let cleared = Self.bytes(clear) == Self.bytes(bare)
        #expect(cleared)
        // Nearly cleared is nearly the footage: no richer copy of it that
        // snaps back the frame the blur reaches nought.
        glass.style.effects = [.blur(BlurEffect(radius: 0.02, kind: .background, zoom: 100))]
        let almost = try #require(Self.render(Self.timed([picture, glass]), atMS: 0, store: store))
        let a = Self.bytes(almost), b = Self.bytes(bare)
        // Read inside the stripes, where a blur this small changes nothing
        // and only a jump in colour would show.
        var worst = 0
        for y in stride(from: 100, to: almost.height - 100, by: 97) {
            for x in stride(from: 20, to: almost.width - 40, by: 40) {
                for channel in 0..<3 {
                    let i = (y * almost.width + x) * 4 + channel
                    worst = max(worst, abs(Int(a[i]) - Int(b[i])))
                }
            }
        }
        #expect(worst <= 4, "nearly cleared glass differs by \(worst)")
    }

    // MARK: - Trim

    @Test("A trimmed line draws only the part it keeps, and an arrow's head waits for its shaft")
    func trimmedLine() throws {
        func line(_ shape: AnnotationShape, trim: StrokeTrim?) -> Layer {
            var content = AnnotationContent(shape: shape, strokeWidth: 8, colorHex: "#FFFFFF",
                                            start: CGPoint(x: 4, y: 20), end: CGPoint(x: 804, y: 20))
            content.trim = trim
            return Layer(name: "Rule", content: .annotation(content), frame: CGRect(x: 100, y: 500, width: 808, height: 40))
        }
        func ink(_ layer: Layer, from: Int, to: Int) throws -> Int {
            let image = try #require(DocumentRenderer().render(
                PhotonzDocument(canvasSize: Self.canvas, layers: [layer]), store: ImageStore()))
            let data = Self.bytes(image)
            var count = 0
            for x in from..<to where Self.pixel(data, width: image.width, x: x, y: 520).3 > 128 { count += 1 }
            return count
        }
        let half = line(.line, trim: StrokeTrim(start: 0, end: 0.5))
        #expect(try ink(half, from: 120, to: 480) > 300)
        #expect(try ink(half, from: 560, to: 900) == 0)
        let whole = line(.line, trim: nil)
        #expect(try ink(whole, from: 560, to: 900) > 300)
        let nothing = line(.line, trim: StrokeTrim(start: 0, end: 0))
        #expect(try ink(nothing, from: 100, to: 910) == 0)
        // An arrow most of the way drawn has no head yet; drawn on, it does.
        let arrowing = line(.arrow, trim: StrokeTrim(start: 0, end: 0.9))
        #expect(try ink(arrowing, from: 860, to: 910) == 0)
        let arrived = line(.arrow, trim: nil)
        #expect(try ink(arrived, from: 860, to: 905) > 0)
    }

    // MARK: - Playback, scrub and export

    /// Playback runs every frame in order through one renderer; a scrub jumps
    /// about through another; an export makes a fresh one. All three agree on
    /// a drifting mesh with grain over it, and on glass over a picture.
    @Test("Playback, scrubbing and export draw the same Aurora and Behind Glass frames")
    func playbackScrubExportAgree() throws {
        let store = ImageStore()
        for preset in [BuiltInTitle.aurora, .glass] {
            var doc = Self.timed([Self.stripes(store: store)], lengthMS: 6000)
            let landed = doc.insertTitle(preset, atTimeMS: 0)
            _ = try #require(landed)
            let moments = [280, 1_600, 3_640]
            let playback = DocumentRenderer()
            var played: [Int: [UInt8]] = [:]
            for ms in stride(from: 0, through: 3_700, by: 40) {
                let image = try #require(Self.render(doc, atMS: ms, store: store, renderer: playback))
                if moments.contains(ms) { played[ms] = Self.bytes(image) }
            }
            let scrub = DocumentRenderer()
            for ms in moments.reversed() + [2_000, 120] {
                _ = Self.render(doc, atMS: ms, store: store, renderer: scrub)
            }
            for ms in moments {
                let scrubbed = try #require(Self.render(doc, atMS: ms, store: store, renderer: scrub))
                let exported = try #require(DocumentRenderer().render(doc.drawn(atTimeMS: ms), store: store,
                                                                     scale: 1))
                let scrubAgrees = played[ms] == Self.bytes(scrubbed)
                let exportAgrees = played[ms] == Self.bytes(exported)
                #expect(scrubAgrees, "\(preset.name): scrub differs at \(ms)")
                #expect(exportAgrees, "\(preset.name): export differs at \(ms)")
            }
        }
    }

    // MARK: - A whole page, inside a frame

    /// One frame of each new title page through the canvas's own render, at
    /// 1080p, over twenty frames of its hold. Printed for the perf note.
    @Test("Aurora and Behind Glass at 1080p each draw inside a frame")
    func pagesInsideAFrame() throws {
        let store = ImageStore()
        var report: [String] = []
        for preset in [BuiltInTitle.aurora, .glass] {
            var doc = Self.timed([Self.stripes(store: store)], lengthMS: 10_000)
            let landed = doc.insertTitle(preset, atTimeMS: 0)
            _ = try #require(landed)
            // A context of its own, so the reading is this page's cost and not
            // the queue of every other render suite running beside it.
            let renderer = DocumentRenderer(privateContext: CIContext(options: [.cacheIntermediates: true]))
            _ = renderer.renderInteractive(doc.drawn(atTimeMS: 1_000), store: store)
            var samples: [Double] = []
            for ms in stride(from: 1_016, to: 1_016 + 20 * 16, by: 16) {
                let shown = doc.drawn(atTimeMS: ms)
                let began = ContinuousClock.now
                _ = renderer.renderInteractive(shown, store: store)
                samples.append(Self.milliseconds(ContinuousClock.now - began))
            }
            let median = samples.sorted()[samples.count / 2]
            report.append(String(format: "%@: median %.1fms, worst %.1fms over %d frames",
                                 preset.name, median, samples.max() ?? 0, samples.count))
            // Measured alone at 8.9 to 10.4 ms (Aurora) and 4.7 to 5.5 ms
            // (Behind Glass) on 2026-10-10; inside the full suite the CPU half
            // of a drifting frame competes with every other suite, so the gate
            // is the shared one, scaled by how fast this machine is.
            let baseline = preset == .aurora ? 10.0 : 5.5
            let factor = MachineSpeed.factor(.filterGraph)
            if MachineSpeed.isGating {
                #expect(median < MachineSpeed.budget(baselineMS: baseline, factor: factor),
                        "\(preset.name) median \(median)ms")
            }
        }
        // The mesh grid on its own, the CPU part of a drifting frame.
        let began = ContinuousClock.now
        for ms in stride(from: 0, to: 20 * 16, by: 16) { _ = MeshPainter.image(Self.aurora, size: Self.canvas, atMS: ms) }
        let grid = Self.milliseconds(ContinuousClock.now - began) / 20
        report.append(String(format: "mesh grid alone: %.2fms a frame", grid))
        print("[perf] title backgrounds, 1920x1080:\n  " + report.joined(separator: "\n  "))
    }
}
