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

    /// Median milliseconds per refresh over 29 moves of a scrub at `scale`.
    static func scrub(scale: CGFloat) throws -> Double {
        let movie = MovieRef(pixelSize: canvas, durationMS: 8000)
        var document = PhotonzDocument.recording(movie, name: "Take")
        for i in 0..<5 {
            let box = CGRect(x: 200 + i * 500, y: 300 + i * 250, width: 600, height: 400)
            document.addLayer(Layer(name: "Box \(i)", content: .annotation(AnnotationContent(
                shape: .rectangle, strokeWidth: 12, colorHex: "#FF3B30",
                start: box.origin, end: CGPoint(x: box.maxX, y: box.maxY))),
                frame: CGRect(origin: .zero, size: canvas)))
        }
        let store = ImageStore()
        // Frames read at the size a fitted Retina window shows them.
        let decoded = movie.decodePixelSize(shownScale: 0.47)
        var inHand = MovieFramesInHand()
        for frame in 0..<30 {
            let image = try #require(busyFrame(decoded, seed: frame * 7))
            store.register(image, as: movie.frameRef(atSourceMS: frame * MovieRef.frameStepMS))
            inHand.insert(movie: movie.id, frameIndex: frame)
        }
        let renderer = DocumentRenderer()
        func shown(_ frame: Int) -> PhotonzDocument {
            var drawn = document.drawn(atTimeMS: frame * MovieRef.frameStepMS, framesInHand: inHand)
            // The first box travels with the playhead, the way a keyed one does.
            drawn.updateLayer(id: document.layers[1].id) { $0.frame.origin.x = CGFloat(frame * 9) }
            guard scale < 1 else { return drawn }
            let size = CGSize(width: (canvas.width * scale).rounded(), height: (canvas.height * scale).rounded())
            drawn = drawn.magnified(by: scale)
            drawn.canvasSize = size
            return drawn
        }
        _ = renderer.renderInteractive(shown(0), store: store)
        var samples: [Double] = []
        for frame in 1..<30 {
            let document = shown(frame)
            let began = ContinuousClock.now
            _ = renderer.renderInteractive(document, store: store)
            let took = ContinuousClock.now - began
            samples.append(Double(took.components.attoseconds) / 1e15 + Double(took.components.seconds) * 1000)
        }
        return samples.sorted()[samples.count / 2]
    }

    @Test("At the size it is shown, a scrub refresh composites well inside a 60 hertz frame")
    func shownSizeIsInsideAFrame() throws {
        let full = try Self.scrub(scale: 1)
        let shownScale = CompositeScale.forShown(0.47)
        let shown = try Self.scrub(scale: shownScale)
        print(String(format: "[perf] scrub refresh, 3456x2234 + 5 graphics: full size %.1fms, "
                     + "at the shown size (%.3f) %.1fms", full, shownScale, shown))
        // Calibration machine, 2026-09-26: 17ms full size, 7.5ms shown.
        MachineSpeed.check("scrub refresh at the shown size", medianMS: shown, baselineMS: 7.5)
        #expect(shown < full)
    }
}
