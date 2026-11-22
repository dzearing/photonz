import CoreGraphics
import Foundation
import PhotonzCore
import PhotonzRender
import Testing

/// What one refresh of a scrub costs the composite, on a full-screen Retina
/// recording with five graphics over it
/// (`scrubbing-is-smooth-never-goes-black-and-the-pic`).
///
/// Before: every refresh composited all 3456x2234 pixels, 17ms a picture on the
/// calibration machine, and the picture trailed the hand by one or two display
/// frames. After (7.5ms): it is composited at the size it is shown (`CompositeScale`),
/// half its pixels each way fitted in a 1440 point window on a Retina screen.
@Suite("A scrub refresh composites inside a frame", .serialized)
struct ScrubCompositePerfTests {

    static let canvas = CGSize(width: 3456, height: 2234)

    static func busyFrame(_ size: CGSize, seed: Int) -> CGImage? {
        let w = Int(size.width), h = Int(size.height)
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        for i in 0..<40 {
            context.setFillColor(CGColor(red: CGFloat((i * 37 + seed) % 255) / 255,
                                         green: CGFloat((i * 91 + seed) % 255) / 255,
                                         blue: CGFloat((i * 13) % 255) / 255, alpha: 1))
            context.fill(CGRect(x: (i * 97 + seed) % w, y: (i * 53) % h, width: w / 5, height: h / 6))
        }
        return context.makeImage()
    }

    /// The recording with five graphics over it, its frames in hand at the
    /// size a fitted Retina window reads them.
    struct Scene {
        let document: PhotonzDocument
        let store: ImageStore
        let inHand: MovieFramesInHand

        init() throws {
            let movie = MovieRef(pixelSize: ScrubCompositePerfTests.canvas, durationMS: 8000)
            var document = PhotonzDocument.recording(movie, name: "Take")
            for i in 0..<5 {
                let box = CGRect(x: 200 + i * 500, y: 300 + i * 250, width: 600, height: 400)
                document.addLayer(Layer(name: "Box \(i)", content: .annotation(AnnotationContent(
                    shape: .rectangle, strokeWidth: 12, colorHex: "#FF3B30",
                    start: box.origin, end: CGPoint(x: box.maxX, y: box.maxY))),
                    frame: CGRect(origin: .zero, size: ScrubCompositePerfTests.canvas)))
            }
            let store = ImageStore()
            // Frames read at the size a fitted Retina window shows them.
            let decoded = movie.decodePixelSize(shownScale: 0.47)
            var inHand = MovieFramesInHand()
            for frame in 0..<30 {
                let image = try #require(ScrubCompositePerfTests.busyFrame(decoded, seed: frame * 7))
                store.register(image, as: movie.frameRef(atFrame: frame))
                inHand.insert(movie: movie.id, frameIndex: frame)
            }
            self.document = document
            self.store = store
            self.inHand = inHand
        }

        /// What one refresh of the scrub at `frame` composites, at `scale`.
        func shown(_ frame: Int, scale: CGFloat) -> PhotonzDocument {
            var drawn = document.drawn(atTimeMS: MovieRef.gridMS(ofFrame: frame), framesInHand: inHand)
            // The first box travels with the playhead, the way a keyed one does.
            drawn.updateLayer(id: document.layers[1].id) { $0.frame.origin.x = CGFloat(frame * 9) }
            guard scale < 1 else { return drawn }
            let canvas = ScrubCompositePerfTests.canvas
            let size = CGSize(width: (canvas.width * scale).rounded(), height: (canvas.height * scale).rounded())
            drawn = drawn.magnified(by: scale)
            drawn.canvasSize = size
            return drawn
        }
    }

    static func ms(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }

    /// Both sizes are read in the SAME rounds, beside the same 1080p frame
    /// ruler, and compared round by round. Until 2026-11-19 the full size was
    /// a plain median taken first and the shown size a gated median taken
    /// after it, a minute apart; on a CI runner three times slower than the
    /// calibration machine and swinging, the shown size read 58.8ms against
    /// a full size of 48.7ms on unchanged code and main went red. Drawn back
    /// to back, whatever the machine is doing slows both alike, and the order
    /// alternates so neither always pays for the other's leftovers.
    @Test("At the size it is shown, a scrub refresh composites well inside a 60 hertz frame")
    func shownSizeIsInsideAFrame() throws {
        let scene = try Scene()
        let shownScale = CompositeScale.forShown(0.47)
        let fullFrames = (0..<30).map { scene.shown($0, scale: 1) }
        let shownFrames = (0..<30).map { scene.shown($0, scale: shownScale) }
        // One renderer each, so neither hands back the other's last picture.
        let fullRenderer = MachineSpeed.timedRenderer()
        let shownRenderer = MachineSpeed.timedRenderer()
        let ruler = MachineSpeed.round(for: .frame)
        // Warm all three, so none pays for a pipeline the others get for free.
        ruler()
        _ = fullRenderer.renderInteractive(fullFrames[0], store: scene.store)
        _ = shownRenderer.renderInteractive(shownFrames[0], store: scene.store)

        let clock = ContinuousClock()
        var rulerMS: [Double] = [], fullMS: [Double] = [], shownMS: [Double] = []
        for frame in 1..<30 {
            rulerMS.append(Self.ms(clock.measure { ruler() }))
            let full = { fullMS.append(Self.ms(clock.measure {
                _ = fullRenderer.renderInteractive(fullFrames[frame], store: scene.store) })) }
            let shown = { shownMS.append(Self.ms(clock.measure {
                _ = shownRenderer.renderInteractive(shownFrames[frame], store: scene.store) })) }
            if frame.isMultiple(of: 2) { full(); shown() } else { shown(); full() }
        }

        // Calibration machine, 2026-09-26: 17ms full size, 7.5ms shown. The
        // gate is the shared frame gate, each frame read beside a fixed 1080p
        // frame of Core Image work: a budget scaled once at process start
        // failed at 80.1ms against 74ms with another process drawing beside
        // this one (2026-10-14).
        let yardstick = MachineSpeed.Yardstick.frame
        let reading = MachineSpeed.Interleaved(
            normalizedMS: MachineSpeed.normalizedMS(subject: shownMS, reference: rulerMS,
                                                    referenceBaselineMS: yardstick.baselineMS),
            rawMS: MachineSpeed.median(of: shownMS) ?? .infinity,
            yardstickMS: MachineSpeed.median(of: rulerMS) ?? .infinity,
            yardstick: yardstick, rounds: shownMS.count)
        MachineSpeed.judge("scrub refresh at the shown size", reading, baselineMS: 7.5,
                           sourceLocation: #_sourceLocation)

        // Each round's shown picture against the full one drawn beside it.
        let ratios = zip(shownMS, fullMS).filter { $0.1 > 0 }.map { $0.0 / $0.1 }
        let ratio = MachineSpeed.median(of: ratios) ?? .infinity
        print(String(format: "[perf] scrub refresh, 3456x2234 + 5 graphics, %d interleaved rounds: "
                     + "full size %.1fms, at the shown size (%.3f) %.1fms, shown/full per round %.2f "
                     + "(calibration 0.44)", shownMS.count, MachineSpeed.median(of: fullMS) ?? .infinity,
                     shownScale, reading.rawMS, ratio))
        #expect(ratio < 1, "at the shown size a scrub refresh should cost less than at full size, drawn beside it")
    }
}
